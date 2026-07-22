import { router } from '@kit.ArkUI';
import { GamePauseDialog, GameOverOverlay, GameTopBar, stars3, randInt } from '../common/GameCommon';

// "更多更少" — compare two math expressions (game id=11)
interface Cmp { e1: string; e2: string; result: number; } // result: 1 = e1>e2, 0 = equal, -1 = e1<e2

function compare(a: number, b: number): number { return a > b ? 1 : a < b ? -1 : 0; }

function gen(level: number): Cmp {
  if (level <= 2) {
    const x1 = randInt(1, 10); const x2 = randInt(1, 10);
    return { e1: `${x1}`, e2: `${x2}`, result: compare(x1, x2) };
  }
  if (level <= 3) {
    const x1 = randInt(1, 10); const y1 = randInt(1, 10); const x2 = randInt(1, 10); const y2 = randInt(1, 10);
    return { e1: `${x1} + ${y1}`, e2: `${x2} + ${y2}`, result: compare(x1 + y1, x2 + y2) };
  }
  if (level <= 7) {
    const lo = level <= 5 ? 10 : 15; const hi = level <= 5 ? 20 : 30;
    const x1 = randInt(lo, hi); const y1 = randInt(4, 12);
    const f1 = randInt(1, 5); const f2 = randInt(1, 3);
    const s1 = Math.random() < 0.5; const s2 = !s1;
    const x2 = s1 ? x1 + f1 : x1 - f1; const y2 = s2 ? y1 + f2 : y1 - f2;
    const useAdd = Math.random() < 0.5;
    const r1 = useAdd ? x1 + y1 : x1 - y1;
    const r2 = useAdd ? x2 + y2 : x2 - y2;
    const op = useAdd ? '+' : '-';
    return { e1: `${x1} ${op} ${y1}`, e2: `${x2} ${op} ${y2}`, result: compare(r1, r2) };
  }
  if (level <= 13) {
    const x1 = randInt(7, 13); const y1 = randInt(6, 12);
    const f1 = randInt(1, 3); const f2 = randInt(1, 3);
    const s1 = Math.random() < 0.5; const s2 = !s1;
    const x2 = s1 ? x1 + f1 : x1 - f1; const y2 = s2 ? y1 + f2 : y1 - f2;
    return { e1: `${x1} × ${y1}`, e2: `${x2} × ${y2}`, result: compare(x1 * y1, x2 * y2) };
  }
  // Higher levels: complex expressions
  const x1 = randInt(30, 80); const y1 = randInt(5, 12); const z1 = randInt(5, 9);
  const x2 = x1 + randInt(-5, 5); const y2 = y1 + randInt(-3, 3); const z2 = z1 + randInt(-2, 2);
  const op = Math.random() < 0.5 ? '+' : '-';
  const r1 = op === '+' ? x1 + y1 * z1 : x1 - y1 * z1;
  const r2 = op === '+' ? x2 + y2 * z2 : x2 - y2 * z2;
  return { e1: `${x1} ${op} ${y1} × ${z1}`, e2: `${x2} ${op} ${y2} × ${z2}`, result: compare(r1, r2) };
}

@Entry
@Component
struct MoreLessPage {
  @State private level: number = 1;
  @State private score: number = 0;
  @State private qTimeMs: number = 6000;
  @State private cur: Cmp = { e1: '', e2: '', result: 0 };
  @State private picked: number = 99;
  @State private showFb: boolean = false;
  @State private fbOk: boolean = false;
  @State private isPaused: boolean = false;
  @State private isGameOver: boolean = false;
  private qTimerId: number = -1;
  private qStart: number = 0;
  private qLimit: number = 6000;
  private flowId: number = 0;

  aboutToAppear(): void { this.startGame(); }
  aboutToDisappear(): void { if (this.qTimerId !== -1) clearInterval(this.qTimerId); this.flowId++; }

  private startGame(): void {
    this.flowId++;
    this.level = 1; this.score = 0;
    this.isPaused = false; this.isGameOver = false; this.showFb = false;
    this.nextQ();
  }

