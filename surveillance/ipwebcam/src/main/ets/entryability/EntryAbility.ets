import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';

const DOMAIN = 0x0000;

const NEEDED: Permissions[] = ['ohos.permission.CAMERA', 'ohos.permission.MICROPHONE'];

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    hilog.info(DOMAIN, 'IPWebcam', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'IPWebcam', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 保持屏幕常亮，推流时更实用
    windowStage.getMainWindow().then((win) => {
      win.setWindowKeepScreenOn(true);
    });
    this.requestPermissions();
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'IPWebcam', 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'IPWebcam', 'loadContent succeeded');
    });
  }

  private async requestPermissions(): Promise<void> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      await atManager.requestPermissionsFromUser(this.context as common.UIAbilityContext, NEEDED);
    } catch (e) {
      hilog.error(DOMAIN, 'IPWebcam', 'requestPermissions error: %{public}s', JSON.stringify(e));
    }
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'IPWebcam', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'IPWebcam', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'IPWebcam', 'Ability onBackground');
  }
}
