/**
 * 灵绘 AGI — 单页生图工作台
 * 视觉方向：玄幻仙侠「墨玉 × 鎏金」，呼应结印题材的金色符文氛围。
 * 页面自上而下：标题栏 → 模式切换 → 参考图 → 提示词（含 JSON 批量导入）
 *              → 模型与分辨率 → 生成 → 归档画廊；全屏预览为覆盖层。
 */
import { picker } from '@kit.CoreFileKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { util } from '@kit.ArkTS'
import { common } from '@kit.AbilityKit'
import { promptAction } from '@kit.ArkUI'
import {
  PromptItem, ArchivedImage, GenerateRequest,
  MODEL_OPTIONS, RESOLUTION_OPTIONS, ModelOption
} from '../model/Models'
import { GrsaiApi } from '../service/GrsaiApi'
import { ArchiveStore } from '../common/ArchiveStore'
import { DEBUG_MODE, DEFAULT_API_KEY, getDefaultPrompts } from '../common/DebugConfig'

// ———— 主题色 ————
const C_BG = '#0D0B10'          // 墨玉底
const C_CARD = '#16131C'        // 卡片
const C_CARD_DEEP = '#1D1926'   // 深层卡片
const C_GOLD = '#D4AF37'        // 鎏金主色
const C_GOLD_DIM = '#8A7430'    // 暗金
const C_TEXT = '#E8DFC8'        // 米金正文
const C_TEXT_DIM = '#8F8878'    // 弱化文字
const C_LINE = '#2A2435'        // 分隔线
const C_DANGER = '#C25450'

@Entry
@Component
struct Index {
  // ———— 全局状态 ————
  @State apiKey: string = ''
  @State showSettings: boolean = false
  // 模式：false = 纯 Prompt（文生图），true = 原图 + Prompt（图生图）
  @State img2imgMode: boolean = false
  @State refImageUri: string = ''
  @State refImageBase64: string = ''
  @State prompt: string = ''
  @State modelIndex: number = 1          // 默认 nano-banana
  @State resolutionIndex: number = 1     // 默认 2K
  // 批量导入
  @State importedPrompts: PromptItem[] = []
  @State activePromptId: number = -1
  // 生成状态
  @State generating: boolean = false
  @State progressText: string = ''
  @State batchTotal: number = 0
  @State batchDone: number = 0
  // 归档
  @State gallery: ArchivedImage[] = []
  // 全屏预览
  @State previewItem: ArchivedImage | null = null

  private context = this.getUIContext().getHostContext() as common.UIAbilityContext

  async aboutToAppear(): Promise<void> {
    await ArchiveStore.init(this.context)
    this.apiKey = await ArchiveStore.loadApiKey()
    this.gallery = await ArchiveStore.loadGallery()
    // Debug 模式：未配置 API Key 时使用默认密钥，并预载默认提示词
    if (DEBUG_MODE) {
      if (this.apiKey.length === 0) {
        this.apiKey = DEFAULT_API_KEY
        await ArchiveStore.saveApiKey(this.apiKey)
      }
      if (this.importedPrompts.length === 0) {
        this.importedPrompts = getDefaultPrompts()
      }
    }
  }

  // ———— 参考图选择 ————
  async pickRefImage(): Promise<void> {
    try {
      const photoPicker = new photoAccessHelper.PhotoViewPicker()
      const result = await photoPicker.select({
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      })
      if (result.photoUris.length === 0) {
        return
      }
      const uri = result.photoUris[0]
      const file = fs.openSync(uri, fs.OpenMode.READ_ONLY)
      const stat = fs.statSync(file.fd)
      const buffer = new ArrayBuffer(stat.size)
      fs.readSync(file.fd, buffer)
      fs.closeSync(file)
      const helper = new util.Base64Helper()
      this.refImageBase64 = helper.encodeToStringSync(new Uint8Array(buffer))
      this.refImageUri = uri
    } catch (e) {
      this.toast(`选图失败：${(e as Error).message}`)
    }
  }

