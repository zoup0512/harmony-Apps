/**
 * Index.ets - 主页面
 *
 * 结构：顶栏（发现/添加）→ Tabs：
 *   「列表」：相机卡片列表，缩略图按 5s 周期刷新快照（有快照地址的相机）；
 *            点击进全屏，长按编辑；PTZ 徽标标识可云台设备；
 *   「四分屏」：前 4 路启用相机 2×2 同屏（RTSP 硬解受并发上限保护）。
 * 弹层：
 *   发现：ONVIF WS-Discovery → 填账号 → 一键取流地址 + 快照地址 + PTZ 能力探测；
 *   编辑：名称/类型/地址/快照地址/账号/间隔/启用/删除 + 全局设置（硬解上限、轮巡间隔）。
 */
import { promptAction, router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import {
  Camera, CamKind, CamState, OnvifDevice, THUMB_INTERVAL_MS
} from '../model/Models';
import { CameraStore } from '../common/CameraStore';
import { QuadCell } from '../common/QuadCell';
import { JpegPollClient } from '../network/StreamClient';
import { OnvifDiscovery } from '../network/OnvifDiscovery';
import { OnvifSession } from '../network/OnvifSession';

/** 列表缩略图：有快照来源的相机每 5s 刷一帧 */
@Component
struct CamThumb {
  @Prop cam: Camera;
  @State frame: PixelMap | null = null;
  private poller: JpegPollClient | null = null;
  private lastFrame: image.PixelMap | null = null;

  private canThumb(): boolean {
    return this.cam.snapshotUrl !== '' || this.cam.kind === CamKind.JPEG_POLL;
  }

  aboutToAppear(): void {
    if (!this.cam.enabled || !this.canThumb()) {
      return;
    }
    this.poller = new JpegPollClient();
    this.poller.start(this.cam, (pm: image.PixelMap): void => {
      const old = this.lastFrame;
      this.lastFrame = pm;
      this.frame = pm;
      if (old) {
        old.release();
      }
    }, (): void => {
    }, THUMB_INTERVAL_MS);
  }

  aboutToDisappear(): void {
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
      if (this.frame !== null) {
        Image(this.frame)
          .width('100%').height('100%')
          .objectFit(ImageFit.Cover)
      } else {
        Text(this.cam.enabled ? '📹' : '⏸').fontSize(24)
      }
    }
    .width(104).height(58.5)
    .backgroundColor('#000')
    .borderRadius(8)
    .clip(true)
  }
}

@Entry
@Component
struct Index {
  private store: CameraStore = CameraStore.getInstance();
  private discovery: OnvifDiscovery = new OnvifDiscovery();

  @State cameras: Camera[] = [];
  @State listVersion: number = 0;
  @State activeTab: number = 0;
  @State videoCap: number = 2;
  @State sequenceSec: number = 10;

  // 发现
  @State showDiscover: boolean = false;
  @State discovering: boolean = false;
  @State found: OnvifDevice[] = [];
  @State onvifUser: string = 'admin';
  @State onvifPass: string = '';
  @State fetchingXAddr: string = '';

  // 编辑
  @State showEditor: boolean = false;
  @State editingId: string = '';
  @State formName: string = '';
  @State formUrl: string = '';
  @State formSnapshotUrl: string = '';
  @State formUser: string = '';
  @State formPass: string = '';
  @State formKind: CamKind = CamKind.RTSP_HTTP;
  @State formEnabled: boolean = true;
  @State formInterval: number = 1000;
  @State formXAddr: string = '';
  @State formPtz: boolean = false;

  async aboutToAppear(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    await this.store.init(context);
    this.videoCap = this.store.getVideoCap();
    this.sequenceSec = this.store.getSequenceSec();
    this.reload();
  }

  onPageShow(): void {
    // 从全屏返回后刷新缩略图组件（预置位/状态可能变化）
    this.reload();
  }

  aboutToDisappear(): void {
    this.discovery.stop();
  }

  reload(): void {
    this.cameras = this.store.getCameras();
    this.listVersion++;
  }

  /** 四分屏取前 4 路启用相机 */
  quadCams(): Camera[] {
    return this.store.getEnabledCameras().slice(0, 4);
  }

  /** 四分屏内该相机是否分到硬解名额 */
  allowVideoFor(cams: Camera[], cam: Camera): boolean {
    if (cam.kind !== CamKind.RTSP_HTTP) {
      return false;
    }
    let idx = 0;
    for (const c of cams) {
      if (c.kind === CamKind.RTSP_HTTP && c.enabled) {
        if (c.id === cam.id) {
          return idx < this.videoCap;
        }
        idx++;
      }
    }
    return false;
  }

