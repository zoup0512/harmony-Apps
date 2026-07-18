import { router } from '@kit.ArkUI';
import { GamePauseDialog, GameOverOverlay, GameTopBar, stars3, fmtTime, randInt, repStr } from '../common/GameCommon';

// "激光" — place mirrors (/ and \) to redirect a laser from start to end (game id=21)
// Cell types: 0=empty, 1=busy(obstacle), 2=start, 3=end, 4=slash(/), 5=backslash(\)
const GAME_TIME_MS = 80000;

interface LXY { x: number; y: number; }

@Entry
@Component
struct LaserPage {
  @State private level: number = 1;
  @State private lives: number = 3;
  @State private timeMs: number = GAME_TIME_MS;
  @State private gridSize: number = 6;
  @State private grid: number[] = [];
  @State private start: LXY = { x: 0, y: 0 };
  @State private startDir: number = 1; // 0=up,1=right,2=down,3=left (incoming direction into grid)
  @State private end: LXY = { x: 0, y: 0 };
  @State private mirrorsLeft: number = 2;
  @State private mirrorsTotal: number = 2;
  @State private laserCells: number[] = [];
  @State private isWon: boolean = false;
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
    this.isPaused = false; this.isGameOver = false; this.isWon = false;
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

  private gridSizeForLevel(level: number): number {
    if (level <= 3) return 6;
    if (level <= 5) return 7;
    return 8;
  }

  private mirrorsForLevel(level: number): number {
    if (level <= 1) return 1;
    if (level <= 3) return 2;
    if (level <= 7) return 3;
    return 4;
  }

  private busyForLevel(level: number): number {
    if (level === 1) return 0;
    if (level === 2) return 1;
    if (level === 3) return 2;
    if (level <= 5) return level;
    if (level <= 9) return level + 2;
    return 15;
  }

  private newLevel(): void {
    const gs = this.gridSizeForLevel(this.level);
    this.gridSize = gs;
    const total = gs * gs;
    const g: number[] = [];
    for (let i = 0; i < total; i++) g.push(0);

    // Pick start edge (0=top, 1=right, 2=bottom, 3=left) and end on opposite
    const se = randInt(0, 3);
    const ee = (se + 2) % 4;
    let sx = 0; let sy = 0; let ex = 0; let ey = 0;
    if (se === 0) { sx = randInt(1, gs - 2); sy = 0; }
    else if (se === 1) { sx = gs - 1; sy = randInt(1, gs - 2); }
    else if (se === 2) { sx = randInt(1, gs - 2); sy = gs - 1; }
    else { sx = 0; sy = randInt(1, gs - 2); }
    if (ee === 0) { ex = randInt(1, gs - 2); ey = 0; }
    else if (ee === 1) { ex = gs - 1; ey = randInt(1, gs - 2); }
    else if (ee === 2) { ex = randInt(1, gs - 2); ey = gs - 1; }
    else { ex = 0; ey = randInt(1, gs - 2); }

    g[sy * gs + sx] = 2; // start
    g[ey * gs + ex] = 3; // end

    // Add busy cells
    const busy = this.busyForLevel(this.level);
    let placed = 0; let attempts = 0;
    while (placed < busy && attempts < 200) {
      const x = randInt(1, gs - 2);
      const y = randInt(1, gs - 2);
      const idx = y * gs + x;
      if (g[idx] === 0) { g[idx] = 1; placed++; }
      attempts++;
    }

    this.grid = g;
    this.start = { x: sx, y: sy };
    // Start direction: into grid from edge
    this.startDir = se === 0 ? 2 : se === 1 ? 3 : se === 2 ? 0 : 1;
    this.end = { x: ex, y: ey };
    this.mirrorsTotal = this.mirrorsForLevel(this.level);
    this.mirrorsLeft = this.mirrorsTotal;
    this.isWon = false;
    this.updateLaserPath();
  }

  private onCellTap(idx: number): void {
    if (this.isPaused || this.isGameOver || this.isWon) return;
    const cur = this.grid[idx];
    let next: number = cur;
    if (cur === 0) {
      if (this.mirrorsLeft > 0) { next = 4; this.mirrorsLeft = this.mirrorsLeft - 1; }
    } else if (cur === 4) {
      next = 5;
    } else if (cur === 5) {
      next = 0; this.mirrorsLeft = this.mirrorsLeft + 1;
    } else return; // busy / start / end - cannot change

    const newGrid = [...this.grid];
    newGrid[idx] = next;
    this.grid = newGrid;
    this.updateLaserPath();
  }

