import { EEGDataStore } from '../store/EEGDataStore';
import { StorageService } from '../service/StorageService';
import { BlinkDetector } from '../detectors/BlinkDetector';
import { SessionService } from '../service/SessionService';

const store = EEGDataStore.getInstance();
const sessionService = SessionService.getInstance();

// ============================================================
//  常量
// ============================================================
const VW = 360;          // 虚拟画布宽度
const VH = 640;          // 虚拟画布高度
const CTRL_EMA = 0.50;   // 控制指令 EMA：模拟数据帧到达后快速跟随（数据源约 150~300ms/帧）
const PLANE_R = 14;      // 飞机碰撞半径
const OBS_W = 44;        // 障碍物宽度
const GAP_H = 160;       // 通道高度
const BULLET_V = 7;      // 子弹速度
const BULLET_CD = 13;    // 射击冷却 (tick)
const INVIN_TICKS = 30;  // 受伤无敌时间

// 操控灵敏度参数（针对单通道脑环优化）
const DEAD_ZONE = 3;       // 死区半宽（专注度 50±3 内不移动，越小越灵敏）
const ATT_SPEED = 0.18;    // 专注移动速度系数（越大反应越快）
const EMA_PLANE = 0.45;    // 飞机 EMA 新值权重（越大越跟手）
const SCROLL_BASE = 2.2;   // 基础卷轴速度（略降，给脑控留更多反应时间）
const SCROLL_MED = 0.035;  // 冥想影响卷轴系数
const SPAWN_GAP_BASE = 50;   // 基础间隔（最小）
const SPAWN_GAP_ATT = 1.0;    // 注意力偏离加成（偏离50越多→间隔越宽）
const SPAWN_GAP_MED = 0.5;    // 冥想加成（越放松→间隔越宽）
const SPAWN_BIAS = 260;    // 通道中心相对飞机位置的随机偏移范围（±130，降低单通道延迟导致的撞墙）

// ============================================================
//  游戏对象
// ============================================================
class Obstacle {
  x: number;
  topH: number;
  passed: boolean = false;
  constructor(x: number, topH: number) { this.x = x; this.topH = topH; }
}

class Bullet {
  x: number; y: number;
  constructor(x: number, y: number) { this.x = x; this.y = y; }
}

class Particle {
  x: number; y: number;
  vx: number; vy: number;
  life: number;
  maxLife: number;
  color: string;
  size: number;
  kind: number; // 0=普通 1=引擎尾迹 2=环境浮尘 3=闪光
  constructor(x: number, y: number, vx: number, vy: number, life: number, color: string, size: number, kind: number = 0) {
    this.x = x; this.y = y;
    this.vx = vx; this.vy = vy;
    this.life = life;
    this.maxLife = life;
    this.color = color;
    this.size = size;
    this.kind = kind;
  }
}

class Collectible {
  x: number; y: number;
  kind: number;
  constructor(x: number, y: number, kind: number) {
    this.x = x; this.y = y;
    this.kind = kind;
  }
}

// ============================================================
//  页面组件
// ============================================================
@Component
export struct GamePage {
  // ---- 画布 ----
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D();
  private ready: boolean = false;

  // ---- 游戏状态 ----
  @State score: number = 0;
  @State bestScore: number = 0;
  @State lives: number = 3;
  @State state: number = 0;       // 0=待机 1=游戏中 2=结束
  @State attBar: number = 50;
  @State medBar: number = 50;
  @State flashBlink: boolean = false;

  // ---- 内部状态 ----
  private planeY: number = VH / 2;
  private smoothAtt: number = 50;
  private smoothMed: number = 50;
  private obstacles: Obstacle[] = [];
  private bullets: Bullet[] = [];
  private particles: Particle[] = [];
  private ambients: Particle[] = [];    // 环境浮尘
  private pickups: Collectible[] = [];
  private stars: number[][] = [];       // [x, y, speed, alpha]
  private tick: number = 0;
  private trailTimer: number = 0;       // 引擎尾迹发射计时
  private obsTimer: number = 0;
  private bulletCD: number = 0;
  private invinTimer: number = 0;
  private totalDist: number = 0;
  private blinkDetector: BlinkDetector = new BlinkDetector();
  private blinkLastFedRawCount: number = 0;
  private shakeMag: number = 0;
  private planePulse: number = 0;
  private lastMoveDir: number = 0;
  private scrollV: number = SCROLL_BASE;

  private loopTimer: number = -1;

  /** 退出游戏：通知 GameHubPage 收起游戏视图 */
  private exitGame(): void {
    AppStorage.set('hub_reset', Date.now());
  }

