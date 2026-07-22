/**
 * StatsStore.ets — 玩家战绩本地持久化（@ohos.data.preferences）
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

/** 累计战绩 */
export class Stats {
  played: number = 0;   // 总对局数
  wins: number = 0;     // 胜利局数
  best: number = 0;     // 最少猜中次数（0 表示暂无）
  streak: number = 0;   // 当前连胜
}

const PREF_NAME: string = 'guess_stats';
const KEY_PLAYED: string = 'played';
const KEY_WINS: string = 'wins';
const KEY_BEST: string = 'best';
const KEY_STREAK: string = 'streak';
const KEY_TUTORIAL: string = 'tutorial_done';

export class StatsStore {
  private static async pref(ctx: common.Context): Promise<preferences.Preferences> {
    return await preferences.getPreferences(ctx, PREF_NAME);
  }

  /** 读取战绩 */
  static async load(ctx: common.Context): Promise<Stats> {
    const p = await StatsStore.pref(ctx);
    const s = new Stats();
    s.played = await p.get(KEY_PLAYED, 0) as number;
    s.wins = await p.get(KEY_WINS, 0) as number;
    s.best = await p.get(KEY_BEST, 0) as number;
    s.streak = await p.get(KEY_STREAK, 0) as number;
    return s;
  }

  /** 记录一局结果并落盘，返回最新战绩 */
  static async recordResult(ctx: common.Context, win: boolean, attempts: number): Promise<Stats> {
    const s = await StatsStore.load(ctx);
    s.played++;
    if (win) {
      s.wins++;
      s.streak++;
      if (s.best === 0 || attempts < s.best) {
        s.best = attempts;
      }
    } else {
      s.streak = 0;
    }
    const p = await StatsStore.pref(ctx);
    await p.put(KEY_PLAYED, s.played);
    await p.put(KEY_WINS, s.wins);
    await p.put(KEY_BEST, s.best);
    await p.put(KEY_STREAK, s.streak);
    await p.flush();
    return s;
  }

  /** 新手引导是否已完成（含跳过） */
  static async isTutorialDone(ctx: common.Context): Promise<boolean> {
    const p = await StatsStore.pref(ctx);
    return await p.get(KEY_TUTORIAL, false) as boolean;
  }

  /** 标记新手引导已完成 */
  static async setTutorialDone(ctx: common.Context): Promise<void> {
    const p = await StatsStore.pref(ctx);
    await p.put(KEY_TUTORIAL, true);
    await p.flush();
  }
}
