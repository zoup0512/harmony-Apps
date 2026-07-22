import { router } from '@kit.ArkUI';

// ─── Helpers (ArkTS-safe) ──────────────────────────────────────────────────────

function makeRange(n: number): number[] {
  const arr: number[] = [];
  for (let i = 0; i < n; i++) arr.push(i);
  return arr;
}

function repeatStr(s: string, n: number, sep: string): string {
  const parts: string[] = [];
  for (let i = 0; i < n; i++) parts.push(s);
  return parts.join(sep);
}

// ─── Game states ───────────────────────────────────────────────────────────────

const RG_READY = 'READY';
const RG_GRID_ANIM = 'GRID_ANIMATION';
const RG_SHOW_CHALLENGE = 'SHOW_CHALLENGE';
const RG_ROTATING = 'ROTATING';
const RG_PLAYER_TURN = 'PLAYER_TURN';
const RG_LEVEL_COMPLETE = 'LEVEL_COMPLETE';
const RG_SHOW_FAILURE = 'SHOW_FAILURE';
const RG_GAME_OVER = 'GAME_OVER';

// Rotation angles (same as Android: [90, -180, 270, -90, 180, -270])
const ROTATION_ANGLES: number[] = [90, -180, 270, -90, 180, -270];

// ─── Progression (same logic as GameProgression1 / GameProgression2) ───────────

function rgCalcGridSize(level: number): number {
  if (level <= 2) return 3;
  if (level <= 5) return 4;
  if (level <= 10) return 5;
  if (level <= 15) return 6;
  if (level <= 20) return 7;
  return 8;
}

function rgCalcWinCells(level: number, gridSize: number): number {
  let w: number;
  if (level === 1) w = 3;
  else if (level === 2) w = 4;
  else if (level === 3) w = 5;
  else if (level === 4) w = 6;
  else if (level === 5) w = 7;
  else if (level === 6) w = 8;
  else if (level === 7) w = 9;
  else if (level === 8) w = 10;
  else if (level === 9) w = 11;
  else if (level === 10) w = 12;
  else if (level <= 15) w = 13 + (level - 10);
  else if (level <= 20) w = 18 + (level - 15);
  else w = 23 + (level - 20);
  const max = gridSize * gridSize - 1;
  return w > max ? max : w;
}

function rgCalcStars(level: number): number {
  if (level >= 15) return 3;
  if (level >= 10) return 2;
  if (level >= 5) return 1;
  return 0;
}

function rgGeneratePattern(gridSize: number, winCells: number): number[] {
  const total = gridSize * gridSize;
  const positions: number[] = [];
  while (positions.length < winCells) {
    const n = Math.floor(Math.random() * total);
    if (!positions.includes(n)) positions.push(n);
  }
  return positions;
}

function pickRotationAngle(): number {
  return ROTATION_ANGLES[Math.floor(Math.random() * ROTATION_ANGLES.length)];
}

// ─── Pattern rotation math (matches Android rotatePattern) ────────────────────

function rotatePattern(pattern: number[], gridSize: number, angle: number): number[] {
  const result: number[] = [];
  for (let i = 0; i < pattern.length; i++) {
    const pos = pattern[i];
    const row = Math.floor(pos / gridSize);
    const col = pos % gridSize;
    let nr: number;
    let nc: number;
    if (angle === 90 || angle === -270) {
      nr = col;
      nc = gridSize - 1 - row;
    } else if (angle === -90 || angle === 270) {
      nr = gridSize - 1 - col;
      nc = row;
    } else {
      // 180 / -180
      nr = gridSize - 1 - row;
      nc = gridSize - 1 - col;
    }
    result.push(nr * gridSize + nc);
  }
  return result;
}

function arraysMatch(a: number[], b: number[]): boolean {
  if (a.length !== b.length) return false;
  const sa = [...a].sort((x, y) => x - y);
  const sb = [...b].sort((x, y) => x - y);
  for (let i = 0; i < sa.length; i++) {
    if (sa[i] !== sb[i]) return false;
  }
  return true;
}

// ─── State indicator helpers ───────────────────────────────────────────────────

