import { router } from '@kit.ArkUI';

const CELL_COLORS: string[] = ['#E57373','#64B5F6','#81C784','#FFD54F'];
const GAME_DURATION_MS = 60000;
const BOARD_GAP = 4;

function makeGrid(): number[][] {
  const g: number[][] = [];
  for (let c = 0; c < 6; c++) {
    const col: number[] = [];
    for (let r = 0; r < 6; r++) col.push(Math.floor(Math.random() * 4));
    g.push(col);
  }
  return g;
}
function make36(): number[] { const a: number[] = []; for (let i=0;i<36;i++) a.push(i); return a; }
function chainScore(len: number): number {
  return len < 10 ? Math.round(Math.pow(2, len)) : (len - 9) * 512 + 512;
}
function stars248(total: number): number {
  return total >= 5000 ? 3 : total >= 2000 ? 2 : 1;
}

// ─── Tutorial ──────────────────────────────────────────────────────────────────

@Component
struct Tutorial248 {
  @State private step: number = 0;
  onFinish: () => void = () => {};

  private titles: string[] = ['认识248','滑动连接','分数翻倍','移动行列','出发！'];
  private descs: string[] = [
    '248 是一款连珠消除游戏。中间 4×4 是游戏区，边缘是方向箭头，你有 60 秒！',
    '用手指在游戏区滑过相邻的同色方块来选中它们，抬起手指即可消除并得分。',
    '连接数量越多，得分呈指数增长！\n2连=4分  3连=8分\n5连=32分  9连=512分',
    '点击行两侧的 ← → 可循环移动整行；点击列上下的 ↑ ↓ 可循环移动整列，帮你拼出更长的链！',
    '60秒内总分达到 2000+ 得2星，5000+ 得3星。\n准备好了吗？加油！'
  ];
  private icons: string[] = ['🎮','👆','💰','↔','🚀'];

  @Builder MiniGrid() {
    Grid() {
      ForEach([0,1,2,3,4,5,6,7,8] as number[], (i: number) => {
        GridItem() {
          Column().width('100%').height('100%')
            .backgroundColor(CELL_COLORS[i % 4]).borderRadius(6)
            .border({ width: (i===0||i===1||i===3) ? 2 : 0, color: '#FFFFFF' })
            .scale({ x: (i===0||i===1||i===3) ? 0.85 : 1.0, y: (i===0||i===1||i===3) ? 0.85 : 1.0 })
        }
      }, (i: number) => `tg_${i}`)
    }
    .columnsTemplate('1fr 1fr 1fr').rowsTemplate('1fr 1fr 1fr')
    .columnsGap(4).rowsGap(4).width(120).height(120)
  }

  @Builder ScoreTable() {
    Column({ space: 6 }) {
      ForEach(['2连 → 4分','3连 → 8分','5连 → 32分','9连 → 512分'] as string[], (s: string) => {
        Text(s).fontSize(15).fontColor('#424242').fontWeight(FontWeight.Medium)
      }, (s: string) => s)
    }
  }

  @Builder ArrowDemo() {
    Row({ space: 6 }) {
      Text('←').fontSize(22).fontColor('#FFFFFF').width(44).height(44)
        .textAlign(TextAlign.Center).backgroundColor('#546E7A').borderRadius(22)
      Grid() {
        ForEach([0,1,2,3] as number[], (i: number) => {
          GridItem() {
            Column().width('100%').height('100%')
              .backgroundColor(CELL_COLORS[i]).borderRadius(6)
          }
        }, (i: number) => `ad_${i}`)
      }
      .columnsTemplate('1fr 1fr').rowsTemplate('1fr 1fr')
      .columnsGap(4).rowsGap(4).width(96).height(96)
      Text('→').fontSize(22).fontColor('#FFFFFF').width(44).height(44)
        .textAlign(TextAlign.Center).backgroundColor('#546E7A').borderRadius(22)
    }
  }

