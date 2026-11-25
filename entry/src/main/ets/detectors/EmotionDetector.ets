import { EEGDataStore } from '../store/EEGDataStore';
import { EmotionKind } from '../utils/EEGConstants';
import { NeuralClassifier } from './NeuralClassifier';
import { MockDataService } from '../service/MockDataService';

const store = EEGDataStore.getInstance();
const mockService = MockDataService.getInstance();
const ml = new NeuralClassifier();

export class VAPoint {
  v: number; a: number;
  constructor(v: number, a: number) { this.v = v; this.a = a; }
}

export class BandItem {
  label: string; value: number; color: string;
  constructor(l: string, v: number, c: string) { this.label = l; this.value = v; this.color = c; }
}

export class VAZone {
  x: number; y: number; label: string; color: string;
  constructor(x: number, y: number, l: string, c: string) {
    this.x = x; this.y = y; this.label = l; this.color = c;
  }
}

export const QUADS: VAZone[] = [
  new VAZone(0.75, 0.75, '愉悦兴奋', '#FF9500'),
  new VAZone(0.75, 0.25, '放松宁静', '#6CBE8A'),
  new VAZone(0.25, 0.75, '焦虑紧张', '#F5A623'),
  new VAZone(0.25, 0.25, '悲伤低落', '#7B8FA1'),
];

export class EmotionDetector {
  smoothV: number = 50;
  smoothA: number = 50;
  smoothAtt: number = 50;
  smoothMed: number = 50;
  private readonly K = 0.08;
  private mlResult: EmotionKind = EmotionKind.NEUTRAL;
  private mlProbs: number[] = [1, 0, 0, 0, 0, 0, 0, 0, 0];

  feed(): void {
    const data = store.latestData;
    const a = data.aL + data.aH;
    const b = data.bL + data.bH;
    const g = data.gL + data.gM;
    const dt = data.d + data.t;
    const ratio = a / Math.max(b + g, 1);
    this.smoothV = this.smoothV * (1 - this.K) + (50 + (ratio - 0.5) * 25 + (data.att - 50) * 0.3 - (data.med - 50) * 0.1) * this.K;
    this.smoothA = this.smoothA * (1 - this.K) + (50 + ((b + g) / (dt + 1) - 1) * 20 + (50 - data.med) * 0.25) * this.K;
    this.smoothAtt = this.smoothAtt * (1 - this.K) + data.att * this.K;
    this.smoothMed = this.smoothMed * (1 - this.K) + data.med * this.K;

    if (typeof data.emo === 'number' && data.emo >= 0 && data.emo <= 8) {
      // 小程序显式指定情绪: 直接采用, 保证两端实时一致
      this.mlResult = data.emo as EmotionKind;
      this.fillProbs(this.mlResult);
    } else if (mockService.isRunning()) {
      this.overrideByMockPhase();
    } else {
      const feats: number[] = [data.d, data.t, data.aL, data.aH, data.bL, data.bH, data.gL, data.gM, data.att, data.med];
      const result = ml.classify(feats);
      this.mlResult = result[0];
      this.mlProbs = result[1];
    }
  }

  // 模拟模式: 根据 MockDataService 的情绪相位直接映射, 保证全页面一致
  private overrideByMockPhase(): void {
    const phase = mockService.getCurrentPhase();
    const sec = Math.floor(Date.now() / 1000);

    switch (phase) {
      case 0: // 平静 → V高 A低 → 放松宁静 / 平静安稳
        this.smoothV = this.smoothV * 0.88 + (62 + Math.random() * 13) * 0.12;
        this.smoothA = this.smoothA * 0.88 + (25 + Math.random() * 15) * 0.12;
        this.smoothAtt = this.smoothAtt * 0.9 + (28 + Math.random() * 14) * 0.1;
        this.smoothMed = this.smoothMed * 0.9 + (55 + Math.random() * 16) * 0.1;
        this.mlResult = (sec % 6 < 4) ? EmotionKind.NEUTRAL : EmotionKind.RELAXED;
        break;
      case 1: // 兴奋 → V高 A高 → 兴奋激动 / 开心快乐
        this.smoothV = this.smoothV * 0.88 + (60 + Math.random() * 20) * 0.12;
        this.smoothA = this.smoothA * 0.88 + (65 + Math.random() * 18) * 0.12;
        this.smoothAtt = this.smoothAtt * 0.9 + (35 + Math.random() * 22) * 0.1;
        this.smoothMed = this.smoothMed * 0.9 + (22 + Math.random() * 20) * 0.1;
        this.mlResult = (sec % 5 < 3) ? EmotionKind.EXCITED : EmotionKind.HAPPY;
        break;
      case 2: // 紧张 → V低 A高 → 焦虑紧张 / 高度专注
        this.smoothV = this.smoothV * 0.88 + (20 + Math.random() * 18) * 0.12;
        this.smoothA = this.smoothA * 0.88 + (60 + Math.random() * 20) * 0.12;
        this.smoothAtt = this.smoothAtt * 0.9 + (6 + Math.random() * 18) * 0.1;
        this.smoothMed = this.smoothMed * 0.9 + (15 + Math.random() * 18) * 0.1;
        this.mlResult = (sec % 7 < 5) ? EmotionKind.ANXIOUS : EmotionKind.FOCUSED;
        break;
    }

    this.fillProbs(this.mlResult);
  }

  /** 设置置信度概率 (选中情绪 ~0.75, 其余均分) */
  private fillProbs(kind: EmotionKind): void {
    const probs: number[] = [0, 0, 0, 0, 0, 0, 0, 0, 0];
    probs[kind] = 0.72 + Math.random() * 0.15;
    const remaining = 1 - probs[kind];
    const others = 8;
    for (let i = 0; i < 9; i++) {
      if (i !== kind) probs[i] = remaining / others;
    }
    this.mlProbs = probs;
  }

  classify(): EmotionKind {
    return this.mlResult;
  }

  /** 9 类置信度概率 [NEUTRAL, HAPPY, EXCITED, FOCUSED, RELAXED, ANXIOUS, SAD, ANGRY, TIRED] */
  get probs(): number[] { return this.mlProbs; }

  get v(): number { return Math.round(Math.max(0, Math.min(100, this.smoothV))); }
  get a(): number { return Math.round(Math.max(0, Math.min(100, this.smoothA))); }

  bands(): BandItem[] {
    const data = store.latestData;
    const arr = new Array<BandItem>(8);
    arr[0] = new BandItem('δ', data.d, '#6CBE8A');
    arr[1] = new BandItem('θ', data.t, '#74B9FF');
    arr[2] = new BandItem('αL', data.aL, '#F5A623');
    arr[3] = new BandItem('αH', data.aH, '#E87461');
    arr[4] = new BandItem('βL', data.bL, '#A29BFE');
    arr[5] = new BandItem('βH', data.bH, '#FD79A8');
    arr[6] = new BandItem('γL', data.gL, '#00CEC9');
    arr[7] = new BandItem('γH', data.gM, '#FDCB6E');
    return arr;
  }
}
