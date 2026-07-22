import { router } from '@kit.ArkUI';

// ─── Progression (GameProgression1) ────────────────────────────────────────────

function hexGridSize(level: number): number {
  if (level <= 2) return 3;
  if (level <= 5) return 4;
  if (level <= 10) return 5;
  if (level <= 15) return 6;
  if (level <= 20) return 7;
  return 8;
}

function hexWinCells(level: number): number {
  let c: number;
  if (level === 1) c = 3;
  else if (level === 2) c = 4;
  else if (level === 3) c = 5;
  else if (level === 4) c = 6;
  else if (level === 5) c = 7;
  else if (level === 6) c = 8;
  else if (level === 7) c = 9;
  else if (level === 8) c = 10;
  else if (level === 9) c = 11;
  else if (level === 10) c = 12;
  else if (level <= 15) c = 13 + (level - 10);
  else if (level <= 20) c = 18 + (level - 15);
  else c = 23 + (level - 20);
  const gs = hexGridSize(level);
  return Math.min(c, gs * gs - 1);
}

function hexStars(level: number): number {
  if (level >= 15) return 3;
  if (level >= 10) return 2;
  if (level >= 5) return 1;
  return 0;
}

// ─── Helpers ───────────────────────────────────────────────────────────────────

function genChallenge(total: number, count: number): number[] {
  const all: number[] = [];
  for (let i = 0; i < total; i++) all.push(i);
  for (let i = all.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    const t = all[i]; all[i] = all[j]; all[j] = t;
  }
  return all.slice(0, count);
}

function hexCenterXY(row: number, col: number, radius: number, W: number, H: number, gs: number): number[] {
  // Pointy-top hexagon: width = sqrt(3)*r, height = 2r
  const hs = radius * 1.7320508;  // horizontal spacing = hex width
  const vs = radius * 1.5;        // vertical spacing
  const off = row % 2 === 1 ? hs / 2 : 0;
  // Bounding box of full grid (including half-hex margins on edges)
  const totalWidth = (gs + 0.5) * hs;
  const totalHeight = (gs - 1) * vs + 2 * radius;
  // Shift so leftmost/topmost hex edge sits at the canvas centering offset
  const shiftX = (W - totalWidth) / 2 + hs / 2;
  const shiftY = (H - totalHeight) / 2 + radius;
  return [col * hs + off + shiftX, row * vs + shiftY];
}

function touchToHex(tx: number, ty: number, W: number, H: number, gs: number): number {
  const radius = Math.min(W / ((gs + 0.5) * 1.7320508), H / ((gs - 1) * 1.5 + 2));
  for (let row = 0; row < gs; row++) {
    for (let col = 0; col < gs; col++) {
      const p = hexCenterXY(row, col, radius, W, H, gs);
      const dist = Math.sqrt((tx - p[0]) * (tx - p[0]) + (ty - p[1]) * (ty - p[1]));
      if (dist <= radius) return row * gs + col;
    }
  }
  return -1;
}

// ─── Pause dialog ──────────────────────────────────────────────────────────────

@Component
struct HexPause {
  @Prop visible: boolean = false;
  onResume: () => void = () => {};
  onRestart: () => void = () => {};
  onExit: () => void = () => {};
  build() {
    if (this.visible) {
      Stack() {
        Column().width('100%').height('100%').backgroundColor('rgba(0,0,0,0.5)')
        Column({ space: 14 }) {
          Text('游戏暂停').fontSize(22).fontWeight(FontWeight.Bold)
          Text('六边形').fontSize(14).fontColor('#757575')
          Divider().color('#E0E0E0')
          Button({ type: ButtonType.Normal }) {
            Row({ space: 8 }) { Text('▶').fontColor('#FFF'); Text('继续游戏').fontColor('#FFF') }.justifyContent(FlexAlign.Center)
          }.width('100%').height(52).backgroundColor('#4CAF50').borderRadius(10).onClick(() => this.onResume())
          Button({ type: ButtonType.Normal }) {
            Row({ space: 8 }) { Text('↺').fontColor('#FFF'); Text('重新开始').fontColor('#FFF') }.justifyContent(FlexAlign.Center)
          }.width('100%').height(52).backgroundColor('#2196F3').borderRadius(10).onClick(() => this.onRestart())
          Button({ type: ButtonType.Normal }) {
            Row({ space: 8 }) { Text('✕').fontColor('#FFF'); Text('退出游戏').fontColor('#FFF') }.justifyContent(FlexAlign.Center)
          }.width('100%').height(52).backgroundColor('#F44336').borderRadius(10).onClick(() => this.onExit())
        }
        .padding(24).backgroundColor('#FFF').borderRadius(16)
        .shadow({ radius: 16, color: '#3A000000', offsetX: 0, offsetY: 8 })
        .width('85%').alignItems(HorizontalAlign.Center)
      }.width('100%').height('100%').position({ x: 0, y: 0 }).zIndex(100)
    }
  }
}

