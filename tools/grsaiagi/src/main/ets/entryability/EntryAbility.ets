import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { window } from '@kit.ArkUI'

const TAG = 'EntryAbility'

export default class EntryAbility extends UIAbility {
  onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, TAG, 'Ability onCreate')
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(0x0000, TAG, 'loadContent failed: %{public}s', JSON.stringify(err))
        return
      }
      // 深色沉浸式状态栏，匹配应用暗色主题
      const mainWindow = windowStage.getMainWindowSync()
      mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#0D0B10',
        statusBarContentColor: '#E8DFC8',
        navigationBarColor: '#0D0B10',
        navigationBarContentColor: '#E8DFC8'
      })
    })
  }

  onWindowStageDestroy(): void {
    hilog.info(0x0000, TAG, 'Ability onWindowStageDestroy')
  }
}