  // ———— JSON 批量导入 ————
  async importPromptJson(): Promise<void> {
    try {
      const docPicker = new picker.DocumentViewPicker(this.context)
      const uris = await docPicker.select({
        maxSelectNumber: 1,
        fileSuffixFilters: ['JSON 文件|.json']
      })
      if (uris.length === 0) {
        return
      }
      const file = fs.openSync(uris[0], fs.OpenMode.READ_ONLY)
      const stat = fs.statSync(file.fd)
      const buffer = new ArrayBuffer(stat.size)
      fs.readSync(file.fd, buffer)
      fs.closeSync(file)
      const text = new util.TextDecoder('utf-8').decodeToString(new Uint8Array(buffer))
      const root: Record<string, Object> = JSON.parse(text) as Record<string, Object>
      const rawList = root['prompts'] as Object[]
      if (!rawList || !Array.isArray(rawList)) {
        this.toast('JSON 中未找到 prompts 数组')
        return
      }
      const parsed: PromptItem[] = []
      for (const item of rawList) {
        const obj = item as Record<string, Object>
        parsed.push(new PromptItem(
          (obj['id'] as number) ?? parsed.length + 1,
          (obj['name'] as string) ?? `Prompt ${parsed.length + 1}`,
          (obj['positive_prompt'] as string) ?? '',
          (obj['negative_prompt'] as string) ?? ''
        ))
      }
      this.importedPrompts = parsed
      this.activePromptId = -1
      this.toast(`已导入 ${parsed.length} 条提示词`)
    } catch (e) {
      this.toast(`导入失败：${(e as Error).message}`)
    }
  }

  // ———— 生成 ————
  private buildRequest(promptText: string): GenerateRequest {
    const req = new GenerateRequest()
    req.prompt = promptText
    req.model = MODEL_OPTIONS[this.modelIndex].modelName
    req.imageSize = RESOLUTION_OPTIONS[this.resolutionIndex]
    req.aspectRatio = 'auto'
    req.refImagesBase64 = (this.img2imgMode && this.refImageBase64.length > 0)
      ? [this.refImageBase64] : []
    return req
  }

  private async generateOne(promptText: string, promptName: string): Promise<boolean> {
    const result = await GrsaiApi.generate(this.apiKey, this.buildRequest(promptText))
    if (!result.success) {
      this.toast(result.errorMessage)
      return false
    }
    try {
      const dir = ArchiveStore.galleryDir(this.context)
      const fileName = `agi_${Date.now()}.png`
      const filePath = await GrsaiApi.downloadImage(result.imageUrl, dir, fileName)
      const record = ArchivedImage.create(
        filePath, promptText, promptName,
        MODEL_OPTIONS[this.modelIndex].displayName,
        RESOLUTION_OPTIONS[this.resolutionIndex]
      )
      this.gallery = [record, ...this.gallery]
      await ArchiveStore.saveGallery(this.gallery)
      return true
    } catch (e) {
      this.toast((e as Error).message)
      return false
    }
  }

  async onGenerate(): Promise<void> {
    if (this.generating) {
      return
    }
    if (this.prompt.trim().length === 0) {
      this.toast('请输入提示词，或从导入列表中选择一条')
      return
    }
    if (this.img2imgMode && this.refImageBase64.length === 0) {
      this.toast('原图 + Prompt 模式需要先选择参考图')
      return
    }
    this.generating = true
    this.batchTotal = 0
    this.progressText = '正在凝聚灵气，生成中…'
    const active = this.importedPrompts.find((p: PromptItem) => p.id === this.activePromptId)
    const ok = await this.generateOne(this.prompt.trim(), active ? active.name : '手动输入')
    this.progressText = ''
    this.generating = false
    if (ok) {
      this.toast('生成完成，已归档')
    }
  }

