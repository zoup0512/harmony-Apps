import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    hilog.info(DOMAIN, 'CamMonitor', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'CamMonitor', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 监控看板保持屏幕常亮
    windowStage.getMainWindow().then((win) => {
      win.setWindowKeepScreenOn(true);
    });
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'CamMonitor', 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'CamMonitor', 'loadContent succeeded');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'CamMonitor', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'CamMonitor', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'CamMonitor', 'Ability onBackground');
  }
}
