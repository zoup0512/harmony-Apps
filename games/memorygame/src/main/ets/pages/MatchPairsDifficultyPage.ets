import { router } from '@kit.ArkUI';
import common from '@ohos.app.ability.common';
import { MP_DIFFICULTIES, MPDifficulty, getThemeById, MPTheme, loadBest, MPBest } from '../common/MatchPairsCommon';

interface DiffRow { diff: MPDifficulty; best: MPBest; }

@Entry
@Component
struct MatchPairsDifficultyPage {
  @State private themeId: number = 1;
  @State private theme: MPTheme = getThemeById(1);
  @State private rows: DiffRow[] = [];

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, Object>;
    if (params && params.themeId !== undefined) this.themeId = params.themeId as number;
    this.theme = getThemeById(this.themeId);
    this.refresh();
  }

  onPageShow(): void { this.refresh(); }

  private async refresh(): Promise<void> {
    const ctx = getContext(this) as common.UIAbilityContext;
    const out: DiffRow[] = [];
    for (const d of MP_DIFFICULTIES) {
      const best = await loadBest(ctx, this.themeId, d.level);
      out.push({ diff: d, best } as DiffRow);
    }
    this.rows = out;
  }

  private fmtTime(sec: number): string {
    if (sec <= 0) return '--';
    const m = Math.floor(sec / 60);
    const s = sec % 60;
    return `${m}:${s < 10 ? '0' : ''}${s}`;
  }

  build() {
    Column() {
      // Top bar
      Row() {
        Button({ type: ButtonType.Circle }) {
          Text('‹').fontSize(28).fontColor('#FFF').fontWeight(FontWeight.Bold)
        }.width(40).height(40).backgroundColor('#9E9E9E').onClick(() => router.back())
        Text(`${this.theme.name} - 选择难度`).fontSize(18).fontWeight(FontWeight.Bold).fontColor('#212121').margin({ left: 12 })
        Blank()
        Text(this.theme.cover).fontSize(28).margin({ right: 12 })
      }.width('100%').padding(16).backgroundColor(this.theme.bgColor)

      List({ space: 12 }) {
        ListItem().height(8)
        ForEach(this.rows, (row: DiffRow) => {
          ListItem() {
            Row() {
              // Level badge
              Stack() {
                Column().width(56).height(56).borderRadius(28).backgroundColor('#1976D2')
                Text(`${row.diff.level}`).fontSize(26).fontColor('#FFF').fontWeight(FontWeight.Bold)
              }.margin({ left: 16, right: 16 })

              Column({ space: 4 }) {
                Text(`${row.diff.cols} × ${row.diff.rows}  (${row.diff.numTiles} 张牌)`)
                  .fontSize(15).fontColor('#212121').fontWeight(FontWeight.Medium)
                Text(`限时 ${row.diff.timeSec} 秒`).fontSize(12).fontColor('#757575')
                Row({ space: 4 }) {
                  ForEach([1, 2, 3] as number[], (i: number) => {
                    Text(i <= row.best.stars ? '★' : '☆').fontSize(16)
                      .fontColor(i <= row.best.stars ? '#FFB300' : '#BDBDBD')
                  }, (i: number) => `mpd_star_${row.diff.level}_${i}`)
                  Text(`  最佳: ${this.fmtTime(row.best.timeSec)}`).fontSize(12).fontColor('#9E9E9E')
                }
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)

              Text('▶').fontSize(22).fontColor('#1976D2').margin({ right: 16 })
            }.width('100%').height(96)
            .backgroundColor('#FFFFFF').borderRadius(12)
            .onClick(() => {
              router.pushUrl({
                url: 'pages/MatchPairsGamePage',
                params: { themeId: this.themeId, level: row.diff.level }
              });
            })
          }.padding({ left: 12, right: 12 })
        }, (row: DiffRow) => `mpd_${row.diff.level}`)
        ListItem().height(16)
      }.layoutWeight(1).width('100%').backgroundColor('#F5F5F5')
    }.width('100%').height('100%').backgroundColor('#F5F5F5')
  }
}