  async onBatchGenerate(): Promise<void> {
    if (this.generating || this.importedPrompts.length === 0) {
      return
    }
    if (this.img2imgMode && this.refImageBase64.length === 0) {
      this.toast('原图 + Prompt 模式需要先选择参考图')
      return
    }
    this.generating = true
    this.batchTotal = this.importedPrompts.length
    this.batchDone = 0
    let successCount = 0
    for (const item of this.importedPrompts) {
      this.progressText = `批量生成 ${this.batchDone + 1}/${this.batchTotal}：${item.name}`
      const ok = await this.generateOne(item.toFinalPrompt(), item.name)
      if (ok) {
        successCount++
      }
      this.batchDone++
    }
    this.progressText = ''
    this.generating = false
    this.batchTotal = 0
    this.toast(`批量完成：成功 ${successCount}/${this.importedPrompts.length}`)
  }

  async onDeleteImage(id: string): Promise<void> {
    this.gallery = await ArchiveStore.deleteImage(this.gallery, id)
    if (this.previewItem && this.previewItem.id === id) {
      this.previewItem = null
    }
    this.toast('已删除')
  }

  private toast(msg: string): void {
    promptAction.showToast({ message: msg, duration: 2500 })
  }

  private formatTime(ts: number): string {
    const d = new Date(ts)
    const pad = (n: number): string => n < 10 ? `0${n}` : `${n}`
    return `${d.getMonth() + 1}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`
  }

