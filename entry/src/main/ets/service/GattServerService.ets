import ble from '@ohos.bluetooth.ble';
import constant from '@ohos.bluetooth.constant';
import { util } from '@kit.ArkTS';
import { EEGDataStore, EEGData } from '../store/EEGDataStore';
import { MockDataService } from '../service/MockDataService';

const SVC_UUID = '0000EE01-0000-1000-8000-00805F9B34FB';
const TX_UUID  = '0000EE02-0000-1000-8000-00805F9B34FB';
const DEVICE_ID = 'mini_program';
const DEVICE_NAME = '小程序';
const MAX_LOGS = 50;

export enum GattServerError {
  PERMISSION_DENIED = 'PERMISSION_DENIED',
  BT_DISABLED = 'BT_DISABLED',
  CREATE_SERVER_FAILED = 'CREATE_SERVER_FAILED',
  ADD_SERVICE_FAILED = 'ADD_SERVICE_FAILED',
  ADVERTISE_FAILED = 'ADVERTISE_FAILED',
  UNKNOWN = 'UNKNOWN'
}

export interface GattLogEvent {
  type: 'info' | 'connected' | 'disconnected' | 'data' | 'error';
  timestamp: number;
  message: string;
  frameCount?: number;
  deviceId?: string;
}

export class GattServerService {
  private static ins: GattServerService;
  private store: EEGDataStore = EEGDataStore.getInstance();
  private server: ble.GattServer | null = null;
  private running: boolean = false;
  private jsonBuf: string = '';
  private textDecoder: util.TextDecoder = new util.TextDecoder('utf-8');
  private connectedDevices: Set<string> = new Set();
  private stateCb: ((running: boolean, connCount: number) => void) | null = null;
  private errorCb: ((code: GattServerError, message: string) => void) | null = null;
  private logCb: ((event: GattLogEvent) => void) | null = null;
  private logs: GattLogEvent[] = [];
  private frameCount: number = 0;
  private retryTimer: number = -1;
  private dataStarted: boolean = false;
  lastError: string = '';

  static getInstance(): GattServerService {
    if (!GattServerService.ins) GattServerService.ins = new GattServerService();
    return GattServerService.ins;
  }
  private constructor() {}

  isRunning(): boolean { return this.running; }
  getConnectedCount(): number { return this.connectedDevices.size; }
  getFrameCount(): number { return this.frameCount; }
  getLogs(): GattLogEvent[] { return [...this.logs]; }
  onStateChange(cb: (running: boolean, connCount: number) => void): void { this.stateCb = cb; }
  onError(cb: (code: GattServerError, message: string) => void): void { this.errorCb = cb; }
  onLog(cb: (event: GattLogEvent) => void): void { this.logCb = cb; }

  // ========== 启动 ==========

  start(): void { this.cancelRetry(); this.attemptStart(false); }

  private attemptStart(isRetry: boolean): void {
    if (this.running) return;
    this.lastError = '';
    this.running = true;
    this.jsonBuf = '';
    this.frameCount = 0;
    this.dataStarted = false;
    this.connectedDevices.clear();
    this.logs = [];

    try {
      this.server = ble.createGattServer();
      if (!this.server) {
        if (isRetry) { this.reportError(GattServerError.CREATE_SERVER_FAILED, '无法创建 GATT 服务端'); }
        else { this.scheduleRetry('BLE 未就绪，自动重试...'); }
        return;
      }

      // ★ 事件监听：必须在 addService 之前注册
      this.server.on('connectionStateChange', (data: ble.BLEConnectionChangeState) => {
        console.info('[GattServer] connectionStateChange: state=' + data.state + ' devId=' + data.deviceId);
        if (data.state === constant.ProfileConnectionState.STATE_CONNECTED) {
          this.connectedDevices.add(data.deviceId);
          const sid = data.deviceId.substring(data.deviceId.length - 8);
          this.addLog('connected', '已连接 ' + sid, data.deviceId);
        } else {
          this.connectedDevices.delete(data.deviceId);
          const sid = data.deviceId.substring(data.deviceId.length - 8);
          this.addLog('disconnected', '已断开 ' + sid, data.deviceId);
        }
        this.emitState();
      });

      this.server.on('characteristicWrite', (req: ble.CharacteristicWriteRequest) => {
        // ★ 立即发 ACK（第一件事，确保小程序不超时）
        if (req.needRsp) {
          this.server!.sendResponse({
            deviceId: req.deviceId, transId: req.transId,
            status: 0, offset: req.offset, value: new ArrayBuffer(0)
          });
        }
        // 然后处理数据
        this.handleWrite(req);
      });

      // 添加 GATT 服务（Write With Response）
      const characteristic: ble.BLECharacteristic = {
        serviceUuid: SVC_UUID,
        characteristicUuid: TX_UUID,
        characteristicValue: new ArrayBuffer(512),
        properties: { write: true },
        permissions: { write: true },
        descriptors: []
      };
      const service: ble.GattService = {
        serviceUuid: SVC_UUID,
        isPrimary: true,
        characteristics: [characteristic]
      };
      this.server.addService(service);
      this.addLog('info', 'GATT 服务注册成功');

      // 开始广播
      ble.startAdvertising(
        { interval: 160, txPower: 0, connectable: true },
        { serviceUuids: [SVC_UUID], manufactureData: [], serviceData: [] }
      );
      this.addLog('info', '开始广播，等待小程序...');
      this.emitState();
      console.info('[GattServer] 启动成功');
    } catch (e) {
      const em = JSON.stringify(e);
      console.error('[GattServer] 启动异常: ' + em);
      if (isRetry) {
        this.addLog('error', '重试仍失败: ' + em);
        this.reportError(GattServerError.UNKNOWN, '启动失败: ' + em);
      } else {
        this.scheduleRetry('初化异常，500ms 后重试...');
      }
    }
  }

