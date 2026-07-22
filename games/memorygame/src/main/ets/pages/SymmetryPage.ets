import { router } from '@kit.ArkUI';
import { GamePauseDialog, GameOverOverlay, GameTopBar, stars3, fmtTime, randInt } from '../common/GameCommon';

// "对称" — tap the symmetric cells (game id=20)
const GAME_TIME_MS = 80000;

interface SCell { row: number; col: number; isSym: boolean; clicked: boolean; }

@Entry
@Component
struct SymmetryPage {
  @State private level: number = 1;
  @State private lives: number = 3;
  @State private timeMs: number = GAME_TIME_MS;
  @State private gridW: number = 4;
  @State private gridH: number = 3;
  @State private cells: SCell[] = [];
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
    this.newLevel();
    this.startTimer();
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

  private gridSize(level: number): number[] {
    if (level <= 2) return [4, 3];
    if (level <= 4) return [4, 4];
    if (level <= 8) return [6, 5];
    if (level <= 10) return [6, 6];
    if (level <= 13) return [8, 7];
    return [8, 8];
  }

  private newLevel(): void {
    const sz = this.gridSize(this.level);
    this.gridW = sz[0]; this.gridH = sz[1];
    const targetCount = Math.min(this.level + 2, Math.floor(this.gridW * this.gridH / 3));

    const symKeys: Set<string> = new Set();
    let tries = 0;
    while (symKeys.size < targetCount * 2 && tries < 200) {
      const col = randInt(0, Math.floor(this.gridW / 2) - 1);
      const row = randInt(0, this.gridH - 1);
      const k1 = `${row}_${col}`;
      const k2 = `${row}_${this.gridW - 1 - col}`;
      symKeys.add(k1); symKeys.add(k2);
      tries++;
    }
    const out: SCell[] = [];
    for (let r = 0; r < this.gridH; r++) {
      for (let c = 0; c < this.gridW; c++) {
        out.push({ row: r, col: c, isSym: symKeys.has(`${r}_${c}`), clicked: false });
      }
    }
    this.cells = out;
  }

  private tap(idx: number): void {
    if (this.isPaused || this.isGameOver || this.showFb) return;
    const cell = this.cells[idx];
    if (cell.clicked) return;
    const newCells: SCell[] = this.cells.map((c: SCell, i: number) =>
      i === idx ? { row: c.row, col: c.col, isSym: c.isSym, clicked: true } as SCell : c);
    this.cells = newCells;

    if (cell.isSym) {
      const allClicked = newCells.filter((c: SCell) => c.isSym).every((c: SCell) => c.clicked);
      if (allClicked) {
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

  private colsTpl(n: number): string {
    let s = '1fr';
    for (let i = 1; i < n; i++) s = s + ' 1fr';
    return s;
  }

  build() {
    Stack() {
      Column() {
        GameTopBar({ title: '对称', lives: this.lives, showLives: true,
          onPause: () => { if (!this.isGameOver) { if (this.timerId !== -1) clearInterval(this.timerId); this.timerId = -1; this.isPaused = true; } }
        })
        Row() {
          Text(`关卡 ${this.level}`).fontSize(14).fontColor('#616161')
          Blank()
          Text(`⏱ ${fmtTime(this.timeMs)}`).fontSize(14).fontColor(this.timeMs <= 15000 ? '#F44336' : '#424242')
        }.width('100%').padding({ left: 16, right: 16, bottom: 8 })

        Text('点击所有需要补全的对称单元格').fontSize(14).fontColor('#616161').margin({ bottom: 12 })

        Column() {
          Grid() {
            ForEach(this.cells, (c: SCell, idx: number) => {
              GridItem() {
                Column().width('100%').height('100%')
                  .backgroundColor(c.clicked ? (c.isSym ? '#4CAF50' : '#F44336') : '#FFFFFF')
                  .borderRadius(6)
                  .border({ width: 1, color: '#E0E0E0' })
                  .animation({ duration: 150, curve: Curve.EaseOut })
                  .onClick(() => this.tap(idx))
              }.aspectRatio(1)
            }, (c: SCell, idx: number) => `sym_${idx}_${this.level}`)
          }
          .columnsTemplate(this.colsTpl(this.gridW))
          .columnsGap(4).rowsGap(4)
          .width('100%')
        }.width('92%').layoutWeight(1)

        if (this.showFb) {
          Text(this.fbOk ? '✓ 正确' : '✗ 错误')
            .fontSize(20).fontWeight(FontWeight.Bold)
            .fontColor(this.fbOk ? '#4CAF50' : '#F44336').margin({ top: 12 })
        } else {
          Text(' ').fontSize(20).margin({ top: 12 })
        }
        Text(' ').height(16)
      }.width('100%').height('100%').backgroundColor('#F5F5F5')

      GamePauseDialog({ visible: this.isPaused, gameName: '对称',
        onResume: () => { this.isPaused = false; this.startTimer(); },
        onRestart: () => { this.isPaused = false; this.startGame(); },
        onExit: () => router.back()
      })
      GameOverOverlay({ visible: this.isGameOver, score: this.level * 12, level: this.level,
        stars: stars3(this.level, 15, 10, 5),
        onPlayAgain: () => this.startGame(), onExit: () => router.back()
      })
    }.width('100%').height('100%')
  }
}
