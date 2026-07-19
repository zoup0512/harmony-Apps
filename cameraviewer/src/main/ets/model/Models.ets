/**
 * Models.ets - 全局数据模型
 */

/** 相机流类型 */
export enum CamKind {
  /** MJPEG 视频流 */
  MJPEG = 'MJPEG',
  /** 单帧快照轮询 */
  JPEG_POLL = 'JPEG_POLL',
  /** RTSP / HTTP 视频流（AVPlayer 硬解） */
  RTSP_HTTP = 'RTSP_HTTP'
}

/** 相机连接状态 */
export enum CamState {
  IDLE = 'IDLE',
  CONNECTING = 'CONNECTING',
  LIVE = 'LIVE',
  ERROR = 'ERROR'
}

/** 相机配置 */
export class Camera {
  id: string = '';
  name: string = '';
  kind: CamKind = CamKind.RTSP_HTTP;
  /** 主取流地址（rtsp:// 或 http(s)://） */
  url: string = '';
  /** 快照地址（列表缩略图与 RTSP 通道截图用；ONVIF 添加时自动获取） */
  snapshotUrl: string = '';
  username: string = '';
  password: string = '';
  enabled: boolean = true;
  pollIntervalMs: number = 1000;
  /** ONVIF 设备服务地址（发现添加时记录；有值才有 PTZ 能力） */
  onvifXAddr: string = '';
  /** 设备是否报告 PTZ 能力（GetCapabilities 有 PTZ 段） */
  ptz: boolean = false;

  static fromJson(o: object): Camera {
    const c = new Camera();
    const r = o as Record<string, Object>;
    c.id = (r['id'] as string) ?? '';
    c.name = (r['name'] as string) ?? '';
    c.kind = (r['kind'] as CamKind) ?? CamKind.RTSP_HTTP;
    c.url = (r['url'] as string) ?? '';
    c.snapshotUrl = (r['snapshotUrl'] as string) ?? '';
    c.username = (r['username'] as string) ?? '';
    c.password = (r['password'] as string) ?? '';
    c.enabled = (r['enabled'] as boolean) ?? true;
    c.pollIntervalMs = (r['pollIntervalMs'] as number) ?? 1000;
    c.onvifXAddr = (r['onvifXAddr'] as string) ?? '';
    c.ptz = (r['ptz'] as boolean) ?? false;
    return c;
  }
}

/** ONVIF WS-Discovery 发现结果 */
export class OnvifDevice {
  xAddr: string = '';
  name: string = '';
  hardware: string = '';
  ip: string = '';
}

/** ONVIF PTZ 预置位 */
export class PtzPreset {
  token: string = '';
  name: string = '';
}

/** PTZ 方向速度向量（pan/tilt/zoom ∈ [-1,1]） */
export class PtzVector {
  x: number = 0;
  y: number = 0;
  z: number = 0;

  constructor(x: number, y: number, z: number) {
    this.x = x;
    this.y = y;
    this.z = z;
  }
}

/** 全屏页路由参数 */
export class LivePageParams {
  camera: Camera = new Camera();
}

/** 四分屏 RTSP 硬解并发上限（默认 2，可调 1-4） */
export const DEFAULT_VIDEO_DECODE_CAP = 2;

/** 列表缩略图刷新间隔（毫秒） */
export const THUMB_INTERVAL_MS = 5000;

/** 轮巡切换间隔（秒，可调） */
export const DEFAULT_SEQUENCE_SEC = 10;