function rgStateColor(state: string): string {
  switch (state) {
    case RG_READY: return '#4CAF50';
    case RG_GRID_ANIM: return '#2196F3';
    case RG_SHOW_CHALLENGE: return '#FFC107';
    case RG_ROTATING: return '#009688';
    case RG_PLAYER_TURN: return '#4CAF50';
    case RG_LEVEL_COMPLETE: return '#4CAF50';
    case RG_SHOW_FAILURE: return '#F44336';
    case RG_GAME_OVER: return '#F44336';
    default: return '#9E9E9E';
  }
}

function rgStateLabel(state: string, angleDeg: number): string {
  switch (state) {
    case RG_READY: return '准备好！';
    case RG_GRID_ANIM: return '注意...';
    case RG_SHOW_CHALLENGE: return '记住这些位置！';
    case RG_ROTATING: return `↻ 网格旋转中... ${angleDeg}°`;
    case RG_PLAYER_TURN: return '选择旋转后的位置';
    case RG_LEVEL_COMPLETE: return '正确！';
    case RG_SHOW_FAILURE: return '错误！';
    case RG_GAME_OVER: return '游戏结束';
    default: return '';
  }
}

// ─── Grid cell component ───────────────────────────────────────────────────────

@Component
struct RGCell {
  @Prop cellIdx: number = 0;
  @Prop isInPattern: boolean = false;
  @Prop isSelected: boolean = false;
  @Prop gameState: string = RG_READY;
  onCellClick: (idx: number) => void = () => {};

  private cellBg(): string {
    if (this.gameState === RG_LEVEL_COMPLETE && this.isInPattern) return '#4CAF50';
    if (this.gameState === RG_SHOW_FAILURE && this.isInPattern) return '#F44336';
    if (this.gameState === RG_SHOW_CHALLENGE && this.isInPattern) return '#009688';
    if (this.gameState === RG_PLAYER_TURN && this.isSelected) return '#2196F3';
    return '#E0E0E0';
  }

  private cellIcon(): string {
    if (this.gameState === RG_LEVEL_COMPLETE && this.isInPattern) return '✓';
    if (this.gameState === RG_SHOW_FAILURE && this.isInPattern) return '✗';
    if (this.gameState === RG_SHOW_CHALLENGE && this.isInPattern) return '●';
    if (this.gameState === RG_PLAYER_TURN && this.isSelected) return '●';
    return '';
  }

  private showIcon(): boolean {
    if (this.gameState === RG_LEVEL_COMPLETE && this.isInPattern) return true;
    if (this.gameState === RG_SHOW_FAILURE && this.isInPattern) return true;
    if (this.gameState === RG_SHOW_CHALLENGE && this.isInPattern) return true;
    if (this.gameState === RG_PLAYER_TURN && this.isSelected) return true;
    return false;
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.cellBg())
        .borderRadius(10)
        .border({
          width: this.showIcon() ? 2 : 0,
          color: '#FFFFFF'
        })
        .animation({ duration: 180, curve: Curve.EaseOut })

      if (this.showIcon()) {
        Text(this.cellIcon())
          .fontSize(20)
          .fontColor('#FFFFFF')
          .fontWeight(FontWeight.Bold)
      }
    }
    .width('100%')
    .height('100%')
    .onClick(() => {
      if (this.gameState === RG_PLAYER_TURN) {
        this.onCellClick(this.cellIdx);
      }
    })
  }
}

// ─── Rotating grid view ────────────────────────────────────────────────────────

@Component
struct RotatingGridView {
  @Prop gridSize: number = 3;
  @Prop pattern: number[] = [];
  @Prop userSelections: number[] = [];
  @Prop gameState: string = RG_READY;
  @Prop displayAngle: number = 0;
  @Prop animDuration: number = 0;
  onCellClick: (idx: number) => void = () => {};

  build() {
    Grid() {
      ForEach(
        makeRange(this.gridSize * this.gridSize),
        (pos: number) => {
          GridItem() {
            RGCell({
              cellIdx: pos,
              isInPattern: this.pattern.includes(pos),
              isSelected: this.userSelections.includes(pos),
              gameState: this.gameState,
              onCellClick: (p: number) => this.onCellClick(p)
            })
          }
        },
        (pos: number) => `rg_${pos}`
      )
    }
    .columnsTemplate(repeatStr('1fr', this.gridSize, ' '))
    .rowsTemplate(repeatStr('1fr', this.gridSize, ' '))
    .columnsGap(7)
    .rowsGap(7)
    .width('100%')
    .aspectRatio(1)
    .padding(4)
    .rotate({ angle: this.displayAngle })
    .animation({ duration: this.animDuration, curve: Curve.FastOutSlowIn })
  }
}