  private updateLaserPath(): void {
    const gs = this.gridSize;
    const path: number[] = [];
    let x = this.start.x; let y = this.start.y;
    let dir = this.startDir;
    path.push(y * gs + x);
    // Step from start in dir, then trace
    for (let step = 0; step < gs * gs * 4; step++) {
      // advance
      if (dir === 0) y = y - 1;
      else if (dir === 1) x = x + 1;
      else if (dir === 2) y = y + 1;
      else x = x - 1;
      if (x < 0 || x >= gs || y < 0 || y >= gs) break;
      const idx = y * gs + x;
      path.push(idx);
      const c = this.grid[idx];
      if (c === 3) { this.laserCells = path; this.handleWin(); return; }
      if (c === 1 || c === 2) break;
      if (c === 4) {
        // '/' reflection: up<->right, down<->left
        dir = dir === 0 ? 1 : dir === 1 ? 0 : dir === 2 ? 3 : 2;
      } else if (c === 5) {
        // '\' reflection: up<->left, down<->right
        dir = dir === 0 ? 3 : dir === 1 ? 2 : dir === 2 ? 1 : 0;
      }
    }
    this.laserCells = path;
  }

  private handleWin(): void {
    if (this.isWon) return;
    this.isWon = true;
    const fid = ++this.flowId;
    setTimeout(() => { if (fid === this.flowId) { this.level = this.level + 1; this.newLevel(); } }, 900);
  }

  private endGame(): void { if (this.timerId !== -1) clearInterval(this.timerId); this.timerId = -1; this.isGameOver = true; }

  private cellGlyph(t: number): string {
    if (t === 4) return '╱';
    if (t === 5) return '╲';
    if (t === 2) return '◆';
    if (t === 3) return '◎';
    return '';
  }

  private cellBg(idx: number, t: number): string {
    if (t === 1) return '#37474F';
    if (t === 2) return '#1976D2';
    if (t === 3) return '#4CAF50';
    if (this.laserCells.includes(idx) && t !== 4 && t !== 5) return '#FFCDD2';
    return '#FFFFFF';
  }

  private range(n: number): number[] { const a: number[] = []; for (let i = 0; i < n; i++) a.push(i); return a; }

  build() {
    Stack() {
      Column() {
        GameTopBar({ title: '激光', lives: this.lives, showLives: true,
          onPause: () => { if (!this.isGameOver) { if (this.timerId !== -1) clearInterval(this.timerId); this.timerId = -1; this.isPaused = true; } }
        })
        Row() {
          Text(`关卡 ${this.level}`).fontSize(13).fontColor('#616161')
          Blank()
          Text(`剩余镜子: ${this.mirrorsLeft}/${this.mirrorsTotal}`).fontSize(13).fontColor('#673AB7').fontWeight(FontWeight.Bold)
          Text('  ').fontSize(13)
          Text(`⏱ ${fmtTime(this.timeMs)}`).fontSize(13).fontColor(this.timeMs <= 15000 ? '#F44336' : '#424242')
        }.width('100%').padding({ left: 12, right: 12, bottom: 8 })

        Text('点击空格放置镜子，引导激光抵达终点 (再次点击切换方向)').fontSize(12).fontColor('#9E9E9E').margin({ bottom: 8 })

        Column() {
          Grid() {
            ForEach(this.range(this.gridSize * this.gridSize), (idx: number) => {
              GridItem() {
                Stack() {
                  Column().width('100%').height('100%').backgroundColor(this.cellBg(idx, this.grid[idx]))
                    .borderRadius(4).border({ width: 1, color: '#E0E0E0' })
                    .animation({ duration: 150, curve: Curve.EaseOut })
                  if (this.grid[idx] === 4 || this.grid[idx] === 5) {
                    Text(this.cellGlyph(this.grid[idx])).fontSize(22).fontColor('#1976D2').fontWeight(FontWeight.Bold)
                  } else if (this.grid[idx] === 2) {
                    Text('◆').fontSize(20).fontColor('#FFF').fontWeight(FontWeight.Bold)
                  } else if (this.grid[idx] === 3) {
                    Text('◎').fontSize(20).fontColor('#FFF').fontWeight(FontWeight.Bold)
                  }
                }.width('100%').height('100%').onClick(() => this.onCellTap(idx))
              }.aspectRatio(1)
            }, (idx: number) => `lz_${idx}_${this.level}`)
          }
          .columnsTemplate(repStr('1fr', this.gridSize, ' '))
          .columnsGap(2).rowsGap(2).width('100%')
        }.width('94%').layoutWeight(1).justifyContent(FlexAlign.Center)

        if (this.isWon) {
          Text('✓ 激光抵达终点！').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#4CAF50').margin({ top: 12, bottom: 16 })
        } else {
          Text(' ').fontSize(20).margin({ top: 12, bottom: 16 })
        }
      }.width('100%').height('100%').backgroundColor('#F5F5F5')

      GamePauseDialog({ visible: this.isPaused, gameName: '激光',
        onResume: () => { this.isPaused = false; this.startTimer(); },
        onRestart: () => { this.isPaused = false; this.startGame(); },
        onExit: () => router.back()
      })
      GameOverOverlay({ visible: this.isGameOver, score: (this.level - 1) * 20, level: this.level,
        stars: stars3(this.level, 10, 6, 3),
        onPlayAgain: () => this.startGame(), onExit: () => router.back()
      })
    }.width('100%').height('100%')
  }
}
