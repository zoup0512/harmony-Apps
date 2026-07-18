import { Game, GameState, TRACKS, TrackInfo } from '../game/Game';

@Entry
@Component
struct Index {
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private game: Game = new Game();
  private timerId: number = -1;
  private lastTick: number = 0;
  @State uiState: number = GameState.MENU;
  @State selectedTrack: number = 0;
  @State resultRank: number = 1;
  @State resultTime: string = '';
  @State resultBest: string = '';

  aboutToDisappear(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private startLoop(): void {
    this.lastTick = Date.now();
    this.timerId = setInterval(() => {
      const now: number = Date.now();
      let dt: number = (now - this.lastTick) / 1000;
      this.lastTick = now;
      if (dt > 0.05) {
        dt = 0.05;
      }
      this.game.update(dt);
      const w: number = this.ctx.width;
      const h: number = this.ctx.height;
      if (w > 0 && h > 0) {
        this.game.render(this.ctx, w, h);
      }
      if (this.uiState !== this.game.state) {
        if (this.game.state === GameState.FINISHED) {
          this.resultRank = this.game.finalRank;
          this.resultTime = this.game.formatTime(this.game.raceTime);
          this.resultBest = this.game.formatTime(this.game.bestLapTime);
        }
        this.uiState = this.game.state;
      }
    }, 16);
  }

  @Builder
  ControlButton(label: string, onDown: () => void, onUp: () => void) {
    Text(label)
      .width(76)
      .height(76)
      .fontSize(30)
      .fontColor('#ffffff')
      .fontWeight(FontWeight.Bold)
      .textAlign(TextAlign.Center)
      .borderRadius(38)
      .backgroundColor('rgba(0,0,0,0.35)')
      .border({ width: 2, color: 'rgba(255,255,255,0.5)' })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          onDown();
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          onUp();
        }
      })
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Canvas(this.ctx)
        .width('100%')
        .height('100%')
        .onReady(() => {
          if (this.timerId < 0) {
            this.startLoop();
          }
        })

      // ---------- 主菜单 ----------
      if (this.uiState === GameState.MENU) {
        Column() {
          Text('3D 卡丁车')
            .fontSize(42)
            .fontWeight(FontWeight.Bold)
            .fontColor('#ffffff')
            .textShadow({ radius: 8, color: '#000000', offsetX: 2, offsetY: 2 })
          Text('KART RACING')
            .fontSize(14)
            .fontColor('#ffd700')
            .letterSpacing(6)
            .margin({ top: 4, bottom: 18 })

          Row({ space: 14 }) {
            ForEach(TRACKS, (item: TrackInfo, index: number) => {
              Column({ space: 6 }) {
                Text(item.name)
                  .fontSize(20)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.selectedTrack === index ? '#1a1a2e' : '#ffffff')
                Text(item.desc)
                  .fontSize(11)
                  .fontColor(this.selectedTrack === index ? '#333344' : '#bbbbcc')
                Text(`对手 x${item.aiCount}`)
                  .fontSize(11)
                  .fontColor(this.selectedTrack === index ? '#333344' : '#bbbbcc')
              }
              .width(150)
              .padding(14)
              .borderRadius(14)
              .backgroundColor(this.selectedTrack === index ? '#ffd700' : 'rgba(0,0,0,0.45)')
              .border({
                width: 2,
                color: this.selectedTrack === index ? '#ffffff' : 'rgba(255,255,255,0.25)'
              })
              .onClick(() => {
                this.selectedTrack = index;
              })
            }, (item: TrackInfo, index: number) => `${index}`)
          }

          Button('开始比赛')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1a1a2e')
            .backgroundColor('#2ecc71')
            .width(200)
            .height(50)
            .margin({ top: 22 })
            .onClick(() => {
              this.game.startRace(this.selectedTrack);
            })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('rgba(10,10,30,0.35)')
      }

      // ---------- 比赛触控 ----------
      if (this.uiState === GameState.RACING || this.uiState === GameState.COUNTDOWN) {
        // 暂停按钮
        Text('II')
          .width(44)
          .height(44)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#ffffff')
          .textAlign(TextAlign.Center)
          .borderRadius(22)
          .backgroundColor('rgba(0,0,0,0.4)')
          .position({ x: '92%', y: '2%' })
          .onClick(() => {
            this.game.pause();
          })

        // 左侧:转向
        Row({ space: 16 }) {
          this.ControlButton('◀', (): void => {
            this.game.inputLeft = true;
          }, (): void => {
            this.game.inputLeft = false;
          })
          this.ControlButton('▶', (): void => {
            this.game.inputRight = true;
          }, (): void => {
            this.game.inputRight = false;
          })
        }
        .position({ x: 24, y: '78%' })

        // 右侧:油门/刹车
        Row({ space: 16 }) {
          this.ControlButton('B', (): void => {
            this.game.inputBrake = true;
          }, (): void => {
            this.game.inputBrake = false;
          })
          this.ControlButton('A', (): void => {
            this.game.inputAccel = true;
          }, (): void => {
            this.game.inputAccel = false;
          })
        }
        .position({ x: '100%', y: '78%' })
        .markAnchor({ x: 192, y: 0 })
      }

      // ---------- 暂停 ----------
      if (this.uiState === GameState.PAUSED) {
        Column({ space: 18 }) {
          Text('暂停')
            .fontSize(36)
            .fontWeight(FontWeight.Bold)
            .fontColor('#ffffff')
          Button('继续比赛')
            .width(180)
            .backgroundColor('#2ecc71')
            .fontColor('#1a1a2e')
            .fontWeight(FontWeight.Bold)
            .onClick(() => {
              this.game.resume();
            })
          Button('返回主菜单')
            .width(180)
            .backgroundColor('#e63946')
            .fontColor('#ffffff')
            .onClick(() => {
              this.game.quitToMenu();
            })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('rgba(0,0,0,0.55)')
      }

      // ---------- 结算 ----------
      if (this.uiState === GameState.FINISHED) {
        Column({ space: 10 }) {
          Text(this.resultRank === 1 ? '🏆 冠军!' : `第 ${this.resultRank} 名`)
            .fontSize(40)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.resultRank === 1 ? '#ffd700' : '#ffffff')
          Text(`总用时  ${this.resultTime}`)
            .fontSize(20)
            .fontColor('#ffffff')
          Text(`最快圈  ${this.resultBest}`)
            .fontSize(20)
            .fontColor('#7CFC00')

          Row({ space: 16 }) {
            Button('再来一局')
              .backgroundColor('#2ecc71')
              .fontColor('#1a1a2e')
              .fontWeight(FontWeight.Bold)
              .onClick(() => {
                this.game.startRace(this.selectedTrack);
              })
            Button('返回主菜单')
              .backgroundColor('#4a4a6a')
              .fontColor('#ffffff')
              .onClick(() => {
                this.game.quitToMenu();
              })
          }
          .margin({ top: 16 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('rgba(0,0,0,0.6)')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }
}
