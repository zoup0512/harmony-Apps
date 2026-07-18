import preferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';
import media from '@ohos.multimedia.media';

// ─── 主题数据（PNG 切图，来自 _ref/old/memory-game） ─────────────────────────
export interface MPTheme {
  id: number;
  name: string;
  bgColor: string;
  cover: Resource;
  bgImage: Resource;
  cardBack: Resource;
  images: Resource[];
  imageCount: number;
}

// ── Animals (28) ─────────────────────────────────────────────────────────────
const ANIMALS_IMG: Resource[] = [
  $r('app.media.animals_1'),  $r('app.media.animals_2'),  $r('app.media.animals_3'),  $r('app.media.animals_4'),
  $r('app.media.animals_5'),  $r('app.media.animals_6'),  $r('app.media.animals_7'),  $r('app.media.animals_8'),
  $r('app.media.animals_9'),  $r('app.media.animals_10'), $r('app.media.animals_11'), $r('app.media.animals_12'),
  $r('app.media.animals_13'), $r('app.media.animals_14'), $r('app.media.animals_15'), $r('app.media.animals_16'),
  $r('app.media.animals_17'), $r('app.media.animals_18'), $r('app.media.animals_19'), $r('app.media.animals_20'),
  $r('app.media.animals_21'), $r('app.media.animals_22'), $r('app.media.animals_23'), $r('app.media.animals_24'),
  $r('app.media.animals_25'), $r('app.media.animals_26'), $r('app.media.animals_27'), $r('app.media.animals_28'),
];

// ── Monsters (40) — 注意原工程拼写为 "mosters" ───────────────────────────────
const MONSTERS_IMG: Resource[] = [
  $r('app.media.mosters_1'),  $r('app.media.mosters_2'),  $r('app.media.mosters_3'),  $r('app.media.mosters_4'),
  $r('app.media.mosters_5'),  $r('app.media.mosters_6'),  $r('app.media.mosters_7'),  $r('app.media.mosters_8'),
  $r('app.media.mosters_9'),  $r('app.media.mosters_10'), $r('app.media.mosters_11'), $r('app.media.mosters_12'),
  $r('app.media.mosters_13'), $r('app.media.mosters_14'), $r('app.media.mosters_15'), $r('app.media.mosters_16'),
  $r('app.media.mosters_17'), $r('app.media.mosters_18'), $r('app.media.mosters_19'), $r('app.media.mosters_20'),
  $r('app.media.mosters_21'), $r('app.media.mosters_22'), $r('app.media.mosters_23'), $r('app.media.mosters_24'),
  $r('app.media.mosters_25'), $r('app.media.mosters_26'), $r('app.media.mosters_27'), $r('app.media.mosters_28'),
  $r('app.media.mosters_29'), $r('app.media.mosters_30'), $r('app.media.mosters_31'), $r('app.media.mosters_32'),
  $r('app.media.mosters_33'), $r('app.media.mosters_34'), $r('app.media.mosters_35'), $r('app.media.mosters_36'),
  $r('app.media.mosters_37'), $r('app.media.mosters_38'), $r('app.media.mosters_39'), $r('app.media.mosters_40'),
];

// ── Emoji (40，可用 48 中前 40) ──────────────────────────────────────────────
const EMOJI_IMG: Resource[] = [
  $r('app.media.emoji_1'),  $r('app.media.emoji_2'),  $r('app.media.emoji_3'),  $r('app.media.emoji_4'),
  $r('app.media.emoji_5'),  $r('app.media.emoji_6'),  $r('app.media.emoji_7'),  $r('app.media.emoji_8'),
  $r('app.media.emoji_9'),  $r('app.media.emoji_10'), $r('app.media.emoji_11'), $r('app.media.emoji_12'),
  $r('app.media.emoji_13'), $r('app.media.emoji_14'), $r('app.media.emoji_15'), $r('app.media.emoji_16'),
  $r('app.media.emoji_17'), $r('app.media.emoji_18'), $r('app.media.emoji_19'), $r('app.media.emoji_20'),
  $r('app.media.emoji_21'), $r('app.media.emoji_22'), $r('app.media.emoji_23'), $r('app.media.emoji_24'),
  $r('app.media.emoji_25'), $r('app.media.emoji_26'), $r('app.media.emoji_27'), $r('app.media.emoji_28'),
  $r('app.media.emoji_29'), $r('app.media.emoji_30'), $r('app.media.emoji_31'), $r('app.media.emoji_32'),
  $r('app.media.emoji_33'), $r('app.media.emoji_34'), $r('app.media.emoji_35'), $r('app.media.emoji_36'),
  $r('app.media.emoji_37'), $r('app.media.emoji_38'), $r('app.media.emoji_39'), $r('app.media.emoji_40'),
];

