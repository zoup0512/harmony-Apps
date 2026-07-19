/**
 * MediaLibrary.ets - 媒体库（单例）
 *
 * 用 @ohos.data.preferences 持久化三类数据：
 *   videos   本地导入 / 直链 / WebDAV 添加的视频条目
 *   sources  WebDAV 网络源
 * 并提供播放进度回写（断点续播）与"继续观看"排序。
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { VideoItem, WebDavSource } from '../model/Models';

const TAG = 'MediaLibrary';
const STORE = 'infuse_library';
const KEY_VIDEOS = 'videos';
const KEY_SOURCES = 'sources';

export class MediaLibrary {
  private static instance: MediaLibrary | null = null;

  static getInstance(): MediaLibrary {
    if (MediaLibrary.instance === null) {
      MediaLibrary.instance = new MediaLibrary();
    }
    return MediaLibrary.instance;
  }

  private store: preferences.Preferences | null = null;
  private videos: VideoItem[] = [];
  private sources: WebDavSource[] = [];

  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.store !== null) {
      return;
    }
    this.store = await preferences.getPreferences(context, STORE);
    this.videos = MediaLibrary.parseVideos(await this.store.get(KEY_VIDEOS, '[]') as string);
    this.sources = MediaLibrary.parseSources(await this.store.get(KEY_SOURCES, '[]') as string);
    hilog.info(0x0001, TAG, 'library loaded: %{public}d videos, %{public}d sources',
      this.videos.length, this.sources.length);
  }

  // ---------------- 视频 ----------------

  getVideos(): VideoItem[] {
    return this.videos.slice();
  }

  /** 最近播放（有 lastPlayedAt 且未播完 95% 的排前面） */
  getContinueWatching(): VideoItem[] {
    return this.videos
      .filter((v: VideoItem) => v.lastPlayedAt > 0 &&
        (v.durationMs === 0 || v.resumeMs < v.durationMs * 0.95))
      .sort((a: VideoItem, b: VideoItem) => b.lastPlayedAt - a.lastPlayedAt)
      .slice(0, 10);
  }

  async addVideo(item: VideoItem): Promise<void> {
    const idx = this.videos.findIndex((v: VideoItem) => v.id === item.id);
    if (idx >= 0) {
      this.videos[idx] = item;
    } else {
      this.videos.unshift(item);
    }
    await this.persistVideos();
  }

  async removeVideo(id: string): Promise<void> {
    this.videos = this.videos.filter((v: VideoItem) => v.id !== id);
    await this.persistVideos();
  }

  /** 播放器退出时回写进度 */
  async updateProgress(id: string, resumeMs: number, durationMs: number): Promise<void> {
    const v = this.videos.find((x: VideoItem) => x.id === id);
    if (!v) {
      return;
    }
    v.resumeMs = resumeMs;
    if (durationMs > 0) {
      v.durationMs = durationMs;
    }
    v.lastPlayedAt = Date.now();
    await this.persistVideos();
  }

  // ---------------- 网络源 ----------------

  getSources(): WebDavSource[] {
    return this.sources.slice();
  }

  async addSource(src: WebDavSource): Promise<void> {
    const idx = this.sources.findIndex((s: WebDavSource) => s.id === src.id);
    if (idx >= 0) {
      this.sources[idx] = src;
    } else {
      this.sources.push(src);
    }
    await this.persistSources();
  }

  async removeSource(id: string): Promise<void> {
    this.sources = this.sources.filter((s: WebDavSource) => s.id !== id);
    await this.persistSources();
  }

  // ---------------- 内部 ----------------

  private async persistVideos(): Promise<void> {
    if (!this.store) {
      return;
    }
    await this.store.put(KEY_VIDEOS, JSON.stringify(this.videos));
    await this.store.flush();
  }

  private async persistSources(): Promise<void> {
    if (!this.store) {
      return;
    }
    await this.store.put(KEY_SOURCES, JSON.stringify(this.sources));
    await this.store.flush();
  }

  private static parseVideos(json: string): VideoItem[] {
    try {
      const arr = JSON.parse(json) as object[];
      return arr.map((o: object) => VideoItem.fromJson(o));
    } catch (e) {
      return [];
    }
  }

  private static parseSources(json: string): WebDavSource[] {
    try {
      const arr = JSON.parse(json) as object[];
      return arr.map((o: object) => WebDavSource.fromJson(o));
    } catch (e) {
      return [];
    }
  }
}
