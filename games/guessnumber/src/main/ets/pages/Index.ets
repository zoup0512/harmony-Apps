/**
 * Index.ets — 主页
 * 标题区（1A2B 主视觉）→ 战绩卡 → 难度选择 → 开始按钮 → 玩法规则（半模态）
 */
import { GamePage } from '../views/GamePage';
import { TutorialPage } from '../views/TutorialPage';
import { Stats, StatsStore } from '../model/StatsStore';
import { DIFFICULTIES, Difficulty } from '../model/GameEngine';
import { Theme } from '../common/Theme';
import { common } from '@kit.AbilityKit';

@Entry
@Component
struct Index {
  @Provide('pathStack') pathStack: NavPathStack = new NavPathStack();
  @State stats: Stats = new Stats();
  @State selectedDigits: number = 4;
  @State showRules: boolean = false;

  aboutToAppear(): void {
    this.loadStats();
    this.checkFirstLaunch();
  }

  loadStats(): void {
    const ctx = this.getUIContext().getHostContext() as common.Context;
    StatsStore.load(ctx).then((s: Stats) => {
      this.stats = s;
    });
  }

  /** 首次启动自动进入新手引导 */
  checkFirstLaunch(): void {
    const ctx = this.getUIContext().getHostContext() as common.Context;
    StatsStore.isTutorialDone(ctx).then((done: boolean) => {
      if (!done) {
        // 稍作延迟，确保 Navigation 已就绪
        setTimeout(() => {
          this.pathStack.pushPathByName('tutorial', '', () => {
            this.loadStats();
          });
        }, 150);
      }
    });
  }

  winRateText(): string {
    if (this.stats.played === 0) {
      return '--';
    }
    return Math.round(this.stats.wins * 100 / this.stats.played).toString() + '%';
  }

  @Builder
  PagesMap(name: string) {
    if (name === 'game') {
      GamePage()
    } else if (name === 'tutorial') {
      TutorialPage()
    }
  }

  @Builder
  HeroTiles() {
    Row({ space: 8 }) {
      ForEach(['1', 'A', '2', 'B'], (ch: string, idx: number) => {
        Text(ch)
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor(idx === 1 ? Theme.GREEN : (idx === 3 ? Theme.BLUE : Theme.TEXT))
          .width(48)
          .height(58)
          .textAlign(TextAlign.Center)
          .backgroundColor('rgba(255,255,255,0.08)')
          .borderRadius(Theme.R_TILE)
          .borderWidth(1)
          .borderColor(Theme.STROKE)
          .rotate({ angle: idx % 2 === 0 ? -3 : 3 })
      }, (ch: string, idx: number) => idx.toString())
    }
  }

