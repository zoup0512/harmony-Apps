import { router } from '@kit.ArkUI';
import { GamePauseDialog, GameOverOverlay, GameTopBar, stars3, fmtTime, shuffled, randInt } from '../common/GameCommon';

// "排序数字" — tap numbers in ascending order (game id=13)
const PALETTE: string[] = ['#E91E63', '#9C27B0', '#3F51B5', '#2196F3', '#00BCD4', '#4CAF50', '#FF9800', '#FF5722'];
const GAME_TIME_MS = 60000;

interface STDElem { num: number; color: number; order: number; clicked: boolean; }

@Entry
@Component
struct SortTheDigitsPage {
  @State private level: number = 1;
  @State private lives: number = 3;
  @State private timeMs: number = GAME_TIME_MS;
  @State private elems: STDElem[] = [];
  @State private nextOrder: number = 0;
  @State private showFb: boolean = false;
  @State private fbOk: boolean = false;
  @State private isPaused: boolean = false;
  @State private isGameOver: boolean = false;
  private timerId: number = -1;
  private startTs: number = 0;
  private flowId: number = 0;

  aboutToAppear(): void { this.startGame(); }
  aboutToDisappear(): void { if (this.timerId !== -1) clearInterval(this.timerId); this.flowId++; }

  private startGame(): void {
    this.flowId++;
    this.level = 1; this.lives = 3; this.timeMs = GAME_TIME_MS;
    this.isPaused = false; this.isGameOver = false; this.showFb = false;
    this.startTimer();
    this.newLevel();
  }

  private startTimer(): void {
    if (this.timerId !== -1) clearInterval(this.timerId);
    this.startTs = Date.now();
    const initial = this.timeMs;
    this.timerId = setInterval(() => {
      const rem = initial - (Date.now() - this.startTs);
      if (rem <= 0) { this.timeMs = 0; this.endGame(); }
      else this.timeMs = rem;
    }, 100);
  }

  private newLevel(): void {
    const level = this.level;
    let cnt: number; let colorN: number; let lo: number; let hi: number;
    if (level <= 3) { cnt = 3; colorN = 1; lo = 1; hi = 9; }
    else if (level <= 10) { cnt = 4; colorN = 2; lo = 1; hi = 15; }
    else if (level <= 15) { cnt = 5; colorN = 3; lo = -5; hi = 20; }
    else { cnt = 6; colorN = 4; lo = -10; hi = 30; }

    const pool: number[] = [];
    for (let i = lo; i <= hi; i++) pool.push(i);
    const nums = shuffled(pool).slice(0, cnt);
    const sorted = [...nums].sort((a: number, b: number) => a - b);
    const palette = shuffled(this.range(PALETTE.length)).slice(0, colorN);
    const out: STDElem[] = nums.map((n: number, i: number) => ({
      num: n, color: palette[i % palette.length], order: sorted.indexOf(n), clicked: false
    } as STDElem));
    this.elems = shuffled(out);
    this.nextOrder = 0;
    this.showFb = false;
  }

  private onTap(idx: number): void {
    if (this.isPaused || this.isGameOver || this.showFb) return;
    const e = this.elems[idx];
    if (e.clicked) return;
    if (e.order === this.nextOrder) {
      const newE: STDElem[] = this.elems.map((x: STDElem, i: number) =>
        i === idx ? ({ num: x.num, color: x.color, order: x.order, clicked: true } as STDElem) : x);
      this.elems = newE;
      this.nextOrder = this.nextOrder + 1;
      if (this.nextOrder >= this.elems.length) {
        this.fbOk = true; this.showFb = true;
        const fid = ++this.flowId;
        setTimeout(() => { if (fid === this.flowId) { this.showFb = false; this.level = this.level + 1; this.newLevel(); } }, 700);
      }
    } else {
      this.fbOk = false; this.showFb = true;
      const fid = ++this.flowId;
      setTimeout(() => {
        if (fid !== this.flowId) return;
        this.showFb = false;
        const nl = this.lives - 1; this.lives = nl;
        if (nl <= 0) this.endGame(); else this.newLevel();
      }, 700);
    }
  }

  private endGame(): void { if (this.timerId !== -1) clearInterval(this.timerId); this.timerId = -1; this.isGameOver = true; }
  private range(n: number): number[] { const a: number[] = []; for (let i = 0; i < n; i++) a.push(i); return a; }

  build() {
    Stack() {
      Column() {
        GameTopBar({ title: '排序数字', lives: this.lives, showLives: true,
          onPause: () => { if (!this.isGameOver) { if (this.timerId !== -1) clearInterval(this.timerId); this.timerId = -1; this.isPaused = true; } }
        })
        Row() {
          Text(`关卡 ${this.level}`).fontSize(14).fontColor('#616161')
          Blank()
          Text(`⏱ ${fmtTime(this.timeMs)}`).fontSize(14).fontColor(this.timeMs <= 10000 ? '#F44336' : '#424242')
        }.width('100%').padding({ left: 16, right: 16, bottom: 8 })

        Text(`从小到大依次点击 (${this.nextOrder}/${this.elems.length})`)
          .fontSize(15).fontColor('#616161').margin({ bottom: 16 })

        Column() {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center, alignItems: ItemAlign.Center }) {
            ForEach(this.elems, (e: STDElem, idx: number) => {
              Button({ type: ButtonType.Normal }) {
                Text(`${e.num}`).fontSize(28).fontColor('#FFF').fontWeight(FontWeight.Bold)
              }.width(72).height(72).borderRadius(36)
              .backgroundColor(e.clicked ? '#9E9E9E' : PALETTE[e.color])
              .opacity(e.clicked ? 0.5 : 1.0)
              .margin(8)
              .onClick(() => this.onTap(idx))
              .enabled(!e.clicked)
            }, (e: STDElem, idx: number) => `std_${idx}_${this.level}_${e.num}`)
          }
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)

        if (this.showFb) {
          Text(this.fbOk ? '✓ 完美排序！' : '✗ 顺序错误')
            .fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor(this.fbOk ? '#4CAF50' : '#F44336').margin({ top: 8 })
        } else {
          Text(' ').fontSize(18).margin({ top: 8 })
        }
        Text(' ').height(16)
      }.width('100%').height('100%').backgroundColor('#F5F5F5')

      GamePauseDialog({ visible: this.isPaused, gameName: '排序数字',
        onResume: () => { this.isPaused = false; this.startTimer(); },
        onRestart: () => { this.isPaused = false; this.startGame(); },
        onExit: () => router.back()
      })
      GameOverOverlay({ visible: this.isGameOver, score: this.level * 12, level: this.level,
        stars: stars3(this.level, 20, 12, 6),
        onPlayAgain: () => this.startGame(), onExit: () => router.back()
      })
    }.width('100%').height('100%')
  }
}
