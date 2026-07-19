/**
 * WallCell.ets - 视频墙单元组件
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
import { Channel, ChannelType, ChState } from '../model/Models';
import { MjpegClient, JpegPollClient } from '../network/StreamClient';

@Component
export struct WallCell {
  @Prop ch: Channel;
  /** 是否允许本格做视频硬解（由父级按并发上限分配） */
  @Prop allowVideo: boolean;
  onOpen: (ch: Channel) => void = () => {
  };

  @State frame: PixelMap | null = null;
  @State state: ChState = ChState.IDLE;
  @State errMsg: string = '';

  private mjpeg: MjpegClient | null = null;
  private poller: JpegPollClient | null = null;
  private player: media.AVPlayer | null = null;
  private xc: XComponentController = new XComponentController();
  private lastFrame: image.PixelMap | null = null;

  aboutToAppear(): void {
    if (this.ch.type !== ChannelType.RTSP_HTTP) {
      this.connectImageStream();
    }
    // RTSP 在 XComponent onLoad 时启动
  }

  aboutToDisappear(): void {
    this.disconnect();
  }

  connectImageStream(): void {
    if (!this.ch.enabled) {
      this.state = ChState.IDLE;
      return;
    }
    this.state = ChState.CONNECTING;
    this.errMsg = '';
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

  async startPlayer(surfaceId: string): Promise<void> {
    if (!this.ch.enabled) {
      this.state = ChState.IDLE;
      return;
    }
    this.state = ChState.CONNECTING;
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
        this.errMsg = `播放失败(${err.code})`;
      });
      player.url = this.ch.url;
    } catch (e) {
      this.state = ChState.ERROR;
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
      // 画面
      if (this.ch.type === ChannelType.RTSP_HTTP && this.allowVideo && this.ch.enabled) {
        XComponent({ id: 'cell_' + this.ch.id, type: XComponentType.SURFACE, controller: this.xc })
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
          if (this.state === ChState.CONNECTING) {
            LoadingProgress().width(22).height(22).color($r('app.color.brand_primary'))
          } else if (this.state === ChState.ERROR) {
            Text('⚠️').fontSize(18)
            Text(this.errMsg).fontSize(9).fontColor($r('app.color.text_secondary'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          } else if (this.ch.type === ChannelType.RTSP_HTTP && !this.allowVideo) {
            Text('🎞️').fontSize(18)
            Text('超出并发上限\n点击全屏播放').fontSize(9)
              .fontColor($r('app.color.text_secondary')).textAlign(TextAlign.Center)
          } else if (!this.ch.enabled) {
            Text('⏸').fontSize(18)
          }
        }
      }

      // 角标：状态点 + 名称
      Row({ space: 4 }) {
        Circle({ width: 6, height: 6 })
          .fill(this.state === ChState.LIVE ? $r('app.color.brand_ok')
            : (this.state === ChState.ERROR ? $r('app.color.brand_danger') : '#888'))
        Text(this.ch.name)
          .fontSize(9).fontColor('#FFFFFFDD')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
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
      if (this.state === ChState.ERROR) {
        // 原地重连
        this.disconnect();
        if (this.ch.type === ChannelType.RTSP_HTTP) {
          if (this.allowVideo) {
            this.startPlayer(this.xc.getXComponentSurfaceId());
          }
        } else {
          this.connectImageStream();
        }
      } else {
        this.onOpen(this.ch);
      }
    })
  }
}
