/**
 * CameraStore.ets - 相机配置存储（单例）
 * preferences 持久化：相机列表、四分屏硬解上限、轮巡间隔。
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Camera, DEFAULT_VIDEO_DECODE_CAP, DEFAULT_SEQUENCE_SEC } from '../model/Models';

const TAG = 'CameraStore';
const STORE = 'cameraviewer_store';
const KEY_CAMERAS = 'cameras';
const KEY_CAP = 'videoDecodeCap';
const KEY_SEQ = 'sequenceSec';

export class CameraStore {
  private static instance: CameraStore | null = null;

  static getInstance(): CameraStore {
    if (CameraStore.instance === null) {
      CameraStore.instance = new CameraStore();
    }
    return CameraStore.instance;
  }

  private store: preferences.Preferences | null = null;
  private cameras: Camera[] = [];
  private videoCap: number = DEFAULT_VIDEO_DECODE_CAP;
  private sequenceSec: number = DEFAULT_SEQUENCE_SEC;

  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.store !== null) {
      return;
    }
    this.store = await preferences.getPreferences(context, STORE);
    const json = await this.store.get(KEY_CAMERAS, '[]') as string;
    this.videoCap = await this.store.get(KEY_CAP, DEFAULT_VIDEO_DECODE_CAP) as number;
    this.sequenceSec = await this.store.get(KEY_SEQ, DEFAULT_SEQUENCE_SEC) as number;
    try {
      const arr = JSON.parse(json) as object[];
      this.cameras = arr.map((o: object) => Camera.fromJson(o));
    } catch (e) {
      this.cameras = [];
    }
    hilog.info(0x0001, TAG, 'loaded %{public}d cameras', this.cameras.length);
  }

  getCameras(): Camera[] {
    return this.cameras.slice();
  }

  getEnabledCameras(): Camera[] {
    return this.cameras.filter((c: Camera) => c.enabled);
  }

  getVideoCap(): number {
    return this.videoCap;
  }

  getSequenceSec(): number {
    return this.sequenceSec;
  }

  async setVideoCap(cap: number): Promise<void> {
    this.videoCap = cap;
    await this.putFlush(KEY_CAP, cap);
  }

  async setSequenceSec(sec: number): Promise<void> {
    this.sequenceSec = sec;
    await this.putFlush(KEY_SEQ, sec);
  }

  async upsert(cam: Camera): Promise<void> {
    const idx = this.cameras.findIndex((c: Camera) => c.id === cam.id);
    if (idx >= 0) {
      this.cameras[idx] = cam;
    } else {
      this.cameras.push(cam);
    }
    await this.putFlush(KEY_CAMERAS, JSON.stringify(this.cameras));
  }

  async remove(id: string): Promise<void> {
    this.cameras = this.cameras.filter((c: Camera) => c.id !== id);
    await this.putFlush(KEY_CAMERAS, JSON.stringify(this.cameras));
  }

  private async putFlush(key: string, value: preferences.ValueType): Promise<void> {
    if (!this.store) {
      return;
    }
    await this.store.put(key, value);
    await this.store.flush();
  }
}
