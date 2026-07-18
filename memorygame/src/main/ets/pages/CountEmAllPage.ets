import { router } from '@kit.ArkUI';
import { GamePauseDialog, GameOverOverlay, GameTopBar, stars3, gp1GridSize, gp1WinCells, repStr, shuffled, randInt } from '../common/GameCommon';

// "数一数" — count items shown briefly, then pick the correct count (game id=19)
const ITEMS: string[] = ['⭐', '🌟', '✨', '🔥', '💧', '❄️', '⚡', '☀️', '🌙',
  '🍎', '🍊', '🍋', '🍌', '🍉', '🍇', '🍓', '🍒', '🍑'];

@Entry
@Component
struct CountEmAllPage {
  @State private level: number = 1;
  @State private score: number = 0;
  @State private lives: number = 3;
  @State private gridSize: number = 3;
  @State private grid: string[] = [];
  @State private correct: number = 0;
  @State private options: number[] = [];
  @State private gameState: string = 'IDLE'; // SHOWING / HIDING / OPTIONS / SUCCESS / FAILURE
  @State private pickedIdx: number = -1;
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
    this.correct = cnt;
    const emoji = ITEMS[randInt(0, ITEMS.length - 1)];
    const total = this.gridSize * this.gridSize;
    const positions = shuffled(this.range(total)).slice(0, cnt);
    const g: string[] = [];
    for (let i = 0; i < total; i++) g.push('');
    for (const p of positions) g[p] = emoji;
    this.grid = g;

    // Generate 4 options including the correct
    const correctPos = randInt(0, 3);
    const opts: number[] = [];
    for (let i = 0; i < 4; i++) {
      if (i === correctPos) opts.push(cnt);
      else opts.push(cnt + (i - correctPos));
    }
    this.options = opts;
    this.pickedIdx = -1;
    this.gameState = 'SHOWING';

    const ok1 = await this.sleep(2000, fid); if (!ok1) return;
    this.gameState = 'HIDING';
    const ok2 = await this.sleep(500, fid); if (!ok2) return;
    this.gameState = 'OPTIONS';
  }

  private onOption(opt: number, idx: number): void {
    if (this.gameState !== 'OPTIONS') return;
    this.pickedIdx = idx;
    if (opt === this.correct) {
      this.score = this.score + 16 + this.level * 2;
      this.gameState = 'SUCCESS';
      const fid = ++this.flowId;
      setTimeout(() => { if (fid === this.flowId) { this.level = this.level + 1; this.startLevel(); } }, 600);
    } else {
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

  private optBg(opt: number, idx: number): string {
    if (this.gameState === 'SUCCESS' && opt === this.correct) return '#4CAF50';
    if (this.gameState === 'FAILURE') {
      if (idx === this.pickedIdx) return '#F44336';
      if (opt === this.correct) return '#4CAF50';
    }
    return '#1976D2';
  }

  build() {
    Stack() {
      Column() {
        GameTopBar({ title: '数一数', lives: this.lives, showLives: true,
          onPause: () => { if (!this.isGameOver) { this.flowId++; this.isPaused = true; } }
        })
        Row() {
          Text(`关卡 ${this.level}`).fontSize(14).fontColor('#616161')
          Blank()
          Text(`分: ${this.score}`).fontSize(14).fontColor('#673AB7').fontWeight(FontWeight.Bold)
        }.width('100%').padding({ left: 16, right: 16, bottom: 8 })

        Text(
          this.gameState === 'SHOWING' ? '数一数有多少个图标' :
          this.gameState === 'OPTIONS' ? '选择正确的数字' :
          this.gameState === 'SUCCESS' ? '✓ 正确！' :
          this.gameState === 'FAILURE' ? `✗ 正确答案: ${this.correct}` : ' '
        ).fontSize(15)
        .fontColor(this.gameState === 'SUCCESS' ? '#4CAF50' : this.gameState === 'FAILURE' ? '#F44336' : '#616161')
        .fontWeight(FontWeight.Medium).margin({ bottom: 12 })

        Column() {
          if (this.gameState === 'OPTIONS') {
            Stack() {
              Column().width('100%').height('100%').backgroundColor('#FAFAFA').borderRadius(12)
              Text('?').fontSize(60).fontColor('#BDBDBD').fontWeight(FontWeight.Bold)
            }.width('100%').layoutWeight(1)
          } else {
            Grid() {
              ForEach(this.range(this.gridSize * this.gridSize), (idx: number) => {
                GridItem() {
                  Stack() {
                    Column().width('100%').height('100%').backgroundColor('#FFFFFF').borderRadius(8)
                      .border({ width: 1, color: '#E0E0E0' })
                    if (this.grid[idx].length > 0) Text(this.grid[idx]).fontSize(32)
                  }.width('100%').height('100%')
                }.aspectRatio(1)
              }, (idx: number) => `cea_${idx}_${this.level}`)
            }
            .columnsTemplate(repStr('1fr', this.gridSize, ' '))
            .columnsGap(6).rowsGap(6).width('100%')
          }
        }.width('90%').layoutWeight(1).justifyContent(FlexAlign.Center)

        if (this.gameState === 'OPTIONS' || this.gameState === 'SUCCESS' || this.gameState === 'FAILURE') {
          Row({ space: 10 }) {
            ForEach(this.options, (opt: number, idx: number) => {
              Button({ type: ButtonType.Normal }) {
                Text(`${opt}`).fontSize(22).fontColor('#FFF').fontWeight(FontWeight.Bold)
              }.layoutWeight(1).height(64).borderRadius(14)
              .backgroundColor(this.optBg(opt, idx))
              .onClick(() => this.onOption(opt, idx))
            }, (opt: number, idx: number) => `cea_o_${idx}_${this.level}_${opt}`)
          }.width('92%').margin({ top: 8, bottom: 16 })
        } else {
          Text(' ').height(80)
        }
      }.width('100%').height('100%').backgroundColor('#F5F5F5')

      GamePauseDialog({ visible: this.isPaused, gameName: '数一数',
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
