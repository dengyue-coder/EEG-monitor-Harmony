export interface HealthInfo {
  status: string;
  color: string;
  tip: string;
}

export function getHealthInfo(bpm: number): HealthInfo {
  if (bpm < 5) {
    return { status: '严重不足', color: '#E74C3C',
      tip: '眨眼极少！请立即休息双眼，每20分钟看远处20秒（20-20-20法则）' };
  }
  if (bpm < 10) {
    return { status: '眨眼偏少', color: '#F5A623',
      tip: '可能正在专注屏幕，建议有意识多眨眼，保持眼睛湿润' };
  }
  if (bpm > 30) {
    return { status: '眨眼过多', color: '#F5A623',
      tip: '眨眼频繁可能是眼部疲劳或紧张，建议闭眼休息1分钟' };
  }
  if (bpm > 25) {
    return { status: '略微偏多', color: '#F5A623',
      tip: '眨眼略多，注意是否眼部干涩或神经性紧张' };
  }
  return { status: '健康正常', color: '#6CBE8A',
    tip: '眨眼频率正常，眼睛状态良好，继续保持！' };
}

export class BlinkDetector {
  private buffer: number[] = [];
  private readonly MAX_BUFFER = 128;
  private refractory: number = 0;
  private readonly REFRACTORY = 14;

  private smMedian: number = 0;
  private smIQR: number = 1;
  private readonly ALPHA = 0.04;

  feed(raw: number): boolean {
    this.buffer.push(raw);
    if (this.buffer.length > this.MAX_BUFFER) {
      this.buffer.shift();
    }

    if (this.refractory > 0) {
      this.refractory--;
      return false;
    }

    if (this.buffer.length < 32) {
      return false;
    }

    if (this.buffer.length % 4 === 0) {
      this.updateStats();
    }

    const threshold = this.smMedian + 4.5 * this.smIQR;
    if (this.smIQR > 0 && raw > threshold) {
      this.refractory = this.REFRACTORY;
      return true;
    }
    return false;
  }

  private updateStats(): void {
    const sorted = [...this.buffer].sort((a: number, b: number) => a - b);
    const n = sorted.length;
    const q1 = sorted[Math.floor(n * 0.25)];
    const q2 = sorted[Math.floor(n * 0.50)];
    const q3 = sorted[Math.floor(n * 0.75)];
    const iqr = q3 - q1;

    this.smMedian = this.smMedian * (1 - this.ALPHA) + q2 * this.ALPHA;
    this.smIQR = Math.max(1, this.smIQR * (1 - this.ALPHA) + iqr * this.ALPHA);
  }

  reset(): void {
    this.buffer = [];
    this.refractory = 0;
    this.smMedian = 0;
    this.smIQR = 1;
  }
}
