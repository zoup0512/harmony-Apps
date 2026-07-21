import { appTasks } from '@ohos/hvigor-ohos-plugin';
import { hvigor } from '@ohos/hvigor';
import * as fs from 'fs';
import * as path from 'path';

/**
 * 按 product 动态改写 AppScope/app.json5 的 bundleName，使各模块能作为独立 app 共存于设备。
 *
 * 背景：多 entry 模块工程下，设备上同 bundleName 只能装一个 entry 模块，
 * 报错 install entry already exist。hvigor 的 product.bundleName 字段
 * 在当前版本的打包链路中不被采用，需要在构建前物理改写 AppScope/app.json5。
 *
 * 策略：
 *   1. 在 nodesEvaluated hook（product 参数已就绪）改写 AppScope/app.json5
 *   2. buildFinished hook 自动还原，保证 git 工作区干净
 *   3. default product 不改写，保持 com.razor.apps
 *
 * 注意：product 参数通过 hvigor.getParameter().getExtParam('product') 获取，
 * 而非 getProperty()。命令行 -p product=xxx 走 extParam 通道。
 */
const BUNDLE_NAME_MAP: Record<string, string> = {
  cams: 'com.razor.apps.cams',
  webvideocast: 'com.razor.apps.webvideocast',
  cammonitor: 'com.razor.apps.cammonitor',
  ipwebcam: 'com.razor.apps.ipwebcam',
  infuse: 'com.razor.apps.infuse',
  streamshow: 'com.razor.apps.streamshow',
  cameraviewer: 'com.razor.apps.cameraviewer'
};

const APP_JSON5 = path.join(__dirname, 'AppScope', 'app.json5');
const BUNDLE_NAME_RE = /("bundleName"\s*:\s*")([^"]*)(")/;

let appJson5Original: string | null = null;

function applyOverride(): void {
  if (appJson5Original !== null) {
    return;
  }
  const product = hvigor.getParameter().getExtParam('product') as string | undefined;
  if (!product || !(product in BUNDLE_NAME_MAP)) {
    return;
  }
  if (!fs.existsSync(APP_JSON5)) {
    return;
  }
  const target = BUNDLE_NAME_MAP[product];
  const original = fs.readFileSync(APP_JSON5, 'utf8');
  const match = original.match(BUNDLE_NAME_RE);
  if (!match || match[2] === target) {
    return;
  }
  appJson5Original = original;
  fs.writeFileSync(APP_JSON5, original.replace(BUNDLE_NAME_RE, `$1${target}$3`));
  console.log(`[bundleNameOverride] product=${product} -> bundleName=${target}`);
}

function restoreOverride(): void {
  if (appJson5Original === null) {
    return;
  }
  try {
    fs.writeFileSync(APP_JSON5, appJson5Original);
    console.log('[bundleNameOverride] AppScope/app.json5 restored');
  } catch (e) {
    console.error('[bundleNameOverride] restore failed:', e);
  }
  appJson5Original = null;
}

hvigor.nodesEvaluated(() => {
  applyOverride();
});

hvigor.buildFinished(() => {
  restoreOverride();
});

export default {
  system: appTasks,
  plugins: []
}
