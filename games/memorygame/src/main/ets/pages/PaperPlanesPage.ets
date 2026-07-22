import { router } from '@kit.ArkUI';
import { GamePauseDialog, GameOverOverlay, GameTopBar, stars3, fmtTime, randInt } from '../common/GameCommon';

// "纸飞机" — swipe in the matching direction (game id=14)
const GAME_TIME_MS = 30000;
// Type: 0 = move (按移动方向), 1 = orient (按朝向)
// Direction codes: 0=up, 1=right, 2=down, 3=left

@Entry
@Component
struct PaperPlanesPage {
  @State private level: number = 1;
  @State private lives: number = 3;
  @State private timeMs: number = GAME_TIME_MS;
  @State private gameType: number = 0;
  @State private moveDir: number = 0;
  @State private orientDir: number = 0;
  @State private planeX: number = 0;
  @State private planeY: number = 0;
  @State private showFb: boolean = false;
  @State private fbOk: boolean = false;
  @State private isPaused: boolean = false;
  @State private isGameOver: boolean = false;
  private timerId: number = -1;
  private startTs: number = 0;
  private animId: number = -1;
  private flowId: number = 0;

  aboutToAppear(): void { this.startGame(); }
  aboutToDisappear(): void { this.stopAll(); this.flowId++; }

  private stopAll(): void {
    if (this.timerId !== -1) { clearInterval(this.timerId); this.timerId = -1; }
    if (this.animId !== -1) { clearInterval(this.animId); this.animId = -1; }
  }

  private startGame(): void {
    this.flowId++;
    this.level = 1; this.lives = 3; this.timeMs = GAME_TIME_MS;
    this.isPaused = false; this.isGameOver = false; this.showFb = false;
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

  private newLevel(): void {
    this.gameType = Math.random() < 0.5 ? 0 : 1;
    this.moveDir = randInt(0, 3);
    this.orientDir = randInt(0, 3);
    this.showFb = false;
    this.startPlaneAnim();
  }

  private startPlaneAnim(): void {
    if (this.animId !== -1) clearInterval(this.animId);
    // Reset position to opposite of move direction
    if (this.moveDir === 0) { this.planeX = 0; this.planeY = 100; }
    else if (this.moveDir === 1) { this.planeX = -100; this.planeY = 0; }
    else if (this.moveDir === 2) { this.planeX = 0; this.planeY = -100; }
    else { this.planeX = 100; this.planeY = 0; }

    const totalSteps = 30;
    let step = 0;
    const sx = this.planeX; const sy = this.planeY;
    this.animId = setInterval(() => {
      step++;
      const t = step / totalSteps;
      this.planeX = sx * (1 - t);
      this.planeY = sy * (1 - t);
      if (step >= totalSteps) {
        if (this.animId !== -1) { clearInterval(this.animId); this.animId = -1; }
        // restart loop
        setTimeout(() => { if (!this.showFb && !this.isPaused && !this.isGameOver) this.startPlaneAnim(); }, 200);
      }
    }, 60);
  }

  private answer(dir: number): void {
    if (this.isGameOver || this.isPaused || this.showFb) return;
    const target = this.gameType === 0 ? this.moveDir : this.orientDir;
    const ok = dir === target;
    this.fbOk = ok; this.showFb = true;
    if (this.animId !== -1) { clearInterval(this.animId); this.animId = -1; }
    const fid = ++this.flowId;
    setTimeout(() => {
      if (fid !== this.flowId) return;
      this.showFb = false;
      if (ok) { this.level = this.level + 1; this.newLevel(); }
      else {
        const nl = this.lives - 1; this.lives = nl;
        if (nl <= 0) this.endGame(); else this.newLevel();
      }
    }, 700);
  }

  private endGame(): void { this.stopAll(); this.isGameOver = true; }

  private planeRot(): number { return this.orientDir * 90; }
  private dirLabel(d: number): string { return d === 0 ? '↑' : d === 1 ? '→' : d === 2 ? '↓' : '←'; }

  build() {
    Stack() {
      Column() {
        GameTopBar({ title: '纸飞机', lives: this.lives, showLives: true,
          onPause: () => { if (!this.isGameOver) { this.stopAll(); this.isPaused = true; } }
        })
        Row() {
          Text(`关卡 ${this.level}`).fontSize(14).fontColor('#616161')
          Blank()
          Text(`⏱ ${fmtTime(this.timeMs)}`).fontSize(14).fontColor(this.timeMs <= 5000 ? '#F44336' : '#424242')
        }.width('100%').padding({ left: 16, right: 16, bottom: 8 })

        Text(this.gameType === 0 ? '按"飞机移动方向"点击' : '按"飞机机头朝向"点击')
          .fontSize(15).fontColor('#1976D2').fontWeight(FontWeight.Bold).margin({ bottom: 4 })
        Text('(注意区分移动和朝向是否一致)')
          .fontSize(11).fontColor('#9E9E9E').margin({ bottom: 16 })

        // Plane stage
        Stack() {
          Column().width('92%').height(280).backgroundColor('#E1F5FE').borderRadius(20)
            .border({ width: 1, color: '#B3E5FC' })
          Text('✈')
            .fontSize(64).fontColor('#1976D2')
            .translate({ x: this.planeX, y: this.planeY })
            .rotate({ angle: this.planeRot() })
            .animation({ duration: 60, curve: Curve.Linear })
        }

        if (this.showFb) {
          Text(this.fbOk ? '✓ 正确' : '✗ 错误')
            .fontSize(20).fontWeight(FontWeight.Bold)
            .fontColor(this.fbOk ? '#4CAF50' : '#F44336').margin({ top: 12 })
        } else {
          Text(' ').fontSize(20).margin({ top: 12 })
        }

        Blank()

        // Direction button cross
        Column({ space: 8 }) {
          Button({ type: ButtonType.Normal }) {
            Text('↑').fontSize(32).fontColor('#FFF').fontWeight(FontWeight.Bold)
          }.width(72).height(72).backgroundColor('#1976D2').borderRadius(36).onClick(() => this.answer(0))
          Row({ space: 32 }) {
            Button({ type: ButtonType.Normal }) {
              Text('←').fontSize(32).fontColor('#FFF').fontWeight(FontWeight.Bold)
            }.width(72).height(72).backgroundColor('#1976D2').borderRadius(36).onClick(() => this.answer(3))
            Button({ type: ButtonType.Normal }) {
              Text('→').fontSize(32).fontColor('#FFF').fontWeight(FontWeight.Bold)
            }.width(72).height(72).backgroundColor('#1976D2').borderRadius(36).onClick(() => this.answer(1))
          }
          Button({ type: ButtonType.Normal }) {
            Text('↓').fontSize(32).fontColor('#FFF').fontWeight(FontWeight.Bold)
          }.width(72).height(72).backgroundColor('#1976D2').borderRadius(36).onClick(() => this.answer(2))
        }.margin({ bottom: 24 })
      }.width('100%').height('100%').backgroundColor('#F5F5F5')

      GamePauseDialog({ visible: this.isPaused, gameName: '纸飞机',
        onResume: () => { this.isPaused = false; this.startTimer(); this.startPlaneAnim(); },
        onRestart: () => { this.isPaused = false; this.startGame(); },
        onExit: () => router.back()
      })
      GameOverOverlay({ visible: this.isGameOver, score: this.level * 10, level: this.level,
        stars: stars3(this.level, 20, 12, 6),
        onPlayAgain: () => this.startGame(), onExit: () => router.back()
      })
    }.width('100%').height('100%')
  }
}
