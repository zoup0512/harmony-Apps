/**
 * PlayerPage.ets - 全屏播放页
 *
 * XComponent 提供渲染 Surface；PlayerController 驱动 AVPlayer。
 * 交互：
 *   单击        显示/隐藏控制层（3s 自动隐藏）
 *   双击        播放/暂停
 *   水平拖动    快进/快退预览，松手 seek
 *   进度条      拖拽 seek
 *   速度        0.75 / 1.0 / 1.25 / 1.5 / 2.0
 * 退出时回写断点进度；进入横屏，退出恢复竖屏。
 */
import { router, window, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { VideoItem, PlayParams } from '../model/Models';
import { PlayerController } from '../common/PlayerController';
import { MediaLibrary } from '../common/MediaLibrary';

const SPEEDS: number[] = [0.75, 1.0, 1.25, 1.5, 2.0];

@Entry
@Component
struct PlayerPage {
  private ctrl: PlayerController = new PlayerController();
  private xc: XComponentController = new XComponentController();
  private lib: MediaLibrary = MediaLibrary.getInstance();
  private hideTimer: number = -1;

  @State item: VideoItem = new VideoItem();
  @State stateText: string = '加载中…';
  @State playing: boolean = false;
  @State currentMs: number = 0;
  @State durationMs: number = 0;
  @State controlsVisible: boolean = true;
  @State speedIndex: number = 1;
  @State seeking: boolean = false;
  @State seekPreviewMs: number = 0;
  @State errorMsg: string = '';

  aboutToAppear(): void {
    const params = router.getParams() as PlayParams;
    if (params && params.item) {
      this.item = params.item;
    }
    this.ctrl.setCallbacks({
      onStateChanged: (state: string) => {
        this.playing = state === 'playing';
        if (state === 'prepared' || state === 'playing') {
          this.stateText = '';
          this.durationMs = this.ctrl.durationMs;
        } else if (state === 'completed') {
          this.stateText = '播放完成';
          this.controlsVisible = true;
        }
      },
      onProgress: (cur: number, dur: number) => {
        if (!this.seeking) {
          this.currentMs = cur;
        }
        if (dur > 0) {
          this.durationMs = dur;
        }
      },
      onVideoSize: (w: number, h: number) => {
        // 预留：可按视频宽高比调整填充模式
      },
      onError: (msg: string) => {
        this.errorMsg = msg;
        this.stateText = '';
        this.controlsVisible = true;
      }
    });
    this.setOrientation(window.Orientation.AUTO_ROTATION_LANDSCAPE);
  }

  async aboutToDisappear(): Promise<void> {
    this.clearHideTimer();
    // 回写断点
    if (this.item.id !== '' && this.currentMs > 3000) {
      await this.lib.updateProgress(this.item.id, this.currentMs, this.durationMs);
    }
    await this.ctrl.release();
    this.setOrientation(window.Orientation.PORTRAIT);
  }

  private setOrientation(o: window.Orientation): void {
    const context = getContext(this) as common.UIAbilityContext;
    window.getLastWindow(context).then((win) => {
      win.setPreferredOrientation(o);
    });
  }

  private scheduleHide(): void {
    this.clearHideTimer();
    this.hideTimer = setTimeout(() => {
      if (this.playing) {
        this.controlsVisible = false;
      }
    }, 3000);
  }

  private clearHideTimer(): void {
    if (this.hideTimer >= 0) {
      clearTimeout(this.hideTimer);
      this.hideTimer = -1;
    }
  }

  togglePlay(): void {
    if (this.playing) {
      this.ctrl.pause();
    } else {
      this.ctrl.play();
    }
    this.scheduleHide();
  }

  static fmt(ms: number): string {
    const s = Math.max(0, Math.floor(ms / 1000));
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    const ss = s % 60;
    const pad = (n: number): string => n < 10 ? '0' + n.toString() : n.toString();
    return h > 0 ? `${h}:${pad(m)}:${pad(ss)}` : `${m}:${pad(ss)}`;
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 视频渲染面
      XComponent({ id: 'player', type: XComponentType.SURFACE, controller: this.xc })
        .onLoad(() => {
          const surfaceId = this.xc.getXComponentSurfaceId();
          this.ctrl.open(this.item, surfaceId, this.item.resumeMs).then(() => {
            this.scheduleHide();
          });
        })
        .width('100%').height('100%')

      // 手势层
      Column()
        .width('100%').height('100%')
        .onClick(() => {
          this.controlsVisible = !this.controlsVisible;
          if (this.controlsVisible) {
            this.scheduleHide();
          }
        })
        .gesture(
          GestureGroup(GestureMode.Exclusive,
            TapGesture({ count: 2 }).onAction(() => this.togglePlay()),
            PanGesture({ direction: PanDirection.Horizontal })
              .onActionStart(() => {
                this.seeking = true;
                this.seekPreviewMs = this.currentMs;
                this.controlsVisible = true;
                this.clearHideTimer();
              })
              .onActionUpdate((event: GestureEvent) => {
                // 全屏宽度拖满 ≈ ±90 秒
                const deltaMs = (event.offsetX / 360) * 90000;
                this.seekPreviewMs = Math.max(0,
                  Math.min(this.durationMs, this.currentMs + deltaMs));
              })
              .onActionEnd(() => {
                this.ctrl.seek(this.seekPreviewMs);
                this.currentMs = this.seekPreviewMs;
                this.seeking = false;
                this.scheduleHide();
              })
          )
        )

      // 状态/错误
      if (this.stateText !== '' && this.errorMsg === '') {
        Column({ space: 10 }) {
          LoadingProgress().width(42).height(42).color($r('app.color.brand_primary'))
          Text(this.stateText).fontSize(13).fontColor('#FFFFFFAA')
        }
      }
      if (this.errorMsg !== '') {
        Column({ space: 10 }) {
          Text('⚠️').fontSize(38)
          Text(this.errorMsg).fontSize(14).fontColor('#FFFFFFCC')
          Button('返回').fontSize(13).height(34)
            .backgroundColor($r('app.color.bg_elevated'))
            .onClick(() => router.back())
        }
      }

      // 拖动 seek 预览
      if (this.seeking) {
        Column({ space: 4 }) {
          Text(PlayerPage.fmt(this.seekPreviewMs))
            .fontSize(26).fontWeight(FontWeight.Bold).fontColor('#fff')
          Text('/ ' + PlayerPage.fmt(this.durationMs))
            .fontSize(13).fontColor('#FFFFFF99')
        }
        .padding(16).backgroundColor('#000000AA').borderRadius(12)
      }

      // 控制层
      if (this.controlsVisible) {
        Column() {
          // 顶部：返回 + 标题
          Row({ space: 12 }) {
            Text('‹').fontSize(30).fontColor('#fff')
              .padding({ left: 4, right: 8 })
              .onClick(() => router.back())
            Text(this.item.title)
              .fontSize(15).fontColor('#fff')
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Text(SPEEDS[this.speedIndex] + 'x')
              .fontSize(13).fontColor('#fff')
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .backgroundColor('#FFFFFF22').borderRadius(8)
              .onClick(() => {
                this.speedIndex = (this.speedIndex + 1) % SPEEDS.length;
                this.ctrl.setSpeed(SPEEDS[this.speedIndex]);
                this.scheduleHide();
              })
          }
          .width('100%')
          .padding({ left: 12, right: 16, top: 10 })
          .linearGradient({ angle: 180, colors: [['#000000CC', 0], ['#00000000', 1]] })
          .height(64)

          Blank()

          // 中央播放键
          Row({ space: 46 }) {
            Text('-10s').fontSize(14).fontColor('#FFFFFFCC')
              .onClick(() => {
                this.ctrl.seek(this.currentMs - 10000);
                this.scheduleHide();
              })
            Text(this.playing ? '⏸' : '▶')
              .fontSize(46).fontColor('#fff')
              .onClick(() => this.togglePlay())
            Text('+30s').fontSize(14).fontColor('#FFFFFFCC')
              .onClick(() => {
                this.ctrl.seek(this.currentMs + 30000);
                this.scheduleHide();
              })
          }

          Blank()

          // 底部进度
          Column({ space: 2 }) {
            Row({ space: 10 }) {
              Text(PlayerPage.fmt(this.currentMs)).fontSize(11).fontColor('#fff')
              Slider({ value: this.currentMs, min: 0, max: Math.max(1, this.durationMs) })
                .layoutWeight(1)
                .selectedColor($r('app.color.brand_accent'))
                .trackColor('#FFFFFF33')
                .onChange((value: number, mode: SliderChangeMode) => {
                  if (mode === SliderChangeMode.Begin) {
                    this.seeking = true;
                    this.clearHideTimer();
                  }
                  this.seekPreviewMs = value;
                  if (mode === SliderChangeMode.End) {
                    this.ctrl.seek(value);
                    this.currentMs = value;
                    this.seeking = false;
                    this.scheduleHide();
                  }
                })
              Text(PlayerPage.fmt(this.durationMs)).fontSize(11).fontColor('#fff')
            }
            .width('100%')
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 14, top: 20 })
          .linearGradient({ angle: 0, colors: [['#000000CC', 0], ['#00000000', 1]] })
        }
        .width('100%').height('100%')
      }
    }
    .width('100%').height('100%')
    .backgroundColor(Color.Black)
  }
}
