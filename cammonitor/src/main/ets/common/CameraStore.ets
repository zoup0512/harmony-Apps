/**
 * CameraStore.ets - 摄像头配置存储（单例）
 * 用 @ohos.data.preferences 持久化摄像头列表与网格列数。
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CameraDevice } from '../model/Models';

const TAG = 'CameraStore';
const STORE = 'cam_monitor_store';
const KEY_CAMERAS = 'cameras';
const KEY_GRID = 'gridColumns';

export class CameraStore {
  private static instance: CameraStore | null = null;

  static getInstance(): CameraStore {
    if (CameraStore.instance === null) {
      CameraStore.instance = new CameraStore();
    }
    return CameraStore.instance;
  }

  private store: preferences.Preferences | null = null;
  private cameras: CameraDevice[] = [];
  private gridColumns: number = 2;

  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.store !== null) {
      return;
    }
    this.store = await preferences.getPreferences(context, STORE);
    const json = await this.store.get(KEY_CAMERAS, '[]') as string;
    this.gridColumns = await this.store.get(KEY_GRID, 2) as number;
    try {
      const arr = JSON.parse(json) as object[];
      this.cameras = arr.map((o: object) => CameraDevice.fromJson(o));
    } catch (e) {
      this.cameras = [];
    }
    hilog.info(0x0001, TAG, 'loaded %{public}d cameras', this.cameras.length);
  }

  getCameras(): CameraDevice[] {
    return this.cameras.slice();
  }

  getGridColumns(): number {
    return this.gridColumns;
  }

  async setGridColumns(cols: number): Promise<void> {
    this.gridColumns = cols;
    if (this.store) {
      await this.store.put(KEY_GRID, cols);
      await this.store.flush();
    }
  }

  async upsert(cam: CameraDevice): Promise<void> {
    const idx = this.cameras.findIndex((c: CameraDevice) => c.id === cam.id);
    if (idx >= 0) {
      this.cameras[idx] = cam;
    } else {
      this.cameras.push(cam);
    }
    await this.persist();
  }

  async remove(id: string): Promise<void> {
    this.cameras = this.cameras.filter((c: CameraDevice) => c.id !== id);
    await this.persist();
  }

  private async persist(): Promise<void> {
    if (!this.store) {
      return;
    }
    await this.store.put(KEY_CAMERAS, JSON.stringify(this.cameras));
    await this.store.flush();
  }
}