  static hostOf(url: string): string {
    const m = url.match(/^[a-z]+:\/\/(?:[^@\/]+@)?([^\/:]+)/);
    return m !== null ? m[1] : '';
  }

  // ---------------- 发现 ----------------

  startDiscover(): void {
    this.found = [];
    this.discovering = true;
    this.discovery.search((dev: OnvifDevice) => {
      this.found = this.found.concat([dev]);
    }, 5000).then(() => {
      this.discovering = false;
    });
  }

  /** 一键添加：取流地址 + 快照地址 + PTZ 能力探测 */
  async addFromOnvif(dev: OnvifDevice): Promise<void> {
    this.fetchingXAddr = dev.xAddr;
    const session = new OnvifSession(dev.xAddr, this.onvifUser, this.onvifPass);
    const streamUri = await session.getStreamUri();
    this.fetchingXAddr = '';
    if (streamUri === '') {
      promptAction.showToast({ message: '获取流地址失败，请检查账号密码' });
      return;
    }
    const snapshotUri = await session.getSnapshotUri();
    const cam = new Camera();
    cam.id = util.generateRandomUUID();
    cam.name = dev.name;
    cam.kind = CamKind.RTSP_HTTP;
    cam.url = Index.embedAuth(streamUri, this.onvifUser, this.onvifPass);
    cam.snapshotUrl = snapshotUri;
    cam.username = this.onvifUser;
    cam.password = this.onvifPass;
    cam.onvifXAddr = dev.xAddr;
    cam.ptz = session.hasPtz();
    await this.store.upsert(cam);
    this.reload();
    promptAction.showToast({
      message: cam.ptz ? `已添加（支持 PTZ 云台）：${dev.name}` : `已添加：${dev.name}`
    });
  }

  static embedAuth(rtspUrl: string, user: string, pass: string): string {
    if (user === '' || rtspUrl.includes('@')) {
      return rtspUrl;
    }
    return rtspUrl.replace(/^rtsp:\/\//,
      `rtsp://${encodeURIComponent(user)}:${encodeURIComponent(pass)}@`);
  }

  // ---------------- 编辑 ----------------

  openEditor(cam: Camera | null): void {
    if (cam !== null) {
      this.editingId = cam.id;
      this.formName = cam.name;
      this.formUrl = cam.url;
      this.formSnapshotUrl = cam.snapshotUrl;
      this.formUser = cam.username;
      this.formPass = cam.password;
      this.formKind = cam.kind;
      this.formEnabled = cam.enabled;
      this.formInterval = cam.pollIntervalMs;
      this.formXAddr = cam.onvifXAddr;
      this.formPtz = cam.ptz;
    } else {
      this.editingId = '';
      this.formName = '';
      this.formUrl = '';
      this.formSnapshotUrl = '';
      this.formUser = '';
      this.formPass = '';
      this.formKind = CamKind.RTSP_HTTP;
      this.formEnabled = true;
      this.formInterval = 1000;
      this.formXAddr = '';
      this.formPtz = false;
    }
    this.showEditor = true;
  }

  async saveCamera(): Promise<void> {
    const url = this.formUrl.trim();
    const isRtsp = url.startsWith('rtsp://');
    if (!url.startsWith('http://') && !url.startsWith('https://') && !isRtsp) {
      promptAction.showToast({ message: '地址需以 http(s):// 或 rtsp:// 开头' });
      return;
    }
    if (isRtsp) {
      this.formKind = CamKind.RTSP_HTTP;
    }
    const cam = new Camera();
    cam.id = this.editingId !== '' ? this.editingId : util.generateRandomUUID();
    cam.name = this.formName.trim() !== '' ? this.formName.trim() : '相机';
    cam.url = url;
    cam.snapshotUrl = this.formSnapshotUrl.trim();
    cam.username = this.formUser.trim();
    cam.password = this.formPass;
    cam.kind = this.formKind;
    cam.enabled = this.formEnabled;
    cam.pollIntervalMs = this.formInterval;
    cam.onvifXAddr = this.formXAddr;
    cam.ptz = this.formPtz;
    await this.store.upsert(cam);
    this.showEditor = false;
    this.reload();
    promptAction.showToast({ message: '已保存' });
  }

