/**
 * MjpegStreamer.ets - MJPEG 推流器
 *
 * 维护一组"正在观看 /video 的 TCP 连接"，用一个按帧率触发的定时器，
 * 从 CameraService 取最新 JPEG，封装为 multipart/x-mixed-replace 帧
 * 依次写入每个连接。任一连接写失败即从集合移除。
 */
import { socket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CameraService } from '../camera/CameraService';
import { StreamConfig } from '../model/Models';

const TAG = 'MjpegStreamer';
const BOUNDARY = 'ipwcframe';

export type StatsListener = (viewers: number, framesSent: number, fps: number) => void;

export class MjpegStreamer {
  private clients: Set<socket.TCPSocketConnection> = new Set<socket.TCPSocketConnection>();
  private camera: CameraService;
  private config: StreamConfig;
  private timer: number = -1;
  private framesSent: number = 0;
  private fpsWindowStart: number = 0;
  private fpsWindowCount: number = 0;
  private actualFps: number = 0;
  private statsListener: StatsListener | null = null;
  private sending: boolean = false;

  constructor(camera: CameraService, config: StreamConfig) {
    this.camera = camera;
    this.config = config;
  }

  onStats(l: StatsListener): void {
    this.statsListener = l;
  }

  /** 一个新的 /video 请求到来：先回复 multipart 响应头，再加入推送集合 */
  async addClient(conn: socket.TCPSocketConnection): Promise<void> {
    const header =
      'HTTP/1.1 200 OK\r\n' +
      'Connection: close\r\n' +
      'Cache-Control: no-cache, private\r\n' +
      'Pragma: no-cache\r\n' +
      `Content-Type: multipart/x-mixed-replace; boundary=${BOUNDARY}\r\n\r\n`;
    try {
      await conn.send({ data: header });
      this.clients.add(conn);
      conn.on('close', () => {
        this.clients.delete(conn);
        this.notifyStats();
      });
      this.notifyStats();
      this.ensureTimer();
    } catch (e) {
      hilog.warn(0x0001, TAG, 'addClient send header failed');
    }
  }

  private ensureTimer(): void {
    if (this.timer >= 0) {
      return;
    }
    const interval = Math.max(33, Math.floor(1000 / Math.max(1, this.config.fps)));
    this.fpsWindowStart = Date.now();
    this.fpsWindowCount = 0;
    this.timer = setInterval(() => {
      this.tick();
    }, interval);
  }

  private stopTimerIfIdle(): void {
    if (this.clients.size === 0 && this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private async tick(): Promise<void> {
    if (this.sending) {
      return; // 上一帧还没发完，丢帧防积压
    }
    if (this.clients.size === 0) {
      this.stopTimerIfIdle();
      return;
    }
    this.sending = true;
    try {
      const jpeg = await this.camera.getLatestJpeg();
      if (jpeg !== null && jpeg.byteLength > 0) {
        await this.broadcast(jpeg);
        this.tallyFps();
      }
    } finally {
      this.sending = false;
    }
  }

  private async broadcast(jpeg: ArrayBuffer): Promise<void> {
    const partHeader =
      `--${BOUNDARY}\r\n` +
      'Content-Type: image/jpeg\r\n' +
      `Content-Length: ${jpeg.byteLength}\r\n\r\n`;
    const tail = '\r\n';
    const dead: socket.TCPSocketConnection[] = [];
    for (const conn of this.clients) {
      try {
        await conn.send({ data: partHeader });
        await conn.send({ data: jpeg });
        await conn.send({ data: tail });
      } catch (e) {
        dead.push(conn);
      }
    }
    for (const d of dead) {
      this.clients.delete(d);
      try {
        d.close();
      } catch (e) {
        // ignore
      }
    }
    if (dead.length > 0) {
      this.notifyStats();
    }
    this.framesSent++;
  }

  /** 返回单帧 JPEG（供 /shot.jpg），失败返回 null */
  async snapshot(): Promise<ArrayBuffer | null> {
    return this.camera.getLatestJpeg();
  }

  viewerCount(): number {
    return this.clients.size;
  }

  getFramesSent(): number {
    return this.framesSent;
  }

  getFps(): number {
    return this.actualFps;
  }

  stop(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
    for (const conn of this.clients) {
      try {
        conn.close();
      } catch (e) {
        // ignore
      }
    }
    this.clients.clear();
    this.notifyStats();
  }

  private tallyFps(): void {
    this.fpsWindowCount++;
    const now = Date.now();
    const elapsed = now - this.fpsWindowStart;
    if (elapsed >= 1000) {
      this.actualFps = Math.round((this.fpsWindowCount * 1000) / elapsed);
      this.fpsWindowStart = now;
      this.fpsWindowCount = 0;
      this.notifyStats();
    }
  }

  private notifyStats(): void {
    if (this.statsListener) {
      this.statsListener(this.clients.size, this.framesSent, this.actualFps);
    }
  }
}
