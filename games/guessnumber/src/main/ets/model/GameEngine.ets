/**
 * GameEngine.ets — 1A2B 猜数字核心逻辑
 *
 * 与原 C 程序的对应关系：
 *   CreateNum()  -> GameEngine.generateSecret()   生成各位互不相同的随机数字
 *   JudgeA()     -> judge() 中的 a 计数            数字对且位置对
 *   JudgeB()     -> judge() 中的 b 计数            数字对但位置错
 *   JudgeInput() -> 由键盘输入规则天然保证          （重复数字直接禁用按键）
 */

/** 一条猜测记录 */
export interface GuessRecord {
  index: number;   // 第几次猜测（从 1 开始）
  guess: string;   // 猜测的数字串
  a: number;       // xA：数字对且位置对
  b: number;       // yB：数字对但位置错
}

/** 难度配置 */
export interface Difficulty {
  digits: number;      // 位数
  attempts: number;    // 允许的猜测次数
  name: string;        // 显示名
  desc: string;        // 描述
}

export const DIFFICULTIES: Difficulty[] = [
  { digits: 3, attempts: 6, name: '入门', desc: '3 位密码 · 6 次机会' },
  { digits: 4, attempts: 8, name: '经典', desc: '4 位密码 · 8 次机会' },
  { digits: 5, attempts: 10, name: '大师', desc: '5 位密码 · 10 次机会' }
];

export class GameEngine {
  secret: string = '';
  digits: number = 4;
  maxAttempts: number = 8;
  attemptsUsed: number = 0;
  hintUsed: boolean = false;

  /** 开始一局新游戏 */
  start(digits: number, attempts: number): void {
    this.digits = digits;
    this.maxAttempts = attempts;
    this.attemptsUsed = 0;
    this.hintUsed = false;
    this.secret = GameEngine.generateSecret(digits);
  }

  /** 生成各位互不相同的随机数字（Fisher–Yates 洗牌，允许首位为 0，与原版一致） */
  static generateSecret(n: number): string {
    const pool: number[] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];
    for (let i = pool.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      const t = pool[i];
      pool[i] = pool[j];
      pool[j] = t;
    }
    let s = '';
    for (let i = 0; i < n; i++) {
      s += pool[i].toString();
    }
    return s;
  }

  /** 判定一次猜测，返回记录（自动累计次数） */
  judge(guess: string): GuessRecord {
    let a = 0;
    let b = 0;
    for (let i = 0; i < guess.length; i++) {
      const pos = this.secret.indexOf(guess.charAt(i));
      if (pos === i) {
        a++;
      } else if (pos >= 0) {
        b++;
      }
    }
    this.attemptsUsed++;
    const rec: GuessRecord = { index: this.attemptsUsed, guess: guess, a: a, b: b };
    return rec;
  }

  /** 剩余次数 */
  attemptsLeft(): number {
    return this.maxAttempts - this.attemptsUsed;
  }

  /**
   * 使用一次提示：从尚未被任何历史猜测"猜对位置"的位里，随机揭示一位。
   * 代价为消耗一次猜测机会，每局限一次。
   * 返回揭示文案，如 "第 2 位是 7"；不可用时返回空串。
   */
  useHint(pastGuesses: string[]): string {
    if (this.hintUsed || this.attemptsLeft() <= 1) {
      return '';
    }
    const candidates: number[] = [];
    for (let i = 0; i < this.digits; i++) {
      let confirmed = false;
      for (let g = 0; g < pastGuesses.length; g++) {
        if (pastGuesses[g].charAt(i) === this.secret.charAt(i)) {
          confirmed = true;
          break;
        }
      }
      if (!confirmed) {
        candidates.push(i);
      }
    }
    if (candidates.length === 0) {
      return '';
    }
    const pick = candidates[Math.floor(Math.random() * candidates.length)];
    this.hintUsed = true;
    this.attemptsUsed++; // 提示消耗一次机会
    return '第 ' + (pick + 1).toString() + ' 位是 ' + this.secret.charAt(pick);
  }
}
