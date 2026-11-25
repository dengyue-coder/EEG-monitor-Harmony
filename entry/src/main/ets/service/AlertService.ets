import { EEGDataStore, EEGData, DeviceInfo } from '../store/EEGDataStore';

const store = EEGDataStore.getInstance();

export class AlertItem {
  level: number;     // 0=info 1=warn 2=alert
  msg: string;
  constructor(l: number, m: string) {
    this.level = l;
    this.msg = m;
  }
}

export class AlertService {
  private static instance: AlertService;

  static getInstance(): AlertService {
    if (!AlertService.instance) {
      AlertService.instance = new AlertService();
    }
    return AlertService.instance;
  }

  analyzeTeacher(infos: DeviceInfo[]): AlertItem {
    const connected = infos.filter((i: DeviceInfo) => i.connected);
    if (connected.length === 0) {
      return new AlertItem(1, '暂无设备连接，请在「设备管理」页添加模拟设备');
    }

    let attSum = 0;
    let medSum = 0;
    let poorSignal = '';

    for (let info of connected) {
      const d = store.getLatestData(info.deviceId);
      if (!d) continue;
      attSum += d.att;
      medSum += d.med;
      if (d.sig >= 100) poorSignal = info.deviceName;
    }

    const n = Math.max(connected.length, 1);
    const avgAtt = Math.round(attSum / n);
    const avgMed = Math.round(medSum / n);

    if (poorSignal !== '') {
      return new AlertItem(2, `${poorSignal} 信号差，请检查电极接触`);
    }
    if (avgAtt < 25) {
      return new AlertItem(2, `${n}名学生平均专注度仅${avgAtt}，建议引导5分钟深呼吸`);
    }
    if (avgMed > 70) {
      return new AlertItem(0, `整体放松（冥想度${avgMed}），适合创意或冥想环节`);
    }
    if (avgAtt > 65) {
      return new AlertItem(0, `${n}名学生专注度高（均${avgAtt}），处于高效"心流"状态`);
    }
    if (avgAtt < 40 && n >= 2) {
      return new AlertItem(1, `多生专注度偏低（均${avgAtt}），建议切换教学方式`);
    }

    return new AlertItem(0, `状态正常 · ${n}名学生平均专注${avgAtt} / 冥想${avgMed}`);
  }
}