  aboutToAppear(): void {
    this.bestScore = StorageService.getInstance().getNumber('flight_best', 0);
    this.initStars();
    this.loopTimer = setInterval(() => {
      this.gameLoop();
    }, 50);
  }

  aboutToDisappear(): void {
    if (this.loopTimer >= 0) {
      clearInterval(this.loopTimer);
      this.loopTimer = -1;
    }
  }

  // ==================== 游戏循环 ====================

  private gameLoop(): void {
    this.tick++;

    // 读取脑波数据
    const att = store.latestData.att;
    const med = store.latestData.med;

    // 控制指令 EMA：数据帧一到就快速驱动飞机，不再叠两层慢平滑
    this.smoothAtt = this.smoothAtt * (1 - CTRL_EMA) + att * CTRL_EMA;
    this.smoothMed = this.smoothMed * (1 - CTRL_EMA) + med * CTRL_EMA;
    this.attBar = Math.round(this.smoothAtt);
    this.medBar = Math.round(this.smoothMed);

    // 眨眼检测 (使用统一的自适应 IQR 算法)：
    // 消费 rawHistory 里新增的原始波形样本，过滤无效值，
    // 避免固件帧缺 raw 字段时把 undefined 喂进检测器导致眨眼永远不触发
    const blinkHist = store.rawHistory;
    if (this.blinkLastFedRawCount > blinkHist.length) {
      this.blinkLastFedRawCount = 0;
    }
    let blinked = false;
    for (let bi = this.blinkLastFedRawCount; bi < blinkHist.length; bi++) {
      const bv = blinkHist[bi];
      if (typeof bv === 'number' && isFinite(bv)) {
        if (this.blinkDetector.feed(bv)) {
          blinked = true;
        }
      }
    }
    this.blinkLastFedRawCount = blinkHist.length;
    if (blinked) {
      sessionService.incrementBlinks();
      if (this.state === 1 && this.bulletCD <= 0) {
        this.shoot();
      }
      this.flashBlink = true;
      setTimeout(() => { this.flashBlink = false; }, 120);
    }

    // ---- 状态机 ----
    if (this.state === 0) {
      this.planeY = VH / 2 + Math.sin(this.tick * 0.04) * 18;
      if (this.ready) this.draw();
      return;
    }
    if (this.state === 2) {
      this.updateParticles();
      if (this.shakeMag > 0) this.shakeMag *= 0.88;
      if (this.ready) this.draw();
      return;
    }

    // === 游戏中 ===

    // 无敌计时
    if (this.invinTimer > 0) this.invinTimer--;

    // 飞机移动：专注度偏离50%越多移动越快，DEAD_ZONE 内为死区
    const attDelta = this.smoothAtt - 50;
    const moveDir = Math.abs(attDelta) < DEAD_ZONE ? 0 : (attDelta > 0 ? 1 : -1);
    const moveMag = Math.max(0, Math.abs(attDelta) - DEAD_ZONE);
    const speed = moveDir * moveMag * ATT_SPEED;
    const rawTarget = this.planeY - speed;
    const clampedTarget = Math.max(PLANE_R + 4, Math.min(VH - PLANE_R - 4, rawTarget));
    this.planeY = this.planeY * (1 - EMA_PLANE) + clampedTarget * EMA_PLANE;

    // 飞机脉冲（跨越死区边界时触发强脉冲）
    if (moveDir !== 0 && this.lastMoveDir === 0) {
      this.planePulse = 1.0;
    }
    if (moveDir !== 0) {
      this.planePulse = Math.max(this.planePulse - 0.04, 0.25);
    } else {
      this.planePulse = Math.max(0, this.planePulse - 0.07);
    }
    this.lastMoveDir = moveDir;

    // 卷轴速度：冥想度越高越慢（更放松=更易）
    this.scrollV = SCROLL_BASE + (100 - this.smoothMed) * SCROLL_MED;
    this.totalDist += this.scrollV;
    this.score = Math.floor(this.totalDist / 10);

    // 引擎尾迹
    this.trailTimer++;
    if (this.trailTimer >= 2) {
      this.trailTimer = 0;
      const tx = 52 - PLANE_R * 0.7;
      const ty = this.planeY + (Math.random() - 0.5) * 6;
      this.particles.push(new Particle(
        tx, ty,
        -0.5 - Math.random() * 1.5, (Math.random() - 0.5) * 0.6,
        0.4 + Math.random() * 0.35,
        Math.random() < 0.5 ? '#00D4FF' : '#00e6ff',
        1.5 + Math.random() * 3, 1
      ));
    }

    // 环境浮尘更新
    for (let i = this.ambients.length - 1; i >= 0; i--) {
      const a = this.ambients[i];
      a.x += a.vx - this.scrollV * 0.3;
      a.y += a.vy;
      a.life -= 0.001;
      if (a.y < -10 || a.x < -10 || a.x > VW + 10 || a.life <= 0) {
        a.x = VW + Math.random() * 60;
        a.y = Math.random() * VH;
        a.life = 0.5 + Math.random() * 0.5;
      }
    }

    // 子弹冷却
    if (this.bulletCD > 0) this.bulletCD--;

    // 障碍物生成
    this.obsTimer++;
    const attDev = Math.abs(this.smoothAtt - 50);
    const spawnGap = SPAWN_GAP_BASE + attDev * SPAWN_GAP_ATT + this.smoothMed * SPAWN_GAP_MED;
    if (this.obsTimer >= spawnGap) {
      this.obsTimer = 0;
      // 通道中心偏向飞机当前位置：单通道脑环有延迟/误差时也能轻松躲开
      const gapCenter = this.planeY + (Math.random() - 0.5) * SPAWN_BIAS;
      const gapY = Math.max(80, Math.min(VH - GAP_H - 80, gapCenter - GAP_H / 2));
      this.obstacles.push(new Obstacle(VW + OBS_W, gapY));

      // 30% 概率在通道中间生成金币
      if (Math.random() < 0.3) {
        this.pickups.push(new Collectible(VW + OBS_W + 30, gapY + GAP_H / 2, 0));
      }
    }

    // 更新障碍物
    for (let i = this.obstacles.length - 1; i >= 0; i--) {
      this.obstacles[i].x -= this.scrollV;
      if (this.obstacles[i].x < -OBS_W - 30) this.obstacles.splice(i, 1);
    }

    // 更新子弹
    for (let i = this.bullets.length - 1; i >= 0; i--) {
      this.bullets[i].x += BULLET_V;
      if (this.bullets[i].x > VW + 20) this.bullets.splice(i, 1);
    }

    // 更新金币
    for (let i = this.pickups.length - 1; i >= 0; i--) {
      this.pickups[i].x -= this.scrollV;
      if (this.pickups[i].x < -20) this.pickups.splice(i, 1);
    }

    // 更新粒子
    this.updateParticles();

    // 抖动衰减
    if (this.shakeMag > 0) this.shakeMag *= 0.85;

    // ---- 碰撞检测 ----
    if (this.invinTimer <= 0) {
      const px = 52;
      const py = this.planeY;
      for (const obs of this.obstacles) {
        if (px + PLANE_R > obs.x && px - PLANE_R < obs.x + OBS_W) {
          if (py - PLANE_R < obs.topH || py + PLANE_R > obs.topH + GAP_H) {
            this.onHit();
            break;
          }
        }
      }
    }

    // 金币拾取
    const px = 52;
    const py = this.planeY;
    for (let i = this.pickups.length - 1; i >= 0; i--) {
      const p = this.pickups[i];
      const dx = px - p.x;
      const dy = py - p.y;
      if (dx * dx + dy * dy < 400) {
        this.score += 50;
        this.spawnParticles(p.x, p.y, '#FFD700', 8);
        this.pickups.splice(i, 1);
      }
    }

    // 绘制
    if (this.ready) this.draw();
  }

