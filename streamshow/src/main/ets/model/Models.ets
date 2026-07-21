/**
 * Models.ets - 全局数据模型
 */

/** 通道流类型 */
export enum ChannelType {
  /** MJPEG 视频流 */
  MJPEG = 'MJPEG',
  /** 单帧快照轮询 */
  JPEG_POLL = 'JPEG_POLL',
  /** RTSP / HTTP 视频流（AVPlayer 硬解） */
  RTSP_HTTP = 'RTSP_HTTP'
}

/** 通道连接状态 */
export enum ChState {
  IDLE = 'IDLE',
  CONNECTING = 'CONNECTING',
  LIVE = 'LIVE',
  ERROR = 'ERROR'
}

/** 摄像头通道配置 */
export class Channel {
  id: string = '';
  name: string = '';
  type: ChannelType = ChannelType.MJPEG;
  url: string = '';
  username: string = '';
  password: string = '';
  enabled: boolean = true;
  pollIntervalMs: number = 1000;
  /** 由 ONVIF 发现时记录设备服务地址（便于日后重取流地址） */
  onvifXAddr: string = '';

  static fromJson(o: object): Channel {
    const c = new Channel();
    const r = o as Record<string, Object>;
    c.id = (r['id'] as string) ?? '';
    c.name = (r['name'] as string) ?? '';
    c.type = (r['type'] as ChannelType) ?? ChannelType.MJPEG;
    c.url = (r['url'] as string) ?? '';
    c.username = (r['username'] as string) ?? '';
    c.password = (r['password'] as string) ?? '';
    c.enabled = (r['enabled'] as boolean) ?? true;
    c.pollIntervalMs = (r['pollIntervalMs'] as number) ?? 1000;
    c.onvifXAddr = (r['onvifXAddr'] as string) ?? '';
    return c;
  }
}

/** 网格布局：每屏格数（1/4/9/16），列数为平方根 */
export const WALL_LAYOUTS: number[] = [1, 4, 9, 16];

export function columnsOf(cells: number): number {
  return Math.round(Math.sqrt(cells));
}

/** 同屏 RTSP 硬解并发上限（性能保护，可在设置调整 1-4） */
export const DEFAULT_VIDEO_DECODE_CAP = 2;

/** ONVIF WS-Discovery 发现结果 */
export class OnvifDevice {
  /** 设备服务地址，如 http://192.168.1.64/onvif/device_service */
  xAddr: string = '';
  /** 从 scopes 提取的名称 */
  name: string = '';
  /** 从 scopes 提取的硬件型号 */
  hardware: string = '';
  /** 设备 IP（从 xAddr 提取） */
  ip: string = '';
}

/** RTSP 地址模板（地址生成器用） */
export class RtspTemplate {
  brand: string;
  main: string;
  sub: string;

  constructor(brand: string, main: string, sub: string) {
    this.brand = brand;
    this.main = main;
    this.sub = sub;
  }
}

export const RTSP_TEMPLATES: RtspTemplate[] = [
  new RtspTemplate('海康威视 Hikvision',
    'rtsp://{user}:{pass}@{ip}:554/Streaming/Channels/101',
    'rtsp://{user}:{pass}@{ip}:554/Streaming/Channels/102'),
  new RtspTemplate('大华 Dahua',
    'rtsp://{user}:{pass}@{ip}:554/cam/realmonitor?channel=1&subtype=0',
    'rtsp://{user}:{pass}@{ip}:554/cam/realmonitor?channel=1&subtype=1'),
  new RtspTemplate('Reolink',
    'rtsp://{user}:{pass}@{ip}:554/h264Preview_01_main',
    'rtsp://{user}:{pass}@{ip}:554/h264Preview_01_sub'),
  new RtspTemplate('通用 ONVIF 杂牌',
    'rtsp://{user}:{pass}@{ip}:554/stream1',
    'rtsp://{user}:{pass}@{ip}:554/stream2')
];

/** 连接测试结果 */
export class TestResult {
  ok: boolean = false;
  /** TCP 建连耗时（毫秒），失败为 -1 */
  connectMs: number = -1;
  /** HTTP 状态码（仅 http 目标），无则 0 */
  httpCode: number = 0;
  detail: string = '';
}

/** 全屏页路由参数 */
export class ChPageParams {
  channel: Channel = new Channel();
}
