/**
 * LivePage.ets - 全屏直播页（本作重头戏：PTZ 云台）
 *
 * 画面：RTSP_HTTP → XComponent + AVPlayer 硬解；MJPEG/快照 → Image(PixelMap)。
 * 数字变焦：双指捏合 1x–5x（拖影由 objectFit 承担），双击复位。
 * PTZ 云台（ONVIF 设备且探测到 PTZ 能力时显示）：
 *   八向方向盘按住 ContinuousMove、抬手 Stop；变焦 ＋/－ 同模式；⌂ 回 Home 位；
 *   预置位弹层：列出/转到/把当前位置存为新预置位。
 * 轮巡：按设置间隔在启用相机间自动切换（顺序循环）。
 * 截图：MJPEG/快照通道取最近一帧；RTSP 通道经快照地址抓取原始 JPEG——
 *       补上前作"RTSP 截图待 2.0"的缺口。
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
import { Camera, CamKind, CamState, LivePageParams, PtzPreset, PtzVector } from '../model/Models';
import { MjpegClient, JpegPollClient, fetchSnapshot } from '../network/StreamClient';
import { OnvifSession } from '../network/OnvifSession';
import { CameraStore } from '../common/CameraStore';

const TAG = 'LivePage';
/** PTZ 连续移动速度（|v| ≤ 1） */
const PTZ_SPEED = 0.5;
const ZOOM_SPEED = 0.5;

@Entry
@Component
struct LivePage {
  private store: CameraStore = CameraStore.getInstance();
  private mjpeg: MjpegClient | null = null;
  private poller: JpegPollClient | null = null;
  private player: media.AVPlayer | null = null;
  private xc: XComponentController = new XComponentController();
  private lastFrame: image.PixelMap | null = null;
  private session: OnvifSession | null = null;
  private surfaceId: string = '';
  private seqTimer: number = -1;
  private baseScale: number = 1;

  @State cam: Camera = new Camera();
  @State frame: PixelMap | null = null;
  @State state: CamState = CamState.CONNECTING;
  @State errMsg: string = '';
  @State hudVisible: boolean = true;
  @State zoomScale: number = 1;
  @State sequenceOn: boolean = false;
  @State showPresets: boolean = false;
  @State presets: PtzPreset[] = [];
  @State presetsLoading: boolean = false;
  @State newPresetName: string = '';
  @State ptzBusy: boolean = false;

  aboutToAppear(): void {
    const params = router.getParams() as LivePageParams;
    if (params && params.camera) {
      this.cam = params.camera;
    }
    this.setOrientation(window.Orientation.AUTO_ROTATION_LANDSCAPE);
    this.rebuildSession();
    if (this.cam.kind !== CamKind.RTSP_HTTP) {
      this.startImageStream();
    }
  }

