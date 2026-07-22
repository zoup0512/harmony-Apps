/**
 * Models.ets - 全局数据模型
 */

/** 摄像头流类型 */
export enum CameraType {
  /** MJPEG 视频流（http://.../video 或 /mjpg/video.mjpg） */
  MJPEG = 'MJPEG',
  /** 单帧 JPEG 快照地址，按间隔轮询刷新（http://.../shot.jpg） */
  JPEG_POLL = 'JPEG_POLL',
  /** RTSP / HTTP 视频流，交给系统 AVPlayer 解码 */
  RTSP_HTTP = 'RTSP_HTTP'
}

/** 摄像头连接状态 */
export enum CamState {
  IDLE = 'IDLE',
  CONNECTING = 'CONNECTING',
  LIVE = 'LIVE',
  ERROR = 'ERROR'
}

/** 摄像头设备配置 */
export class CameraDevice {
  /** 唯一 id (UUID) */
  id: string = '';
  /** 显示名，如 "门口" */
  name: string = '';
  type: CameraType = CameraType.MJPEG;
  /** 流地址 */
  url: string = '';
  /** Basic 认证（可选） */
  username: string = '';
  password: string = '';
  /** 是否启用（关闭后不在网格中拉流） */
  enabled: boolean = true;
  /** JPEG_POLL 的刷新间隔（毫秒） */
  pollIntervalMs: number = 1000;

  static fromJson(o: object): CameraDevice {
    const c = new CameraDevice();
    const r = o as Record<string, Object>;
    c.id = (r['id'] as string) ?? '';
    c.name = (r['name'] as string) ?? '';
    c.type = (r['type'] as CameraType) ?? CameraType.MJPEG;
    c.url = (r['url'] as string) ?? '';
    c.username = (r['username'] as string) ?? '';
    c.password = (r['password'] as string) ?? '';
    c.enabled = (r['enabled'] as boolean) ?? true;
    c.pollIntervalMs = (r['pollIntervalMs'] as number) ?? 1000;
    return c;
  }
}

/** 单摄像头页路由参数 */
export class CamPageParams {
  camera: CameraDevice = new CameraDevice();
}

/** 网格布局档位（每行列数） */
export const GRID_COLUMNS: number[] = [1, 2, 3];
