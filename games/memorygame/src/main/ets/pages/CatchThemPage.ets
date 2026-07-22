import { router } from '@kit.ArkUI';
import { GamePauseDialog, GameOverOverlay, GameTopBar, stars3, fmtTime, gp1GridSize, gp1WinCells, repStr, shuffled } from '../common/GameCommon';

// "抓住它们" — remember target cells, watch them shuffle, then tap them at new positions (game id=7)
const GAME_TIME_MS = 60000;

@Entry
@Component
struct CatchThemPage {
  @State private level: number = 1;
  @State private lives: number = 3;
  @State private timeMs: number = GAME_TIME_MS;
  @State private gridSize: number = 3;
  @State private visibleCells: number[] = [];    // original indices that are visible
  @State private targetCells: number[] = [];     // original indices that are targets
  @State private clickedCells: number[] = [];    // original indices that have been clicked
  @State private shuffleMap: number[] = [];      // origIdx -> newIdx
  @State private gameState: string = 'IDLE';     // SHOW / SHUFFLING / INPUT / SOLUTION
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
    this.isPaused = false; this.isGameOver = false;
    this.startTimer();
    this.startLevel();
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

  private async sleep(ms: number, fid: number): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      setTimeout(() => resolve(fid === this.flowId && !this.isPaused), ms);
    });
  }

  private async startLevel(): Promise<void> {
    const fid = ++this.flowId;
    this.gridSize = gp1GridSize(this.level);
    const winCount = gp1WinCells(this.level);
    const visibleCount = Math.min(winCount + 2, this.gridSize * this.gridSize);
    const total = this.gridSize * this.gridSize;

    const allIdx = shuffled(this.range(total));
    this.visibleCells = allIdx.slice(0, visibleCount);
    this.targetCells = this.visibleCells.slice(0, winCount);
    this.clickedCells = [];

    // identity mapping for SHOW phase
    const idMap: number[] = [];
    for (let i = 0; i < total; i++) idMap.push(i);
    this.shuffleMap = idMap;
    this.gameState = 'SHOW';

    const ok1 = await this.sleep(1800, fid); if (!ok1) return;

    // Generate shuffle mapping
    const newMap: number[] = [];
    for (let i = 0; i < total; i++) newMap.push(i);
    const shuf = shuffled(newMap);
    const mapping: number[] = [];
    for (let i = 0; i < total; i++) mapping.push(0);
    for (let i = 0; i < total; i++) mapping[i] = shuf[i];
    this.shuffleMap = mapping;
    this.gameState = 'SHUFFLING';

    const ok2 = await this.sleep(1200, fid); if (!ok2) return;
    this.gameState = 'INPUT';
  }

  private onTap(slotIdx: number): void {
    if (this.gameState !== 'INPUT') return;
    // Find which original cell occupies this slot
    let origIdx = -1;
    for (let i = 0; i < this.shuffleMap.length; i++) {
      if (this.shuffleMap[i] === slotIdx) { origIdx = i; break; }
    }
    if (origIdx === -1) return;
    if (!this.visibleCells.includes(origIdx)) return;
    if (this.clickedCells.includes(origIdx)) return;

    if (this.targetCells.includes(origIdx)) {
      this.clickedCells = [...this.clickedCells, origIdx];
      // Check all targets clicked
      const allClicked = this.targetCells.every((t: number) => this.clickedCells.includes(t));
      if (allClicked) {
        const fid = ++this.flowId;
        setTimeout(() => { if (fid === this.flowId) { this.level = this.level + 1; this.startLevel(); } }, 500);
      }
    } else {
      const nl = this.lives - 1; this.lives = nl;
      this.clickedCells = [...this.clickedCells, origIdx];
      if (nl <= 0) {
        this.gameState = 'SOLUTION';
        const fid = ++this.flowId;
        setTimeout(() => { if (fid === this.flowId) this.endGame(); }, 1500);
      }
    }
  }

  private endGame(): void { if (this.timerId !== -1) clearInterval(this.timerId); this.timerId = -1; this.isGameOver = true; }
  private range(n: number): number[] { const a: number[] = []; for (let i = 0; i < n; i++) a.push(i); return a; }

  private slotColor(slotIdx: number): string {
    // Find original index at this slot
    let orig = -1;
    for (let i = 0; i < this.shuffleMap.length; i++) {
      if (this.shuffleMap[i] === slotIdx) { orig = i; break; }
    }
    if (orig === -1) return 'transparent';
    if (!this.visibleCells.includes(orig)) return 'transparent';

    const isT = this.targetCells.includes(orig);
    const isC = this.clickedCells.includes(orig);
    if (this.gameState === 'SHOW') return isT ? '#1976D2' : '#90CAF9';
    if (this.gameState === 'SOLUTION') return isT && !isC ? '#FF5252' : isC && isT ? '#4CAF50' : isC ? '#F44336' : '#90CAF9';
    if (isC && isT) return '#4CAF50';
    if (isC && !isT) return '#F44336';
    return '#90CAF9';
  }

  private slotShowCheck(slotIdx: number): boolean {
    let orig = -1;
    for (let i = 0; i < this.shuffleMap.length; i++) if (this.shuffleMap[i] === slotIdx) { orig = i; break; }
    return orig !== -1 && this.clickedCells.includes(orig) && this.targetCells.includes(orig);
  }

  build() {
    Stack() {
      Column() {
        GameTopBar({ title: '抓住它们', lives: this.lives, showLives: true,
          onPause: () => { if (!this.isGameOver) { if (this.timerId !== -1) clearInterval(this.timerId); this.timerId = -1; this.isPaused = true; } }
        })
        Row() {
          Text(`关卡 ${this.level}`).fontSize(14).fontColor('#616161')
          Blank()
          Text(`⏱ ${fmtTime(this.timeMs)}`).fontSize(14).fontColor(this.timeMs <= 10000 ? '#F44336' : '#424242')
        }.width('100%').padding({ left: 16, right: 16, bottom: 8 })

        Text(
          this.gameState === 'SHOW' ? '记住深蓝色的位置' :
          this.gameState === 'SHUFFLING' ? '⟳ 洗牌中...' :
          this.gameState === 'INPUT' ? `点击移动后的目标 (${this.clickedCells.filter((c: number) => this.targetCells.includes(c)).length}/${this.targetCells.length})` :
          '查看答案'
        ).fontSize(15).fontColor('#616161').fontWeight(FontWeight.Medium).margin({ bottom: 12 })

        Column() {
          Grid() {
            ForEach(this.range(this.gridSize * this.gridSize), (slotIdx: number) => {
              GridItem() {
                Stack() {
                  Column().width('100%').height('100%').backgroundColor(this.slotColor(slotIdx))
                    .borderRadius(8)
                    .animation({ duration: 1100, curve: Curve.FastOutSlowIn })
                  if (this.slotShowCheck(slotIdx)) {
                    Text('✓').fontSize(24).fontColor('#FFF').fontWeight(FontWeight.Bold)
                  }
                }.width('100%').height('100%').onClick(() => this.onTap(slotIdx))
              }.aspectRatio(1)
            }, (slotIdx: number) => `ct_${slotIdx}_${this.level}`)
          }
          .columnsTemplate(repStr('1fr', this.gridSize, ' '))
          .columnsGap(6).rowsGap(6).width('100%')
        }.width('90%').layoutWeight(1).justifyContent(FlexAlign.Center)

        Text(' ').height(20)
      }.width('100%').height('100%').backgroundColor('#F5F5F5')

      GamePauseDialog({ visible: this.isPaused, gameName: '抓住它们',
        onResume: () => { this.isPaused = false; this.startTimer(); this.startLevel(); },
        onRestart: () => { this.isPaused = false; this.startGame(); },
        onExit: () => router.back()
      })
      GameOverOverlay({ visible: this.isGameOver, score: (this.level - 1) * 16, level: this.level,
        stars: stars3(this.level, 15, 8, 3),
        onPlayAgain: () => this.startGame(), onExit: () => router.back()
      })
    }.width('100%').height('100%')
  }
}