  async deleteCamera(): Promise<void> {
    if (this.editingId === '') {
      return;
    }
    await this.store.remove(this.editingId);
    this.showEditor = false;
    this.reload();
  }

  openLive(cam: Camera): void {
    router.pushUrl({ url: 'pages/LivePage', params: { camera: cam } });
  }

  build() {
    Column() {
      // 顶栏
      Row({ space: 8 }) {
        Text('IP Camera').fontSize(21).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.brand_primary'))
        Text('Viewer').fontSize(21).fontWeight(FontWeight.Lighter)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Button('🔍').fontSize(15).width(34).height(34).type(ButtonType.Circle)
          .backgroundColor($r('app.color.bg_elevated'))
          .onClick(() => {
            this.showDiscover = true;
            this.startDiscover();
          })
        Button('＋').fontSize(17).width(34).height(34).type(ButtonType.Circle)
          .backgroundColor($r('app.color.brand_primary')).fontColor('#0B1B33')
          .onClick(() => this.openEditor(null))
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 12, bottom: 6 })

      Tabs({ index: this.activeTab }) {
        TabContent() {
          this.ListTab()
        }.tabBar('列表')

        TabContent() {
          this.QuadTab()
        }.tabBar('四分屏')
      }
      .layoutWeight(1)
      .barHeight(40)
      .onChange((idx: number) => {
        this.activeTab = idx;
        this.listVersion++;
      })
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.bg_dark'))
    .bindSheet($$this.showDiscover, this.DiscoverSheet(), {
      height: 560, dragBar: true, backgroundColor: $r('app.color.bg_card')
    })
    .bindSheet($$this.showEditor, this.EditorSheet(), {
      height: 660, dragBar: true, backgroundColor: $r('app.color.bg_card')
    })
  }

  // ---------- 列表 Tab ----------
  @Builder
  ListTab() {
    if (this.cameras.length === 0) {
      Column({ space: 10 }) {
        Text('📹').fontSize(48)
        Text('还没有相机').fontSize(15).fontColor($r('app.color.text_primary'))
        Text('点 🔍 自动发现局域网 ONVIF 摄像头\n或点 ＋ 手动添加 RTSP / MJPEG / 快照地址')
          .fontSize(12).fontColor($r('app.color.text_secondary')).textAlign(TextAlign.Center)
      }
      .width('100%').height('100%').justifyContent(FlexAlign.Center)
    } else {
      List({ space: 8 }) {
        ForEach(this.cameras, (cam: Camera) => {
          ListItem() {
            Row({ space: 10 }) {
              CamThumb({ cam: cam })
              Column({ space: 4 }) {
                Row({ space: 6 }) {
                  Text(cam.name).fontSize(15).fontColor($r('app.color.text_primary'))
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (cam.ptz) {
                    Text('PTZ').fontSize(9).fontColor('#0B1B33')
                      .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                      .backgroundColor($r('app.color.brand_primary')).borderRadius(4)
                  }
                  if (!cam.enabled) {
                    Text('已停用').fontSize(9).fontColor($r('app.color.text_secondary'))
                      .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                      .backgroundColor($r('app.color.bg_dark')).borderRadius(4)
                  }
                }
                Text(`${cam.kind} · ${Index.hostOf(cam.url)}`)
                  .fontSize(11).fontColor($r('app.color.text_secondary'))
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Text('›').fontSize(22).fontColor($r('app.color.text_secondary'))
            }
            .width('100%').padding(10)
            .borderRadius(12).backgroundColor($r('app.color.bg_card'))
          }
          .onClick(() => this.openLive(cam))
          .gesture(LongPressGesture().onAction(() => this.openEditor(cam)))
        }, (cam: Camera) => cam.id + '_' + this.listVersion)
      }
      .width('100%').height('100%')
      .padding({ left: 12, right: 12 })
      .scrollBar(BarState.Off)
    }
  }

  // ---------- 四分屏 Tab ----------
  @Builder
  QuadTab() {
    Column() {
      if (this.quadCams().length === 0) {
        Column({ space: 8 }) {
          Text('🖥️').fontSize(42)
          Text('没有启用中的相机').fontSize(13).fontColor($r('app.color.text_secondary'))
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            ForEach(this.quadCams(), (cam: Camera) => {
              Column() {
                QuadCell({
                  cam: cam,
                  allowVideo: this.allowVideoFor(this.quadCams(), cam),
                  onOpen: (c: Camera): void => this.openLive(c)
                })
              }
              .width('50%')
              .padding(3)
              .gesture(LongPressGesture().onAction(() => this.openEditor(cam)))
            }, (cam: Camera) => cam.id + '_q' + this.listVersion)
          }
          .width('100%')
          .padding({ left: 10, right: 10, top: 6 })
        }
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
        .layoutWeight(1)
      }
      Text(`前 4 路启用相机同屏 · RTSP 硬解上限 ${this.videoCap} 路 · 点击全屏 · 长按编辑`)
        .fontSize(10).fontColor($r('app.color.text_secondary'))
        .padding({ bottom: 6 })
    }
    .width('100%').height('100%')
  }

