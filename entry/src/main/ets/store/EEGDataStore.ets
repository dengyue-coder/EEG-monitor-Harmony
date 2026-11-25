export class EEGData {
  sig: number = 200;
  att: number = 0;
  med: number = 0;
  emo: number = -1;
  motor: number = -1;
  raw: number = 0;
  r?: number[];
  d: number = 0;
  t: number = 0;
  aL: number = 0;
  aH: number = 0;
  bL: number = 0;
  bH: number = 0;
  gL: number = 0;
  gM: number = 0;
}

export class TrendPoint {
  att: number = 0;
  med: number = 0;
}

export const BAND_LABELS: string[] = [
  'Delta', 'Theta', 'Low α', 'High α',
  'Low β', 'High β', 'Low γ', 'Mid γ'
];

export class DeviceInfo {
  deviceId: string = '';
  deviceName: string = '';
  connected: boolean = false;
  signalColor: string = '#95A5A6';
}

class DeviceSlot {
  info: DeviceInfo = new DeviceInfo();
  latestData: EEGData = new EEGData();
  lastUpdate: number = 0;
  contactLost: boolean = false;
  validStreak: number = 0;
  lostStreak: number = 0;
  attEst: number = 0;   /* 频带估算的专注度（模块不输出 att 时使用） */
  medEst: number = 0;   /* 频带估算的冥想度（模块不输出 med 时使用） */
  rawHistory: number[] = [];
  needsSynth: boolean = false;  /* 固件帧不带原始波形时，由 APP 根据真实频段功率合成 */
  trendHistory: TrendPoint[] = [];
  bandPower: number[] = [0, 0, 0, 0, 0, 0, 0, 0];
  bandHistory: number[][] = [[], [], [], [], [], [], [], []];
  dataVersion: number = 0;
  rawVersion: number = 0;

  get connected(): boolean { return this.info.connected; }
  set connected(v: boolean) { this.info.connected = v; }

  get signalText(): string {
    const s = this.latestData.sig;
    if (s === 0) return '优秀';
    if (s < 50) return '良好';
    if (s < 100) return '一般';
    if (s < 200) return '较差';
    if (s === 200) return '等待接触';
    return '未知';
  }

  get signalColor(): string {
    const s = this.latestData.sig;
    if (s === 0) return '#6CBE8A';
    if (s < 50) return '#6CBE8A';
    if (s < 100) return '#F5A623';
    if (s < 200) return '#E87461';
    if (s === 200) return '#F5A623';
    return '#95A5A6';
  }
}

export class EEGDataStore {
  private static instance: EEGDataStore;
  private slots: Map<string, DeviceSlot> = new Map();
  private _activeDeviceId: string = '';

  readonly MAX_RAW_POINTS = 512;
  readonly MAX_TREND_POINTS = 300;
  readonly MAX_BAND_POINTS = 300;

  private updateListeners: Set<() => void> = new Set();
  private rawUpdateListeners: Set<() => void> = new Set();
  private globalListeners: Set<(action: string, deviceId: string) => void> = new Set();

  static getInstance(): EEGDataStore {
    if (!EEGDataStore.instance) {
      EEGDataStore.instance = new EEGDataStore();
    }
    return EEGDataStore.instance;
  }

  // ========== 设备管理 ==========

  registerDevice(deviceId: string, deviceName: string): DeviceSlot {
    if (!this.slots.has(deviceId)) {
      let slot = new DeviceSlot();
      slot.info.deviceId = deviceId;
      slot.info.deviceName = deviceName;
      slot.connected = true;
      this.slots.set(deviceId, slot);
      if (this._activeDeviceId === '') {
        this._activeDeviceId = deviceId;
      }
    }
    this.emitGlobal('registered', deviceId);
    return this.slots.get(deviceId)!;
  }

  removeDevice(deviceId: string): void {
    this.slots.delete(deviceId);
    if (this._activeDeviceId === deviceId) {
      const ids = this.getDeviceIds();
      this._activeDeviceId = ids.length > 0 ? ids[0] : '';
    }
    this.emitGlobal('removed', deviceId);
  }

  renameDevice(deviceId: string, newName: string): void {
    const slot = this.slots.get(deviceId);
    if (slot && newName.trim().length > 0) {
      slot.info.deviceName = newName.trim();
      this.emitGlobal('renamed', deviceId);
    }
  }

