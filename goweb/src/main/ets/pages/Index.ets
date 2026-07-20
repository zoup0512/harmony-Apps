import { webview } from '@kit.ArkWeb';
import { router } from '@kit.ArkUI';
import { FavoritesManager } from '../utils/FavoritesManager';
import { DownloadManager } from '../utils/DownloadManager';
import { FavoriteItem, DownloadRecord, QuickLink } from '../model/FavoriteItem';
import { promptAction } from '@kit.ArkUI';

@Entry
@Component
struct Index {
  @State urlInput: string = '';
  @State currentUrl: string = '';
  @State currentTitle: string = '';
  @State canGoBack: boolean = false;
  @State canGoForward: boolean = false;
  @State loadingProgress: number = 0;
  @State isLoading: boolean = false;
  @State isFavorite: boolean = false;
  @State showDownloadPanel: boolean = false;
  @State downloadRecords: DownloadRecord[] = [];
  @State showQuickLinks: boolean = true;
  @State favoritesPreviewList: FavoriteItem[] = [];

  private webController: webview.WebviewController = new webview.WebviewController();
  private favoritesManager: FavoritesManager = FavoritesManager.getInstance();
  private downloadManager: DownloadManager = DownloadManager.getInstance();

  private quickLinks: QuickLink[] = [
    { title: '知乎', url: 'https://www.zhihu.com' } as QuickLink,
    { title: 'AIZEX', url: 'https://aizex.net/' } as QuickLink,
    { title: '掘金', url: 'https://juejin.cn/' } as QuickLink
  ];

  async aboutToAppear(): Promise<void> {
    const context = getContext(this) as Context;
    await this.favoritesManager.init(context);
    this.downloadManager.init(context);
    this.downloadManager.addListener((records: DownloadRecord[]) => {
      this.downloadRecords = records;
    });
    this.favoritesPreviewList = await this.favoritesManager.getAllFavorites();
  }

  async onPageShow(): Promise<void> {
    this.favoritesPreviewList = await this.favoritesManager.getAllFavorites();
    const selectedUrl = AppStorage.get<string>('selectedUrl');
    if (selectedUrl && selectedUrl.length > 0) {
      this.urlInput = selectedUrl;
      this.currentUrl = selectedUrl;
      this.showQuickLinks = false;
      AppStorage.delete('selectedUrl');
    }
  }

  normalizeUrl(input: string): string {
    let url = input.trim();
    if (url.length === 0) {
      return '';
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      if (url.includes('.') && !url.includes(' ')) {
        url = 'https://' + url;
      } else {
        url = 'https://www.baidu.com/s?wd=' + encodeURIComponent(url);
      }
    }
    return url;
  }

  async loadUrl(): Promise<void> {
    const url = this.normalizeUrl(this.urlInput);
    if (url.length === 0) {
      return;
    }
    this.currentUrl = url;
    this.showQuickLinks = false;
    try {
      this.webController.loadUrl(url);
    } catch (err) {
      promptAction.showToast({ message: '加载失败', duration: 2000 });
    }
  }

  async checkFavorite(): Promise<void> {
    if (this.currentUrl.length > 0) {
      this.isFavorite = await this.favoritesManager.isFavorite(this.currentUrl);
    } else {
      this.isFavorite = false;
    }
  }

  async toggleFavorite(): Promise<void> {
    if (this.isFavorite) {
      const list = await this.favoritesManager.getAllFavorites();
      const item = list.find(i => i.url === this.currentUrl);
      if (item) {
        await this.favoritesManager.removeFavorite(item.id);
        this.isFavorite = false;
        promptAction.showToast({ message: '已取消收藏', duration: 1500 });
      }
    } else {
      const title = this.currentTitle || this.currentUrl;
      const success = await this.favoritesManager.addFavorite(title, this.currentUrl);
      if (success) {
        this.isFavorite = true;
        promptAction.showToast({ message: '已添加收藏', duration: 1500 });
      } else {
        promptAction.showToast({ message: '该网址已收藏', duration: 1500 });
      }
    }
  }

  goBack(): void {
    try {
      this.webController.backward();
    } catch {}
  }

  goForward(): void {
    try {
      this.webController.forward();
    } catch {}
  }

  goHome(): void {
    this.urlInput = '';
    this.currentUrl = '';
    this.currentTitle = '';
    this.isFavorite = false;
    this.showQuickLinks = true;
  }

  refresh(): void {
    try {
      this.webController.refresh();
    } catch {}
  }

