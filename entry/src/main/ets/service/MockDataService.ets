import { EEGDataStore, EEGData } from '../store/EEGDataStore';
import { randomBetween } from '../utils/MathUtils';

// ================================================================
//  MockDataService — 模拟 BearPi H3863 + 金牛座脑波模块数据
//
//  情绪循环: 平静4s → 兴奋7s → 紧张4s → 循环 (周期15s)
//  眨眼波峰: 每2~4秒一次
//
//  八波段功率层级 (符合真实EEG生理规律):
//    放松→α主导  兴奋→β+γ  紧张→β主导+γ中等
//
//  多设备模式: 每设备有独立的相位偏移和随机种子
// ================================================================

const store = EEGDataStore.getInstance();

const CALM_SEC    = 4;
const EXCITED_SEC = 7;
const NERVOUS_SEC = 4;
const BLINK_MIN_GAP = 100;
const BLINK_MAX_GAP = 200;
const BLINK_WAVE = [0.15, 0.45, 0.80, 1.00, 0.65, 0.25, 0.05];
const MI_LEFT_SEC  = 8;
const MI_RIGHT_SEC = 8;
const MI_REST_SEC  = 4;
const BIG_INTERVAL = 50;

class PerDeviceState {
  tick: number = 0;
  phase: number = 0;
  phaseTick: number = 0;
  medTrend: number = 45;
  blinkOn: boolean = false;
  blinkIdx: number = 0;
  blinkAmp: number = 0;
  nextBlinkAt: number = 0;
  gammaSpike: boolean = false;
  gammaSpikeTick: number = 0;
  gammaSpikeLen: number = 0;
  motorState: number = 0;
  motorTick: number = 0;
  motorCycleNext: number = 1;
  forcedMotor: number = -1;
  bigTick: number = 0;
  pSig: number = 0;
  pAtt: number = 0;
  pMed: number = 0;
  pBands: number[] = [0, 0, 0, 0, 0, 0, 0, 0];
  cSig: number = 0;
  cAtt: number = 0;
  cMed: number = 0;
  cBands: number[] = [0, 0, 0, 0, 0, 0, 0, 0];
  // 个体差异种子 (-1~1)
  seed: number = 0;

  constructor(seed: number) {
    this.seed = seed;
    this.medTrend = 40 + seed * 15;
  }

  /** 返回本设备的随机偏移量 [-1, 1] 乘以 seed 叠加全局随机 */
  jitter(global: number, scale: number): number {
    return global + this.seed * scale * 0.5 + randomBetween(-scale * 0.25, scale * 0.25);
  }
}

export class MockDataService {
  private static instance: MockDataService;
  private timer: number = -1;
  private running: boolean = false;
  private multiMode: boolean = false;
  private devices: Map<string, PerDeviceState> = new Map();
  private globalTick: number = 0;

  static getInstance(): MockDataService {
    if (!MockDataService.instance) MockDataService.instance = new MockDataService();
    return MockDataService.instance;
  }

  private constructor() {}

  start(): boolean {
    return this.startAs('mock_1', '模拟设备 #1');
  }

  /** 强制全新启动（先清状态再启动），确保任何时序下都能出数据 */
  restart(): boolean {
    this.stopInternal();
    return this.startAs('mock_1', '模拟设备 #1');
  }

  startAs(deviceId: string, deviceName: string): boolean {
    if (this.running) return true;
    this.running = true;
    this.multiMode = false;
    this.globalTick = 0;
    console.info('[Mock] startAs called device=' + deviceId);

    store.registerDevice(deviceId, deviceName);
    store.setActiveDevice(deviceId);
    store.connected = true;

    const st = new PerDeviceState(0);
    this.initState(st);
    this.devices.set(deviceId, st);

    // 立即推送首帧，确保 store 有数据
    this.generate();
    this.generate();
    this.generate();

    this.timer = setInterval(() => this.generate(), 20);
    return true;
  }

  stop(): void {
    this.stopInternal();
  }

  private stopInternal(): void {
    this.running = false;
    if (this.timer >= 0) { clearInterval(this.timer); this.timer = -1; }
    // 先移除 store 里的设备，再清内部 map
    this.devices.forEach((_st, deviceId) => { store.removeDevice(deviceId); });
    this.devices.clear();
  }