  private nextQ(): void {
    this.cur = gen(this.level);
    this.picked = 99;
    this.showFb = false;
    this.qLimit = this.level <= 10 ? 6000 : 10000;
    this.qTimeMs = this.qLimit;
    if (this.qTimerId !== -1) clearInterval(this.qTimerId);
    this.qStart = Date.now();
    this.qTimerId = setInterval(() => {
      const rem = this.qLimit - (Date.now() - this.qStart);
      if (rem <= 0) {
        this.qTimeMs = 0;
        if (this.qTimerId !== -1) { clearInterval(this.qTimerId); this.qTimerId = -1; }
        this.endGame();
      } else this.qTimeMs = rem;
    }, 50);
  }

  private answer(choice: number): void { // -1=less, 0=equal, 1=greater
    if (this.isGameOver || this.isPaused || this.showFb) return;
    if (this.qTimerId !== -1) { clearInterval(this.qTimerId); this.qTimerId = -1; }
    this.picked = choice;
    const ok = choice === this.cur.result;
    this.fbOk = ok; this.showFb = true;
    const fid = ++this.flowId;
    setTimeout(() => {
      if (fid !== this.flowId) return;
      if (ok) { this.score = this.score + 8 + this.level * 2; this.level = this.level + 1; this.nextQ(); }
      else this.endGame();
    }, 700);
  }

  private endGame(): void { if (this.qTimerId !== -1) clearInterval(this.qTimerId); this.qTimerId = -1; this.isGameOver = true; }

  build() {
    Stack() {
      Column() {
        GameTopBar({ title: '更多更少', scoreText: `分: ${this.score}`,
          onPause: () => { if (!this.isGameOver) { if (this.qTimerId !== -1) clearInterval(this.qTimerId); this.qTimerId = -1; this.isPaused = true; } }
        })
        Row() {
          Text(`关卡 ${this.level}`).fontSize(14).fontColor('#616161')
        }.width('100%').padding({ left: 16, bottom: 8 })

        Stack({ alignContent: Alignment.Start }) {
          Row().width('100%').height(4).backgroundColor('#E0E0E0').borderRadius(2)
          Row().width(`${(this.qTimeMs / this.qLimit * 100).toFixed(1)}%`).height(4)
            .backgroundColor(this.qTimeMs > 2000 ? '#FF9800' : '#F44336').borderRadius(2)
        }.width('90%').margin({ bottom: 24 })

        Blank()

        Column({ space: 24 }) {
          Stack() {
            Column().width('80%').height(80).backgroundColor('#FFFFFF').borderRadius(16).border({ width: 2, color: '#BBDEFB' })
            Text(this.cur.e1).fontSize(32).fontWeight(FontWeight.Bold).fontColor('#1976D2')
          }
          Text('VS').fontSize(20).fontColor('#9E9E9E').fontWeight(FontWeight.Bold)
          Stack() {
            Column().width('80%').height(80).backgroundColor('#FFFFFF').borderRadius(16).border({ width: 2, color: '#FFCCBC' })
            Text(this.cur.e2).fontSize(32).fontWeight(FontWeight.Bold).fontColor('#E64A19')
          }
        }.width('100%')

        if (this.showFb) {
          Text(this.fbOk ? '✓ 正确' : '✗ 错误')
            .fontSize(22).fontWeight(FontWeight.Bold)
            .fontColor(this.fbOk ? '#4CAF50' : '#F44336').margin({ top: 20 })
        } else {
          Text(' ').fontSize(22).margin({ top: 20 })
        }

        Blank()

        Row({ space: 10 }) {
          Button({ type: ButtonType.Normal }) {
            Text('左边大').fontSize(15).fontColor('#FFF').fontWeight(FontWeight.Bold)
          }.layoutWeight(1).height(56).backgroundColor('#1976D2').borderRadius(14).onClick(() => this.answer(1))
          Button({ type: ButtonType.Normal }) {
            Text('相等').fontSize(15).fontColor('#FFF').fontWeight(FontWeight.Bold)
          }.layoutWeight(1).height(56).backgroundColor('#757575').borderRadius(14).onClick(() => this.answer(0))
          Button({ type: ButtonType.Normal }) {
            Text('右边大').fontSize(15).fontColor('#FFF').fontWeight(FontWeight.Bold)
          }.layoutWeight(1).height(56).backgroundColor('#E64A19').borderRadius(14).onClick(() => this.answer(-1))
        }.width('92%').margin({ bottom: 24 })
      }.width('100%').height('100%').backgroundColor('#F5F5F5')

      GamePauseDialog({ visible: this.isPaused, gameName: '更多更少',
        onResume: () => { this.isPaused = false; this.nextQ(); },
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
