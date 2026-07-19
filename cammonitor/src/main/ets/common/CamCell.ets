/**
 * CamCell.ets - 网格单元组件
 *
 * 每个单元独立持有自己的取流客户端（MJPEG 流 / JPEG 轮询），
 * 把帧渲染为 Image(PixelMap)。RTSP/HTTP 视频类型在网格中显示占位卡
 * （提示点开全屏用 AVPlayer 播放），避免多路硬解并发压力。
 * aboutToDisappear 必定停流，防泄漏。
 */
import { image } from '@kit.ImageKit';
import { CameraDevice, CameraType, CamState } from '../model/Models';
import { MjpegClient, JpegPollClient } from '../network/MjpegClient';

@Component
export struct CamCell {
  @Prop cam: CameraDevice;
  onOpen: (cam: CameraDevice) => void = () => {
  };

  @State frame: PixelMap | null = null;
  @State state: CamState = CamState.IDLE;
  @State errMsg: string = '';

  private mjpeg: MjpegClient | null = null;
  private poller: JpegPollClient | null = null;
  private lastFrame: image.PixelMap | null = null;

  aboutToAppear(): void {
    this.connect();
  }

  aboutToDisappear(): void {
    this.disconnect();
  }

  connect(): void {
    if (!this.cam.enabled) {
      this.state = CamState.IDLE;
      return;
    }
    if (this.cam.type === CameraType.RTSP_HTTP) {
      // 网格不解码视频流，点开全屏播
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
    if (this.cam.type === CameraType.MJPEG) {
      this.mjpeg = new MjpegClient();
      this.mjpeg.start(this.cam, onFrame, onError);
    } else {
      this.poller = new JpegPollClient();
      this.poller.start(this.cam, onFrame, onError);
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
    if (this.lastFrame) {
      this.lastFrame.release();
      this.lastFrame = null;
    }
    this.frame = null;
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 画面 / 占位
      if (this.frame !== null) {
        Image(this.frame)
          .width('100%').height('100%')
          .objectFit(ImageFit.Contain)
          .backgroundColor('#000')
      } else {
        Column({ space: 6 }) {
          if (this.state === CamState.CONNECTING) {
            LoadingProgress().width(26).height(26).color($r('app.color.brand_primary'))
            Text('连接中…').fontSize(11).fontColor($r('app.color.text_secondary'))
          } else if (this.state === CamState.ERROR) {
            Text('⚠️').fontSize(22)
            Text(this.errMsg).fontSize(10).fontColor($r('app.color.text_secondary'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text('点击重试').fontSize(10).fontColor($r('app.color.brand_primary'))
          } else if (this.cam.type === CameraType.RTSP_HTTP) {
            Text('🎞️').fontSize(22)
            Text('点击全屏播放').fontSize(10).fontColor($r('app.color.text_secondary'))
          } else if (!this.cam.enabled) {
            Text('⏸').fontSize(22)
            Text('已停用').fontSize(10).fontColor($r('app.color.text_secondary'))
          }
        }
      }

      // 左上：名称 + 状态点
      Row({ space: 5 }) {
        Circle({ width: 7, height: 7 })
          .fill(this.state === CamState.LIVE ? $r('app.color.brand_ok')
            : (this.state === CamState.ERROR ? $r('app.color.brand_danger') : '#888'))
        Text(this.cam.name)
          .fontSize(10).fontColor('#FFFFFFDD')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .padding({ left: 6, right: 6, top: 3, bottom: 3 })
      .backgroundColor('#00000088')
      .borderRadius(6)
      .position({ x: 6, y: 6 })
    }
    .width('100%')
    .aspectRatio(16 / 9)
    .backgroundColor('#000')
    .borderRadius(10)
    .clip(true)
    .onClick(() => {
      if (this.state === CamState.ERROR) {
        // 点卡片重连
        this.disconnect();
        this.connect();
      } else {
        this.onOpen(this.cam);
      }
    })
  }
}
