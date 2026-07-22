import { router } from '@kit.ArkUI';
import { GamePauseDialog, GameOverOverlay, GameTopBar, stars3, fmtTime, shuffled, randInt } from '../common/GameCommon';

// "金字塔" — find the different pyramid (game id=17)
const COLORS: string[] = ['#F44336', '#2196F3', '#4CAF50', '#FFC107', '#9C27B0', '#FF9800', '#00BCD4', '#FF5722'];
const GAME_TIME_MS = 60000;

interface Pyr { colors: number[]; }

@Entry
@Component
struct PyramidsPage {
  @State private level: number = 1;
  @State private score: number = 0;
  @State private lives: number = 3;
  @State private timeMs: number = GAME_TIME_MS;
  @State private pyramids: Pyr[] = [];
  @State private circleCount: number = 3;
  @State private diffIdx: number = -1;
  @State private gameState: string = 'INPUT'; // INPUT / SUCCESS / FAILURE
  @State private clickedIdx: number = -1;
  @State private isPaused: boolean = false;
  @State private isGameOver: boolean = false;
  private timerId: number = -1;
  private startTs: number = 0;
  private flowId: number = 0;

  aboutToAppear(): void { this.startGame(); }
  aboutToDisappear(): void { if (this.timerId !== -1) clearInterval(this.timerId); this.flowId++; }