  // ———— UI 构建 ————
  build() {
    Stack() {
      Scroll() {
        Column({ space: 14 }) {
          this.HeaderBar()
          this.ModeSwitcher()
          if (this.img2imgMode) {
            this.RefImageCard()
          }
          this.PromptCard()
          this.ModelCard()
          this.GenerateArea()
          this.GallerySection()
          Blank().height(40)
        }
        .padding({ left: 16, right: 16, top: 8 })
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      if (this.showSettings) {
        this.SettingsOverlay()
      }
      if (this.previewItem !== null) {
        this.PreviewOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(C_BG)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  // 标题栏
  @Builder
  HeaderBar() {
    Row() {
      Column({ space: 2 }) {
        Text('灵 绘')
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor(C_GOLD)
          .letterSpacing(6)
        Text('GRSAI · NANO BANANA 生图工作台')
          .fontSize(10)
          .fontColor(C_TEXT_DIM)
          .letterSpacing(2)
      }
      .alignItems(HorizontalAlign.Start)

      Blank()

      // 设置入口（API Key）
      Text(this.apiKey.length > 0 ? '⚙ 已配置' : '⚙ 设置 Key')
        .fontSize(12)
        .fontColor(this.apiKey.length > 0 ? C_GOLD_DIM : C_DANGER)
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .border({ width: 1, color: C_LINE, radius: 14 })
        .onClick(() => {
          this.showSettings = true
        })
    }
    .width('100%')
    .padding({ top: 10, bottom: 2 })
  }

  // 模式切换：纯 Prompt / 原图 + Prompt
  @Builder
  ModeSwitcher() {
    Row() {
      this.ModeTab('纯 Prompt 生图', !this.img2imgMode, () => {
        this.img2imgMode = false
      })
      this.ModeTab('原图 + Prompt', this.img2imgMode, () => {
        this.img2imgMode = true
      })
    }
    .width('100%')
    .padding(4)
    .backgroundColor(C_CARD)
    .borderRadius(16)
    .border({ width: 1, color: C_LINE })
  }

  @Builder
  ModeTab(label: string, active: boolean, onTap: () => void) {
    Text(label)
      .fontSize(14)
      .fontWeight(active ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(active ? '#1A1408' : C_TEXT_DIM)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .padding({ top: 10, bottom: 10 })
      .backgroundColor(active ? C_GOLD : Color.Transparent)
      .borderRadius(12)
      .onClick(onTap)
      .animation({ duration: 180, curve: Curve.EaseOut })
  }

  // 参考图卡片（图生图模式）
  @Builder
  RefImageCard() {
    Column({ space: 10 }) {
      Row() {
        Text('参考原图').fontSize(14).fontColor(C_TEXT).fontWeight(FontWeight.Medium)
        Blank()
        if (this.refImageUri.length > 0) {
          Text('移除')
            .fontSize(12)
            .fontColor(C_DANGER)
            .onClick(() => {
              this.refImageUri = ''
              this.refImageBase64 = ''
            })
        }
      }
      .width('100%')

      if (this.refImageUri.length > 0) {
        Image(this.refImageUri)
          .width('100%')
          .height(180)
          .objectFit(ImageFit.Cover)
          .borderRadius(12)
          .onClick(() => {
            this.pickRefImage()
          })
      } else {
        Column({ space: 6 }) {
          Text('＋').fontSize(30).fontColor(C_GOLD_DIM)
          Text('从相册选择参考图').fontSize(12).fontColor(C_TEXT_DIM)
        }
        .width('100%')
        .height(120)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(C_CARD_DEEP)
        .borderRadius(12)
        .border({ width: 1, color: C_LINE, style: BorderStyle.Dashed })
        .onClick(() => {
          this.pickRefImage()
        })
      }
    }
    .cardStyle()
  }

  // 提示词卡片 + 批量导入
  @Builder
  PromptCard() {
    Column({ space: 12 }) {
      Row() {
        Text('提示词').fontSize(14).fontColor(C_TEXT).fontWeight(FontWeight.Medium)
        Blank()
        Text('导入 JSON')
          .fontSize(12)
          .fontColor(C_GOLD)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .border({ width: 1, color: C_GOLD_DIM, radius: 12 })
          .onClick(() => {
            this.importPromptJson()
          })
      }
      .width('100%')

      TextArea({
        placeholder: '描述想要生成的画面，例如：中国玄幻仙侠风，手部结印特写…',
        text: this.prompt
      })
        .placeholderColor(C_TEXT_DIM)
        .placeholderFont({ size: 13 })
        .fontSize(14)
        .fontColor(C_TEXT)
        .caretColor(C_GOLD)
        .backgroundColor(C_CARD_DEEP)
        .borderRadius(12)
        .height(110)
        .onChange((value: string) => {
          this.prompt = value
          // 手动编辑后取消导入项高亮
          const active = this.importedPrompts.find((p: PromptItem) => p.id === this.activePromptId)
          if (active && value !== active.toFinalPrompt()) {
            this.activePromptId = -1
          }
        })

      if (this.importedPrompts.length > 0) {
        Column({ space: 8 }) {
          Row() {
            Text(`已导入 ${this.importedPrompts.length} 条 · 点选填入`)
              .fontSize(11)
              .fontColor(C_TEXT_DIM)
            Blank()
            Text('清空')
              .fontSize(11)
              .fontColor(C_TEXT_DIM)
              .onClick(() => {
                this.importedPrompts = []
                this.activePromptId = -1
              })
          }
          .width('100%')

          Scroll() {
            Row({ space: 8 }) {
              ForEach(this.importedPrompts, (item: PromptItem) => {
                Text(`${item.id} · ${item.name}`)
                  .fontSize(12)
                  .fontColor(this.activePromptId === item.id ? '#1A1408' : C_TEXT)
                  .padding({ left: 12, right: 12, top: 7, bottom: 7 })
                  .backgroundColor(this.activePromptId === item.id ? C_GOLD : C_CARD_DEEP)
                  .borderRadius(14)
                  .border({ width: 1, color: this.activePromptId === item.id ? C_GOLD : C_LINE })
                  .onClick(() => {
                    this.activePromptId = item.id
                    this.prompt = item.toFinalPrompt()
                  })
              }, (item: PromptItem) => `${item.id}`)
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
        }
      }
    }
    .cardStyle()
  }

  // 模型与分辨率
  @Builder
  ModelCard() {
    Column({ space: 12 }) {
      Text('模型与画质').fontSize(14).fontColor(C_TEXT).fontWeight(FontWeight.Medium)
        .alignSelf(ItemAlign.Start)

      Scroll() {
        Row({ space: 8 }) {
          ForEach(MODEL_OPTIONS, (item: ModelOption, index: number) => {
            Text(item.displayName)
              .fontSize(12)
              .fontColor(this.modelIndex === index ? '#1A1408' : C_TEXT)
              .padding({ left: 12, right: 12, top: 7, bottom: 7 })
              .backgroundColor(this.modelIndex === index ? C_GOLD : C_CARD_DEEP)
              .borderRadius(14)
              .onClick(() => {
                this.modelIndex = index
              })
          }, (item: ModelOption) => item.modelName)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')

      Row({ space: 8 }) {
        ForEach(RESOLUTION_OPTIONS, (res: string, index: number) => {
          Text(res)
            .fontSize(13)
            .fontColor(this.resolutionIndex === index ? '#1A1408' : C_TEXT)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .padding({ top: 8, bottom: 8 })
            .backgroundColor(this.resolutionIndex === index ? C_GOLD : C_CARD_DEEP)
            .borderRadius(12)
            .onClick(() => {
              this.resolutionIndex = index
            })
        }, (res: string) => res)
      }
      .width('100%')
    }
    .cardStyle()
  }

  // 生成按钮与进度
  @Builder
  GenerateArea() {
    Column({ space: 10 }) {
      Button(this.generating && this.batchTotal === 0 ? '生成中…' : '立即生成')
        .width('100%')
        .height(50)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor('#1A1408')
        .backgroundColor(C_GOLD)
        .borderRadius(25)
        .enabled(!this.generating)
        .opacity(this.generating ? 0.5 : 1)
        .onClick(() => {
          this.onGenerate()
        })

      if (this.importedPrompts.length > 0) {
        Button(this.generating && this.batchTotal > 0
          ? `批量生成中 ${this.batchDone}/${this.batchTotal}`
          : `批量生成全部 ${this.importedPrompts.length} 条`)
          .width('100%')
          .height(44)
          .fontSize(14)
          .fontColor(C_GOLD)
          .backgroundColor(Color.Transparent)
          .border({ width: 1, color: C_GOLD_DIM, radius: 22 })
          .enabled(!this.generating)
          .opacity(this.generating ? 0.5 : 1)
          .onClick(() => {
            this.onBatchGenerate()
          })
      }

      if (this.generating) {
        Row({ space: 10 }) {
          LoadingProgress().width(18).height(18).color(C_GOLD)
          Text(this.progressText).fontSize(12).fontColor(C_TEXT_DIM)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        if (this.batchTotal > 0) {
          Progress({ value: this.batchDone, total: this.batchTotal, type: ProgressType.Linear })
            .width('100%')
            .color(C_GOLD)
            .backgroundColor(C_CARD_DEEP)
        }
      }
    }
    .width('100%')
  }

  // 归档画廊
  @Builder
  GallerySection() {
    Column({ space: 12 }) {
      Row() {
        Text('归档').fontSize(16).fontColor(C_GOLD).fontWeight(FontWeight.Medium).letterSpacing(2)
        Text(`  ${this.gallery.length} 张`).fontSize(11).fontColor(C_TEXT_DIM)
        Blank()
      }
      .width('100%')

      if (this.gallery.length === 0) {
        Column({ space: 6 }) {
          Text('◇').fontSize(28).fontColor(C_GOLD_DIM)
          Text('还没有作品，生成后会自动归档到这里').fontSize(12).fontColor(C_TEXT_DIM)
        }
        .width('100%')
        .padding({ top: 30, bottom: 30 })
        .backgroundColor(C_CARD)
        .borderRadius(16)
      } else {
        Grid() {
          ForEach(this.gallery, (item: ArchivedImage) => {
            GridItem() {
              Column({ space: 0 }) {
                Image(`file://${item.filePath}`)
                  .width('100%')
                  .aspectRatio(1)
                  .objectFit(ImageFit.Cover)
                  .borderRadius({ topLeft: 12, topRight: 12 })
                Column({ space: 2 }) {
                  Text(item.promptName)
                    .fontSize(11)
                    .fontColor(C_TEXT)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(`${item.resolution} · ${this.formatTime(item.createdAt)}`)
                    .fontSize(9)
                    .fontColor(C_TEXT_DIM)
                }
                .alignItems(HorizontalAlign.Start)
                .width('100%')
                .padding(8)
              }
              .backgroundColor(C_CARD)
              .borderRadius(12)
              .border({ width: 1, color: C_LINE })
              .onClick(() => {
                this.previewItem = item
              })
              .gesture(LongPressGesture().onAction(() => {
                this.getUIContext().showAlertDialog({
                  title: '删除作品',
                  message: `确定删除「${item.promptName}」吗？`,
                  primaryButton: {
                    value: '取消',
                    action: () => {
                    }
                  },
                  secondaryButton: {
                    value: '删除',
                    fontColor: C_DANGER,
                    action: () => {
                      this.onDeleteImage(item.id)
                    }
                  }
                })
              }))
            }
          }, (item: ArchivedImage) => item.id)
        }
        .columnsTemplate('1fr 1fr')
        .columnsGap(10)
        .rowsGap(10)
        .width('100%')
      }
    }
    .width('100%')
  }

  // API Key 设置浮层
  @Builder
  SettingsOverlay() {
    Column() {
      Blank()
        .layoutWeight(1)
        .width('100%')
        .onClick(() => {
          this.showSettings = false
        })
      Column({ space: 14 }) {
        Text('GRSAI API Key')
          .fontSize(16)
          .fontColor(C_GOLD)
          .fontWeight(FontWeight.Medium)
        Text('调用 grsai.dakka.com.cn 生图接口所需的密钥，仅保存在本机。')
          .fontSize(11)
          .fontColor(C_TEXT_DIM)
        TextInput({ placeholder: 'sk-xxxxxxxx', text: this.apiKey })
          .type(InputType.Password)
          .fontSize(14)
          .fontColor(C_TEXT)
          .placeholderColor(C_TEXT_DIM)
          .caretColor(C_GOLD)
          .backgroundColor(C_CARD_DEEP)
          .borderRadius(12)
          .onChange((value: string) => {
            this.apiKey = value
          })
        Button('保存')
          .width('100%')
          .height(44)
          .fontColor('#1A1408')
          .backgroundColor(C_GOLD)
          .borderRadius(22)
          .onClick(async () => {
            await ArchiveStore.saveApiKey(this.apiKey.trim())
            this.showSettings = false
            this.toast('已保存')
          })
      }
      .width('100%')
      .padding(20)
      .backgroundColor(C_CARD)
      .borderRadius({ topLeft: 20, topRight: 20 })
      .border({ width: { top: 1 }, color: C_LINE })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#B3000000')
    .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
  }

  // 全屏大图预览
  @Builder
  PreviewOverlay() {
    Column() {
      Row() {
        Text('✕')
          .fontSize(20)
          .fontColor(C_TEXT)
          .padding(12)
          .onClick(() => {
            this.previewItem = null
          })
        Blank()
        Text('删除')
          .fontSize(14)
          .fontColor(C_DANGER)
          .padding(12)
          .onClick(() => {
            if (this.previewItem) {
              this.onDeleteImage(this.previewItem.id)
            }
          })
      }
      .width('100%')
      .padding({ top: 36, left: 8, right: 8 })

      Image(`file://${this.previewItem!.filePath}`)
        .width('100%')
        .layoutWeight(1)
        .objectFit(ImageFit.Contain)
        .onClick(() => {
          this.previewItem = null
        })

      Column({ space: 4 }) {
        Text(this.previewItem!.promptName)
          .fontSize(14)
          .fontColor(C_GOLD)
          .fontWeight(FontWeight.Medium)
        Text(`${this.previewItem!.model} · ${this.previewItem!.resolution} · ${this.formatTime(this.previewItem!.createdAt)}`)
          .fontSize(10)
          .fontColor(C_TEXT_DIM)
        Text(this.previewItem!.prompt)
          .fontSize(11)
          .fontColor(C_TEXT_DIM)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 30 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F2000000')
    .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
  }
}

// 通用卡片样式
@Extend(Column)
function cardStyle() {
  .width('100%')
  .padding(14)
  .backgroundColor(C_CARD)
  .borderRadius(16)
  .border({ width: 1, color: C_LINE })
  .alignItems(HorizontalAlign.Start)
}