  startMulti(count: number, baseName?: string): boolean {
    if (this.running) { this.stop(); }
    this.multiMode = true;
    this.running = true;
    this.globalTick = 0;
    this.devices.clear();

    const prefix = baseName || '模拟设备';
    for (let i = 1; i <= count; i++) {
      const deviceId = `mock_multi_${i}`;
      const deviceName = `${prefix} #${i}`;
      store.registerDevice(deviceId, deviceName);
      const seed = (i - 1) / Math.max(count - 1, 1) * 2 - 1; // -1 ~ 1 均匀分布
      const st = new PerDeviceState(seed);
      this.initState(st);
      this.devices.set(deviceId, st);
    }
    store.setActiveDevice('mock_multi_1');
    store.connected = true;

    this.timer = setInterval(() => this.generate(), 20);
    return true;
  }

  isRunning(): boolean { return this.running; }

  getCurrentPhase(): number {
    const first = this.devices.values().next();
    return first.done ? 0 : first.value.phase;
  }

  getCurrentMotorState(): number {
    const first = this.devices.values().next();
    return first.done ? 0 : first.value.motorState;
  }

  forceMotorState(state: number): void {
    this.devices.forEach(st => {
      st.forcedMotor = state;
      if (state >= 0) { st.motorState = state; st.motorTick = 0; }
    });
  }

  private initState(st: PerDeviceState): void {
    st.tick = 0;
    st.phase = 0;
    st.phaseTick = 0;
    st.blinkOn = false;
    st.blinkIdx = 0;
    st.nextBlinkAt = BLINK_MIN_GAP + Math.floor(Math.random() * (BLINK_MAX_GAP - BLINK_MIN_GAP));
    st.gammaSpike = false;
    st.gammaSpikeTick = 0;
    st.bigTick = 0;
    st.motorState = 0;
    st.motorTick = 0;
    st.motorCycleNext = 1;
    st.forcedMotor = -1;
    this.generateBigPacket(st);
    for (let i = 0; i < 8; i++) st.pBands[i] = st.cBands[i];
    st.pSig = st.cSig;
    st.pAtt = st.cAtt;
    st.pMed = st.cMed;
  }

  // ================================================================
  //  大包生成
  // ================================================================

  private generateBigPacket(st: PerDeviceState): void {
    st.pSig = st.cSig;
    st.pAtt = st.cAtt;
    st.pMed = st.cMed;
    for (let i = 0; i < 8; i++) st.pBands[i] = st.cBands[i];

    st.phaseTick++;
    const maxTick = st.phase === 0 ? CALM_SEC : st.phase === 1 ? EXCITED_SEC : NERVOUS_SEC;
    if (st.phaseTick >= maxTick) {
      st.phaseTick = 0;
      st.phase = (st.phase + 1) % 3;
    }

    const prog = st.phaseTick / maxTick;

    // 运动想象
    if (st.forcedMotor < 0) {
      st.motorTick++;
      const motorMaxTick = st.motorState === 0 ? MI_REST_SEC :
        st.motorState === 1 ? MI_LEFT_SEC : MI_RIGHT_SEC;
      if (st.motorTick >= motorMaxTick) {
        st.motorTick = 0;
        if (st.motorState === 0) {
          st.motorState = st.motorCycleNext;
          st.motorCycleNext = st.motorCycleNext === 1 ? 2 : 1;
        } else {
          st.motorState = 0;
        }
      }
    }

    // Gamma 尖峰
    if (st.gammaSpike) {
      st.gammaSpikeTick++;
      if (st.gammaSpikeTick >= st.gammaSpikeLen) { st.gammaSpike = false; }
    }
    if (st.phase === 1 && !st.gammaSpike) {
      const offsets = [60, 200, 330];
      for (const off of offsets) {
        if (st.phaseTick === off) {
          st.gammaSpike = true;
          st.gammaSpikeTick = 0;
          st.gammaSpikeLen = 8 + Math.floor(Math.random() * 10);
          break;
        }
      }
    }
    if (st.phase === 2 && !st.gammaSpike && st.phaseTick === 80) {
      st.gammaSpike = true;
      st.gammaSpikeTick = 0;
      st.gammaSpikeLen = 6 + Math.floor(Math.random() * 8);
    }

    // Med 趋势
    if (st.phase === 0) {
      st.medTrend += randomBetween(0.20, 0.50);
    } else if (st.phase === 1) {
      st.medTrend += randomBetween(-0.35, 0.10);
    } else {
      st.medTrend += randomBetween(-0.45, 0.00);
    }
    st.medTrend = Math.max(20, Math.min(75, st.medTrend));

    // 信号
    const r = Math.random();
    if (r < 0.02)           st.cSig = Math.floor(randomBetween(100, 180));
    else if (r < 0.06)      st.cSig = Math.floor(randomBetween(30, 80));
    else                    st.cSig = Math.floor(randomBetween(0, 5));

    switch (st.phase) {
      case 0: this.pktCalm(st, prog);   break;
      case 1: this.pktExcited(st, prog); break;
      case 2: this.pktNervous(st, prog); break;
    }

    this.applyMotorModifiers(st);

    st.cAtt = Math.max(0, Math.min(100, st.cAtt));
    st.cMed = Math.max(0, Math.min(100, st.cMed));
    for (let i = 0; i < 8; i++) st.cBands[i] = Math.max(0, st.cBands[i]);
  }