  build(): void {
    Column() {
      Column() {
        Row() {
          Button({ type: ButtonType.Circle }) {
            Text('\u2190')
              .fontSize(20)
              .fontColor(this.canGoBack ? '#333333' : '#CCCCCC')
          }
          .width(32).height(32)
          .backgroundColor(Color.Transparent)
          .enabled(this.canGoBack)
          .onClick(() => this.goBack())

          Button({ type: ButtonType.Circle }) {
            Text('\u2192')
              .fontSize(20)
              .fontColor(this.canGoForward ? '#333333' : '#CCCCCC')
          }
          .width(32).height(32)
          .backgroundColor(Color.Transparent)
          .enabled(this.canGoForward)
          .onClick(() => this.goForward())

          TextInput({ text: this.urlInput, placeholder: '输入网址或搜索' })
            .layoutWeight(1)
            .height(36)
            .fontSize(14)
            .backgroundColor('#F5F5F5')
            .borderRadius(18)
            .padding({ left: 12, right: 12 })
            .onChange((value: string) => {
              this.urlInput = value;
            })
            .onSubmit(() => {
              this.loadUrl();
            })

          Button({ type: ButtonType.Circle }) {
            Text('Go')
              .fontSize(13)
              .fontColor('#007DFF')
              .fontWeight(FontWeight.Medium)
          }
          .width(36).height(32)
          .backgroundColor(Color.Transparent)
          .onClick(() => this.loadUrl())

          Button({ type: ButtonType.Circle }) {
            Text(this.isFavorite ? '\u2605' : '\u2606')
              .fontSize(20)
              .fontColor(this.isFavorite ? '#FFB300' : '#666666')
          }
          .width(32).height(32)
          .backgroundColor(Color.Transparent)
          .onClick(() => this.toggleFavorite())
        }
        .width('100%')
        .height(52)
        .padding({ left: 8, right: 8 })
        .backgroundColor('#FFFFFF')

        if (this.isLoading && this.loadingProgress < 100) {
          Progress({ value: this.loadingProgress, total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(2)
            .color('#007DFF')
            .backgroundColor('#E5E5E5')
        }
      }
      .width('100%')

      Stack({ alignContent: Alignment.Bottom }) {
        if (this.currentUrl.length > 0) {
          Web({ src: this.currentUrl, controller: this.webController })
            .domStorageAccess(true)
            .fileAccess(true)
            .imageAccess(true)
            .javaScriptAccess(true)
            .mixedMode(MixedMode.All)
            .geolocationAccess(true)
            .width('100%')
            .height('100%')
            .onPageBegin((event) => {
              this.isLoading = true;
              this.urlInput = event.url;
              this.currentUrl = event.url;
            })
            .onPageEnd((event) => {
              this.isLoading = false;
              this.loadingProgress = 100;
              this.currentUrl = event.url;
              this.urlInput = event.url;
              try {
                this.currentTitle = this.webController.getTitle();
              } catch {}
              try {
                this.canGoBack = this.webController.accessBackward();
                this.canGoForward = this.webController.accessForward();
              } catch {}
              this.checkFavorite();
            })
            .onProgressChange((event) => {
              this.loadingProgress = event.newProgress;
            })
            .onDownloadStart((event) => {
              this.downloadManager.startDownload(event.url, event.contentDisposition, event.mimetype);
            })
        } else {
          this.QuickLinksView()
        }

        if (this.showDownloadPanel) {
          this.DownloadPanel()
        }
      }
      .layoutWeight(1)
      .width('100%')

      this.BottomToolbar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F1F3F5')
  }

  @Builder
  QuickLinksView() {
    Column() {
      Text('快捷链接')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#182431')
        .margin({ top: 40, bottom: 20 })

      Grid() {
        ForEach(this.quickLinks, (link: QuickLink) => {
          GridItem() {
            Column() {
              Text(link.title.charAt(0))
                .fontSize(22)
                .fontColor('#FFFFFF')
                .fontWeight(FontWeight.Bold)
                .width(48).height(48)
                .textAlign(TextAlign.Center)
                .borderRadius(12)
                .backgroundColor('#007DFF')
              Text(link.title)
                .fontSize(12)
                .fontColor('#333333')
                .margin({ top: 8 })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
          }
          .onClick(() => {
            this.urlInput = link.url;
            this.currentUrl = link.url;
            this.showQuickLinks = false;
          })
        })
      }
      .columnsTemplate('1fr 1fr 1fr 1fr')
      .rowsGap(20)
      .columnsGap(12)
      .width('90%')
      .padding({ bottom: 20 })

      Row() {
        Text('收藏夹')
          .fontSize(16)
          .fontColor('#007DFF')
          .fontWeight(FontWeight.Medium)
        Blank()
        Text('管理 >')
          .fontSize(14)
          .fontColor('#666666')
      }
      .width('90%')
      .margin({ top: 20, bottom: 12 })
      .onClick(() => {
        router.pushUrl({ url: 'pages/FavoritesPage' });
      })

      this.FavoritesPreviewList()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F1F3F5')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  FavoritesPreviewList() {
    if (this.favoritesPreviewList.length > 0) {
      List({ space: 8 }) {
        ForEach(this.favoritesPreviewList, (item: FavoriteItem) => {
          ListItem() {
            Row() {
              Text(item.title)
                .fontSize(14)
                .fontColor('#333333')
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(item.url)
                .fontSize(11)
                .fontColor('#999999')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('40%')
            }
            .width('100%')
            .height(44)
            .padding({ left: 12, right: 12 })
            .backgroundColor('#FFFFFF')
            .borderRadius(10)
            .onClick(() => {
              this.urlInput = item.url;
              this.currentUrl = item.url;
              this.showQuickLinks = false;
            })
          }
        })
      }
      .width('90%')
      .height(180)
      .padding({ bottom: 80 })
    } else {
      Column() {
        Text('暂无收藏网址')
          .fontSize(14)
          .fontColor('#999999')
          .margin({ top: 20 })
      }
      .width('90%')
    }
  }

  @Builder
  DownloadPanel() {
    Column() {
      Row() {
        Text('下载列表')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#333333')
        Blank()
        Button('关闭')
          .type(ButtonType.Normal)
          .fontSize(14)
          .fontColor('#007DFF')
          .height(28)
          .onClick(() => {
            this.showDownloadPanel = false;
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      if (this.downloadRecords.length === 0) {
        Text('暂无下载记录')
          .fontSize(14)
          .fontColor('#999999')
          .margin({ top: 24, bottom: 24 })
      } else {
        Scroll() {
          Column() {
            ForEach(this.downloadRecords.slice().reverse(), (record: DownloadRecord) => {
              Row() {
                Column() {
                  Text(record.fileName)
                    .fontSize(14)
                    .fontColor('#333333')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  Row() {
                    Text(record.status === 'completed' ? '已完成' :
                         record.status === 'failed' ? '下载失败' : '下载中')
                      .fontSize(12)
                      .fontColor(record.status === 'completed' ? '#4CAF50' :
                                 record.status === 'failed' ? '#F44336' : '#007DFF')
                    if (record.status === 'downloading') {
                      Text(` ${record.progress}%`)
                        .fontSize(12)
                        .fontColor('#999999')
                    }
                  }
                  .width('100%')
                  .margin({ top: 4 })

                  if (record.status === 'downloading') {
                    Progress({ value: record.progress, total: 100, type: ProgressType.Linear })
                      .width('100%')
                      .height(3)
                      .color('#007DFF')
                      .margin({ top: 6 })
                  }
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .padding(12)
              .backgroundColor('#FFFFFF')
              .borderRadius(10)
              .margin({ bottom: 8 })
            })
          }
          .width('100%')
          .padding({ left: 12, right: 12, bottom: 12 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .height(300)
    .backgroundColor('#FFFFFF')
    .borderRadius({ topLeft: 16, topRight: 16 })
    .shadow({ radius: 20, color: 'rgba(0,0,0,0.15)' })
  }

  @Builder
  BottomToolbar() {
    Row() {
      Button({ type: ButtonType.Circle }) {
        Column() {
          Text('\u2302')
            .fontSize(20)
            .fontColor('#333333')
          Text('首页')
            .fontSize(10)
            .fontColor('#666666')
            .margin({ top: 2 })
        }
      }
      .layoutWeight(1)
      .height(48)
      .backgroundColor(Color.Transparent)
      .onClick(() => this.goHome())

      Button({ type: ButtonType.Circle }) {
        Column() {
          Text('\u2605')
            .fontSize(20)
            .fontColor('#333333')
          Text('收藏')
            .fontSize(10)
            .fontColor('#666666')
            .margin({ top: 2 })
        }
      }
      .layoutWeight(1)
      .height(48)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        router.pushUrl({ url: 'pages/FavoritesPage' });
      })

      Button({ type: ButtonType.Circle }) {
        Column() {
          Text('\u2B07')
            .fontSize(18)
            .fontColor('#333333')
          Text('下载')
            .fontSize(10)
            .fontColor('#666666')
            .margin({ top: 2 })
        }
      }
      .layoutWeight(1)
      .height(48)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.showDownloadPanel = !this.showDownloadPanel;
      })

      Button({ type: ButtonType.Circle }) {
        Column() {
          Text('\u21BB')
            .fontSize(20)
            .fontColor('#333333')
          Text('刷新')
            .fontSize(10)
            .fontColor('#666666')
            .margin({ top: 2 })
        }
      }
      .layoutWeight(1)
      .height(48)
      .backgroundColor(Color.Transparent)
      .onClick(() => this.refresh())
    }
    .width('100%')
    .height(56)
    .backgroundColor('#FFFFFF')
    .border({ width: { top: 1 }, color: { top: '#E5E5E5' } })
    .padding({ bottom: 4 })
  }
}
