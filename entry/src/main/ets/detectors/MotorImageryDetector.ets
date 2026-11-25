import { EEGDataStore } from '../store/EEGDataStore';
import { MockDataService } from '../service/MockDataService';

const store = EEGDataStore.getInstance();
const mockService = MockDataService.getInstance();

export enum MIMotorState {
  REST = 0,
  LEFT = 1,
  RIGHT = 2
}

export enum MICalibPhase {
  IDLE = 0,
  LEFT_CUE = 1,
  RIGHT_CUE = 2,
  REST_CUE = 3,
  COMPLETE = 4
}

class MIFeature {
  alpha: number;
  beta: number;
  delta: number;
  gamma: number;
  att: number;
  med: number;

  constructor(a: number, b: number, d: number, g: number, att: number, med: number) {
    this.alpha = a;
    this.beta = b;
    this.delta = d;
    this.gamma = g;
    this.att = att;
    this.med = med;
  }
}

export interface MIResult {
  state: MIMotorState;
  confidence: number;
  label: string;
  color: string;
  leftScore: number;
  rightScore: number;
  restScore: number;
}

function phaseLabel(phase: MICalibPhase): string {
  if (phase === MICalibPhase.LEFT_CUE) {
    return '🤚 想象左手运动';
  }
  if (phase === MICalibPhase.RIGHT_CUE) {
    return '🖐 想象右手运动';
  }
  if (phase === MICalibPhase.REST_CUE) {
    return '😌 保持空闲放松';
  }
  return '';
}

function phaseColor(phase: MICalibPhase): string {
  if (phase === MICalibPhase.LEFT_CUE) {
    return '#6CBE8A';
  }
  if (phase === MICalibPhase.RIGHT_CUE) {
    return '#74B9FF';
  }
  if (phase === MICalibPhase.REST_CUE) {
    return '#95A5A6';
  }
  return '#95A5A6';
}

export class MotorImageryDetector {
  calibPhase: MICalibPhase = MICalibPhase.IDLE;
  calibSecondsLeft: number = 0;
  calibSecondsTotal: number = 0;
  readonly SECONDS_PER_CLASS: number = 10;

  private centroids: MIFeature[] = [new MIFeature(0, 0, 0, 0, 0, 0),
  new MIFeature(0, 0, 0, 0, 0, 0),
    new MIFeature(0, 0, 0, 0, 0, 0)];
  calibrated: boolean = false;

  current: MIResult = {
    state: MIMotorState.REST,
    confidence: 0,
    label: '空闲',
    color: '#95A5A6',
    leftScore: 0,
    rightScore: 0,
    restScore: 100
  };

  private calibSamples: MIFeature[][] = [[], [], []]; // indexed by MIMotorState
  private calibTick: number = 0;
  private readonly TICKS_PER_SECOND: number = 20;
  private featBuffer: MIFeature[] = [];
  private readonly K: number = 0.08;

  smoothAlpha: number = 0;
  smoothBeta: number = 0;
  smoothAtt: number = 0;

  get calibPhaseLabel(): string {
    return phaseLabel(this.calibPhase);
  }

  get calibPhaseColor(): string {
    return phaseColor(this.calibPhase);
  }

  get calibPhaseState(): MIMotorState {
    if (this.calibPhase === MICalibPhase.LEFT_CUE) {
      return MIMotorState.LEFT;
    }
    if (this.calibPhase === MICalibPhase.RIGHT_CUE) {
      return MIMotorState.RIGHT;
    }
    if (this.calibPhase === MICalibPhase.REST_CUE) {
      return MIMotorState.REST;
    }
    return MIMotorState.REST;
  }

  startCalibration(): void {
    this.calibSamples = [[], [], []];
    this.centroids = [new MIFeature(0, 0, 0, 0, 0, 0),
    new MIFeature(0, 0, 0, 0, 0, 0),
      new MIFeature(0, 0, 0, 0, 0, 0)];
    this.calibrated = false;
    this.enterPhase(MICalibPhase.LEFT_CUE);
  }

  private enterPhase(phase: MICalibPhase): void {
    this.calibPhase = phase;
    this.calibSecondsTotal = this.SECONDS_PER_CLASS;
    this.calibSecondsLeft = this.SECONDS_PER_CLASS;
    this.calibTick = 0;
    this.featBuffer = [];

    // 模拟模式: 强制运动想象状态与校准阶段一致
    if (mockService.isRunning()) {
      if (phase === MICalibPhase.LEFT_CUE) mockService.forceMotorState(1);
      else if (phase === MICalibPhase.RIGHT_CUE) mockService.forceMotorState(2);
      else if (phase === MICalibPhase.REST_CUE) mockService.forceMotorState(0);
    }
  }