  @Builder StarsDemo() {
    Row({ space: 8 }) {
      Text('★').fontSize(44).fontColor('#FFC107')
      Text('★').fontSize(44).fontColor('#FFC107')
      Text('★').fontSize(44).fontColor('#FFC107')
    }
  }

  build() {
    Stack() {
      Column().width('100%').height('100%').backgroundColor('rgba(0,0,0,0.7)')
      Column({ space: 20 }) {
        Row() {
          Blank()
          Text('跳过').fontSize(14).fontColor('#9E9E9E')
            .onClick(() => this.onFinish())
        }.width('100%')

        Text(this.icons[this.step]).fontSize(48)
        Text(this.titles[this.step])
          .fontSize(22).fontWeight(FontWeight.Bold).fontColor('#212121')
        Text(this.descs[this.step])
          .fontSize(14).fontColor('#616161').textAlign(TextAlign.Center)
          .lineHeight(22).padding({ left: 8, right: 8 })

        if (this.step === 1) { this.MiniGrid() }
        else if (this.step === 2) { this.ScoreTable() }
        else if (this.step === 3) { this.ArrowDemo() }
        else if (this.step === 4) { this.StarsDemo() }

        Row({ space: 8 }) {
          ForEach([0,1,2,3,4] as number[], (i: number) => {
            Column().width(i === this.step ? 20 : 8).height(8).borderRadius(4)
              .backgroundColor(i === this.step ? '#673AB7' : '#E0E0E0')
              .animation({ duration: 200, curve: Curve.EaseOut })
          }, (i: number) => `dot_${i}`)
        }

        Row({ space: 12 }) {
          if (this.step > 0) {
            Button({ type: ButtonType.Normal }) { Text('上一步').fontSize(15).fontColor('#673AB7') }
            .height(44).padding({ left: 20, right: 20 }).backgroundColor('#EDE7F6').borderRadius(22)
            .onClick(() => { this.step = this.step - 1; })
          }
          if (this.step < 4) {
            Button({ type: ButtonType.Normal }) { Text('下一步').fontSize(15).fontColor('#FFFFFF') }
            .height(44).padding({ left: 28, right: 28 }).backgroundColor('#673AB7').borderRadius(22)
            .onClick(() => { this.step = this.step + 1; })
          } else {
            Button({ type: ButtonType.Normal }) { Text('开始游戏！').fontSize(16).fontColor('#FFFFFF').fontWeight(FontWeight.Bold) }
            .height(50).padding({ left: 32, right: 32 }).backgroundColor('#4CAF50').borderRadius(25)
            .onClick(() => this.onFinish())
          }
        }
      }
      .padding(24).backgroundColor('#FFFFFF').borderRadius(20)
      .shadow({ radius: 20, color: '#40000000', offsetX: 0, offsetY: 8 })
      .width('92%').alignItems(HorizontalAlign.Center)
    }
    .width('100%').height('100%').position({ x: 0, y: 0 }).zIndex(300)
  }
}

// ─── Pause dialog ──────────────────────────────────────────────────────────────

@Component
struct G248Pause {
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
          Text('248').fontSize(14).fontColor('#757575')
          Divider().color('#E0E0E0')
          Button({ type: ButtonType.Normal }) { Row({ space:8 }) { Text('▶').fontColor('#FFF'); Text('继续').fontColor('#FFF') }.justifyContent(FlexAlign.Center) }
          .width('100%').height(52).backgroundColor('#4CAF50').borderRadius(10).onClick(() => this.onResume())
          Button({ type: ButtonType.Normal }) { Row({ space:8 }) { Text('↺').fontColor('#FFF'); Text('重新开始').fontColor('#FFF') }.justifyContent(FlexAlign.Center) }
          .width('100%').height(52).backgroundColor('#2196F3').borderRadius(10).onClick(() => this.onRestart())
          Button({ type: ButtonType.Normal }) { Row({ space:8 }) { Text('✕').fontColor('#FFF'); Text('退出').fontColor('#FFF') }.justifyContent(FlexAlign.Center) }
          .width('100%').height(52).backgroundColor('#F44336').borderRadius(10).onClick(() => this.onExit())
        }
        .padding(24).backgroundColor('#FFF').borderRadius(16)
        .shadow({ radius: 16, color: '#3A000000', offsetX: 0, offsetY: 8 })
        .width('85%').alignItems(HorizontalAlign.Center)
      }
      .width('100%').height('100%').position({ x: 0, y: 0 }).zIndex(100)
    }
  }
}