// ─── Pause dialog ──────────────────────────────────────────────────────────────

@Component
struct RGPauseDialog {
  @Prop visible: boolean = false;
  onResume: () => void = () => {};
  onRestart: () => void = () => {};
  onExit: () => void = () => {};

  build() {
    if (this.visible) {
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.5)')

        Column({ space: 14 }) {
          Text('游戏暂停')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#000000')

          Text('旋转网格')
            .fontSize(14)
            .fontColor('#757575')

          Divider().color('#E0E0E0')

          Button({ type: ButtonType.Normal }) {
            Row({ space: 8 }) {
              Text('▶').fontSize(16).fontColor('#FFFFFF')
              Text('继续游戏').fontSize(16).fontColor('#FFFFFF')
            }.justifyContent(FlexAlign.Center)
          }
          .width('100%').height(52).backgroundColor('#4CAF50').borderRadius(10)
          .onClick(() => this.onResume())

          Button({ type: ButtonType.Normal }) {
            Row({ space: 8 }) {
              Text('↺').fontSize(16).fontColor('#FFFFFF')
              Text('重新开始').fontSize(16).fontColor('#FFFFFF')
            }.justifyContent(FlexAlign.Center)
          }
          .width('100%').height(52).backgroundColor('#2196F3').borderRadius(10)
          .onClick(() => this.onRestart())

          Button({ type: ButtonType.Normal }) {
            Row({ space: 8 }) {
              Text('✕').fontSize(16).fontColor('#FFFFFF')
              Text('退出游戏').fontSize(16).fontColor('#FFFFFF')
            }.justifyContent(FlexAlign.Center)
          }
          .width('100%').height(52).backgroundColor('#F44336').borderRadius(10)
          .onClick(() => this.onExit())
        }
        .padding(24)
        .backgroundColor('#FFFFFF')
        .borderRadius(16)
        .shadow({ radius: 16, color: '#3A000000', offsetX: 0, offsetY: 8 })
        .width('85%')
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .position({ x: 0, y: 0 })
      .zIndex(100)
    }
  }
}

// ─── Game over overlay ─────────────────────────────────────────────────────────

@Component
struct RGGameOverOverlay {
  @Prop visible: boolean = false;
  @Prop score: number = 0;
  @Prop level: number = 1;
  @Prop stars: number = 0;
  onPlayAgain: () => void = () => {};
  onExit: () => void = () => {};

  build() {
    if (this.visible) {
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.6)')

        Column({ space: 18 }) {
          Text('游戏结束')
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor('#000000')

          Row({ space: 6 }) {
            Text(this.stars >= 1 ? '★' : '☆').fontSize(38)
              .fontColor(this.stars >= 1 ? '#FFC107' : '#BDBDBD')
            Text(this.stars >= 2 ? '★' : '☆').fontSize(38)
              .fontColor(this.stars >= 2 ? '#FFC107' : '#BDBDBD')
            Text(this.stars >= 3 ? '★' : '☆').fontSize(38)
              .fontColor(this.stars >= 3 ? '#FFC107' : '#BDBDBD')
          }

          Column({ space: 8 }) {
            Row({ space: 6 }) {
              Text('最终得分：').fontSize(16).fontColor('#424242')
              Text(this.score.toString()).fontSize(22).fontWeight(FontWeight.Bold)
                .fontColor('#2196F3')
            }
            Row({ space: 6 }) {
              Text('到达关卡：').fontSize(16).fontColor('#424242')
              Text(this.level.toString()).fontSize(22).fontWeight(FontWeight.Bold)
                .fontColor('#4CAF50')
            }
          }

          Button({ type: ButtonType.Normal }) {
            Text('再玩一次').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
          }
          .width('100%').height(56).backgroundColor('#4CAF50').borderRadius(12)
          .onClick(() => this.onPlayAgain())

          Button({ type: ButtonType.Normal }) {
            Text('退出游戏').fontSize(16).fontColor('#FFFFFF')
          }
          .width('100%').height(48).backgroundColor('#F44336').borderRadius(12)
          .onClick(() => this.onExit())
        }
        .padding(28)
        .backgroundColor('#FFFFFF')
        .borderRadius(20)
        .shadow({ radius: 20, color: '#3A000000', offsetX: 0, offsetY: 8 })
        .width('85%')
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .position({ x: 0, y: 0 })
      .zIndex(200)
    }
  }
}