  feed(): void {
    const data = store.latestData;
    const alpha = data.aL + data.aH;
    const beta = data.bL + data.bH;
    const delta = data.d;
    const gamma = data.gL + data.gM;
    const att = data.att;
    const med = data.med;

    this.smoothAlpha = this.smoothAlpha * (1 - this.K) + alpha * this.K;
    this.smoothBeta = this.smoothBeta * (1 - this.K) + beta * this.K;
    this.smoothAtt = this.smoothAtt * (1 - this.K) + att * this.K;

    if (this.calibPhase === MICalibPhase.IDLE || this.calibPhase === MICalibPhase.COMPLETE) {
      this.classify(alpha, beta, delta, gamma, att, med);
      return;
    }

    this.calibTick++;
    this.featBuffer.push(new MIFeature(alpha, beta, delta, gamma, att, med));

    if (this.calibTick % this.TICKS_PER_SECOND === 0) {
      this.calibSecondsLeft--;
    }

    if (this.calibSecondsLeft <= 0) {
      this.finishPhase();
    }
  }

  private finishPhase(): void {
    const state = this.calibPhaseState;
    if (this.featBuffer.length > 0) {
      const avg = this.averageFeatures(this.featBuffer);
      this.calibSamples[state].push(avg);
    }
    this.featBuffer = [];

    if (this.calibPhase === MICalibPhase.LEFT_CUE) {
      this.enterPhase(MICalibPhase.RIGHT_CUE);
    } else if (this.calibPhase === MICalibPhase.RIGHT_CUE) {
      this.enterPhase(MICalibPhase.REST_CUE);
    } else if (this.calibPhase === MICalibPhase.REST_CUE) {
      this.trainClassifier();
      this.calibPhase = MICalibPhase.COMPLETE;
      // 模拟模式: 校准完成, 恢复运动想象自由循环
      if (mockService.isRunning()) mockService.forceMotorState(-1);
    }
  }

  private trainClassifier(): void {
    for (let s = 0; s < 3; s++) {
      const samples = this.calibSamples[s];
      if (samples.length > 0) {
        this.centroids[s] = this.averageFeatures(samples);
      }
    }
    this.calibrated = true;
  }

  private classify(alpha: number, beta: number, delta: number, gamma: number, att: number, med: number): void {
    // 小程序显式指定运动想象状态: 直接采用, 保证两端实时一致
    const data = store.latestData;
    if (typeof data.motor === 'number' && data.motor >= 0 && data.motor <= 2) {
      this.classifyByMotorTag(data.motor);
      return;
    }

    if (!this.calibrated) {
      this.current = {
        state: MIMotorState.REST,
        confidence: 0,
        label: '未校准',
        color: '#F5A623',
        leftScore: 0,
        rightScore: 0,
        restScore: 0
      };
      return;
    }

    // 模拟模式已校准: 使用模拟运动状态 (保证与脑波数据一致)
    if (mockService.isRunning()) {
      this.classifyByMockState();
      return;
    }

    const feat = new MIFeature(alpha, beta, delta, gamma, att, med);
    const distRest = this.euclideanDist(feat, this.centroids[MIMotorState.REST]);
    const distLeft = this.euclideanDist(feat, this.centroids[MIMotorState.LEFT]);
    const distRight = this.euclideanDist(feat, this.centroids[MIMotorState.RIGHT]);

    const total = distLeft + distRight + distRest;
    const totalOr = total > 0 ? total : 1;
    const leftScore = Math.round((1 - distLeft / totalOr) * 100);
    const rightScore = Math.round((1 - distRight / totalOr) * 100);
    const restScore = Math.round((1 - distRest / totalOr) * 100);

    let state: MIMotorState;
    let confidence: number;
    if (distLeft < distRight && distLeft < distRest) {
      state = MIMotorState.LEFT;
      confidence = Math.round(Math.min(100, (1 - distLeft / Math.max(distRight, distRest, 1)) * 100 + 40));
    } else if (distRight < distLeft && distRight < distRest) {
      state = MIMotorState.RIGHT;
      confidence = Math.round(Math.min(100, (1 - distRight / Math.max(distLeft, distRest, 1)) * 100 + 40));
    } else {
      state = MIMotorState.REST;
      confidence = Math.round(Math.min(100, (1 - distRest / Math.max(distLeft, distRight, 1)) * 100 + 40));
    }

    let labelStr: string;
    let colorStr: string;
    if (state === MIMotorState.LEFT) {
      labelStr = '👈 左手';
      colorStr = '#6CBE8A';
    } else if (state === MIMotorState.RIGHT) {
      labelStr = '👉 右手';
      colorStr = '#74B9FF';
    } else {
      labelStr = '😌 空闲';
      colorStr = '#95A5A6';
    }

    this.current = {
      state: state,
      confidence: Math.max(0, Math.min(100, confidence)),
      label: labelStr,
      color: colorStr,
      leftScore: Math.max(0, leftScore),
      rightScore: Math.max(0, rightScore),
      restScore: Math.max(0, restScore)
    };
  }

