/**
 * QuadCell.ets - 四分屏单元组件
 *
 * 每格独立取流生命周期：
 *   MJPEG / JPEG_POLL → Image(PixelMap) 实时渲染；
 *   RTSP_HTTP → allowVideo=true 时内嵌 XComponent + AVPlayer 硬解，
 *               超出并发上限的格子显示占位卡（点开全屏播放）。
 * aboutToDisappear 必定停流/释放播放器。
 */
import { image } from '@kit.ImageKit';
import { media } from '@kit.MediaKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Camera, CamKind, CamState } from '../model/Models';
import { MjpegClient, JpegPollClient } from '../network/StreamClient';

@Component
export struct QuadCell {
  @Prop cam: Camera;
  /** 是否允许本格做视频硬解（由父级按并发上限分配） */
  @Prop allowVideo: boolean;
  onOpen: (cam: Camera) => void = () => {
  };

  @State frame: PixelMap | null = null;
  @State state: CamState = CamState.IDLE;
  @State errMsg: string = '';

  private mjpeg: MjpegClient | null = null;
  private poller: JpegPollClient | null = null;
  private player: media.AVPlayer | null = null;
  private xc: XComponentController = new XComponentController();
  private lastFrame: image.PixelMap | null = null;

  aboutToAppear(): void {
    if (this.cam.kind !== CamKind.RTSP_HTTP) {
      this.connectImageStream();
    }
    // RTSP 在 XComponent onLoad 时启动
  }

  aboutToDisappear(): void {
    this.disconnect();
  }

  connectImageStream(): void {
    if (!this.cam.enabled) {
      this.state = CamState.IDLE;
      return;
    }
    this.state = CamState.CONNECTING;
    this.errMsg = '';
    const onFrame = (pm: image.PixelMap): void => {
      const old = this.lastFrame;
      this.lastFrame = pm;
      this.frame = pm;
      this.state = CamState.LIVE;
      if (old) {
        old.release();
      }
    };
    const onError = (msg: string): void => {
      this.state = CamState.ERROR;
      this.errMsg = msg;
    };
    if (this.cam.kind === CamKind.MJPEG) {
      this.mjpeg = new MjpegClient();
      this.mjpeg.start(this.cam, onFrame, onError);
    } else {
      this.poller = new JpegPollClient();
      this.poller.start(this.cam, onFrame, onError);
    }
  }

  async startPlayer(surfaceId: string): Promise<void> {
    if (!this.cam.enabled) {
      this.state = CamState.IDLE;
      return;
    }
    this.state = CamState.CONNECTING;
    try {
      const player = await media.createAVPlayer();
      this.player = player;
      player.on('stateChange', (s: string) => {
        if (s === 'initialized') {
          player.surfaceId = surfaceId;
          player.prepare();
        } else if (s === 'prepared') {
          this.state = CamState.LIVE;
          player.play();
        }
      });
      player.on('error', (err: BusinessError) => {
        this.state = CamState.ERROR;
        this.errMsg = `播放失败(${err.code})`;
      });
      player.url = this.cam.url;
    } catch (e) {
      this.state = CamState.ERROR;
      this.errMsg = '播放器创建失败';
    }
  }

  disconnect(): void {
    if (this.mjpeg) {
      this.mjpeg.stop();
      this.mjpeg = null;
    }
    if (this.poller) {
      this.poller.stop();
      this.poller = null;
    }
    if (this.player) {
      const p = this.player;
      this.player = null;
      try {
        p.off('stateChange');
        p.off('error');
        p.release();
      } catch (e) { /* ignore */
      }
    }
    if (this.lastFrame) {
      this.lastFrame.release();
      this.lastFrame = null;
    }
    this.frame = null;
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.cam.kind === CamKind.RTSP_HTTP && this.allowVideo && this.cam.enabled) {
        XComponent({ id: 'quad_' + this.cam.id, type: XComponentType.SURFACE, controller: this.xc })
          .onLoad(() => {
            this.startPlayer(this.xc.getXComponentSurfaceId());
          })
          .width('100%').height('100%')
      } else if (this.frame !== null) {
        Image(this.frame)
          .width('100%').height('100%')
          .objectFit(ImageFit.Contain)
          .backgroundColor('#000')
      } else {
        Column({ space: 5 }) {
          if (this.state === CamState.CONNECTING) {
            LoadingProgress().width(22).height(22).color($r('app.color.brand_primary'))
          } else if (this.state === CamState.ERROR) {
            Text('⚠️').fontSize(18)
            Text(this.errMsg).fontSize(9).fontColor($r('app.color.text_secondary'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          } else if (this.cam.kind === CamKind.RTSP_HTTP && !this.allowVideo) {
            Text('🎞️').fontSize(18)
            Text('超出并发上限\n点击全屏播放').fontSize(9)
              .fontColor($r('app.color.text_secondary')).textAlign(TextAlign.Center)
          } else if (!this.cam.enabled) {
            Text('⏸').fontSize(18)
          }
        }
      }

      // 角标：状态点 + 名称 + PTZ 标记
      Row({ space: 4 }) {
        Circle({ width: 6, height: 6 })
          .fill(this.state === CamState.LIVE ? $r('app.color.brand_ok')
            : (this.state === CamState.ERROR ? $r('app.color.brand_danger') : '#888'))
        Text(this.cam.name)
          .fontSize(9).fontColor('#FFFFFFDD')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.cam.ptz) {
          Text('PTZ').fontSize(8).fontColor('#0B1B33')
            .padding({ left: 3, right: 3, top: 1, bottom: 1 })
            .backgroundColor($r('app.color.brand_primary')).borderRadius(3)
        }
      }
      .padding({ left: 5, right: 5, top: 2, bottom: 2 })
      .backgroundColor('#00000088')
      .borderRadius(5)
      .position({ x: 4, y: 4 })
    }
    .width('100%')
    .aspectRatio(16 / 9)
    .backgroundColor('#000')
    .borderRadius(8)
    .clip(true)
    .onClick(() => {
      if (this.state === CamState.ERROR) {
        // 原地重连
        this.disconnect();
        if (this.cam.kind === CamKind.RTSP_HTTP) {
          if (this.allowVideo) {
            this.startPlayer(this.xc.getXComponentSurfaceId());
          }
        } else {
          this.connectImageStream();
        }
      } else {
        this.onOpen(this.cam);
      }
    })
  }
}
