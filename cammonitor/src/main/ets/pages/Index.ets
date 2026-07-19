/**
 * Index.ets - 监控看板主页面
 *
 * 结构：顶栏（列数切换/添加）→ 摄像头网格（CamCell，每格独立取流）
 * 弹层：添加/编辑摄像头表单（名称/类型/地址/账号/启用/轮询间隔）
 * 长按卡片进入编辑；点击卡片进入全屏单摄像头页。
 */
import { promptAction, router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { CameraDevice, CameraType, GRID_COLUMNS } from '../model/Models';
import { CameraStore } from '../common/CameraStore';
import { CamCell } from '../common/CamCell';

@Entry
@Component
struct Index {
  private store: CameraStore = CameraStore.getInstance();

  @State cameras: CameraDevice[] = [];
  @State columns: number = 2;
  /** 递增以强制网格重建（编辑保存后重连取流） */
  @State gridVersion: number = 0;

  // 表单
  @State showEditor: boolean = false;
  @State editingId: string = '';
  @State formName: string = '';
  @State formUrl: string = '';
  @State formUser: string = '';
  @State formPass: string = '';
  @State formType: CameraType = CameraType.MJPEG;
  @State formEnabled: boolean = true;
  @State formInterval: number = 1000;

  async aboutToAppear(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    await this.store.init(context);
    this.columns = this.store.getGridColumns();
    this.reload();
  }

  reload(): void {
    this.cameras = this.store.getCameras();
    this.gridVersion++;
  }

  openEditor(cam: CameraDevice | null): void {
    if (cam !== null) {
      this.editingId = cam.id;
      this.formName = cam.name;
      this.formUrl = cam.url;
      this.formUser = cam.username;
      this.formPass = cam.password;
      this.formType = cam.type;
      this.formEnabled = cam.enabled;
      this.formInterval = cam.pollIntervalMs;
    } else {
      this.editingId = '';
      this.formName = '';
      this.formUrl = '';
      this.formUser = '';
      this.formPass = '';
      this.formType = CameraType.MJPEG;
      this.formEnabled = true;
      this.formInterval = 1000;
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
    if (isRtsp && this.formType !== CameraType.RTSP_HTTP) {
      this.formType = CameraType.RTSP_HTTP; // rtsp 地址强制视频流类型
    }
    const cam = new CameraDevice();
    cam.id = this.editingId !== '' ? this.editingId : util.generateRandomUUID();
    cam.name = this.formName.trim() !== '' ? this.formName.trim() : '摄像头';
    cam.url = url;
    cam.username = this.formUser.trim();
    cam.password = this.formPass;
    cam.type = this.formType;
    cam.enabled = this.formEnabled;
    cam.pollIntervalMs = this.formInterval;
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
    promptAction.showToast({ message: '已删除' });
  }

  openFullscreen(cam: CameraDevice): void {
    router.pushUrl({ url: 'pages/CameraPage', params: { camera: cam } });
  }

  build() {
    Column() {
      // 顶栏
      Row({ space: 10 }) {
        Text('Cam').fontSize(24).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.brand_primary'))
        Text('Monitor').fontSize(24).fontWeight(FontWeight.Lighter)
          .fontColor($r('app.color.text_primary'))
        Blank()
        // 列数切换
        Row({ space: 0 }) {
          ForEach(GRID_COLUMNS, (c: number) => {
            Text(`${c}`)
              .fontSize(13)
              .fontColor(this.columns === c ? '#04121F' : $r('app.color.text_secondary'))
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .backgroundColor(this.columns === c ? $r('app.color.brand_primary') : $r('app.color.bg_card'))
              .onClick(() => {
                this.columns = c;
                this.store.setGridColumns(c);
              })
          }, (c: number) => c.toString())
        }
        .borderRadius(9).clip(true)

        Button('＋').fontSize(18).width(36).height(36)
          .type(ButtonType.Circle)
          .backgroundColor($r('app.color.brand_primary')).fontColor('#04121F')
          .onClick(() => this.openEditor(null))
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 10 })

      // 网格
      if (this.cameras.length === 0) {
        Column({ space: 10 }) {
          Text('📹').fontSize(48)
          Text('还没有摄像头').fontSize(15).fontColor($r('app.color.text_primary'))
          Text('点右上角 ＋ 添加你的第一台 IP 摄像头\n支持 MJPEG 流 / 快照轮询 / RTSP·HTTP 视频流')
            .fontSize(12).fontColor($r('app.color.text_secondary')).textAlign(TextAlign.Center)
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          // key 含 gridVersion：保存/删除后强制重建单元以重连
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            ForEach(this.cameras, (cam: CameraDevice) => {
              Column() {
                CamCell({
                  cam: cam,
                  onOpen: (c: CameraDevice): void => this.openFullscreen(c)
                })
              }
              .width(`${100 / this.columns}%`)
              .padding(4)
              .gesture(LongPressGesture().onAction(() => this.openEditor(cam)))
            }, (cam: CameraDevice) => cam.id + '_' + this.gridVersion + '_' + this.columns)
          }
          .width('100%')
          .padding({ left: 12, right: 12, bottom: 20 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
      }

      // 底部提示
      Text('点击卡片全屏 · 长按编辑')
        .fontSize(11).fontColor($r('app.color.text_secondary'))
        .padding({ bottom: 8 })
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.bg_dark'))
    .bindSheet($$this.showEditor, this.EditorSheet(), {
      height: 620, dragBar: true, backgroundColor: $r('app.color.bg_card')
    })
  }

  // ---------- 添加/编辑弹层 ----------
  @Builder
  EditorSheet() {
    Scroll() {
      Column({ space: 12 }) {
        Text(this.editingId === '' ? '添加摄像头' : '编辑摄像头')
          .fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary')).margin({ top: 8 })

        TextInput({ placeholder: '名称，如：门口', text: $$this.formName })
          .height(42).backgroundColor($r('app.color.bg_dark')).fontColor($r('app.color.text_primary'))

        // 类型选择
        Column({ space: 6 }) {
          Text('流类型').fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
          Row({ space: 8 }) {
            this.TypeChip('MJPEG 流', CameraType.MJPEG)
            this.TypeChip('快照轮询', CameraType.JPEG_POLL)
            this.TypeChip('RTSP/视频', CameraType.RTSP_HTTP)
          }.width('100%')
        }

        TextInput({
          placeholder: this.formType === CameraType.RTSP_HTTP
            ? 'rtsp://ip:554/stream 或 http 视频地址'
            : (this.formType === CameraType.MJPEG ? 'http://ip:8080/video' : 'http://ip:8080/shot.jpg'),
          text: $$this.formUrl
        })
          .height(42).backgroundColor($r('app.color.bg_dark')).fontColor($r('app.color.text_primary'))

        TextInput({ placeholder: '用户名（可选）', text: $$this.formUser })
          .height(42).backgroundColor($r('app.color.bg_dark')).fontColor($r('app.color.text_primary'))
        TextInput({ placeholder: '密码（可选）', text: $$this.formPass })
          .type(InputType.Password)
          .height(42).backgroundColor($r('app.color.bg_dark')).fontColor($r('app.color.text_primary'))

        if (this.formType === CameraType.JPEG_POLL) {
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

        Button('保存').width('100%').height(44)
          .backgroundColor($r('app.color.brand_primary')).fontColor('#04121F')
          .onClick(() => this.saveCamera())

        if (this.editingId !== '') {
          Button('删除此摄像头').width('100%').height(40)
            .backgroundColor('transparent').fontColor($r('app.color.brand_danger'))
            .onClick(() => this.deleteCamera())
        }

        Text('提示：RTSP/视频类型在网格中显示占位卡，点开全屏用系统播放器解码，'
          + '避免多路视频并发解码的性能压力。账号密码仅保存在本机。')
          .fontSize(11).fontColor($r('app.color.text_secondary'))
      }
      .width('100%').padding(16)
    }
    .scrollBar(BarState.Off)
  }

  @Builder
  TypeChip(label: string, t: CameraType) {
    Text(label)
      .fontSize(12)
      .fontColor(this.formType === t ? '#04121F' : $r('app.color.text_primary'))
      .layoutWeight(1).textAlign(TextAlign.Center)
      .padding({ top: 9, bottom: 9 })
      .backgroundColor(this.formType === t ? $r('app.color.brand_primary') : $r('app.color.bg_dark'))
      .borderRadius(9)
      .onClick(() => {
        this.formType = t;
      })
  }
}
