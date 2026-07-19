/**
 * Models.ets - 全局数据模型定义
 */

/** 嗅探到的媒体资源 */
export class MediaItem {
  /** 媒体直链 (mp4 / m3u8 / mpd ...) */
  url: string = '';
  /** 猜测的标题（来自页面 title） */
  title: string = '';
  /** 媒体类型: video / audio / stream */
  kind: MediaKind = MediaKind.VIDEO;
  /** MIME 类型 */
  mimeType: string = 'video/mp4';
  /** 来源页面 URL */
  pageUrl: string = '';
  /** 嗅探时间戳 */
  foundAt: number = 0;

  constructor(url?: string, title?: string, kind?: MediaKind, mimeType?: string, pageUrl?: string) {
    this.url = url ?? '';
    this.title = title ?? '';
    this.kind = kind ?? MediaKind.VIDEO;
    this.mimeType = mimeType ?? 'video/mp4';
    this.pageUrl = pageUrl ?? '';
    this.foundAt = Date.now();
  }
}

export enum MediaKind {
  VIDEO = 'video',
  AUDIO = 'audio',
  STREAM = 'stream'
}

/** DLNA 渲染设备 (MediaRenderer) */
export class CastDevice {
  /** 设备唯一标识 (UDN) */
  udn: string = '';
  /** 友好名称，如 "客厅的小米电视" */
  friendlyName: string = '';
  /** 设备描述文档地址 (SSDP LOCATION) */
  location: string = '';
  /** AVTransport 服务控制地址（绝对 URL） */
  avTransportControlUrl: string = '';
  /** RenderingControl 服务控制地址（绝对 URL），用于音量控制 */
  renderingControlUrl: string = '';
  /** 厂商 */
  manufacturer: string = '';
  /** 型号 */
  modelName: string = '';
}

/** 投屏播放状态 */
export enum PlayState {
  IDLE = 'IDLE',
  TRANSITIONING = 'TRANSITIONING',
  PLAYING = 'PLAYING',
  PAUSED = 'PAUSED',
  STOPPED = 'STOPPED',
  ERROR = 'ERROR'
}

/** 当前投屏会话 */
export class CastSession {
  device: CastDevice | null = null;
  media: MediaItem | null = null;
  state: PlayState = PlayState.IDLE;
  positionSec: number = 0;
  durationSec: number = 0;
}

/** 浏览器书签 / 历史条目 */
export class BookmarkItem {
  title: string = '';
  url: string = '';
  visitedAt: number = 0;

  constructor(title?: string, url?: string) {
    this.title = title ?? '';
    this.url = url ?? '';
    this.visitedAt = Date.now();
  }
}
