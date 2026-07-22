import { router } from '@kit.ArkUI';
import { GamePauseDialog, GameOverOverlay, GameTopBar, stars3, fmtTime, randInt } from '../common/GameCommon';

// Stroop effect game (game id=26)
const COLOR_NAMES: string[] = ['红', '蓝', '绿', '黄', '紫', '橙'];
const COLOR_HEX: string[] = ['#F44336', '#2196F3', '#4CAF50', '#FFEB3B', '#9C27B0', '#FF9800'];
const GAME_TIME_MS = 30000;

@Entry
@Component
struct ColorsPage {
  @State private level: number = 1;
  @State private score: number = 0;
  @State private timeMs: number = GAME_TIME_MS;
  @State private wordIdx: number = 0;
  @State private colorIdx: number = 0;
  @State private isMatch: boolean = false;
  @State private showHint: boolean = false;
  @State private hintCorrect: boolean = true;
  @State private isPaused: boolean = false;
  @State private isGameOver: boolean = false;
  private timerId: number = -1;
  private startTs: number = 0;

  aboutToAppear(): void { this.startGame(); }
  aboutToDisappear(): void { this.clearTimer(); }

  private clearTimer(): void { if (this.timerId !== -1) { clearInterval(this.timerId); this.timerId = -1; } }

  private startGame(): void {
    this.level = 1; this.score = 0; this.timeMs = GAME_TIME_MS;
    this.isPaused = false; this.isGameOver = false;
    this.newQuestion();
    this.startTimer();
  }

  private startTimer(): void {
    this.clearTimer();
    this.startTs = Date.now();
    const initial = this.timeMs;
    this.timerId = setInterval(() => {
      const elapsed = Date.now() - this.startTs;
      const rem = initial - elapsed;
      if (rem <= 0) { this.timeMs = 0; this.endGame(); }
      else this.timeMs = rem;
    }, 50);
  }

  private newQuestion(): void {
    this.wordIdx = randInt(0, COLOR_NAMES.length - 1);
    this.colorIdx = randInt(0, COLOR_HEX.length - 1);
    this.isMatch = this.wordIdx === this.colorIdx;
  }

  private answer(playerSaysMatch: boolean): void {
    if (this.isGameOver || this.isPaused) return;
    const correct = playerSaysMatch === this.isMatch;
    if (correct) {
      this.score = this.score + 8;
      this.level = this.level + 1;
      this.hintCorrect = true;
      this.showHint = true;
      setTimeout(() => { this.showHint = false; }, 300);
      this.newQuestion();
    } else {
      this.hintCorrect = false;
      this.showHint = true;
      setTimeout(() => { this.endGame(); }, 400);
    }
  }

  private endGame(): void { this.clearTimer(); this.isGameOver = true; }

  build() {
    Stack() {
      Column() {
        GameTopBar({ title: '颜色', scoreText: `分: ${this.score}`,
          onPause: () => { if (!this.isGameOver) { this.clearTimer(); this.isPaused = true; } }
        })
        Row() {
          Text(`关卡 ${this.level}`).fontSize(14).fontColor('#616161')
          Blank()
          Text(`⏱ ${fmtTime(this.timeMs)}`).fontSize(14).fontColor(this.timeMs <= 5000 ? '#F44336' : '#424242')
        }.width('100%').padding({ left: 16, right: 16, bottom: 8 })
        Stack({ alignContent: Alignment.Start }) {
          Row().width('100%').height(4).backgroundColor('#E0E0E0').borderRadius(2)
          Row().width(`${(this.timeMs / GAME_TIME_MS * 100).toFixed(1)}%`).height(4)
            .backgroundColor(this.timeMs > 10000 ? '#4CAF50' : '#F44336').borderRadius(2)
        }.width('90%').margin({ bottom: 12 })

        Column({ space: 12 }) {
          Text('词的颜色和词的意思').fontSize(14).fontColor('#757575')
          Text('是否一致？').fontSize(14).fontColor('#757575')
        }.padding({ top: 8, bottom: 24 })

        // Word display
        Stack() {
          Column().width(280).height(140).backgroundColor('#FAFAFA').borderRadius(20)
            .border({ width: 2, color: '#E0E0E0' })
          Text(COLOR_NAMES[this.wordIdx])
            .fontSize(64).fontWeight(FontWeight.Bold).fontColor(COLOR_HEX[this.colorIdx])
        }

        // Hint
        if (this.showHint) {
          Text(this.hintCorrect ? '✓ 正确' : '✗ 错误')
            .fontSize(20).fontWeight(FontWeight.Bold)
            .fontColor(this.hintCorrect ? '#4CAF50' : '#F44336')
            .margin({ top: 16 })
        } else {
          Text(' ').fontSize(20).margin({ top: 16 })
        }

        Blank()

        Row({ space: 12 }) {
          Button({ type: ButtonType.Normal }) {
            Text('一致').fontSize(18).fontColor('#FFF').fontWeight(FontWeight.Bold)
          }.layoutWeight(1).height(70).backgroundColor('#4CAF50').borderRadius(14)
          .onClick(() => this.answer(true))
          Button({ type: ButtonType.Normal }) {
            Text('不一致').fontSize(18).fontColor('#FFF').fontWeight(FontWeight.Bold)
          }.layoutWeight(1).height(70).backgroundColor('#F44336').borderRadius(14)
          .onClick(() => this.answer(false))
        }.width('92%').margin({ bottom: 24 })
      }
      .width('100%').height('100%').backgroundColor('#F5F5F5')

      GamePauseDialog({
        visible: this.isPaused, gameName: '颜色',
        onResume: () => { this.isPaused = false; this.startTimer(); },
        onRestart: () => { this.isPaused = false; this.startGame(); },
        onExit: () => router.back()
      })

      GameOverOverlay({
        visible: this.isGameOver, score: this.score, level: this.level,
        stars: stars3(this.level, 30, 20, 10),
        onPlayAgain: () => this.startGame(),
        onExit: () => router.back()
      })
    }.width('100%').height('100%')
  }
}
