/**
 * 数据模型定义
 */

/** 批量导入的提示词条目（对应 hand_seal_prompts.json 的 prompts[] 结构） */
export class PromptItem {
  id: number = 0
  name: string = ''
  positivePrompt: string = ''
  negativePrompt: string = ''

  constructor(id: number, name: string, positive: string, negative: string) {
    this.id = id
    this.name = name
    this.positivePrompt = positive
    this.negativePrompt = negative
  }

  /** 合并正向 + 负面提示词为最终生图 prompt（GRSAI 接口无独立负面字段） */
  toFinalPrompt(): string {
    if (this.negativePrompt && this.negativePrompt.length > 0) {
      return `${this.positivePrompt}。严格避免出现：${this.negativePrompt}`
    }
    return this.positivePrompt
  }
}

/** 归档图片记录 */
export class ArchivedImage {
  id: string = ''
  filePath: string = ''
  prompt: string = ''
  promptName: string = ''
  model: string = ''
  resolution: string = ''
  createdAt: number = 0

  static create(filePath: string, prompt: string, promptName: string,
    model: string, resolution: string): ArchivedImage {
    const item = new ArchivedImage()
    item.id = `img_${Date.now()}_${Math.floor(Math.random() * 10000)}`
    item.filePath = filePath
    item.prompt = prompt
    item.promptName = promptName
    item.model = model
    item.resolution = resolution
    item.createdAt = Date.now()
    return item
  }
}

/** 可用模型 */
export class ModelOption {
  displayName: string
  modelName: string

  constructor(displayName: string, modelName: string) {
    this.displayName = displayName
    this.modelName = modelName
  }
}

export const MODEL_OPTIONS: ModelOption[] = [
  new ModelOption('Nano Banana Fast', 'nano-banana-fast'),
  new ModelOption('Nano Banana', 'nano-banana'),
  new ModelOption('Nano Banana Pro', 'nano-banana-pro'),
  new ModelOption('Nano Banana Pro VIP', 'nano-banana-pro-vip'),
  new ModelOption('Nano Banana Pro 4K VIP', 'nano-banana-pro-4k-vip')
]

export const RESOLUTION_OPTIONS: string[] = ['1K', '2K', '4K']

/** 生图请求参数 */
export class GenerateRequest {
  prompt: string = ''
  model: string = 'nano-banana'
  imageSize: string = '2K'
  aspectRatio: string = 'auto'
  /** 图生图模式下的参考图 Base64（不含 data: 前缀）；纯文生图为空数组 */
  refImagesBase64: string[] = []
}

/** 生图结果 */
export class GenerateResult {
  success: boolean = false
  imageUrl: string = ''
  errorMessage: string = ''
}