  async aboutToDisappear(): Promise<void> {
    this.stopSequence();
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

  private rebuildSession(): void {
    this.session = this.cam.onvifXAddr !== ''
      ? new OnvifSession(this.cam.onvifXAddr, this.cam.username, this.cam.password)
      : null;
  }

  // ---------- 取流 ----------

  startImageStream(): void {
    this.state = CamState.CONNECTING;
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

  async startPlayer(surfaceId: string): Promise<void> {
    this.surfaceId = surfaceId;
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
        this.errMsg = `播放失败 (${err.code})`;
      });
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
      } catch (e) { /* ignore */
      }
      this.player = null;
    }
  }

  reconnect(): void {
    if (this.cam.kind === CamKind.RTSP_HTTP) {
      this.releasePlayer().then(() => {
        if (this.surfaceId !== '') {
          this.startPlayer(this.surfaceId);
        }
      });
    } else {
      this.stopImageStream();
      this.startImageStream();
    }
  }

  // ---------- 轮巡 ----------

  toggleSequence(): void {
    if (this.sequenceOn) {
      this.stopSequence();
      promptAction.showToast({ message: '轮巡已停止' });
      return;
    }
    const cams = this.store.getEnabledCameras();
    if (cams.length < 2) {
      promptAction.showToast({ message: '至少需要 2 路启用相机才能轮巡' });
      return;
    }
    this.sequenceOn = true;
    const sec = this.store.getSequenceSec();
    this.seqTimer = setInterval(() => {
      this.switchToNext();
    }, sec * 1000);
    promptAction.showToast({ message: `轮巡已开启（${sec} 秒/路）` });
  }

  stopSequence(): void {
    this.sequenceOn = false;
    if (this.seqTimer >= 0) {
      clearInterval(this.seqTimer);
      this.seqTimer = -1;
    }
  }

  private switchToNext(): void {
    const cams = this.store.getEnabledCameras();
    if (cams.length === 0) {
      return;
    }
    let idx = cams.findIndex((c: Camera) => c.id === this.cam.id);
    idx = (idx + 1) % cams.length;
    this.switchTo(cams[idx]);
  }

  /** 切换到另一路：完整停流后按新类型重启（RTSP→RTSP 复用同一 surface） */
  private switchTo(next: Camera): void {
    const prevKind = this.cam.kind;
    this.stopImageStream();
    this.releasePlayer().then(() => {
      this.cam = next;
      this.zoomScale = 1;
      this.errMsg = '';
      this.rebuildSession();
      this.presets = [];
      if (next.kind === CamKind.RTSP_HTTP) {
        if (prevKind === CamKind.RTSP_HTTP && this.surfaceId !== '') {
          // 同为 RTSP：XComponent 不重建，直接用已有 surface 起播
          this.startPlayer(this.surfaceId);
        }
        // 否则 XComponent 重建，onLoad 里起播
      } else {
        this.startImageStream();
      }
    });
  }

  // ---------- PTZ ----------

  private ptzMove(x: number, y: number, z: number): void {
    if (this.session === null) {
      return;
    }
    this.session.continuousMove(new PtzVector(x, y, z));
  }

  private ptzStop(): void {
    if (this.session === null) {
      return;
    }
    this.session.stopMove();
  }

  private async ptzHome(): Promise<void> {
    if (this.session === null) {
      return;
    }
    await this.session.gotoHome();
    promptAction.showToast({ message: '回 Home 位' });
  }

  async loadPresets(): Promise<void> {
    if (this.session === null) {
      return;
    }
    this.presetsLoading = true;
    this.presets = await this.session.getPresets();
    this.presetsLoading = false;
  }

  async gotoPreset(p: PtzPreset): Promise<void> {
    if (this.session === null) {
      return;
    }
    await this.session.gotoPreset(p.token);
    promptAction.showToast({ message: `转到：${p.name}` });
  }

  async savePreset(): Promise<void> {
    if (this.session === null) {
      return;
    }
    const name = this.newPresetName.trim() !== '' ? this.newPresetName.trim()
      : `预置位 ${this.presets.length + 1}`;
    this.ptzBusy = true;
    const token = await this.session.setPreset(name);
    this.ptzBusy = false;
    if (token === '') {
      promptAction.showToast({ message: '保存预置位失败' });
      return;
    }
    this.newPresetName = '';
    promptAction.showToast({ message: `已保存：${name}` });
    this.loadPresets();
  }

  // ---------- 截图 ----------

  async saveSnapshot(): Promise<void> {
    let jpegBytes: Uint8Array | null = null;
    if (this.cam.kind !== CamKind.RTSP_HTTP) {
      const pm = this.lastFrame;
      if (pm === null) {
        promptAction.showToast({ message: '暂无画面' });
        return;
      }
      try {
        const packer = image.createImagePacker();
        const buf = await packer.packing(pm, { format: 'image/jpeg', quality: 90 });
        packer.release();
        jpegBytes = new Uint8Array(buf);
      } catch (e) {
        promptAction.showToast({ message: '编码失败' });
        return;
      }
    } else {
      // RTSP 通道：经 ONVIF 快照地址抓取原始 JPEG
      if (this.cam.snapshotUrl === '') {
        promptAction.showToast({ message: '该相机没有快照地址（可在编辑中补填）' });
        return;
      }
      const rawOut: Uint8Array[] = [];
      const pm = await fetchSnapshot(this.cam.snapshotUrl, this.cam.username, this.cam.password, rawOut);
      if (pm !== null) {
        pm.release();
      }
      if (rawOut.length === 0) {
        promptAction.showToast({ message: '抓取快照失败' });
        return;
      }
      jpegBytes = rawOut[0];
    }
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      const uri = await helper.createAsset(photoAccessHelper.PhotoType.IMAGE, 'jpg');
      const file = await fileIo.open(uri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      await fileIo.write(file.fd,
        jpegBytes.buffer.slice(jpegBytes.byteOffset, jpegBytes.byteOffset + jpegBytes.byteLength));
      await fileIo.close(file.fd);
      promptAction.showToast({ message: '截图已保存到相册' });
    } catch (e) {
      hilog.error(0x0001, TAG, 'snapshot error: %{public}s', JSON.stringify(e));
      promptAction.showToast({ message: '保存失败（可能未授权相册）' });
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 画面（数字变焦作用于此容器）
      Stack({ alignContent: Alignment.Center }) {
        if (this.cam.kind === CamKind.RTSP_HTTP) {
          XComponent({ id: 'liveplayer', type: XComponentType.SURFACE, controller: this.xc })
            .onLoad(() => {
              this.startPlayer(this.xc.getXComponentSurfaceId());
            })
            .width('100%').height('100%')
        } else if (this.frame !== null) {
          Image(this.frame)
            .width('100%').height('100%')
            .objectFit(ImageFit.Contain)
        }
      }
      .width('100%').height('100%')
      .scale({ x: this.zoomScale, y: this.zoomScale })
      .clip(true)

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
              .backgroundColor($r('app.color.brand_primary')).fontColor('#0B1B33')
              .onClick(() => this.reconnect())
            Button('返回').fontSize(13).height(34)
              .backgroundColor($r('app.color.bg_elevated'))
              .onClick(() => router.back())
          }
        }
      }

      // 手势层：点击切 HUD；捏合数字变焦；双击复位
      Column()
        .width('100%').height('100%')
        .onClick(() => {
          this.hudVisible = !this.hudVisible;
        })
        .gesture(GestureGroup(GestureMode.Exclusive,
          TapGesture({ count: 2 }).onAction(() => {
            this.zoomScale = 1;
          }),
          PinchGesture({ fingers: 2 })
            .onActionStart(() => {
              this.baseScale = this.zoomScale;
            })
            .onActionUpdate((event: GestureEvent) => {
              const s = this.baseScale * event.scale;
              this.zoomScale = Math.min(5, Math.max(1, s));
            })
        ))
        .hitTestBehavior(this.state === CamState.ERROR ? HitTestMode.Transparent : HitTestMode.Default)

      // PTZ 方向盘（右侧，仅 PTZ 相机且 HUD 可见）
      if (this.hudVisible && this.cam.ptz && this.session !== null) {
        Column({ space: 6 }) {
          Row({ space: 6 }) {
            this.PtzKey('↖', -PTZ_SPEED, PTZ_SPEED, 0)
            this.PtzKey('↑', 0, PTZ_SPEED, 0)
            this.PtzKey('↗', PTZ_SPEED, PTZ_SPEED, 0)
          }
          Row({ space: 6 }) {
            this.PtzKey('←', -PTZ_SPEED, 0, 0)
            this.PtzHomeKey()
            this.PtzKey('→', PTZ_SPEED, 0, 0)
          }
          Row({ space: 6 }) {
            this.PtzKey('↙', -PTZ_SPEED, -PTZ_SPEED, 0)
            this.PtzKey('↓', 0, -PTZ_SPEED, 0)
            this.PtzKey('↘', PTZ_SPEED, -PTZ_SPEED, 0)
          }
          Row({ space: 6 }) {
            this.PtzKey('＋', 0, 0, ZOOM_SPEED)
            this.PtzKey('－', 0, 0, -ZOOM_SPEED)
          }
        }
        .padding(8)
        .backgroundColor('#00000066')
        .borderRadius(14)
        .position({ x: '100%', y: '50%' })
        .markAnchor({ x: 156, y: 92 })
      }

      // HUD
      if (this.hudVisible) {
        Column() {
          Row({ space: 12 }) {
            Text('‹').fontSize(30).fontColor('#fff')
              .padding({ left: 4, right: 8 })
              .onClick(() => router.back())
            Circle({ width: 8, height: 8 })
              .fill(this.state === CamState.LIVE ? $r('app.color.brand_ok') : '#888')
            Text(this.cam.name).fontSize(15).fontColor('#fff')
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            if (this.zoomScale > 1.01) {
              Text(`${this.zoomScale.toFixed(1)}x`).fontSize(11).fontColor('#fff')
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .backgroundColor('#3B82F644').borderRadius(6)
            }
            if (this.cam.ptz) {
              Text('PTZ').fontSize(11).fontColor('#0B1B33')
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .backgroundColor($r('app.color.brand_primary')).borderRadius(6)
            }
            Text(this.cam.kind).fontSize(11).fontColor('#FFFFFF99')
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor('#FFFFFF22').borderRadius(6)
          }
          .width('100%')
          .padding({ left: 12, right: 16, top: 10 })
          .linearGradient({ angle: 180, colors: [['#000000CC', 0], ['#00000000', 1]] })
          .height(64)

          Blank()

          Row({ space: 14 }) {
            Button('📷 截图').fontSize(13).height(38)
              .backgroundColor('#FFFFFF22').fontColor('#fff')
              .onClick(() => this.saveSnapshot())
            if (this.cam.ptz && this.session !== null) {
              Button('📌 预置位').fontSize(13).height(38)
                .backgroundColor('#FFFFFF22').fontColor('#fff')
                .onClick(() => {
                  this.showPresets = true;
                  this.loadPresets();
                })
            }
            Button(this.sequenceOn ? '⏹ 停止轮巡' : '🔁 轮巡')
              .fontSize(13).height(38)
              .backgroundColor(this.sequenceOn ? $r('app.color.brand_warn') : '#FFFFFF22')
              .fontColor(this.sequenceOn ? '#33230B' : '#fff')
              .onClick(() => this.toggleSequence())
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
    .bindSheet($$this.showPresets, this.PresetsSheet(), {
      height: 420, dragBar: true, backgroundColor: $r('app.color.bg_card')
    })
  }

  /** PTZ 按键：按住移动、抬手停止 */
  @Builder
  PtzKey(label: string, x: number, y: number, z: number) {
    Text(label)
      .fontSize(17).fontColor('#fff')
      .width(44).height(44).textAlign(TextAlign.Center)
      .backgroundColor('#FFFFFF22')
      .borderRadius(10)
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.ptzMove(x, y, z);
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.ptzStop();
        }
      })
  }

  @Builder
  PtzHomeKey() {
    Text('⌂')
      .fontSize(17).fontColor('#0B1B33')
      .width(44).height(44).textAlign(TextAlign.Center)
      .backgroundColor($r('app.color.brand_primary'))
      .borderRadius(10)
      .onClick(() => {
        this.ptzHome();
      })
  }

  // ---------- 预置位弹层 ----------
  @Builder
  PresetsSheet() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text('PTZ 预置位').fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        if (this.presetsLoading) {
          LoadingProgress().width(16).height(16).color($r('app.color.brand_primary'))
        }
        Blank()
        Button('刷新').fontSize(12).height(28)
          .backgroundColor($r('app.color.bg_elevated'))
          .onClick(() => this.loadPresets())
      }.width('100%').margin({ top: 8 })

      if (this.presets.length === 0 && !this.presetsLoading) {
        Text('设备上还没有预置位。移动云台到目标画面后，在下方保存当前位置。')
          .fontSize(12).fontColor($r('app.color.text_secondary'))
          .width('100%')
      } else {
        List({ space: 6 }) {
          ForEach(this.presets, (p: PtzPreset) => {
            ListItem() {
              Row({ space: 10 }) {
                Text('📌').fontSize(16)
                Text(p.name).fontSize(14).fontColor($r('app.color.text_primary'))
                  .layoutWeight(1)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                Button('转到').fontSize(12).height(28)
                  .backgroundColor($r('app.color.brand_primary')).fontColor('#0B1B33')
                  .onClick(() => this.gotoPreset(p))
              }
              .width('100%').padding(10)
              .borderRadius(10).backgroundColor($r('app.color.bg_elevated'))
            }
          }, (p: PtzPreset) => p.token)
        }
        .layoutWeight(1).width('100%')
      }

      Row({ space: 8 }) {
        TextInput({ placeholder: '新预置位名称（可留空自动编号）', text: $$this.newPresetName })
          .layoutWeight(1).height(38)
          .backgroundColor($r('app.color.bg_dark')).fontColor($r('app.color.text_primary'))
        Button(this.ptzBusy ? '…' : '保存当前位置').fontSize(12).height(38)
          .enabled(!this.ptzBusy)
          .backgroundColor($r('app.color.brand_primary')).fontColor('#0B1B33')
          .onClick(() => this.savePreset())
      }.width('100%')
    }
    .width('100%').height('100%').padding(14)
  }
}
