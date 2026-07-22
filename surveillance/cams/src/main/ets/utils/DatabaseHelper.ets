import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { CameraDevice, createCameraDevice } from '../model/CameraDevice';

const TABLE_CAMERAS = 'cameras';
const DATABASE_NAME = 'NVRDatabase.db';
const DATABASE_VERSION = 3;

export class DatabaseHelper {
  private rdbStore: relationalStore.RdbStore | null = null;
  private context: common.Context;

  constructor(context: common.Context) {
    this.context = context;
  }

  async init(): Promise<void> {
    const config: relationalStore.StoreConfig = {
      name: DATABASE_NAME,
      securityLevel: relationalStore.SecurityLevel.S1,
    };
    try {
      this.rdbStore = await relationalStore.getRdbStore(this.context, config);
      if (this.rdbStore.version === 0) {
        await this.onCreate(this.rdbStore);
        this.rdbStore.version = DATABASE_VERSION;
      }
    } catch (e) {
      console.error(`DatabaseHelper init failed: ${(e as Error).message}`);
    }
  }

  private async onCreate(db: relationalStore.RdbStore): Promise<void> {
    const sql = `CREATE TABLE IF NOT EXISTS ${TABLE_CAMERAS} (
      id TEXT PRIMARY KEY,
      name TEXT,
      rtsp_url TEXT,
      camera_group TEXT DEFAULT '',
      sort_order INTEGER DEFAULT 0
    )`;
    try {
      await db.executeSql(sql);
    } catch (e) {
      console.error(`DatabaseHelper onCreate failed: ${(e as Error).message}`);
    }
  }

  async addCamera(camera: CameraDevice): Promise<boolean> {
    if (!this.rdbStore) await this.init();
    if (!this.rdbStore) return false;
    try {
      const values: relationalStore.ValuesBucket = {
        'id': camera.id,
        'name': camera.name,
        'rtsp_url': camera.rtspUrl,
        'camera_group': camera.group ?? '',
        'sort_order': camera.sortOrder ?? 0,
      };
      await this.rdbStore.insert(TABLE_CAMERAS, values);
      return true;
    } catch (e) {
      console.error(`DatabaseHelper addCamera failed: ${(e as Error).message}`);
      return false;
    }
  }

  async getCamera(id: string): Promise<CameraDevice | null> {
    if (!this.rdbStore) await this.init();
    if (!this.rdbStore) return null;
    try {
      const predicates = new relationalStore.RdbPredicates(TABLE_CAMERAS);
      predicates.equalTo('id', id);
      const result = await this.rdbStore.query(predicates, ['id', 'name', 'rtsp_url', 'camera_group', 'sort_order']);
      if (result.goToFirstRow()) {
        const camera = createCameraDevice(
          result.getString(result.getColumnIndex('id')),
          result.getString(result.getColumnIndex('name')),
          result.getString(result.getColumnIndex('rtsp_url')),
          false,
          false,
          result.getString(result.getColumnIndex('camera_group')),
          result.getLong(result.getColumnIndex('sort_order')),
        );
        result.close();
        return camera;
      }
      result.close();
      return null;
    } catch (e) {
      console.error(`DatabaseHelper getCamera failed: ${(e as Error).message}`);
      return null;
    }
  }

  async getAllCameras(): Promise<CameraDevice[]> {
    if (!this.rdbStore) await this.init();
    if (!this.rdbStore) return [];
    try {
      const predicates = new relationalStore.RdbPredicates(TABLE_CAMERAS);
      predicates.orderByAsc('sort_order');
      const result = await this.rdbStore.query(predicates, ['id', 'name', 'rtsp_url', 'camera_group', 'sort_order']);
      const cameras: CameraDevice[] = [];
      while (result.goToNextRow()) {
        cameras.push(createCameraDevice(
          result.getString(result.getColumnIndex('id')),
          result.getString(result.getColumnIndex('name')),
          result.getString(result.getColumnIndex('rtsp_url')),
          false,
          false,
          result.getString(result.getColumnIndex('camera_group')),
          result.getLong(result.getColumnIndex('sort_order')),
        ));
      }
      result.close();
      return cameras;
    } catch (e) {
      console.error(`DatabaseHelper getAllCameras failed: ${(e as Error).message}`);
      return [];
    }
  }

  async updateCamera(camera: CameraDevice): Promise<number> {
    if (!this.rdbStore) await this.init();
    if (!this.rdbStore) return 0;
    try {
      const values: relationalStore.ValuesBucket = {
        'name': camera.name,
        'rtsp_url': camera.rtspUrl,
        'camera_group': camera.group ?? '',
        'sort_order': camera.sortOrder ?? 0,
      };
      const predicates = new relationalStore.RdbPredicates(TABLE_CAMERAS);
      predicates.equalTo('id', camera.id);
      return await this.rdbStore.update(values, predicates);
    } catch (e) {
      console.error(`DatabaseHelper updateCamera failed: ${(e as Error).message}`);
      return 0;
    }
  }

  async deleteCamera(id: string): Promise<boolean> {
    if (!this.rdbStore) await this.init();
    if (!this.rdbStore) return false;
    try {
      const predicates = new relationalStore.RdbPredicates(TABLE_CAMERAS);
      predicates.equalTo('id', id);
      const rows = await this.rdbStore.delete(predicates);
      return rows > 0;
    } catch (e) {
      console.error(`DatabaseHelper deleteCamera failed: ${(e as Error).message}`);
      return false;
    }
  }

  async getCamerasCount(): Promise<number> {
    if (!this.rdbStore) await this.init();
    if (!this.rdbStore) return 0;
    try {
      const predicates = new relationalStore.RdbPredicates(TABLE_CAMERAS);
      const result = await this.rdbStore.query(predicates, ['id']);
      const count = result.rowCount;
      result.close();
      return count;
    } catch (e) {
      return 0;
    }
  }
}
