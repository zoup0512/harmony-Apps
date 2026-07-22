import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const PREFS_NAME = 'com.razor.cams_preferences';

export class PrefStore {
  private prefs: preferences.Preferences | null = null;
  private context: common.Context;

  constructor(context: common.Context) {
    this.context = context;
  }

  async init(): Promise<void> {
    const options: preferences.Options = {
      name: PREFS_NAME,
    };
    try {
      this.prefs = await preferences.getPreferences(this.context, options);
    } catch (e) {
      console.error(`PrefStore init failed: ${(e as Error).message}`);
    }
  }

  async getString(key: string, defaultValue: string = ''): Promise<string> {
    if (!this.prefs) await this.init();
    if (!this.prefs) return defaultValue;
    try {
      const val = await this.prefs.get(key, defaultValue);
      return val as string;
    } catch (e) {
      console.error(`PrefStore getString failed: ${(e as Error).message}`);
      return defaultValue;
    }
  }

  async getBoolean(key: string, defaultValue: boolean = false): Promise<boolean> {
    if (!this.prefs) await this.init();
    if (!this.prefs) return defaultValue;
    try {
      const val = await this.prefs.get(key, defaultValue);
      return val as boolean;
    } catch (e) {
      console.error(`PrefStore getBoolean failed: ${(e as Error).message}`);
      return defaultValue;
    }
  }

  async getNumber(key: string, defaultValue: number = 0): Promise<number> {
    if (!this.prefs) await this.init();
    if (!this.prefs) return defaultValue;
    try {
      const val = await this.prefs.get(key, defaultValue);
      return val as number;
    } catch (e) {
      console.error(`PrefStore getNumber failed: ${(e as Error).message}`);
      return defaultValue;
    }
  }

  async putString(key: string, value: string): Promise<void> {
    if (!this.prefs) await this.init();
    if (!this.prefs) return;
    try {
      await this.prefs.put(key, value);
      await this.prefs.flush();
    } catch (e) {
      console.error(`PrefStore putString failed: ${(e as Error).message}`);
    }
  }

  async putBoolean(key: string, value: boolean): Promise<void> {
    if (!this.prefs) await this.init();
    if (!this.prefs) return;
    try {
      await this.prefs.put(key, value);
      await this.prefs.flush();
    } catch (e) {
      console.error(`PrefStore putBoolean failed: ${(e as Error).message}`);
    }
  }

  async putNumber(key: string, value: number): Promise<void> {
    if (!this.prefs) await this.init();
    if (!this.prefs) return;
    try {
      await this.prefs.put(key, value);
      await this.prefs.flush();
    } catch (e) {
      console.error(`PrefStore putNumber failed: ${(e as Error).message}`);
    }
  }

  async remove(key: string): Promise<void> {
    if (!this.prefs) await this.init();
    if (!this.prefs) return;
    try {
      await this.prefs.delete(key);
      await this.prefs.flush();
    } catch (e) {
      console.error(`PrefStore remove failed: ${(e as Error).message}`);
    }
  }
}
