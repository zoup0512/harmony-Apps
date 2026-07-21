/**
 * WebcamController.ets - 顶层协调器（单例）
 * 串起 CameraService / MjpegStreamer / HttpServer，对 UI 暴露 start/stop/统计。
 */
import { common } from '@kit.AbilityKit';
import { CameraService } from '../camera/CameraService';
import { MjpegStreamer } from '../server/MjpegStreamer';
import { HttpServer } from '../server/HttpServer';
import { NetworkUtil } from './NetworkUtil';
import { ServerState, ServerStats, StreamConfig } from '../model/Models';

export type StatsUpdate = (stats: ServerStats) => void;

export class WebcamController {
  private static instance: WebcamController | null = null;

  static getInstance(): WebcamController {
    if (WebcamController.instance === null) {
      WebcamController.instance = new WebcamController();
    }
    return WebcamController.instance;
  }

  private camera: CameraService = new CameraService();
  private streamer: MjpegStreamer | null = null;
  private server: HttpServer | null = null;
  private stats: ServerStats = new ServerStats();
  private listener: StatsUpdate | null = null;

  onStats(l: StatsUpdate): void {
    this.listener = l;
  }

  getStats(): ServerStats {
    return this.stats;
  }

  getCamera(): CameraService {
    return this.camera;
  }

  /** previewSurfaceId 来自 UI 的 XComponent */
  async start(context: common.UIAbilityContext, previewSurfaceId: string, config: StreamConfig): Promise<boolean> {
    this.stats.state = ServerState.STARTING;
    this.emit();

    const ip = NetworkUtil.getLocalIp();
    if (ip === '') {
      this.stats.state = ServerState.ERROR;
      this.stats.accessUrl = '未连接 Wi-Fi';
      this.emit();
      return false;
    }

    const camOk = await this.camera.start(context, previewSurfaceId, config);
    if (!camOk) {
      this.stats.state = ServerState.ERROR;
      this.emit();
      return false;
    }

    this.streamer = new MjpegStreamer(this.camera, config);
    this.streamer.onStats((viewers: number, frames: number, fps: number) => {
      this.stats.viewers = viewers;
      this.stats.framesSent = frames;
      this.stats.actualFps = fps;
      this.emit();
    });

    this.server = new HttpServer(this.camera, this.streamer, config);
    this.server.setDeviceLabel('HarmonyOS Phone');
    const srvOk = await this.server.start();
    if (!srvOk) {
      await this.camera.stop();
      this.stats.state = ServerState.ERROR;
      this.emit();
      return false;
    }

    this.stats.state = ServerState.RUNNING;
    this.stats.accessUrl = `http://${ip}:${config.port}`;
    this.emit();
    return true;
  }

  async stop(): Promise<void> {
    if (this.server) {
      await this.server.stop();
      this.server = null;
    }
    this.streamer = null;
    await this.camera.stop();
    this.stats = new ServerStats();
    this.stats.state = ServerState.STOPPED;
    this.emit();
  }

  setTorch(on: boolean): void {
    this.camera.setTorch(on);
  }

  private emit(): void {
    if (this.listener) {
      this.listener(this.stats);
    }
  }
}
