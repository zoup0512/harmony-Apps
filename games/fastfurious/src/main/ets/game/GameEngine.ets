/**
 * 速度与激情6 复刻版 - 游戏核心引擎
 * 2D 竖屏公路赛车：变道躲避车流、氮气加速、计分
 */

export enum GameState {
  MENU = 0,
  PLAYING = 1,
  GAME_OVER = 2
}

const LANE_COUNT = 4;

class TrafficCar {
  lane: number = 0;
  y: number = 0;
  speed: number = 0;
  color: string = '#cc3344';
  passed: boolean = false;
  imgIndex: number = -1;

  constructor(lane: number, y: number, speed: number, color: string, imgIndex: number = -1) {
    this.lane = lane;
    this.y = y;
    this.speed = speed;
    this.color = color;
    this.imgIndex = imgIndex;
  }
}

class RoadMark {
  y: number = 0;

  constructor(y: number) {
    this.y = y;
  }
}

export class GameEngine {
  // 画布尺寸
  width: number = 360;
  height: number = 780;

  state: GameState = GameState.MENU;

  // 道路布局
  roadLeft: number = 0;
  roadWidth: number = 0;
  laneWidth: number = 0;
  carWidth: number = 0;
  carHeight: number = 0;

  // 玩家
  playerLane: number = 1;
  playerX: number = 0; // 平滑移动的当前 x（车中心）
  playerY: number = 0;
  speed: number = 300; // 当前速度 像素/秒
  baseSpeed: number = 300;
  maxSpeed: number = 900;

  // 氮气
  nitro: number = 100; // 0-100
  nitroActive: boolean = false;

  // 车流与路标
  traffic: TrafficCar[] = [];
  marks: RoadMark[] = [];
  spawnTimer: number = 0;

  // 计分
  score: number = 0;
  highScore: number = 0;
  distance: number = 0; // 米
  overtakeCount: number = 0;

  // 撞车抖动
  crashShake: number = 0;

  // 原版精灵图
  carImages: ImageBitmap[] = [];
  private trafficColors: string[] = ['#c0392b', '#2980b9', '#27ae60', '#f39c12', '#8e44ad', '#16a085'];

  init(width: number, height: number): void {
    this.width = width;
    this.height = height;
    this.roadWidth = Math.min(width * 0.88, 520);
    this.roadLeft = (width - this.roadWidth) / 2;
    this.laneWidth = this.roadWidth / LANE_COUNT;
    this.carWidth = this.laneWidth * 0.62;
    this.carHeight = this.carWidth * 1.9;
    this.playerY = height - this.carHeight - height * 0.12;
    this.resetMarks();
  }

  private resetMarks(): void {
    this.marks = [];
    const gap = 90;
    let y = -gap;
    while (y < this.height + gap) {
      this.marks.push(new RoadMark(y));
      y += gap;
    }
  }

  laneCenterX(lane: number): number {
    return this.roadLeft + this.laneWidth * lane + this.laneWidth / 2;
  }

  start(): void {
    this.state = GameState.PLAYING;
    this.playerLane = 1;
    this.playerX = this.laneCenterX(this.playerLane);
    this.speed = this.baseSpeed;
    this.nitro = 100;
    this.nitroActive = false;
    this.traffic = [];
    this.spawnTimer = 0;
    this.score = 0;
    this.distance = 0;
    this.overtakeCount = 0;
    this.crashShake = 0;
    this.resetMarks();
  }

  moveLeft(): void {
    if (this.state !== GameState.PLAYING) {
      return;
    }
    if (this.playerLane > 0) {
      this.playerLane--;
    }
  }

  moveRight(): void {
    if (this.state !== GameState.PLAYING) {
      return;
    }
    if (this.playerLane < LANE_COUNT - 1) {
      this.playerLane++;
    }
  }

  setNitro(active: boolean): void {
    this.nitroActive = active;
  }

  setCarImages(imgs: ImageBitmap[]): void {
    this.carImages = imgs;
  }

