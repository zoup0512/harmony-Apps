/**
 * Models.ets - 全局数据模型
 */

/** 服务运行状态 */
export enum ServerState {
  STOPPED = 'STOPPED',
  STARTING = 'STARTING',
  RUNNING = 'RUNNING',
  ERROR = 'ERROR'
}

/** 分辨率档位 */
export class Resolution {
  width: number;
  height: number;
  label: string;

  constructor(width: number, height: number) {
    this.width = width;
    this.height = height;
    this.label = `${width}x${height}`;
  }
}

/** 推流参数配置 */
export class StreamConfig {
  /** 监听端口 */
  port: number = 8080;
  /** 目标帧率 */
  fps: number = 15;
  /** JPEG 质量 0-100 */
  quality: number = 60;
  /** 使用后置(false)还是前置(true)摄像头 */
  useFront: boolean = false;
  /** 分辨率 */
  resolution: Resolution = new Resolution(1280, 720);
  /** 是否推送音频 */
  audioEnabled: boolean = false;
  /** 基础访问鉴权：为空则不校验 */
  authUser: string = '';
  authPass: string = '';
}

/** 服务运行时统计 */
export class ServerStats {
  state: ServerState = ServerState.STOPPED;
  /** 局域网访问地址，如 http://192.168.1.8:8080 */
  accessUrl: string = '';
  /** 当前 MJPEG 观看连接数 */
  viewers: number = 0;
  /** 已推送帧数 */
  framesSent: number = 0;
  /** 实测帧率 */
  actualFps: number = 0;
}