  // -------------------------------------------------------
  //  平静: α波主导
  // -------------------------------------------------------
  private pktCalm(st: PerDeviceState, _prog: number): void {
    st.cAtt = Math.floor(st.jitter(28, 20));
    st.cMed = Math.floor(st.medTrend + randomBetween(10, 25));
    st.cBands = [
      st.jitter(560, 50), st.jitter(370, 40),
      st.jitter(420, 50), st.jitter(320, 40),
      st.jitter(90, 30),  st.jitter(55, 20),
      st.jitter(25, 12),  st.jitter(16, 8),
    ];
  }

  // -------------------------------------------------------
  //  兴奋: β+γ 主导
  // -------------------------------------------------------
  private pktExcited(st: PerDeviceState, _prog: number): void {
    const gs = st.gammaSpike;
    const half = st.gammaSpikeLen / 2;
    const spike = gs ? (1 - Math.abs(st.gammaSpikeTick - half) / half) : 0;

    st.cAtt = Math.floor(st.jitter(50, 25));
    const dip = gs ? Math.floor(12 * spike) : 0;
    st.cMed = Math.floor(st.medTrend - 20 + randomBetween(-10, 12) - dip);
    st.cBands = [
      st.jitter(500, 60), st.jitter(320, 45),
      st.jitter(80, 25),  st.jitter(52, 18),
      st.jitter(200, 50), st.jitter(145, 40),
      (gs ? 440 + Math.floor(spike * 260) : st.jitter(30, 14)),
      (gs ? 350 + Math.floor(spike * 200) : st.jitter(20, 10)),
    ];
  }

  // -------------------------------------------------------
  //  紧张: β主导
  // -------------------------------------------------------
  private pktNervous(st: PerDeviceState, prog: number): void {
    const gs = st.gammaSpike;
    const half = st.gammaSpikeLen / 2;
    const spike = gs ? (1 - Math.abs(st.gammaSpikeTick - half) / half) : 0;

    st.cAtt = Math.floor(st.jitter(20, 20));
    const fall = prog > 0.5 ? (prog - 0.5) * 25 : 0;
    const spDip = gs ? Math.floor(10 * spike) : 0;
    st.cMed = Math.floor(st.medTrend - 12 - fall + randomBetween(-10, 8) - spDip);
    st.cBands = [
      st.jitter(460, 55), st.jitter(290, 40),
      st.jitter(55, 20),  st.jitter(35, 14),
      st.jitter(230, 50), st.jitter(170, 45),
      (gs ? 310 + Math.floor(spike * 190) : st.jitter(110, 45)),
      (gs ? 230 + Math.floor(spike * 150) : st.jitter(70, 35)),
    ];
  }

  // -------------------------------------------------------
  //  运动想象修正
  // -------------------------------------------------------
  private applyMotorModifiers(st: PerDeviceState): void {
    switch (st.motorState) {
      case 1:
        st.cBands[2] = Math.max(0, st.cBands[2] - 150);
        st.cBands[3] = Math.max(0, st.cBands[3] - 100);
        st.cBands[4] = st.cBands[4] + 80;
        st.cBands[5] = st.cBands[5] + 60;
        st.cBands[6] = st.cBands[6] + 50;
        st.cBands[7] = st.cBands[7] + 35;
        st.cAtt = Math.min(100, st.cAtt + 15);
        st.cMed = Math.max(0, st.cMed - 10);
        break;
      case 2:
        st.cBands[2] = Math.max(0, st.cBands[2] - 130);
        st.cBands[3] = Math.max(0, st.cBands[3] - 90);
        st.cBands[4] = st.cBands[4] + 70;
        st.cBands[5] = st.cBands[5] + 50;
        st.cBands[6] = st.cBands[6] + 40;
        st.cBands[7] = st.cBands[7] + 30;
        st.cAtt = Math.min(100, st.cAtt + 12);
        st.cMed = Math.max(0, st.cMed - 8);
        break;
    }
  }

  // ================================================================
  //  每帧生成 (50Hz) — 遍历所有设备
  // ================================================================

  private lerp(a: number, b: number, t: number): number {
    return a + (b - a) * t;
  }