  @Builder
  StatCell(value: string, label: string) {
    Column({ space: 4 }) {
      Text(value)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.GOLD)
      Text(label)
        .fontSize(12)
        .fontColor(Theme.TEXT_SUB)
    }
    .layoutWeight(1)
  }

  @Builder
  StatsCard() {
    Row() {
      this.StatCell(this.stats.played.toString(), '对局')
      this.VDivider()
      this.StatCell(this.winRateText(), '胜率')
      this.VDivider()
      this.StatCell(this.stats.best === 0 ? '--' : this.stats.best.toString() + ' 次', '最佳')
      this.VDivider()
      this.StatCell(this.stats.streak.toString(), '连胜')
    }
    .width('100%')
    .padding({ top: 16, bottom: 16 })
    .backgroundColor(Theme.CARD)
    .borderRadius(Theme.R_CARD)
    .borderWidth(1)
    .borderColor(Theme.STROKE)
  }

  @Builder
  VDivider() {
    Column()
      .width(1)
      .height(28)
      .backgroundColor(Theme.STROKE)
  }

  @Builder
  DifficultyCard(d: Difficulty) {
    Column({ space: 4 }) {
      Text(d.name)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.selectedDigits === d.digits ? '#1B1030' : Theme.TEXT)
      Text(d.desc)
        .fontSize(11)
        .fontColor(this.selectedDigits === d.digits ? 'rgba(27,16,48,0.75)' : Theme.TEXT_SUB)
        .textAlign(TextAlign.Center)
    }
    .layoutWeight(1)
    .padding({ top: 14, bottom: 14, left: 4, right: 4 })
    .linearGradient(this.selectedDigits === d.digits
      ? { angle: 135, colors: [[Theme.GOLD, 0], [Theme.GOLD_DEEP, 1]] }
      : { angle: 135, colors: [[Theme.CARD, 0], [Theme.CARD, 1]] })
    .borderRadius(Theme.R_CARD - 4)
    .borderWidth(1)
    .borderColor(this.selectedDigits === d.digits ? 'rgba(0,0,0,0)' : Theme.STROKE)
    .animation({ duration: 180, curve: Curve.EaseOut })
    .onClick(() => {
      this.selectedDigits = d.digits;
    })
  }

  @Builder
  RulesSheet() {
    Column({ space: 14 }) {
      Text('玩法规则')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TEXT)
      Column({ space: 10 }) {
        this.RuleLine('🎯', '系统随机生成一组各位互不相同的数字（首位可以为 0），你要在限定次数内破解它。')
        this.RuleLine('🟢', 'A：数字对且位置对的个数。例如答案 5234，猜 5346 → 数字 5 位置正确，记 1A。')
        this.RuleLine('🔵', 'B：数字猜对但位置不对的个数。上例中 3 和 4 数字对但位置错，记 2B，结果即 1A2B。')
        this.RuleLine('⌨️', '键盘会自动禁用已输入的数字，杜绝重复；凑满位数后点「破解」提交。')
        this.RuleLine('💡', '每局可用一次提示，随机揭示一位密码，但会消耗 1 次机会，慎用。')
        this.RuleLine('🏆', '猜中即胜利；用完机会则失败并公布答案。次数越少、用时越短，战绩越好。')
      }
      .alignItems(HorizontalAlign.Start)
      Text('知道了')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1B1030')
        .textAlign(TextAlign.Center)
        .width('100%')
        .height(46)
        .linearGradient({ angle: 135, colors: [[Theme.GOLD, 0], [Theme.GOLD_DEEP, 1]] })
        .borderRadius(999)
        .onClick(() => {
          this.showRules = false;
        })
    }
    .width('100%')
    .padding({ left: 22, right: 22, top: 10, bottom: 30 })
  }

  @Builder
  RuleLine(icon: string, text: string) {
    Row({ space: 10 }) {
      Text(icon)
        .fontSize(16)
      Text(text)
        .fontSize(14)
        .fontColor(Theme.TEXT_SUB)
        .lineHeight(21)
        .layoutWeight(1)
    }
    .alignItems(VerticalAlign.Top)
  }

  build() {
    Navigation(this.pathStack) {
      Column() {
        Blank()
          .height(30)

        this.HeroTiles()

        Text('数字解密')
          .fontSize(34)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT)
          .margin({ top: 20 })
        Text('经典 1A2B · 用逻辑破解密码')
          .fontSize(14)
          .fontColor(Theme.TEXT_SUB)
          .margin({ top: 6 })

        Blank()
          .height(34)

        this.StatsCard()

        Text('选择难度')
          .fontSize(14)
          .fontColor(Theme.TEXT_SUB)
          .alignSelf(ItemAlign.Start)
          .margin({ top: 26, bottom: 10 })

        Row({ space: 10 }) {
          ForEach(DIFFICULTIES, (d: Difficulty) => {
            this.DifficultyCard(d)
          }, (d: Difficulty) => d.digits.toString())
        }
        .width('100%')

        Blank()

        Text('开始破解')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1B1030')
          .textAlign(TextAlign.Center)
          .width('100%')
          .height(56)
          .linearGradient({ angle: 135, colors: [[Theme.GOLD, 0], [Theme.GOLD_DEEP, 1]] })
          .borderRadius(999)
          .shadow({ radius: 24, color: 'rgba(245,180,65,0.35)', offsetY: 6 })
          .onClick(() => {
            this.pathStack.pushPathByName('game', this.selectedDigits, () => {
              // 从对局页返回时刷新战绩
              this.loadStats();
            });
          })

        Row({ space: 4 }) {
          Text('玩法规则')
            .fontSize(14)
            .fontColor(Theme.TEXT_SUB)
            .padding(12)
            .onClick(() => {
              this.showRules = true;
            })
            .bindSheet($$this.showRules, this.RulesSheet(), {
              height: SheetSize.FIT_CONTENT,
              backgroundColor: '#1D1838',
              showClose: true,
              dragBar: true
            })
          Text('·')
            .fontSize(14)
            .fontColor(Theme.TEXT_FAINT)
          Text('新手教学')
            .fontSize(14)
            .fontColor(Theme.GOLD)
            .opacity(0.85)
            .padding(12)
            .onClick(() => {
              this.pathStack.pushPathByName('tutorial', '');
            })
        }
        .margin({ top: 6, bottom: 10 })
      }
      .width('100%')
      .height('100%')
      .padding({ left: 24, right: 24, top: 40, bottom: 20 })
    }
    .mode(NavigationMode.Stack)
    .navDestination(this.PagesMap)
    .hideTitleBar(true)
    .linearGradient({ angle: 180, colors: [[Theme.BG_TOP, 0], [Theme.BG_BOTTOM, 1]] })
    .width('100%')
    .height('100%')
  }
}
