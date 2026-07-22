/**
 * GamePage.ets — 对局页面
 * 顶部：返回 / 计时 / 剩余机会
 * 中部：当前输入瓷砖 + 猜测历史（最新在上）
 * 底部：定制数字键盘（自动禁用已用数字，杜绝非法输入）+ 提示
 * 结束：结果浮层（揭示答案 / 再来一局 / 返回主页）
 */
import { GameEngine, GuessRecord, DIFFICULTIES, Difficulty } from '../model/GameEngine';
import { StatsStore } from '../model/StatsStore';
import { Theme } from '../common/Theme';
import { common } from '@kit.AbilityKit';

const KEY_DELETE: string = 'DEL';
const KEY_SUBMIT: string = 'OK';

@Component
export struct GamePage {
  @Consume('pathStack') pathStack: NavPathStack;
  private engine: GameEngine = new GameEngine();
  @State digits: number = 4;
  @State current: string = '';
  @State records: GuessRecord[] = [];
  @State attemptsLeft: number = 8;
  @State maxAttempts: number = 8;
  @State finished: boolean = false;
  @State win: boolean = false;
  @State seconds: number = 0;
  @State hintText: string = '';
  @State hintUsed: boolean = false;
  @State statsSaved: boolean = false;
  private timerId: number = -1;
  private keyRows: string[][] = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    [KEY_DELETE, '0', KEY_SUBMIT]
  ];

  aboutToDisappear(): void {
    this.stopTimer();
  }

  startGame(digits: number): void {
    let attempts = 8;
    for (let i = 0; i < DIFFICULTIES.length; i++) {
      const d: Difficulty = DIFFICULTIES[i];
      if (d.digits === digits) {
        attempts = d.attempts;
        break;
      }
    }
    this.digits = digits;
    this.maxAttempts = attempts;
    this.engine.start(digits, attempts);
    this.records = [];
    this.current = '';
    this.attemptsLeft = attempts;
    this.finished = false;
    this.win = false;
    this.seconds = 0;
    this.hintText = '';
    this.hintUsed = false;
    this.statsSaved = false;
    this.stopTimer();
    this.timerId = setInterval(() => {
      if (!this.finished) {
        this.seconds++;
      }
    }, 1000);
  }

  stopTimer(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  timeText(): string {
    const m = Math.floor(this.seconds / 60);
    const s = this.seconds % 60;
    const mm = m < 10 ? '0' + m.toString() : m.toString();
    const ss = s < 10 ? '0' + s.toString() : s.toString();
    return mm + ':' + ss;
  }

  onKey(key: string): void {
    if (this.finished) {
      return;
    }
    if (key === KEY_DELETE) {
      if (this.current.length > 0) {
        this.current = this.current.substring(0, this.current.length - 1);
      }
      return;
    }
    if (key === KEY_SUBMIT) {
      this.submit();
      return;
    }
    // 数字键：长度未满且不重复（对应原 C 版 JudgeInput 的输入校验）
    if (this.current.length < this.digits && this.current.indexOf(key) < 0) {
      this.current += key;
    }
  }

  submit(): void {
    if (this.current.length !== this.digits || this.finished) {
      return;
    }
    const rec = this.engine.judge(this.current);
    const next: GuessRecord[] = [rec];
    for (let i = 0; i < this.records.length; i++) {
      next.push(this.records[i]);
    }
    this.records = next;
    this.current = '';
    this.attemptsLeft = this.engine.attemptsLeft();
    if (rec.a === this.digits) {
      this.endGame(true);
    } else if (this.attemptsLeft <= 0) {
      this.endGame(false);
    }
  }

  requestHint(): void {
    if (this.finished || this.hintUsed) {
      return;
    }
    const past: string[] = [];
    for (let i = 0; i < this.records.length; i++) {
      past.push(this.records[i].guess);
    }
    const text = this.engine.useHint(past);
    if (text !== '') {
      this.hintText = text;
      this.hintUsed = true;
      this.attemptsLeft = this.engine.attemptsLeft();
      this.getUIContext().getPromptAction().showToast({
        message: '提示：' + text + '（消耗 1 次机会）',
        duration: 2500
      });
    } else {
      this.getUIContext().getPromptAction().showToast({
        message: '剩余机会不足，无法使用提示',
        duration: 2000
      });
    }
  }

  endGame(win: boolean): void {
    this.win = win;
    this.finished = true;
    this.stopTimer();
    if (!this.statsSaved) {
      this.statsSaved = true;
      const ctx = this.getUIContext().getHostContext() as common.Context;
      StatsStore.recordResult(ctx, win, this.engine.attemptsUsed);
    }
  }

  digitKeyDisabled(key: string): boolean {
    return this.finished ||
      this.current.length >= this.digits ||
      this.current.indexOf(key) >= 0;
  }

  // ---------- UI ----------

  @Builder
  ResultBadge(count: number, label: string, color: string) {
    Row({ space: 2 }) {
      Text(count.toString())
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(color)
      Text(label)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(color)
        .opacity(0.85)
    }
    .padding({ left: 10, right: 10, top: 4, bottom: 4 })
    .backgroundColor('rgba(255,255,255,0.06)')
    .borderRadius(999)
  }

  @Builder
  GuessTiles(guess: string, size: number, fontSize: number) {
    Row({ space: 6 }) {
      ForEach(guess.split(''), (ch: string) => {
        Text(ch)
          .fontSize(fontSize)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT)
          .width(size)
          .height(size)
          .textAlign(TextAlign.Center)
          .backgroundColor('rgba(255,255,255,0.08)')
          .borderRadius(Theme.R_TILE - 4)
      }, (ch: string, idx: number) => idx.toString() + '_' + ch)
    }
  }

  @Builder
  Header() {
    Row() {
      // 返回
      Text('‹')
        .fontSize(34)
        .fontColor(Theme.TEXT)
        .width(44)
        .height(44)
        .textAlign(TextAlign.Center)
        .backgroundColor(Theme.CARD)
        .borderRadius(999)
        .onClick(() => {
          this.stopTimer();
          this.pathStack.pop();
        })

      Blank()

      // 计时
      Row({ space: 4 }) {
        Text('⏱')
          .fontSize(14)
        Text(this.timeText())
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TEXT)
      }
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(Theme.CARD)
      .borderRadius(999)

      Blank()

      // 剩余机会
      Row({ space: 4 }) {
        Text('❤')
          .fontSize(13)
          .fontColor(Theme.GOLD)
        Text(this.attemptsLeft.toString() + ' / ' + this.maxAttempts.toString())
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TEXT)
      }
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(Theme.CARD)
      .borderRadius(999)
    }
    .width('100%')
  }

  @Builder
  AttemptPips() {
    Row({ space: 6 }) {
      ForEach(this.pipArray(), (used: boolean, idx: number) => {
        Circle()
          .width(8)
          .height(8)
          .fill(used ? Theme.GOLD : 'rgba(255,255,255,0.18)')
      }, (used: boolean, idx: number) => idx.toString() + '_' + (used ? '1' : '0'))
    }
    .margin({ top: 10 })
  }

  pipArray(): boolean[] {
    const arr: boolean[] = [];
    const used = this.maxAttempts - this.attemptsLeft;
    for (let i = 0; i < this.maxAttempts; i++) {
      arr.push(i < used);
    }
    return arr;
  }

  @Builder
  CurrentInput() {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        ForEach(this.slotArray(), (ch: string, idx: number) => {
          Text(ch)
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.GOLD)
            .width(54)
            .height(64)
            .textAlign(TextAlign.Center)
            .backgroundColor(ch === '' ? 'rgba(255,255,255,0.05)' : 'rgba(245,180,65,0.12)')
            .borderRadius(Theme.R_TILE)
            .borderWidth(1.5)
            .borderColor(idx === this.current.length && !this.finished
              ? Theme.GOLD : Theme.STROKE)
        }, (ch: string, idx: number) => idx.toString() + '_' + ch)
      }
      if (this.hintText !== '') {
        Text('💡 ' + this.hintText)
          .fontSize(13)
          .fontColor(Theme.GOLD)
          .opacity(0.9)
      }
    }
    .margin({ top: 18 })
  }

  slotArray(): string[] {
    const arr: string[] = [];
    for (let i = 0; i < this.digits; i++) {
      arr.push(i < this.current.length ? this.current.charAt(i) : '');
    }
    return arr;
  }

  @Builder
  History() {
    if (this.records.length === 0) {
      Column({ space: 6 }) {
        Text('🔐')
          .fontSize(34)
          .opacity(0.6)
        Text('输入一组互不相同的数字，开始破解')
          .fontSize(13)
          .fontColor(Theme.TEXT_FAINT)
        Text('A = 数字对、位置对　B = 数字对、位置错')
          .fontSize(12)
          .fontColor(Theme.TEXT_FAINT)
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else {
      List({ space: 8 }) {
        ForEach(this.records, (rec: GuessRecord) => {
          ListItem() {
            Row() {
              Text('#' + rec.index.toString())
                .fontSize(12)
                .fontColor(Theme.TEXT_FAINT)
                .width(30)
              this.GuessTiles(rec.guess, 34, 18)
              Blank()
              this.ResultBadge(rec.a, 'A', Theme.GREEN)
              Row().width(6)
              this.ResultBadge(rec.b, 'B', Theme.BLUE)
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .backgroundColor(Theme.CARD)
            .borderRadius(Theme.R_CARD - 6)
          }
        }, (rec: GuessRecord) => rec.index.toString())
      }
      .layoutWeight(1)
      .width('100%')
      .margin({ top: 14 })
      .scrollBar(BarState.Off)
    }
  }

  @Builder
  Keypad() {
    Column({ space: 10 }) {
      // 提示按钮
      Row() {
        Blank()
        Row({ space: 4 }) {
          Text('💡')
            .fontSize(13)
          Text(this.hintUsed ? '提示已用' : '提示（耗 1 次机会）')
            .fontSize(13)
            .fontColor(this.hintUsed ? Theme.TEXT_FAINT : Theme.GOLD)
        }
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .backgroundColor(this.hintUsed ? 'rgba(255,255,255,0.04)' : 'rgba(245,180,65,0.12)')
        .borderRadius(999)
        .onClick(() => this.requestHint())
      }
      .width('100%')

      ForEach(this.keyRows, (row: string[], rIdx: number) => {
        Row({ space: 10 }) {
          ForEach(row, (key: string) => {
            this.KeyButton(key)
          }, (key: string) => key)
        }
        .width('100%')
      }, (row: string[], rIdx: number) => rIdx.toString())
    }
    .width('100%')
    .margin({ top: 12 })
  }

  @Builder
  KeyButton(key: string) {
    if (key === KEY_DELETE) {
      Text('⌫')
        .fontSize(22)
        .fontColor(this.current.length > 0 ? Theme.RED : Theme.TEXT_FAINT)
        .textAlign(TextAlign.Center)
        .height(52)
        .layoutWeight(1)
        .backgroundColor(Theme.CARD)
        .borderRadius(Theme.R_KEY)
        .onClick(() => this.onKey(key))
    } else if (key === KEY_SUBMIT) {
      Text('✓ 破解')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.current.length === this.digits ? '#1B1030' : Theme.TEXT_FAINT)
        .textAlign(TextAlign.Center)
        .height(52)
        .layoutWeight(1)
        .linearGradient(this.current.length === this.digits
          ? { angle: 135, colors: [[Theme.GOLD, 0], [Theme.GOLD_DEEP, 1]] }
          : { angle: 135, colors: [['rgba(255,255,255,0.06)', 0], ['rgba(255,255,255,0.06)', 1]] })
        .borderRadius(Theme.R_KEY)
        .onClick(() => this.onKey(key))
    } else {
      Text(key)
        .fontSize(22)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.digitKeyDisabled(key) ? Theme.TEXT_FAINT : Theme.TEXT)
        .textAlign(TextAlign.Center)
        .height(52)
        .layoutWeight(1)
        .backgroundColor(this.digitKeyDisabled(key) ? 'rgba(255,255,255,0.03)' : Theme.CARD_STRONG)
        .borderRadius(Theme.R_KEY)
        .enabled(!this.digitKeyDisabled(key))
        .onClick(() => this.onKey(key))
    }
  }

  @Builder
  ResultOverlay() {
    Column() {
      Column({ space: 14 }) {
        Text(this.win ? '🎉' : '💥')
          .fontSize(52)
        Text(this.win ? '破解成功！' : '解密失败')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.win ? Theme.GREEN : Theme.RED)
        Text(this.win
          ? '用时 ' + this.timeText() + ' · 共 ' + this.engine.attemptsUsed.toString() + ' 次尝试'
          : '机会已用完，正确密码是：')
          .fontSize(14)
          .fontColor(Theme.TEXT_SUB)
        this.GuessTiles(this.engine.secret, 44, 24)
        Row({ space: 12 }) {
          Text('返回主页')
            .fontSize(16)
            .fontColor(Theme.TEXT)
            .textAlign(TextAlign.Center)
            .height(48)
            .layoutWeight(1)
            .backgroundColor(Theme.CARD_STRONG)
            .borderRadius(999)
            .onClick(() => {
              this.stopTimer();
              this.pathStack.pop();
            })
          Text('再来一局')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1B1030')
            .textAlign(TextAlign.Center)
            .height(48)
            .layoutWeight(1)
            .linearGradient({ angle: 135, colors: [[Theme.GOLD, 0], [Theme.GOLD_DEEP, 1]] })
            .borderRadius(999)
            .onClick(() => this.startGame(this.digits))
        }
        .width('100%')
        .margin({ top: 8 })
      }
      .width('84%')
      .padding(24)
      .backgroundColor('#1D1838')
      .borderRadius(24)
      .borderWidth(1)
      .borderColor(Theme.STROKE)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('rgba(8,8,20,0.72)')
    .transition(TransitionEffect.OPACITY.animation({ duration: 260 }))
  }

  build() {
    NavDestination() {
      Stack() {
        Column() {
          this.Header()
          this.AttemptPips()
          this.CurrentInput()
          this.History()
          this.Keypad()
        }
        .width('100%')
        .height('100%')
        .padding({ left: 18, right: 18, top: 52, bottom: 24 })

        if (this.finished) {
          this.ResultOverlay()
        }
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .linearGradient({ angle: 180, colors: [[Theme.BG_TOP, 0], [Theme.BG_BOTTOM, 1]] })
    .onReady((ctx: NavDestinationContext) => {
      const digits = ctx.pathInfo.param as number;
      this.startGame(digits > 0 ? digits : 4);
    })
    .onBackPressed(() => {
      this.stopTimer();
      this.pathStack.pop();
      return true;
    })
  }
}