// ─── Game over overlay ─────────────────────────────────────────────────────────

@Component
struct G248Over {
  @Prop visible: boolean = false;
  @Prop totalScore: number = 0;
  @Prop stars: number = 1;
  onPlayAgain: () => void = () => {};
  onExit: () => void = () => {};
  build() {
    if (this.visible) {
      Stack() {
        Column().width('100%').height('100%').backgroundColor('rgba(0,0,0,0.6)')
        Column({ space: 18 }) {
          Text('时间到！').fontSize(30).fontWeight(FontWeight.Bold)
          Row({ space: 6 }) {
            Text(this.stars>=1?'★':'☆').fontSize(38).fontColor(this.stars>=1?'#FFC107':'#BDBDBD')
            Text(this.stars>=2?'★':'☆').fontSize(38).fontColor(this.stars>=2?'#FFC107':'#BDBDBD')
            Text(this.stars>=3?'★':'☆').fontSize(38).fontColor(this.stars>=3?'#FFC107':'#BDBDBD')
          }
          Row({ space: 6 }) {
            Text('总得分：').fontSize(16).fontColor('#424242')
            Text(this.totalScore.toString()).fontSize(26).fontWeight(FontWeight.Bold).fontColor('#673AB7')
          }
          Button({ type: ButtonType.Normal }) { Text('再玩一次').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#FFFFFF') }
          .width('100%').height(56).backgroundColor('#4CAF50').borderRadius(12).onClick(() => this.onPlayAgain())
          Button({ type: ButtonType.Normal }) { Text('退出游戏').fontSize(16).fontColor('#FFFFFF') }
          .width('100%').height(48).backgroundColor('#F44336').borderRadius(12).onClick(() => this.onExit())
        }
        .padding(28).backgroundColor('#FFF').borderRadius(20)
        .shadow({ radius: 20, color: '#3A000000', offsetX: 0, offsetY: 8 })
        .width('85%').alignItems(HorizontalAlign.Center)
      }
      .width('100%').height('100%').position({ x: 0, y: 0 }).zIndex(200)
    }
  }
}

// ─── Grid Cell Component ───────────────────────────────────────────────────────

@Component
struct GridCell248 {
  @Prop idx: number = 0;
  @Prop grid: number[][] = [];
  @Prop selectedCells: number[] = [];
  onArrowClick: (col: number, row: number) => void = () => {};
  isSelected: (col: number, row: number) => boolean = () => false;
  arrowLabel: (col: number, row: number) => string = () => '';

  private getCol(): number { return this.idx % 6; }
  private getRow(): number { return Math.floor(this.idx / 6); }
  private isCorner(): boolean { 
    const col = this.getCol();
    const row = this.getRow();
    return (col===0||col===5) && (row===0||row===5);
  }
  private isArrow(): boolean { 
    const col = this.getCol();
    const row = this.getRow();
    return !this.isCorner() && (col===0||col===5||row===0||row===5);
  }
  private isGame(): boolean { 
    const col = this.getCol();
    const row = this.getRow();
    return col>=1&&col<=4&&row>=1&&row<=4;
  }
  private getCellType(): number { return this.grid[this.getCol()][this.getRow()]; }
  private isCellSelected(): boolean { return this.isSelected(this.getCol(), this.getRow()); }

