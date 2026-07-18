import { router } from '@kit.ArkUI';
import common from '@ohos.app.ability.common';
import { MP_THEMES, MPTheme, MPSettings } from '../common/MatchPairsCommon';

@Entry
@Component
struct MatchPairsThemePage {
  aboutToAppear(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    MPSettings.load(ctx);
  }

  build() {
    Column() {
      // Top bar
      Row() {
        Button({ type: ButtonType.Circle }) {
          Text('‹').fontSize(28).fontColor('#FFF').fontWeight(FontWeight.Bold)
        }.width(40).height(40).backgroundColor('#9E9E9E').onClick(() => router.back())
        Text('翻牌配对').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#212121').margin({ left: 12 })
        Blank()
      }.width('100%').padding(16)

      Text('选择一个主题').fontSize(16).fontColor('#616161').margin({ bottom: 16 })

      Column({ space: 16 }) {
        ForEach(MP_THEMES, (t: MPTheme) => {
          Stack() {
            // Background image
            Image(t.bgImage).width('100%').height('100%').objectFit(ImageFit.Cover).borderRadius(20)
            Column().width('100%').height('100%').backgroundColor('#55000000').borderRadius(20)
            Row() {
              Stack() {
                Column().width(96).height(96).borderRadius(16).backgroundColor('#FFFFFF')
                Image(t.cover).width(80).height(80).objectFit(ImageFit.Contain)
              }.margin({ left: 16 })
              Column({ space: 6 }) {
                Text(t.name).fontSize(22).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
                Text(`${t.imageCount} 张图案`).fontSize(13).fontColor('#EEEEEE')
              }.alignItems(HorizontalAlign.Start).margin({ left: 16 })
              Blank()
              Text('▶').fontSize(28).fontColor('#FFFFFF').margin({ right: 20 })
            }.width('100%').height('100%').alignItems(VerticalAlign.Center)
          }.width('92%').height(140)
          .shadow({ radius: 8, color: '#22000000', offsetX: 0, offsetY: 2 })
          .onClick(() => {
            router.pushUrl({ url: 'pages/MatchPairsDifficultyPage', params: { themeId: t.id } });
          })
        }, (t: MPTheme) => `mpt_${t.id}`)
      }.width('100%')

      Blank()
    }.width('100%').height('100%').backgroundColor('#F5F5F5')
  }
}
