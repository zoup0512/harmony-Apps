import { router } from '@kit.ArkUI';
import { GamePauseDialog, GameOverOverlay, GameTopBar, stars3, gp1GridSize, gp1WinCells, repStr, randInt } from '../common/GameCommon';

// "谁是新的" — identify the newly-added cell (game id=3)

@Entry
@Component
struct WhosNewPage {
  @State private level: number = 1;
  @State private score: number = 0;
  @State private lives: number = 3;
  @State private gridSize: number = 3;
  @State private highlighted: number[] = [];
  @State private newIdx: number = -1;
  @State private gameState: string = 'IDLE'; // SHOWING / HIDING / USER_INPUT / SUCCESS / FAILURE
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
    const wc = gp1WinCells(this.level);
    const total = this.gridSize * this.gridSize;
    this.highlighted = [];
    this.newIdx = -1;
    this.gameState = 'SHOWING';

    // Add cells one by one
    const all: number[] = [];
    for (let i = 0; i < total; i++) all.push(i);
    // Shuffle
    for (let i = all.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      const t = all[i]; all[i] = all[j]; all[j] = t;
    }

    for (let i = 0; i < wc; i++) {
      const ok = await this.sleep(700, fid);
      if (!ok) return;
      this.highlighted = all.slice(0, i + 1);
      this.newIdx = all[i];
    }

    const ok1 = await this.sleep(800, fid);
    if (!ok1) return;
    this.gameState = 'HIDING';
    const ok2 = await this.sleep(800, fid);
    if (!ok2) return;

    // Add one more new cell (not in highlighted)
    const newCell = all[wc];
    this.highlighted = all.slice(0, wc + 1);
    this.newIdx = newCell;
    this.gameState = 'USER_INPUT';
  }

  private onCellTap(idx: number): void {
    if (this.gameState !== 'USER_INPUT') return;
    if (idx === this.newIdx) {
      this.score = this.score + 16 + this.level * 2;
      this.gameState = 'SUCCESS';
      const fid = ++this.flowId;
      setTimeout(() => { if (fid === this.flowId) { this.level = this.level + 1; this.startLevel(); } }, 500);
    } else {
      const nl = this.lives - 1; this.lives = nl;
      this.gameState = 'FAILURE';
      const fid = ++this.flowId;
      setTimeout(() => {
        if (fid !== this.flowId) return;
        if (nl <= 0) { this.isGameOver = true; } else this.startLevel();
      }, 1000);
    }
  }

  private cellColor(idx: number): string {
    const isHl = this.highlighted.includes(idx);
    if (this.gameState === 'SHOWING') return isHl ? '#4CAF50' : '#E0E0E0';
    if (this.gameState === 'HIDING') return '#E0E0E0';
    if (this.gameState === 'USER_INPUT') return isHl ? '#FFC107' : '#E0E0E0';
    if (this.gameState === 'SUCCESS') return idx === this.newIdx ? '#4CAF50' : isHl ? '#FFC107' : '#E0E0E0';
    if (this.gameState === 'FAILURE') return idx === this.newIdx ? '#2196F3' : isHl ? '#FFC107' : '#E0E0E0';
    return '#E0E0E0';
  }

  build() {
    Stack() {
      Column() {
        GameTopBar({ title: '谁是新的', lives: this.lives, showLives: true,
          onPause: () => { if (!this.isGameOver) { this.flowId++; this.isPaused = true; } }
        })
        Row() {
          Text(`关卡 ${this.level}`).fontSize(14).fontColor('#616161')
          Blank()
          Text(`分: ${this.score}`).fontSize(14).fontColor('#673AB7').fontWeight(FontWeight.Bold)
        }.width('100%').padding({ left: 16, right: 16, bottom: 8 })

        Text(
          this.gameState === 'SHOWING' ? '记住高亮的位置' :
          this.gameState === 'HIDING' ? '等待...' :
          this.gameState === 'USER_INPUT' ? '哪一个是新增的？' :
          this.gameState === 'SUCCESS' ? '✓ 正确！' :
          this.gameState === 'FAILURE' ? '✗ 错误' : ' '
        ).fontSize(15).fontColor(this.gameState === 'SUCCESS' ? '#4CAF50' : this.gameState === 'FAILURE' ? '#F44336' : '#616161')
        .fontWeight(FontWeight.Medium).margin({ bottom: 12 })

        Column() {
          Grid() {
            ForEach(this.makeRange(this.gridSize * this.gridSize), (idx: number) => {
              GridItem() {
                Column().width('100%').height('100%').backgroundColor(this.cellColor(idx))
                  .borderRadius(8).border({ width: 1, color: '#FFFFFF' })
                  .animation({ duration: 200, curve: Curve.EaseOut })
                  .onClick(() => this.onCellTap(idx))
              }.aspectRatio(1)
            }, (idx: number) => `wn_${idx}_${this.level}`)
          }
          .columnsTemplate(repStr('1fr', this.gridSize, ' '))
          .columnsGap(6).rowsGap(6).width('100%')
        }.width('90%').layoutWeight(1).justifyContent(FlexAlign.Center)

        Text(' ').height(20)
      }.width('100%').height('100%').backgroundColor('#F5F5F5')

      GamePauseDialog({ visible: this.isPaused, gameName: '谁是新的',
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

  private makeRange(n: number): number[] {
    const a: number[] = [];
    for (let i = 0; i < n; i++) a.push(i);
    return a;
  }
}
