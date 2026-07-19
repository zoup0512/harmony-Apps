/**
 * Models.ets - 全局数据模型
 */

/** 媒体来源类型 */
export enum SourceType {
  LOCAL = 'LOCAL',       // 通过文件选择器导入的本地文件
  WEBDAV = 'WEBDAV',     // WebDAV 网络共享
  URL = 'URL'            // 直接输入的 http(s) 直链
}

/** 视频条目（媒体库最小单元） */
export class VideoItem {
  /** 唯一 id：LOCAL/URL 用 uri 本身；WEBDAV 用 server+path */
  id: string = '';
  /** 播放 uri：file:// 或 http(s):// */
  uri: string = '';
  /** 展示标题（经过文件名清洗） */
  title: string = '';
  /** 原始文件名 */
  fileName: string = '';
  source: SourceType = SourceType.LOCAL;
  /** 文件大小（字节），未知为 0 */
  sizeBytes: number = 0;
  /** 时长（毫秒），首次播放后回填 */
  durationMs: number = 0;
  /** 上次播放位置（毫秒） */
  resumeMs: number = 0;
  /** 最近播放时间戳，0 表示从未播放 */
  lastPlayedAt: number = 0;
  /** WebDAV 播放所需的 Authorization 头（Basic xxx），本地/直链为空 */
  authHeader: string = '';

  static fromJson(o: object): VideoItem {
    const v = new VideoItem();
    const r = o as Record<string, Object>;
    v.id = (r['id'] as string) ?? '';
    v.uri = (r['uri'] as string) ?? '';
    v.title = (r['title'] as string) ?? '';
    v.fileName = (r['fileName'] as string) ?? '';
    v.source = (r['source'] as SourceType) ?? SourceType.LOCAL;
    v.sizeBytes = (r['sizeBytes'] as number) ?? 0;
    v.durationMs = (r['durationMs'] as number) ?? 0;
    v.resumeMs = (r['resumeMs'] as number) ?? 0;
    v.lastPlayedAt = (r['lastPlayedAt'] as number) ?? 0;
    v.authHeader = (r['authHeader'] as string) ?? '';
    return v;
  }
}

/** WebDAV 网络源配置 */
export class WebDavSource {
  /** 唯一 id */
  id: string = '';
  /** 显示名，如 "家里的 NAS" */
  name: string = '';
  /** 根地址，如 https://nas.local:5006/dav */
  baseUrl: string = '';
  username: string = '';
  password: string = '';

  static fromJson(o: object): WebDavSource {
    const s = new WebDavSource();
    const r = o as Record<string, Object>;
    s.id = (r['id'] as string) ?? '';
    s.name = (r['name'] as string) ?? '';
    s.baseUrl = (r['baseUrl'] as string) ?? '';
    s.username = (r['username'] as string) ?? '';
    s.password = (r['password'] as string) ?? '';
    return s;
  }
}

/** WebDAV 目录浏览条目 */
export class DavEntry {
  name: string = '';
  /** 相对 baseUrl 的路径，目录以 / 结尾 */
  path: string = '';
  isDir: boolean = false;
  sizeBytes: number = 0;
}

/** 播放器传参（router params） */
export class PlayParams {
  item: VideoItem = new VideoItem();
}

/** 支持的视频扩展名 */
export const VIDEO_EXTS: string[] =
  ['.mp4', '.mkv', '.mov', '.webm', '.avi', '.flv', '.ts', '.m4v', '.3gp', '.wmv', '.m3u8'];

export function isVideoFile(name: string): boolean {
  const n = name.toLowerCase();
  for (const e of VIDEO_EXTS) {
    if (n.endsWith(e)) {
      return true;
    }
  }
  return false;
}

/**
 * 文件名清洗为展示标题：
 * "The.Movie.2023.1080p.BluRay.x264.mkv" → "The Movie 2023"
 */
export function cleanTitle(fileName: string): string {
  let t = fileName;
  const dot = t.lastIndexOf('.');
  if (dot > 0) {
    t = t.substring(0, dot);
  }
  t = t.replace(/[._]+/g, ' ');
  // 截断常见发布组/规格标记
  const markers = ['1080p', '2160p', '720p', '4k', 'bluray', 'blu-ray', 'webrip', 'web-dl', 'webdl',
    'hdtv', 'x264', 'x265', 'h264', 'h265', 'hevc', 'aac', 'remux', 'hdr'];
  const lower = t.toLowerCase();
  let cut = t.length;
  for (const m of markers) {
    const i = lower.indexOf(m);
    if (i > 0 && i < cut) {
      cut = i;
    }
  }
  t = t.substring(0, cut).trim();
  return t === '' ? fileName : t;
}