  // ==================== 动作 ====================

  private shoot(): void {
    this.bulletCD = BULLET_CD;
    this.bullets.push(new Bullet(62, this.planeY - 7));
    this.bullets.push(new Bullet(62, this.planeY + 7));
  }

  private onHit(): void {
    this.lives--;
    this.shakeMag = 14;
    this.invinTimer = INVIN_TICKS;
    this.spawnParticles(52, this.planeY, '#FF6B6B', 16);
    if (this.lives <= 0) {
      this.state = 2;
      if (this.score > this.bestScore) {
        this.bestScore = this.score;
        StorageService.getInstance().setNumber('flight_best', this.score);
      }
      // 多色爆炸
      this.spawnParticles(52, this.planeY, '#FF4444', 18);
      this.spawnParticles(52, this.planeY, '#FFD700', 10);
      this.spawnParticles(52, this.planeY, '#FF6B6B', 14);
      this.spawnParticles(52, this.planeY, '#FFFFFF', 6);
    }
  }

  private startGame(): void {
    this.state = 1;
    this.score = 0;
    this.lives = 3;
    this.planeY = VH / 2;
    this.obstacles = [];
    this.bullets = [];
    this.particles = [];
    this.pickups = [];
    this.totalDist = 0;
    this.obsTimer = 0;
    this.trailTimer = 0;
    this.bulletCD = 0;
    this.invinTimer = INVIN_TICKS;
    this.shakeMag = 0;
    this.smoothAtt = 50;
    this.smoothMed = 50;
    this.blinkDetector.reset();
  }

