import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PrefStore } from '../utils/PrefStore';

const DOMAIN = 0x0001;
const TAG = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onCreate');
    AppStorage.setOrCreate('currentColorMode', ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    AppStorage.setOrCreate('isAppForeground', true);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'onWindowStageCreate');
    this.applySavedThemeMode();
    windowStage.loadContent('pages/MainPage', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, `loadContent failed: ${JSON.stringify(err)}`);
        return;
      }
      hilog.info(DOMAIN, TAG, 'loadContent succeeded');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'onForeground');
    console.info('EntryAbility onForeground: setting isAppForeground=true');
    AppStorage.setOrCreate('isAppForeground', true);
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'onBackground');
    console.info('EntryAbility onBackground: setting isAppForeground=false');
    AppStorage.setOrCreate('isAppForeground', false);
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    hilog.info(DOMAIN, TAG, `onConfigurationUpdate: colorMode=${newConfig.colorMode}`);
    AppStorage.setOrCreate('currentColorMode', newConfig.colorMode);
  }

  private async applySavedThemeMode(): Promise<void> {
    try {
      const prefs = new PrefStore(this.context);
      const mode = await prefs.getString('appearance_theme_mode', 'light');
      const appContext = this.context.getApplicationContext();
      if (mode === 'system') {
        appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      } else if (mode === 'dark') {
        appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      } else {
        appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
      }
      hilog.info(DOMAIN, TAG, `applySavedThemeMode: ${mode}`);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `applySavedThemeMode failed: ${(e as Error).message}`);
    }
  }
}
