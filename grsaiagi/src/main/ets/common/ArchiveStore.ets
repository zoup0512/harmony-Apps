/**
 * 归档仓库：用 preferences 持久化归档图片元数据与 API Key。
 * 图片文件本体保存在应用沙箱 filesDir/gallery 下。
 */
import { preferences } from '@kit.ArkData'
import { fileIo as fs } from '@kit.CoreFileKit'
import { common } from '@kit.AbilityKit'
import { ArchivedImage } from '../model/Models'

const PREF_NAME = 'agi_store'
const KEY_GALLERY = 'gallery_json'
const KEY_API_KEY = 'grsai_api_key'

export class ArchiveStore {
  private static pref: preferences.Preferences | null = null

  static async init(context: common.UIAbilityContext): Promise<void> {
    if (!ArchiveStore.pref) {
      ArchiveStore.pref = await preferences.getPreferences(context, PREF_NAME)
    }
  }

  static galleryDir(context: common.UIAbilityContext): string {
    return `${context.filesDir}/gallery`
  }

  static async loadGallery(): Promise<ArchivedImage[]> {
    if (!ArchiveStore.pref) {
      return []
    }
    const raw = await ArchiveStore.pref.get(KEY_GALLERY, '[]') as string
    try {
      const arr: ArchivedImage[] = JSON.parse(raw) as ArchivedImage[]
      // 过滤掉文件已不存在的记录
      return arr.filter((item: ArchivedImage) => fs.accessSync(item.filePath))
    } catch (_e) {
      return []
    }
  }

  static async saveGallery(list: ArchivedImage[]): Promise<void> {
    if (!ArchiveStore.pref) {
      return
    }
    await ArchiveStore.pref.put(KEY_GALLERY, JSON.stringify(list))
    await ArchiveStore.pref.flush()
  }

  static async deleteImage(list: ArchivedImage[], id: string): Promise<ArchivedImage[]> {
    const target = list.find((item: ArchivedImage) => item.id === id)
    if (target && fs.accessSync(target.filePath)) {
      try {
        fs.unlinkSync(target.filePath)
      } catch (_e) {
        // 忽略删除文件失败
      }
    }
    const next = list.filter((item: ArchivedImage) => item.id !== id)
    await ArchiveStore.saveGallery(next)
    return next
  }

  static async loadApiKey(): Promise<string> {
    if (!ArchiveStore.pref) {
      return ''
    }
    return await ArchiveStore.pref.get(KEY_API_KEY, '') as string
  }

  static async saveApiKey(key: string): Promise<void> {
    if (!ArchiveStore.pref) {
      return
    }
    await ArchiveStore.pref.put(KEY_API_KEY, key)
    await ArchiveStore.pref.flush()
  }
}
