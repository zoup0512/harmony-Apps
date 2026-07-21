/**
 * HttpServer.ets - 轻量 HTTP 服务器
 *
 * 基于 TCPSocketServer 自实现。解析请求行与 Host/Authorization 头，
 * 分发路由：
 *   GET /          → 控制/观看页 (HTML)
 *   GET /video     → MJPEG 长连接（交给 MjpegStreamer）
 *   GET /shot.jpg  → 当前单帧 JPEG
 *   GET /status    → JSON 运行状态
 * 其它路径 → 404。可选 Basic Auth。
 */
import { socket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CameraService } from '../camera/CameraService';
import { MjpegStreamer } from './MjpegStreamer';
import { WebPage } from './WebPage';
import { StreamConfig } from '../model/Models';

const TAG = 'HttpServer';

export class HttpServer {
  private server: socket.TCPSocketServer | null = null;
  private streamer: MjpegStreamer;
  private camera: CameraService;
  private config: StreamConfig;
  private deviceLabel: string = 'HarmonyOS';

  constructor(camera: CameraService, streamer: MjpegStreamer, config: StreamConfig) {
    this.camera = camera;
    this.streamer = streamer;
    this.config = config;
  }

  setDeviceLabel(label: string): void {
    this.deviceLabel = label;
  }

  async start(): Promise<boolean> {
    try {
      this.server = socket.constructTCPSocketServerInstance();
      await this.server.listen({ address: '0.0.0.0', port: this.config.port, family: 1 } as socket.NetAddress);
      this.server.on('connect', (conn: socket.TCPSocketConnection) => {
        this.handleConnection(conn);
      });
      hilog.info(0x0001, TAG, 'listening on :%{public}d', this.config.port);
      return true;
    } catch (e) {
      hilog.error(0x0001, TAG, 'listen error: %{public}s', JSON.stringify(e));
      return false;
    }
  }

  async stop(): Promise<void> {
    this.streamer.stop();
    if (this.server) {
      try {
        this.server.off('connect');
      } catch (e) {
        // ignore
      }
      this.server = null;
    }
  }

  private handleConnection(conn: socket.TCPSocketConnection): void {
    conn.on('message', async (value: socket.SocketMessageInfo) => {
      const req = HttpServer.decode(value.message);
      const reqLine = req.split('\r\n')[0] ?? '';
      const parts = reqLine.split(' ');
      const method = parts[0] ?? '';
      const path = HttpServer.pathOf(parts[1] ?? '/');

      if (method !== 'GET') {
        await HttpServer.sendText(conn, 405, 'Method Not Allowed');
        conn.close();
        return;
      }
      if (!this.checkAuth(req)) {
        await this.sendAuthRequired(conn);
        conn.close();
        return;
      }

      switch (path) {
        case '/':
          await HttpServer.sendHtml(conn, WebPage.html(this.deviceLabel));
          conn.close();
          break;
        case '/video':
          // 长连接，交给推流器，不主动 close
          await this.streamer.addClient(conn);
          break;
        case '/shot.jpg':
          await this.sendSnapshot(conn);
          conn.close();
          break;
        case '/status':
          await this.sendStatus(conn);
          conn.close();
          break;
        default:
          await HttpServer.sendText(conn, 404, 'Not Found');
          conn.close();
      }
    });
  }

  private async sendSnapshot(conn: socket.TCPSocketConnection): Promise<void> {
    const jpeg = await this.streamer.snapshot();
    if (jpeg === null) {
      await HttpServer.sendText(conn, 503, 'Camera not ready');
      return;
    }
    const header =
      'HTTP/1.1 200 OK\r\n' +
      'Content-Type: image/jpeg\r\n' +
      `Content-Length: ${jpeg.byteLength}\r\n` +
      'Cache-Control: no-cache\r\nConnection: close\r\n\r\n';
    try {
      await conn.send({ data: header });
      await conn.send({ data: jpeg });
    } catch (e) {
      hilog.warn(0x0001, TAG, 'snapshot send failed');
    }
  }

  private async sendStatus(conn: socket.TCPSocketConnection): Promise<void> {
    const body = JSON.stringify({
      state: 'running',
      viewers: this.streamer.viewerCount(),
      framesSent: this.streamer.getFramesSent(),
      fps: this.streamer.getFps(),
      resolution: this.config.resolution.label,
      quality: this.config.quality
    });
    const header =
      'HTTP/1.1 200 OK\r\n' +
      'Content-Type: application/json; charset=utf-8\r\n' +
      `Content-Length: ${HttpServer.byteLen(body)}\r\n` +
      'Connection: close\r\n\r\n';
    try {
      await conn.send({ data: header + body });
    } catch (e) {
      // ignore
    }
  }

  private checkAuth(req: string): boolean {
    if (this.config.authUser === '') {
      return true;
    }
    const expected = 'Basic ' + HttpServer.base64(`${this.config.authUser}:${this.config.authPass}`);
    const lines = req.split('\r\n');
    for (const l of lines) {
      if (l.toLowerCase().startsWith('authorization:')) {
        return l.substring(l.indexOf(':') + 1).trim() === expected;
      }
    }
    return false;
  }

  private async sendAuthRequired(conn: socket.TCPSocketConnection): Promise<void> {
    const body = 'Authentication required';
    const header =
      'HTTP/1.1 401 Unauthorized\r\n' +
      'WWW-Authenticate: Basic realm="IP Webcam"\r\n' +
      'Content-Type: text/plain\r\n' +
      `Content-Length: ${HttpServer.byteLen(body)}\r\nConnection: close\r\n\r\n`;
    try {
      await conn.send({ data: header + body });
    } catch (e) {
      // ignore
    }
  }

  // ---------------- 静态工具 ----------------

  private static async sendHtml(conn: socket.TCPSocketConnection, html: string): Promise<void> {
    const header =
      'HTTP/1.1 200 OK\r\n' +
      'Content-Type: text/html; charset=utf-8\r\n' +
      `Content-Length: ${HttpServer.byteLen(html)}\r\nConnection: close\r\n\r\n`;
    try {
      await conn.send({ data: header + html });
    } catch (e) {
      // ignore
    }
  }

  private static async sendText(conn: socket.TCPSocketConnection, code: number, text: string): Promise<void> {
    const status = code === 404 ? 'Not Found' : (code === 405 ? 'Method Not Allowed' : (code === 503 ? 'Service Unavailable' : 'OK'));
    const header =
      `HTTP/1.1 ${code} ${status}\r\n` +
      'Content-Type: text/plain; charset=utf-8\r\n' +
      `Content-Length: ${HttpServer.byteLen(text)}\r\nConnection: close\r\n\r\n`;
    try {
      await conn.send({ data: header + text });
    } catch (e) {
      // ignore
    }
  }

  private static decode(buf: ArrayBuffer): string {
    return util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buf));
  }

  private static pathOf(target: string): string {
    const q = target.indexOf('?');
    return q >= 0 ? target.substring(0, q) : target;
  }

  private static byteLen(s: string): number {
    return new util.TextEncoder().encodeInto(s).length;
  }

  private static base64(s: string): string {
    const bytes = new util.TextEncoder().encodeInto(s);
    return new util.Base64Helper().encodeToStringSync(bytes);
  }
}
