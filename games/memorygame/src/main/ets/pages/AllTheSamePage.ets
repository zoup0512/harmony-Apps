import { router } from '@kit.ArkUI';
import { GamePauseDialog, GameOverOverlay, GameTopBar, stars3, fmtTime, randInt, shuffled } from '../common/GameCommon';

// "全部相同" — judge if all elements are the same (game id=12)
const SHAPES: string[] = ['●', '■', '▲', '◆', '★', '⬢', '♥'];
const COLORS: string[] = ['#E91E63', '#9C27B0', '#3F51B5', '#2196F3', '#00BCD4', '#4CAF50', '#FFEB3B', '#FF9800', '#FF5722', '#795548'];
const GAME_TIME_MS = 60000;

interface Elem { shape: number; color: number; }

@Entry
@Component
struct AllTheSamePage {
  @State private level: number = 1;
  @State private lives: number = 3;
  @State private timeMs: number = GAME_TIME_MS;
  @State private elems: Elem[] = [];
  @State private gridCols: number = 4;
  @State private showFb: boolean = false;
  @State private fbOk: boolean = false;
  @State private isPaused: boolean = false;
  @State private isGameOver: boolean = false;
  private timerId: number = -1;
  private startTs: number = 0;
  private flowId: number = 0;

  aboutToAppear(): void { this.startGame(); }
  aboutToDisappear(): void { this.clearTimer(); this.flowId++; }

  private clearTimer(): void { if (this.timerId !== -1) { clearInterval(this.timerId); this.timerId = -1; } }

  private startGame(): void {
    this.flowId++;
    this.level = 1; this.lives = 3; this.timeMs = GAME_TIME_MS;
    this.isPaused = false; this.isGameOver = false; this.showFb = false;
    this.newLevel();
    this.startTimer();
  }

  private startTimer(): void {
    this.clearTimer();
    this.startTs = Date.now();
    const initial = this.timeMs;
    this.timerId = setInterval(() => {
      const rem = initial - (Date.now() - this.startTs);
      if (rem <= 0) { this.timeMs = 0; this.endGame(); }
      else this.timeMs = rem;
    }, 50);
  }

  private newLevel(): void {
    const level = this.level;
    const count = Math.min(level + 4, 40);
    this.gridCols = count <= 9 ? 3 : count <= 16 ? 4 : count <= 25 ? 5 : 6;

    // Decide element types
    let e1: Elem; let e2: Elem;
    if (level <= 5) {
      // Different shape AND different color
      const s1 = randInt(0, SHAPES.length - 1);
      let s2 = randInt(0, SHAPES.length - 1); while (s2 === s1) s2 = randInt(0, SHAPES.length - 1);
      const c1 = randInt(0, COLORS.length - 1);
      let c2 = randInt(0, COLORS.length - 1); while (c2 === c1) c2 = randInt(0, COLORS.length - 1);
      e1 = { shape: s1, color: c1 }; e2 = { shape: s2, color: c2 };
    } else if (level <= 10) {
      // Same shape, different color
      const s = randInt(0, SHAPES.length - 1);
      const c1 = randInt(0, COLORS.length - 1);
      let c2 = randInt(0, COLORS.length - 1); while (c2 === c1) c2 = randInt(0, COLORS.length - 1);
      e1 = { shape: s, color: c1 }; e2 = { shape: s, color: c2 };
    } else {
      // Different shape, same color
      const s1 = randInt(0, SHAPES.length - 1);
      let s2 = randInt(0, SHAPES.length - 1); while (s2 === s1) s2 = randInt(0, SHAPES.length - 1);
      const c = randInt(0, COLORS.length - 1);
      e1 = { shape: s1, color: c }; e2 = { shape: s2, color: c };
    }

    // 50% chance: all same. Otherwise mix.
    const allSame = Math.random() < 0.5;
    const result: Elem[] = [];
    if (allSame) {
      for (let i = 0; i < count; i++) result.push(e1);
    } else {
      const r = 0.35 + Math.random() * 0.3;
      const g1 = Math.max(1, Math.min(count - 1, Math.floor(count * r)));
      for (let i = 0; i < g1; i++) result.push(e1);
      for (let i = g1; i < count; i++) result.push(e2);
    }
    this.elems = shuffled(result);
  }

