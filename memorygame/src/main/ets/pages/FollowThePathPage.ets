import { router } from '@kit.ArkUI';
import { GamePauseDialog, GameOverOverlay, GameTopBar, stars3, gp1GridSize, gp1WinCells, repStr, shuffled } from '../common/GameCommon';

// "跟随路径" — remember the sequence, then tap cells in the same order (game id=5)

@Entry
@Component
struct FollowThePathPage {
  @State private level: number = 1;
  @State private score: number = 0;
  @State private lives: number = 3;
  @State private gridSize: number = 3;
  @State private path: number[] = [];
  @State private showStep: number = -1;  // -1 = none, 0..n-1 = current step shown
  @State private userStep: number = 0;
  @State private wrongIdx: number = -1;
  @State private gameState: string = 'IDLE';
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
    const len = gp1WinCells(this.level);
    const all: number[] = [];
    for (let i = 0; i < this.gridSize * this.gridSize; i++) all.push(i);
    this.path = shuffled(all).slice(0, len);
    this.userStep = 0;
    this.wrongIdx = -1;
    this.gameState = 'SHOWING';

    // Animate path step-by-step
    for (let i = 0; i < this.path.length; i++) {
      this.showStep = i;
      const ok = await this.sleep(650, fid);
      if (!ok) return;
    }
    this.showStep = -1;
    const ok2 = await this.sleep(400, fid);
    if (!ok2) return;
    this.gameState = 'USER_INPUT';
  }

  private onCellTap(idx: number): void {
    if (this.gameState !== 'USER_INPUT') return;
    if (idx === this.path[this.userStep]) {
      this.userStep = this.userStep + 1;
      if (this.userStep >= this.path.length) {
        this.score = this.score + 16 + this.level * 2;
        this.gameState = 'SUCCESS';
        const fid = ++this.flowId;
        setTimeout(() => { if (fid === this.flowId) { this.level = this.level + 1; this.startLevel(); } }, 500);
      }
    } else {
      this.wrongIdx = idx;
      this.gameState = 'FAILURE';
      const nl = this.lives - 1; this.lives = nl;
      const fid = ++this.flowId;
      setTimeout(() => {
        if (fid !== this.flowId) return;
        if (nl <= 0) this.isGameOver = true; else this.startLevel();
      }, 1000);
    }
  }

  private cellColor(idx: number): string {
    if (this.gameState === 'SHOWING') {
      const step = this.path.indexOf(idx);
      if (step !== -1 && step === this.showStep) return '#4CAF50';
      return '#E0E0E0';
    }
    if (this.gameState === 'USER_INPUT') {
      const inDone = this.path.slice(0, this.userStep).includes(idx);
      return inDone ? '#FFC107' : '#FAFAFA';
    }
    if (this.gameState === 'SUCCESS') return this.path.includes(idx) ? '#4CAF50' : '#E0E0E0';
    if (this.gameState === 'FAILURE') {
      if (idx === this.wrongIdx) return '#F44336';
      const step = this.path.indexOf(idx);
      if (step !== -1 && step === this.userStep) return '#2196F3'; // expected
      if (this.path.slice(0, this.userStep).includes(idx)) return '#FFC107';
      return '#E0E0E0';
    }
    return '#E0E0E0';
  }

  private cellLabel(idx: number): string {
    if (this.gameState === 'SHOWING' && idx === this.path[this.showStep]) {
      return `${this.showStep + 1}`;
    }
    if (this.gameState === 'USER_INPUT') {
      const step = this.path.slice(0, this.userStep).indexOf(idx);
      if (step !== -1) return `${step + 1}`;
    }
    return '';
  }

  build() {
    Stack() {
      Column() {
        GameTopBar({ title: '跟随路径', lives: this.lives, showLives: true,
          onPause: () => { if (!this.isGameOver) { this.flowId++; this.isPaused = true; } }
        })
        Row() {
          Text(`关卡 ${this.level}`).fontSize(14).fontColor('#616161')
          Blank()
          Text(`分: ${this.score}`).fontSize(14).fontColor('#673AB7').fontWeight(FontWeight.Bold)
        }.width('100%').padding({ left: 16, right: 16, bottom: 8 })

        Text(
          this.gameState === 'SHOWING' ? '观察并记住路径顺序' :
          this.gameState === 'USER_INPUT' ? `按顺序点击 (${this.userStep + 1}/${this.path.length})` :
          this.gameState === 'SUCCESS' ? '✓ 完成！' :
          this.gameState === 'FAILURE' ? '✗ 顺序错误' : ' '
        ).fontSize(15)
        .fontColor(this.gameState === 'SUCCESS' ? '#4CAF50' : this.gameState === 'FAILURE' ? '#F44336' : '#616161')
        .fontWeight(FontWeight.Medium).margin({ bottom: 12 })

        Column() {
          Grid() {
            ForEach(this.makeRange(this.gridSize * this.gridSize), (idx: number) => {
              GridItem() {
                Stack() {
                  Column().width('100%').height('100%').backgroundColor(this.cellColor(idx))
                    .borderRadius(8).border({ width: 1, color: '#FFFFFF' })
                    .animation({ duration: 200, curve: Curve.EaseOut })
                  if (this.cellLabel(idx).length > 0) {
                    Text(this.cellLabel(idx)).fontSize(20).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
                  }
                }.width('100%').height('100%').onClick(() => this.onCellTap(idx))
              }.aspectRatio(1)
            }, (idx: number) => `ftp_${idx}_${this.level}`)
          }
          .columnsTemplate(repStr('1fr', this.gridSize, ' '))
          .columnsGap(6).rowsGap(6).width('100%')
        }.width('90%').layoutWeight(1).justifyContent(FlexAlign.Center)

        Text(' ').height(20)
      }.width('100%').height('100%').backgroundColor('#F5F5F5')

      GamePauseDialog({ visible: this.isPaused, gameName: '跟随路径',
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