  setActiveDevice(deviceId: string): void {
    if (this.slots.has(deviceId) && this._activeDeviceId !== deviceId) {
      this._activeDeviceId = deviceId;
      this.emitGlobal('activeChanged', deviceId);
    }
  }

  getActiveDeviceId(): string { return this._activeDeviceId; }

  getDeviceIds(): string[] { return Array.from(this.slots.keys()); }

  getDeviceCount(): number { return this.slots.size; }

  getDeviceInfo(deviceId: string): DeviceInfo | null {
    return this.slots.get(deviceId)?.info ?? null;
  }

  getAllDeviceInfos(): DeviceInfo[] {
    let result: DeviceInfo[] = [];
    this.slots.forEach(slot => result.push(slot.info));
    return result;
  }

  private activeSlot(): DeviceSlot {
    if (this.slots.has(this._activeDeviceId)) {
      return this.slots.get(this._activeDeviceId)!;
    }
    // 兜底：返回第一个 slot
    const ids = this.getDeviceIds();
    if (ids.length > 0) {
      this._activeDeviceId = ids[0];
      return this.slots.get(ids[0])!;
    }
    // 真正无设备时注册一个占位 slot
    let s = new DeviceSlot();
    s.info.deviceId = '__default__';
    s.info.deviceName = '未连接';
    this.slots.set('__default__', s);
    this._activeDeviceId = '__default__';
    return s;
  }

  // ========== 兼容旧 API 的 getter（默认路由到活跃设备） ==========

  get latestData(): EEGData { return this.activeSlot().latestData; }

  get rawHistory(): number[] { return this.activeSlot().rawHistory; }

  get trendHistory(): TrendPoint[] { return this.activeSlot().trendHistory; }

  get bandPower(): number[] { return this.activeSlot().bandPower; }

  get bandHistory(): number[][] { return this.activeSlot().bandHistory; }

  get connected(): boolean { return this.activeSlot().connected; }
  set connected(v: boolean) { this.activeSlot().connected = v; }

  get dataVersion(): number { return this.activeSlot().dataVersion; }

  get rawVersion(): number { return this.activeSlot().rawVersion; }

  getSignalText(): string { return this.activeSlot().signalText; }

  getSignalColor(): string { return this.activeSlot().signalColor; }

  get contactLost(): boolean { return this.activeSlot().contactLost; }

  get dataAge(): number { return this.getDataAge(this._activeDeviceId); }

  // ========== 指定设备的数据访问 ==========

  getLatestData(deviceId: string): EEGData | null {
    return this.slots.get(deviceId)?.latestData ?? null;
  }

  getRawHistory(deviceId: string): number[] {
    return this.slots.get(deviceId)?.rawHistory ?? [];
  }

  getTrendHistory(deviceId: string): TrendPoint[] {
    return this.slots.get(deviceId)?.trendHistory ?? [];
  }

  getBandPower(deviceId: string): number[] {
    return this.slots.get(deviceId)?.bandPower ?? [0, 0, 0, 0, 0, 0, 0, 0];
  }

  getBandHistory(deviceId: string): number[][] {
    return this.slots.get(deviceId)?.bandHistory ?? [[], [], [], [], [], [], [], []];
  }

  getConnected(deviceId: string): boolean {
    return this.slots.get(deviceId)?.connected ?? false;
  }

  getDataVersion(deviceId: string): number {
    return this.slots.get(deviceId)?.dataVersion ?? 0;
  }

  getSignalTextFor(deviceId: string): string {
    return this.slots.get(deviceId)?.signalText ?? '未知';
  }

  getSignalColorFor(deviceId: string): string {
    return this.slots.get(deviceId)?.signalColor ?? '#95A5A6';
  }

  getContactLost(deviceId: string): boolean {
    return this.slots.get(deviceId)?.contactLost ?? false;
  }

  getDataAge(deviceId: string): number {
    const slot = this.slots.get(deviceId);
    return slot ? (Date.now() - slot.lastUpdate) : -1;
  }

  isDataStale(deviceId: string, maxAgeMs: number): boolean {
    const age = this.getDataAge(deviceId);
    return age < 0 || age > maxAgeMs;
  }

  // ========== 数据写入 ==========

  updateData(data: EEGData): void {
    this.updateDeviceData(this._activeDeviceId, data);
  }

