/**
 * ChannelStore.ets - 通道配置存储（单例）
 * preferences 持久化：通道列表、视频墙格数、RTSP 硬解并发上限。
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Channel, DEFAULT_VIDEO_DECODE_CAP } from '../model/Models';

const TAG = 'ChannelStore';
const STORE = 'streamshow_store';
const KEY_CHANNELS = 'channels';
const KEY_CELLS = 'wallCells';
const KEY_CAP = 'videoDecodeCap';

export class ChannelStore {
  private static instance: ChannelStore | null = null;

  static getInstance(): ChannelStore {
    if (ChannelStore.instance === null) {
      ChannelStore.instance = new ChannelStore();
    }
    return ChannelStore.instance;
  }

  private store: preferences.Preferences | null = null;
  private channels: Channel[] = [];
  private wallCells: number = 4;
  private videoCap: number = DEFAULT_VIDEO_DECODE_CAP;

  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.store !== null) {
      return;
    }
    this.store = await preferences.getPreferences(context, STORE);
    const json = await this.store.get(KEY_CHANNELS, '[]') as string;
    this.wallCells = await this.store.get(KEY_CELLS, 4) as number;
    this.videoCap = await this.store.get(KEY_CAP, DEFAULT_VIDEO_DECODE_CAP) as number;
    try {
      const arr = JSON.parse(json) as object[];
      this.channels = arr.map((o: object) => Channel.fromJson(o));
    } catch (e) {
      this.channels = [];
    }
    hilog.info(0x0001, TAG, 'loaded %{public}d channels', this.channels.length);
  }

  getChannels(): Channel[] {
    return this.channels.slice();
  }

  getWallCells(): number {
    return this.wallCells;
  }

  getVideoCap(): number {
    return this.videoCap;
  }

  async setWallCells(cells: number): Promise<void> {
    this.wallCells = cells;
    await this.putFlush(KEY_CELLS, cells);
  }

  async setVideoCap(cap: number): Promise<void> {
    this.videoCap = cap;
    await this.putFlush(KEY_CAP, cap);
  }

  async upsert(ch: Channel): Promise<void> {
    const idx = this.channels.findIndex((c: Channel) => c.id === ch.id);
    if (idx >= 0) {
      this.channels[idx] = ch;
    } else {
      this.channels.push(ch);
    }
    await this.putFlush(KEY_CHANNELS, JSON.stringify(this.channels));
  }

  async remove(id: string): Promise<void> {
    this.channels = this.channels.filter((c: Channel) => c.id !== id);
    await this.putFlush(KEY_CHANNELS, JSON.stringify(this.channels));
  }

  private async putFlush(key: string, value: preferences.ValueType): Promise<void> {
    if (!this.store) {
      return;
    }
    await this.store.put(key, value);
    await this.store.flush();
  }
}
