/**
 * Index.ets - 视频墙主页面
 *
 * 结构：顶栏（布局 1/4/9/16、发现、工具、添加）→ 视频墙分页网格
 * 弹层：
 *   发现：ONVIF WS-Discovery 结果 → 填账号取 RTSP 地址 → 一键入墙
 *   工具：RTSP 地址生成器（品牌模板）+ 连接测试/延迟诊断
 *   编辑：通道表单（名称/类型/地址/账号/间隔/启用/删除）
 * 视频墙分页：每页 wallCells 格，Swiper 横滑翻页；
 * RTSP 硬解并发上限内的格子实时播放，超出显示占位。
 */
import { promptAction, router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import {
  Channel, ChannelType, OnvifDevice, WALL_LAYOUTS, columnsOf,
  RTSP_TEMPLATES, RtspTemplate, TestResult
} from '../model/Models';
import { ChannelStore } from '../common/ChannelStore';
import { WallCell } from '../common/WallCell';
import { OnvifDiscovery } from '../network/OnvifDiscovery';
import { OnvifClient } from '../network/OnvifClient';
import { ConnTester } from '../network/ConnTester';

@Entry
@Component
struct Index {
  private store: ChannelStore = ChannelStore.getInstance();
  private discovery: OnvifDiscovery = new OnvifDiscovery();

  @State channels: Channel[] = [];
  @State wallCells: number = 4;
  @State videoCap: number = 2;
  @State gridVersion: number = 0;

  // 发现
  @State showDiscover: boolean = false;
  @State discovering: boolean = false;
  @State found: OnvifDevice[] = [];
  @State onvifUser: string = 'admin';
  @State onvifPass: string = '';
  @State fetchingXAddr: string = '';

  // 工具
  @State showTools: boolean = false;
  @State genBrandIndex: number = 0;
  @State genIp: string = '';
  @State genUser: string = 'admin';
  @State genPass: string = '';
  @State genSub: boolean = false;
  @State testUrl: string = '';
  @State testing: boolean = false;
  @State testResultText: string = '';

  // 编辑
  @State showEditor: boolean = false;
  @State editingId: string = '';
  @State formName: string = '';
  @State formUrl: string = '';
  @State formUser: string = '';
  @State formPass: string = '';
  @State formType: ChannelType = ChannelType.MJPEG;
  @State formEnabled: boolean = true;
  @State formInterval: number = 1000;
  @State formXAddr: string = '';

  async aboutToAppear(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    await this.store.init(context);
    this.wallCells = this.store.getWallCells();
    this.videoCap = this.store.getVideoCap();
    this.reload();
  }

  aboutToDisappear(): void {
    this.discovery.stop();
  }

  reload(): void {
    this.channels = this.store.getChannels();
    this.gridVersion++;
  }

  /** 视频墙分页数据：每页 wallCells 个 */
  pages(): Channel[][] {
    const out: Channel[][] = [];
    for (let i = 0; i < this.channels.length; i += this.wallCells) {
      out.push(this.channels.slice(i, i + this.wallCells));
    }
    return out.length === 0 ? [[]] : out;
  }

  /** 该通道是否分到硬解名额（页内 RTSP 序号 < 上限） */
  allowVideoFor(page: Channel[], ch: Channel): boolean {
    if (ch.type !== ChannelType.RTSP_HTTP) {
      return false;
    }
    let idx = 0;
    for (const c of page) {
      if (c.type === ChannelType.RTSP_HTTP && c.enabled) {
        if (c.id === ch.id) {
          return idx < this.videoCap;
        }
        idx++;
      }
    }
    return false;
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

  async addFromOnvif(dev: OnvifDevice): Promise<void> {
    this.fetchingXAddr = dev.xAddr;
    const uri = await OnvifClient.fetchStreamUri(dev.xAddr, this.onvifUser, this.onvifPass);
    this.fetchingXAddr = '';
    if (uri === '') {
      promptAction.showToast({ message: '获取流地址失败，请检查账号密码' });
      return;
    }
    const ch = new Channel();
    ch.id = util.generateRandomUUID();
    ch.name = dev.name;
    ch.type = ChannelType.RTSP_HTTP;
    // 将账号内嵌 RTSP URL（AVPlayer 播放惯例）
    ch.url = Index.embedAuth(uri, this.onvifUser, this.onvifPass);
    ch.username = this.onvifUser;
    ch.password = this.onvifPass;
    ch.onvifXAddr = dev.xAddr;
    await this.store.upsert(ch);
    this.reload();
    promptAction.showToast({ message: `已添加：${dev.name}` });
  }

  static embedAuth(rtspUrl: string, user: string, pass: string): string {
    if (user === '' || rtspUrl.includes('@')) {
      return rtspUrl;
    }
    return rtspUrl.replace(/^rtsp:\/\//,
      `rtsp://${encodeURIComponent(user)}:${encodeURIComponent(pass)}@`);
  }

  // ---------------- 工具 ----------------

  genUrl(): string {
    const t: RtspTemplate = RTSP_TEMPLATES[this.genBrandIndex];
    const template = this.genSub ? t.sub : t.main;
    return template
      .replace('{user}', this.genUser === '' ? 'admin' : this.genUser)
      .replace('{pass}', this.genPass === '' ? 'password' : this.genPass)
      .replace('{ip}', this.genIp === '' ? '192.168.1.64' : this.genIp);
  }

  async runTest(): Promise<void> {
    const url = this.testUrl.trim();
    if (url === '') {
      return;
    }
    this.testing = true;
    this.testResultText = '';
    const r: TestResult = await ConnTester.test(url, '');
    this.testing = false;
    this.testResultText = (r.ok ? '✅ ' : '❌ ') + r.detail;
  }

  // ---------------- 编辑 ----------------

  openEditor(ch: Channel | null): void {
    if (ch !== null) {
      this.editingId = ch.id;
      this.formName = ch.name;
      this.formUrl = ch.url;
      this.formUser = ch.username;
      this.formPass = ch.password;
      this.formType = ch.type;
      this.formEnabled = ch.enabled;
      this.formInterval = ch.pollIntervalMs;
      this.formXAddr = ch.onvifXAddr;
    } else {
      this.editingId = '';
      this.formName = '';
      this.formUrl = '';
      this.formUser = '';
      this.formPass = '';
      this.formType = ChannelType.MJPEG;
      this.formEnabled = true;
      this.formInterval = 1000;
      this.formXAddr = '';
    }
    this.showEditor = true;
  }

  async saveChannel(): Promise<void> {
    const url = this.formUrl.trim();
    const isRtsp = url.startsWith('rtsp://');
    if (!url.startsWith('http://') && !url.startsWith('https://') && !isRtsp) {
      promptAction.showToast({ message: '地址需以 http(s):// 或 rtsp:// 开头' });
      return;
    }
    if (isRtsp) {
      this.formType = ChannelType.RTSP_HTTP;
    }
    const ch = new Channel();
    ch.id = this.editingId !== '' ? this.editingId : util.generateRandomUUID();
    ch.name = this.formName.trim() !== '' ? this.formName.trim() : '通道';
    ch.url = url;
    ch.username = this.formUser.trim();
    ch.password = this.formPass;
    ch.type = this.formType;
    ch.enabled = this.formEnabled;
    ch.pollIntervalMs = this.formInterval;
    ch.onvifXAddr = this.formXAddr;
    await this.store.upsert(ch);
    this.showEditor = false;
    this.reload();
    promptAction.showToast({ message: '已保存' });
  }

  async deleteChannel(): Promise<void> {
    if (this.editingId === '') {
      return;
    }
    await this.store.remove(this.editingId);
    this.showEditor = false;
    this.reload();
  }

  openFullscreen(ch: Channel): void {
    router.pushUrl({ url: 'pages/CameraPage', params: { channel: ch } });
  }

  build() {
    Column() {
      // 顶栏
      Row({ space: 8 }) {
        Text('Stream').fontSize(22).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.brand_primary'))
        Text('Show').fontSize(22).fontWeight(FontWeight.Lighter)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Row({ space: 0 }) {
          ForEach(WALL_LAYOUTS, (n: number) => {
            Text(`${n}`)
              .fontSize(12)
              .fontColor(this.wallCells === n ? '#03211D' : $r('app.color.text_secondary'))
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .backgroundColor(this.wallCells === n ? $r('app.color.brand_primary') : $r('app.color.bg_card'))
              .onClick(() => {
                this.wallCells = n;
                this.store.setWallCells(n);
                this.gridVersion++;
              })
          }, (n: number) => n.toString())
        }
        .borderRadius(8).clip(true)

        Button('🔍').fontSize(15).width(34).height(34).type(ButtonType.Circle)
          .backgroundColor($r('app.color.bg_elevated'))
          .onClick(() => {
            this.showDiscover = true;
            this.startDiscover();
          })
        Button('🧰').fontSize(15).width(34).height(34).type(ButtonType.Circle)
          .backgroundColor($r('app.color.bg_elevated'))
          .onClick(() => {
            this.showTools = true;
          })
        Button('＋').fontSize(17).width(34).height(34).type(ButtonType.Circle)
          .backgroundColor($r('app.color.brand_primary')).fontColor('#03211D')
          .onClick(() => this.openEditor(null))
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 12, bottom: 8 })

      // 视频墙
      if (this.channels.length === 0) {
        Column({ space: 10 }) {
          Text('📺').fontSize(48)
          Text('监控墙是空的').fontSize(15).fontColor($r('app.color.text_primary'))
          Text('点 🔍 自动发现局域网 ONVIF 摄像头\n或点 ＋ 手动添加 RTSP / MJPEG / 快照地址')
            .fontSize(12).fontColor($r('app.color.text_secondary')).textAlign(TextAlign.Center)
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        Swiper() {
          ForEach(this.pages(), (page: Channel[], pageIdx: number) => {
            Scroll() {
              Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                ForEach(page, (ch: Channel) => {
                  Column() {
                    WallCell({
                      ch: ch,
                      allowVideo: this.allowVideoFor(page, ch),
                      onOpen: (c: Channel): void => this.openFullscreen(c)
                    })
                  }
                  .width(`${100 / columnsOf(this.wallCells)}%`)
                  .padding(3)
                  .gesture(LongPressGesture().onAction(() => this.openEditor(ch)))
                }, (ch: Channel) => ch.id + '_' + this.gridVersion + '_' + this.wallCells)
              }
              .width('100%')
              .padding({ left: 10, right: 10 })
            }
            .scrollBar(BarState.Off)
            .align(Alignment.Top)
          }, (page: Channel[], pageIdx: number) => 'p' + pageIdx + '_' + this.gridVersion)
        }
        .layoutWeight(1)
        .indicator(this.pages().length > 1)
        .loop(false)
      }

      Text(`共 ${this.channels.length} 路 · 硬解上限 ${this.videoCap} 路/屏 · 点击全屏 · 长按编辑`)
        .fontSize(10).fontColor($r('app.color.text_secondary'))
        .padding({ bottom: 6 })
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.bg_dark'))
    .bindSheet($$this.showDiscover, this.DiscoverSheet(), {
      height: 560, dragBar: true, backgroundColor: $r('app.color.bg_card')
    })
    .bindSheet($$this.showTools, this.ToolsSheet(), {
      height: 620, dragBar: true, backgroundColor: $r('app.color.bg_card')
    })
    .bindSheet($$this.showEditor, this.EditorSheet(), {
      height: 620, dragBar: true, backgroundColor: $r('app.color.bg_card')
    })
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
          Text(this.discovering ? '正在向 239.255.255.250:3702 广播探测…' : '未发现设备。请确认摄像头与手机在同一网段且开启 ONVIF。')
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
                  Button('取流入墙').fontSize(12).height(30)
                    .backgroundColor($r('app.color.brand_primary')).fontColor('#03211D')
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
      Text('说明：发现走 WS-Discovery 组播；"取流入墙"会用上方账号向设备请求 ONVIF GetStreamUri 拿 RTSP 地址。')
        .fontSize(10).fontColor($r('app.color.text_secondary'))
    }
    .width('100%').height('100%').padding(14)
  }

  // ---------- 工具弹层 ----------
  @Builder
  ToolsSheet() {
    Scroll() {
      Column({ space: 14 }) {
        Text('RTSP 地址生成器').fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary')).width('100%').margin({ top: 8 })

        Row({ space: 6 }) {
          ForEach(RTSP_TEMPLATES, (t: RtspTemplate, i: number) => {
            Text(t.brand.split(' ')[0])
              .fontSize(11)
              .fontColor(this.genBrandIndex === i ? '#03211D' : $r('app.color.text_primary'))
              .padding({ left: 8, right: 8, top: 7, bottom: 7 })
              .backgroundColor(this.genBrandIndex === i ? $r('app.color.brand_primary') : $r('app.color.bg_dark'))
              .borderRadius(8)
              .onClick(() => {
                this.genBrandIndex = i;
              })
          }, (t: RtspTemplate) => t.brand)
        }.width('100%')

        Row({ space: 8 }) {
          TextInput({ placeholder: 'IP，如 192.168.1.64', text: $$this.genIp })
            .layoutWeight(1).height(38)
            .backgroundColor($r('app.color.bg_dark')).fontColor($r('app.color.text_primary'))
          Row({ space: 4 }) {
            Text('子码流').fontSize(11).fontColor($r('app.color.text_secondary'))
            Toggle({ type: ToggleType.Switch, isOn: this.genSub })
              .selectedColor($r('app.color.brand_primary'))
              .onChange((v: boolean) => this.genSub = v)
          }
        }.width('100%')
        Row({ space: 8 }) {
          TextInput({ placeholder: '用户名', text: $$this.genUser })
            .layoutWeight(1).height(38)
            .backgroundColor($r('app.color.bg_dark')).fontColor($r('app.color.text_primary'))
          TextInput({ placeholder: '密码', text: $$this.genPass })
            .type(InputType.Password).layoutWeight(1).height(38)
            .backgroundColor($r('app.color.bg_dark')).fontColor($r('app.color.text_primary'))
        }.width('100%')

        Column({ space: 8 }) {
          Text(this.genUrl())
            .fontSize(12).fontColor($r('app.color.brand_primary'))
            .width('100%')
            .padding(10).backgroundColor($r('app.color.bg_dark')).borderRadius(8)
          Row({ space: 8 }) {
            Button('测试此地址').fontSize(12).height(32).layoutWeight(1)
              .backgroundColor($r('app.color.bg_elevated'))
              .onClick(() => {
                this.testUrl = this.genUrl();
                this.runTest();
              })
            Button('用它建通道').fontSize(12).height(32).layoutWeight(1)
              .backgroundColor($r('app.color.brand_primary')).fontColor('#03211D')
              .onClick(() => {
                this.showTools = false;
                this.openEditor(null);
                this.formType = ChannelType.RTSP_HTTP;
                this.formUrl = this.genUrl();
                this.formName = RTSP_TEMPLATES[this.genBrandIndex].brand.split(' ')[0];
              })
          }.width('100%')
        }

        Divider().color('#2A3550')

        Text('连接测试 / 延迟诊断').fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary')).width('100%')
        TextInput({ placeholder: 'rtsp:// 或 http(s):// 地址', text: $$this.testUrl })
          .height(38)
          .backgroundColor($r('app.color.bg_dark')).fontColor($r('app.color.text_primary'))
        Button(this.testing ? '测试中…' : '开始测试').width('100%').height(40)
          .enabled(!this.testing)
          .backgroundColor($r('app.color.bg_elevated'))
          .onClick(() => this.runTest())
        if (this.testResultText !== '') {
          Text(this.testResultText)
            .fontSize(13).fontColor($r('app.color.text_primary'))
            .width('100%').padding(10)
            .backgroundColor($r('app.color.bg_dark')).borderRadius(8)
        }
        Text('RTSP 测 TCP 建连耗时（<50ms 同网段极佳，>200ms 偏慢）；HTTP 返回状态码与响应耗时，401 提示账号错误。')
          .fontSize(10).fontColor($r('app.color.text_secondary'))
      }
      .width('100%').padding(14)
    }
    .scrollBar(BarState.Off)
  }

  // ---------- 编辑弹层 ----------
  @Builder
  EditorSheet() {
    Scroll() {
      Column({ space: 12 }) {
        Text(this.editingId === '' ? '添加通道' : '编辑通道')
          .fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary')).margin({ top: 8 })

        TextInput({ placeholder: '名称，如：大门', text: $$this.formName })
          .height(40).backgroundColor($r('app.color.bg_dark')).fontColor($r('app.color.text_primary'))

        Row({ space: 8 }) {
          this.TypeChip('MJPEG', ChannelType.MJPEG)
          this.TypeChip('快照轮询', ChannelType.JPEG_POLL)
          this.TypeChip('RTSP/视频', ChannelType.RTSP_HTTP)
        }.width('100%')

        TextInput({
          placeholder: this.formType === ChannelType.RTSP_HTTP
            ? 'rtsp://user:pass@ip:554/…'
            : (this.formType === ChannelType.MJPEG ? 'http://ip:8080/video' : 'http://ip:8080/shot.jpg'),
          text: $$this.formUrl
        })
          .height(40).backgroundColor($r('app.color.bg_dark')).fontColor($r('app.color.text_primary'))

        Row({ space: 8 }) {
          TextInput({ placeholder: '用户名（HTTP 认证用）', text: $$this.formUser })
            .layoutWeight(1).height(40)
            .backgroundColor($r('app.color.bg_dark')).fontColor($r('app.color.text_primary'))
          TextInput({ placeholder: '密码', text: $$this.formPass })
            .type(InputType.Password).layoutWeight(1).height(40)
            .backgroundColor($r('app.color.bg_dark')).fontColor($r('app.color.text_primary'))
        }.width('100%')

        if (this.formType === ChannelType.JPEG_POLL) {
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

        // 硬解上限设置
        Column({ space: 2 }) {
          Row() {
            Text('每屏 RTSP 硬解上限').fontSize(13).fontColor($r('app.color.text_secondary'))
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

        Button('保存').width('100%').height(42)
          .backgroundColor($r('app.color.brand_primary')).fontColor('#03211D')
          .onClick(() => this.saveChannel())
        if (this.editingId !== '') {
          Button('删除此通道').width('100%').height(38)
            .backgroundColor('transparent').fontColor($r('app.color.brand_danger'))
            .onClick(() => this.deleteChannel())
        }
        Text('账号密码仅保存在本机。MJPEG/快照通道在墙上实时软解；RTSP 硬解受每屏上限保护，超出的格子点开全屏播放。')
          .fontSize(10).fontColor($r('app.color.text_secondary'))
      }
      .width('100%').padding(14)
    }
    .scrollBar(BarState.Off)
  }

  @Builder
  TypeChip(label: string, t: ChannelType) {
    Text(label)
      .fontSize(12)
      .fontColor(this.formType === t ? '#03211D' : $r('app.color.text_primary'))
      .layoutWeight(1).textAlign(TextAlign.Center)
      .padding({ top: 8, bottom: 8 })
      .backgroundColor(this.formType === t ? $r('app.color.brand_primary') : $r('app.color.bg_dark'))
      .borderRadius(8)
      .onClick(() => {
        this.formType = t;
      })
  }
}