// ─── Main page ─────────────────────────────────────────────────────────────────

@Entry
@Component
struct RotatingGridPage {
  // ── State ──────────────────────────────────────────
  @State private gameState: string = RG_READY;
  @State private level: number = 1;
  @State private score: number = 0;
  @State private lives: number = 3;
  @State private timeRemaining: number = 60;
  @State private gridSize: number = 3;
  @State private winCells: number = 3;
  @State private pattern: number[] = [];
  @State private userSelections: number[] = [];
  @State private rotationAngle: number = 90;
  @State private displayAngle: number = 0;
  @State private animDuration: number = 0;
  @State private isPaused: boolean = false;
  @State private isGameOver: boolean = false;
  @State private showReadyTimer: boolean = false;
  @State private readyTimerSec: number = 3;

  // ── Flow control ───────────────────────────────────
  private flowId: number = 0;
  private countdownId: number = -1;

  // ── Lifecycle ──────────────────────────────────────
  aboutToAppear(): void {
    this.startGame();
  }

  aboutToDisappear(): void {
    this.flowId = this.flowId + 1;
    this.clearCountdown();
  }

  // ─── Game control ──────────────────────────────────────────────────────────────

  private startGame(): void {
    this.clearCountdown();
    this.level = 1;
    this.score = 0;
    this.lives = 3;
    this.timeRemaining = 60;
    this.isPaused = false;
    this.isGameOver = false;
    this.userSelections = [];
    this.displayAngle = 0;
    this.animDuration = 0;
    this.updateGridParams();
    this.startCountdown();
    this.startLevelFlow();
  }

  private updateGridParams(): void {
    this.gridSize = rgCalcGridSize(this.level);
    this.winCells = rgCalcWinCells(this.level, this.gridSize);
  }

  private startLevelFlow(): void {
    this.flowId = this.flowId + 1;
    const myFlow = this.flowId;

    // Reset rotation instantly
    this.animDuration = 0;
    this.displayAngle = 0;

    // Pick rotation angle for this level
    const angle = pickRotationAngle();
    this.rotationAngle = angle;

    // Generate pattern
    this.pattern = rgGeneratePattern(this.gridSize, this.winCells);
    this.userSelections = [];

    this.runLevelFlow(myFlow);
  }

  private async runLevelFlow(flowId: number): Promise<void> {
    const alive = (): boolean => this.flowId === flowId && !this.isPaused && !this.isGameOver;
    const sleep = (ms: number): Promise<void> => new Promise(r => setTimeout(r, ms));

    // ── READY: 3-2-1 countdown ────────────────────────
    this.gameState = RG_READY;
    this.showReadyTimer = true;
    this.readyTimerSec = 3;

    await sleep(267); if (!alive()) return;
    this.readyTimerSec = 2;
    await sleep(267); if (!alive()) return;
    this.readyTimerSec = 1;
    await sleep(266); if (!alive()) return;
    this.readyTimerSec = 0;
    await sleep(200); if (!alive()) return;
    this.showReadyTimer = false;

    // ── GRID_ANIMATION ────────────────────────────────
    this.gameState = RG_GRID_ANIM;
    await sleep(1000); if (!alive()) return;

    // ── SHOW_CHALLENGE ────────────────────────────────
    this.gameState = RG_SHOW_CHALLENGE;
    const showDuration = 1200 + this.level * 200;
    await sleep(showDuration); if (!alive()) return;

    // ── ROTATING: animate grid ────────────────────────
    this.gameState = RG_ROTATING;
    this.animDuration = 2000;
    this.displayAngle = this.rotationAngle;
    await sleep(2000); if (!alive()) return;

    // ── PLAYER_TURN: wait for submit ──────────────────
    this.gameState = RG_PLAYER_TURN;
  }

  // ─── Cell click ────────────────────────────────────────────────────────────────