export const MP_THEMES: MPTheme[] = [
  {
    id: 1, name: '动物乐园', bgColor: '#FFE0B2',
    cover: $r('app.media.animals_1'),
    bgImage: $r('app.media.back_animals'),
    cardBack: $r('app.media.tile_back_star'),
    images: ANIMALS_IMG, imageCount: 28,
  },
  {
    id: 2, name: '怪物巢穴', bgColor: '#D1C4E9',
    cover: $r('app.media.mosters_1'),
    bgImage: $r('app.media.back_horror'),
    cardBack: $r('app.media.tile_back_star'),
    images: MONSTERS_IMG, imageCount: 40,
  },
  {
    id: 3, name: '表情大全', bgColor: '#FFF9C4',
    cover: $r('app.media.emoji_1'),
    bgImage: $r('app.media.background'),
    cardBack: $r('app.media.tile_back_star'),
    images: EMOJI_IMG, imageCount: 40,
  },
];

export function getThemeById(id: number): MPTheme {
  for (const t of MP_THEMES) if (t.id === id) return t;
  return MP_THEMES[0];
}

// ─── 难度配置 ─────────────────────────────────────────────────────────────────
export interface MPDifficulty {
  level: number;
  numTiles: number;
  cols: number;
  rows: number;
  timeSec: number;
}

export const MP_DIFFICULTIES: MPDifficulty[] = [
  { level: 1, numTiles: 6,  cols: 3,  rows: 2, timeSec: 60  },
  { level: 2, numTiles: 12, cols: 4,  rows: 3, timeSec: 90  },
  { level: 3, numTiles: 18, cols: 6,  rows: 3, timeSec: 120 },
  { level: 4, numTiles: 28, cols: 7,  rows: 4, timeSec: 150 },
  { level: 5, numTiles: 32, cols: 8,  rows: 4, timeSec: 180 },
  { level: 6, numTiles: 50, cols: 10, rows: 5, timeSec: 210 },
];

export function getDifficulty(level: number): MPDifficulty {
  for (const d of MP_DIFFICULTIES) if (d.level === level) return d;
  return MP_DIFFICULTIES[0];
}

// ─── 星级与得分 ───────────────────────────────────────────────────────────────
export function calcStars(passedSec: number, totalSec: number): number {
  if (passedSec >= totalSec) return 0;
  if (passedSec <= totalSec / 2) return 3;
  if (passedSec <= totalSec * 4 / 5) return 2;
  return 1;
}

export function calcScore(difficulty: number, remainedSec: number, themeId: number): number {
  return Math.max(0, difficulty * remainedSec * themeId);
}

// ─── 持久化 ───────────────────────────────────────────────────────────────────
const PREF_NAME = 'match_pairs_v1';
let prefInst: preferences.Preferences | null = null;

async function getPref(ctx: common.Context): Promise<preferences.Preferences> {
  if (prefInst === null) prefInst = await preferences.getPreferences(ctx, PREF_NAME);
  return prefInst;
}

export interface MPBest { stars: number; timeSec: number; }

export async function loadBest(ctx: common.Context, themeId: number, level: number): Promise<MPBest> {
  try {
    const p = await getPref(ctx);
    const stars = await p.get(`s_${themeId}_${level}`, 0) as number;
    const timeSec = await p.get(`t_${themeId}_${level}`, 0) as number;
    return { stars, timeSec };
  } catch (_e) {
    return { stars: 0, timeSec: 0 };
  }
}

export async function saveBest(ctx: common.Context, themeId: number, level: number,
                               stars: number, timeSec: number): Promise<void> {
  try {
    const p = await getPref(ctx);
    const oldStars = await p.get(`s_${themeId}_${level}`, 0) as number;
    const oldTime = await p.get(`t_${themeId}_${level}`, 0) as number;
    if (stars > oldStars) await p.put(`s_${themeId}_${level}`, stars);
    if (oldTime === 0 || (timeSec > 0 && timeSec < oldTime)) {
      await p.put(`t_${themeId}_${level}`, timeSec);
    }
    await p.flush();
  } catch (_e) { /* ignore */ }
}

// ─── 设置（音乐/音效开关） ───────────────────────────────────────────────────
export class MPSettings {
  private static _music: boolean = true;
  private static _sfx: boolean = true;
  private static _loaded: boolean = false;

