// Shared game UI components: pause dialog, game-over overlay, top bar.

@Component
export struct GamePauseDialog {
  @Prop visible: boolean = false;
  @Prop gameName: string = '';
  onResume: () => void = () => {};
  onRestart: () => void = () => {};
  onExit: () => void = () => {};
  build() {
    if (this.visible) {
      Stack() {
        Column().width('100%').height('100%').backgroundColor('rgba(0,0,0,0.5)')
        Column({ space: 14 }) {
          Text('游戏暂停').fontSize(22).fontWeight(FontWeight.Bold).fontColor('#212121')
          Text(this.gameName).fontSize(14).fontColor('#757575')
          Divider().color('#E0E0E0')
          Button({ type: ButtonType.Normal }) {
            Row({ space: 8 }) { Text('▶').fontColor('#FFF'); Text('继续游戏').fontColor('#FFF') }.justifyContent(FlexAlign.Center)
          }.width('100%').height(50).backgroundColor('#4CAF50').borderRadius(10).onClick(() => this.onResume())
          Button({ type: ButtonType.Normal }) {
            Row({ space: 8 }) { Text('↺').fontColor('#FFF'); Text('重新开始').fontColor('#FFF') }.justifyContent(FlexAlign.Center)
          }.width('100%').height(50).backgroundColor('#2196F3').borderRadius(10).onClick(() => this.onRestart())
          Button({ type: ButtonType.Normal }) {
            Row({ space: 8 }) { Text('✕').fontColor('#FFF'); Text('退出游戏').fontColor('#FFF') }.justifyContent(FlexAlign.Center)
          }.width('100%').height(50).backgroundColor('#F44336').borderRadius(10).onClick(() => this.onExit())
        }
        .padding(24).backgroundColor('#FFF').borderRadius(16)
        .shadow({ radius: 16, color: '#3A000000', offsetX: 0, offsetY: 8 })
        .width('85%').alignItems(HorizontalAlign.Center)
      }.width('100%').height('100%').position({ x: 0, y: 0 }).zIndex(100)
    }
  }
}

@Component
export struct GameOverOverlay {
  @Prop visible: boolean = false;
  @Prop score: number = 0;
  @Prop level: number = 1;
  @Prop stars: number = 0;
  @Prop subtitle: string = '';
  onPlayAgain: () => void = () => {};
  onExit: () => void = () => {};
  build() {
    if (this.visible) {
      Stack() {
        Column().width('100%').height('100%').backgroundColor('rgba(0,0,0,0.6)')
        Column({ space: 16 }) {
          Text('游戏结束').fontSize(28).fontWeight(FontWeight.Bold).fontColor('#212121')
          if (this.subtitle.length > 0) {
            Text(this.subtitle).fontSize(14).fontColor('#757575')
          }
          Row({ space: 6 }) {
            Text(this.stars >= 1 ? '★' : '☆').fontSize(36).fontColor(this.stars >= 1 ? '#FFC107' : '#BDBDBD')
            Text(this.stars >= 2 ? '★' : '☆').fontSize(36).fontColor(this.stars >= 2 ? '#FFC107' : '#BDBDBD')
            Text(this.stars >= 3 ? '★' : '☆').fontSize(36).fontColor(this.stars >= 3 ? '#FFC107' : '#BDBDBD')
          }
          Column({ space: 8 }) {
            Row({ space: 6 }) {
              Text('得分：').fontSize(16).fontColor('#424242')
              Text(this.score.toString()).fontSize(22).fontWeight(FontWeight.Bold).fontColor('#673AB7')
            }
            Row({ space: 6 }) {
              Text('关卡：').fontSize(16).fontColor('#424242')
              Text(this.level.toString()).fontSize(22).fontWeight(FontWeight.Bold).fontColor('#4CAF50')
            }
          }
          Button({ type: ButtonType.Normal }) {
            Text('再玩一次').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
          }.width('100%').height(52).backgroundColor('#4CAF50').borderRadius(12).onClick(() => this.onPlayAgain())
          Button({ type: ButtonType.Normal }) {
            Text('退出').fontSize(16).fontColor('#FFFFFF')
          }.width('100%').height(44).backgroundColor('#F44336').borderRadius(12).onClick(() => this.onExit())
        }
        .padding(26).backgroundColor('#FFF').borderRadius(20)
        .shadow({ radius: 20, color: '#3A000000', offsetX: 0, offsetY: 8 })
        .width('85%').alignItems(HorizontalAlign.Center)
      }.width('100%').height('100%').position({ x: 0, y: 0 }).zIndex(200)
    }
  }
}

