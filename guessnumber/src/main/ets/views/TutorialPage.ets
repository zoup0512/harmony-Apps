/**
 * TutorialPage.ets — 新手引导（四步渐进式）
 * Step 0 目标认知：藏起来的密码是什么
 * Step 1 读懂反馈：以 答案5234 / 猜5346 为例，逐步高亮讲解 A 与 B（核心步骤）
 * Step 2 推理策略：三条关键思维
 * Step 3 上手练习：3 位迷你实战局（复用 GameEngine，不限次数，教练实时解读）
 */
import { GameEngine, GuessRecord } from '../model/GameEngine';
import { StatsStore } from '../model/StatsStore';
import { Theme } from '../common/Theme';
import { common } from '@kit.AbilityKit';

const DEMO_ANSWER: string = '5234';
const DEMO_GUESS: string = '5346';
const KEY_DELETE: string = 'DEL';
const KEY_SUBMIT: string = 'OK';

/** 策略卡片数据 */
interface StrategyCard {
  code: string;
  result: string;
  tip: string;
}

const STRATEGIES: StrategyCard[] = [
  { code: '125', result: '0A0B', tip: '一个都没中？恭喜！1、2、5 全部排除，信息量最大。' },
  { code: '367', result: '2B', tip: '有 B 没 A：数字猜对了，但都放错了位置，换换顺序试试。' },
  { code: '736', result: '2A1B', tip: 'A 变多了，说明调整方向是对的，保留对的位置继续微调。' }
];

