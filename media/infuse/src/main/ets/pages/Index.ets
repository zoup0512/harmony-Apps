/**
 * Index.ets - 主页面
 *
 * 两个标签：
 *   媒体库：继续观看横滑区 + 全部视频网格；支持文件选择器导入本地视频、添加直链
 *   网络源：WebDAV 源管理与目录浏览（面包屑），点视频直接播放
 */
import { picker } from '@kit.CoreFileKit';
import { promptAction, router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import {
  VideoItem, WebDavSource, DavEntry, SourceType, cleanTitle, isVideoFile
} from '../model/Models';
import { MediaLibrary } from '../common/MediaLibrary';
import { WebDavClient } from '../network/WebDavClient';

@Entry
@Component
struct Index {
  private lib: MediaLibrary = MediaLibrary.getInstance();

  @State activeTab: number = 0;
  @State videos: VideoItem[] = [];
  @State continueList: VideoItem[] = [];
  @State sources: WebDavSource[] = [];

  // WebDAV 浏览态
  @State browsingSource: WebDavSource | null = null;
  @State davPath: string = '/';
  @State davEntries: DavEntry[] = [];
  @State davLoading: boolean = false;

  // 弹层
  @State showAddSource: boolean = false;
  @State showAddUrl: boolean = false;
  @State formName: string = '';
  @State formUrl: string = '';
  @State formUser: string = '';
  @State formPass: string = '';

  async aboutToAppear(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    await this.lib.init(context);
    this.reload();
  }

  onPageShow(): void {
    this.reload(); // 播放返回后刷新进度
  }

  reload(): void {
    this.videos = this.lib.getVideos();
    this.continueList = this.lib.getContinueWatching();
    this.sources = this.lib.getSources();
  }

  // ---------------- 动作 ----------------

  async importLocal(): Promise<void> {
    try {
      const docPicker = new picker.DocumentViewPicker(getContext(this));
      const uris = await docPicker.select({
        maxSelectNumber: 20,
        fileSuffixFilters: ['视频|.mp4,.mkv,.mov,.webm,.avi,.ts,.m4v']
      });
      let added = 0;
      for (const uri of uris) {
        const fileName = Index.nameOfUri(uri);
        if (!isVideoFile(fileName)) {
          continue;
        }
        const item = new VideoItem();
        item.id = uri;
        item.uri = uri;
        item.fileName = fileName;
        item.title = cleanTitle(fileName);
        item.source = SourceType.LOCAL;
        await this.lib.addVideo(item);
        added++;
      }
      if (added > 0) {
        promptAction.showToast({ message: `已导入 ${added} 个视频` });
        this.reload();
      }
    } catch (e) {
      promptAction.showToast({ message: '导入已取消或失败' });
    }
  }

  async addUrlVideo(): Promise<void> {
    const url = this.formUrl.trim();
    if (!url.startsWith('http')) {
      promptAction.showToast({ message: '请输入 http(s) 直链' });
      return;
    }
    const item = new VideoItem();
    item.id = url;
    item.uri = url;
    item.fileName = Index.nameOfUri(url);
    item.title = this.formName.trim() !== '' ? this.formName.trim() : cleanTitle(item.fileName);
    item.source = SourceType.URL;
    await this.lib.addVideo(item);
    this.showAddUrl = false;
    this.formName = '';
    this.formUrl = '';
    this.reload();
  }

  async saveSource(): Promise<void> {
    const base = this.formUrl.trim();
    if (!base.startsWith('http')) {
      promptAction.showToast({ message: '地址需以 http(s):// 开头' });
      return;
    }
    const src = new WebDavSource();
    src.id = util.generateRandomUUID();
    src.name = this.formName.trim() !== '' ? this.formName.trim() : base;
    src.baseUrl = base;
    src.username = this.formUser.trim();
    src.password = this.formPass;
    await this.lib.addSource(src);
    this.showAddSource = false;
    this.formName = '';
    this.formUrl = '';
    this.formUser = '';
    this.formPass = '';
    this.reload();
    promptAction.showToast({ message: '网络源已保存' });
  }

  async browse(src: WebDavSource, path: string): Promise<void> {
    this.browsingSource = src;
    this.davPath = path;
    this.davLoading = true;
    const entries = await WebDavClient.list(src, path);
    this.davLoading = false;
    if (entries === null) {
      promptAction.showToast({ message: '连接失败，请检查地址与账号' });
      return;
    }
    this.davEntries = entries;
  }

  davUp(): void {
    if (this.browsingSource === null) {
      return;
    }
    if (this.davPath === '/' || this.davPath === '') {
      this.browsingSource = null; // 退回源列表
      this.davEntries = [];
      return;
    }
    const trimmed = this.davPath.replace(/\/$/, '');
    const i = trimmed.lastIndexOf('/');
    const parent = i <= 0 ? '/' : trimmed.substring(0, i + 1);
    this.browse(this.browsingSource, parent);
  }

  async playDavFile(entry: DavEntry): Promise<void> {
    const src = this.browsingSource;
    if (src === null) {
      return;
    }
    const item = new VideoItem();
    item.id = src.id + '|' + entry.path;
    item.uri = WebDavClient.fileUrl(src, entry.path);
    item.fileName = entry.name;
    item.title = cleanTitle(entry.name);
    item.source = SourceType.WEBDAV;
    item.sizeBytes = entry.sizeBytes;
    item.authHeader = WebDavClient.authHeader(src);
    await this.lib.addVideo(item); // 进库以便记录进度
    this.openPlayer(item);
  }

  openPlayer(item: VideoItem): void {
    router.pushUrl({ url: 'pages/PlayerPage', params: { item: item } });
  }

  static nameOfUri(uri: string): string {
    const q = uri.indexOf('?');
    const clean = q >= 0 ? uri.substring(0, q) : uri;
    const i = clean.lastIndexOf('/');
    let name = i >= 0 ? clean.substring(i + 1) : clean;
    try {
      name = decodeURIComponent(name);
    } catch (e) { /* keep */ }
    return name;
  }

  static fmtSize(bytes: number): string {
    if (bytes <= 0) {
      return '';
    }
    if (bytes > 1024 * 1024 * 1024) {
      return (bytes / (1024 * 1024 * 1024)).toFixed(1) + ' GB';
    }
    return Math.round(bytes / (1024 * 1024)) + ' MB';
  }

  static fmtProgress(v: VideoItem): string {
    if (v.durationMs <= 0 || v.resumeMs <= 0) {
      return '';
    }
    return Math.round((v.resumeMs / v.durationMs) * 100) + '%';
  }

  // ---------------- UI ----------------

  build() {
    Column() {
      // 顶栏
      Row({ space: 10 }) {
        Text('Infuse').fontSize(24).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.brand_primary'))
        Text('Player').fontSize(24).fontWeight(FontWeight.Lighter)
          .fontColor($r('app.color.text_primary'))
        Blank()
        if (this.activeTab === 0) {
          Button('＋直链').fontSize(12).height(32).backgroundColor($r('app.color.bg_elevated'))
            .onClick(() => {
              this.formName = '';
              this.formUrl = '';
              this.showAddUrl = true;
            })
          Button('导入').fontSize(12).height(32).backgroundColor($r('app.color.brand_primary'))
            .fontColor('#2A1205')
            .onClick(() => this.importLocal())
        } else if (this.browsingSource === null) {
          Button('＋添加源').fontSize(12).height(32).backgroundColor($r('app.color.brand_primary'))
            .fontColor('#2A1205')
            .onClick(() => {
              this.formName = '';
              this.formUrl = '';
              this.formUser = '';
              this.formPass = '';
              this.showAddSource = true;
            })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      // 标签
      Row({ space: 0 }) {
        this.TabButton('媒体库', 0)
        this.TabButton('网络源', 1)
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })

        if (this.activeTab === 0) {
          this.LibraryTab()
        } else {
          this.SourcesTab()
        }
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.bg_dark'))
    .bindSheet($$this.showAddUrl, this.AddUrlSheet(), {
      height: 320, dragBar: true, backgroundColor: $r('app.color.bg_card')
    })
    .bindSheet($$this.showAddSource, this.AddSourceSheet(), {
      height: 480, dragBar: true, backgroundColor: $r('app.color.bg_card')
    })
  }

  @Builder
  TabButton(label: string, index: number) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(15)
        .fontWeight(this.activeTab === index ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.activeTab === index ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
      Divider()
        .width(28).strokeWidth(3)
        .color(this.activeTab === index ? $r('app.color.brand_primary') : Color.Transparent)
    }
    .padding({ right: 20 })
    .onClick(() => {
      this.activeTab = index;
    })
  }

  // ---------- 媒体库 ----------
  @Builder
  LibraryTab() {
    Scroll() {
      Column({ space: 16 }) {
        if (this.continueList.length > 0) {
          Column({ space: 8 }) {
            Text('继续观看').fontSize(17).fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary')).width('100%')
            Scroll() {
              Row({ space: 10 }) {
                ForEach(this.continueList, (v: VideoItem) => {
                  this.ContinueCard(v)
                }, (v: VideoItem) => v.id)
              }
            }
            .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
          }
        }

        Column({ space: 8 }) {
          Row() {
            Text('全部视频').fontSize(17).fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Blank()
            Text(`${this.videos.length} 个`).fontSize(12).fontColor($r('app.color.text_secondary'))
          }.width('100%')

          if (this.videos.length === 0) {
            Column({ space: 10 }) {
              Text('🎬').fontSize(46)
              Text('媒体库还是空的').fontSize(15).fontColor($r('app.color.text_primary'))
              Text('点右上角"导入"选择本地视频，或添加直链 / 网络源')
                .fontSize(12).fontColor($r('app.color.text_secondary')).textAlign(TextAlign.Center)
            }
            .width('100%').padding({ top: 60, bottom: 60 })
            .justifyContent(FlexAlign.Center)
          } else {
            ForEach(this.videos, (v: VideoItem) => {
              this.VideoRow(v)
            }, (v: VideoItem) => v.id)
          }
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 24 })
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
  }

  @Builder
  ContinueCard(v: VideoItem) {
    Column({ space: 0 }) {
      Stack({ alignContent: Alignment.Center }) {
        Rect().width(180).height(101).radiusWidth(10).radiusHeight(10)
          .fill($r('app.color.bg_elevated'))
        Text('▶').fontSize(26).fontColor('#FFFFFFCC')
        if (v.durationMs > 0) {
          Column() {
            Blank()
            Progress({ value: v.resumeMs, total: v.durationMs, type: ProgressType.Linear })
              .width('100%').height(3).color($r('app.color.brand_accent'))
          }.width(180).height(101)
        }
      }
      Text(v.title).fontSize(12).fontColor($r('app.color.text_primary'))
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .width(180).margin({ top: 6 })
    }
    .onClick(() => this.openPlayer(v))
  }

  @Builder
  VideoRow(v: VideoItem) {
    Row({ space: 12 }) {
      Stack({ alignContent: Alignment.Center }) {
        Rect().width(96).height(54).radiusWidth(8).radiusHeight(8)
          .fill($r('app.color.bg_elevated'))
        Text('▶').fontSize(18).fontColor('#FFFFFF99')
      }
      Column({ space: 3 }) {
        Text(v.title).fontSize(14).fontColor($r('app.color.text_primary'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: 6 }) {
          Text(v.source === SourceType.LOCAL ? '本地' : (v.source === SourceType.WEBDAV ? 'WebDAV' : '直链'))
            .fontSize(10).fontColor($r('app.color.brand_primary'))
            .padding({ left: 6, right: 6, top: 1, bottom: 1 })
            .backgroundColor('#FF8C4222').borderRadius(4)
          if (Index.fmtSize(v.sizeBytes) !== '') {
            Text(Index.fmtSize(v.sizeBytes)).fontSize(11).fontColor($r('app.color.text_secondary'))
          }
          if (Index.fmtProgress(v) !== '') {
            Text('已看 ' + Index.fmtProgress(v)).fontSize(11).fontColor($r('app.color.text_secondary'))
          }
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('⋯').fontSize(18).fontColor($r('app.color.text_secondary'))
        .padding(8)
        .onClick(() => {
          this.lib.removeVideo(v.id).then(() => {
            promptAction.showToast({ message: '已从库中移除' });
            this.reload();
          });
        })
    }
    .width('100%')
    .padding(10)
    .borderRadius(12)
    .backgroundColor($r('app.color.bg_card'))
    .onClick(() => this.openPlayer(v))
  }

  // ---------- 网络源 ----------
  @Builder
  SourcesTab() {
    Column({ space: 10 }) {
      if (this.browsingSource === null) {
        // 源列表
        if (this.sources.length === 0) {
          Column({ space: 10 }) {
            Text('🗄️').fontSize(46)
            Text('还没有网络源').fontSize(15).fontColor($r('app.color.text_primary'))
            Text('添加 NAS / WebDAV 共享，直接串流播放，无需下载')
              .fontSize(12).fontColor($r('app.color.text_secondary')).textAlign(TextAlign.Center)
          }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          List({ space: 10 }) {
            ForEach(this.sources, (s: WebDavSource) => {
              ListItem() {
                Row({ space: 12 }) {
                  Text('🗄️').fontSize(22)
                  Column({ space: 2 }) {
                    Text(s.name).fontSize(15).fontColor($r('app.color.text_primary'))
                    Text(s.baseUrl).fontSize(11).fontColor($r('app.color.text_secondary'))
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                  Text('删').fontSize(13).fontColor($r('app.color.text_secondary')).padding(8)
                    .onClick(() => {
                      this.lib.removeSource(s.id).then(() => this.reload());
                    })
                }
                .width('100%').padding(14)
                .borderRadius(12).backgroundColor($r('app.color.bg_card'))
                .onClick(() => this.browse(s, '/'))
              }
            }, (s: WebDavSource) => s.id)
          }
          .layoutWeight(1).width('100%')
        }
      } else {
        // 目录浏览
        Row({ space: 8 }) {
          Button('↑ 上级').fontSize(12).height(30).backgroundColor($r('app.color.bg_elevated'))
            .onClick(() => this.davUp())
          Text(this.browsingSource.name + this.davPath)
            .fontSize(12).fontColor($r('app.color.text_secondary'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }.width('100%')

        if (this.davLoading) {
          Column() {
            LoadingProgress().width(36).height(36).color($r('app.color.brand_primary'))
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          List({ space: 8 }) {
            ForEach(this.davEntries, (e: DavEntry) => {
              ListItem() {
                Row({ space: 12 }) {
                  Text(e.isDir ? '📁' : '🎬').fontSize(20)
                  Column({ space: 2 }) {
                    Text(e.name).fontSize(14).fontColor($r('app.color.text_primary'))
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    if (!e.isDir && Index.fmtSize(e.sizeBytes) !== '') {
                      Text(Index.fmtSize(e.sizeBytes)).fontSize(11)
                        .fontColor($r('app.color.text_secondary'))
                    }
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                  Text('›').fontSize(16).fontColor($r('app.color.text_secondary'))
                }
                .width('100%').padding(12)
                .borderRadius(10).backgroundColor($r('app.color.bg_card'))
                .onClick(() => {
                  const src = this.browsingSource;
                  if (src === null) {
                    return;
                  }
                  if (e.isDir) {
                    this.browse(src, e.path);
                  } else {
                    this.playDavFile(e);
                  }
                })
              }
            }, (e: DavEntry) => e.path)
          }
          .layoutWeight(1).width('100%')
        }
      }
    }
    .layoutWeight(1)
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 16 })
  }

  // ---------- 弹层 ----------
  @Builder
  AddUrlSheet() {
    Column({ space: 14 }) {
      Text('添加视频直链').fontSize(16).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary')).margin({ top: 8 })
      TextInput({ placeholder: '标题（可选）', text: $$this.formName })
        .height(42).backgroundColor($r('app.color.bg_dark')).fontColor($r('app.color.text_primary'))
      TextInput({ placeholder: 'https://.../movie.mp4 或 .m3u8', text: $$this.formUrl })
        .height(42).backgroundColor($r('app.color.bg_dark')).fontColor($r('app.color.text_primary'))
      Button('保存到媒体库').width('100%').height(44)
        .backgroundColor($r('app.color.brand_primary')).fontColor('#2A1205')
        .onClick(() => this.addUrlVideo())
    }
    .width('100%').padding(16)
  }

  @Builder
  AddSourceSheet() {
    Column({ space: 12 }) {
      Text('添加 WebDAV 源').fontSize(16).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary')).margin({ top: 8 })
      TextInput({ placeholder: '名称，如：家里的 NAS', text: $$this.formName })
        .height(42).backgroundColor($r('app.color.bg_dark')).fontColor($r('app.color.text_primary'))
      TextInput({ placeholder: '地址 https://host:port/dav', text: $$this.formUrl })
        .height(42).backgroundColor($r('app.color.bg_dark')).fontColor($r('app.color.text_primary'))
      TextInput({ placeholder: '用户名（可选）', text: $$this.formUser })
        .height(42).backgroundColor($r('app.color.bg_dark')).fontColor($r('app.color.text_primary'))
      TextInput({ placeholder: '密码（可选）', text: $$this.formPass })
        .type(InputType.Password)
        .height(42).backgroundColor($r('app.color.bg_dark')).fontColor($r('app.color.text_primary'))
      Button('保存').width('100%').height(44)
        .backgroundColor($r('app.color.brand_primary')).fontColor('#2A1205')
        .onClick(() => this.saveSource())
      Text('提示：账号密码仅保存在本机，用于访问你的私有共享。')
        .fontSize(11).fontColor($r('app.color.text_secondary'))
    }
    .width('100%').padding(16)
  }
}
