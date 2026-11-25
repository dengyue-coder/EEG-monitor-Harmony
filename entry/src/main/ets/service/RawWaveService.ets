import { EEGDataStore } from '../store/EEGDataStore';

// ================================================================
//  RawWaveService — APP 端原始脑波合成
//
//  当前小熊派固件的帧里没有原始波形（只有 sig/att/med + 8 频段功率），
//  本服务在 APP 内以 50Hz 实时合成“原始脑波”，但严格以真实数据为输入：
//    - 8 个频段的正弦波权重 = 真实频段功率占比（δ/θ/α/β/γ 组成来自真实测量）
//    - 波形整体幅度随真实功率总量缩放
//    - 仅当：已连接 && 未接触丢失 && sig<200 && 数据新鲜(3s 内) 才合成
//    - 一旦断连/无信号/数据过期，立即清空波形，图表保持空白（不做假数据）
// ================================================================

const SAMPLE_INTERVAL_MS = 20;   // 50Hz 采样
const SAMPLE_RATE = 50;
const STALE_MS = 3000;           // 超过 3s 没有新帧视为数据过期
const MAX_AMP = 16000;           // 波形幅度上限（与 drawWave 的 ±20000 量程匹配）
const AMP_PER_POWER = 40;        // 每单位频段功率对应的波形幅度

// 各频段的代表性频率（Hz），与 Mock 波形保持一致观感
const BAND_FREQ: number[] = [2.1, 6.3, 10.2, 12.0, 16.7, 23.4, 36.5, 44.1];

class SynthState {
  phase: number[] = [0, 0, 0, 0, 0, 0, 0, 0];
  drift: number = 0;
}

export class RawWaveService {
  private static instance: RawWaveService;
  private store: EEGDataStore = EEGDataStore.getInstance();
  private timer: number = -1;
  private running: boolean = false;
  private synths: Map<string, SynthState> = new Map();
  private diagTick: number = 0;

  static getInstance(): RawWaveService {
    if (!RawWaveService.instance) {
      RawWaveService.instance = new RawWaveService();
    }
    return RawWaveService.instance;
  }

  private constructor() {}

  start(): void {
    if (this.running) return;
    this.running = true;
    this.timer = setInterval(() => this.tick(), SAMPLE_INTERVAL_MS);
  }

  stop(): void {
    this.running = false;
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
    this.synths.clear();
  }

  private tick(): void {
    const ids = this.store.getDeviceIds();
    for (let i = 0; i < ids.length; i++) {
      const id = ids[i];
      const data = this.store.getLatestData(id);
      const connected = this.store.getConnected(id);
      const contactLost = this.store.getContactLost(id);
      const age = this.store.getDataAge(id);
      const valid = data !== null && connected && !contactLost &&
        data.sig < 200 && age >= 0 && age < STALE_MS;

      if (!valid) {
        // 没有真实数据 → 停止合成并清空该设备波形（只清一次）
        if (this.synths.delete(id)) {
          this.store.clearRawHistory(id);
        }
        continue;
      }

      let st = this.synths.get(id);
      if (!st) {
        st = new SynthState();
        this.synths.set(id, st);
      }
      const sample = this.computeSample(st, this.store.getBandPower(id));
      this.store.pushRawSample(id, sample);

      // 低频诊断日志（每 5 秒一条），便于确认合成是否在真实数据驱动下运行
      this.diagTick++;
      if (this.diagTick % 250 === 0) {
        const hist = this.store.getRawHistory(id);
        console.info('[RAW] synth active device=' + id + ' sample=' + sample +
          ' historyLen=' + hist.length + ' bands=' +
          this.store.getBandPower(id).join(','));
      }
    }
  }

  private computeSample(st: SynthState, bp: number[]): number {
    const step = 2 * Math.PI / SAMPLE_RATE;
    const total = bp[0] + bp[1] + bp[2] + bp[3] + bp[4] + bp[5] + bp[6] + bp[7];

    let v = 0;
    for (let i = 0; i < 8; i++) {
      st.phase[i] = (st.phase[i] + step * BAND_FREQ[i]) % (2 * Math.PI);
      v += bp[i] * Math.sin(st.phase[i]);
    }

    // 幅度随真实功率总量缩放；功率为 0 时输出 0（连接正常但无脑电活动 → 平线）
    const amp = Math.min(MAX_AMP, Math.max(0, total * AMP_PER_POWER));
    let out = total > 0 ? (v / total) * amp : 0;

    // 生理噪声（幅度与真实功率成正比）
    out += (Math.random() * 2 - 1) * amp * 0.04;
    // 缓慢基线漂移
    st.drift = Math.max(-1, Math.min(1, st.drift + (Math.random() * 2 - 1) * 0.02));
    out += st.drift * amp * 0.06;

    return Math.floor(out);
  }
}