  build() {
    Column() {
      if (this.isCorner()) {
        Column().width('100%').height('100%').backgroundColor('transparent')
      } else if (this.isArrow()) {
        Stack() {
          Column().width('100%').height('100%').backgroundColor('#546E7A').borderRadius(8)
          Text(this.arrowLabel(this.getCol(), this.getRow())).fontSize(18).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
        }
        .width('100%').height('100%')
        .onClick(() => this.onArrowClick(this.getCol(), this.getRow()))
      } else if (this.isGame()) {
        Stack() {
          Column().width('100%').height('100%')
            .backgroundColor(this.isCellSelected() ? '#FFFFFF' : CELL_COLORS[this.getCellType()])
            .borderRadius(8)
            .border({ width: this.isCellSelected() ? 3 : 0, color: CELL_COLORS[this.getCellType()] })
            .scale({ x: this.isCellSelected() ? 0.88 : 1.0, y: this.isCellSelected() ? 0.88 : 1.0 })
            .animation({ duration: 120, curve: Curve.EaseOut })
          if (this.isCellSelected()) {
            Column().width(14).height(14).borderRadius(7)
              .backgroundColor(CELL_COLORS[this.getCellType()])
          }
        }
        .width('100%').height('100%')
      } else {
        Column().width('100%').height('100%').backgroundColor('#E0E0E0').borderRadius(8)
      }
    }
    .width('100%').height('100%')
  }
}

// ─── Main page ─────────────────────────────────────────────────────────────────

@Entry
@Component
struct Game248Page {
  @State private grid: number[][] = makeGrid();
  @State private selectedCells: number[] = [];
  @State private totalScore: number = 0;
  @State private bonusText: string = '';
  @State private showBonus: boolean = false;
  @State private timeRemainingMs: number = GAME_DURATION_MS;
  @State private isGameOver: boolean = false;
  @State private isPaused: boolean = false;
  @State private showTutorial: boolean = true;
  @State private boardW: number = 320;

  private timerId: number = -1;
  private isDragging: boolean = false;
  private dragColor: number = -1;

  aboutToAppear(): void { /* tutorial shown first, game starts after */ }
  aboutToDisappear(): void { this.clearTimer(); }

  private clearTimer(): void {
    if (this.timerId !== -1) { clearInterval(this.timerId); this.timerId = -1; }
  }

  private startGame(): void {
    this.clearTimer();
    this.grid = makeGrid();
    this.selectedCells = [];
    this.totalScore = 0;
    this.timeRemainingMs = GAME_DURATION_MS;
    this.isGameOver = false;
    this.isPaused = false;
    this.isDragging = false;
    this.timerId = setInterval(() => {
      this.timeRemainingMs = this.timeRemainingMs - 100;
      if (this.timeRemainingMs <= 0) {
        this.timeRemainingMs = 0;
        this.clearTimer();
        this.isGameOver = true;
      }
    }, 100);
  }

  private gridCopy(): number[][] {
    return this.grid.map((col: number[]) => [...col]);
  }

  private cellToColRow(code: number): number[] { return [code % 6, Math.floor(code / 6)]; }
  private colRowToCell(col: number, row: number): number { return row * 6 + col; }

  private handleTouch(event: TouchEvent): void {
    if (this.isGameOver || this.isPaused) return;
    const tx = event.touches[0].x;
    const ty = event.touches[0].y;
    const step = (this.boardW + BOARD_GAP) / 6;
    const col = Math.floor(tx / step);
    const row = Math.floor(ty / step);
    const isGameCell = col >= 1 && col <= 4 && row >= 1 && row <= 4;
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.commitDrag(); return;
    }
    if (!isGameCell) return;
    const code = this.colRowToCell(col, row);
    const colorType = this.grid[col][row];
    if (event.type === TouchType.Down) {
      this.isDragging = true;
      this.dragColor = colorType;
      this.selectedCells = [code];
    } else if (event.type === TouchType.Move && this.isDragging && colorType === this.dragColor) {
      const idx = this.selectedCells.indexOf(code);
      if (idx >= 0) {
        this.selectedCells = this.selectedCells.slice(0, idx + 1);
      } else {
        const last = this.selectedCells[this.selectedCells.length - 1];
        const lcr = this.cellToColRow(last);
        const lc = lcr[0];
        const lr = lcr[1];
        if (Math.abs(col - lc) + Math.abs(row - lr) === 1) {
          this.selectedCells = [...this.selectedCells, code];
        }
      }
    }
  }