  updateDeviceData(deviceId: string, data: EEGData): void {
    let slot = this.slots.get(deviceId);
    if (!slot) {
      slot = this.registerDevice(deviceId, deviceId);
    }
    slot.lastUpdate = Date.now();

    // 无接触/无效帧识别：电极接触不良时固件上报的帧没有真实脑电活动
    // （raw/delta/theta 全为 0，或 sig>=200 表示无信号）。
    // 诚信优先：无接触时不保留最后有效值，显示为“无信号”，
    // 避免未佩戴电极时界面仍然出现数据（会被误认为数据造假）。
    // 新版固件把 5 个真实采样打包在 data.r 数组里；旧版固件/虚拟设备用 data.raw 单值
    const rawArr = data.r;
    const hasRawArr = rawArr !== undefined && rawArr.length > 0;
    const hasBands = data.d !== 0 || data.t !== 0 || data.aL !== 0 || data.aH !== 0 ||
      data.bL !== 0 || data.bH !== 0 || data.gL !== 0 || data.gM !== 0;

    // 仅当固件明确上报 sig>=200（无接触），或帧里完全没有有效数据时才判定无信号。
    // 注意：raw/delta/theta 为 0 但其它频段或 att/med 有值仍是真实数据，
    // 不能仅凭 raw==0 && d==0 && t==0 就误判为无接触（会导致 APP 一直无数据）。
    const noContact = data.sig >= 200 ||
      (!hasRawArr && data.raw === 0 && !hasBands && data.att === 0 && data.med === 0);
    if (noContact) {
      // 进入无信号去抖：连续 3 帧无接触才判定信号丢失，避免 sig 抖动导致界面闪烁
      slot.lostStreak++;
      if (slot.lostStreak < 3) {
        // 仍认为有信号：保留上一帧显示，不切换 contactLost
        if (!slot.contactLost) {
          slot.validStreak = 0;
        }
        return;
      }
      slot.validStreak = 0;
      slot.contactLost = true;
      this.applyBlank(slot);
      return;
    }
    // 有有效帧：重置无信号计数，立即恢复显示。
    // 脑环帧率较低（约 2Hz），若要求连续 2 帧有效才恢复，会让用户感觉“一直没数据”。
    slot.lostStreak = 0;
    slot.validStreak++;
    slot.contactLost = false;

    // 金士座模块可能不输出 Attention/Meditation（恒为 0），此时用真实频带估算
    // 专注 ≈ β/(α+θ)、冥想 ≈ α/(β+γ)，并做指数平滑避免跳变
    // 纯 raw 帧（无频带字段）：沿用上一帧频带/专注度，避免显示跳 0
    if (hasRawArr && !hasBands) {
      const prev = slot.latestData;
      data.d = prev.d;
      data.t = prev.t;
      data.aL = prev.aL;
      data.aH = prev.aH;
      data.bL = prev.bL;
      data.bH = prev.bH;
      data.gL = prev.gL;
      data.gM = prev.gM;
      data.att = prev.att;
      data.med = prev.med;
    }

    // 仅全量帧才更新频带/趋势统计，避免 50Hz raw 帧重复覆盖相同频带值
    const isFullFrame = hasBands || !hasRawArr;

    if (isFullFrame && data.att === 0 && data.med === 0) {
      const theta = data.t;
      const alpha = data.aL + data.aH;
      const beta = data.bL + data.bH;
      const gamma = data.gL + data.gM;
      const total = theta + alpha + beta + gamma;
      if (total > 0) {
        const attRaw = Math.round(Math.min(100, Math.max(0, (beta / (alpha + theta + 1)) * 100)));
        const medRaw = Math.round(Math.min(100, Math.max(0, (alpha / (beta + gamma + 1)) * 100)));
        slot.attEst = slot.attEst === 0 ? attRaw : Math.round(slot.attEst * 0.75 + attRaw * 0.25);
        slot.medEst = slot.medEst === 0 ? medRaw : Math.round(slot.medEst * 0.75 + medRaw * 0.25);
        data.att = slot.attEst;
        data.med = slot.medEst;
      }
    }

    slot.latestData = data;
    slot.dataVersion++;
    slot.info.signalColor = slot.signalColor;

    if (rawArr !== undefined && rawArr.length > 0) {
      for (const v of rawArr) {
        if (typeof v === 'number' && isFinite(v)) {
          slot.rawHistory.push(v);
        }
      }
      if (slot.rawHistory.length > this.MAX_RAW_POINTS) {
        slot.rawHistory.splice(0, slot.rawHistory.length - this.MAX_RAW_POINTS);
      }
      data.raw = rawArr[rawArr.length - 1];
      slot.needsSynth = false;
    } else if (typeof data.raw === 'number' && isFinite(data.raw)) {
      // 只保留有效数值样本，避免固件帧里没有 raw 字段时把 undefined/NaN 写入波形历史
      slot.rawHistory.push(data.raw);
      if (slot.rawHistory.length > this.MAX_RAW_POINTS) {
        slot.rawHistory.shift();
      }
      slot.needsSynth = false;
    } else {
      // 固件帧不带原始波形（当前小熊派固件）→ 由 RawWaveService 按真实频段功率合成
      slot.needsSynth = true;
    }

    if (isFullFrame) {
      slot.bandPower = [data.d, data.t, data.aL, data.aH, data.bL, data.bH, data.gL, data.gM];

      let pt = new TrendPoint();
      pt.att = data.att;
      pt.med = data.med;
      slot.trendHistory.push(pt);
      if (slot.trendHistory.length > this.MAX_TREND_POINTS) {
        slot.trendHistory.shift();
      }
      for (let i = 0; i < 8; i++) {
        slot.bandHistory[i].push(slot.bandPower[i]);
        if (slot.bandHistory[i].length > this.MAX_BAND_POINTS) {
          slot.bandHistory[i].shift();
        }
      }
    }

    // 只通知活跃设备相关监听
    this.updateListeners.forEach((cb) => { cb(); });
    this.notifyRawUpdate();
  }