// ─── Game over overlay ─────────────────────────────────────────────────────────

@Component
struct HexGameOver {
  @Prop visible: boolean = false;
  @Prop score: number = 0;
  @Prop level: number = 1;
  @Prop stars: number = 0;
  onPlayAgain: () => void = () => {};
  onExit: () => void = () => {};
  build() {
    if (this.visible) {
      Stack() {
        Column().width('100%').height('100%').backgroundColor('rgba(0,0,0,0.6)')
        Column({ space: 18 }) {
          Text('游戏结束').fontSize(30).fontWeight(FontWeight.Bold)
          Row({ space: 6 }) {
            Text(this.stars >= 1 ? '★' : '☆').fontSize(38).fontColor(this.stars >= 1 ? '#FFC107' : '#BDBDBD')
            Text(this.stars >= 2 ? '★' : '☆').fontSize(38).fontColor(this.stars >= 2 ? '#FFC107' : '#BDBDBD')
            Text(this.stars >= 3 ? '★' : '☆').fontSize(38).fontColor(this.stars >= 3 ? '#FFC107' : '#BDBDBD')
          }
          Column({ space: 8 }) {
            Row({ space: 6 }) {
              Text('最终得分：').fontSize(16).fontColor('#424242')
              Text(this.score.toString()).fontSize(22).fontWeight(FontWeight.Bold).fontColor('#673AB7')
            }
            Row({ space: 6 }) {
              Text('到达关卡：').fontSize(16).fontColor('#424242')
              Text(this.level.toString()).fontSize(22).fontWeight(FontWeight.Bold).fontColor('#4CAF50')
            }
          }
          Button({ type: ButtonType.Normal }) {
            Text('再玩一次').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
          }.width('100%').height(56).backgroundColor('#4CAF50').borderRadius(12).onClick(() => this.onPlayAgain())
          Button({ type: ButtonType.Normal }) {
            Text('退出游戏').fontSize(16).fontColor('#FFFFFF')
          }.width('100%').height(48).backgroundColor('#F44336').borderRadius(12).onClick(() => this.onExit())
        }
        .padding(28).backgroundColor('#FFF').borderRadius(20)
        .shadow({ radius: 20, color: '#3A000000', offsetX: 0, offsetY: 8 })
        .width('85%').alignItems(HorizontalAlign.Center)
      }.width('100%').height('100%').position({ x: 0, y: 0 }).zIndex(200)
    }
  }
}

// ─── Main page ─────────────────────────────────────────────────────────────────

@Entry
@Component
struct HexagonsPage {
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  @State private level: number = 1;
  @State private score: number = 0;
  @State private lives: number = 3;
  @State private gridSize: number = 3;
  @State private challengeCells: number[] = [];
  @State private selectedCells: number[] = [];
  @State private gameState: string = 'IDLE';
  @State private isPaused: boolean = false;
  @State private isGameOver: boolean = false;

  private canvasReady: boolean = false;
  private flowId: number = 0;

  aboutToDisappear(): void {
    this.flowId = this.flowId + 1;
  }

  // ── Game flow ──────────────────────────────────────

  private startGame(): void {
    this.level = 1;
    this.score = 0;
    this.lives = 3;
    this.isGameOver = false;
    this.isPaused = false;
    this.startLevel();
  }