  /** 每帧更新，dt 单位秒；返回 true 表示本帧发生撞车 */
  update(dt: number): boolean {
    if (this.state !== GameState.PLAYING) {
      if (this.crashShake > 0) {
        this.crashShake = Math.max(0, this.crashShake - dt * 30);
      }
      return false;
    }
    if (dt > 0.1) {
      dt = 0.1;
    }

    // 速度：随时间缓慢提升 + 氮气
    let targetSpeed = Math.min(this.maxSpeed, this.baseSpeed + this.distance * 0.35);
    if (this.nitroActive && this.nitro > 0) {
      targetSpeed *= 1.6;
      this.nitro = Math.max(0, this.nitro - dt * 30);
      if (this.nitro <= 0) {
        this.nitroActive = false;
      }
    } else {
      this.nitro = Math.min(100, this.nitro + dt * 8);
    }
    this.speed += (targetSpeed - this.speed) * Math.min(1, dt * 3);

    // 里程与分数
    this.distance += this.speed * dt * 0.05; // 换算成"米"
    this.score = Math.floor(this.distance) + this.overtakeCount * 50;

    // 玩家横向平滑移动
    const targetX = this.laneCenterX(this.playerLane);
    this.playerX += (targetX - this.playerX) * Math.min(1, dt * 12);

    // 路面标线滚动
    const scroll = this.speed * dt;
    for (let i = 0; i < this.marks.length; i++) {
      this.marks[i].y += scroll;
      if (this.marks[i].y > this.height + 45) {
        this.marks[i].y -= this.marks.length * 90;
      }
    }

    // 生成车流
    this.spawnTimer -= dt;
    if (this.spawnTimer <= 0) {
      this.spawnTraffic();
      const difficulty = Math.min(1, this.distance / 3000);
      this.spawnTimer = 1.1 - difficulty * 0.55 + Math.random() * 0.4;
    }

    // 车流移动与碰撞
    let crashed = false;
    const px = this.playerX;
    const py = this.playerY;
    for (let i = this.traffic.length - 1; i >= 0; i--) {
      const car = this.traffic[i];
      car.y += (this.speed - car.speed) * dt;
      if (car.y > this.height + this.carHeight) {
        this.traffic.splice(i, 1);
        continue;
      }
      // 超车判定
      if (!car.passed && car.y > py + this.carHeight) {
        car.passed = true;
        this.overtakeCount++;
      }
      // AABB 碰撞（略缩小判定盒，手感更好）
      const cx = this.laneCenterX(car.lane);
      const shrinkW = this.carWidth * 0.78;
      const shrinkH = this.carHeight * 0.88;
      if (Math.abs(cx - px) < shrinkW && Math.abs(car.y - py) < shrinkH) {
        crashed = true;
      }
    }

    if (crashed) {
      this.state = GameState.GAME_OVER;
      this.crashShake = 12;
      if (this.score > this.highScore) {
        this.highScore = this.score;
      }
    }
    return crashed;
  }

  private spawnTraffic(): void {
    // 随机选择车道，但保证至少留一条可通行车道
    const occupied: boolean[] = [false, false, false, false];
    for (let i = 0; i < this.traffic.length; i++) {
      if (this.traffic[i].y < this.carHeight * 2.5) {
        occupied[this.traffic[i].lane] = true;
      }
    }
    const free: number[] = [];
    for (let l = 0; l < LANE_COUNT; l++) {
      if (!occupied[l]) {
        free.push(l);
      }
    }
    if (free.length <= 1) {
      return; // 保证至少一条空道
    }
    const lane = free[Math.floor(Math.random() * free.length)];
    const carSpeed = this.speed * (0.35 + Math.random() * 0.25);
    const color = this.trafficColors[Math.floor(Math.random() * this.trafficColors.length)];
    const trafficImgCount = this.carImages.length - 1;
    const imgIndex = trafficImgCount > 0 ? 1 + Math.floor(Math.random() * trafficImgCount) : -1;
    this.traffic.push(new TrafficCar(lane, -this.carHeight * 1.5, carSpeed, color, imgIndex));
  }

  // ==================== 渲染 ====================

