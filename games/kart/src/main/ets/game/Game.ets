/**
 * 3D 卡丁车 - 伪3D赛车引擎 (灵感来源于经典 J2ME 游戏 Jet Set Racing)
 * 使用分段投影法(segment projection)实现 3D 公路渲染
 */

export enum GameState {
  MENU = 0,
  COUNTDOWN = 1,
  RACING = 2,
  PAUSED = 3,
  FINISHED = 4
}

export class TrackInfo {
  name: string;
  desc: string;
  laps: number;
  aiCount: number;
  grassLight: string;
  grassDark: string;
  skyTop: string;
  skyBottom: string;
  hillColor: string;
  treeColor: string;

  constructor(name: string, desc: string, laps: number, aiCount: number,
              grassLight: string, grassDark: string,
              skyTop: string, skyBottom: string,
              hillColor: string, treeColor: string) {
    this.name = name;
    this.desc = desc;
    this.laps = laps;
    this.aiCount = aiCount;
    this.grassLight = grassLight;
    this.grassDark = grassDark;
    this.skyTop = skyTop;
    this.skyBottom = skyBottom;
    this.hillColor = hillColor;
    this.treeColor = treeColor;
  }
}

export const TRACKS: TrackInfo[] = [
  new TrackInfo('翡翠环道', '平缓弯道 · 新手友好 · 3圈', 3, 4,
    '#7ec850', '#6db544', '#3fa7ff', '#bfe8ff', '#4a8a3a', '#2d6b2d'),
  new TrackInfo('沙漠竞速', '连绵长弯 · 起伏沙丘 · 3圈', 3, 5,
    '#e8c878', '#d9b560', '#ff9a3d', '#ffe0b0', '#c49a4a', '#8a7038'),
  new TrackInfo('雪峰之巅', '急弯陡坡 · 高手挑战 · 3圈', 3, 6,
    '#e8eef5', '#d5dde8', '#5a7ba6', '#cfdcec', '#8fa5c0', '#3a5a3a')
];

class Segment {
  index: number = 0;
  curve: number = 0;
  y1: number = 0;
  y2: number = 0;
  spriteX: number = 0; // 0 表示无路边物体
  // 投影缓存
  sx1: number = 0; sy1: number = 0; sw1: number = 0;
  sx2: number = 0; sy2: number = 0; sw2: number = 0;
  scale2: number = 0;
  clipY: number = 0;
  fog: number = 0;
  drawn: boolean = false;
}

class Car {
  z: number = 0;
  offset: number = 0;
  speed: number = 0;
  color: string = '#ff3333';
  totalDist: number = 0;
}

const SEG_LEN: number = 200;
const ROAD_W: number = 1000;
const RUMBLE: number = 3;
const CAM_H: number = 1000;
const CAM_DEPTH: number = 0.84; // 1 / tan(fov/2), fov=100
const DRAW_DIST: number = 65;
const CENTRIFUGAL: number = 0.31;

const CAR_COLORS: string[] = ['#e63946', '#f4a300', '#9b5de5', '#00b4d8', '#ff70a6', '#43aa8b'];

function easeIn(a: number, b: number, p: number): number {
  return a + (b - a) * Math.pow(p, 2);
}

function easeInOut(a: number, b: number, p: number): number {
  return a + (b - a) * ((-Math.cos(p * Math.PI) / 2) + 0.5);
}

function clamp(v: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, v));
}

function overlap(x1: number, w1: number, x2: number, w2: number): boolean {
  const half: number = 1.0;
  const min1: number = x1 - w1 * half;
  const max1: number = x1 + w1 * half;
  const min2: number = x2 - w2 * half;
  const max2: number = x2 + w2 * half;
  return !(max1 < min2 || min1 > max2);
}

export class Game {
  state: GameState = GameState.MENU;
  trackId: number = 0;
  track: TrackInfo = TRACKS[0];

  segments: Segment[] = [];
  trackLength: number = 0;
  cars: Car[] = [];

  // 玩家状态
  position: number = 0;      // 摄像机沿赛道的 z
  playerX: number = 0;       // -1..1 为路面范围
  playerZ: number = CAM_H * CAM_DEPTH; // 玩家在摄像机前方的距离(z 单位)
  speed: number = 0;
  maxSpeed: number = SEG_LEN * 62;
  lap: number = 1;
  totalDist: number = 0;
  rank: number = 1;
  finalRank: number = 1;

  // 计时
  raceTime: number = 0;
  lapStartTime: number = 0;
  lastLapTime: number = 0;
  bestLapTime: number = 0;
  countdown: number = 0;

  // 输入
  inputLeft: boolean = false;
  inputRight: boolean = false;
  inputAccel: boolean = false;
  inputBrake: boolean = false;

  private bounceT: number = 0;

  constructor() {
    this.buildTrack(0);
  }

  // ---------------- 赛道构建 ----------------

  private lastY(): number {
    return this.segments.length === 0 ? 0 : this.segments[this.segments.length - 1].y2;
  }

  private addSegment(curve: number, y: number): void {
    const seg: Segment = new Segment();
    seg.index = this.segments.length;
    seg.curve = curve;
    seg.y1 = this.lastY();
    seg.y2 = y;
    this.segments.push(seg);
  }

