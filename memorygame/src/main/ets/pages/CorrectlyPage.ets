import { router } from '@kit.ArkUI';
import { GamePauseDialog, GameOverOverlay, GameTopBar, stars3, fmtTime, randInt } from '../common/GameCommon';

// "正确吗" — judge if a math equation is correct (game id=25)
const GAME_TIME_MS = 60000;

interface Eqn { text: string; correct: boolean; }

function genEqn(level: number): Eqn {
  let expr = '';
  let result = 0;
  if (level <= 3) {
    const a = randInt(4, 10); const b = randInt(1, 7);
    if (Math.random() < 0.5) { expr = `${a} + ${b} = `; result = a + b; }
    else { expr = `${a} - ${b} = `; result = a - b; }
  } else if (level <= 5) {
    const a = randInt(9, 25); const b = randInt(5, 15);
    if (Math.random() < 0.5) { expr = `${a} + ${b} = `; result = a + b; }
    else { expr = `${a} - ${b} = `; result = a - b; }
  } else if (level <= 7) {
    const a = randInt(2, 8); const b = randInt(3, 6);
    expr = `${a} × ${b} = `; result = a * b;
  } else if (level <= 11) {
    const a = randInt(4, 12); const b = randInt(2, 6); const c = randInt(3, 8);
    const op1 = Math.random() < 0.5 ? '+' : '-';
    const op2 = Math.random() < 0.5 ? '+' : '-';
    const r1 = op1 === '+' ? a + b : a - b;
    result = op2 === '+' ? r1 + c : r1 - c;
    expr = `${a} ${op1} ${b} ${op2} ${c} = `;
  } else if (level <= 15) {
    const a = randInt(9, 20); const b = randInt(2, 9); const c = randInt(15, 30);
    const op = Math.random() < 0.5 ? '+' : '-';
    result = op === '+' ? a * b + c : a * b - c;
    expr = `${a} × ${b} ${op} ${c} = `;
  } else {
    const a = randInt(6, 12); const b = randInt(7, 15); const c = randInt(5, 11); const d = randInt(8, 16);
    const op = Math.random() < 0.5 ? '+' : '-';
    result = op === '+' ? a * b + c * d : a * b - c * d;
    expr = `${a} × ${b} ${op} ${c} × ${d} = `;
  }
  const isCorrect = Math.random() < 0.5;
  const z = randInt(1, 3);
  const display = isCorrect ? result : result + (Math.random() < 0.5 ? z : -z);
  return { text: expr + display, correct: isCorrect };
}

function levelTimeLimitMs(level: number): number {
  if (level <= 5) return 5000;
  if (level <= 10) return 4500;
  if (level <= 15) return 4000;
  return 3500;
}

@Entry
@Component
struct CorrectlyPage {
  @State private level: number = 1;
  @State private score: number = 0;
  @State private lives: number = 3;
  @State private timeMs: number = GAME_TIME_MS;
  @State private qTimeMs: number = 5000;
  @State private eqn: Eqn = { text: '', correct: true };
  @State private showFb: boolean = false;
  @State private fbOk: boolean = false;
  @State private isPaused: boolean = false;
  @State private isGameOver: boolean = false;
  private timerId: number = -1;
  private qTimerId: number = -1;
  private startTs: number = 0;
  private qStartTs: number = 0;
  private qLimit: number = 5000;
  private flowId: number = 0;

  aboutToAppear(): void { this.startGame(); }
  aboutToDisappear(): void { this.clearTimers(); this.flowId++; }

  private clearTimers(): void {
    if (this.timerId !== -1) { clearInterval(this.timerId); this.timerId = -1; }
    if (this.qTimerId !== -1) { clearInterval(this.qTimerId); this.qTimerId = -1; }
  }

  private startGame(): void {
    this.flowId++;
    this.level = 1; this.score = 0; this.lives = 3; this.timeMs = GAME_TIME_MS;
    this.isPaused = false; this.isGameOver = false; this.showFb = false;
    this.nextQuestion();
    this.startGameTimer();
  }

  private startGameTimer(): void {
    if (this.timerId !== -1) clearInterval(this.timerId);
    this.startTs = Date.now();
    const initial = this.timeMs;
    this.timerId = setInterval(() => {
      const rem = initial - (Date.now() - this.startTs);
      if (rem <= 0) { this.timeMs = 0; this.endGame(); }
      else this.timeMs = rem;
    }, 200);
  }