  private spawnParticles(x: number, y: number, color: string, count: number): void {
    for (let i = 0; i < count; i++) {
      const a = Math.random() * Math.PI * 2;
      const s = 1.2 + Math.random() * 3.5;
      const kind = i < count * 0.3 ? 3 : 0; // 30% 闪光粒子
      this.particles.push(new Particle(x, y, Math.cos(a) * s, Math.sin(a) * s,
        0.6 + Math.random() * 0.6, color, 1.5 + Math.random() * 3.5, kind));
    }
  }

  private updateParticles(): void {
    for (let i = this.particles.length - 1; i >= 0; i--) {
      const p = this.particles[i];
      p.x += p.vx;
      p.y += p.vy;
      p.life -= 0.028;
      if (p.life <= 0) this.particles.splice(i, 1);
    }
  }

  private initStars(): void {
    for (let i = 0; i < 70; i++) {
      this.stars.push([Math.random() * VW, Math.random() * VH, 0.4 + Math.random() * 1.6, Math.random()]);
    }
    // 初始化环境浮尘
    for (let i = 0; i < 18; i++) {
      this.ambients.push(new Particle(
        Math.random() * VW, Math.random() * VH,
        (Math.random() - 0.5) * 0.3, (Math.random() - 0.5) * 0.2 - 0.15,
        0.5 + Math.random() * 0.5,
        ['#74B9FF', '#6CBE8A', '#F5A623', '#E87461'][Math.floor(Math.random() * 4)],
        0.6 + Math.random() * 1.4,
        2
      ));
    }
  }

  // ==================== 绘制 ====================

  private draw(): void {
    const ctx = this.ctx;
    const cw = ctx.width;
    const ch = ctx.height;
    const sx = cw / VW;
    const sy = ch / VH;

    // 抖动偏移
    const ox = this.shakeMag * (Math.random() - 0.5) * 2;
    const oy = this.shakeMag * (Math.random() - 0.5) * 2;

    ctx.clearRect(0, 0, cw, ch);
    ctx.save();
    ctx.scale(sx, sy);
    ctx.translate(ox, oy);

    this.drawBackground(ctx);
    this.drawStars(ctx);
    this.drawSpeedLines(ctx);
    this.drawAmbients(ctx);
    this.drawPickups(ctx);
    this.drawObstacles(ctx);
    this.drawBullets(ctx);
    this.drawParticles(ctx);
    this.drawPlane(ctx);
    this.drawHUD(ctx);
    this.drawOverlay(ctx);

    ctx.restore();
  }

  private drawBackground(ctx: CanvasRenderingContext2D): void {
    const g = ctx.createLinearGradient(0, 0, 0, VH);
    g.addColorStop(0, '#070720');
    g.addColorStop(0.45, '#0f1a3a');
    g.addColorStop(1, '#1a1040');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, VW, VH);