  private commitDrag(): void {
    this.isDragging = false;
    if (this.selectedCells.length > 1) {
      const score = chainScore(this.selectedCells.length);
      const ng = this.gridCopy();
      for (const code of this.selectedCells) {
        const cr = this.cellToColRow(code);
        ng[cr[0]][cr[1]] = Math.floor(Math.random() * 4);
      }
      this.grid = ng;
      this.totalScore = this.totalScore + score;
      this.bonusText = `+${score}`;
      this.showBonus = true;
      setTimeout(() => { this.showBonus = false; }, 700);
    }
    this.selectedCells = [];
  }

  private moveRowLeft(gameRow: number): void {
    const ng = this.gridCopy();
    const tmp = ng[1][gameRow];
    for (let i = 1; i < 5; i++) ng[i][gameRow] = ng[i + 1][gameRow];
    ng[5][gameRow] = tmp;
    this.grid = ng;
  }
  private moveRowRight(gameRow: number): void {
    const ng = this.gridCopy();
    const tmp = ng[5][gameRow];
    for (let i = 5; i >= 2; i--) ng[i][gameRow] = ng[i - 1][gameRow];
    ng[1][gameRow] = tmp;
    this.grid = ng;
  }
  private moveColUp(gameCol: number): void {
    const ng = this.gridCopy();
    const tmp = ng[gameCol][1];
    for (let j = 1; j < 5; j++) ng[gameCol][j] = ng[gameCol][j + 1];
    ng[gameCol][5] = tmp;
    this.grid = ng;
  }
  private moveColDown(gameCol: number): void {
    const ng = this.gridCopy();
    const tmp = ng[gameCol][5];
    for (let j = 5; j >= 2; j--) ng[gameCol][j] = ng[gameCol][j - 1];
    ng[gameCol][1] = tmp;
    this.grid = ng;
  }

  private timerText(): string {
    const s = Math.ceil(this.timeRemainingMs / 1000);
    return `${Math.floor(s / 60)}:${s % 60 < 10 ? '0' + s % 60 : s % 60}`;
  }
  private progressRatio(): number { return this.timeRemainingMs / GAME_DURATION_MS; }

  private arrowLabel(col: number, row: number): string {
    if (col === 0) return '←';
    if (col === 5) return '→';
    if (row === 0) return '↑';
    if (row === 5) return '↓';
    return '';
  }
  private arrowAction(col: number, row: number): void {
    if (col === 0 && row >= 1 && row <= 4) this.moveRowLeft(row);
    else if (col === 5 && row >= 1 && row <= 4) this.moveRowRight(row);
    else if (row === 0 && col >= 1 && col <= 4) this.moveColUp(col);
    else if (row === 5 && col >= 1 && col <= 4) this.moveColDown(col);
  }
  private isSelected(col: number, row: number): boolean {
    return this.selectedCells.includes(this.colRowToCell(col, row));
  }