  // ========== 处理写入 ==========

  private handleWrite(req: ble.CharacteristicWriteRequest): void {
    try {
      const arr = new Uint8Array(req.value);
      const text = this.textDecoder.decodeToString(arr);
      console.info('[GattServer] WRITE 收到 ' + arr.byteLength + ' 字节: ' + text.substring(0, 60));

      // 简约处理：整帧 JSON
      try {
        const parsed: EEGData = JSON.parse(text) as EEGData;
        this.store.registerDevice(DEVICE_ID, DEVICE_NAME);
        this.store.updateDeviceData(DEVICE_ID, parsed);
        this.frameCount++;

        if (!this.dataStarted) {
          this.dataStarted = true;
          MockDataService.getInstance().stop();
          this.addLog('info', '开始接收数据 · 模拟器已停');
        }
        if (this.frameCount % 5 === 0) {
          this.addLog('data', '已收 ' + this.frameCount + ' 帧 · Att=' + parsed.att + ' Med=' + parsed.med);
        }
      } catch (_e) {
        // 可能是分片（MTU 小的情况），累积
        this.jsonBuf += text;
        try {
          const p2: EEGData = JSON.parse(this.jsonBuf) as EEGData;
          this.store.registerDevice(DEVICE_ID, DEVICE_NAME);
          this.store.updateDeviceData(DEVICE_ID, p2);
          this.frameCount++;
          this.jsonBuf = '';
          if (!this.dataStarted) {
            this.dataStarted = true;
            MockDataService.getInstance().stop();
            this.addLog('info', '开始接收数据(分片) · 模拟器已停');
          }
          if (this.frameCount % 5 === 0) {
            this.addLog('data', '已收 ' + this.frameCount + ' 帧(分片拼合)');
          }
        } catch (_e2) {
          if (this.jsonBuf.length > 4096) { this.jsonBuf = ''; }
        }
      }
    } catch (e) {
      console.error('[GattServer] handleWrite 异常: ' + JSON.stringify(e));
    }
  }

  // ========== 停止 ==========

  stop(): void {
    this.cancelRetry();
    if (!this.running && !this.server) return;
    this.running = false;
    this.jsonBuf = '';
    this.frameCount = 0;
    try { ble.stopAdvertising(); } catch (e) {}
    if (this.server) {
      try { this.server.removeService(SVC_UUID); } catch (e) {}
      try { this.server.close(); } catch (e) {}
      this.server = null;
    }
    this.connectedDevices.clear();
    this.addLog('info', '服务端已停止');
    this.emitState();
  }

  // ========== 内部 ==========

  private scheduleRetry(msg: string): void {
    this.running = false;
    this.jsonBuf = '';
    if (this.server) { try { this.server.close(); } catch (e) {} this.server = null; }
    this.addLog('info', msg);
    this.retryTimer = setTimeout(() => { this.retryTimer = -1; this.attemptStart(true); }, 500);
  }

  private cancelRetry(): void {
    if (this.retryTimer >= 0) { clearTimeout(this.retryTimer); this.retryTimer = -1; }
  }

  private reportError(code: GattServerError, msg: string): void {
    this.running = false;
    this.lastError = msg;
    this.addLog('error', msg);
    this.stop();
    if (this.errorCb) { try { this.errorCb(code, msg); } catch (e) {} }
  }

  private addLog(type: 'info' | 'connected' | 'disconnected' | 'data' | 'error', msg: string, devId?: string, fc?: number): void {
    const ev: GattLogEvent = { type: type, timestamp: Date.now(), message: msg, deviceId: devId, frameCount: fc };
    this.logs.push(ev);
    if (this.logs.length > MAX_LOGS) this.logs.shift();
    if (this.logCb) { try { this.logCb(ev); } catch (e) {} }
  }

  private emitState(): void {
    if (this.stateCb) { try { this.stateCb(this.running, this.connectedDevices.size); } catch (e) {} }
  }
}
