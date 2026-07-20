/**
 * GRSAI Nano Banana 生图 API 客户端
 * 文档：POST https://grsai.dakka.com.cn/v1/draw/nano-banana
 * 响应可能为 JSON 直出或 SSE 流式（逐行 data: {...}）
 */
import { http } from '@kit.NetworkKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { GenerateRequest, GenerateResult } from '../model/Models'

const BASE_URL = 'https://grsai.dakka.com.cn'
const NANO_BANANA_ENDPOINT = '/v1/draw/nano-banana'
/** 直接字段候选（按文档优先级） */
const DIRECT_URL_KEYS: string[] = ['url', 'imageUrl', 'image_url', 'output', 'result', 'resultUrl']
/** 数组 / 嵌套对象候选字段 */
const NESTED_KEYS: string[] = ['results', 'data', 'output', 'images', 'result', 'image']

export class GrsaiApi {

  /**
   * 调用 Nano Banana 生图接口
   */
  static async generate(apiKey: string, req: GenerateRequest): Promise<GenerateResult> {
    const result = new GenerateResult()
    if (!apiKey || apiKey.trim().length === 0) {
      result.errorMessage = '请先在设置中填写 API Key'
      return result
    }

    const httpRequest = http.createHttp()
    try {
      const body: Record<string, Object> = {
        'model': req.model,
        'webhook': '',
        'urls': req.refImagesBase64,
        'shutProgress': false,
        'prompt': req.prompt,
        'aspectRatio': req.aspectRatio,
        'imageSize': req.imageSize
      }

      const response = await httpRequest.request(BASE_URL + NANO_BANANA_ENDPOINT, {
        method: http.RequestMethod.POST,
        header: {
          'Authorization': `Bearer ${apiKey.trim()}`,
          'Content-Type': 'application/json'
        },
        extraData: JSON.stringify(body),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 30000,
        readTimeout: 300000 // 生图耗时较长，读超时放宽到 5 分钟
      })

      if (response.responseCode < 200 || response.responseCode >= 300) {
        result.errorMessage =
          `Nano Banana image generation failed: HTTP ${response.responseCode} ${response.result}`
        return result
      }

      const raw = response.result as string
      if (!raw || raw.trim().length === 0) {
        result.errorMessage = 'Nano Banana response body is empty'
        return result
      }

      return GrsaiApi.parseResponse(raw)
    } catch (e) {
      result.errorMessage = `请求异常：${(e as Error).message ?? JSON.stringify(e)}`
      return result
    } finally {
      httpRequest.destroy()
    }
  }

  /**
   * 解析响应：兼容 JSON 直出与 SSE 流式两种格式
   */
  static parseResponse(raw: string): GenerateResult {
    const result = new GenerateResult()
    const trimmed = raw.trim()

    // SSE 流式：逐行 data: {...}
    if (trimmed.startsWith('data:') || trimmed.includes('\ndata:')) {
      const lines = trimmed.split('\n')
      let lastFailReason = ''
      for (const line of lines) {
        const l = line.trim()
        if (!l.startsWith('data:')) {
          continue
        }
        const payload = l.substring(5).trim()
        if (payload === '[DONE]' || payload.length === 0) {
          continue
        }
        try {
          const obj: Record<string, Object> = JSON.parse(payload) as Record<string, Object>
          const status = obj['status'] as string
          if (status === 'failed') {
            lastFailReason = (obj['failure_reason'] as string) ?? 'unknown'
            continue
          }
          const url = GrsaiApi.extractImageUrl(obj, 0)
          if (url.length > 0) {
            result.success = true
            result.imageUrl = url
          }
        } catch (_e) {
          // 单行解析失败则跳过
        }
      }
      if (!result.success) {
        result.errorMessage = lastFailReason.length > 0
          ? `Nano Banana task failed: ${lastFailReason}`
          : `Nano Banana stream finished without a successful image url: ${trimmed.substring(0, 200)}`
      }
      return result
    }

    // JSON 直出
    try {
      const obj: Record<string, Object> = JSON.parse(trimmed) as Record<string, Object>
      const status = obj['status'] as string
      if (status === 'failed') {
        result.errorMessage = `Nano Banana task failed: ${(obj['failure_reason'] as string) ?? 'unknown'}`
        return result
      }
      const url = GrsaiApi.extractImageUrl(obj, 0)
      if (url.length > 0) {
        result.success = true
        result.imageUrl = url
      } else {
        result.errorMessage = `响应中未找到图片 URL：${trimmed.substring(0, 200)}`
      }
    } catch (_e) {
      result.errorMessage = `响应解析失败：${trimmed.substring(0, 200)}`
    }
    return result
  }

  /**
   * 按文档规则递归提取图片 URL：
   * 1. 直接字段 url/imageUrl/image_url/output/result/resultUrl
   * 2. 数组字段 results/data/output/images → 递归
   * 3. 嵌套对象 result/data/output/image/images → 递归
   */
  static extractImageUrl(node: Object, depth: number): string {
    if (depth > 5 || node === null || node === undefined) {
      return ''
    }
    if (typeof node === 'string') {
      const s = node as string
      return s.startsWith('http') ? s : ''
    }
    if (Array.isArray(node)) {
      const arr = node as Object[]
      for (const item of arr) {
        const found = GrsaiApi.extractImageUrl(item, depth + 1)
        if (found.length > 0) {
          return found
        }
      }
      return ''
    }
    if (typeof node === 'object') {
      const obj = node as Record<string, Object>
      // 1. 直接字段（值为字符串 URL）
      for (const key of DIRECT_URL_KEYS) {
        const v = obj[key]
        if (typeof v === 'string' && (v as string).startsWith('http')) {
          return v as string
        }
      }
      // 2 & 3. 数组 / 嵌套对象递归
      for (const key of NESTED_KEYS) {
        const v = obj[key]
        if (v !== undefined && typeof v !== 'string') {
          const found = GrsaiApi.extractImageUrl(v, depth + 1)
          if (found.length > 0) {
            return found
          }
        }
      }
    }
    return ''
  }

  /**
   * 下载图片到本地文件，返回本地路径
   */
  static async downloadImage(url: string, destDir: string, fileName: string): Promise<string> {
    const httpRequest = http.createHttp()
    try {
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 30000,
        readTimeout: 120000
      })
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`Image download failed: HTTP ${response.responseCode}`)
      }
      const buffer = response.result as ArrayBuffer
      if (!fs.accessSync(destDir)) {
        fs.mkdirSync(destDir, true)
      }
      const filePath = `${destDir}/${fileName}`
      const file = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
      fs.writeSync(file.fd, buffer)
      fs.closeSync(file)
      return filePath
    } finally {
      httpRequest.destroy()
    }
  }
}
