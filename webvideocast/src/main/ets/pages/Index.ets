/**
 * Index.ets - 主页面
 *
 * 结构：地址栏 → Web 浏览区（含资源嗅探）→ 投屏控制条（有会话时显示）
 * 弹层：嗅探到的媒体列表（半模态）、设备选择（半模态）
 */
import { webview } from '@kit.ArkWeb';
import { promptAction } from '@kit.ArkUI';
import { MediaItem, CastDevice, CastSession, PlayState, MediaKind } from '../model/Models';
import { VideoSniffer } from '../common/VideoSniffer';
import { CastManager } from '../common/CastManager';

const HOME_URL = 'https://www.bing.com';

@Entry
@Component
struct Index {
  webController: webview.WebviewController = new webview.WebviewController();
  sniffer: VideoSniffer = new VideoSniffer();
  castMgr: CastManager = CastManager.getInstance();

  @State inputUrl: string = HOME_URL;
  @State currentUrl: string = HOME_URL;
  @State pageTitle: string = '';
  @State loadProgress: number = 0;
  @State mediaList: MediaItem[] = [];
  @State devices: CastDevice[] = [];
  @State showMediaSheet: boolean = false;
  @State showDeviceSheet: boolean = false;
  @State pendingMedia: MediaItem | null = null;
  @State session: CastSession = new CastSession();
  @State sessionVersion: number = 0; // 触发控制条刷新
  @State discovering: boolean = false;

  aboutToAppear(): void {
    this.sniffer.onFound((item: MediaItem) => {
      this.mediaList = this.mediaList.concat([item]);
    });
    this.castMgr.onDevicesChanged((devs: CastDevice[]) => {
      this.devices = devs;
    });
    this.castMgr.onSessionChanged((s: CastSession) => {
      this.session = s;
      this.sessionVersion++;
    });
  }

  loadUrl(raw: string): void {
    let url = raw.trim();
    if (url === '') {
      return;
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      // 含空格或不含点则走搜索
      if (url.includes(' ') || !url.includes('.')) {
        url = 'https://www.bing.com/search?q=' + encodeURIComponent(url);
      } else {
        url = 'https://' + url;
      }
    }
    this.mediaList = [];
    this.sniffer.resetForPage(url);
    this.webController.loadUrl(url);
  }

  pickDeviceAndCast(item: MediaItem): void {
    this.pendingMedia = item;
    this.showMediaSheet = false;
    this.showDeviceSheet = true;
    this.discovering = true;
    this.castMgr.startDiscovery();
    setTimeout(() => {
      this.discovering = false;
    }, 6500);
  }

  async doCast(device: CastDevice): Promise<void> {
    this.showDeviceSheet = false;
    if (this.pendingMedia === null) {
      return;
    }
    promptAction.showToast({ message: `正在投送到 ${device.friendlyName}…` });
    const ok = await this.castMgr.castTo(device, this.pendingMedia);
    promptAction.showToast({ message: ok ? '投屏成功' : '投屏失败，请检查设备与网络' });
  }

