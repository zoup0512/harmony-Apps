/**
 * CastManager.ets - 投屏会话管理（单例）
 *
 * 组合 SsdpDiscovery 与 DlnaController，向 UI 提供：
 * 设备发现、投屏、播放控制、进度轮询。
 */
import { CastDevice, CastSession, MediaItem, PlayState } from '../model/Models';
import { SsdpDiscovery, SsdpResult } from '../dlna/SsdpDiscovery';
import { DlnaController } from '../dlna/DlnaController';

export type DeviceListListener = (devices: CastDevice[]) => void;
export type SessionListener = (session: CastSession) => void;

export class CastManager {
  private static instance: CastManager | null = null;

  static getInstance(): CastManager {
    if (CastManager.instance === null) {
      CastManager.instance = new CastManager();
    }
    return CastManager.instance;
  }

  private discovery: SsdpDiscovery = new SsdpDiscovery();
  private devices: CastDevice[] = [];
  private session: CastSession = new CastSession();
  private deviceListener: DeviceListListener | null = null;
  private sessionListener: SessionListener | null = null;
  private pollTimer: number = -1;

  private constructor() {
    this.discovery.onDeviceFound((r: SsdpResult) => {
      this.handleSsdpResult(r);
    });
  }

  onDevicesChanged(l: DeviceListListener): void {
    this.deviceListener = l;
  }

  onSessionChanged(l: SessionListener): void {
    this.sessionListener = l;
  }

  getDevices(): CastDevice[] {
    return this.devices;
  }

  getSession(): CastSession {
    return this.session;
  }

  /** 启动一轮设备搜索（不清空已发现设备，按 UDN 去重） */
  startDiscovery(): void {
    this.discovery.search(6000);
  }

  private async handleSsdpResult(r: SsdpResult): Promise<void> {
    const dev = await DlnaController.describeDevice(r.location);
    if (dev === null) {
      return;
    }
    const exists = this.devices.some((d: CastDevice) => d.udn === dev.udn);
    if (!exists) {
      this.devices.push(dev);
      if (this.deviceListener) {
        this.deviceListener(this.devices.slice());
      }
    }
  }

  /** 将媒体投送到设备 */
  async castTo(device: CastDevice, media: MediaItem): Promise<boolean> {
    this.session.device = device;
    this.session.media = media;
    this.session.state = PlayState.TRANSITIONING;
    this.notifySession();

    const ok = await DlnaController.cast(device, media);
    this.session.state = ok ? PlayState.PLAYING : PlayState.ERROR;
    this.notifySession();
    if (ok) {
      this.startPolling();
    }
    return ok;
  }

  async play(): Promise<void> {
    if (this.session.device === null) {
      return;
    }
    if (await DlnaController.play(this.session.device)) {
      this.session.state = PlayState.PLAYING;
      this.notifySession();
    }
  }

  async pause(): Promise<void> {
    if (this.session.device === null) {
      return;
    }
    if (await DlnaController.pause(this.session.device)) {
      this.session.state = PlayState.PAUSED;
      this.notifySession();
    }
  }

  async stop(): Promise<void> {
    if (this.session.device === null) {
      return;
    }
    await DlnaController.stop(this.session.device);
    this.session.state = PlayState.STOPPED;
    this.stopPolling();
    this.notifySession();
  }

  async seekTo(sec: number): Promise<void> {
    if (this.session.device === null) {
      return;
    }
    await DlnaController.seek(this.session.device, CastManager.secToHms(sec));
  }

  async setVolume(v: number): Promise<void> {
    if (this.session.device !== null) {
      await DlnaController.setVolume(this.session.device, v);
    }
  }

  private startPolling(): void {
    this.stopPolling();
    this.pollTimer = setInterval(() => {
      this.pollPosition();
    }, 1000);
  }

  private stopPolling(): void {
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  private async pollPosition(): Promise<void> {
    if (this.session.device === null || this.session.state !== PlayState.PLAYING) {
      return;
    }
    const pos = await DlnaController.getPosition(this.session.device);
    if (pos[0] >= 0) {
      this.session.positionSec = pos[0];
      this.session.durationSec = pos[1];
      this.notifySession();
    }
  }

  private notifySession(): void {
    if (this.sessionListener) {
      this.sessionListener(this.session);
    }
  }

  static secToHms(sec: number): string {
    const s = Math.max(0, Math.floor(sec));
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    const ss = s % 60;
    const pad = (n: number): string => n < 10 ? '0' + n.toString() : n.toString();
    return `${pad(h)}:${pad(m)}:${pad(ss)}`;
  }
}
