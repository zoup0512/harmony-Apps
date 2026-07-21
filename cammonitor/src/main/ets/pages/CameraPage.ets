/**
 * CameraPage.ets - 全屏单摄像头页
 *
 * 按类型分流：
 *   MJPEG / JPEG_POLL：复用取流客户端，Image(PixelMap) 渲染，支持保存快照到相册；
 *   RTSP_HTTP：XComponent + AVPlayer 硬解播放（直播流不显示进度条）。
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
import { CameraDevice, CameraType, CamPageParams, CamState } from '../model/Models';
import { MjpegClient, JpegPollClient, basicAuth } from '../network/MjpegClient';

const TAG = 'CameraPage';

@Entry
@Component
struct CameraPage {
  private mjpeg: MjpegClient | null = null;
  private poller: JpegPollClient | null = null;
  private player: media.AVPlayer | null = null;
  private xc: XComponentController = new XComponentController();
  private lastFrame: image.PixelMap | null = null;

  @State cam: CameraDevice = new CameraDevice();
  @State frame: PixelMap | null = null;
  @State state: CamState = CamState.CONNECTING;
  @State errMsg: string = '';
  @State hudVisible: boolean = true;
  @State frameCount: number = 0;

  aboutToAppear(): void {
    const params = router.getParams() as CamPageParams;
    if (params && params.camera) {
      this.cam = params.camera;
    }
    this.setOrientation(window.Orientation.AUTO_ROTATION_LANDSCAPE);
    if (this.cam.type !== CameraType.RTSP_HTTP) {
      this.startImageStream();
    }
    // RTSP/HTTP 在 XComponent onLoad 后启动
  }

  async aboutToDisappear(): Promise<void> {
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
    this.state = CamState.CONNECTING;
    const onFrame = (pm: image.PixelMap): void => {
      const old = this.lastFrame;
      this.lastFrame = pm;
      this.frame = pm;
      this.state = CamState.LIVE;
      this.frameCount++;
      if (old) {
        old.release();
      }
    };
    const onError = (msg: string): void => {
      this.state = CamState.ERROR;
      this.errMsg = msg;
    };
    if (this.cam.type === CameraType.MJPEG) {
      this.mjpeg = new MjpegClient();
      this.mjpeg.start(this.cam, onFrame, onError);
    } else {
      this.poller = new JpegPollClient();
      this.poller.start(this.cam, onFrame, onError);
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

  /** 保存当前帧到相册 */
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
      promptAction.showToast({ message: '快照已保存到相册' });
    } catch (e) {
      hilog.error(0x0001, TAG, 'saveSnapshot error: %{public}s', JSON.stringify(e));
      promptAction.showToast({ message: '保存失败（可能未授权相册）' });
    }
  }

  // ---------- RTSP / HTTP 视频 ----------

  async startPlayer(surfaceId: string): Promise<void> {
    try {
      const player = await media.createAVPlayer();
      this.player = player;
      player.on('stateChange', (state: string) => {
        if (state === 'initialized') {
          player.surfaceId = surfaceId;
          player.prepare();
        } else if (state === 'prepared') {
          this.state = CamState.LIVE;
          player.play();
        }
      });
      player.on('error', (err: BusinessError) => {
        this.state = CamState.ERROR;
        this.errMsg = `播放失败 (${err.code})`;
      });
      // 注：RTSP 摄像头的账号一般内嵌在 URL（rtsp://user:pass@ip/...）
      player.url = this.cam.url;
    } catch (e) {
      this.state = CamState.ERROR;
      this.errMsg = '播放器创建失败';
    }
  }

  async releasePlayer(): Promise<void> {
    if (this.player) {
      try {
        this.player.off('stateChange');
        this.player.off('error');
        await this.player.release();
      } catch (e) {
        // ignore
      }
      this.player = null;
    }
  }

  reconnect(): void {
    if (this.cam.type === CameraType.RTSP_HTTP) {
      this.releasePlayer().then(() => {
        this.state = CamState.CONNECTING;
        this.startPlayer(this.xc.getXComponentSurfaceId());
      });
    } else {
      this.stopImageStream();
      this.startImageStream();
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 画面
      if (this.cam.type === CameraType.RTSP_HTTP) {
        XComponent({ id: 'camplayer', type: XComponentType.SURFACE, controller: this.xc })
          .onLoad(() => {
            this.state = CamState.CONNECTING;
            this.startPlayer(this.xc.getXComponentSurfaceId());
          })
          .width('100%').height('100%')
      } else if (this.frame !== null) {
        Image(this.frame)
          .width('100%').height('100%')
          .objectFit(ImageFit.Contain)
      }

      // 加载/错误
      if (this.state === CamState.CONNECTING) {
        Column({ space: 10 }) {
          LoadingProgress().width(42).height(42).color($r('app.color.brand_primary'))
          Text('连接中…').fontSize(13).fontColor('#FFFFFFAA')
        }
      }
      if (this.state === CamState.ERROR) {
        Column({ space: 10 }) {
          Text('⚠️').fontSize(38)
          Text(this.errMsg).fontSize(14).fontColor('#FFFFFFCC')
          Row({ space: 12 }) {
            Button('重试').fontSize(13).height(34)
              .backgroundColor($r('app.color.brand_primary')).fontColor('#04121F')
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
        .hitTestBehavior(this.state === CamState.ERROR ? HitTestMode.Transparent : HitTestMode.Default)

      // HUD
      if (this.hudVisible) {
        Column() {
          // 顶部
          Row({ space: 12 }) {
            Text('‹').fontSize(30).fontColor('#fff')
              .padding({ left: 4, right: 8 })
              .onClick(() => router.back())
            Circle({ width: 8, height: 8 })
              .fill(this.state === CamState.LIVE ? $r('app.color.brand_ok') : '#888')
            Text(this.cam.name).fontSize(15).fontColor('#fff')
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Text(this.cam.type).fontSize(11).fontColor('#FFFFFF99')
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor('#FFFFFF22').borderRadius(6)
          }
          .width('100%')
          .padding({ left: 12, right: 16, top: 10 })
          .linearGradient({ angle: 180, colors: [['#000000CC', 0], ['#00000000', 1]] })
          .height(64)

          Blank()

          // 底部动作
          Row({ space: 14 }) {
            if (this.cam.type !== CameraType.RTSP_HTTP) {
              Button('📷 保存快照').fontSize(13).height(38)
                .backgroundColor('#FFFFFF22').fontColor('#fff')
                .onClick(() => this.saveSnapshot())
              Text(`已收 ${this.frameCount} 帧`).fontSize(11).fontColor('#FFFFFF99')
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