  private onCellClick(pos: number): void {
    if (this.gameState !== RG_PLAYER_TURN) return;
    const sel = [...this.userSelections];
    const idx = sel.indexOf(pos);
    if (idx >= 0) {
      sel.splice(idx, 1);
    } else {
      sel.push(pos);
    }
    this.userSelections = sel;
  }

  // ─── Submit answer ─────────────────────────────────────────────────────────────

  private submitAnswer(): void {
    if (this.gameState !== RG_PLAYER_TURN) return;

    const expectedPositions = rotatePattern(this.pattern, this.gridSize, this.rotationAngle);
    const isCorrect = arraysMatch(expectedPositions, this.userSelections);

    if (isCorrect) {
      const levelScore = 10 + this.level * 2;
      this.score = this.score + levelScore;
      this.gameState = RG_LEVEL_COMPLETE;

      setTimeout(() => {
        if (this.isGameOver || this.isPaused) return;
        this.level = this.level + 1;
        this.updateGridParams();
        this.startLevelFlow();
      }, 500);
    } else {
      this.lives = this.lives - 1;
      if (this.lives <= 0) {
        this.lives = 0;
        this.gameState = RG_GAME_OVER;
        this.flowId = this.flowId + 1;
        this.clearCountdown();
        this.isGameOver = true;
      } else {
        this.userSelections = [];
        this.gameState = RG_SHOW_FAILURE;
        setTimeout(() => {
          if (this.isPaused || this.isGameOver) return;
          this.startLevelFlow();
        }, 1000);
      }
    }
  }

  // ─── Countdown ─────────────────────────────────────────────────────────────────

  private startCountdown(): void {
    this.clearCountdown();
    this.countdownId = setInterval(() => {
      this.timeRemaining = this.timeRemaining - 1;
      if (this.timeRemaining <= 0) {
        this.timeRemaining = 0;
        this.clearCountdown();
        this.gameState = RG_GAME_OVER;
        this.flowId = this.flowId + 1;
        this.isGameOver = true;
      }
    }, 1000);
  }

  private clearCountdown(): void {
    if (this.countdownId !== -1) {
      clearInterval(this.countdownId);
      this.countdownId = -1;
    }
  }

  // ─── Pause / resume ────────────────────────────────────────────────────────────

  private pauseGame(): void {
    if (this.isGameOver) return;
    this.flowId = this.flowId + 1;
    this.clearCountdown();
    this.isPaused = true;
  }

  private resumeGame(): void {
    this.isPaused = false;
    this.startCountdown();
    if (this.gameState === RG_PLAYER_TURN) {
      // Stay in player turn, user continues selecting
    } else {
      this.startLevelFlow();
    }
  }

  private restartGame(): void {
    this.isPaused = false;
    this.startGame();
  }

  private exitGame(): void {
    this.clearCountdown();
    this.flowId = this.flowId + 1;
    router.back();
  }

  // ─── Timer display ─────────────────────────────────────────────────────────────

  private timerText(): string {
    const m = Math.floor(this.timeRemaining / 60);
    const s = this.timeRemaining % 60;
    const ss = s < 10 ? `0${s}` : `${s}`;
    return `${m}:${ss}`;
  }

  // ─── Build ─────────────────────────────────────────────────────────────────────