    // 网格线（透视感）
    ctx.strokeStyle = 'rgba(255,255,255,0.03)';
    ctx.lineWidth = 0.5;
    for (let y = 0; y < VH; y += 48) {
      ctx.beginPath();
      ctx.moveTo(0, y);
      ctx.lineTo(VW, y);
      ctx.stroke();
    }
    for (let x = (this.totalDist % 80); x < VW; x += 80) {
      ctx.beginPath();
      ctx.moveTo(x, 0);
      ctx.lineTo(x - 40, VH);
      ctx.stroke();
    }
  }

  private drawStars(ctx: CanvasRenderingContext2D): void {
    for (const s of this.stars) {
      const sx = ((s[0] - this.totalDist * s[2] * 0.25) % VW + VW) % VW;
      const a = 0.25 + s[3] * 0.65;
      ctx.fillStyle = `rgba(255,255,255,${a})`;
      ctx.fillRect(sx, s[1], 1.5, 1.5);
    }
  }

  private drawSpeedLines(ctx: CanvasRenderingContext2D): void {
    const speedRatio = (this.scrollV - SCROLL_BASE) / (100 * SCROLL_MED);
    const intensity = Math.min(0.55, 0.08 + speedRatio * 0.47);
    if (intensity <= 0.08) return;
    const count = Math.floor(6 + speedRatio * 14);
    ctx.globalAlpha = intensity;
    ctx.strokeStyle = '#ffffff';
    ctx.lineWidth = 0.5;
    for (let i = 0; i < count; i++) {
      const seed = i * 137.5;
      const x = ((seed * 73 + this.totalDist * (1.2 + (seed % 7) * 0.3)) % (VW + 60)) - 30;
      const y = 60 + (seed * 211) % (VH - 120);
      const len = 12 + (seed % 28);
      ctx.beginPath();
      ctx.moveTo(x, y);
      ctx.lineTo(x + len, y);
      ctx.stroke();
    }
    ctx.globalAlpha = 1;
  }

  private drawObstacles(ctx: CanvasRenderingContext2D): void {
    const gradTop = ctx.createLinearGradient(0, 0, OBS_W, 0);
    gradTop.addColorStop(0, '#d63031');
    gradTop.addColorStop(0.5, '#e17055');
    gradTop.addColorStop(1, '#d63031');

    const gradBot = ctx.createLinearGradient(0, 0, OBS_W, 0);
    gradBot.addColorStop(0, '#d63031');
    gradBot.addColorStop(0.5, '#e17055');
    gradBot.addColorStop(1, '#d63031');

    for (const obs of this.obstacles) {
      const x = obs.x;
      const th = obs.topH;
      const by = th + GAP_H;

      // 顶部柱子
      ctx.fillStyle = gradTop;
      ctx.fillRect(x, 0, OBS_W, th);
      // 底部发光边
      ctx.fillStyle = '#ff7675';
      ctx.fillRect(x, th - 3, OBS_W, 3);

      // 底部柱子
      ctx.fillStyle = gradBot;
      ctx.fillRect(x, by, OBS_W, VH - by);
      // 顶部发光边
      ctx.fillStyle = '#ff7675';
      ctx.fillRect(x, by, OBS_W, 3);
    }
  }

  private drawBullets(ctx: CanvasRenderingContext2D): void {
    for (const b of this.bullets) {
      // 发光
      ctx.fillStyle = 'rgba(0,230,255,0.35)';
      ctx.beginPath();
      ctx.arc(b.x, b.y, 6, 0, Math.PI * 2);
      ctx.fill();
      // 核心
      ctx.fillStyle = '#00e6ff';
      ctx.beginPath();
      ctx.arc(b.x, b.y, 2.5, 0, Math.PI * 2);
      ctx.fill();
      // 尾迹
      ctx.fillStyle = 'rgba(0,230,255,0.18)';
      ctx.fillRect(b.x - 8, b.y - 1.5, 8, 3);
    }
  }

  private drawAmbients(ctx: CanvasRenderingContext2D): void {
    for (const a of this.ambients) {
      ctx.globalAlpha = a.life * 0.35;
      ctx.fillStyle = a.color;
      ctx.beginPath();
      ctx.arc(a.x, a.y, a.size * a.life, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  }

  private drawPickups(ctx: CanvasRenderingContext2D): void {
    for (const p of this.pickups) {
      if (p.kind === 0) {
        // 金币：旋转效果用缩放模拟
        const s = 1 + Math.sin(this.tick * 0.2 + p.x) * 0.15;
        ctx.fillStyle = '#FFD700';
        ctx.beginPath();
        ctx.arc(p.x, p.y, 7 * s, 0, Math.PI * 2);
        ctx.fill();
        ctx.fillStyle = '#FFF8B0';
        ctx.beginPath();
        ctx.arc(p.x - 2, p.y - 2, 2.5 * s, 0, Math.PI * 2);
        ctx.fill();
      }
    }
  }

  private drawParticles(ctx: CanvasRenderingContext2D): void {
    for (const p of this.particles) {
      const alpha = p.life / p.maxLife;
      if (p.kind === 1) {
        // 引擎尾迹：水平拉长的光点
        ctx.globalAlpha = alpha * 0.7;
        ctx.fillStyle = p.color;
        ctx.beginPath();
        ctx.ellipse(p.x, p.y, p.size * alpha, p.size * 0.4 * alpha, 0, 0, Math.PI * 2);
        ctx.fill();
      } else if (p.kind === 3) {
        // 闪光：带有辉光
        ctx.globalAlpha = alpha;
        const glow = ctx.createRadialGradient(p.x, p.y, 0, p.x, p.y, p.size * 2);
        glow.addColorStop(0, p.color);
        glow.addColorStop(1, 'rgba(255,255,255,0)');
        ctx.fillStyle = glow;
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.size * 2 * alpha, 0, Math.PI * 2);
        ctx.fill();
      } else {
        // 普通爆炸粒子
        ctx.globalAlpha = alpha;
        ctx.fillStyle = p.color;
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.size * alpha, 0, Math.PI * 2);
        ctx.fill();
      }
    }
    ctx.globalAlpha = 1;
  }

  private drawPlane(ctx: CanvasRenderingContext2D): void {
    const cx = 52;
    const cy = this.planeY;

    // 无敌闪烁
    if (this.invinTimer > 0 && Math.floor(this.invinTimer / 3) % 2 === 0) return;

    ctx.save();
    ctx.translate(cx, cy);

    // 引擎光焰
    const glowG = ctx.createRadialGradient(-PLANE_R * 0.7, 0, 1, -PLANE_R * 0.7, 0, PLANE_R * 0.9);
    glowG.addColorStop(0, 'rgba(0,200,255,0.55)');
    glowG.addColorStop(1, 'rgba(0,200,255,0)');
    ctx.fillStyle = glowG;
    ctx.beginPath();
    ctx.arc(-PLANE_R * 0.7, 0, PLANE_R * 0.9, 0, Math.PI * 2);
    ctx.fill();

    // 机身
    ctx.fillStyle = '#00D4FF';
    ctx.beginPath();
    ctx.moveTo(PLANE_R * 0.7, 0);
    ctx.lineTo(-PLANE_R * 0.3, -PLANE_R * 0.35);
    ctx.lineTo(-PLANE_R * 0.6, -PLANE_R * 0.18);
    ctx.lineTo(-PLANE_R * 0.6, PLANE_R * 0.18);
    ctx.lineTo(-PLANE_R * 0.3, PLANE_R * 0.35);
    ctx.closePath();
    ctx.fill();

    // 机翼强调
    ctx.fillStyle = '#0099CC';
    ctx.beginPath();
    ctx.moveTo(0, -PLANE_R * 0.08);
    ctx.lineTo(-PLANE_R * 0.5, -PLANE_R * 0.5);
    ctx.lineTo(PLANE_R * 0.15, -PLANE_R * 0.5);
    ctx.lineTo(0, -PLANE_R * 0.08);
    ctx.closePath();
    ctx.fill();
    ctx.beginPath();
    ctx.moveTo(0, PLANE_R * 0.08);
    ctx.lineTo(-PLANE_R * 0.5, PLANE_R * 0.5);
    ctx.lineTo(PLANE_R * 0.15, PLANE_R * 0.5);
    ctx.lineTo(0, PLANE_R * 0.08);
    ctx.closePath();
    ctx.fill();

    // 驾驶舱
    ctx.fillStyle = '#FFFFFF';
    ctx.beginPath();
    ctx.arc(PLANE_R * 0.05, 0, PLANE_R * 0.18, 0, Math.PI * 2);
    ctx.fill();

    // 脉冲环（跨越死区边界时显示）
    if (this.planePulse > 0.02) {
      ctx.strokeStyle = `rgba(0,230,255,${this.planePulse * 0.45})`;
      ctx.lineWidth = 2.5 * this.planePulse;
      ctx.beginPath();
      ctx.arc(-PLANE_R * 0.1, 0, PLANE_R * (1.15 + this.planePulse * 0.7), 0, Math.PI * 2);
      ctx.stroke();
    }

    ctx.restore();
  }

  // ==================== HUD — BCI 实验面板 ====================

  private drawHUD(ctx: CanvasRenderingContext2D): void {
    const attDelta = this.smoothAtt - 50;
    const inDead = Math.abs(attDelta) < DEAD_ZONE;
    const stability = Math.round(100 - Math.abs(attDelta) * 1.2);

    // ==== 顶栏：生命 + 分数 ====
    ctx.fillStyle = 'rgba(0,0,20,0.55)';
    ctx.fillRect(0, 0, VW, 84);
    // 底部发光线
    ctx.strokeStyle = 'rgba(96,165,250,0.15)';
    ctx.lineWidth = 0.5;
    ctx.beginPath(); ctx.moveTo(0, 84); ctx.lineTo(VW, 84); ctx.stroke();

    // 生命（爱心 64px）
    ctx.fillStyle = '#F87171';
    ctx.font = '64px sans-serif';
    ctx.textAlign = 'left';
    let hearts = '';
    for (let i = 0; i < this.lives; i++) hearts += '♥';
    ctx.fillText(hearts, 12, 70);

    // 最佳分
    ctx.fillStyle = '#8B949E';
    ctx.font = '44px sans-serif';
    ctx.textAlign = 'left';
    ctx.fillText('最佳 ' + this.bestScore.toString(), 215, 70);

    // 分数
    ctx.fillStyle = '#E6EDF3';
    ctx.font = 'bold 34px monospace';
    ctx.textAlign = 'center';
    ctx.fillText(`${this.score}`, VW / 2, 70);

    // ==== 底栏：BCI 反馈面板 ====
    ctx.fillStyle = 'rgba(0,0,20,0.55)';
    ctx.fillRect(0, VH - 106, VW, 106);
    ctx.strokeStyle = 'rgba(96,165,250,0.12)';
    ctx.lineWidth = 0.5;
    ctx.beginPath(); ctx.moveTo(0, VH - 106); ctx.lineTo(VW, VH - 106); ctx.stroke();

    // 左侧卡片：专注度
    const cardY = VH - 100;
    const cardH = 82;
    const cardW = 108;
    this.drawBCICard(ctx, 8, cardY, cardW, cardH,
      '专注度', `${this.attBar}%`, '#4ADE80', 3);
    // 中间卡片：稳定度
    this.drawBCICard(ctx, 122, cardY, cardW, cardH,
      '稳定度', `${stability}%`, '#60A5FA', 3);
    // 中间卡片2：冥想度
    this.drawBCICard(ctx, 236, cardY, cardW, cardH,
      '冥想度', `${this.medBar}%`, '#A78BFA', 3);

    // 第二行：方向指示器（简化，横排一行）
    const dirX = 10;
    const dirY = VH - 8;
    const dirW = 150;
    ctx.textAlign = 'center';
    ctx.fillStyle = inDead ? '#484F58' : (attDelta > 0 ? '#4ADE80' : '#60A5FA');
    ctx.font = 'bold 14px sans-serif';
    ctx.fillText((inDead ? '— ' : (attDelta > 0 ? '↑ ' : '↓ ')) + '控制方向', dirX + dirW / 2, dirY);
    // 眨眼提示（右侧）
    ctx.textAlign = 'right';
    ctx.fillStyle = this.flashBlink ? '#4ADE80' : '#484F58';
    ctx.font = this.flashBlink ? 'bold 14px sans-serif' : '13px sans-serif';
    ctx.fillText(this.flashBlink ? '神经脉冲' : '眨眼触发', VW - 10, dirY);

    // 无敌条
    if (this.invinTimer > 0) {
      const invPct = this.invinTimer / INVIN_TICKS;
      ctx.fillStyle = 'rgba(255,255,255,0.06)';
      ctx.fillRect(8, cardY - 6, 248, 2);
      ctx.fillStyle = '#FBBF24';
      ctx.fillRect(8, cardY - 6, 248 * invPct, 2);
    }
  }

  private drawBCICard(ctx: CanvasRenderingContext2D,
                      x: number, y: number, w: number, h: number,
                      label: string, value: string, color: string, scale: number = 1): void {
    ctx.fillStyle = 'rgba(255,255,255,0.03)';
    ctx.strokeStyle = color + '28';
    ctx.lineWidth = 1;
    this.roundRect(ctx, x, y, w, h, 8);
    ctx.fill();
    ctx.stroke();

    ctx.textAlign = 'center';
    ctx.fillStyle = '#6E7681';
    ctx.font = `${Math.round(11 * scale)}px sans-serif`;
    ctx.fillText(label, x + w / 2, y + 24);

    ctx.fillStyle = color;
    ctx.font = `bold ${Math.round(18 * scale)}px monospace`;
    ctx.fillText(value, x + w / 2, y + 70);
  }

  private roundRect(ctx: CanvasRenderingContext2D,
                    x: number, y: number, w: number, h: number, r: number): void {
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.lineTo(x + w - r, y);
    ctx.arcTo(x + w, y, x + w, y + r, r);
    ctx.lineTo(x + w, y + h - r);
    ctx.arcTo(x + w, y + h, x + w - r, y + h, r);
    ctx.lineTo(x + r, y + h);
    ctx.arcTo(x, y + h, x, y + h - r, r);
    ctx.lineTo(x, y + r);
    ctx.arcTo(x, y, x + r, y, r);
    ctx.closePath();
  }

  // ==================== 覆盖层 ====================

  private drawOverlay(ctx: CanvasRenderingContext2D): void {
    if (this.state === 0) {
      // 待机 — 脑机接口实验待命
      ctx.fillStyle = 'rgba(0,0,20,0.72)';
      const ox = 24, oy = VH / 2 - 90, ow = VW - 48, oh = 180;
      this.roundRect(ctx, ox, oy, ow, oh, 16);
      ctx.fill();
      ctx.strokeStyle = 'rgba(96,165,250,0.18)';
      ctx.lineWidth = 1;
      this.roundRect(ctx, ox, oy, ow, oh, 16);
      ctx.stroke();

      ctx.fillStyle = '#E6EDF3';
      ctx.font = 'bold 44px sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText('脑机交互实验', VW / 2, oy + 56);

      ctx.fillStyle = '#8B949E';
      ctx.font = '21px sans-serif';
      ctx.fillText('专注度 ↕ 高度  ·  冥想度 ↕ 速度  ·  眨眼 ↕ 射击', VW / 2, oy + 96);

      ctx.fillStyle = '#60A5FA';
      ctx.font = 'bold 24px sans-serif';
      const blink = Math.sin(Date.now() * 0.005) * 0.3 + 0.7;
      ctx.globalAlpha = blink;
      ctx.fillText('● 点击初始化连接', VW / 2, oy + 146);
      ctx.globalAlpha = 1;
    } else if (this.state === 2) {
      // 结束 — 实验数据报告
      ctx.fillStyle = 'rgba(0,0,20,0.78)';
      const ox = 24, oy = VH / 2 - 110, ow = VW - 48, oh = 220;
      this.roundRect(ctx, ox, oy, ow, oh, 16);
      ctx.fill();
      ctx.strokeStyle = 'rgba(96,165,250,0.18)';
      ctx.lineWidth = 1;
      this.roundRect(ctx, ox, oy, ow, oh, 16);
      ctx.stroke();

      // 评分
      const grade = this.score >= 300 ? 'S' : this.score >= 200 ? 'A' : this.score >= 100 ? 'B' : 'C';
      const gradeColor = this.score >= 300 ? '#FBBF24' : this.score >= 200 ? '#4ADE80' :
        this.score >= 100 ? '#60A5FA' : '#8B949E';
      ctx.fillStyle = gradeColor;
      ctx.font = 'bold 58px sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText(grade + ' 级', VW / 2, oy + 50);

      ctx.fillStyle = '#F87171';
      ctx.font = 'bold 30px sans-serif';
      ctx.fillText('实验终止', VW / 2, oy + 80);

      ctx.fillStyle = '#E6EDF3';
      ctx.font = 'bold 52px monospace';
      ctx.fillText(`${this.score}`, VW / 2, oy + 126);
      ctx.fillStyle = '#8B949E';
      ctx.font = '17px sans-serif';
      ctx.fillText('神经反馈得分', VW / 2, oy + 144);

      ctx.fillStyle = '#6E7681';
      ctx.font = '20px sans-serif';
      ctx.fillText(`历史最佳 ${this.bestScore}`, VW / 2, oy + 168);

      ctx.fillStyle = '#60A5FA';
      ctx.font = 'bold 22px sans-serif';
      ctx.fillText('● 点击重新实验', VW / 2, oy + 200);
    }
  }

  // ==================== UI ====================

  build() {
    Column() {
      // BCI 脑机交互状态栏
      Row() {
        Text('✕')
          .fontSize(15).fontColor($r('app.color.text_secondary'))
          .width(38).height(38).textAlign(TextAlign.Center)
          .borderRadius(12).backgroundColor($r('app.color.card_bg'))
          .border({ width: 0.5, color: $r('app.color.card_border') })
          .onClick(() => { this.exitGame(); })
        Row() {
          Stack() {
            Circle().width(28).height(28)
              .fill($r('app.color.primary_light'))
            Circle().width(8).height(8)
              .fill(store.connected ? $r('app.color.status_online') : $r('app.color.status_danger'))
              .shadow({ radius: 4, color: store.connected ? $r('app.color.shadow_glow_green') : $r('app.color.shadow_glow_red'), offsetX: 0, offsetY: 0 })
          }
          Column() {
            Text(store.connected ? '脑波连接正常' : '脑波未连接')
              .fontSize(12).fontColor($r('app.color.text_primary')).fontWeight(FontWeight.Medium)
            Text('EEG Monitor 脑机交互')
              .fontSize(9).fontColor($r('app.color.text_tertiary')).margin({ top: 1 })
          }
          .alignItems(HorizontalAlign.Start).margin({ left: 8 })
        }
        .margin({ left: 8 })

        Blank()

        Row() {
          Column() {
            Text('控制稳定度')
              .fontSize(8).fontColor($r('app.color.text_tertiary'))
            Text(Math.round(100 - Math.abs(this.smoothAtt - 50) * 1.2).toString() + '%')
              .fontSize(11).fontColor($r('app.color.secondary')).fontWeight(FontWeight.Bold)
          }
          .alignItems(HorizontalAlign.Center).margin({ left: 12 })
          Column() {
            Text('信号')
              .fontSize(8).fontColor($r('app.color.text_tertiary'))
            Text(store.getSignalText())
              .fontSize(11).fontColor(store.getSignalColor()).fontWeight(FontWeight.Bold)
          }
          .alignItems(HorizontalAlign.Center).margin({ left: 12 })
        }
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 10, bottom: 8 })
      .backgroundColor($r('app.color.overlay_game'))
      .border({ width: { bottom: 0.5 }, color: $r('app.color.card_border') })

      Canvas(this.ctx)
        .width('100%')
        .layoutWeight(1)
        .backgroundColor($r('app.color.page_bg'))
        .onReady(() => {
          this.ready = true;
        })
        .onClick(() => {
          if (this.state === 0 || this.state === 2) {
            this.startGame();
          }
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
  }
}
