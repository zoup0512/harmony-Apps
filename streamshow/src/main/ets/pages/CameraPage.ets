/**
 * CameraPage.ets - 全屏单路页
 *
 * MJPEG / JPEG_POLL：Image(PixelMap) 渲染，支持
 *   截图 → 相册（photoAccessHelper）
 *   录像 → 原始 JPEG 帧序列写 .mjpeg 文件（Recorder）
 * RTSP_HTTP：XComponent + AVPlayer 硬解（录像列入 2.0 路线）。
 * 进入横屏，退出恢复竖屏并释放全部资源。
 */
import { router, window, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { media } from '@kit.MediaKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Channel, ChannelType, ChPageParams, ChState } from '../model/Models';
import { MjpegClient, JpegPollClient } from '../network/StreamClient';
import { Recorder } from '../common/Recorder';

const TAG = 'CameraPage';

@Entry
@Component
struct CameraPage {
  private mjpeg: MjpegClient | null = null;
  private poller: JpegPollClient | null = null;
  private player: media.AVPlayer | null = null;
  private xc: XComponentController = new XComponentController();
  private lastFrame: image.PixelMap | null = null;
  private recorder: Recorder = new Recorder();
  private recTimer: number = -1;

  @State ch: Channel = new Channel();
  @State frame: PixelMap | null = null;
  @State state: ChState = ChState.CONNECTING;
  @State errMsg: string = '';
  @State hudVisible: boolean = true;
  @State recording: boolean = false;
  @State recSeconds: number = 0;

  aboutToAppear(): void {
    const params = router.getParams() as ChPageParams;
    if (params && params.channel) {
      this.ch = params.channel;
    }
    this.setOrientation(window.Orientation.AUTO_ROTATION_LANDSCAPE);
    if (this.ch.type !== ChannelType.RTSP_HTTP) {
      this.startImageStream();
    }
  }

  async aboutToDisappear(): Promise<void> {
    this.stopRecording(true);
    this.stopImageStream();
    await this.releasePlayer();
    this.setOrientation(window.Orientation.PORTRAIT);
  }

  private setOrientation(o: window.Orientation): void {
    const context = getContext(this) as common.UIAbilityContext;
    window.getLastWindow(context).then((win) => {
      win.setPreferredOrientation(o);
    });
  }

  // ---------- MJPEG / 轮询 ----------

  startImageStream(): void {
    this.state = ChState.CONNECTING;
    const onFrame = (pm: image.PixelMap): void => {
      const old = this.lastFrame;
      this.lastFrame = pm;
      this.frame = pm;
      this.state = ChState.LIVE;
      if (old) {
        old.release();
      }
    };
    const onError = (msg: string): void => {
      this.state = ChState.ERROR;
      this.errMsg = msg;
    };
    if (this.ch.type === ChannelType.MJPEG) {
      this.mjpeg = new MjpegClient();
      this.mjpeg.start(this.ch, onFrame, onError);
    } else {
      this.poller = new JpegPollClient();
      this.poller.start(this.ch, onFrame, onError);
    }
  }

  stopImageStream(): void {
    if (this.mjpeg) {
      this.mjpeg.stop();
      this.mjpeg = null;
    }
    if (this.poller) {
      this.poller.stop();
      this.poller = null;
    }
    if (this.lastFrame) {
      this.lastFrame.release();
      this.lastFrame = null;
    }
    this.frame = null;
  }

  // ---------- 截图 ----------

  async saveSnapshot(): Promise<void> {
    const pm = this.lastFrame;
    if (pm === null) {
      promptAction.showToast({ message: '暂无画面' });
      return;
    }
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const packer = image.createImagePacker();
      const buf = await packer.packing(pm, { format: 'image/jpeg', quality: 90 });
      packer.release();
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      const uri = await helper.createAsset(photoAccessHelper.PhotoType.IMAGE, 'jpg');
      const file = await fileIo.open(uri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      await fileIo.write(file.fd, buf);
      await fileIo.close(file.fd);
      promptAction.showToast({ message: '截图已保存到相册' });
    } catch (e) {
      hilog.error(0x0001, TAG, 'snapshot error: %{public}s', JSON.stringify(e));
      promptAction.showToast({ message: '保存失败（可能未授权相册）' });
    }
  }

  // ---------- 录像 ----------

  toggleRecording(): void {
    if (this.recording) {
      this.stopRecording(false);
      return;
    }
    const context = getContext(this) as common.UIAbilityContext;
    const path = this.recorder.start(context, this.ch.name);
    if (path === '') {
      promptAction.showToast({ message: '录像启动失败' });
      return;
    }
    // 挂钩原始帧
    const hook = (jpeg: Uint8Array): void => this.recorder.writeFrame(jpeg);
    if (this.mjpeg) {
      this.mjpeg.rawListener = hook;
    }
    if (this.poller) {
      this.poller.rawListener = hook;
    }
    this.recording = true;
    this.recSeconds = 0;
    this.recTimer = setInterval(() => {
      this.recSeconds = this.recorder.getSeconds();
    }, 1000);
    promptAction.showToast({ message: '开始录像（MJPEG 帧序列）' });
  }

  stopRecording(silent: boolean): void {
    if (!this.recording) {
      return;
    }
    if (this.mjpeg) {
      this.mjpeg.rawListener = null;
    }
    if (this.poller) {
      this.poller.rawListener = null;
    }
    if (this.recTimer >= 0) {
      clearInterval(this.recTimer);
      this.recTimer = -1;
    }
    const summary = this.recorder.stop();
    this.recording = false;
    if (!silent && summary !== '') {
      promptAction.showToast({ message: `${summary}\n${this.recorder.getFilePath()}` });
    }
  }

  // ---------- RTSP / HTTP 视频 ----------

  async startPlayer(surfaceId: string): Promise<void> {
    try {
      const player = await media.createAVPlayer();
      this.player = player;
      player.on('stateChange', (s: string) => {
        if (s === 'initialized') {
          player.surfaceId = surfaceId;
          player.prepare();
        } else if (s === 'prepared') {
          this.state = ChState.LIVE;
          player.play();
        }
      });
      player.on('error', (err: BusinessError) => {
        this.state = ChState.ERROR;
        this.errMsg = `播放失败 (${err.code})`;
      });
      player.url = this.ch.url;
    } catch (e) {
      this.state = ChState.ERROR;
      this.errMsg = '播放器创建失败';
    }
  }

  async releasePlayer(): Promise<void> {
    if (this.player) {
      try {
        this.player.off('stateChange');
        this.player.off('error');
        await this.player.release();
      } catch (e) { /* ignore */
      }
      this.player = null;
    }
  }

  reconnect(): void {
    if (this.ch.type === ChannelType.RTSP_HTTP) {
      this.releasePlayer().then(() => {
        this.state = ChState.CONNECTING;
        this.startPlayer(this.xc.getXComponentSurfaceId());
      });
    } else {
      const wasRecording = this.recording;
      this.stopRecording(true);
      this.stopImageStream();
      this.startImageStream();
      if (wasRecording) {
        this.toggleRecording();
      }
    }
  }

  static fmtRec(sec: number): string {
    const m = Math.floor(sec / 60);
    const s = sec % 60;
    const pad = (n: number): string => n < 10 ? '0' + n.toString() : n.toString();
    return `${pad(m)}:${pad(s)}`;
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 画面
      if (this.ch.type === ChannelType.RTSP_HTTP) {
        XComponent({ id: 'fsplayer', type: XComponentType.SURFACE, controller: this.xc })
          .onLoad(() => {
            this.state = ChState.CONNECTING;
            this.startPlayer(this.xc.getXComponentSurfaceId());
          })
          .width('100%').height('100%')
      } else if (this.frame !== null) {
        Image(this.frame)
          .width('100%').height('100%')
          .objectFit(ImageFit.Contain)
      }

      if (this.state === ChState.CONNECTING) {
        Column({ space: 10 }) {
          LoadingProgress().width(42).height(42).color($r('app.color.brand_primary'))
          Text('连接中…').fontSize(13).fontColor('#FFFFFFAA')
        }
      }
      if (this.state === ChState.ERROR) {
        Column({ space: 10 }) {
          Text('⚠️').fontSize(38)
          Text(this.errMsg).fontSize(14).fontColor('#FFFFFFCC')
          Row({ space: 12 }) {
            Button('重试').fontSize(13).height(34)
              .backgroundColor($r('app.color.brand_primary')).fontColor('#03211D')
              .onClick(() => this.reconnect())
            Button('返回').fontSize(13).height(34)
              .backgroundColor($r('app.color.bg_elevated'))
              .onClick(() => router.back())
          }
        }
      }

      // 点击切换 HUD
      Column()
        .width('100%').height('100%')
        .onClick(() => {
          this.hudVisible = !this.hudVisible;
        })
        .hitTestBehavior(this.state === ChState.ERROR ? HitTestMode.Transparent : HitTestMode.Default)

      // HUD
      if (this.hudVisible) {
        Column() {
          Row({ space: 12 }) {
            Text('‹').fontSize(30).fontColor('#fff')
              .padding({ left: 4, right: 8 })
              .onClick(() => router.back())
            Circle({ width: 8, height: 8 })
              .fill(this.state === ChState.LIVE ? $r('app.color.brand_ok') : '#888')
            Text(this.ch.name).fontSize(15).fontColor('#fff')
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            if (this.recording) {
              Row({ space: 5 }) {
                Circle({ width: 8, height: 8 }).fill($r('app.color.brand_danger'))
                Text('REC ' + CameraPage.fmtRec(this.recSeconds))
                  .fontSize(12).fontColor('#fff')
              }
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor('#E8453C44').borderRadius(6)
            }
            Text(this.ch.type).fontSize(11).fontColor('#FFFFFF99')
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor('#FFFFFF22').borderRadius(6)
          }
          .width('100%')
          .padding({ left: 12, right: 16, top: 10 })
          .linearGradient({ angle: 180, colors: [['#000000CC', 0], ['#00000000', 1]] })
          .height(64)

          Blank()

          Row({ space: 14 }) {
            if (this.ch.type !== ChannelType.RTSP_HTTP) {
              Button('📷 截图').fontSize(13).height(38)
                .backgroundColor('#FFFFFF22').fontColor('#fff')
                .onClick(() => this.saveSnapshot())
              Button(this.recording ? '⏹ 停止录像' : '⏺ 录像')
                .fontSize(13).height(38)
                .backgroundColor(this.recording ? $r('app.color.brand_danger') : '#FFFFFF22')
                .fontColor('#fff')
                .onClick(() => this.toggleRecording())
            } else {
              Text('RTSP 录像与截图列入 2.0（需要解复用/取帧能力）')
                .fontSize(11).fontColor('#FFFFFF88')
            }
            Blank()
            Button('重连').fontSize(13).height(38)
              .backgroundColor('#FFFFFF22').fontColor('#fff')
              .onClick(() => this.reconnect())
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 14, top: 22 })
          .linearGradient({ angle: 0, colors: [['#000000CC', 0], ['#00000000', 1]] })
        }
        .width('100%').height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
      }
    }
    .width('100%').height('100%')
    .backgroundColor(Color.Black)
  }
}