  private startLevel(): void {
    this.flowId = this.flowId + 1;
    const fid = this.flowId;
    const gs = hexGridSize(this.level);
    const wc = hexWinCells(this.level);
    this.gridSize = gs;
    this.challengeCells = genChallenge(gs * gs, wc);
    this.selectedCells = [];
    this.gameState = 'SHOW_CHALLENGE';
    this.drawCanvas();

    setTimeout(() => {
      if (fid !== this.flowId || this.isPaused) return;
      this.gameState = 'USER_INPUT';
      this.drawCanvas();
    }, 2000);
  }

  private onCellClick(idx: number): void {
    if (this.gameState !== 'USER_INPUT') return;

    if (this.selectedCells.includes(idx)) {
      this.selectedCells = this.selectedCells.filter((c: number) => c !== idx);
    } else {
      this.selectedCells = [...this.selectedCells, idx];
    }
    this.drawCanvas();

    if (this.selectedCells.length === this.challengeCells.length) {
      this.checkAnswer();
    }
  }

  private checkAnswer(): void {
    const isCorrect =
      this.challengeCells.every((c: number) => this.selectedCells.includes(c)) &&
      this.selectedCells.every((c: number) => this.challengeCells.includes(c));

    if (isCorrect) {
      this.score = this.score + 16 + (this.level * 2);
      this.gameState = 'SUCCESS';
      this.drawCanvas();
      this.flowId = this.flowId + 1;
      const fid = this.flowId;
      setTimeout(() => {
        if (fid !== this.flowId) return;
        this.level = this.level + 1;
        this.startLevel();
      }, 500);
    } else {
      this.gameState = 'FAILURE';
      this.drawCanvas();
      this.flowId = this.flowId + 1;
      const fid = this.flowId;
      setTimeout(() => {
        if (fid !== this.flowId) return;
        const nl = this.lives - 1;
        this.lives = nl;
        if (nl <= 0) {
          this.lives = 0;
          this.isGameOver = true;
          this.gameState = 'GAME_OVER';
          this.drawCanvas();
        } else {
          this.startLevel();
        }
      }, 1000);
    }
  }

  // ── Canvas drawing ─────────────────────────────────

  private drawCanvas(): void {
    if (!this.canvasReady) return;
    const W = this.ctx.width;
    const H = this.ctx.height;
    const gs = this.gridSize;
    // Fit pointy-top hexagons: width bound = (gs+0.5)*sqrt(3)*r, height bound = ((gs-1)*1.5 + 2)*r
    const radius = Math.min(W / ((gs + 0.5) * 1.7320508), H / ((gs - 1) * 1.5 + 2));

    this.ctx.clearRect(0, 0, W, H);

    for (let row = 0; row < gs; row++) {
      for (let col = 0; col < gs; col++) {
        const idx = row * gs + col;
        const p = hexCenterXY(row, col, radius, W, H, gs);
        this.drawHex(p[0], p[1], radius * 0.92, this.cellColor(idx));
      }
    }
  }

  private drawHex(cx: number, cy: number, r: number, color: string): void {
    this.ctx.beginPath();
    for (let i = 0; i <= 6; i++) {
      // +PI/6 rotates to pointy-top orientation (vertex up/down, flat left/right edges)
      const angle = Math.PI / 3 * i + Math.PI / 6;
      const px = cx + r * Math.cos(angle);
      const py = cy + r * Math.sin(angle);
      if (i === 0) this.ctx.moveTo(px, py);
      else this.ctx.lineTo(px, py);
    }
    this.ctx.closePath();
    this.ctx.fillStyle = color;
    this.ctx.fill();
    this.ctx.strokeStyle = '#FFFFFF';
    this.ctx.lineWidth = 2.5;
    this.ctx.stroke();
  }

  private cellColor(idx: number): string {
    const isC = this.challengeCells.includes(idx);
    const isS = this.selectedCells.includes(idx);
    if (this.gameState === 'SHOW_CHALLENGE') return isC ? '#4CAF50' : '#BDBDBD';
    if (this.gameState === 'USER_INPUT') return isS ? '#2196F3' : '#E0E0E0';
    if (this.gameState === 'SUCCESS') return isC ? '#4CAF50' : '#E0E0E0';
    if (this.gameState === 'FAILURE') {
      if (isC && isS) return '#4CAF50';
      if (isC && !isS) return '#FFC107';
      if (!isC && isS) return '#F44336';
      return '#E0E0E0';
    }
    return '#E0E0E0';
  }