  private addRoad(enter: number, hold: number, leave: number, curve: number, hill: number): void {
    const startY: number = this.lastY();
    const endY: number = startY + hill * SEG_LEN;
    const total: number = enter + hold + leave;
    for (let i = 0; i < enter; i++) {
      this.addSegment(easeIn(0, curve, i / enter), easeInOut(startY, endY, i / total));
    }
    for (let i = 0; i < hold; i++) {
      this.addSegment(curve, easeInOut(startY, endY, (enter + i) / total));
    }
    for (let i = 0; i < leave; i++) {
      this.addSegment(easeInOut(curve, 0, i / leave), easeInOut(startY, endY, (enter + hold + i) / total));
    }
  }

  private straight(n: number): void {
    this.addRoad(n, n, n, 0, 0);
  }

  buildTrack(id: number): void {
    this.trackId = id;
    this.track = TRACKS[id];
    this.segments = [];

    if (id === 0) {
      // 翡翠环道:平缓
      this.straight(12);
      this.addRoad(20, 20, 20, -2, 0);
      this.straight(8);
      this.addRoad(15, 15, 15, 3, 8);
      this.addRoad(15, 15, 15, 0, -8);
      this.addRoad(25, 25, 25, 2, 0);
      this.straight(10);
      this.addRoad(20, 30, 20, -3, 4);
      this.addRoad(15, 15, 15, 0, -4);
      this.addRoad(20, 20, 20, 2, 0);
      this.straight(12);
    } else if (id === 1) {
      // 沙漠竞速:长弯+起伏
      this.straight(10);
      this.addRoad(25, 40, 25, 3, 10);
      this.addRoad(15, 15, 15, 0, -6);
      this.addRoad(25, 35, 25, -4, 8);
      this.addRoad(15, 15, 15, 0, -12);
      this.straight(8);
      this.addRoad(20, 30, 20, 4, 6);
      this.addRoad(20, 30, 20, -3, -6);
      this.addRoad(15, 20, 15, 2, 10);
      this.addRoad(15, 20, 15, -2, -10);
      this.straight(10);
    } else {
      // 雪峰之巅:急弯陡坡
      this.straight(8);
      this.addRoad(10, 15, 10, 5, 14);
      this.addRoad(10, 10, 10, -5, 6);
      this.addRoad(12, 12, 12, 4, -10);
      this.straight(6);
      this.addRoad(10, 20, 10, -6, 16);
      this.addRoad(10, 10, 10, 5, -8);
      this.addRoad(12, 15, 12, -4, -12);
      this.addRoad(10, 10, 10, 6, 8);
      this.addRoad(10, 15, 10, -5, -14);
      this.straight(10);
    }

    // 闭合高度:让终点高度回到起点
    const endY: number = this.lastY();
    if (Math.abs(endY) > 1) {
      const n: number = 30;
      const startY: number = endY;
      for (let i = 0; i < n; i++) {
        this.addSegment(0, easeInOut(startY, 0, (i + 1) / n));
      }
    }

    // 路边树木/标志
    for (let i = 20; i < this.segments.length; i += 4) {
      if (i % 12 === 0) {
        continue;
      }
      const side: number = (i % 8 < 4) ? -1 : 1;
      this.segments[i].spriteX = side * (1.4 + (i * 7 % 13) / 10);
    }

    this.trackLength = this.segments.length * SEG_LEN;
  }

  // ---------------- 比赛控制 ----------------

  startRace(id: number): void {
    this.buildTrack(id);
    this.position = 0;
    this.playerX = 0;
    this.speed = 0;
    this.lap = 1;
    this.totalDist = 0;
    this.raceTime = 0;
    this.lapStartTime = 0;
    this.lastLapTime = 0;
    this.bestLapTime = 0;
    this.rank = this.track.aiCount + 1;
    this.countdown = 3.5;
    this.inputLeft = false;
    this.inputRight = false;
    this.inputAccel = false;
    this.inputBrake = false;

    // 初始化 AI:在玩家前方排成发车阵型
    this.cars = [];
    for (let i = 0; i < this.track.aiCount; i++) {
      const c: Car = new Car();
      c.z = (i + 1) * SEG_LEN * 3;
      c.offset = (i % 2 === 0) ? -0.45 : 0.45;
      c.speed = this.maxSpeed * (0.62 + 0.05 * i / this.track.aiCount + Math.random() * 0.08);
      c.color = CAR_COLORS[i % CAR_COLORS.length];
      c.totalDist = c.z;
      this.cars.push(c);
    }

    this.state = GameState.COUNTDOWN;
  }

  pause(): void {
    if (this.state === GameState.RACING) {
      this.state = GameState.PAUSED;
    }
  }

  resume(): void {
    if (this.state === GameState.PAUSED) {
      this.state = GameState.RACING;
    }
  }

  quitToMenu(): void {
    this.state = GameState.MENU;
    this.speed = 0;
  }

  // ---------------- 逻辑更新 ----------------

  private findSegment(z: number): Segment {
    let idx: number = Math.floor(z / SEG_LEN) % this.segments.length;
    if (idx < 0) {
      idx += this.segments.length;
    }
    return this.segments[idx];
  }

  private increase(start: number, inc: number, max: number): number {
    let r: number = start + inc;
    while (r >= max) {
      r -= max;
    }
    while (r < 0) {
      r += max;
    }
    return r;
  }