  private startGame(): void {
    this.flowId++;
    this.level = 1; this.score = 0; this.lives = 3; this.timeMs = GAME_TIME_MS;
    this.isPaused = false; this.isGameOver = false;
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

  private circlesByLevel(level: number): number {
    if (level <= 3) return 3;
    if (level <= 7) return 4;
    if (level <= 13) return 5;
    if (level <= 18) return 6;
    if (level <= 23) return 7;
    return 8;
  }

  private genColors(count: number): number[] {
    const out: number[] = [];
    let prev = -1;
    for (let i = 0; i < count; i++) {
      let c = randInt(0, COLORS.length - 1);
      let tries = 0;
      while (c === prev && tries < 10) { c = randInt(0, COLORS.length - 1); tries++; }
      out.push(c);
      prev = c;
    }
    return out;
  }

  private isValid(colors: number[], existing: Pyr[], level: number): boolean {
    for (let i = 1; i < colors.length; i++) if (colors[i] === colors[i - 1]) return false;
    for (const ex of existing) {
      // Identical?
      let same = true;
      for (let i = 0; i < colors.length; i++) if (colors[i] !== ex.colors[i]) { same = false; break; }
      if (same) return false;
      // Level constraints
      if (level > 5 && level <= 8) {
        if (colors[colors.length - 1] !== ex.colors[ex.colors.length - 1]) return false;
      } else if (level > 8 && level <= 18) {
        if (colors[0] !== ex.colors[0]) return false;
        if (colors[colors.length - 1] !== ex.colors[ex.colors.length - 1]) return false;
      } else if (level > 18) {
        if (colors[0] !== ex.colors[0]) return false;
        if (colors[colors.length - 2] !== ex.colors[ex.colors.length - 2]) return false;
        if (colors[colors.length - 1] !== ex.colors[ex.colors.length - 1]) return false;
      }
    }
    return true;
  }

  private newLevel(): void {
    this.circleCount = this.circlesByLevel(this.level);
    const pyramids: Pyr[] = [];
    for (let p = 0; p < 3; p++) {
      let colors: number[] = [];
      let tries = 0;
      do {
        colors = this.genColors(this.circleCount);
        tries++;
      } while (!this.isValid(colors, pyramids, this.level) && tries < 100);
      pyramids.push({ colors });
    }
    this.pyramids = pyramids;
    this.diffIdx = randInt(0, 2);
    this.gameState = 'INPUT';
    this.clickedIdx = -1;
  }

  private onPick(idx: number): void {
    if (this.gameState !== 'INPUT') return;
    this.clickedIdx = idx;
    if (idx === this.diffIdx) {
      this.score = this.score + 8 + this.level * 2;
      this.gameState = 'SUCCESS';
      const fid = ++this.flowId;
      setTimeout(() => { if (fid === this.flowId) { this.level = this.level + 1; this.newLevel(); } }, 500);
    } else {
      this.gameState = 'FAILURE';
      const nl = this.lives - 1; this.lives = nl;
      const fid = ++this.flowId;
      setTimeout(() => {
        if (fid !== this.flowId) return;
        if (nl <= 0) this.endGame(); else this.newLevel();
      }, 1000);
    }
  }

  private endGame(): void { if (this.timerId !== -1) clearInterval(this.timerId); this.timerId = -1; this.isGameOver = true; }

  private pyrBorder(idx: number): string {
    if (this.gameState === 'SUCCESS' && idx === this.diffIdx) return '#4CAF50';
    if (this.gameState === 'FAILURE') {
      if (idx === this.clickedIdx) return '#F44336';
      if (idx === this.diffIdx) return '#4CAF50';
    }
    return '#E0E0E0';
  }

  private circleSize(layer: number): number {
    // Decreasing from large (bottom) to small (top)
    const base = 44;
    const step = 4;
    return Math.max(14, base - layer * step);
  }

  build() {
    Stack() {
      Column() {
        GameTopBar({ title: '金字塔', lives: this.lives, showLives: true,
          onPause: () => { if (!this.isGameOver) { if (this.timerId !== -1) clearInterval(this.timerId); this.timerId = -1; this.isPaused = true; } }
        })
        Row() {
          Text(`关卡 ${this.level}`).fontSize(14).fontColor('#616161')
          Blank()
          Text(`分: ${this.score}`).fontSize(13).fontColor('#673AB7').fontWeight(FontWeight.Bold)
          Text('   ').fontSize(13)
          Text(`⏱ ${fmtTime(this.timeMs)}`).fontSize(13).fontColor(this.timeMs <= 10000 ? '#F44336' : '#424242')
        }.width('100%').padding({ left: 16, right: 16, bottom: 8 })

        Text('找出与众不同的金字塔').fontSize(15).fontColor('#616161').margin({ bottom: 16 })

        Row({ space: 10 }) {
          ForEach([0, 1, 2] as number[], (idx: number) => {
            Stack() {
              Column().width('100%').height('100%').backgroundColor('#FFFFFF').borderRadius(12)
                .border({ width: 3, color: this.pyrBorder(idx) })
              // Pyramid (top to bottom): smallest first (layer 0 at top has small size? we want largest at bottom)
              // pyramid.colors[i]: i=0 is top, last is bottom. Use reverse drawing for visual pyramid.
              Column({ space: 4 }) {
                ForEach(this.pyramids[idx].colors, (col: number, i: number) => {
                  Column().width(this.circleSize(this.pyramids[idx].colors.length - 1 - i))
                    .height(this.circleSize(this.pyramids[idx].colors.length - 1 - i))
                    .borderRadius(40).backgroundColor(COLORS[col])
                }, (col: number, i: number) => `pyr_${idx}_${i}_${col}_${this.level}`)
              }.padding(8)
            }.layoutWeight(1).aspectRatio(0.55).onClick(() => this.onPick(idx))
          }, (idx: number) => `pyr_box_${idx}_${this.level}`)
        }.width('94%')

        if (this.gameState === 'SUCCESS' || this.gameState === 'FAILURE') {
          Text(this.gameState === 'SUCCESS' ? '✓ 正确！' : '✗ 错误')
            .fontSize(20).fontWeight(FontWeight.Bold)
            .fontColor(this.gameState === 'SUCCESS' ? '#4CAF50' : '#F44336').margin({ top: 16 })
        } else {
          Text(' ').fontSize(20).margin({ top: 16 })
        }

        Blank()
      }.width('100%').height('100%').backgroundColor('#F5F5F5')

      GamePauseDialog({ visible: this.isPaused, gameName: '金字塔',
        onResume: () => { this.isPaused = false; this.startTimer(); },
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