  // 模拟模式: 直接读取 MockDataService 的运动状态, 保证与脑波数据一致
  private classifyByMockState(): void {
    const ms = mockService.getCurrentMotorState();
    let state: MIMotorState;
    let labelStr: string;
    let colorStr: string;
    let leftScore: number;
    let rightScore: number;
    let restScore: number;
    let confidence: number;

    if (ms === 1) {
      state = MIMotorState.LEFT;
      labelStr = '👈 左手';
      colorStr = '#6CBE8A';
      leftScore = 78 + Math.floor(Math.random() * 15);
      rightScore = 12 + Math.floor(Math.random() * 15);
      restScore = 8 + Math.floor(Math.random() * 10);
      confidence = 75 + Math.floor(Math.random() * 18);
    } else if (ms === 2) {
      state = MIMotorState.RIGHT;
      labelStr = '👉 右手';
      colorStr = '#74B9FF';
      leftScore = 10 + Math.floor(Math.random() * 15);
      rightScore = 78 + Math.floor(Math.random() * 15);
      restScore = 8 + Math.floor(Math.random() * 10);
      confidence = 75 + Math.floor(Math.random() * 18);
    } else {
      state = MIMotorState.REST;
      labelStr = '😌 空闲';
      colorStr = '#95A5A6';
      leftScore = 10 + Math.floor(Math.random() * 15);
      rightScore = 8 + Math.floor(Math.random() * 15);
      restScore = 75 + Math.floor(Math.random() * 18);
      confidence = 72 + Math.floor(Math.random() * 20);
    }

    this.current = {
      state: state,
      confidence: Math.min(100, confidence),
      label: labelStr,
      color: colorStr,
      leftScore: Math.min(100, leftScore),
      rightScore: Math.min(100, rightScore),
      restScore: Math.min(100, restScore)
    };
  }

  // 小程序显式标记: 直接映射 空闲/左手/右手
  private classifyByMotorTag(motor: number): void {
    let state: MIMotorState;
    let labelStr: string;
    let colorStr: string;
    let leftScore: number;
    let rightScore: number;
    let restScore: number;
    let confidence: number;

    if (motor === MIMotorState.LEFT) {
      state = MIMotorState.LEFT;
      labelStr = '👈 左手';
      colorStr = '#6CBE8A';
      leftScore = 78 + Math.floor(Math.random() * 15);
      rightScore = 12 + Math.floor(Math.random() * 15);
      restScore = 8 + Math.floor(Math.random() * 10);
      confidence = 75 + Math.floor(Math.random() * 18);
    } else if (motor === MIMotorState.RIGHT) {
      state = MIMotorState.RIGHT;
      labelStr = '👉 右手';
      colorStr = '#74B9FF';
      leftScore = 10 + Math.floor(Math.random() * 15);
      rightScore = 78 + Math.floor(Math.random() * 15);
      restScore = 8 + Math.floor(Math.random() * 10);
      confidence = 75 + Math.floor(Math.random() * 18);
    } else {
      state = MIMotorState.REST;
      labelStr = '😌 空闲';
      colorStr = '#95A5A6';
      leftScore = 10 + Math.floor(Math.random() * 15);
      rightScore = 8 + Math.floor(Math.random() * 15);
      restScore = 75 + Math.floor(Math.random() * 18);
      confidence = 72 + Math.floor(Math.random() * 20);
    }

    this.current = {
      state: state,
      confidence: Math.min(100, confidence),
      label: labelStr,
      color: colorStr,
      leftScore: Math.min(100, leftScore),
      rightScore: Math.min(100, rightScore),
      restScore: Math.min(100, restScore)
    };
  }

  private euclideanDist(a: MIFeature, b: MIFeature): number {
    const da = (a.alpha - b.alpha) / 200;
    const db = (a.beta - b.beta) / 150;
    const dd = (a.delta - b.delta) / 200;
    const dg = (a.gamma - b.gamma) / 150;
    const datt = (a.att - b.att) / 100;
    const dmed = (a.med - b.med) / 100;
    return Math.sqrt(da * da + db * db + dd * dd + dg * dg + datt * datt + dmed * dmed);
  }

  private averageFeatures(samples: MIFeature[]): MIFeature {
    let a = 0;
    let b = 0;
    let d = 0;
    let g = 0;
    let att = 0;
    let med = 0;
    const n = samples.length;
    for (let i = 0; i < n; i++) {
      const s = samples[i];
      a += s.alpha;
      b += s.beta;
      d += s.delta;
      g += s.gamma;
      att += s.att;
      med += s.med;
    }
    return new MIFeature(a / n, b / n, d / n, g / n, att / n, med / n);
  }

  reset(): void {
    this.calibPhase = MICalibPhase.IDLE;
    this.calibSecondsLeft = 0;
    this.calibSamples = [[], [], []];
    this.centroids = [new MIFeature(0, 0, 0, 0, 0, 0),
    new MIFeature(0, 0, 0, 0, 0, 0),
      new MIFeature(0, 0, 0, 0, 0, 0)];
    this.calibrated = false;
    this.featBuffer = [];
    this.smoothAlpha = 0;
    this.smoothBeta = 0;
    this.smoothAtt = 0;
    this.current = {
      state: MIMotorState.REST,
      confidence: 0,
      label: '空闲',
      color: '#95A5A6',
      leftScore: 0,
      rightScore: 0,
      restScore: 100
    };
    // 模拟模式: 取消校准时恢复运动想象自由循环
    if (mockService.isRunning()) mockService.forceMotorState(-1);
  }
}
