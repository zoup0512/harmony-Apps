/**
 * Theme.ets — 全局视觉常量
 * 深夜靛蓝底 + 暖金 / 湖绿 / 星蓝三色点缀的"解密终端"风格
 */
export class Theme {
  // 背景渐变（自上而下）
  static readonly BG_TOP: string = '#10142E';
  static readonly BG_BOTTOM: string = '#241242';

  // 卡片与描边
  static readonly CARD: string = 'rgba(255,255,255,0.07)';
  static readonly CARD_STRONG: string = 'rgba(255,255,255,0.12)';
  static readonly STROKE: string = 'rgba(255,255,255,0.14)';

  // 文本
  static readonly TEXT: string = '#F4F2FF';
  static readonly TEXT_SUB: string = 'rgba(244,242,255,0.55)';
  static readonly TEXT_FAINT: string = 'rgba(244,242,255,0.35)';

  // 强调色
  static readonly GOLD: string = '#F5B441';   // 主行动色
  static readonly GOLD_DEEP: string = '#E08A2E';
  static readonly GREEN: string = '#3FCF8E';  // A（数字对、位置对）
  static readonly BLUE: string = '#5B9DF5';   // B（数字对、位置错）
  static readonly RED: string = '#F0616D';    // 失败 / 删除

  // 圆角
  static readonly R_CARD: number = 20;
  static readonly R_TILE: number = 12;
  static readonly R_KEY: number = 16;
}