  build() {
    Column() {
      this.AddressBar()
      if (this.loadProgress > 0 && this.loadProgress < 100) {
        Progress({ value: this.loadProgress, total: 100, type: ProgressType.Linear })
          .width('100%').height(2).color($r('app.color.brand_primary'))
      }
      this.WebArea()
      if (this.session.device !== null && this.session.state !== PlayState.STOPPED) {
        this.CastBar()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_dark'))
    .bindSheet($$this.showMediaSheet, this.MediaSheet(), {
      height: 420, dragBar: true, backgroundColor: $r('app.color.bg_card')
    })
    .bindSheet($$this.showDeviceSheet, this.DeviceSheet(), {
      height: 420, dragBar: true, backgroundColor: $r('app.color.bg_card')
    })
  }

  // ---------- 顶部地址栏 ----------
  @Builder
  AddressBar() {
    Row({ space: 8 }) {
      Button() {
        Text('◀').fontSize(16).fontColor($r('app.color.text_primary'))
      }
      .type(ButtonType.Circle).width(36).height(36).backgroundColor($r('app.color.bg_card'))
      .onClick(() => {
        if (this.webController.accessBackward()) {
          this.webController.backward();
        }
      })

      TextInput({ text: $$this.inputUrl, placeholder: '输入网址或搜索' })
        .layoutWeight(1)
        .height(38)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_secondary'))
        .backgroundColor($r('app.color.bg_card'))
        .borderRadius(19)
        .type(InputType.Normal)
        .enterKeyType(EnterKeyType.Go)
        .onSubmit(() => {
          this.loadUrl(this.inputUrl);
        })

      // 嗅探入口：徽标显示已发现媒体数
      Badge({
        count: this.mediaList.length,
        maxCount: 99,
        position: BadgePosition.RightTop,
        style: { badgeSize: 14, badgeColor: '#E8453C', fontSize: 10 }
      }) {
        Button() {
          Text('📺').fontSize(16)
        }
        .type(ButtonType.Circle).width(36).height(36)
        .backgroundColor(this.mediaList.length > 0 ? $r('app.color.brand_primary') : $r('app.color.bg_card'))
        .onClick(() => {
          if (this.mediaList.length === 0) {
            promptAction.showToast({ message: '当前页面尚未发现可投屏的视频' });
            return;
          }
          this.showMediaSheet = true;
        })
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
  }

  // ---------- Web 浏览区 ----------
  @Builder
  WebArea() {
    Web({ src: HOME_URL, controller: this.webController })
      .layoutWeight(1)
      .domStorageAccess(true)
      .javaScriptAccess(true)
      .mixedMode(MixedMode.All)
      .onPageBegin((event) => {
        if (event) {
          this.currentUrl = event.url;
          this.inputUrl = event.url;
          this.sniffer.resetForPage(event.url);
          this.mediaList = [];
        }
      })
      .onTitleReceive((event) => {
        if (event) {
          this.pageTitle = event.title;
          this.sniffer.currentPageTitle = event.title;
        }
      })
      .onProgressChange((event) => {
        if (event) {
          this.loadProgress = event.newProgress;
        }
      })
      .onInterceptRequest((event) => {
        // 旁路嗅探：检查 URL 后返回 null，请求照常发出
        if (event) {
          this.sniffer.inspect(event.request.getRequestUrl());
        }
        return null;
      })
  }

  // ---------- 底部投屏控制条 ----------
  @Builder
  CastBar() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text('📺').fontSize(18)
        Column() {
          Text(this.session.media?.title ?? '')
            .fontSize(13).fontColor($r('app.color.text_primary'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${this.session.device?.friendlyName ?? ''} · ${this.stateLabel()}`)
            .fontSize(11).fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Button(this.session.state === PlayState.PLAYING ? '暂停' : '播放')
          .fontSize(12).height(30)
          .backgroundColor($r('app.color.brand_primary'))
          .onClick(() => {
            if (this.session.state === PlayState.PLAYING) {
              this.castMgr.pause();
            } else {
              this.castMgr.play();
            }
          })
        Button('停止')
          .fontSize(12).height(30)
          .backgroundColor('#3A4250')
          .onClick(() => {
            this.castMgr.stop();
          })
      }
      .width('100%')

      if (this.session.durationSec > 0) {
        Row({ space: 8 }) {
          Text(CastManager.secToHms(this.session.positionSec))
            .fontSize(10).fontColor($r('app.color.text_secondary'))
          Slider({
            value: this.session.positionSec,
            min: 0,
            max: this.session.durationSec,
            style: SliderStyle.OutSet
          })
            .layoutWeight(1)
            .selectedColor($r('app.color.brand_primary'))
            .onChange((value: number, mode: SliderChangeMode) => {
              if (mode === SliderChangeMode.End) {
                this.castMgr.seekTo(value);
              }
            })
          Text(CastManager.secToHms(this.session.durationSec))
            .fontSize(10).fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
      }
    }
    .padding(12)
    .backgroundColor($r('app.color.bg_card'))
  }

  stateLabel(): string {
    switch (this.session.state) {
      case PlayState.PLAYING:
        return '播放中';
      case PlayState.PAUSED:
        return '已暂停';
      case PlayState.TRANSITIONING:
        return '连接中…';
      case PlayState.ERROR:
        return '出错了';
      default:
        return '空闲';
    }
  }

  // ---------- 媒体列表弹层 ----------
  @Builder
  MediaSheet() {
    Column({ space: 4 }) {
      Text('发现的媒体')
        .fontSize(16).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 8, bottom: 8 })
      List({ space: 8 }) {
        ForEach(this.mediaList, (item: MediaItem) => {
          ListItem() {
            Row({ space: 10 }) {
              Text(item.kind === MediaKind.STREAM ? '🔴' : (item.kind === MediaKind.AUDIO ? '🎵' : '🎬'))
                .fontSize(20)
              Column({ space: 2 }) {
                Text(item.title !== '' ? item.title : item.url)
                  .fontSize(13).fontColor($r('app.color.text_primary'))
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(item.url)
                  .fontSize(10).fontColor($r('app.color.text_secondary'))
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Button('投屏')
                .fontSize(12).height(30)
                .backgroundColor($r('app.color.brand_primary'))
                .onClick(() => {
                  this.pickDeviceAndCast(item);
                })
            }
            .width('100%')
            .padding(10)
            .borderRadius(10)
            .backgroundColor('#232A35')
          }
        }, (item: MediaItem) => item.url)
      }
      .layoutWeight(1)
      .width('100%')
    }
    .padding({ left: 16, right: 16, bottom: 16 })
    .width('100%')
    .height('100%')
  }

  // ---------- 设备选择弹层 ----------
  @Builder
  DeviceSheet() {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        Text('选择投屏设备')
          .fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        if (this.discovering) {
          LoadingProgress().width(18).height(18).color($r('app.color.brand_primary'))
        }
        Blank()
        Button('重新搜索')
          .fontSize(12).height(28)
          .backgroundColor('#3A4250')
          .onClick(() => {
            this.discovering = true;
            this.castMgr.startDiscovery();
            setTimeout(() => {
              this.discovering = false;
            }, 6500);
          })
      }
      .width('100%')
      .margin({ top: 8, bottom: 8 })

      if (this.devices.length === 0) {
        Column({ space: 8 }) {
          Text('🔍').fontSize(40)
          Text(this.discovering ? '正在搜索同一 Wi-Fi 下的设备…' : '未发现设备。请确认电视与手机在同一网络，并已开启 DLNA/投屏功能。')
            .fontSize(13).fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .width('100%')
      } else {
        List({ space: 8 }) {
          ForEach(this.devices, (dev: CastDevice) => {
            ListItem() {
              Row({ space: 10 }) {
                Text('🖥️').fontSize(20)
                Column({ space: 2 }) {
                  Text(dev.friendlyName)
                    .fontSize(14).fontColor($r('app.color.text_primary'))
                  Text(`${dev.manufacturer} ${dev.modelName}`.trim())
                    .fontSize(11).fontColor($r('app.color.text_secondary'))
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Text('›').fontSize(18).fontColor($r('app.color.text_secondary'))
              }
              .width('100%')
              .padding(12)
              .borderRadius(10)
              .backgroundColor('#232A35')
              .onClick(() => {
                this.doCast(dev);
              })
            }
          }, (dev: CastDevice) => dev.udn)
        }
        .layoutWeight(1)
        .width('100%')
      }
    }
    .padding({ left: 16, right: 16, bottom: 16 })
    .width('100%')
    .height('100%')
  }
}
