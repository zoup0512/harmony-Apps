/**
 * VideoSniffer.ets - 视频嗅探器
 *
 * 挂接在 Web 组件的 onInterceptRequest 回调上，检查每一个由页面发起的
 * 子资源请求 URL；命中媒体特征（扩展名 / 关键路径）则记录为 MediaItem。
 * 返回 null 让请求继续正常加载，做到"旁路观察、不干扰页面"。
 */
import { MediaItem, MediaKind } from '../model/Models';

const VIDEO_EXT: string[] = ['.mp4', '.mkv', '.webm', '.mov', '.avi', '.flv', '.ts', '.3gp'];
const AUDIO_EXT: string[] = ['.mp3', '.aac', '.m4a', '.flac', '.ogg', '.wav'];
const STREAM_EXT: string[] = ['.m3u8', '.mpd'];

const MIME_BY_EXT: Record<string, string> = {
  '.mp4': 'video/mp4',
  '.mkv': 'video/x-matroska',
  '.webm': 'video/webm',
  '.mov': 'video/quicktime',
  '.avi': 'video/x-msvideo',
  '.flv': 'video/x-flv',
  '.ts': 'video/mp2t',
  '.3gp': 'video/3gpp',
  '.mp3': 'audio/mpeg',
  '.aac': 'audio/aac',
  '.m4a': 'audio/mp4',
  '.flac': 'audio/flac',
  '.ogg': 'audio/ogg',
  '.wav': 'audio/wav',
  '.m3u8': 'application/vnd.apple.mpegurl',
  '.mpd': 'application/dash+xml'
};

/** 常见广告 / 心跳请求黑名单，避免误报 */
const BLACKLIST_KEYWORDS: string[] = ['googleads', 'doubleclick', 'analytics', 'beacon', 'pixel.gif', 'log.gif'];

export type SnifferListener = (item: MediaItem) => void;

export class VideoSniffer {
  private seen: Set<string> = new Set<string>();
  private listener: SnifferListener | null = null;
  /** 当前页面上下文，用于填充 MediaItem 的 title / pageUrl */
  currentPageUrl: string = '';
  currentPageTitle: string = '';

  onFound(listener: SnifferListener): void {
    this.listener = listener;
  }

  /** 切换页面时清空去重表（同一 URL 在新页面可再次上报） */
  resetForPage(pageUrl: string): void {
    this.seen.clear();
    this.currentPageUrl = pageUrl;
  }

  /**
   * 检查一个请求 URL。命中则回调 listener 并返回 true。
   * 该方法必须足够轻量（每个子请求都会调用）。
   */
  inspect(rawUrl: string): boolean {
    if (!rawUrl || !rawUrl.startsWith('http')) {
      return false;
    }
    const lower = rawUrl.toLowerCase();
    for (const bad of BLACKLIST_KEYWORDS) {
      if (lower.includes(bad)) {
        return false;
      }
    }
    // 去掉 query 后取路径，判断扩展名
    const qIndex = lower.indexOf('?');
    const path = qIndex >= 0 ? lower.substring(0, qIndex) : lower;

    const ext = VideoSniffer.matchExt(path);
    if (ext === '') {
      return false;
    }
    // 去重（HLS 会产生大量 .ts 分片，只保留清单）
    if (ext === '.ts' && this.hasStreamAlready()) {
      return false;
    }
    const dedupKey = ext === '.m3u8' ? VideoSniffer.m3u8DedupKey(path) : path;
    if (this.seen.has(dedupKey)) {
      return false;
    }
    this.seen.add(dedupKey);

    const kind: MediaKind = STREAM_EXT.includes(ext) ? MediaKind.STREAM
      : (AUDIO_EXT.includes(ext) ? MediaKind.AUDIO : MediaKind.VIDEO);
    const item = new MediaItem(
      rawUrl,
      this.currentPageTitle !== '' ? this.currentPageTitle : VideoSniffer.fileNameOf(path),
      kind,
      MIME_BY_EXT[ext] ?? 'video/mp4',
      this.currentPageUrl
    );
    if (this.listener) {
      this.listener(item);
    }
    return true;
  }

  private hasStreamAlready(): boolean {
    let found = false;
    this.seen.forEach((k: string) => {
      if (k.endsWith('.m3u8') || k.endsWith('.mpd')) {
        found = true;
      }
    });
    return found;
  }

  private static matchExt(path: string): string {
    const all = VIDEO_EXT.concat(AUDIO_EXT).concat(STREAM_EXT);
    for (const e of all) {
      if (path.endsWith(e)) {
        return e;
      }
    }
    return '';
  }

  /** 同一目录下的多码率 m3u8 视作同一资源 */
  private static m3u8DedupKey(path: string): string {
    const idx = path.lastIndexOf('/');
    return idx > 0 ? path.substring(0, idx) + '/#hls' : path;
  }

  private static fileNameOf(path: string): string {
    const idx = path.lastIndexOf('/');
    return idx >= 0 ? path.substring(idx + 1) : path;
  }
}