  private generate(): void {
    this.globalTick++;
    const t = this.globalTick * 0.05;

    this.devices.forEach((st, deviceId) => {
      st.tick++;

      st.bigTick++;
      if (st.bigTick >= BIG_INTERVAL) {
        st.bigTick = 0;
        this.generateBigPacket(st);
      }

      const b = st.bigTick / BIG_INTERVAL;

      const data = new EEGData();
      data.sig = Math.floor(this.lerp(st.pSig, st.cSig, b));
      data.att = Math.floor(this.lerp(st.pAtt, st.cAtt, b));
      data.med = Math.floor(this.lerp(st.pMed, st.cMed, b));
      data.d  = Math.floor(this.lerp(st.pBands[0], st.cBands[0], b));
      data.t  = Math.floor(this.lerp(st.pBands[1], st.cBands[1], b));
      data.aL = Math.floor(this.lerp(st.pBands[2], st.cBands[2], b));
      data.aH = Math.floor(this.lerp(st.pBands[3], st.cBands[3], b));
      data.bL = Math.floor(this.lerp(st.pBands[4], st.cBands[4], b));
      data.bH = Math.floor(this.lerp(st.pBands[5], st.cBands[5], b));
      data.gL = Math.floor(this.lerp(st.pBands[6], st.cBands[6], b));
      data.gM = Math.floor(this.lerp(st.pBands[7], st.cBands[7], b));

      // 原始波形合成
      const am1 = 1 + 0.35 * Math.sin(2 * Math.PI * 0.15 * t);
      const am2 = 1 + 0.25 * Math.sin(2 * Math.PI * 0.40 * t);
      const j1  = 1 + 0.06 * Math.sin(2 * Math.PI * 1.70 * t);
      const j2  = 1 + 0.08 * Math.sin(2 * Math.PI * 3.30 * t);
      const brown = Math.sin(2 * Math.PI * 0.07 * t) * 1800;
      const white = randomBetween(-800, 800);
      const pink  = brown * 0.6 + white * 0.4;
      const emg   = randomBetween(-200, 200) * (Math.random() < 0.3 ? 1 : 0.25);

      const wDelta  = 2500 * Math.sin(2 * Math.PI *  2.1 * t * j1) * am1;
      const wTheta  = 1800 * Math.sin(2 * Math.PI *  6.3 * t * j2) * am2;
      const wAlpha  = 3500 * Math.sin(2 * Math.PI * 10.2 * t * j1) * am2;
      const wBeta1  =  900 * Math.sin(2 * Math.PI * 16.7 * t * j2) * am2;
      const wBeta2  =  600 * Math.sin(2 * Math.PI * 23.4 * t * j1);
      const wGamma1 =  350 * Math.sin(2 * Math.PI * 36.5 * t * j2);
      const wGamma2 =  250 * Math.sin(2 * Math.PI * 44.1 * t * j1);

      let raw = 0;
      switch (st.phase) {
        case 0:
          raw = wDelta * 0.35 + wTheta * 0.45 + wAlpha * 2.0 + wBeta1 * 0.25 + wBeta2 * 0.15 + wGamma1 * 0.05 + wGamma2 * 0.03 + pink * 0.7 + emg * 0.3;
          break;
        case 1:
          raw = wDelta * 0.20 + wTheta * 0.30 + wAlpha * 0.50 + wBeta1 * 1.6 + wBeta2 * 1.0 + wGamma1 * 0.5 + wGamma2 * 0.35 + pink * 0.5 + emg * 0.9;
          break;
        case 2:
          raw = wDelta * 0.20 + wTheta * 0.28 + wAlpha * 0.40 + wBeta1 * 1.5 + wBeta2 * 1.1 + wGamma1 * 0.6 + wGamma2 * 0.45 + pink * 0.55 + emg * 1.1;
          break;
      }
      data.raw = Math.floor(raw);

      // 眨眼注入
      if (st.blinkOn) {
        data.raw += Math.floor(st.blinkAmp * BLINK_WAVE[st.blinkIdx]);
        st.blinkIdx++;
        if (st.blinkIdx >= BLINK_WAVE.length) {
          st.blinkOn = false;
          st.blinkIdx = 0;
          st.nextBlinkAt = st.tick + BLINK_MIN_GAP + Math.floor(Math.random() * (BLINK_MAX_GAP - BLINK_MIN_GAP));
        }
      } else if (st.tick >= st.nextBlinkAt) {
        st.blinkOn = true;
        st.blinkIdx = 0;
        st.blinkAmp = 20000 + Math.floor(Math.random() * 10000);
      }

      // 兜底：确保专注度/冥想度始终有非零模拟值
      if (data.att < 10) { data.att = 25 + Math.floor(Math.random() * 40); }
      if (data.med < 10) { data.med = 30 + Math.floor(Math.random() * 35); }

      store.updateDeviceData(deviceId, data);
    });
  }
}