  build() {
    Stack() {
      Column() {
        // Top bar
        Row() {
          Button({ type: ButtonType.Circle }) { Text('⏸').fontSize(18).fontColor('#000') }
          .width(44).height(44).backgroundColor('rgba(0,0,0,0.06)')
          .onClick(() => { if (!this.showTutorial) { this.clearTimer(); this.isPaused = true; } })
          Blank()
          Text('248').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#000')
          Blank()
          Text(`分数: ${this.totalScore}`).fontSize(16).fontColor('#673AB7').fontWeight(FontWeight.Bold)
        }
        .width('100%').height(56).padding({ left: 12, right: 12 }).alignItems(VerticalAlign.Center)

        // Timer bar
        Row() {
          Text(`⏱ ${this.timerText()}`).fontSize(14)
            .fontColor(this.timeRemainingMs <= 10000 ? '#F44336' : '#424242')
            .fontWeight(this.timeRemainingMs <= 10000 ? FontWeight.Bold : FontWeight.Normal)
        }
        .width('100%').padding({ left: 16, right: 16, bottom: 4 }).justifyContent(FlexAlign.End)

        Stack({ alignContent: Alignment.Start }) {
          Row().width('100%').height(5).backgroundColor('#E0E0E0').borderRadius(3)
          Row().width(`${(this.progressRatio() * 100).toFixed(1)}%`).height(5)
            .backgroundColor(this.timeRemainingMs > 20000 ? '#4CAF50' : this.timeRemainingMs > 10000 ? '#FF9800' : '#F44336')
            .borderRadius(3).animation({ duration: 100, curve: Curve.Linear })
        }.width('100%').padding({ left: 0, right: 0, bottom: 8 })

        Divider().color('#E0E0E0')

        // Bonus text
        Text(this.showBonus ? this.bonusText : ' ')
          .fontSize(28).fontWeight(FontWeight.Bold)
          .fontColor('#4CAF50')
          .opacity(this.showBonus ? 1.0 : 0.0)
          .animation({ duration: 300, curve: Curve.EaseOut })
          .padding({ top: 4, bottom: 4 })

        // Game board
        Stack() {
          Grid() {
            ForEach(make36(), (idx: number) => {
              GridItem() {
                GridCell248({
                  idx: idx,
                  grid: this.grid,
                  selectedCells: this.selectedCells,
                  onArrowClick: (col: number, row: number) => this.arrowAction(col, row),
                  isSelected: (col: number, row: number) => this.isSelected(col, row),
                  arrowLabel: (col: number, row: number) => this.arrowLabel(col, row)
                })
              }
            }, (idx: number) => `g_${idx}`)
          }
          .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr')
          .rowsTemplate('1fr 1fr 1fr 1fr 1fr 1fr')
          .columnsGap(BOARD_GAP).rowsGap(BOARD_GAP)
          .width('100%').height('100%')

          // Touch overlay (game cells only)
          Column().width('100%').height('100%').opacity(0.01)
            .onTouch((e: TouchEvent) => this.handleTouch(e))
        }
        .width('100%').aspectRatio(1)
        .padding(8)
        .onAreaChange((_: Area, area: Area) => { this.boardW = area.width as number; })

        // Help hint
        Text('💡 滑动同色方块连接得分，点击边缘箭头移动行列')
          .fontSize(12).fontColor('#9E9E9E').textAlign(TextAlign.Center)
          .width('100%').padding({ top: 8, bottom: 8, left: 12, right: 12 })
      }
      .width('100%').height('100%').backgroundColor('#E5F6FE')

      G248Pause({
        visible: this.isPaused,
        onResume: () => { this.isPaused = false; if (!this.isGameOver) { this.timerId = setInterval(() => { this.timeRemainingMs = this.timeRemainingMs - 100; if (this.timeRemainingMs <= 0) { this.timeRemainingMs = 0; this.clearTimer(); this.isGameOver = true; } }, 100); } },
        onRestart: () => { this.isPaused = false; this.startGame(); },
        onExit: () => { this.clearTimer(); router.back(); }
      })

      G248Over({
        visible: this.isGameOver,
        totalScore: this.totalScore,
        stars: stars248(this.totalScore),
        onPlayAgain: () => this.startGame(),
        onExit: () => { this.clearTimer(); router.back(); }
      })

      if (this.showTutorial) {
        Tutorial248({ onFinish: () => { this.showTutorial = false; this.startGame(); } })
      }
    }
    .width('100%').height('100%')
  }
}