  private startQTimer(): void {
    if (this.qTimerId !== -1) clearInterval(this.qTimerId);
    this.qStartTs = Date.now();
    this.qLimit = levelTimeLimitMs(this.level);
    this.qTimeMs = this.qLimit;
    this.qTimerId = setInterval(() => {
      const rem = this.qLimit - (Date.now() - this.qStartTs);
      if (rem <= 0) { this.qTimeMs = 0; this.answer(!this.eqn.correct); }
      else this.qTimeMs = rem;
    }, 80);
  }

  private nextQuestion(): void {
    this.eqn = genEqn(this.level);
    this.showFb = false;
    this.startQTimer();
  }

  private answer(playerSaysCorrect: boolean): void {
    if (this.isGameOver || this.isPaused || this.showFb) return;
    if (this.qTimerId !== -1) { clearInterval(this.qTimerId); this.qTimerId = -1; }
    const ok = playerSaysCorrect === this.eqn.correct;
    this.fbOk = ok; this.showFb = true;
    const fid = ++this.flowId;
    if (ok) {
      this.score = this.score + 4 + this.level * 2;
      this.level = this.level + 1;
      setTimeout(() => {
        if (fid !== this.flowId) return;
        this.nextQuestion();
      }, 400);
    } else {
      const nl = this.lives - 1; this.lives = nl;
      setTimeout(() => {
        if (fid !== this.flowId) return;
        if (nl <= 0) this.endGame(); else this.nextQuestion();
      }, 700);
    }
  }

  private endGame(): void { this.clearTimers(); this.isGameOver = true; }

  build() {
    Stack() {
      Column() {
        GameTopBar({ title: '正确吗', lives: this.lives, showLives: true,
          onPause: () => { if (!this.isGameOver) { this.clearTimers(); this.isPaused = true; } }
        })
        Row() {
          Text(`关卡 ${this.level}`).fontSize(14).fontColor('#616161')
          Blank()
          Text(`分: ${this.score}`).fontSize(14).fontColor('#673AB7').fontWeight(FontWeight.Bold)
          Text('   ').fontSize(14)
          Text(`⏱ ${fmtTime(this.timeMs)}`).fontSize(14).fontColor(this.timeMs <= 10000 ? '#F44336' : '#424242')
        }.width('100%').padding({ left: 16, right: 16, bottom: 8 })

        // Question timer bar
        Stack({ alignContent: Alignment.Start }) {
          Row().width('100%').height(4).backgroundColor('#E0E0E0').borderRadius(2)
          Row().width(`${(this.qTimeMs / this.qLimit * 100).toFixed(1)}%`).height(4)
            .backgroundColor(this.qTimeMs > 1500 ? '#FF9800' : '#F44336').borderRadius(2)
        }.width('90%').margin({ bottom: 16 })

        Blank()

        // Equation
        Stack() {
          Column().width('90%').height(160).backgroundColor('#FFFFFF').borderRadius(20)
            .border({ width: 2, color: '#E0E0E0' })
          Text(this.eqn.text).fontSize(36).fontWeight(FontWeight.Bold).fontColor('#212121')
        }

        if (this.showFb) {
          Text(this.fbOk ? '✓ 答对了' : '✗ 答错了')
            .fontSize(22).fontWeight(FontWeight.Bold)
            .fontColor(this.fbOk ? '#4CAF50' : '#F44336').margin({ top: 16 })
        } else {
          Text(' ').fontSize(22).margin({ top: 16 })
        }

        Blank()

        Row({ space: 12 }) {
          Button({ type: ButtonType.Normal }) {
            Text('✓ 正确').fontSize(18).fontColor('#FFF').fontWeight(FontWeight.Bold)
          }.layoutWeight(1).height(70).backgroundColor('#4CAF50').borderRadius(14)
          .onClick(() => this.answer(true))
          Button({ type: ButtonType.Normal }) {
            Text('✗ 错误').fontSize(18).fontColor('#FFF').fontWeight(FontWeight.Bold)
          }.layoutWeight(1).height(70).backgroundColor('#F44336').borderRadius(14)
          .onClick(() => this.answer(false))
        }.width('92%').margin({ bottom: 24 })
      }.width('100%').height('100%').backgroundColor('#F5F5F5')

      GamePauseDialog({ visible: this.isPaused, gameName: '正确吗',
        onResume: () => { this.isPaused = false; this.startGameTimer(); this.startQTimer(); },
        onRestart: () => { this.isPaused = false; this.startGame(); },
        onExit: () => router.back()
      })
      GameOverOverlay({ visible: this.isGameOver, score: this.score, level: this.level,
        stars: stars3(this.level, 20, 12, 6),
        onPlayAgain: () => this.startGame(), onExit: () => router.back()
      })
    }.width('100%').height('100%')
  }
}
