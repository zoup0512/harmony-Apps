import { router } from '@kit.ArkUI';
import { GamePauseDialog, GameOverOverlay, GameTopBar, stars3, fmtTime, randInt } from '../common/GameCommon';

// "像之前的吗" — is current element same as the previous one? (game id=15)
const SHAPES: string[] = ['●', '■', '▲', '◆', '★', '⬢', '♥'];
const COLORS: string[] = ['#E91E63', '#9C27B0', '#3F51B5', '#2196F3', '#00BCD4', '#4CAF50', '#FFEB3B', '#FF9800', '#FF5722', '#795548'];
const GAME_TIME_MS = 30000;

interface Elem { shape: number; color: number; }

@Entry
@Component
struct LikePreviousPage {
  @State private level: number = 1;
  @State private lives: number = 3;
  @State private timeMs: number = GAME_TIME_MS;
  @State private prevShape: number = -1;
  @State private prevColor: number = -1;
  @State private curShape: number = 0;
  @State private curColor: number = 0;
  @State private hasPrev: boolean = false;
  @State private isSame: boolean = false;
  @State private showFeedback: boolean = false;
  @State private feedbackOk: boolean = false;
  @State private isPaused: boolean = false;
  @State private isGameOver: boolean = false;
  private timerId: number = -1;
  private startTs: number = 0;
  private flowId: number = 0;

  aboutToAppear(): void { this.startGame(); }
  aboutToDisappear(): void { this.clearTimer(); this.flowId++; }

  private clearTimer(): void { if (this.timerId !== -1) { clearInterval(this.timerId); this.timerId = -1; } }

  private startGame(): void {
    this.flowId++;
    this.level = 1; this.lives = 3; this.timeMs = GAME_TIME_MS;
    this.hasPrev = false; this.prevShape = -1; this.prevColor = -1;
    this.isPaused = false; this.isGameOver = false; this.showFeedback = false;
    this.nextElement();
    this.startTimer();
  }

  private startTimer(): void {
    this.clearTimer();
    this.startTs = Date.now();
    const initial = this.timeMs;
    this.timerId = setInterval(() => {
      const rem = initial - (Date.now() - this.startTs);
      if (rem <= 0) { this.timeMs = 0; this.endGame(); }
      else this.timeMs = rem;
    }, 50);
  }

  private nextElement(): void {
    const level = this.level;
    const colorsCount = level <= 5 ? 4 : level <= 10 ? 4 : level <= 15 ? 4 : 1;
    const figuresCount = level <= 5 ? 7 : level <= 10 ? 5 : level <= 15 ? 4 : 3;

    if (!this.hasPrev) {
      this.curShape = randInt(0, figuresCount - 1);
      this.curColor = randInt(0, colorsCount - 1);
      this.isSame = false;
    } else {
      const willSame = Math.random() < 0.5;
      if (willSame) {
        this.curShape = this.prevShape;
        this.curColor = this.prevColor;
        this.isSame = true;
      } else {
        // Different from previous
        let nc = this.prevColor;
        let ns = this.prevShape;
        if (colorsCount > 1) {
          while (nc === this.prevColor) nc = randInt(0, colorsCount - 1);
        }
        while (ns === this.prevShape) ns = randInt(0, figuresCount - 1);
        this.curShape = ns; this.curColor = nc; this.isSame = false;
      }
    }
  }

  private answer(saysSame: boolean): void {
    if (this.isGameOver || this.isPaused || this.showFeedback) return;
    const correct = saysSame === this.isSame;
    this.feedbackOk = correct;
    this.showFeedback = true;
    const fid = ++this.flowId;
    setTimeout(() => {
      if (fid !== this.flowId) return;
      this.showFeedback = false;
      if (correct) {
        this.prevShape = this.curShape; this.prevColor = this.curColor; this.hasPrev = true;
        this.level = this.level + 1;
        this.nextElement();
      } else {
        const nl = this.lives - 1;
        this.lives = nl;
        if (nl <= 0) this.endGame();
        else {
          this.prevShape = this.curShape; this.prevColor = this.curColor; this.hasPrev = true;
          this.nextElement();
        }
      }
    }, 700);
  }

  private endGame(): void { this.clearTimer(); this.isGameOver = true; }

  build() {
    Stack() {
      Column() {
        GameTopBar({ title: '像之前的吗', lives: this.lives, showLives: true,
          onPause: () => { if (!this.isGameOver) { this.clearTimer(); this.isPaused = true; } }
        })
        Row() {
          Text(`关卡 ${this.level}`).fontSize(14).fontColor('#616161')
          Blank()
          Text(`⏱ ${fmtTime(this.timeMs)}`).fontSize(14).fontColor(this.timeMs <= 5000 ? '#F44336' : '#424242')
        }.width('100%').padding({ left: 16, right: 16, bottom: 8 })

        Blank()

        // Previous element (if any)
        if (this.hasPrev) {
          Column({ space: 8 }) {
            Text('上一个').fontSize(13).fontColor('#9E9E9E')
            Text(SHAPES[this.prevShape]).fontSize(72).fontColor(COLORS[this.prevColor])
          }
        } else {
          Column({ space: 8 }) {
            Text(' ').fontSize(13)
            Column().width(80).height(80).backgroundColor('#EEEEEE').borderRadius(40)
          }
        }

        Text('↓').fontSize(28).fontColor('#9E9E9E').margin({ top: 20, bottom: 20 })

        // Current element
        Column({ space: 8 }) {
          Text('当前').fontSize(13).fontColor('#9E9E9E')
          Text(SHAPES[this.curShape]).fontSize(96).fontColor(COLORS[this.curColor])
        }

        // Feedback
        if (this.showFeedback) {
          Text(this.feedbackOk ? '✓ 正确' : '✗ 错误')
            .fontSize(22).fontWeight(FontWeight.Bold)
            .fontColor(this.feedbackOk ? '#4CAF50' : '#F44336').margin({ top: 12 })
        } else {
          Text(' ').fontSize(22).margin({ top: 12 })
        }

        Blank()

        Row({ space: 12 }) {
          Button({ type: ButtonType.Normal }) {
            Text('相同').fontSize(18).fontColor('#FFF').fontWeight(FontWeight.Bold)
          }.layoutWeight(1).height(64).backgroundColor('#4CAF50').borderRadius(14)
          .onClick(() => this.answer(true)).enabled(this.hasPrev)
          Button({ type: ButtonType.Normal }) {
            Text('不同').fontSize(18).fontColor('#FFF').fontWeight(FontWeight.Bold)
          }.layoutWeight(1).height(64).backgroundColor('#F44336').borderRadius(14)
          .onClick(() => this.answer(false)).enabled(this.hasPrev)
        }.width('92%').margin({ bottom: 24 })
      }.width('100%').height('100%').backgroundColor('#F5F5F5')

      GamePauseDialog({ visible: this.isPaused, gameName: '像之前的吗',
        onResume: () => { this.isPaused = false; this.startTimer(); },
        onRestart: () => { this.isPaused = false; this.startGame(); },
        onExit: () => router.back()
      })
      GameOverOverlay({ visible: this.isGameOver, score: this.level * 8, level: this.level,
        stars: stars3(this.level, 25, 15, 8),
        onPlayAgain: () => this.startGame(), onExit: () => router.back()
      })
    }.width('100%').height('100%')
  }
}