  private isActuallyAllSame(): boolean {
    if (this.elems.length === 0) return true;
    const first = this.elems[0];
    for (const e of this.elems) {
      if (e.shape !== first.shape || e.color !== first.color) return false;
    }
    return true;
  }

  private answer(saysAllSame: boolean): void {
    if (this.isGameOver || this.isPaused || this.showFb) return;
    const correct = saysAllSame === this.isActuallyAllSame();
    this.fbOk = correct; this.showFb = true;
    const fid = ++this.flowId;
    setTimeout(() => {
      if (fid !== this.flowId) return;
      this.showFb = false;
      if (correct) { this.level = this.level + 1; this.newLevel(); }
      else {
        const nl = this.lives - 1; this.lives = nl;
        if (nl <= 0) this.endGame(); else this.newLevel();
      }
    }, 700);
  }

  private endGame(): void { this.clearTimer(); this.isGameOver = true; }

  build() {
    Stack() {
      Column() {
        GameTopBar({ title: '全部相同', lives: this.lives, showLives: true,
          onPause: () => { if (!this.isGameOver) { this.clearTimer(); this.isPaused = true; } }
        })
        Row() {
          Text(`关卡 ${this.level}`).fontSize(14).fontColor('#616161')
          Blank()
          Text(`⏱ ${fmtTime(this.timeMs)}`).fontSize(14).fontColor(this.timeMs <= 10000 ? '#F44336' : '#424242')
        }.width('100%').padding({ left: 16, right: 16, bottom: 8 })

        Text('这些图形是否全部相同？').fontSize(15).fontColor('#616161').margin({ bottom: 12 })

        // Grid area
        Column() {
          Grid() {
            ForEach(this.elems, (e: Elem, idx: number) => {
              GridItem() {
                Text(SHAPES[e.shape]).fontSize(36).fontColor(COLORS[e.color])
              }
            }, (e: Elem, idx: number) => `ats_${idx}_${e.shape}_${e.color}`)
          }
          .columnsTemplate(this.gridCols === 3 ? '1fr 1fr 1fr' : this.gridCols === 4 ? '1fr 1fr 1fr 1fr' : this.gridCols === 5 ? '1fr 1fr 1fr 1fr 1fr' : '1fr 1fr 1fr 1fr 1fr 1fr')
          .columnsGap(6).rowsGap(6)
          .width('100%')
        }.width('92%').layoutWeight(1).backgroundColor('#FAFAFA').borderRadius(12).padding(8)

        if (this.showFb) {
          Text(this.fbOk ? '✓ 正确' : '✗ 错误')
            .fontSize(20).fontWeight(FontWeight.Bold)
            .fontColor(this.fbOk ? '#4CAF50' : '#F44336').margin({ top: 12 })
        } else {
          Text(' ').fontSize(20).margin({ top: 12 })
        }

        Row({ space: 12 }) {
          Button({ type: ButtonType.Normal }) {
            Text('相同').fontSize(18).fontColor('#FFF').fontWeight(FontWeight.Bold)
          }.layoutWeight(1).height(64).backgroundColor('#4CAF50').borderRadius(14).onClick(() => this.answer(true))
          Button({ type: ButtonType.Normal }) {
            Text('不同').fontSize(18).fontColor('#FFF').fontWeight(FontWeight.Bold)
          }.layoutWeight(1).height(64).backgroundColor('#F44336').borderRadius(14).onClick(() => this.answer(false))
        }.width('92%').margin({ top: 8, bottom: 20 })
      }.width('100%').height('100%').backgroundColor('#F5F5F5')

      GamePauseDialog({ visible: this.isPaused, gameName: '全部相同',
        onResume: () => { this.isPaused = false; this.startTimer(); },
        onRestart: () => { this.isPaused = false; this.startGame(); },
        onExit: () => router.back()
      })
      GameOverOverlay({ visible: this.isGameOver, score: this.level * 10, level: this.level,
        stars: stars3(this.level, 25, 15, 8),
        onPlayAgain: () => this.startGame(), onExit: () => router.back()
      })
    }.width('100%').height('100%')
  }
}