  update(dt: number): void {
    if (this.state === GameState.COUNTDOWN) {
      this.countdown -= dt;
      if (this.countdown <= 0.5) {
        this.state = GameState.RACING;
      }
      return;
    }
    if (this.state !== GameState.RACING) {
      return;
    }

    this.raceTime += dt;
    this.bounceT += dt * (4 + 10 * this.speed / this.maxSpeed);

    const playerSegment: Segment = this.findSegment(this.position + this.playerZ);
    const speedPercent: number = this.speed / this.maxSpeed;
    const dx: number = dt * 2 * speedPercent;

    const accel: number = this.maxSpeed / 4.5;
    const braking: number = -this.maxSpeed;
    const decel: number = -this.maxSpeed / 5;
    const offRoadDecel: number = -this.maxSpeed / 1.5;
    const offRoadLimit: number = this.maxSpeed / 4;

    const prevPosition: number = this.position;
    this.position = this.increase(this.position, dt * this.speed, this.trackLength);
    this.totalDist += dt * this.speed;

    // 转向
    if (this.inputLeft) {
      this.playerX -= dx;
    }
    if (this.inputRight) {
      this.playerX += dx;
    }
    // 弯道离心力
    this.playerX -= dx * CENTRIFUGAL * playerSegment.curve * speedPercent;

    // 加速/刹车
    if (this.inputBrake) {
      this.speed += braking * dt;
    } else if (this.inputAccel) {
      this.speed += accel * dt;
    } else {
      this.speed += decel * dt;
    }

    // 出弯冲出路面减速
    if ((this.playerX < -1 || this.playerX > 1) && this.speed > offRoadLimit) {
      this.speed += offRoadDecel * dt;
    }

    // 与 AI 碰撞
    for (let i = 0; i < this.cars.length; i++) {
      const car: Car = this.cars[i];
      const carSeg: Segment = this.findSegment(car.z);
      if (carSeg.index !== playerSegment.index) {
        continue;
      }
      if (this.speed > car.speed && overlap(this.playerX, 0.32, car.offset, 0.32)) {
        this.speed = car.speed * (car.speed / this.speed);
        this.position = this.increase(car.z, -this.playerZ, this.trackLength);
        break;
      }
    }

    this.playerX = clamp(this.playerX, -2.2, 2.2);
    this.speed = clamp(this.speed, 0, this.maxSpeed);

    // 圈数检测(position 回绕)
    if (prevPosition > this.position && dt * this.speed > 0) {
      this.lastLapTime = this.raceTime - this.lapStartTime;
      this.lapStartTime = this.raceTime;
      if (this.bestLapTime === 0 || this.lastLapTime < this.bestLapTime) {
        this.bestLapTime = this.lastLapTime;
      }
      this.lap++;
      if (this.lap > this.track.laps) {
        this.finalRank = this.rank;
        this.state = GameState.FINISHED;
        return;
      }
    }

    this.updateCars(dt, playerSegment);
    this.updateRank();
  }

  private updateCars(dt: number, playerSegment: Segment): void {
    for (let i = 0; i < this.cars.length; i++) {
      const car: Car = this.cars[i];
      const carSeg: Segment = this.findSegment(car.z);
      car.offset += this.steerAI(car, carSeg, playerSegment, dt);
      car.offset = clamp(car.offset, -0.85, 0.85);
      car.z = this.increase(car.z, dt * car.speed, this.trackLength);
      car.totalDist += dt * car.speed;
    }
  }

  private steerAI(car: Car, carSeg: Segment, playerSegment: Segment, dt: number): number {
    const lookahead: number = 20;
    const carW: number = 0.32;

    // 不在玩家可见范围内则不做微操
    const distIdx: number = (carSeg.index - playerSegment.index + this.segments.length) % this.segments.length;
    if (distIdx > DRAW_DIST) {
      return 0;
    }

    for (let i = 1; i < lookahead; i++) {
      const seg: Segment = this.segments[(carSeg.index + i) % this.segments.length];
      // 避让玩家
      if (seg.index === playerSegment.index && car.speed > this.speed &&
        overlap(this.playerX, 0.32, car.offset, carW)) {
        let dir: number;
        if (this.playerX > 0.5) {
          dir = -1;
        } else if (this.playerX < -0.5) {
          dir = 1;
        } else {
          dir = (car.offset > this.playerX) ? 1 : -1;
        }
        return dir * (1 / i) * (car.speed - this.speed) / this.maxSpeed * dt * 12;
      }
      // 避让其他 AI
      for (let j = 0; j < this.cars.length; j++) {
        const other: Car = this.cars[j];
        if (other === car) {
          continue;
        }
        const otherSeg: Segment = this.findSegment(other.z);
        if (otherSeg.index === seg.index && car.speed > other.speed &&
          overlap(car.offset, carW, other.offset, carW)) {
          let dir: number;
          if (other.offset > 0.5) {
            dir = -1;
          } else if (other.offset < -0.5) {
            dir = 1;
          } else {
            dir = (car.offset > other.offset) ? 1 : -1;
          }
          return dir * (1 / i) * (car.speed - other.speed) / this.maxSpeed * dt * 12;
        }
      }
    }

    // 回到路中央
    if (car.offset < -0.7) {
      return 0.1 * dt * 5;
    }
    if (car.offset > 0.7) {
      return -0.1 * dt * 5;
    }
    return 0;
  }