  // ── UI helpers ─────────────────────────────────────

  private stateText(): string {
    if (this.gameState === 'SHOW_CHALLENGE') return `记住 ${this.challengeCells.length} 个高亮六边形`;
    if (this.gameState === 'USER_INPUT') {
      const rem = this.challengeCells.length - this.selectedCells.length;
      return rem > 0 ? `还需点击 ${rem} 个六边形` : '正在判断...';
    }
    if (this.gameState === 'SUCCESS') return '✓ 正确！';
    if (this.gameState === 'FAILURE') return '✗ 错误，已显示正确答案';
    return ' ';
  }

  private stateColor(): string {
    if (this.gameState === 'SUCCESS') return '#4CAF50';
    if (this.gameState === 'FAILURE') return '#F44336';
    if (this.gameState === 'SHOW_CHALLENGE') return '#FF9800';
    return '#2196F3';
  }

  // ── Build ──────────────────────────────────────────

  build() {
    Stack() {
      Column() {
        // Top bar
        Row() {
          Button({ type: ButtonType.Circle }) {
            Text('⏸').fontSize(18).fontColor('#000000')
          }
          .width(44).height(44).backgroundColor('rgba(0,0,0,0.06)')
          .onClick(() => {
            if (!this.isGameOver) {
              this.flowId = this.flowId + 1;
              this.isPaused = true;
            }
          })
          Blank()
          Text('六边形').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#000000')
          Blank()
          Row({ space: 4 }) {
            ForEach(
              [0, 1, 2] as number[],
              (i: number) => {
                Text(i < this.lives ? '❤' : '♡').fontSize(20)
                  .fontColor(i < this.lives ? '#F44336' : '#BDBDBD')
              },
              (i: number) => `hxl_${i}`
            )
          }
        }
        .width('100%').height(56).padding({ left: 12, right: 12 }).alignItems(VerticalAlign.Center)

        Row() {
          Text(`关卡 ${this.level}`).fontSize(14).fontColor('#616161')
          Blank()
          Text(`得分: ${this.score}`).fontSize(14).fontColor('#673AB7').fontWeight(FontWeight.Bold)
        }
        .width('100%').padding({ left: 16, right: 16, bottom: 6 })

        Divider().color('#E0E0E0')

        // State indicator
        Text(this.stateText())
          .fontSize(15).fontColor(this.stateColor()).fontWeight(FontWeight.Medium)
          .textAlign(TextAlign.Center).width('100%')
          .padding({ top: 10, bottom: 6 })

        // Canvas
        Canvas(this.ctx)
          .width('100%')
          .layoutWeight(1)
          .backgroundColor('#F5F5F5')
          .onReady(() => {
            this.canvasReady = true;
            this.startGame();
          })
          .onTouch((event: TouchEvent) => {
            if (event.type !== TouchType.Down) return;
            if (this.gameState !== 'USER_INPUT') return;
            const tx = event.touches[0].x;
            const ty = event.touches[0].y;
            const idx = touchToHex(tx, ty, this.ctx.width, this.ctx.height, this.gridSize);
            if (idx !== -1) this.onCellClick(idx);
          })

        // Bottom hint
        Text(this.gameState === 'SHOW_CHALLENGE' ? '观察完毕后将隐藏' : '点击正确的六边形位置')
          .fontSize(12).fontColor('#9E9E9E').textAlign(TextAlign.Center)
          .width('100%').padding({ top: 6, bottom: 12 })
      }
      .width('100%').height('100%').backgroundColor('#F5F5F5')

      HexPause({
        visible: this.isPaused,
        onResume: () => {
          this.isPaused = false;
          if (this.gameState === 'SHOW_CHALLENGE' || this.gameState === 'USER_INPUT') {
            this.startLevel();
          }
        },
        onRestart: () => { this.isPaused = false; this.startGame(); },
        onExit: () => { this.flowId = this.flowId + 1; router.back(); }
      })

      HexGameOver({
        visible: this.isGameOver,
        score: this.score,
        level: this.level,
        stars: hexStars(this.level),
        onPlayAgain: () => this.startGame(),
        onExit: () => { this.flowId = this.flowId + 1; router.back(); }
      })
    }
    .width('100%').height('100%')
  }
}
