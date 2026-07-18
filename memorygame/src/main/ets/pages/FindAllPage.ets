import { router } from '@kit.ArkUI';
import { GamePauseDialog, GameOverOverlay, GameTopBar, stars3, fmtTime, shuffled, randInt } from '../common/GameCommon';

// "找到全部" — find all matching dual-color circles (game id=18)
const PALETTE: string[] = ['#E91E63', '#9C27B0', '#3F51B5', '#2196F3', '#00BCD4', '#4CAF50', '#FFEB3B', '#FF9800', '#FF5722', '#795548'];
const GAME_TIME_MS = 60000;

interface FACell { center: number; side: number; isTarget: boolean; clicked: boolean; empty: boolean; }
interface ColorPair { center: number; side: number; }

@Entry
@Component
struct FindAllPage {
  @State private level: number = 1;
  @State private lives: number = 3;
  @State private timeMs: number = GAME_TIME_MS;
  @State private cells: FACell[] = [];
  @State private targets: ColorPair[] = [];
  @State private gridR: number = 3;
  @State private gridC: number = 3;
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
    const elementCount = level + 2;
    const numGroups = level <= 5 ? 3 : level <= 10 ? 4 : 6;
    const guessCount = level <= 7 ? 1 : 2;

    let gr: number; let gc: number;
    if (level <= 5) { gr = 3; gc = 3; }
    else if (level <= 8) { gr = 4; gc = 4; }
    else if (level <= 12) { gr = 5; gc = 5; }
    else { gr = 5; gc = 7; }
    this.gridR = gr; this.gridC = gc;

    const palette = shuffled(this.range(PALETTE.length)).slice(0, 6);
    const pairs: ColorPair[] = [];
    for (const c of palette) for (const s of palette) if (c !== s) pairs.push({ center: c, side: s });
    const sel = shuffled(pairs).slice(0, numGroups);
    this.targets = sel.slice(0, guessCount);

    const positions = shuffled(this.range(gr * gc));
    const out: FACell[] = [];
    for (let i = 0; i < gr * gc; i++) {
      out.push({ center: 0, side: 0, isTarget: false, clicked: false, empty: true });
    }
    for (let i = 0; i < elementCount; i++) {
      const cp = sel[i % numGroups];
      const isT = this.targets.some((t: ColorPair) => t.center === cp.center && t.side === cp.side);
      out[positions[i]] = { center: cp.center, side: cp.side, isTarget: isT, clicked: false, empty: false };
    }
    this.cells = out;
    this.showFb = false;
  }

  private onTap(idx: number): void {
    if (this.isPaused || this.isGameOver || this.showFb) return;
    const c = this.cells[idx];
    if (c.empty || c.clicked) return;
    const newCells: FACell[] = this.cells.map((x: FACell, i: number) =>
      i === idx ? ({ center: x.center, side: x.side, isTarget: x.isTarget, clicked: true, empty: x.empty } as FACell) : x);
    this.cells = newCells;

    if (c.isTarget) {
      const allFound = newCells.filter((x: FACell) => x.isTarget).every((x: FACell) => x.clicked);
      if (allFound) {
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
      }, 800);
    }
  }

  private endGame(): void { if (this.timerId !== -1) clearInterval(this.timerId); this.timerId = -1; this.isGameOver = true; }
  private range(n: number): number[] { const a: number[] = []; for (let i = 0; i < n; i++) a.push(i); return a; }
  private colsTpl(n: number): string { let s = '1fr'; for (let i = 1; i < n; i++) s = s + ' 1fr'; return s; }

  build() {
    Stack() {
      Column() {
        GameTopBar({ title: '找到全部', lives: this.lives, showLives: true,
          onPause: () => { if (!this.isGameOver) { if (this.timerId !== -1) clearInterval(this.timerId); this.timerId = -1; this.isPaused = true; } }
        })
        Row() {
          Text(`关卡 ${this.level}`).fontSize(14).fontColor('#616161')
          Blank()
          Text(`⏱ ${fmtTime(this.timeMs)}`).fontSize(14).fontColor(this.timeMs <= 10000 ? '#F44336' : '#424242')
        }.width('100%').padding({ left: 16, right: 16, bottom: 8 })

        // Target pattern preview
        Row({ space: 12 }) {
          Text('目标：').fontSize(14).fontColor('#616161')
          ForEach(this.targets, (t: ColorPair, i: number) => {
            Stack() {
              Column().width(36).height(36).borderRadius(18).backgroundColor(PALETTE[t.side])
              Column().width(20).height(20).borderRadius(10).backgroundColor(PALETTE[t.center])
            }
          }, (t: ColorPair, i: number) => `fa_t_${i}_${t.center}_${t.side}`)
        }.margin({ bottom: 12 })

        Column() {
          Grid() {
            ForEach(this.cells, (c: FACell, idx: number) => {
              GridItem() {
                if (c.empty) {
                  Column().width('100%').height('100%')
                } else {
                  Stack() {
                    Column().width('100%').height('100%').borderRadius(8)
                      .backgroundColor(c.clicked ? '#E8F5E9' : '#FFFFFF')
                      .border({ width: c.clicked ? 2 : 1, color: c.clicked ? '#4CAF50' : '#E0E0E0' })
                    Stack() {
                      Column().width(40).height(40).borderRadius(20).backgroundColor(PALETTE[c.side])
                      Column().width(22).height(22).borderRadius(11).backgroundColor(PALETTE[c.center])
                    }
                  }.width('100%').height('100%').onClick(() => this.onTap(idx))
                }
              }.aspectRatio(1)
            }, (c: FACell, idx: number) => `fa_${idx}_${this.level}_${c.center}_${c.side}`)
          }
          .columnsTemplate(this.colsTpl(this.gridC))
          .columnsGap(6).rowsGap(6).width('100%')
        }.width('92%').layoutWeight(1)

        if (this.showFb) {
          Text(this.fbOk ? '✓ 全部找到！' : '✗ 错误')
            .fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor(this.fbOk ? '#4CAF50' : '#F44336').margin({ top: 8 })
        } else {
          Text(' ').fontSize(18).margin({ top: 8 })
        }
        Text(' ').height(16)
      }.width('100%').height('100%').backgroundColor('#F5F5F5')

      GamePauseDialog({ visible: this.isPaused, gameName: '找到全部',
        onResume: () => { this.isPaused = false; this.startTimer(); },
        onRestart: () => { this.isPaused = false; this.startGame(); },
        onExit: () => router.back()
      })
      GameOverOverlay({ visible: this.isGameOver, score: this.level * 14, level: this.level,
        stars: stars3(this.level, 18, 12, 6),
        onPlayAgain: () => this.startGame(), onExit: () => router.back()
      })
    }.width('100%').height('100%')
  }
}