  static async load(ctx: common.Context): Promise<void> {
    if (MPSettings._loaded) return;
    try {
      const p = await getPref(ctx);
      MPSettings._music = await p.get('music_on', true) as boolean;
      MPSettings._sfx = await p.get('sfx_on', true) as boolean;
    } catch (_e) { /* keep defaults */ }
    MPSettings._loaded = true;
  }

  static music(): boolean { return MPSettings._music; }
  static sfx(): boolean { return MPSettings._sfx; }

  static async setMusic(ctx: common.Context, on: boolean): Promise<void> {
    MPSettings._music = on;
    try { const p = await getPref(ctx); await p.put('music_on', on); await p.flush(); } catch (_e) {}
  }

  static async setSfx(ctx: common.Context, on: boolean): Promise<void> {
    MPSettings._sfx = on;
    try { const p = await getPref(ctx); await p.put('sfx_on', on); await p.flush(); } catch (_e) {}
  }
}

// ─── 音频 (AVPlayer，读取 entry/src/main/resources/rawfile/*.mp3) ─────────────
let bgmPlayer: media.AVPlayer | null = null;

async function playOneShot(ctx: common.Context, rawName: string): Promise<void> {
  let player: media.AVPlayer | null = null;
  try {
    player = await media.createAVPlayer();
    const p = player;
    p.on('stateChange', async (state: string) => {
      try {
        if (state === 'initialized') await p.prepare();
        else if (state === 'prepared') await p.play();
        else if (state === 'completed' || state === 'error') await p.release();
      } catch (_e) {}
    });
    p.on('error', async () => { try { await p.release(); } catch (_e) {} });
    const fd = await ctx.resourceManager.getRawFd(rawName);
    p.fdSrc = { fd: fd.fd, offset: fd.offset, length: fd.length };
  } catch (_e) {
    if (player) { try { await player.release(); } catch (_e2) {} }
  }
}

async function startBgmInternal(ctx: common.Context, rawName: string): Promise<void> {
  await stopBgmInternal();
  let player: media.AVPlayer | null = null;
  try {
    player = await media.createAVPlayer();
    const p = player;
    bgmPlayer = p;
    p.loop = true;
    p.on('stateChange', async (state: string) => {
      try {
        if (state === 'initialized') await p.prepare();
        else if (state === 'prepared') await p.play();
      } catch (_e) {}
      if (state === 'error') {
        try { await p.release(); } catch (_e) {}
        if (bgmPlayer === p) bgmPlayer = null;
      }
    });
    const fd = await ctx.resourceManager.getRawFd(rawName);
    p.fdSrc = { fd: fd.fd, offset: fd.offset, length: fd.length };
  } catch (_e) {
    if (player) { try { await player.release(); } catch (_e2) {} }
    bgmPlayer = null;
  }
}

async function stopBgmInternal(): Promise<void> {
  const p = bgmPlayer;
  bgmPlayer = null;
  if (p !== null) {
    try { await p.stop(); } catch (_e) {}
    try { await p.release(); } catch (_e) {}
  }
}

export class MPMusic {
  private static ctx: common.Context | null = null;
  static init(ctx: common.Context): void { MPMusic.ctx = ctx; }

  static playCorrect(): void {
    if (!MPSettings.sfx() || MPMusic.ctx === null) return;
    playOneShot(MPMusic.ctx, 'correct_answer.mp3');
  }
  static playStar(): void {
    if (!MPSettings.sfx() || MPMusic.ctx === null) return;
    playOneShot(MPMusic.ctx, 'star.mp3');
  }
  static playWrong(): void { /* 原工程无错误音；保留方法占位 */ }

  static startBgm(): void {
    if (!MPSettings.music() || MPMusic.ctx === null) return;
    startBgmInternal(MPMusic.ctx, 'background_music.mp3');
  }
  static stopBgm(): void { stopBgmInternal(); }
}

// ─── Grid 模板辅助 ────────────────────────────────────────────────────────────
export function colsTemplate(n: number): string {
  let s = '1fr';
  for (let i = 1; i < n; i++) s = s + ' 1fr';
  return s;
}

// ─── Fisher–Yates 洗牌 ───────────────────────────────────────────────────────
export function shuffleArr<T>(a: T[]): T[] {
  const r: T[] = [...a];
  for (let i = r.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    const tmp = r[i]; r[i] = r[j]; r[j] = tmp;
  }
  return r;
}

// 获取 0..n-1 的洗牌索引数组
export function shuffleIndices(n: number): number[] {
  const a: number[] = [];
  for (let i = 0; i < n; i++) a.push(i);
  return shuffleArr(a);
}