  build() {
    Stack() {
      Column() {
        // ── Top bar ────────────────────────────────────
        Row() {
          Button({ type: ButtonType.Circle }) {
            Text('⏸').fontSize(18).fontColor('#000000')
          }
          .width(44).height(44)
          .backgroundColor('rgba(0,0,0,0.06)')
          .onClick(() => this.pauseGame())

          Blank()

          Text('旋转网格')
            .fontSize(18).fontColor('#000000').fontWeight(FontWeight.Normal)

          Blank()

          Row({ space: 4 }) {
            ForEach(
              [0, 1, 2] as number[],
              (i: number) => {
                Text(i < this.lives ? '❤' : '♡')
                  .fontSize(20)
                  .fontColor(i < this.lives ? '#F44336' : '#BDBDBD')
              },
              (i: number) => `life_${i}`
            )
          }
        }
        .width('100%').height(56)
        .padding({ left: 12, right: 12 })
        .alignItems(VerticalAlign.Center)

        // ── Level + timer bar ──────────────────────────
        Row() {
          Text(`关卡 ${this.level}`)
            .fontSize(14).fontColor('#424242')
          Blank()
          Text(`⏱ ${this.timerText()}`)
            .fontSize(14)
            .fontColor(this.timeRemaining <= 10 ? '#F44336' : '#424242')
            .fontWeight(this.timeRemaining <= 10 ? FontWeight.Bold : FontWeight.Normal)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 2, bottom: 4 })

        Divider().color('#E0E0E0').strokeWidth(1)

        // ── Game content ───────────────────────────────
        Stack() {
          Column({ space: 16 }) {
            // State indicator
            Text(rgStateLabel(this.gameState, Math.abs(this.rotationAngle)))
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(rgStateColor(this.gameState))
              .textAlign(TextAlign.Center)
              .width('100%')
              .padding({ top: 12, bottom: 12, left: 16, right: 16 })
              .backgroundColor(this.tintBg(rgStateColor(this.gameState)))
              .borderRadius(14)
              .shadow({ radius: 3, color: '#12000000', offsetX: 0, offsetY: 2 })
              .scale({
                x: (this.gameState === RG_LEVEL_COMPLETE ||
                    this.gameState === RG_SHOW_FAILURE) ? 1.06 : 1.0,
                y: (this.gameState === RG_LEVEL_COMPLETE ||
                    this.gameState === RG_SHOW_FAILURE) ? 1.06 : 1.0
              })
              .animation({ duration: 250, curve: Curve.FastOutSlowIn })

            // Rotating grid
            RotatingGridView({
              gridSize: this.gridSize,
              pattern: this.pattern,
              userSelections: this.userSelections,
              gameState: this.gameState,
              displayAngle: this.displayAngle,
              animDuration: this.animDuration,
              onCellClick: (p: number) => this.onCellClick(p)
            })

            // Submit button (PLAYER_TURN only)
            if (this.gameState === RG_PLAYER_TURN) {
              Button({ type: ButtonType.Normal }) {
                Text('提交答案')
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#FFFFFF')
              }
              .width('100%')
              .height(56)
              .backgroundColor(this.userSelections.length > 0 ? '#009688' : '#B0BEC5')
              .borderRadius(12)
              .enabled(this.userSelections.length > 0)
              .onClick(() => this.submitAnswer())
              .animation({ duration: 200, curve: Curve.EaseOut })
            }
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .padding({ top: 16, bottom: 16, left: 16, right: 16 })

          // Ready timer overlay
          if (this.showReadyTimer) {
            Stack() {
              Column()
                .width('100%').height('100%')
                .backgroundColor('rgba(229,246,254,0.85)')

              Column({ space: 16 }) {
                Stack() {
                  Circle()
                    .width(110).height(110)
                    .fill('#FFFFFF')
                    .shadow({ radius: 6, color: '#22000000', offsetX: 0, offsetY: 3 })
                  Text(this.readyTimerSec > 0 ? this.readyTimerSec.toString() : '✓')
                    .fontSize(48).fontWeight(FontWeight.Bold).fontColor('#4CAF50')
                }
                .width(110).height(110)

                Text('准备好！')
                  .fontSize(22).fontWeight(FontWeight.Bold).fontColor('#4CAF50')
              }
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
            }
            .width('100%').height('100%')
          }
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%').height('100%')
      .backgroundColor('#E5F6FE')

      // ── Pause dialog ──────────────────────────────────
      RGPauseDialog({
        visible: this.isPaused,
        onResume: () => this.resumeGame(),
        onRestart: () => this.restartGame(),
        onExit: () => this.exitGame()
      })

      // ── Game over overlay ─────────────────────────────
      RGGameOverOverlay({
        visible: this.isGameOver,
        score: this.score,
        level: this.level,
        stars: rgCalcStars(this.level),
        onPlayAgain: () => this.startGame(),
        onExit: () => this.exitGame()
      })
    }
    .width('100%').height('100%')
  }

  private tintBg(hex: string): string {
    const r = parseInt(hex.slice(1, 3), 16);
    const g = parseInt(hex.slice(3, 5), 16);
    const b = parseInt(hex.slice(5, 7), 16);
    return `rgba(${r},${g},${b},0.12)`;
  }
}
