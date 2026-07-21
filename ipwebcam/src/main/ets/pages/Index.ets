/**
 * Index.ets - 主页面
 *
 * 结构：本地预览(XComponent) → 状态卡(访问地址/观看数/帧率) →
 *       启停大按钮 → 参数区(前后置/分辨率/质量/帧率/端口/手电)
 */
import { promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { WebcamController } from '../common/WebcamController';
import { ServerState, ServerStats, StreamConfig, Resolution } from '../model/Models';

const RESOLUTIONS: Resolution[] = [
  new Resolution(640, 480),
  new Resolution(1280, 720),
  new Resolution(1920, 1080)
];

@Entry
@Component
struct Index {
  private ctrl: WebcamController = WebcamController.getInstance();
  private xController: XComponentController = new XComponentController();
  private surfaceId: string = '';

  @State config: StreamConfig = new StreamConfig();
  @State stats: ServerStats = new ServerStats();
  @State torchOn: boolean = false;
  @State busy: boolean = false;

  aboutToAppear(): void {
    this.ctrl.onStats((s: ServerStats) => {
      this.stats = s;
    });
  }

  get running(): boolean {
    return this.stats.state === ServerState.RUNNING;
  }

  async toggleServer(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    if (this.running) {
      await this.ctrl.stop();
      this.torchOn = false;
    } else {
      if (this.surfaceId === '') {
        promptAction.showToast({ message: '预览未就绪，请稍候再试' });
        this.busy = false;
        return;
      }
      const context = getContext(this) as common.UIAbilityContext;
      const ok = await this.ctrl.start(context, this.surfaceId, this.config);
      if (!ok) {
        promptAction.showToast({ message: this.stats.accessUrl !== '' ? this.stats.accessUrl : '启动失败，请检查权限与网络' });
      }
    }
    this.busy = false;
  }

  copyUrl(): void {
    if (this.stats.accessUrl === '') {
      return;
    }
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.stats.accessUrl);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      promptAction.showToast({ message: '地址已复制' });
    });
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        this.Preview()
        this.StatusCard()
        this.StartButton()
        if (!this.running) {
          this.Settings()
        } else {
          this.RuntimeControls()
        }
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_dark'))
    .scrollBar(BarState.Off)
  }

  // ---------- 预览 ----------
  @Builder
  Preview() {
    Stack({ alignContent: Alignment.TopStart }) {
      XComponent({
        id: 'preview',
        type: XComponentType.SURFACE,
        controller: this.xController
      })
        .onLoad(() => {
          this.surfaceId = this.xController.getXComponentSurfaceId();
        })
        .width('100%')
        .aspectRatio(16 / 9)
        .backgroundColor('#000')
        .borderRadius(14)

      if (this.running) {
        Row({ space: 6 }) {
          Circle({ width: 8, height: 8 }).fill($r('app.color.brand_danger'))
          Text('直播中').fontSize(11).fontColor('#fff')
        }
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .backgroundColor('#00000088')
        .borderRadius(10)
        .margin(10)
      }
    }
  }

  // ---------- 状态卡 ----------
  @Builder
  StatusCard() {
    Column({ space: 10 }) {
      Row() {
        Text('访问地址').fontSize(13).fontColor($r('app.color.text_secondary'))
        Blank()
        Text(this.stateText())
          .fontSize(12)
          .fontColor(this.running ? $r('app.color.brand_primary') : $r('app.color.text_secondary'))
      }.width('100%')

      Row({ space: 8 }) {
        Text(this.running ? this.stats.accessUrl : '服务未启动')
          .fontSize(this.running ? 18 : 14)
          .fontWeight(this.running ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.running ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
          .layoutWeight(1)
        if (this.running) {
          Button('复制').fontSize(12).height(30)
            .backgroundColor($r('app.color.bg_dark'))
            .onClick(() => this.copyUrl())
        }
      }.width('100%')

      if (this.running) {
        Divider().color('#243027')
        Row() {
          this.Metric('观看', this.stats.viewers.toString())
          this.Metric('帧率', this.stats.actualFps + ' fps')
          this.Metric('已推帧', this.stats.framesSent.toString())
        }.width('100%').justifyContent(FlexAlign.SpaceBetween)
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(14)
  }

  @Builder
  Metric(label: string, value: string) {
    Column({ space: 2 }) {
      Text(value).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      Text(label).fontSize(11).fontColor($r('app.color.text_secondary'))
    }
  }

  // ---------- 启停按钮 ----------
  @Builder
  StartButton() {
    Button() {
      Row({ space: 8 }) {
        if (this.busy) {
          LoadingProgress().width(20).height(20).color('#06210F')
        }
        Text(this.running ? '停止服务' : '启动服务器')
          .fontSize(17).fontWeight(FontWeight.Bold)
          .fontColor(this.running ? '#fff' : '#06210F')
      }
    }
    .width('100%').height(52)
    .backgroundColor(this.running ? $r('app.color.brand_danger') : $r('app.color.brand_primary'))
    .borderRadius(14)
    .enabled(!this.busy)
    .onClick(() => this.toggleServer())
  }

  // ---------- 运行时控制 ----------
  @Builder
  RuntimeControls() {
    Column({ space: 12 }) {
      Row() {
        Text('手电补光').fontSize(15).fontColor($r('app.color.text_primary'))
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.torchOn })
          .selectedColor($r('app.color.brand_primary'))
          .onChange((v: boolean) => {
            this.torchOn = v;
            this.ctrl.setTorch(v);
          })
      }.width('100%')
      Text('运行中如需修改分辨率/画质，请先停止服务。')
        .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
    }
    .width('100%').padding(16)
    .backgroundColor($r('app.color.bg_card')).borderRadius(14)
  }

  // ---------- 参数设置 ----------
  @Builder
  Settings() {
    Column({ space: 16 }) {
      // 摄像头
      Row() {
        Text('摄像头').fontSize(15).fontColor($r('app.color.text_primary'))
        Blank()
        Row({ space: 0 }) {
          this.Segment('后置', !this.config.useFront, () => this.config.useFront = false)
          this.Segment('前置', this.config.useFront, () => this.config.useFront = true)
        }
      }.width('100%')

      // 分辨率
      Column({ space: 8 }) {
        Text('分辨率').fontSize(15).fontColor($r('app.color.text_primary')).width('100%')
        Row({ space: 8 }) {
          ForEach(RESOLUTIONS, (r: Resolution) => {
            this.Chip(r.label, this.config.resolution.label === r.label, () => {
              this.config.resolution = r;
            })
          }, (r: Resolution) => r.label)
        }.width('100%')
      }

      // 画质
      Column({ space: 4 }) {
        Row() {
          Text('JPEG 画质').fontSize(15).fontColor($r('app.color.text_primary'))
          Blank()
          Text(this.config.quality.toString()).fontSize(14).fontColor($r('app.color.brand_primary'))
        }.width('100%')
        Slider({ value: this.config.quality, min: 20, max: 95, step: 5 })
          .selectedColor($r('app.color.brand_primary'))
          .onChange((v: number) => this.config.quality = Math.round(v))
      }

      // 帧率
      Column({ space: 4 }) {
        Row() {
          Text('目标帧率').fontSize(15).fontColor($r('app.color.text_primary'))
          Blank()
          Text(this.config.fps + ' fps').fontSize(14).fontColor($r('app.color.brand_primary'))
        }.width('100%')
        Slider({ value: this.config.fps, min: 5, max: 30, step: 1 })
          .selectedColor($r('app.color.brand_primary'))
          .onChange((v: number) => this.config.fps = Math.round(v))
      }

      // 端口
      Row() {
        Text('端口').fontSize(15).fontColor($r('app.color.text_primary'))
        Blank()
        TextInput({ text: this.config.port.toString() })
          .type(InputType.Number).width(110).height(38).textAlign(TextAlign.Center)
          .backgroundColor($r('app.color.bg_dark')).fontColor($r('app.color.text_primary'))
          .borderRadius(10)
          .onChange((v: string) => {
            const n = Number(v);
            if (n >= 1024 && n <= 65535) {
              this.config.port = n;
            }
          })
      }.width('100%')
    }
    .width('100%').padding(16)
    .backgroundColor($r('app.color.bg_card')).borderRadius(14)
  }

  @Builder
  Segment(label: string, active: boolean, onTap: () => void) {
    Text(label)
      .fontSize(13)
      .fontColor(active ? '#06210F' : $r('app.color.text_secondary'))
      .padding({ left: 16, right: 16, top: 7, bottom: 7 })
      .backgroundColor(active ? $r('app.color.brand_primary') : $r('app.color.bg_dark'))
      .onClick(onTap)
  }

  @Builder
  Chip(label: string, active: boolean, onTap: () => void) {
    Text(label)
      .fontSize(13)
      .fontColor(active ? '#06210F' : $r('app.color.text_primary'))
      .layoutWeight(1).textAlign(TextAlign.Center)
      .padding({ top: 9, bottom: 9 })
      .backgroundColor(active ? $r('app.color.brand_primary') : $r('app.color.bg_dark'))
      .borderRadius(10)
      .onClick(onTap)
  }

  stateText(): string {
    switch (this.stats.state) {
      case ServerState.RUNNING: return '● 运行中';
      case ServerState.STARTING: return '启动中…';
      case ServerState.ERROR: return '错误';
      default: return '已停止';
    }
  }
}