  // ---------- 发现弹层 ----------
  @Builder
  DiscoverSheet() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text('ONVIF 自动发现').fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        if (this.discovering) {
          LoadingProgress().width(16).height(16).color($r('app.color.brand_primary'))
        }
        Blank()
        Button('重新扫描').fontSize(12).height(28)
          .backgroundColor($r('app.color.bg_elevated'))
          .onClick(() => this.startDiscover())
      }.width('100%').margin({ top: 8 })

      Row({ space: 8 }) {
        TextInput({ placeholder: '用户名', text: $$this.onvifUser })
          .layoutWeight(1).height(38)
          .backgroundColor($r('app.color.bg_dark')).fontColor($r('app.color.text_primary'))
        TextInput({ placeholder: '密码', text: $$this.onvifPass })
          .type(InputType.Password).layoutWeight(1).height(38)
          .backgroundColor($r('app.color.bg_dark')).fontColor($r('app.color.text_primary'))
      }.width('100%')

      if (this.found.length === 0) {
        Column({ space: 8 }) {
          Text(this.discovering ? '正在向 239.255.255.250:3702 广播探测…'
            : '未发现设备。请确认摄像头与手机在同一网段且开启 ONVIF。')
            .fontSize(12).fontColor($r('app.color.text_secondary')).textAlign(TextAlign.Center)
        }.layoutWeight(1).justifyContent(FlexAlign.Center).width('100%')
      } else {
        List({ space: 8 }) {
          ForEach(this.found, (dev: OnvifDevice) => {
            ListItem() {
              Row({ space: 10 }) {
                Text('📷').fontSize(20)
                Column({ space: 2 }) {
                  Text(dev.name).fontSize(14).fontColor($r('app.color.text_primary'))
                  Text(`${dev.ip}  ${dev.hardware}`).fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                if (this.fetchingXAddr === dev.xAddr) {
                  LoadingProgress().width(18).height(18).color($r('app.color.brand_primary'))
                } else {
                  Button('添加').fontSize(12).height(30)
                    .backgroundColor($r('app.color.brand_primary')).fontColor('#0B1B33')
                    .onClick(() => this.addFromOnvif(dev))
                }
              }
              .width('100%').padding(12)
              .borderRadius(10).backgroundColor($r('app.color.bg_elevated'))
            }
          }, (dev: OnvifDevice) => dev.xAddr)
        }
        .layoutWeight(1).width('100%')
      }
      Text('说明：「添加」会用上方账号向设备请求 GetStreamUri（RTSP 播放）与 GetSnapshotUri（列表缩略图/截图），并探测 PTZ 云台能力。')
        .fontSize(10).fontColor($r('app.color.text_secondary'))
    }
    .width('100%').height('100%').padding(14)
  }

  // ---------- 编辑弹层 ----------
  @Builder
  EditorSheet() {
    Scroll() {
      Column({ space: 12 }) {
        Text(this.editingId === '' ? '添加相机' : '编辑相机')
          .fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary')).margin({ top: 8 })

        TextInput({ placeholder: '名称，如：大门', text: $$this.formName })
          .height(40).backgroundColor($r('app.color.bg_dark')).fontColor($r('app.color.text_primary'))

        Row({ space: 8 }) {
          this.KindChip('RTSP/视频', CamKind.RTSP_HTTP)
          this.KindChip('MJPEG', CamKind.MJPEG)
          this.KindChip('快照轮询', CamKind.JPEG_POLL)
        }.width('100%')

        TextInput({
          placeholder: this.formKind === CamKind.RTSP_HTTP
            ? 'rtsp://user:pass@ip:554/…'
            : (this.formKind === CamKind.MJPEG ? 'http://ip:8080/video' : 'http://ip:8080/shot.jpg'),
          text: $$this.formUrl
        })
          .height(40).backgroundColor($r('app.color.bg_dark')).fontColor($r('app.color.text_primary'))

        TextInput({ placeholder: '快照地址（可选，缩略图与 RTSP 截图用）', text: $$this.formSnapshotUrl })
          .height(40).backgroundColor($r('app.color.bg_dark')).fontColor($r('app.color.text_primary'))

        Row({ space: 8 }) {
          TextInput({ placeholder: '用户名（HTTP 认证用）', text: $$this.formUser })
            .layoutWeight(1).height(40)
            .backgroundColor($r('app.color.bg_dark')).fontColor($r('app.color.text_primary'))
          TextInput({ placeholder: '密码', text: $$this.formPass })
            .type(InputType.Password).layoutWeight(1).height(40)
            .backgroundColor($r('app.color.bg_dark')).fontColor($r('app.color.text_primary'))
        }.width('100%')

        if (this.formKind === CamKind.JPEG_POLL) {
          Column({ space: 2 }) {
            Row() {
              Text('刷新间隔').fontSize(13).fontColor($r('app.color.text_secondary'))
              Blank()
              Text(`${this.formInterval} ms`).fontSize(13).fontColor($r('app.color.brand_primary'))
            }.width('100%')
            Slider({ value: this.formInterval, min: 300, max: 5000, step: 100 })
              .selectedColor($r('app.color.brand_primary'))
              .onChange((v: number) => this.formInterval = Math.round(v))
          }
        }

        Row() {
          Text('启用').fontSize(14).fontColor($r('app.color.text_primary'))
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.formEnabled })
            .selectedColor($r('app.color.brand_primary'))
            .onChange((v: boolean) => this.formEnabled = v)
        }.width('100%')

        if (this.formXAddr !== '') {
          Row() {
            Text('PTZ 云台（ONVIF 探测结果）').fontSize(13).fontColor($r('app.color.text_secondary'))
            Blank()
            Toggle({ type: ToggleType.Switch, isOn: this.formPtz })
              .selectedColor($r('app.color.brand_primary'))
              .onChange((v: boolean) => this.formPtz = v)
          }.width('100%')
        }

        Divider().color('#2A3550')

        // 全局设置
        Column({ space: 2 }) {
          Row() {
            Text('四分屏 RTSP 硬解上限').fontSize(13).fontColor($r('app.color.text_secondary'))
            Blank()
            Text(`${this.videoCap} 路`).fontSize(13).fontColor($r('app.color.brand_primary'))
          }.width('100%')
          Slider({ value: this.videoCap, min: 1, max: 4, step: 1 })
            .selectedColor($r('app.color.brand_primary'))
            .onChange((v: number) => {
              this.videoCap = Math.round(v);
              this.store.setVideoCap(this.videoCap);
            })
        }
        Column({ space: 2 }) {
          Row() {
            Text('轮巡切换间隔').fontSize(13).fontColor($r('app.color.text_secondary'))
            Blank()
            Text(`${this.sequenceSec} 秒`).fontSize(13).fontColor($r('app.color.brand_primary'))
          }.width('100%')
          Slider({ value: this.sequenceSec, min: 3, max: 60, step: 1 })
            .selectedColor($r('app.color.brand_primary'))
            .onChange((v: number) => {
              this.sequenceSec = Math.round(v);
              this.store.setSequenceSec(this.sequenceSec);
            })
        }

        Button('保存').width('100%').height(42)
          .backgroundColor($r('app.color.brand_primary')).fontColor('#0B1B33')
          .onClick(() => this.saveCamera())
        if (this.editingId !== '') {
          Button('删除此相机').width('100%').height(38)
            .backgroundColor('transparent').fontColor($r('app.color.brand_danger'))
            .onClick(() => this.deleteCamera())
        }
        Text('账号密码仅保存在本机。缩略图每 5 秒刷新一次快照；无快照地址的 RTSP/MJPEG 相机显示占位图标。')
          .fontSize(10).fontColor($r('app.color.text_secondary'))
      }
      .width('100%').padding(14)
    }
    .scrollBar(BarState.Off)
  }

  @Builder
  KindChip(label: string, k: CamKind) {
    Text(label)
      .fontSize(12)
      .fontColor(this.formKind === k ? '#0B1B33' : $r('app.color.text_primary'))
      .layoutWeight(1).textAlign(TextAlign.Center)
      .padding({ top: 8, bottom: 8 })
      .backgroundColor(this.formKind === k ? $r('app.color.brand_primary') : $r('app.color.bg_dark'))
      .borderRadius(8)
      .onClick(() => {
        this.formKind = k;
      })
  }
}
