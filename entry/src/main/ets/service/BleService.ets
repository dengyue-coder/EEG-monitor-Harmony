import ble from '@ohos.bluetooth.ble';
import constant from '@ohos.bluetooth.constant';
import { util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { EEGDataStore, EEGData } from '../store/EEGDataStore';
import { RawWaveService } from './RawWaveService';

const TARGET_NAME = 'EEG_Reader';
const SVC_UUID_16 = '0000EE01';
const SVC_UUID_128 = '0000EE01-0000-1000-8000-00805F9B34FB';
const TX_UUID_16 = '0000EE02';
const TX_UUID_128 = '0000EE02-0000-1000-8000-00805F9B34FB';
const LOG_PATH = '/data/storage/el2/base/haps/entry/files/ble_log.txt';

function uuidEq(actual: string, u16: string, u128: string): boolean {
  if (!actual) return false;
  const u = actual.toUpperCase();
  return u === u128 || u === u16;
}

let logFile: fileIo.File | null = null;

function logF(msg: string): void {
  console.info(msg);
  try {
    if (!logFile) {
      logFile = fileIo.openSync(LOG_PATH, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.APPEND);
    }
    let ts = new Date().toISOString();
    fileIo.writeSync(logFile.fd, ts + ' ' + msg + '\n');
  } catch (e) {
    // 静默
  }
}

function closeLog(): void {
  if (logFile) {
    try { fileIo.closeSync(logFile); } catch (e) { }
    logFile = null;
  }
}

export enum BleState {
  IDLE, SCANNING, CONNECTING, CONNECTED, DISCONNECTED, ERROR
}

export interface DiscoveredDevice {
  deviceId: string;
  deviceName: string;
  rssi: number;
}

interface GattSession {
  gatt: ble.GattClientDevice;
  mtu: number;
  jsonBuffer: string;
  pktCount: number;
  frameCount: number;
  connecting: boolean;
  initialized: boolean;
  connectTimer: number;
  reconnecting: boolean;
  dataParsed: boolean;
  unparsedBytes: number;
  formatWarned: boolean;
  lastFrameKey: string;
  repeatCount: number;
  repeatWarned: boolean;
}

export class BleService {
  private static ins: BleService;
  private store: EEGDataStore = EEGDataStore.getInstance();
  private stateCb: ((s: BleState) => void) | null = null;
  private textDecoder: util.TextDecoder = new util.TextDecoder('utf-8');

  // 单设备模式（兼容旧逻辑）
  private singleDevId: string = '';
  private singleGatt: ble.GattClientDevice | null = null;
  private singleJsonBuf: string = '';
  private singlePktCount: number = 0;
  private singleConnecting: boolean = false;
  private singleReconnecting: boolean = false;
  private singleMtu: number = 23;
  private running: boolean = false;

  // 多设备模式
  private discoveredDevices: Map<string, DiscoveredDevice> = new Map();
  private sessions: Map<string, GattSession> = new Map();
  private onDeviceDiscovered: ((devices: DiscoveredDevice[]) => void) | null = null;
  private onDeviceConnected: ((deviceId: string, deviceName: string) => void) | null = null;
  private onDeviceDisconnected: ((deviceId: string) => void) | null = null;
  private onDeviceErrorCb: ((deviceId: string, deviceName: string, message: string) => void) | null = null;
  private onDataReplayCb: ((deviceId: string, deviceName: string) => void) | null = null;
  private scanErrorCb: ((message: string) => void) | null = null;
  private multiMode: boolean = false;
  // 自动重试计数：小熊派固件有时会在连接建立后立刻断开（HCI reason 19），
  // 重试 1~2 次通常就能成功，重试耗尽才报错弹窗。
  private retryMap: Map<string, number> = new Map();

  static getInstance(): BleService {
    if (!BleService.ins) BleService.ins = new BleService();
    return BleService.ins;
  }

  private constructor() { }

  onStateChange(cb: (s: BleState) => void): void { this.stateCb = cb; }

  setOnDeviceDiscovered(cb: (devices: DiscoveredDevice[]) => void): void { this.onDeviceDiscovered = cb; }
  setOnDeviceConnected(cb: (deviceId: string, deviceName: string) => void): void { this.onDeviceConnected = cb; }
  setOnDeviceDisconnected(cb: (deviceId: string) => void): void { this.onDeviceDisconnected = cb; }
  setOnDeviceError(cb: (deviceId: string, deviceName: string, message: string) => void): void { this.onDeviceErrorCb = cb; }
  setOnDataReplay(cb: (deviceId: string, deviceName: string) => void): void { this.onDataReplayCb = cb; }
  setOnScanError(cb: (message: string) => void): void { this.scanErrorCb = cb; }

  isRunning(): boolean { return this.running; }

  // ========== 单设备模式：自动连接（兼容旧逻辑） ==========

  async startSingle(): Promise<boolean> {
    this.running = true;
    this.multiMode = false;
    RawWaveService.getInstance().start();

    closeLog();
    try {
      let fd = fileIo.openSync(LOG_PATH, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      fileIo.closeSync(fd);
    } catch (e) { }

    try {
      ble.on('BLEDeviceFind', (results: Array<ble.ScanResult>) => {
        if (!this.running || this.singleConnecting) return;
        for (let r of results) {
          const name = r.deviceName || '';
          if (name.includes(TARGET_NAME) || name.includes('EEG') || name.includes('BLE_UART') || name.includes('BearPi')) {
            logF('[BLE-single] found: [' + name + ']');
            this.singleDevId = r.deviceId;
            this.singleConnecting = true;
            try { ble.stopBLEScan(); } catch (e) { }
            this.doConnectSingle();
            return;
          }
        }
      });
    } catch (e) {
      logF('[BLE-single] BLEDeviceFind failed: ' + JSON.stringify(e));
    }
    return this.startScan();
  }

  private doConnectSingle(): void {
    this.emit(BleState.CONNECTING);
    try {
      this.singleGatt = ble.createGattClientDevice(this.singleDevId);
      this.singleGatt.on('BLEConnectionStateChange', (data: ble.BLEConnectionChangeState) => {
        if (data.state === constant.ProfileConnectionState.STATE_CONNECTED) {
          this.onSingleConnected();
        } else if (data.state === constant.ProfileConnectionState.STATE_DISCONNECTED) {
          this.onSingleDisconnected();
        }
        // STATE_CONNECTING / STATE_DISCONNECTING 为中间态，忽略，避免误判为断开
      });
      this.singleGatt.on('BLEMtuChange', (mtu: number) => {
        this.singleMtu = mtu;
      });
      this.singleGatt.on('BLECharacteristicChange', (data: ble.BLECharacteristic) => {
        let len = data.characteristicValue ? data.characteristicValue.byteLength : 0;
        if (len > 0) this.handleSingleData(data.characteristicValue);
      });
      this.singleGatt.connect();
    } catch (e) {
      logF('[BLE-single] connect error: ' + JSON.stringify(e));
      this.emit(BleState.ERROR);
      this.singleConnecting = false;
      this.reScanSingle();
    }
  }

  private async onSingleConnected(): Promise<void> {
    try {
      this.singleGatt!.setBLEMtuSize(247);
      await this.sleep(600);
      // 用 BALANCED 而非 HIGH：脑波帧率低，够用且对小熊派固件更友好，降低被踢下线的概率
      await this.singleGatt!.updateConnectionParam(ble.ConnectionParam.BALANCED);
      await this.sleep(200);
      let svcs = await this.singleGatt!.getServices();
      await this.setupSingleNotify(svcs);
    } catch (e) {
      logF('[BLE-single] setup failed: ' + JSON.stringify(e));
      this.emit(BleState.ERROR);
    }
  }

  private async setupSingleNotify(services: Array<ble.GattService>): Promise<void> {
    let tx: ble.BLECharacteristic | null = null;
    for (let s of services) {
      if (uuidEq(s.serviceUuid, SVC_UUID_16, SVC_UUID_128)) {
        for (let c of s.characteristics) {
          if (uuidEq(c.characteristicUuid, TX_UUID_16, TX_UUID_128)) {
            tx = c;
            break;
          }
        }
      }
    }
    if (!tx) { this.emit(BleState.ERROR); return; }

    try {
      await this.singleGatt!.setCharacteristicChangeNotification(tx, false);
      await this.singleGatt!.setCharacteristicChangeNotification(tx, true);
    } catch (e) {
      this.emit(BleState.ERROR);
      return;
    }
    for (let d of tx.descriptors) {
      const u = d.descriptorUuid.toUpperCase();
      if (u === '00002902-0000-1000-8000-00805F9B34FB' || u === '00002902') {
        try {
          d.descriptorValue = new Uint8Array([0x01, 0x00]).buffer as ArrayBuffer;
          await this.singleGatt!.writeDescriptorValue(d);
        } catch (e) { }
        break;
      }
    }
    this.singleConnecting = false;
    this.singleReconnecting = false;
    let name = TARGET_NAME;
    this.store.registerDevice(this.singleDevId, name);
    this.store.setActiveDevice(this.singleDevId);
    this.store.connected = true;
    this.emit(BleState.CONNECTED);
  }

  private handleSingleData(value: ArrayBuffer): void {
    try {
      this.singlePktCount++;
      let bytes = new Uint8Array(value);
      this.singleJsonBuf += this.textDecoder.decodeToString(bytes);
      this.parseSingleFrames();
    } catch (e) { }
  }

  // 单设备模式帧解析：优先整帧，其次按换行分帧，处理粘包与半包
  private parseSingleFrames(): void {
    // 1) 整段恰好是一帧 JSON
    try {
      const frameText = this.singleJsonBuf.trim();
      const data: EEGData = JSON.parse(frameText) as EEGData;
      this.singleJsonBuf = '';
      this.store.updateData(data);
      return;
    } catch (e) { }

    // 2) 按换行分帧：处理所有完整行，未完成尾部保留
    const nl = this.singleJsonBuf.lastIndexOf('\n');
    if (nl >= 0) {
      const completeLines = this.singleJsonBuf.substring(0, nl).split('\n');
      this.singleJsonBuf = this.singleJsonBuf.substring(nl + 1);
      for (const line of completeLines) {
        const t = line.trim();
        if (t.length === 0) continue;
        try {
          const data: EEGData = JSON.parse(t) as EEGData;
          this.store.updateData(data);
        } catch (e) { }
      }
      return;
    }

    // 3) 无换行且超长（异常粘包）→ 清空保护
    if (this.singleJsonBuf.length > 1024) {
      this.singleJsonBuf = '';
    }
  }

  private onSingleDisconnected(): void {
    this.store.connected = false;
    this.emit(BleState.DISCONNECTED);
    if (this.running && !this.singleReconnecting) {
      this.reScanSingle();
    }
  }

  private reScanSingle(): void {
    if (!this.running) return;
    this.singleReconnecting = true;
    this.singleConnecting = false;
    this.singleJsonBuf = '';
    setTimeout(() => { if (this.running) this.startScan(); }, 2000);
  }

  // ========== 多设备模式：手动连接 ==========

  async startMultiScan(): Promise<void> {
    this.multiMode = true;
    this.running = true;
    this.discoveredDevices.clear();
    RawWaveService.getInstance().start();

    try {
      ble.on('BLEDeviceFind', (results: Array<ble.ScanResult>) => {
        if (!this.running) return;
        for (let r of results) {
          const name = r.deviceName || '';
          // 显示所有附近设备（脑环可能使用不同名称），连接后按 EE01/EE02 服务识别
          if (!this.discoveredDevices.has(r.deviceId)) {
            this.discoveredDevices.set(r.deviceId, {
              deviceId: r.deviceId,
              deviceName: name || '(未命名)',
              rssi: r.rssi
            });
            if (this.onDeviceDiscovered) {
              this.onDeviceDiscovered(this.getDiscoveredDevices());
            }
          }
        }
      });
    } catch (e) {
      logF('[BLE-multi] BLEDeviceFind failed: ' + JSON.stringify(e));
    }
    this.startScan();
    this.emit(BleState.SCANNING);
  }

  getDiscoveredDevices(): DiscoveredDevice[] {
    return Array.from(this.discoveredDevices.values());
  }

  getConnectedDeviceIds(): string[] {
    // 只统计真正连接成功的会话（connecting=false），连接中/失败的设备不算"已连接"
    const ids: string[] = [];
    this.sessions.forEach((s: GattSession, id: string) => {
      if (!s.connecting) { ids.push(id); }
    });
    return ids;
  }

  getConnectingDeviceIds(): string[] {
    // 正在发起连接（尚未成功）的设备
    const ids: string[] = [];
    this.sessions.forEach((s: GattSession, id: string) => {
      if (s.connecting) { ids.push(id); }
    });
    return ids;
  }

  isDeviceConnected(deviceId: string): boolean {
    const s = this.sessions.get(deviceId);
    return s !== undefined && !s.connecting;
  }

  isDeviceConnecting(deviceId: string): boolean {
    const s = this.sessions.get(deviceId);
    return s !== undefined && s.connecting;
  }

  async connectDevice(deviceId: string, deviceName: string, isAutoRetry: boolean = false): Promise<void> {
    if (this.sessions.has(deviceId)) return;
    // 用户手动发起的连接重置重试计数；自动重试不重置，避免无限重试
    if (!isAutoRetry) { this.retryMap.set(deviceId, 0); }

    let gattClient: ble.GattClientDevice = ble.createGattClientDevice(deviceId);
    let session: GattSession = {
      gatt: gattClient,
      mtu: 23,
      jsonBuffer: '',
      pktCount: 0,
      frameCount: 0,
      connecting: true,
      initialized: false,
      connectTimer: 0,
      reconnecting: false,
      dataParsed: false,
      unparsedBytes: 0,
      formatWarned: false,
      lastFrameKey: '',
      repeatCount: 0,
      repeatWarned: false
    };

    try {
      session.gatt.on('BLEConnectionStateChange', (data: ble.BLEConnectionChangeState) => {
        if (data.state === constant.ProfileConnectionState.STATE_CONNECTED) {
          this.onMultiDeviceConnected(deviceId);
        } else if (data.state === constant.ProfileConnectionState.STATE_DISCONNECTED) {
          this.onMultiDeviceDisconnected(deviceId);
        }
        // STATE_CONNECTING / STATE_DISCONNECTING 为中间态，忽略，避免连接刚发起就被误判为失败
      });
      session.gatt.on('BLEMtuChange', (mtu: number) => { session.mtu = mtu; });
      session.gatt.on('BLECharacteristicChange', (data: ble.BLECharacteristic) => {
        let len = data.characteristicValue ? data.characteristicValue.byteLength : 0;
        if (len > 0) this.handleMultiData(deviceId, data.characteristicValue);
      });

      this.sessions.set(deviceId, session);
      session.gatt.connect();
      session.connectTimer = setTimeout(() => {
        const s = this.sessions.get(deviceId);
        if (s && s.connecting) {
          s.connecting = false;
          if (s.connectTimer) { clearTimeout(s.connectTimer); s.connectTimer = 0; }
          this.sessions.delete(deviceId);
          try { s.gatt.disconnect(); } catch (e) { }
          try { s.gatt.close(); } catch (e) { }
          this.reportDeviceError(deviceId, '连接超时（30 秒），请确认脑环已开机并处于可连接状态');
          if (this.onDeviceDisconnected) {
            this.onDeviceDisconnected(deviceId);
          }
        }
      }, 30000);
      logF('[BLE-multi] connecting to ' + deviceName);
    } catch (e) {
      logF('[BLE-multi] connect error: ' + JSON.stringify(e));
      if (session.connectTimer) { clearTimeout(session.connectTimer); session.connectTimer = 0; }
      try { gattClient.close(); } catch (e2) { }
      this.sessions.delete(deviceId);
      this.reportDeviceError(deviceId, '发起连接失败：' + JSON.stringify(e));
    }
  }

  private async onMultiDeviceConnected(deviceId: string): Promise<void> {
    const session = this.sessions.get(deviceId);
    if (!session) return;
    // 系统可能重复上报 STATE_CONNECTED（例如配对完成后再次回调），
    // 这里只允许初始化一次，避免重复订阅特征导致 2900099“开启数据通知失败”。
    if (session.initialized) return;
    session.initialized = true;
    try {
      // 注意：不要在服务发现之前请求 MTU/连接参数！
      // 实测（BearPi H3863 + 鸿蒙平板）：发现服务前发 MTU 请求会和
      // 服务发现命令冲突（bta_gattc_enqueue: already has a pending command），
      // 导致 getServices() 挂起 10 秒后超时返回空列表，连接被判失败。
      // 正确顺序：连接 -> 服务发现 -> 订阅通知 -> 再协商 MTU/连接参数。
      await this.sleep(300);
      let svcs = await session.gatt.getServices();
      // 个别设备服务发现较慢，空结果时重试两次
      let retries = 0;
      while ((!svcs || svcs.length === 0) && retries < 2) {
        await this.sleep(1000);
        svcs = await session.gatt.getServices();
        retries++;
      }
      const ok = await this.setupMultiNotify(deviceId, svcs);
      if (ok) {
        // MTU/连接参数协商放到通知开启之后，失败也不影响收数据
        try { await session.gatt.setBLEMtuSize(247); } catch (e) {
          logF('[BLE-multi] MTU 协商失败（忽略，默认 MTU 分片也能收数据）');
        }
        // 用 BALANCED 而非 HIGH：脑波帧率低，够用且对小熊派固件更友好，降低被踢下线的概率
        try { await session.gatt.updateConnectionParam(ble.ConnectionParam.BALANCED); } catch (e) {
          logF('[BLE-multi] 连接参数协商失败（忽略）');
        }
      }
    } catch (e) {
      logF('[BLE-multi] setup ' + deviceId + ' failed: ' + JSON.stringify(e));
      const info = this.discoveredDevices.get(deviceId);
      const name = info ? info.deviceName : deviceId;
      if (!this.scheduleAutoRetry(deviceId, name)) {
        this.reportDeviceError(deviceId, '连接后初始化失败：' + JSON.stringify(e));
      }
      this.teardownSession(deviceId);
    }
  }

  private async setupMultiNotify(deviceId: string, services: Array<ble.GattService>): Promise<boolean> {
    const session = this.sessions.get(deviceId);
    if (!session) return false;

    // 诊断：记录设备实际提供的服务（用于判断固件协议是否匹配）
    let svcSummary = '';
    services.forEach((s: ble.GattService) => {
      svcSummary += (svcSummary.length > 0 ? ', ' : '') + s.serviceUuid;
    });
    logF('[BLE-multi] services of ' + deviceId + ': ' + svcSummary);

    let tx: ble.BLECharacteristic | null = null;
    for (const s of services) {
      if (uuidEq(s.serviceUuid, SVC_UUID_16, SVC_UUID_128)) {
        for (const c of s.characteristics) {
          if (uuidEq(c.characteristicUuid, TX_UUID_16, TX_UUID_128)) {
            tx = c;
            break;
          }
        }
      }
      if (tx) break;
    }

    // 兜底：未找到 EE01/EE02 时，自动匹配第一个可通知/可指示的特征（常见 UART 透传固件）
    let fallbackUsed = false;
    if (!tx) {
      tx = this.firstNotifyCharacteristic(services);
      fallbackUsed = tx !== null;
    }
    if (!tx) {
      this.reportDeviceError(deviceId, '已连接，但设备没有可接收数据的特征。该设备提供的服务：' + (svcSummary || '（无）'));
      this.teardownSession(deviceId);
      return false;
    }

    // 先关闭再开启通知；关闭失败不要紧（有些系统对未开启的特征执行关闭会报错），
    // 不能因为关闭失败就把整个会话拆除，否则会出现“连上了但一直收不到数据”。
    try {
      await session.gatt.setCharacteristicChangeNotification(tx, false);
    } catch (e) {
      logF('[BLE-multi] 关闭通知失败（忽略）：' + JSON.stringify(e));
    }
    try {
      await session.gatt.setCharacteristicChangeNotification(tx, true);
    } catch (e) {
      const info = this.discoveredDevices.get(deviceId);
      const name = info ? info.deviceName : deviceId;
      if (!this.scheduleAutoRetry(deviceId, name)) {
        this.reportDeviceError(deviceId, '开启数据通知失败：' + JSON.stringify(e));
      }
      this.teardownSession(deviceId);
      return false;
    }

    let cccdWritten = false;
    for (const d of tx.descriptors) {
      const u = d.descriptorUuid.toUpperCase();
      if (u === '00002902-0000-1000-8000-00805F9B34FB' || u === '00002902') {
        try {
          // 仅支持 indicate 的特征写 0x02，否则写 0x01（notify）
          const isIndicateOnly = tx.properties !== undefined && tx.properties.indicate === true && tx.properties.notify !== true;
          d.descriptorValue = new Uint8Array(isIndicateOnly ? [0x02, 0x00] : [0x01, 0x00]).buffer as ArrayBuffer;
          await session.gatt.writeDescriptorValue(d);
          cccdWritten = true;
        } catch (e) {
          logF('[BLE-multi] CCCD 写入失败（忽略）：' + JSON.stringify(e));
        }
        break;
      }
    }

    session.connecting = false;
    if (session.connectTimer) { clearTimeout(session.connectTimer); session.connectTimer = 0; }
    this.retryMap.delete(deviceId);
    const info = this.discoveredDevices.get(deviceId);
    const name = info ? info.deviceName : deviceId;
    this.store.registerDevice(deviceId, name);
    this.store.setActiveDevice(deviceId);
    this.store.connected = true;
    logF('[BLE-multi] connected: ' + name + (fallbackUsed ? ' (fallback: ' + tx.characteristicUuid + ')' : '') +
      ' tx=' + tx.characteristicUuid + ' cccd=' + (cccdWritten ? 'written' : 'skipped'));
    this.emit(BleState.CONNECTED);
    if (this.onDeviceConnected) {
      this.onDeviceConnected(deviceId, name);
    }
    return true;
  }

  private handleMultiData(deviceId: string, value: ArrayBuffer): void {
    const session = this.sessions.get(deviceId);
    if (!session) return;
    try {
      session.pktCount++;
      const bytes = new Uint8Array(value);
      session.jsonBuffer += this.textDecoder.decodeToString(bytes);
      // 诊断：前 5 包与每 100 包记录一次收包情况，便于确认数据是否真的到达平板
      if (session.pktCount <= 5 || session.pktCount % 100 === 0) {
        logF('[BLE-multi] ' + deviceId + ' pkt#' + session.pktCount + ' +' + bytes.length + 'B buf=' + session.jsonBuffer.length + 'B');
      }
      this.tryParseFrames(deviceId, session, bytes.length);
    } catch (e) {
      logF('[BLE-multi] 数据回调异常：' + JSON.stringify(e));
    }
  }

  private tryParseFrames(deviceId: string, session: GattSession, bytesLen: number): void {
    // 1) 整段恰好是一帧 JSON
    try {
      const frameText = session.jsonBuffer.trim();
      const data: EEGData = JSON.parse(frameText) as EEGData;
      session.jsonBuffer = '';
      this.consumeFrame(deviceId, session, data, frameText);
      return;
    } catch (e) { }

    // 2) 固件以换行分隔多帧：处理所有完整行，未完成的尾部保留到下一包
    const nl = session.jsonBuffer.lastIndexOf('\n');
    if (nl >= 0) {
      const completeLines = session.jsonBuffer.substring(0, nl).split('\n');
      session.jsonBuffer = session.jsonBuffer.substring(nl + 1);
      for (const line of completeLines) {
        const t = line.trim();
        if (t.length === 0) continue;
        try {
          const data: EEGData = JSON.parse(t) as EEGData;
          this.consumeFrame(deviceId, session, data, t);
        } catch (e) { }
      }
      return;
    }

    // 3) 花括号配对：兼容“无换行分隔 + 分片/粘包”的固件（当前小熊派固件帧之间没有 \n）
    const cut = this.extractFramesByBraces(deviceId, session);
    if (cut > 0) {
      session.jsonBuffer = session.jsonBuffer.substring(cut);
      return;
    }

    // 4) 无换行且超长（异常粘包/非 JSON 数据）→ 清空保护，避免缓冲区无限膨胀
    if (session.jsonBuffer.length > 16384) {
      logF('[BLE-multi] 缓冲区超长无法解析，采样：' + session.jsonBuffer.substring(0, 120));
      session.jsonBuffer = '';
      session.unparsedBytes += bytesLen;
      if (!session.dataParsed && !session.formatWarned && session.unparsedBytes > 4096) {
        session.formatWarned = true;
        this.reportDeviceError(deviceId, '已连接并收到数据，但格式无法解析（固件可能不是本 App 的 JSON 协议）');
      }
    }
  }

  // 用花括号配对从缓冲区中提取完整 JSON 帧，返回已消费的字节数；
  // 未闭合的尾部（分片帧）会留在缓冲区等待下一包。
  private extractFramesByBraces(deviceId: string, session: GattSession): number {
    const buf = session.jsonBuffer;
    let cut = 0;
    let start = -1;
    let depth = 0;
    for (let i = 0; i < buf.length; i++) {
      const ch = buf[i];
      if (ch === '{') {
        if (depth === 0) {
          start = i;
        }
        depth++;
      } else if (ch === '}') {
        if (depth > 0) {
          depth--;
          if (depth === 0 && start >= 0) {
            const frameText = buf.substring(start, i + 1);
            cut = i + 1;
            start = -1;
            try {
              const data: EEGData = JSON.parse(frameText) as EEGData;
              this.consumeFrame(deviceId, session, data, frameText);
            } catch (e) { }
          }
        }
      }
    }
    return cut;
  }

  // 数据帧消费入口：检测固件重复发送（缓冲回环等异常）时丢弃并提示一次
  private consumeFrame(deviceId: string, session: GattSession, data: EEGData, frameText: string): void {
    session.dataParsed = true;
    session.frameCount++;
    // 兼容不同固件的原始波形字段名：部分固件不用 raw/r，而用 w/wave/v/samples 等
    if (data.raw === undefined && (data.r === undefined || data.r.length === 0)) {
      try {
        const obj: Record<string, Object> = JSON.parse(frameText) as Record<string, Object>;
        const rVal = obj['r'] as number[] | undefined;
        if (rVal !== undefined && rVal.length > 0) {
          data.r = rVal;
        } else {
          const rawVal = obj['raw'] as number | undefined;
          if (typeof rawVal === 'number') {
            data.raw = rawVal;
          } else {
            const wVal = obj['w'] as number | undefined;
            if (typeof wVal === 'number') {
              data.raw = wVal;
            } else {
              const waveVal = obj['wave'] as number | undefined;
              if (typeof waveVal === 'number') {
                data.raw = waveVal;
              } else {
                const vVal = obj['v'] as number | undefined;
                if (typeof vVal === 'number') {
                  data.raw = vVal;
                }
              }
            }
          }
        }
      } catch (e) { }
    }
    if (session.frameCount <= 3 || session.frameCount % 500 === 0) {
      logF('[BLE-multi] 解析帧 #' + session.frameCount + ' sig=' + data.sig + ' att=' + data.att + ' med=' + data.med +
        ' raw=' + data.raw + ' d=' + data.d + ' t=' + data.t + ' aL=' + data.aL + ' aH=' + data.aH +
        ' bL=' + data.bL + ' bH=' + data.bH + ' gL=' + data.gL + ' gM=' + data.gM +
        ' text=' + frameText.substring(0, 200));
    }
    if (frameText === session.lastFrameKey) {
      session.repeatCount++;
      if (session.repeatCount >= 8 && !session.repeatWarned) {
        session.repeatWarned = true;
        logF('[BLE-multi] 检测到固件重复发送同一数据帧（连续 ' + session.repeatCount.toString() + ' 次）: ' + deviceId);
        const info = this.discoveredDevices.get(deviceId);
        const name = info ? info.deviceName : deviceId;
        if (this.onDataReplayCb) {
          this.onDataReplayCb(deviceId, name);
        }
      }
      return;
    }
    session.lastFrameKey = frameText;
    session.repeatCount = 0;
    session.repeatWarned = false;
    this.store.updateDeviceData(deviceId, data);
  }

  private onMultiDeviceDisconnected(deviceId: string): void {
    const session = this.sessions.get(deviceId);
    if (!session) return;
    const wasConnecting = session.connecting;
    session.connecting = false;
    if (session.connectTimer) { clearTimeout(session.connectTimer); session.connectTimer = 0; }
    this.sessions.delete(deviceId);
    this.store.removeDevice(deviceId);
    logF('[BLE-multi] disconnected: ' + deviceId);
    const info = this.discoveredDevices.get(deviceId);
    const name = info ? info.deviceName : deviceId;
    if (wasConnecting) {
      // 连接被固件秒断时自动重试（最多 2 次），避免频繁弹窗
      if (this.scheduleAutoRetry(deviceId, name)) {
        if (this.onDeviceDisconnected) {
          this.onDeviceDisconnected(deviceId);
        }
        return;
      }
      this.reportDeviceError(deviceId, '连接被拒绝或超时，请确认脑环已开机且允许连接');
    } else {
      // 已建立的数据连接意外断开：做有限次自动重连，避免界面长期停在“无数据”状态
      if (this.scheduleAutoRetry(deviceId, name)) {
        logF('[BLE-multi] 已连接会话断开，安排自动重连: ' + deviceId);
      }
    }
    if (this.onDeviceDisconnected) {
      this.onDeviceDisconnected(deviceId);
    }
  }

  private firstNotifyCharacteristic(services: Array<ble.GattService>): ble.BLECharacteristic | null {
    // 优先匹配常见的 UART 透传类服务（FFE0/FFF0/Nordic UART/ISSC 等）
    let best: ble.BLECharacteristic | null = null;
    for (const s of services) {
      const su = s.serviceUuid.toUpperCase();
      // BearPi H3863 官方 BLE UART 透传示例：服务 0xABCD / 通知 0xCDEF / 写入 0xEFEF
      const isUartLike = su.indexOf('FFE0') >= 0 || su.indexOf('FFE5') >= 0 ||
        su.indexOf('FFF0') >= 0 || su.indexOf('6E4000') >= 0 || su.indexOf('49535343') >= 0 ||
        su.indexOf('ABCD') >= 0 || su.indexOf('CDEF') >= 0;
      for (const c of s.characteristics) {
        if (c.properties && (c.properties.notify || c.properties.indicate)) {
          if (isUartLike) {
            return c;
          }
          if (!best) {
            best = c;
          }
        }
      }
    }
    return best;
  }

  // 自动重试调度：小熊派固件有时会在连接建立/订阅通知时秒断（HCI reason 19），
  // 最多自动重试 2 次；返回 true 表示已安排重试，false 表示重试已耗尽。
  private scheduleAutoRetry(deviceId: string, deviceName: string): boolean {
    const retries = this.retryMap.get(deviceId) ?? 0;
    if (retries >= 2) {
      this.retryMap.delete(deviceId);
      return false;
    }
    this.retryMap.set(deviceId, retries + 1);
    logF('[BLE-multi] 连接中断，' + (retries + 1).toString() + '/2 次自动重试: ' + deviceId);
    setTimeout(() => {
      if (this.sessions.has(deviceId)) return;
      this.connectDevice(deviceId, deviceName, true);
    }, 2000);
    return true;
  }

  private reportDeviceError(deviceId: string, message: string): void {
    logF('[BLE-multi] ' + message);
    const info = this.discoveredDevices.get(deviceId);
    const name = info ? info.deviceName : deviceId;
    if (this.onDeviceErrorCb) {
      this.onDeviceErrorCb(deviceId, name, message);
    }
  }

  private teardownSession(deviceId: string): void {
    const session = this.sessions.get(deviceId);
    if (!session) return;
    if (session.connectTimer) { clearTimeout(session.connectTimer); session.connectTimer = 0; }
    try { session.gatt.disconnect(); } catch (e) { }
    try { session.gatt.close(); } catch (e) { }
    this.sessions.delete(deviceId);
    this.store.removeDevice(deviceId);
    if (this.onDeviceDisconnected) {
      this.onDeviceDisconnected(deviceId);
    }
  }

  disconnectDevice(deviceId: string): void {
    let session = this.sessions.get(deviceId);
    if (!session) return;
    if (session.connectTimer) { clearTimeout(session.connectTimer); session.connectTimer = 0; }
    this.retryMap.delete(deviceId);
    try { session.gatt.disconnect(); } catch (e) { }
    try { session.gatt.close(); } catch (e) { }
    this.sessions.delete(deviceId);
    this.store.removeDevice(deviceId);
  }

  disconnectAll(): void {
    let ids = Array.from(this.sessions.keys());
    for (let id of ids) {
      this.disconnectDevice(id);
    }
  }

  // ========== 共用 ==========

  private startScan(): boolean {
    try {
      ble.startBLEScan(null, {
        interval: 0,
        dutyMode: ble.ScanDuty.SCAN_MODE_LOW_LATENCY,
        matchMode: ble.MatchMode.MATCH_MODE_AGGRESSIVE
      });
      return true;
    } catch (e) {
      this.emit(BleState.ERROR);
      const msg = JSON.stringify(e);
      if (this.scanErrorCb) {
        if (msg.indexOf('201') >= 0 || msg.indexOf('Permission') >= 0 || msg.indexOf('permission') >= 0) {
          this.scanErrorCb('蓝牙权限未授权，请在系统设置中允许本应用使用蓝牙后重试');
        } else {
          this.scanErrorCb('蓝牙扫描失败，请检查平板蓝牙是否开启');
        }
      }
      return false;
    }
  }

  stopScan(): void {
    try { ble.stopBLEScan(); } catch (e) { }
    try { ble.off('BLEDeviceFind'); } catch (e) { }
  }

  stop(): void {
    this.running = false;
    RawWaveService.getInstance().stop();
    this.stopScan();
    if (this.singleGatt) {
      try { this.singleGatt.disconnect(); } catch (e) { }
      try { this.singleGatt.close(); } catch (e) { }
      this.singleGatt = null;
    }
    if (this.multiMode) {
      this.disconnectAll();
    }
    closeLog();
    this.emit(BleState.IDLE);
  }

  private sleep(ms: number): Promise<void> {
    return new Promise<void>(resolve => setTimeout(resolve, ms));
  }

  private emit(s: BleState): void {
    if (this.stateCb) {
      try { this.stateCb(s); } catch (e) { }
    }
  }
}