  render(ctx: CanvasRenderingContext2D): void {
    ctx.save();
    if (this.crashShake > 0) {
      ctx.translate((Math.random() - 0.5) * this.crashShake, (Math.random() - 0.5) * this.crashShake);
    }

    // 背景（路两侧）
    ctx.fillStyle = '#0d1b0d';
    ctx.fillRect(0, 0, this.width, this.height);

    // 路面
    ctx.fillStyle = '#2b2b33';
    ctx.fillRect(this.roadLeft, 0, this.roadWidth, this.height);

    // 路肩
    ctx.fillStyle = '#e8e6df';
    ctx.fillRect(this.roadLeft - 6, 0, 6, this.height);
    ctx.fillRect(this.roadLeft + this.roadWidth, 0, 6, this.height);

    // 车道虚线
    ctx.fillStyle = '#d9d5c8';
    for (let l = 1; l < LANE_COUNT; l++) {
      const x = this.roadLeft + this.laneWidth * l;
      for (let i = 0; i < this.marks.length; i++) {
        ctx.fillRect(x - 2, this.marks[i].y, 4, 42);
      }
    }

    // 车流
    for (let i = 0; i < this.traffic.length; i++) {
      const car = this.traffic[i];
      this.drawCar(ctx, this.laneCenterX(car.lane), car.y, car.color, false, car.imgIndex);
    }

    // 玩家（氮气时带火焰尾焰）
    if (this.nitroActive && this.nitro > 0) {
      this.drawFlame(ctx, this.playerX, this.playerY + this.carHeight);
    }
    this.drawCar(ctx, this.playerX, this.playerY, '#e8e8f0', true, 0);

    ctx.restore();
  }

  private drawCar(ctx: CanvasRenderingContext2D, cx: number, y: number, color: string, isPlayer: boolean, imgIndex: number): void {
    const w = this.carWidth;
    const h = this.carHeight;
    const x = cx - w / 2;

    // 优先使用原版精灵图
    if (imgIndex >= 0 && imgIndex < this.carImages.length) {
      const img = this.carImages[imgIndex];
      if (img && img.width > 0) {
        ctx.drawImage(img, x, y, w, h);
        return;
      }
    }

    // 回退：程序化绘制
    ctx.fillStyle = color;
    this.roundRect(ctx, x, y, w, h, w * 0.18);
    ctx.fill();

    // 车窗
    ctx.fillStyle = 'rgba(20,26,40,0.85)';
    this.roundRect(ctx, x + w * 0.14, y + h * 0.16, w * 0.72, h * 0.2, 4);
    ctx.fill();
    this.roundRect(ctx, x + w * 0.14, y + h * 0.62, w * 0.72, h * 0.16, 4);
    ctx.fill();

    // 车灯
    if (isPlayer) {
      ctx.fillStyle = '#ffe066';
      ctx.fillRect(x + w * 0.08, y + 2, w * 0.2, 5);
      ctx.fillRect(x + w * 0.72, y + 2, w * 0.2, 5);
      ctx.fillStyle = '#1d6fd1';
      ctx.fillRect(cx - w * 0.07, y + h * 0.05, w * 0.14, h * 0.9);
    } else {
      ctx.fillStyle = '#ff5544';
      ctx.fillRect(x + w * 0.08, y + h - 7, w * 0.2, 5);
      ctx.fillRect(x + w * 0.72, y + h - 7, w * 0.2, 5);
    }
  }

  private drawFlame(ctx: CanvasRenderingContext2D, cx: number, topY: number): void {
    const w = this.carWidth * 0.4;
    const len = this.carHeight * (0.4 + Math.random() * 0.25);
    ctx.fillStyle = 'rgba(255,140,0,0.85)';
    ctx.beginPath();
    ctx.moveTo(cx - w / 2, topY);
    ctx.lineTo(cx + w / 2, topY);
    ctx.lineTo(cx, topY + len);
    ctx.closePath();
    ctx.fill();
    ctx.fillStyle = 'rgba(80,180,255,0.9)';
    ctx.beginPath();
    ctx.moveTo(cx - w / 4, topY);
    ctx.lineTo(cx + w / 4, topY);
    ctx.lineTo(cx, topY + len * 0.55);
    ctx.closePath();
    ctx.fill();
  }

  private roundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number): void {
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.arcTo(x + w, y, x + w, y + h, r);
    ctx.arcTo(x + w, y + h, x, y + h, r);
    ctx.arcTo(x, y + h, x, y, r);
    ctx.arcTo(x, y, x + w, y, r);
    ctx.closePath();
  }

  getSpeedKmh(): number {
    return Math.floor(this.speed * 0.32);
  }
}
