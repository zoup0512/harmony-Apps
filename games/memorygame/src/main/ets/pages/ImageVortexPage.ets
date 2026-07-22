import { router } from '@kit.ArkUI';
import { GamePauseDialog, GameOverOverlay, GameTopBar, stars3, gp1GridSize, gp1WinCells, repStr, shuffled, randInt } from '../common/GameCommon';

// "图像漩涡" — observe a grid of emojis, then locate the target after a vortex rotation (game id=6)
const EMOJIS: string[] = ['🍎', '🍊', '🍋', '🍌', '🍉', '🍇', '🍓', '🍒', '🍑', '🥝',
  '🍍', '🥥', '🥑', '🥕', '🌽', '🥦', '🍄', '🍞', '🥐', '🥨',
  '🧀', '🍖', '🍗', '🍔', '🍟', '🍕', '🌭', '🥪', '🌮', '🌯',
  '🥚', '🍳', '🥘', '🍲', '🥣', '🥗', '🍰', '🍪', '🍫', '🍬'];

@Entry
@Component
struct ImageVortexPage {
  @State private level: number = 1;
  @State private score: number = 0;
  @State private lives: number = 3;
  @State private gridSize: number = 3;
  @State private grid: string[] = [];
  @State private targetEmoji: string = '';
  @State private gameState: string = 'IDLE'; // SHOWING / SPINNING / USER_INPUT / SUCCESS / FAILURE
  @State private rotation: number = 0;
  @State private isPaused: boolean = false;
  @State private isGameOver: boolean = false;
  private flowId: number = 0;

  aboutToAppear(): void { this.startGame(); }
  aboutToDisappear(): void { this.flowId++; }

  private startGame(): void {
    this.flowId++;
    this.level = 1; this.score = 0; this.lives = 3;
    this.isPaused = false; this.isGameOver = false;
    this.startLevel();
  }

  private async sleep(ms: number, fid: number): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      setTimeout(() => resolve(fid === this.flowId && !this.isPaused), ms);
    });
  }

  private async startLevel(): Promise<void> {
    const fid = ++this.flowId;
    this.gridSize = gp1GridSize(this.level);
    const cnt = Math.min(gp1WinCells(this.level), this.gridSize * this.gridSize);
    const total = this.gridSize * this.gridSize;
    const emojis = shuffled(EMOJIS).slice(0, cnt);
    const positions = shuffled(this.range(total)).slice(0, cnt);
    const grid: string[] = [];
    for (let i = 0; i < total; i++) grid.push('');
    for (let i = 0; i < cnt; i++) grid[positions[i]] = emojis[i];

    this.grid = grid;
    this.targetEmoji = emojis[randInt(0, emojis.length - 1)];
    this.rotation = 0;
    this.gameState = 'SHOWING';

    const ok1 = await this.sleep(2000, fid);
    if (!ok1) return;
    // Vortex animation
    this.gameState = 'SPINNING';
    this.rotation = 360;
    const ok2 = await this.sleep(1200, fid);
    if (!ok2) return;
    this.gameState = 'USER_INPUT';
  }

  private onCellTap(idx: number): void {
    if (this.gameState !== 'USER_INPUT') return;
    if (this.grid[idx] === this.targetEmoji) {
      this.score = this.score + 16 + this.level * 2;
      this.gameState = 'SUCCESS';
      const fid = ++this.flowId;
      setTimeout(() => { if (fid === this.flowId) { this.level = this.level + 1; this.startLevel(); } }, 500);
    } else if (this.grid[idx].length > 0) {
      this.gameState = 'FAILURE';
      const nl = this.lives - 1; this.lives = nl;
      const fid = ++this.flowId;
      setTimeout(() => {
        if (fid !== this.flowId) return;
        if (nl <= 0) this.isGameOver = true; else this.startLevel();
      }, 1000);
    }
  }

  private range(n: number): number[] { const a: number[] = []; for (let i = 0; i < n; i++) a.push(i); return a; }

  private hint(): string {
    if (this.gameState === 'SHOWING') return '记住图案的位置！';
    if (this.gameState === 'SPINNING') return '⟳ 旋转中...';
    if (this.gameState === 'USER_INPUT') return `请找出: ${this.targetEmoji}`;
    if (this.gameState === 'SUCCESS') return '✓ 正确！';
    if (this.gameState === 'FAILURE') return '✗ 错误';
    return ' ';
  }

  private hintColor(): string {
    if (this.gameState === 'SUCCESS') return '#4CAF50';
    if (this.gameState === 'FAILURE') return '#F44336';
    return '#616161';
  }

  build() {
    Stack() {
      Column() {
        GameTopBar({ title: '图像漩涡', lives: this.lives, showLives: true,
          onPause: () => { if (!this.isGameOver) { this.flowId++; this.isPaused = true; } }
        })
        Row() {
          Text(`关卡 ${this.level}`).fontSize(14).fontColor('#616161')
          Blank()
          Text(`分: ${this.score}`).fontSize(14).fontColor('#673AB7').fontWeight(FontWeight.Bold)
        }.width('100%').padding({ left: 16, right: 16, bottom: 8 })

        Text(this.hint()).fontSize(16).fontColor(this.hintColor()).fontWeight(FontWeight.Medium).margin({ bottom: 12 })

        Column() {
          Grid() {
            ForEach(this.range(this.gridSize * this.gridSize), (idx: number) => {
              GridItem() {
                Stack() {
                  Column().width('100%').height('100%')
                    .backgroundColor(this.gameState === 'USER_INPUT' && this.grid[idx].length > 0 ? '#FFFFFF' : '#FAFAFA')
                    .borderRadius(8).border({ width: 1, color: '#E0E0E0' })
                  if (this.gameState === 'SHOWING' || this.gameState === 'SPINNING' || this.gameState === 'SUCCESS' || this.gameState === 'FAILURE') {
                    Text(this.grid[idx]).fontSize(32)
                  } else if (this.gameState === 'USER_INPUT' && this.grid[idx].length > 0) {
                    Text('?').fontSize(28).fontColor('#9E9E9E')
                  }
                }.width('100%').height('100%').onClick(() => this.onCellTap(idx))
              }.aspectRatio(1)
            }, (idx: number) => `iv_${idx}_${this.level}`)
          }
          .columnsTemplate(repStr('1fr', this.gridSize, ' '))
          .columnsGap(6).rowsGap(6).width('100%')
        }.width('90%').layoutWeight(1)
        .rotate({ angle: this.rotation })
        .animation({ duration: 1100, curve: Curve.FastOutSlowIn })
        .justifyContent(FlexAlign.Center)

        Text(' ').height(20)
      }.width('100%').height('100%').backgroundColor('#F5F5F5')

      GamePauseDialog({ visible: this.isPaused, gameName: '图像漩涡',
        onResume: () => { this.isPaused = false; this.startLevel(); },
        onRestart: () => { this.isPaused = false; this.startGame(); },
        onExit: () => router.back()
      })
      GameOverOverlay({ visible: this.isGameOver, score: this.score, level: this.level,
        stars: stars3(this.level, 15, 10, 5),
        onPlayAgain: () => this.startGame(), onExit: () => router.back()
      })
    }.width('100%').height('100%')
  }
}