  // 无信号占位：清空显示值（sig=200 表示“等待接触”），所有页面统一显示无信号
  private applyBlank(slot: DeviceSlot): void {
    const blank = new EEGData();
    blank.sig = 200;
    slot.latestData = blank;
    slot.dataVersion++;
    // 无真实数据时同时清空波形历史，图表立即变空白（不保留上一段旧波形）
    if (slot.rawHistory.length > 0) {
      slot.rawHistory = [];
      slot.rawVersion++;
    }
    slot.needsSynth = false;
    this.updateListeners.forEach((cb) => { cb(); });
    this.notifyRawUpdate();
  }

  // ========== 原始波形合成入口（RawWaveService） ==========

  /** 推送一个由真实频段功率合成的原始波形样本 */
  pushRawSample(deviceId: string, sample: number): void {
    const slot = this.slots.get(deviceId);
    if (!slot || typeof sample !== 'number' || !isFinite(sample)) return;
    slot.rawHistory.push(sample);
    if (slot.rawHistory.length > this.MAX_RAW_POINTS) {
      slot.rawHistory.splice(0, slot.rawHistory.length - this.MAX_RAW_POINTS);
    }
    slot.rawVersion++;
    this.notifyRawUpdate();
  }

  /** 设备失去有效数据时清空波形，避免无数据时仍显示旧波形 */
  clearRawHistory(deviceId: string): void {
    const slot = this.slots.get(deviceId);
    if (!slot || slot.rawHistory.length === 0) return;
    slot.rawHistory = [];
    slot.rawVersion++;
    slot.needsSynth = false;
    this.notifyRawUpdate();
  }

  // ========== 订阅 ==========

  subscribe(callback: () => void): () => void {
    this.updateListeners.add(callback);
    return () => { this.updateListeners.delete(callback); };
  }

  subscribeRaw(callback: () => void): () => void {
    this.rawUpdateListeners.add(callback);
    return () => { this.rawUpdateListeners.delete(callback); };
  }

  subscribeGlobal(callback: (action: string, deviceId: string) => void): () => void {
    this.globalListeners.add(callback);
    return () => { this.globalListeners.delete(callback); };
  }

  // ========== 内部 ==========

  private notifyRawUpdate(): void {
    this.rawUpdateListeners.forEach((cb) => { cb(); });
  }

  private emitGlobal(action: string, deviceId: string): void {
    this.globalListeners.forEach(cb => {
      try { cb(action, deviceId); } catch (e) {}
    });
  }

  destroy(): void {
    this.updateListeners.clear();
    this.rawUpdateListeners.clear();
    this.globalListeners.clear();
    this.slots.clear();
  }
}