  private updateRank(): void {
    let r: number = 1;
    for (let i = 0; i < this.cars.length; i++) {
      if (this.cars[i].totalDist > this.totalDist) {
        r++;
      }
    }
    this.rank = r;
  }

  // ---------------- 渲染 ----------------

  render(ctx: CanvasRenderingContext2D, w: number, h: number): void {
    const t: TrackInfo = this.track;

    // 天空
    const sky = ctx.createLinearGradient(0, 0, 0, h * 0.6);
    sky.addColorStop(0, t.skyTop);
    sky.addColorStop(1, t.skyBottom);
    ctx.fillStyle = sky;
    ctx.fillRect(0, 0, w, h);

    // 太阳
    ctx.fillStyle = 'rgba(255,240,180,0.9)';
    ctx.beginPath();
    ctx.arc(w * 0.72, h * 0.16, h * 0.07, 0, Math.PI * 2);
    ctx.fill();

    // 远山(带视差)
    const hillShift: number = -(this.position * 0.0015 + this.playerX * 12) % w;
    ctx.fillStyle = t.hillColor;
    ctx.beginPath();
    ctx.moveTo(0, h * 0.5);
    for (let px = 0; px <= w; px += 8) {
      const yy: number = h * 0.42 + Math.sin((px - hillShift) * 0.012) * h * 0.05
        + Math.sin((px - hillShift) * 0.004 + 2) * h * 0.04;
      ctx.lineTo(px, yy);
    }
    ctx.lineTo(w, h * 0.6);
    ctx.lineTo(0, h * 0.6);
    ctx.closePath();
    ctx.fill();

    // 地面底色
    ctx.fillStyle = t.grassDark;
    ctx.fillRect(0, h * 0.5, w, h * 0.5);

    // ------- 路面 -------
    const baseSegment: Segment = this.findSegment(this.position);
    const basePercent: number = (this.position % SEG_LEN) / SEG_LEN;
    const playerSegment: Segment = this.findSegment(this.position + this.playerZ);
    const playerPercent: number = ((this.position + this.playerZ) % SEG_LEN) / SEG_LEN;
    const playerY: number = playerSegment.y1 + (playerSegment.y2 - playerSegment.y1) * playerPercent;

    let maxY: number = h;
    let x: number = 0;
    let dxCurve: number = -(baseSegment.curve * basePercent);

    const drawnIdx: number[] = [];

    for (let n = 0; n < DRAW_DIST; n++) {
      const segIndex: number = (baseSegment.index + n) % this.segments.length;
      const seg: Segment = this.segments[segIndex];
      seg.drawn = false;

      const looped: boolean = segIndex < baseSegment.index;
      const camZ: number = this.position - (looped ? this.trackLength : 0);
      const camX: number = this.playerX * ROAD_W;
      const camY: number = playerY + CAM_H;

      // 投影 p1 / p2
      const z1: number = segIndex * SEG_LEN - camZ;
      const z2: number = (segIndex + 1) * SEG_LEN - camZ;
      if (z1 <= CAM_DEPTH) {
        x += dxCurve;
        dxCurve += seg.curve;
        continue;
      }
      const scale1: number = CAM_DEPTH / z1;
      const scale2: number = CAM_DEPTH / z2;
      const sx1: number = Math.round(w / 2 + scale1 * (x - camX) * w / 2);
      const sy1: number = Math.round(h / 2 - scale1 * (seg.y1 - camY) * h / 2);
      const sw1: number = Math.round(scale1 * ROAD_W * w / 2);
      const sx2: number = Math.round(w / 2 + scale2 * (x + dxCurve - camX) * w / 2);
      const sy2: number = Math.round(h / 2 - scale2 * (seg.y2 - camY) * h / 2);
      const sw2: number = Math.round(scale2 * ROAD_W * w / 2);

      x += dxCurve;
      dxCurve += seg.curve;

      seg.clipY = maxY;
      if (sy2 >= maxY || sy2 >= sy1) {
        continue;
      }

      seg.sx1 = sx1; seg.sy1 = sy1; seg.sw1 = sw1;
      seg.sx2 = sx2; seg.sy2 = sy2; seg.sw2 = sw2;
      seg.scale2 = scale2;
      seg.fog = 1 - Math.pow(Math.min(1, n / DRAW_DIST), 3);
      seg.drawn = true;
      drawnIdx.push(segIndex);

      this.drawSegment(ctx, w, seg, segIndex);
      maxY = sy2;
    }

    // ------- 路边物体与 AI 车(从远到近) -------
    for (let k = drawnIdx.length - 1; k >= 0; k--) {
      const seg: Segment = this.segments[drawnIdx[k]];

      if (seg.spriteX !== 0) {
        const sx: number = seg.sx2 + seg.sw2 * seg.spriteX;
        this.drawTree(ctx, sx, seg.sy2, seg.sw2 * 0.28, seg.clipY);
      }

      for (let i = 0; i < this.cars.length; i++) {
        const car: Car = this.cars[i];
        const carSegIdx: number = Math.floor(car.z / SEG_LEN) % this.segments.length;
        if (carSegIdx !== seg.index) {
          continue;
        }
        const pct: number = (car.z % SEG_LEN) / SEG_LEN;
        const cx: number = seg.sx1 + (seg.sx2 - seg.sx1) * pct + (seg.sw1 + (seg.sw2 - seg.sw1) * pct) * car.offset;
        const cy: number = seg.sy1 + (seg.sy2 - seg.sy1) * pct;
        const cw: number = (seg.sw1 + (seg.sw2 - seg.sw1) * pct) * 0.30;
        this.drawKart(ctx, cx, cy, cw, car.color, 0, seg.clipY, w);
      }
    }

    // ------- 玩家卡丁车 -------
    if (this.state !== GameState.MENU) {
      const bounce: number = Math.sin(this.bounceT * 3) * (this.speed / this.maxSpeed) * h * 0.004;
      let steer: number = 0;
      if (this.inputLeft) {
        steer = -1;
      } else if (this.inputRight) {
        steer = 1;
      }
      const kartW: number = w * 0.10;
      this.drawKart(ctx, w / 2, h * 0.94 + bounce, kartW, '#2ecc71', steer, h, w);
    }

    // ------- HUD -------
    if (this.state === GameState.RACING || this.state === GameState.COUNTDOWN ||
      this.state === GameState.PAUSED) {
      this.drawHUD(ctx, w, h);
    }
    if (this.state === GameState.COUNTDOWN) {
      const num: number = Math.ceil(this.countdown - 0.5);
      ctx.textAlign = 'center';
      ctx.fillStyle = 'rgba(0,0,0,0.35)';
      ctx.beginPath();
      ctx.arc(w / 2, h * 0.35, h * 0.12, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = num > 0 ? '#ffd700' : '#2ecc71';
      ctx.font = `bold ${Math.round(h * 0.14)}px sans-serif`;
      ctx.fillText(num > 0 ? String(num) : 'GO!', w / 2, h * 0.4);
      ctx.textAlign = 'left';
    }
  }

  private drawSegment(ctx: CanvasRenderingContext2D, w: number, seg: Segment, index: number): void {
    const alt: boolean = Math.floor(index / RUMBLE) % 2 === 0;
    const t: TrackInfo = this.track;

    // 草地
    ctx.fillStyle = alt ? t.grassLight : t.grassDark;
    ctx.fillRect(0, seg.sy2, w, seg.sy1 - seg.sy2);

    const r1: number = seg.sw1 / 6;
    const r2: number = seg.sw2 / 6;
    const l1: number = seg.sw1 / 36;
    const l2: number = seg.sw2 / 36;

    // 路肩
    ctx.fillStyle = alt ? '#ffffff' : '#e63946';
    this.quad(ctx, seg.sx1 - seg.sw1 - r1, seg.sy1, seg.sx1 - seg.sw1, seg.sy1,
      seg.sx2 - seg.sw2, seg.sy2, seg.sx2 - seg.sw2 - r2, seg.sy2);
    this.quad(ctx, seg.sx1 + seg.sw1 + r1, seg.sy1, seg.sx1 + seg.sw1, seg.sy1,
      seg.sx2 + seg.sw2, seg.sy2, seg.sx2 + seg.sw2 + r2, seg.sy2);

    // 路面
    ctx.fillStyle = alt ? '#6b6b6b' : '#636363';
    this.quad(ctx, seg.sx1 - seg.sw1, seg.sy1, seg.sx1 + seg.sw1, seg.sy1,
      seg.sx2 + seg.sw2, seg.sy2, seg.sx2 - seg.sw2, seg.sy2);

    // 车道线
    if (alt) {
      ctx.fillStyle = '#ffffff';
      const lanes: number = 3;
      for (let lane = 1; lane < lanes; lane++) {
        const lx1: number = seg.sx1 - seg.sw1 + seg.sw1 * 2 * lane / lanes;
        const lx2: number = seg.sx2 - seg.sw2 + seg.sw2 * 2 * lane / lanes;
        this.quad(ctx, lx1 - l1 / 2, seg.sy1, lx1 + l1 / 2, seg.sy1,
          lx2 + l2 / 2, seg.sy2, lx2 - l2 / 2, seg.sy2);
      }
    }

    // 起终点线
    if (index < 3 || index >= this.segments.length - 3) {
      ctx.fillStyle = index % 2 === 0 ? '#ffffff' : '#222222';
      this.quad(ctx, seg.sx1 - seg.sw1, seg.sy1, seg.sx1 + seg.sw1, seg.sy1,
        seg.sx2 + seg.sw2, seg.sy2, seg.sx2 - seg.sw2, seg.sy2);
    }

    // 雾化
    if (seg.fog < 1) {
      ctx.fillStyle = this.track.skyBottom;
      ctx.globalAlpha = 1 - seg.fog;
      ctx.fillRect(0, seg.sy2, w, seg.sy1 - seg.sy2);
      ctx.globalAlpha = 1;
    }
  }

  private quad(ctx: CanvasRenderingContext2D,
               x1: number, y1: number, x2: number, y2: number,
               x3: number, y3: number, x4: number, y4: number): void {
    ctx.beginPath();
    ctx.moveTo(x1, y1);
    ctx.lineTo(x2, y2);
    ctx.lineTo(x3, y3);
    ctx.lineTo(x4, y4);
    ctx.closePath();
    ctx.fill();
  }

  private drawTree(ctx: CanvasRenderingContext2D, x: number, y: number, size: number, clipY: number): void {
    if (size < 2) {
      return;
    }
    ctx.save();
    ctx.beginPath();
    ctx.rect(-10000, -10000, 20000, 10000 + clipY);
    ctx.clip();
    // 树干
    ctx.fillStyle = '#5a3a1a';
    ctx.fillRect(x - size * 0.07, y - size * 0.45, size * 0.14, size * 0.45);
    ctx.fillStyle = '#6b4a2a';
    ctx.fillRect(x - size * 0.05, y - size * 0.45, size * 0.04, size * 0.45);
    // 树冠三层(带明暗)
    const dark: string = this.darkenColor(this.track.treeColor, 0.3);
    const light: string = this.lightenColor(this.track.treeColor, 0.2);
    // 底层
    ctx.fillStyle = dark;
    ctx.beginPath();
    ctx.moveTo(x, y - size * 1.5);
    ctx.lineTo(x - size * 0.55, y - size * 0.35);
    ctx.lineTo(x + size * 0.55, y - size * 0.35);
    ctx.closePath();
    ctx.fill();
    // 中层
    ctx.fillStyle = this.track.treeColor;
    ctx.beginPath();
    ctx.moveTo(x, y - size * 1.9);
    ctx.lineTo(x - size * 0.42, y - size * 0.95);
    ctx.lineTo(x + size * 0.42, y - size * 0.95);
    ctx.closePath();
    ctx.fill();
    // 顶层
    ctx.fillStyle = light;
    ctx.beginPath();
    ctx.moveTo(x, y - size * 2.3);
    ctx.lineTo(x - size * 0.3, y - size * 1.5);
    ctx.lineTo(x + size * 0.3, y - size * 1.5);
    ctx.closePath();
    ctx.fill();
    // 左侧高光
    ctx.fillStyle = 'rgba(255,255,255,0.12)';
    ctx.beginPath();
    ctx.moveTo(x - size * 0.1, y - size * 2.2);
    ctx.lineTo(x - size * 0.28, y - size * 1.55);
    ctx.lineTo(x - size * 0.18, y - size * 1.55);
    ctx.closePath();
    ctx.fill();
    ctx.restore();
  }

  private drawKart(ctx: CanvasRenderingContext2D, x: number, y: number, halfW: number,
                   color: string, steer: number, clipY: number, screenW: number): void {
    if (halfW < 1.5) {
      return;
    }
    ctx.save();
    ctx.beginPath();
    ctx.rect(-10000, -10000, 20000 + screenW, 10000 + clipY);
    ctx.clip();

    const s: number = halfW / 50;
    ctx.translate(x, y);
    ctx.lineJoin = 'round';

    // ---- 椭圆软阴影 ----
    ctx.fillStyle = 'rgba(0,0,0,0.28)';
    ctx.beginPath();
    ctx.ellipse(0, 4 * s, 58 * s, 12 * s, 0, 0, Math.PI * 2);
    ctx.fill();

    // ---- 后轮(带轮毂) ----
    this.drawWheel(ctx, -48 * s, -14 * s, 18 * s, 30 * s, 0);
    this.drawWheel(ctx, 48 * s, -14 * s, 18 * s, 30 * s, 0);

    // ---- 底盘暗色 ----
    ctx.fillStyle = '#1a1a22';
    ctx.beginPath();
    ctx.moveTo(-42 * s, -4 * s);
    ctx.lineTo(-30 * s, -12 * s);
    ctx.lineTo(30 * s, -12 * s);
    ctx.lineTo(42 * s, -4 * s);
    ctx.lineTo(38 * s, 2 * s);
    ctx.lineTo(-38 * s, 2 * s);
    ctx.closePath();
    ctx.fill();

    // ---- 主车身(渐变) ----
    const bodyGrad = ctx.createLinearGradient(0, -40 * s, 0, -4 * s);
    bodyGrad.addColorStop(0, this.lightenColor(color, 0.35));
    bodyGrad.addColorStop(0.5, color);
    bodyGrad.addColorStop(1, this.darkenColor(color, 0.3));
    ctx.fillStyle = bodyGrad;
    ctx.beginPath();
    ctx.moveTo(-42 * s, -6 * s);
    ctx.lineTo(-34 * s, -18 * s);
    ctx.lineTo(-28 * s, -30 * s);
    ctx.lineTo(28 * s, -30 * s);
    ctx.lineTo(34 * s, -18 * s);
    ctx.lineTo(42 * s, -6 * s);
    ctx.lineTo(38 * s, 0 * s);
    ctx.lineTo(-38 * s, 0 * s);
    ctx.closePath();
    ctx.fill();

    // 车身高光带
    ctx.fillStyle = 'rgba(255,255,255,0.18)';
    ctx.beginPath();
    ctx.moveTo(-36 * s, -16 * s);
    ctx.lineTo(-30 * s, -28 * s);
    ctx.lineTo(-26 * s, -28 * s);
    ctx.lineTo(-32 * s, -14 * s);
    ctx.closePath();
    ctx.fill();

    // ---- 前鼻锥 ----
    const noseGrad = ctx.createLinearGradient(0, -30 * s, 0, -12 * s);
    noseGrad.addColorStop(0, this.lightenColor(color, 0.2));
    noseGrad.addColorStop(1, this.darkenColor(color, 0.15));
    ctx.fillStyle = noseGrad;
    ctx.beginPath();
    ctx.moveTo(-22 * s, -28 * s);
    ctx.lineTo(-14 * s, -42 * s);
    ctx.lineTo(14 * s, -42 * s);
    ctx.lineTo(22 * s, -28 * s);
    ctx.closePath();
    ctx.fill();

    // 鼻锥高光
    ctx.fillStyle = 'rgba(255,255,255,0.22)';
    ctx.beginPath();
    ctx.moveTo(-18 * s, -30 * s);
    ctx.lineTo(-12 * s, -40 * s);
    ctx.lineTo(-8 * s, -40 * s);
    ctx.lineTo(-14 * s, -28 * s);
    ctx.closePath();
    ctx.fill();

    // 前编号牌
    ctx.fillStyle = '#ffffff';
    ctx.beginPath();
    ctx.roundRect(-10 * s, -38 * s, 20 * s, 8 * s, 2 * s);
    ctx.fill();

    // ---- 尾翼 ----
    // 支柱
    ctx.fillStyle = '#2a2a2e';
    ctx.fillRect(-4 * s, -44 * s, 8 * s, 14 * s);
    ctx.fillRect(-28 * s, -42 * s, 5 * s, 12 * s);
    ctx.fillRect(23 * s, -42 * s, 5 * s, 12 * s);
    // 翼板
    const wingGrad = ctx.createLinearGradient(0, -48 * s, 0, -42 * s);
    wingGrad.addColorStop(0, '#3a3a42');
    wingGrad.addColorStop(1, '#1a1a1e');
    ctx.fillStyle = wingGrad;
    ctx.beginPath();
    ctx.roundRect(-36 * s, -48 * s, 72 * s, 7 * s, 3 * s);
    ctx.fill();
    // 翼板端板
    ctx.fillStyle = '#222226';
    ctx.fillRect(-38 * s, -48 * s, 4 * s, 10 * s);
    ctx.fillRect(34 * s, -48 * s, 4 * s, 10 * s);

    // ---- 侧边进气口 ----
    ctx.fillStyle = this.darkenColor(color, 0.35);
    ctx.beginPath();
    ctx.roundRect(-40 * s, -22 * s, 10 * s, 14 * s, 3 * s);
    ctx.fill();
    ctx.beginPath();
    ctx.roundRect(30 * s, -22 * s, 10 * s, 14 * s, 3 * s);
    ctx.fill();

    // ---- 前轮(带转向) ----
    ctx.save();
    ctx.translate(-30 * s, -18 * s);
    ctx.rotate(steer * 0.32);
    this.drawWheel(ctx, 0, 0, 14 * s, 24 * s, 1);
    ctx.restore();
    ctx.save();
    ctx.translate(30 * s, -18 * s);
    ctx.rotate(steer * 0.32);
    this.drawWheel(ctx, 0, 0, 14 * s, 24 * s, 1);
    ctx.restore();

    // ---- 车手 ----
    // 身体/肩部
    ctx.fillStyle = '#2a2a2e';
    ctx.beginPath();
    ctx.ellipse(0, -34 * s, 16 * s, 10 * s, 0, 0, Math.PI * 2);
    ctx.fill();
    // 头盔上半(亮色)
    const helmetGrad = ctx.createRadialGradient(-4 * s, -46 * s, 2 * s, 0, -42 * s, 16 * s);
    helmetGrad.addColorStop(0, this.lightenColor(color, 0.5));
    helmetGrad.addColorStop(0.6, color);
    helmetGrad.addColorStop(1, this.darkenColor(color, 0.25));
    ctx.fillStyle = helmetGrad;
    ctx.beginPath();
    ctx.arc(0, -42 * s, 13 * s, Math.PI * 1.05, Math.PI * 1.95, false);
    ctx.lineTo(12 * s, -36 * s);
    ctx.lineTo(-12 * s, -36 * s);
    ctx.closePath();
    ctx.fill();
    // 头盔顶部条纹
    ctx.fillStyle = 'rgba(255,255,255,0.3)';
    ctx.beginPath();
    ctx.moveTo(0, -55 * s);
    ctx.lineTo(-3 * s, -42 * s);
    ctx.lineTo(3 * s, -42 * s);
    ctx.closePath();
    ctx.fill();
    // 护目镜
    ctx.fillStyle = '#1a1a2a';
    ctx.beginPath();
    ctx.roundRect(-10 * s, -42 * s, 20 * s, 7 * s, 3 * s);
    ctx.fill();
    // 护目镜反光
    ctx.fillStyle = 'rgba(100,180,255,0.5)';
    ctx.beginPath();
    ctx.roundRect(-8 * s, -41 * s, 7 * s, 3 * s, 1.5 * s);
    ctx.fill();
    ctx.fillStyle = 'rgba(100,180,255,0.25)';
    ctx.beginPath();
    ctx.roundRect(2 * s, -41 * s, 5 * s, 3 * s, 1.5 * s);
    ctx.fill();

    ctx.restore();
  }

  private drawWheel(ctx: CanvasRenderingContext2D, cx: number, cy: number,
                    w: number, h: number, detail: number): void {
    const s: number = w / 14;
    // 轮胎
    ctx.fillStyle = '#15151a';
    ctx.beginPath();
    ctx.roundRect(cx - w / 2, cy - h / 2, w, h, w * 0.3);
    ctx.fill();
    // 轮胎内侧高光
    ctx.fillStyle = '#2a2a30';
    ctx.beginPath();
    ctx.roundRect(cx - w / 2 + 2 * s, cy - h / 2 + 2 * s, w - 4 * s, h - 4 * s, w * 0.25);
    ctx.fill();
    if (detail > 0 && w > 8) {
      // 轮毂
      ctx.fillStyle = '#888890';
      ctx.beginPath();
      ctx.ellipse(cx, cy, w * 0.28, h * 0.28, 0, 0, Math.PI * 2);
      ctx.fill();
      // 轮毂中心
      ctx.fillStyle = '#444448';
      ctx.beginPath();
      ctx.ellipse(cx, cy, w * 0.12, h * 0.12, 0, 0, Math.PI * 2);
      ctx.fill();
      // 辐条
      ctx.strokeStyle = '#aaaab0';
      ctx.lineWidth = 1.5 * s;
      ctx.beginPath();
      for (let i = 0; i < 5; i++) {
        const a: number = (i / 5) * Math.PI * 2;
        ctx.moveTo(cx, cy);
        ctx.lineTo(cx + Math.cos(a) * w * 0.26, cy + Math.sin(a) * h * 0.26);
      }
      ctx.stroke();
    }
  }

  private lightenColor(hex: string, amount: number): string {
    const r: number = parseInt(hex.slice(1, 3), 16);
    const g: number = parseInt(hex.slice(3, 5), 16);
    const b: number = parseInt(hex.slice(5, 7), 16);
    const nr: number = Math.min(255, Math.round(r + (255 - r) * amount));
    const ng: number = Math.min(255, Math.round(g + (255 - g) * amount));
    const nb: number = Math.min(255, Math.round(b + (255 - b) * amount));
    return `#${nr.toString(16).padStart(2, '0')}${ng.toString(16).padStart(2, '0')}${nb.toString(16).padStart(2, '0')}`;
  }

  private darkenColor(hex: string, amount: number): string {
    const r: number = parseInt(hex.slice(1, 3), 16);
    const g: number = parseInt(hex.slice(3, 5), 16);
    const b: number = parseInt(hex.slice(5, 7), 16);
    const nr: number = Math.max(0, Math.round(r * (1 - amount)));
    const ng: number = Math.max(0, Math.round(g * (1 - amount)));
    const nb: number = Math.max(0, Math.round(b * (1 - amount)));
    return `#${nr.toString(16).padStart(2, '0')}${ng.toString(16).padStart(2, '0')}${nb.toString(16).padStart(2, '0')}`;
  }

  private drawHUD(ctx: CanvasRenderingContext2D, w: number, h: number): void {
    const fs: number = Math.round(h * 0.042);
    ctx.font = `bold ${fs}px sans-serif`;

    // 顶部信息条
    ctx.fillStyle = 'rgba(0,0,0,0.4)';
    ctx.fillRect(0, 0, w, fs * 1.8);

    ctx.fillStyle = '#ffffff';
    ctx.textAlign = 'left';
    ctx.fillText(`第 ${Math.min(this.lap, this.track.laps)}/${this.track.laps} 圈`, w * 0.02, fs * 1.25);

    ctx.textAlign = 'center';
    ctx.fillText(this.formatTime(this.raceTime), w * 0.5, fs * 1.25);

    ctx.textAlign = 'right';
    ctx.fillStyle = '#ffd700';
    ctx.fillText(`第 ${this.rank} 名`, w * 0.86, fs * 1.25);

    // 速度
    ctx.textAlign = 'right';
    ctx.fillStyle = '#ffffff';
    const kmh: number = Math.round(this.speed / this.maxSpeed * 180);
    ctx.font = `bold ${Math.round(h * 0.06)}px sans-serif`;
    ctx.fillText(`${kmh}`, w * 0.97, h * 0.12);
    ctx.font = `${Math.round(h * 0.028)}px sans-serif`;
    ctx.fillText('km/h', w * 0.97, h * 0.155);

    // 上一圈 / 最快圈
    if (this.lastLapTime > 0) {
      ctx.textAlign = 'left';
      ctx.font = `${Math.round(h * 0.028)}px sans-serif`;
      ctx.fillStyle = '#cccccc';
      ctx.fillText(`上圈 ${this.formatTime(this.lastLapTime)}`, w * 0.02, fs * 1.8 + h * 0.04);
      ctx.fillStyle = '#7CFC00';
      ctx.fillText(`最快 ${this.formatTime(this.bestLapTime)}`, w * 0.02, fs * 1.8 + h * 0.075);
    }
    ctx.textAlign = 'left';
  }

  formatTime(sec: number): string {
    const m: number = Math.floor(sec / 60);
    const s: number = Math.floor(sec % 60);
    const ms: number = Math.floor((sec % 1) * 100);
    const ss: string = s < 10 ? `0${s}` : String(s);
    const mss: string = ms < 10 ? `0${ms}` : String(ms);
    return `${m}:${ss}.${mss}`;
  }
}
