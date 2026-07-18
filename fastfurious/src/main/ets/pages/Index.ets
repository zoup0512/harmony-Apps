import { GameEngine, GameState } from '../game/GameEngine';
import { preferences } from '@kit.ArkData';

const PREF_NAME = 'game_store';
const KEY_HIGH_SCORE = 'high_score';

const CAR_RES_NAMES: string[] = [
  'car_player',
  'car_traffic_1',
  'car_traffic_2',
  'car_traffic_3',
  'car_traffic_4',
  'car_traffic_5',
  'car_traffic_6'
];

@Entry
@Component
struct Index {
  private engine: GameEngine = new GameEngine();
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private timerId: number = -1;
  private lastTime: number = 0;
  private store: preferences.Preferences | null = null;
  @State gameState: GameState = GameState.MENU;
  @State score: number = 0;
  @State highScore: number = 0;
  @State speedKmh: number = 0;
  @State nitroPercent: number = 100;
  @State canvasReady: boolean = false;
  private carImages: ImageBitmap[] = [];
  private imagesLoaded: boolean = false;

  aboutToAppear(): void {
    try {
      const context = this.getUIContext().getHostContext();
      if (context !== undefined) {
        this.store = preferences.getPreferencesSync(context, { name: PREF_NAME } as preferences.Options);
        this.highScore = this.store.getSync(KEY_HIGH_SCORE, 0) as number;
        this.engine.highScore = this.highScore;
      }
    } catch (e) {
      this.highScore = 0;
    }
    this.loadCarImages();
  }

  private loadCarImages(): void {
    const imgs: ImageBitmap[] = [];
    for (let i = 0; i < CAR_RES_NAMES.length; i++) {
      try {
        const bm = new ImageBitmap($r('app.media.' + CAR_RES_NAMES[i]));
        imgs.push(bm);
      } catch (e) {
        // 加载失败跳过，引擎会回退到程序化绘制
      }
    }
    if (imgs.length > 0) {
      this.carImages = imgs;
      this.engine.setCarImages(imgs);
      this.imagesLoaded = true;
    }
  }

  aboutToDisappear(): void {
    this.stopLoop();
  }

  private startLoop(): void {
    this.stopLoop();
    this.lastTime = Date.now();
    this.timerId = setInterval(() => {
      const now = Date.now();
      const dt = (now - this.lastTime) / 1000;
      this.lastTime = now;
      const crashed = this.engine.update(dt);
      this.engine.render(this.ctx);
      this.score = this.engine.score;
      this.speedKmh = this.engine.getSpeedKmh();
      this.nitroPercent = this.engine.nitro;
      if (crashed) {
        this.onGameOver();
      }
    }, 16);
  }

  private stopLoop(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private onGameOver(): void {
    this.gameState = GameState.GAME_OVER;
    if (this.engine.highScore > this.highScore) {
      this.highScore = this.engine.highScore;
      this.saveHighScore();
    }
    // 撞车后继续渲染一小段抖动，再停表
    setTimeout(() => {
      this.stopLoop();
    }, 600);
  }

  private saveHighScore(): void {
    if (this.store !== null) {
      try {
        this.store.putSync(KEY_HIGH_SCORE, this.highScore);
        this.store.flush();
      } catch (e) {
        // 存储失败不影响游戏
      }
    }
  }

  private startGame(): void {
    this.engine.start();
    this.gameState = GameState.PLAYING;
    this.startLoop();
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 游戏画布
      Canvas(this.ctx)
        .width('100%')
        .height('100%')
        .backgroundColor('#0d1b0d')
        .onReady(() => {
          this.engine.init(this.ctx.width, this.ctx.height);
          this.engine.render(this.ctx);
          this.canvasReady = true;
        })
        .onTouch((event: TouchEvent) => {
          if (this.gameState !== GameState.PLAYING) {
            return;
          }
          if (event.type === TouchType.Down && event.touches.length > 0) {
            const x = event.touches[0].x;
            if (x < this.ctx.width / 2) {
              this.engine.moveLeft();
            } else {
              this.engine.moveRight();
            }
          }
        })

      // ===== HUD（游戏中） =====
      if (this.gameState === GameState.PLAYING) {
        Column() {
          Row() {
            Text(`得分 ${this.score}`)
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#ffffff')
            Blank()
            Text(`${this.speedKmh} km/h`)
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#66ccff')
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 50 })

          Blank()

          // 氮气按钮 + 氮气条
          Column({ space: 8 }) {
            Progress({ value: this.nitroPercent, total: 100, type: ProgressType.Linear })
              .width(140)
              .color('#33bbff')
            Button('氮 气')
              .width(120)
              .height(56)
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .backgroundColor(this.nitroPercent > 5 ? '#0d5fb8' : '#444a55')
              .onTouch((event: TouchEvent) => {
                if (event.type === TouchType.Down) {
                  this.engine.setNitro(true);
                } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                  this.engine.setNitro(false);
                }
              })
          }
          .padding({ bottom: 40 })
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
      }

      // ===== 主菜单 =====
      if (this.gameState === GameState.MENU) {
        Stack({ alignContent: Alignment.Center }) {
          Image($r('app.media.menu_bg'))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .opacity(0.6)

          Column({ space: 16 }) {
            Image($r('app.media.title_bar'))
              .width('60%')
              .objectFit(ImageFit.Contain)
              .margin({ bottom: 8 })

            Text('速度与激情6')
              .fontSize(38)
              .fontWeight(FontWeight.Bolder)
              .fontColor('#ffffff')
              .textShadow({ radius: 12, color: '#0d5fb8', offsetX: 0, offsetY: 0 })
            Text('FAST & FURIOUS 6')
              .fontSize(14)
              .fontColor('#8899aa')
              .letterSpacing(4)
            Text(`最高分  ${this.highScore}`)
              .fontSize(18)
              .fontColor('#ffd257')
              .margin({ top: 24 })
            Button('开始游戏')
              .width(200)
              .height(56)
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .backgroundColor('#0d5fb8')
              .margin({ top: 12 })
              .enabled(this.canvasReady)
              .onClick(() => {
                this.startGame();
              })
            Text('点击屏幕左/右半边变道，按住氮气加速')
              .fontSize(13)
              .fontColor('#667788')
              .margin({ top: 30 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor('rgba(6,10,20,0.55)')
        }
        .width('100%')
        .height('100%')
      }

      // ===== 游戏结束 =====
      if (this.gameState === GameState.GAME_OVER) {
        Column({ space: 14 }) {
          Text('撞 车 了 !')
            .fontSize(40)
            .fontWeight(FontWeight.Bolder)
            .fontColor('#ff4444')
          Text(`本局得分  ${this.score}`)
            .fontSize(22)
            .fontColor('#ffffff')
            .margin({ top: 16 })
          Text(`最高分  ${this.highScore}`)
            .fontSize(18)
            .fontColor('#ffd257')
          Button('再来一局')
            .width(200)
            .height(56)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .backgroundColor('#0d5fb8')
            .margin({ top: 24 })
            .onClick(() => {
              this.startGame();
            })
          Button('返回菜单')
            .width(200)
            .height(48)
            .fontSize(18)
            .backgroundColor('#333a48')
            .onClick(() => {
              this.stopLoop();
              this.gameState = GameState.MENU;
            })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('rgba(6,10,20,0.7)')
      }
    }
    .width('100%')
    .height('100%')
  }
}