@Component
export struct TutorialPage {
  @Consume('pathStack') pathStack: NavPathStack;
  @State step: number = 0;          // 当前步骤 0..3
  @State revealStage: number = 0;   // Step1 讲解进度：0 未开始 / 1 讲A / 2 讲B / 3 出结果
  // —— 练习局状态 ——
  @State pCurrent: string = '';
  @State pRecords: GuessRecord[] = [];
  @State pWon: boolean = false;
  @State coach: string = '试着输入 3 个不同的数字，点「破解」提交';
  private engine: GameEngine = new GameEngine();
  private keyRows: string[][] = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    [KEY_DELETE, '0', KEY_SUBMIT]
  ];

  aboutToAppear(): void {
    this.engine.start(3, 999); // 练习局：3 位，不限次数
  }

  finish(): void {
    const ctx = this.getUIContext().getHostContext() as common.Context;
    StatsStore.setTutorialDone(ctx);
    this.pathStack.pop();
  }

  // ---------- Step1 示例判定辅助 ----------

  /** 示例猜测中第 i 位的讲解状态：'A' | 'B' | 'X'（不存在） */
  demoMark(i: number): string {
    const ch = DEMO_GUESS.charAt(i);
    const pos = DEMO_ANSWER.indexOf(ch);
    if (pos === i) {
      return 'A';
    }
    return pos >= 0 ? 'B' : 'X';
  }

  demoTileColor(i: number): string {
    const mark = this.demoMark(i);
    if (mark === 'A' && this.revealStage >= 1) {
      return Theme.GREEN;
    }
    if (mark === 'B' && this.revealStage >= 2) {
      return Theme.BLUE;
    }
    return 'rgba(0,0,0,0)';
  }

  demoTileOpacity(i: number): number {
    return this.demoMark(i) === 'X' && this.revealStage >= 2 ? 0.3 : 1;
  }

  // ---------- 练习局逻辑 ----------

  onPracticeKey(key: string): void {
    if (this.pWon) {
      return;
    }
    if (key === KEY_DELETE) {
      if (this.pCurrent.length > 0) {
        this.pCurrent = this.pCurrent.substring(0, this.pCurrent.length - 1);
      }
      return;
    }
    if (key === KEY_SUBMIT) {
      if (this.pCurrent.length === 3) {
        const rec = this.engine.judge(this.pCurrent);
        const next: GuessRecord[] = [rec];
        for (let i = 0; i < this.pRecords.length; i++) {
          next.push(this.pRecords[i]);
        }
        this.pRecords = next;
        this.pCurrent = '';
        this.updateCoach(rec);
      }
      return;
    }
    if (this.pCurrent.length < 3 && this.pCurrent.indexOf(key) < 0) {
      this.pCurrent += key;
    }
  }

  /** 教练：把这次的 xAyB 翻译成人话 */
  updateCoach(rec: GuessRecord): void {
    if (rec.a === 3) {
      this.pWon = true;
      this.coach = '🎉 破解成功！你已经完全掌握玩法，出师了！';
      return;
    }
    if (rec.a === 0 && rec.b === 0) {
      this.coach = '0A0B：' + rec.guess.split('').join('、') + ' 都不在密码里，把它们全部排除！';
      return;
    }
    let text = rec.a.toString() + 'A' + rec.b.toString() + 'B：';
    if (rec.a > 0) {
      text += '有 ' + rec.a.toString() + ' 个数字位置完全正确';
    }
    if (rec.b > 0) {
      text += (rec.a > 0 ? '；' : '') + '有 ' + rec.b.toString() + ' 个数字对了但位置放错';
    }
    text += '。结合上几次结果推理一下！';
    this.coach = text;
  }

  practiceKeyDisabled(key: string): boolean {
    return this.pWon || this.pCurrent.length >= 3 || this.pCurrent.indexOf(key) >= 0;
  }

  // ---------- 通用小组件 ----------

  @Builder
  Tile(ch: string, size: number, fontSize: number, color: string, borderClr: string, dim: number) {
    Text(ch)
      .fontSize(fontSize)
      .fontWeight(FontWeight.Bold)
      .fontColor(color)
      .width(size)
      .height(size * 1.18)
      .textAlign(TextAlign.Center)
      .backgroundColor('rgba(255,255,255,0.08)')
      .borderRadius(Theme.R_TILE)
      .borderWidth(2)
      .borderColor(borderClr)
      .opacity(dim)
      .animation({ duration: 240, curve: Curve.EaseOut })
  }

  @Builder
  StepDots() {
    Row({ space: 6 }) {
      ForEach([0, 1, 2, 3], (i: number) => {
        Column()
          .width(this.step === i ? 18 : 7)
          .height(7)
          .borderRadius(999)
          .backgroundColor(this.step === i ? Theme.GOLD : 'rgba(255,255,255,0.2)')
          .animation({ duration: 200, curve: Curve.EaseOut })
      }, (i: number) => i.toString())
    }
  }

  // ---------- 各步骤内容 ----------

  @Builder
  Step0Goal() {
    Column({ space: 22 }) {
      Text('第 1 步 · 你的目标')
        .fontSize(13)
        .fontColor(Theme.GOLD)
        .letterSpacing(2)
      Row({ space: 10 }) {
        ForEach(['?', '?', '?', '?'], (ch: string, idx: number) => {
          this.Tile(ch, 52, 26, Theme.GOLD, Theme.STROKE, 1)
        }, (ch: string, idx: number) => idx.toString())
      }
      Text('系统在暗中记下了一组数字密码\n各位数字互不相同，首位也可能是 0')
        .fontSize(16)
        .fontColor(Theme.TEXT)
        .textAlign(TextAlign.Center)
        .lineHeight(26)
      Text('你的任务：在限定次数内把它猜出来。\n别担心，每次猜测系统都会给你线索。')
        .fontSize(14)
        .fontColor(Theme.TEXT_SUB)
        .textAlign(TextAlign.Center)
        .lineHeight(22)
    }
    .width('100%')
  }

  @Builder
  DemoLabel(i: number) {
    Text(this.demoMark(i) === 'A' ? 'A' : (this.demoMark(i) === 'B' ? 'B' : '✕'))
      .fontSize(14)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.demoMark(i) === 'A' ? Theme.GREEN
        : (this.demoMark(i) === 'B' ? Theme.BLUE : Theme.TEXT_FAINT))
      .opacity((this.demoMark(i) === 'A' && this.revealStage >= 1) ||
        (this.demoMark(i) !== 'A' && this.revealStage >= 2) ? 1 : 0)
      .animation({ duration: 240, curve: Curve.EaseOut })
  }

  @Builder
  Step1Feedback() {
    Column({ space: 16 }) {
      Text('第 2 步 · 读懂线索（最关键！）')
        .fontSize(13)
        .fontColor(Theme.GOLD)
        .letterSpacing(2)

      Column({ space: 6 }) {
        Text('假设密码是（仅演示用）')
          .fontSize(12)
          .fontColor(Theme.TEXT_FAINT)
        Row({ space: 8 }) {
          ForEach(DEMO_ANSWER.split(''), (ch: string, idx: number) => {
            this.Tile(ch, 40, 20, Theme.TEXT, Theme.STROKE, 0.85)
          }, (ch: string, idx: number) => 'a' + idx.toString())
        }
      }

      Text('⬇ 你猜了')
        .fontSize(12)
        .fontColor(Theme.TEXT_FAINT)

      Column({ space: 4 }) {
        Row({ space: 8 }) {
          ForEach(DEMO_GUESS.split(''), (ch: string, idx: number) => {
            this.Tile(ch, 48, 24,
              this.demoTileColor(idx) === 'rgba(0,0,0,0)' ? Theme.TEXT : this.demoTileColor(idx),
              this.demoTileColor(idx) === 'rgba(0,0,0,0)' ? Theme.STROKE : this.demoTileColor(idx),
              this.demoTileOpacity(idx))
          }, (ch: string, idx: number) => 'g' + idx.toString())
        }
        Row({ space: 8 }) {
          ForEach(DEMO_GUESS.split(''), (ch: string, idx: number) => {
            Row() {
              this.DemoLabel(idx)
            }
            .width(48)
            .justifyContent(FlexAlign.Center)
          }, (ch: string, idx: number) => 'l' + idx.toString())
        }
      }

      // 讲解文案随阶段变化
      Column({ space: 8 }) {
        if (this.revealStage === 0) {
          Text('点击下方按钮，看看系统怎么给线索 👇')
            .fontSize(14)
            .fontColor(Theme.TEXT_SUB)
            .textAlign(TextAlign.Center)
        }
        if (this.revealStage >= 1) {
          Text('🟢 「5」数字对、位置也对 → 记 1 个 A')
            .fontSize(14)
            .fontColor(Theme.GREEN)
        }
        if (this.revealStage >= 2) {
          Text('🔵 「3」「4」数字对、位置错 → 记 2 个 B')
            .fontSize(14)
            .fontColor(Theme.BLUE)
          Text('✕ 「6」不在密码里')
            .fontSize(14)
            .fontColor(Theme.TEXT_FAINT)
        }
        if (this.revealStage >= 3) {
          Row({ space: 8 }) {
            Text('所以线索是')
              .fontSize(14)
              .fontColor(Theme.TEXT)
            Text('1A 2B')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.GOLD)
              .padding({ left: 12, right: 12, top: 4, bottom: 4 })
              .backgroundColor('rgba(245,180,65,0.14)')
              .borderRadius(999)
          }
          .transition(TransitionEffect.OPACITY.animation({ duration: 300 }))
        }
      }
      .height(96)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
  }

  @Builder
  Step2Strategy() {
    Column({ space: 14 }) {
      Text('第 3 步 · 高手思维')
        .fontSize(13)
        .fontColor(Theme.GOLD)
        .letterSpacing(2)
      Text('每条线索都在缩小范围，会推理才能又快又准')
        .fontSize(14)
        .fontColor(Theme.TEXT_SUB)
      ForEach(STRATEGIES, (s: StrategyCard, idx: number) => {
        Row({ space: 12 }) {
          Column({ space: 2 }) {
            Text(s.code)
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.TEXT)
            Text(s.result)
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor(s.result === '0A0B' ? Theme.RED
                : (s.result.indexOf('A') >= 0 && s.result.charAt(0) !== '0' ? Theme.GREEN : Theme.BLUE))
          }
          .width(64)
          Text(s.tip)
            .fontSize(13)
            .fontColor(Theme.TEXT_SUB)
            .lineHeight(20)
            .layoutWeight(1)
        }
        .width('100%')
        .padding(14)
        .backgroundColor(Theme.CARD)
        .borderRadius(Theme.R_CARD - 6)
        .borderWidth(1)
        .borderColor(Theme.STROKE)
      }, (s: StrategyCard, idx: number) => idx.toString())
      Text('💡 卡住时还能用一次「提示」，但会消耗 1 次机会')
        .fontSize(13)
        .fontColor(Theme.GOLD)
        .opacity(0.9)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  Step3Practice() {
    Column({ space: 10 }) {
      Text('第 4 步 · 亲手试一局（3 位 · 不限次数）')
        .fontSize(13)
        .fontColor(Theme.GOLD)
        .letterSpacing(2)

      // 教练气泡
      Row({ space: 8 }) {
        Text('🧑‍🏫')
          .fontSize(18)
        Text(this.coach)
          .fontSize(13)
          .fontColor(this.pWon ? Theme.GREEN : Theme.TEXT)
          .lineHeight(19)
          .layoutWeight(1)
      }
      .width('100%')
      .padding(12)
      .backgroundColor(this.pWon ? 'rgba(63,207,142,0.12)' : Theme.CARD)
      .borderRadius(Theme.R_CARD - 6)
      .borderWidth(1)
      .borderColor(this.pWon ? Theme.GREEN : Theme.STROKE)
      .animation({ duration: 200, curve: Curve.EaseOut })

      // 输入槽位
      Row({ space: 8 }) {
        ForEach([0, 1, 2], (i: number) => {
          Text(i < this.pCurrent.length ? this.pCurrent.charAt(i) : '')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.GOLD)
            .width(44)
            .height(50)
            .textAlign(TextAlign.Center)
            .backgroundColor('rgba(255,255,255,0.05)')
            .borderRadius(Theme.R_TILE - 2)
            .borderWidth(1.5)
            .borderColor(i === this.pCurrent.length && !this.pWon ? Theme.GOLD : Theme.STROKE)
        }, (i: number) => i.toString())
      }

      // 最近的猜测记录（最多显示 3 条）
      if (this.pRecords.length > 0) {
        Column({ space: 6 }) {
          ForEach(this.pRecords.slice(0, 3), (rec: GuessRecord) => {
          Row({ space: 10 }) {
            Text('#' + rec.index.toString())
              .fontSize(11)
              .fontColor(Theme.TEXT_FAINT)
              .width(24)
            Text(rec.guess.split('').join(' '))
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.TEXT)
            Blank()
            Text(rec.a.toString() + 'A')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.GREEN)
            Text(rec.b.toString() + 'B')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.BLUE)
          }
          .width('100%')
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .backgroundColor(Theme.CARD)
          .borderRadius(10)
          }, (rec: GuessRecord) => rec.index.toString())
        }
        .width('100%')
      }

      // 迷你键盘
      Column({ space: 8 }) {
        ForEach(this.keyRows, (row: string[], rIdx: number) => {
          Row({ space: 8 }) {
            ForEach(row, (key: string) => {
              if (key === KEY_DELETE) {
                Text('⌫')
                  .fontSize(18)
                  .fontColor(this.pCurrent.length > 0 ? Theme.RED : Theme.TEXT_FAINT)
                  .textAlign(TextAlign.Center)
                  .height(42)
                  .layoutWeight(1)
                  .backgroundColor(Theme.CARD)
                  .borderRadius(12)
                  .onClick(() => this.onPracticeKey(key))
              } else if (key === KEY_SUBMIT) {
                Text('✓ 破解')
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.pCurrent.length === 3 ? '#1B1030' : Theme.TEXT_FAINT)
                  .textAlign(TextAlign.Center)
                  .height(42)
                  .layoutWeight(1)
                  .linearGradient(this.pCurrent.length === 3
                    ? { angle: 135, colors: [[Theme.GOLD, 0], [Theme.GOLD_DEEP, 1]] }
                    : { angle: 135, colors: [['rgba(255,255,255,0.06)', 0], ['rgba(255,255,255,0.06)', 1]] })
                  .borderRadius(12)
                  .onClick(() => this.onPracticeKey(key))
              } else {
                Text(key)
                  .fontSize(18)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.practiceKeyDisabled(key) ? Theme.TEXT_FAINT : Theme.TEXT)
                  .textAlign(TextAlign.Center)
                  .height(42)
                  .layoutWeight(1)
                  .backgroundColor(this.practiceKeyDisabled(key) ? 'rgba(255,255,255,0.03)' : Theme.CARD_STRONG)
                  .borderRadius(12)
                  .enabled(!this.practiceKeyDisabled(key))
                  .onClick(() => this.onPracticeKey(key))
              }
            }, (key: string) => key)
          }
          .width('100%')
        }, (row: string[], rIdx: number) => rIdx.toString())
      }
      .width('100%')
    }
    .width('100%')
  }

  // ---------- 底部导航 ----------

  primaryLabel(): string {
    if (this.step === 1 && this.revealStage < 3) {
      return this.revealStage === 0 ? '看讲解' : '继续';
    }
    if (this.step === 3) {
      return this.pWon ? '完成教学，出发！' : '我学会了，直接开始';
    }
    return '下一步';
  }

  onPrimary(): void {
    if (this.step === 1 && this.revealStage < 3) {
      this.revealStage++;
      return;
    }
    if (this.step < 3) {
      this.step++;
      return;
    }
    this.finish();
  }

  build() {
    NavDestination() {
      Column() {
        // 顶栏：进度点 + 跳过
        Row() {
          this.StepDots()
          Blank()
          Text('跳过')
            .fontSize(14)
            .fontColor(Theme.TEXT_SUB)
            .padding(8)
            .onClick(() => this.finish())
        }
        .width('100%')

        // 内容区
        Scroll() {
          Column() {
            if (this.step === 0) {
              this.Step0Goal()
            } else if (this.step === 1) {
              this.Step1Feedback()
            } else if (this.step === 2) {
              this.Step2Strategy()
            } else {
              this.Step3Practice()
            }
          }
          .width('100%')
          .padding({ top: 18, bottom: 12 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)

        // 底部按钮
        Row({ space: 12 }) {
          if (this.step > 0) {
            Text('上一步')
              .fontSize(15)
              .fontColor(Theme.TEXT)
              .textAlign(TextAlign.Center)
              .height(50)
              .width(96)
              .backgroundColor(Theme.CARD_STRONG)
              .borderRadius(999)
              .onClick(() => {
                if (this.step === 1 && this.revealStage > 0) {
                  this.revealStage = 0;
                }
                this.step--;
              })
          }
          Text(this.primaryLabel())
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1B1030')
            .textAlign(TextAlign.Center)
            .height(50)
            .layoutWeight(1)
            .linearGradient({ angle: 135, colors: [[Theme.GOLD, 0], [Theme.GOLD_DEEP, 1]] })
            .borderRadius(999)
            .onClick(() => this.onPrimary())
        }
        .width('100%')
        .margin({ top: 8 })
      }
      .width('100%')
      .height('100%')
      .padding({ left: 22, right: 22, top: 52, bottom: 24 })
    }
    .hideTitleBar(true)
    .linearGradient({ angle: 180, colors: [[Theme.BG_TOP, 0], [Theme.BG_BOTTOM, 1]] })
    .onBackPressed(() => {
      this.finish();
      return true;
    })
  }
}
