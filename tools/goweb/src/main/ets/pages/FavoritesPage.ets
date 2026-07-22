import { router } from '@kit.ArkUI';
import { FavoritesManager } from '../utils/FavoritesManager';
import { FavoriteItem } from '../model/FavoriteItem';
import { promptAction } from '@kit.ArkUI';

@Entry
@Component
struct FavoritesPage {
  @State favorites: FavoriteItem[] = [];
  @State showAddDialog: boolean = false;
  @State editMode: boolean = false;
  @State inputTitle: string = '';
  @State inputUrl: string = '';
  @State editingId: string = '';

  private favoritesManager: FavoritesManager = FavoritesManager.getInstance();

  async aboutToAppear(): Promise<void> {
    const context = getContext(this) as Context;
    await this.favoritesManager.init(context);
    await this.loadFavorites();
  }

  async onPageShow(): Promise<void> {
    await this.loadFavorites();
  }

  async loadFavorites(): Promise<void> {
    this.favorites = await this.favoritesManager.getAllFavorites();
  }

  showAddFavorite(): void {
    this.editMode = false;
    this.inputTitle = '';
    this.inputUrl = '';
    this.editingId = '';
    this.showAddDialog = true;
  }

  showEditFavorite(item: FavoriteItem): void {
    this.editMode = true;
    this.inputTitle = item.title;
    this.inputUrl = item.url;
    this.editingId = item.id;
    this.showAddDialog = true;
  }

  async saveFavorite(): Promise<void> {
    const title = this.inputTitle.trim();
    const url = this.inputUrl.trim();

    if (title.length === 0) {
      promptAction.showToast({ message: '请输入名称', duration: 1500 });
      return;
    }
    if (url.length === 0) {
      promptAction.showToast({ message: '请输入网址', duration: 1500 });
      return;
    }

    let normalizedUrl = url;
    if (!normalizedUrl.startsWith('http://') && !normalizedUrl.startsWith('https://')) {
      normalizedUrl = 'https://' + normalizedUrl;
    }

    if (this.editMode) {
      await this.favoritesManager.updateFavorite(this.editingId, title, normalizedUrl);
      promptAction.showToast({ message: '已更新', duration: 1500 });
    } else {
      const success = await this.favoritesManager.addFavorite(title, normalizedUrl);
      if (!success) {
        promptAction.showToast({ message: '该网址已存在', duration: 1500 });
        return;
      }
      promptAction.showToast({ message: '已添加', duration: 1500 });
    }

    this.showAddDialog = false;
    await this.loadFavorites();
  }

  async deleteFavorite(item: FavoriteItem): Promise<void> {
    await this.favoritesManager.removeFavorite(item.id);
    promptAction.showToast({ message: '已删除', duration: 1500 });
    await this.loadFavorites();
  }

  openFavorite(item: FavoriteItem): void {
    AppStorage.setOrCreate<string>('selectedUrl', item.url);
    router.back();
  }

  build(): void {
    Stack() {
      Column() {
        Row() {
          Button({ type: ButtonType.Circle }) {
            Text('\u2190')
              .fontSize(22)
              .fontColor('#333333')
          }
          .width(40).height(40)
          .backgroundColor(Color.Transparent)
          .onClick(() => router.back())

        Text('收藏管理')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#182431')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Button({ type: ButtonType.Circle }) {
          Text('+')
            .fontSize(24)
            .fontColor('#007DFF')
            .fontWeight(FontWeight.Bold)
        }
        .width(40).height(40)
        .backgroundColor(Color.Transparent)
        .onClick(() => this.showAddFavorite())
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 8 })
      .backgroundColor('#FFFFFF')

      if (this.favorites.length === 0) {
        Column() {
          Text('\u2606')
            .fontSize(48)
            .fontColor('#CCCCCC')
            .opacity(0.5)
          Text('暂无收藏网址')
            .fontSize(16)
            .fontColor('#999999')
            .margin({ top: 16 })
          Text('点击右上角 + 添加常用网址')
            .fontSize(13)
            .fontColor('#BBBBBB')
            .margin({ top: 8 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#F1F3F5')
      } else {
        List({ space: 8 }) {
          ForEach(this.favorites, (item: FavoriteItem) => {
            ListItem() {
              Row() {
                Column() {
                  Text(item.title)
                    .fontSize(15)
                    .fontColor('#182431')
                    .fontWeight(FontWeight.Medium)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  Text(item.url)
                    .fontSize(12)
                    .fontColor('#999999')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ top: 4 })
                    .width('100%')
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Button({ type: ButtonType.Circle }) {
                  Text('\u270E')
                    .fontSize(16)
                    .fontColor('#666666')
                }
                .width(36).height(36)
                .backgroundColor(Color.Transparent)
                .onClick(() => this.showEditFavorite(item))

                Button({ type: ButtonType.Circle }) {
                  Text('\u2715')
                    .fontSize(16)
                    .fontColor('#F44336')
                }
                .width(36).height(36)
                .backgroundColor(Color.Transparent)
                .onClick(() => this.deleteFavorite(item))
              }
              .width('100%')
              .padding(14)
              .backgroundColor('#FFFFFF')
              .borderRadius(12)
            }
            .onClick(() => this.openFavorite(item))
          })
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 12, right: 12, top: 12 })
        .backgroundColor('#F1F3F5')
      }
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#F1F3F5')

      if (this.showAddDialog) {
        this.AddDialog()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  AddDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        Text(this.editMode ? '编辑收藏' : '添加收藏')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#182431')
          .margin({ bottom: 20 })

        Column() {
          Text('名称')
            .fontSize(14)
            .fontColor('#666666')
            .width('100%')
            .margin({ bottom: 6 })
          TextInput({ text: this.inputTitle, placeholder: '例如：百度' })
            .height(42)
            .fontSize(14)
            .backgroundColor('#F5F5F5')
            .borderRadius(8)
            .padding({ left: 12, right: 12 })
            .onChange((value: string) => {
              this.inputTitle = value;
            })
        }
        .width('100%')
        .margin({ bottom: 16 })

        Column() {
          Text('网址')
            .fontSize(14)
            .fontColor('#666666')
            .width('100%')
            .margin({ bottom: 6 })
          TextInput({ text: this.inputUrl, placeholder: '例如：www.baidu.com' })
            .height(42)
            .fontSize(14)
            .backgroundColor('#F5F5F5')
            .borderRadius(8)
            .padding({ left: 12, right: 12 })
            .onChange((value: string) => {
              this.inputUrl = value;
            })
        }
        .width('100%')
        .margin({ bottom: 24 })

        Row() {
          Button('取消')
            .type(ButtonType.Normal)
            .height(40)
            .layoutWeight(1)
            .fontSize(15)
            .fontColor('#666666')
            .backgroundColor('#F5F5F5')
            .borderRadius(20)
            .margin({ right: 12 })
            .onClick(() => {
              this.showAddDialog = false;
            })

          Button('保存')
            .type(ButtonType.Normal)
            .height(40)
            .layoutWeight(1)
            .fontSize(15)
            .fontColor('#FFFFFF')
            .backgroundColor('#007DFF')
            .borderRadius(20)
            .onClick(() => this.saveFavorite())
        }
        .width('100%')
      }
      .width('85%')
      .padding(24)
      .backgroundColor('#FFFFFF')
      .borderRadius(16)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0,0,0,0.4)')
  }
}