@Component
export struct GameTopBar {
  @Prop title: string = '';
  @Prop lives: number = -1;       // -1 = hide
  @Prop showLives: boolean = false;
  @Prop scoreText: string = '';   // empty = hide
  onPause: () => void = () => {};
  build() {
    Row() {
      Button({ type: ButtonType.Circle }) {
        Text('⏸').fontSize(18).fontColor('#000')
      }
      .width(44).height(44).backgroundColor('rgba(0,0,0,0.06)')
      .onClick(() => this.onPause())
      Blank()
      Text(this.title).fontSize(20).fontWeight(FontWeight.Bold).fontColor('#000')
      Blank()
      if (this.showLives) {
        Row({ space: 4 }) {
          ForEach(
            [0, 1, 2] as number[],
            (i: number) => {
              Text(i < this.lives ? '❤' : '♡').fontSize(20)
                .fontColor(i < this.lives ? '#F44336' : '#BDBDBD')
            },
            (i: number) => `tb_l_${i}`
          )
        }
      } else if (this.scoreText.length > 0) {
        Text(this.scoreText).fontSize(15).fontColor('#673AB7').fontWeight(FontWeight.Bold)
      } else {
        Text(' ').width(44)
      }
    }
    .width('100%').height(56).padding({ left: 12, right: 12 }).alignItems(VerticalAlign.Center)
  }
}

// Shared progression helpers

// GameProgression3 — used by many sub-60s timed games. Level = number of correct answers + 1.
// Stars heuristic shared across games (level-based 0..3).
export function stars3(level: number, t3: number = 30, t2: number = 20, t1: number = 10): number {
  if (level >= t3) return 3;
  if (level >= t2) return 2;
  if (level >= t1) return 1;
  return 0;
}

// Random integer in [min, max] inclusive
export function randInt(min: number, max: number): number {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

// Format milliseconds to "M:SS"
export function fmtTime(ms: number): string {
  const s = Math.max(0, Math.ceil(ms / 1000));
  const m = Math.floor(s / 60);
  const r = s % 60;
  return `${m}:${r < 10 ? '0' + r : r}`;
}

// Shuffle array (Fisher-Yates), returns new array
export function shuffled<T>(arr: T[]): T[] {
  const a: T[] = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    const t = a[i]; a[i] = a[j]; a[j] = t;
  }
  return a;
}

// Pick `n` random distinct integers from [0, total)
export function pickN(total: number, n: number): number[] {
  const all: number[] = [];
  for (let i = 0; i < total; i++) all.push(i);
  return shuffled(all).slice(0, n);
}

// GameProgression1 — used by Memory Grid, Hexagons, WhosNew, FollowPath, ImageVortex, FindThePicture
export function gp1GridSize(level: number): number {
  if (level <= 2) return 3;
  if (level <= 5) return 4;
  if (level <= 10) return 5;
  if (level <= 15) return 6;
  if (level <= 20) return 7;
  return 8;
}

export function gp1WinCells(level: number): number {
  let c: number;
  if (level === 1) c = 3;
  else if (level === 2) c = 4;
  else if (level === 3) c = 5;
  else if (level === 4) c = 6;
  else if (level === 5) c = 7;
  else if (level === 6) c = 8;
  else if (level === 7) c = 9;
  else if (level === 8) c = 10;
  else if (level === 9) c = 11;
  else if (level === 10) c = 12;
  else if (level <= 15) c = 13 + (level - 10);
  else if (level <= 20) c = 18 + (level - 15);
  else c = 23 + (level - 20);
  const gs = gp1GridSize(level);
  return Math.min(c, gs * gs - 1);
}

// Repeat a string n times with separator
export function repStr(s: string, n: number, sep: string): string {
  let out = '';
  for (let i = 0; i < n; i++) out += (i === 0 ? '' : sep) + s;
  return out;
}
