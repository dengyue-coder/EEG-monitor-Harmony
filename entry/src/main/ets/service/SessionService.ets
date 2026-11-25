import { EEGDataStore } from '../store/EEGDataStore';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

const store = EEGDataStore.getInstance();
const SESSIONS_DIR = '/data/storage/el2/base/haps/entry/files/sessions/';
const MAX_SESSIONS = 10;

export class SessionSnapshot {
  sec: number = 0; sig: number = 0; att: number = 0; med: number = 0;
  raw: number = 0; d: number = 0; theta: number = 0;
  aL: number = 0; aH: number = 0; bL: number = 0; bH: number = 0;
  gL: number = 0; gM: number = 0;
}

export class SessionStats {
  avgAtt: number = 0; avgMed: number = 0;
  maxAtt: number = 0; maxMed: number = 0;
  totalBlinks: number = 0; dataPoints: number = 0;
}

export class SessionMeta {
  id: string = ''; startTime: number = 0; endTime: number = 0;
  durationSec: number = 0; stats: SessionStats = new SessionStats();
}

export interface SessionData {
  id: string;
  startTime: number;
  endTime: number;
  durationSec: number;
  stats: SessionStats;
  snapshots: SessionSnapshot[];
}

export class SessionService {
  private static instance: SessionService;
  private sessionId: string = '';
  private startTime: number = 0;
  private active: boolean = false;
  private snapshots: SessionSnapshot[] = [];
  private totalBlinks: number = 0;
  private attSum: number = 0;
  private medSum: number = 0;
  private maxAttVal: number = 0;
  private maxMedVal: number = 0;
  private dataPointCount: number = 0;
  private snapshotTimer: number = -1;
  private saveTimer: number = -1;
  private listeners: Set<() => void> = new Set();

  static getInstance(): SessionService {
    if (!SessionService.instance) SessionService.instance = new SessionService();
    return SessionService.instance;
  }

  private constructor() {}

  onChanged(cb: () => void): () => void {
    this.listeners.add(cb);
    return () => { this.listeners.delete(cb); };
  }

  private notify(): void {
    this.listeners.forEach(cb => { try { cb(); } catch (e) {} });
  }

  startSession(deviceId?: string): void {
    if (this.active) return;
    this.active = true;
    const dId = deviceId || store.getActiveDeviceId();
    const now = Date.now();
    this.startTime = now;
    this.snapshots = [];
    this.totalBlinks = 0;
    this.attSum = 0;
    this.medSum = 0;
    this.maxAttVal = 0;
    this.maxMedVal = 0;
    this.dataPointCount = 0;

    const d = new Date(now);
    const devShort = dId.length > 12 ? dId.substring(0, 12) : dId;
    this.sessionId = `${d.getFullYear()}${this.p2(d.getMonth() + 1)}${this.p2(d.getDate())}_${this.p2(d.getHours())}${this.p2(d.getMinutes())}${this.p2(d.getSeconds())}_${devShort}`;

    this.snapshotTimer = setInterval(() => { this.takeSnapshot(); }, 1000);
    this.saveTimer = setInterval(() => { this.doSave(); }, 10000);

    console.info('[Session] started: ' + this.sessionId);
  }

  endSession(): void {
    if (!this.active) return;
    this.active = false;
    this.clearTimers();
    this.doSave();
    this.notify();
    console.info('[Session] ended: ' + this.sessionId);
  }

  incrementBlinks(): void {
    if (this.active) this.totalBlinks++;
  }

  getSessionId(): string { return this.sessionId; }
  isActive(): boolean { return this.active; }
  getTotalBlinks(): number { return this.totalBlinks; }

  getRecentSessions(limit: number): SessionMeta[] {
    try {
      fileIo.mkdirSync(SESSIONS_DIR, true);
      const files = fileIo.listFileSync(SESSIONS_DIR);
      const sessions: SessionMeta[] = [];
      for (let i = 0; i < files.length; i++) {
        if (!files[i].endsWith('.json')) continue;
        const meta = this.readMeta(files[i]);
        if (meta) sessions.push(meta);
      }
      sessions.sort((a, b) => b.startTime - a.startTime);
      return sessions.slice(0, limit);
    } catch (e) {
      console.error('[Session] list failed: ' + JSON.stringify(e));
      return [];
    }
  }

  // ========== doSave 改为 public，EntryAbility 在退后台时调用 ==========

  doSave(): void {
    if (this.snapshots.length === 0) return;
    try {
      fileIo.mkdirSync(SESSIONS_DIR, true);
      const n = this.dataPointCount || 1;
      const now = Date.now();
      const end = this.active ? now : this.startTime + this.snapshots[this.snapshots.length - 1].sec * 1000;
      const data: SessionData = {
        id: this.sessionId,
        startTime: this.startTime,
        endTime: end,
        durationSec: Math.floor((end - this.startTime) / 1000),
        stats: {
          avgAtt: Math.round(this.attSum / n),
          avgMed: Math.round(this.medSum / n),
          maxAtt: this.maxAttVal,
          maxMed: this.maxMedVal,
          totalBlinks: this.totalBlinks,
          dataPoints: this.dataPointCount
        },
        snapshots: this.snapshots
      };
      const path = SESSIONS_DIR + 'session_' + this.sessionId + '.json';
      const fd = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(fd.fd, JSON.stringify(data));
      fileIo.closeSync(fd.fd);
      console.info('[Session] saved: ' + path);
      this.cleanup();
      this.notify();
    } catch (e) {
      console.error('[Session] save failed: ' + JSON.stringify(e));
    }
  }

  // ========== 内部 ==========

  private p2(n: number): string {
    return n.toString().padStart(2, '0');
  }

  private takeSnapshot(): void {
    if (!this.active) return;
    const d = store.latestData;
    const snap = new SessionSnapshot();
    snap.sec = Math.floor((Date.now() - this.startTime) / 1000);
    snap.sig = d.sig; snap.att = d.att; snap.med = d.med;
    snap.raw = d.raw; snap.d = d.d; snap.theta = d.t;
    snap.aL = d.aL; snap.aH = d.aH; snap.bL = d.bL; snap.bH = d.bH;
    snap.gL = d.gL; snap.gM = d.gM;
    this.snapshots.push(snap);

    this.attSum += d.att;
    this.medSum += d.med;
    if (d.att > this.maxAttVal) this.maxAttVal = d.att;
    if (d.med > this.maxMedVal) this.maxMedVal = d.med;
    this.dataPointCount++;
  }

  private readMeta(filename: string): SessionMeta | null {
    try {
      const path = SESSIONS_DIR + filename;
      const stat = fileIo.statSync(path);
      if (stat.size === 0 || stat.size > 10 * 1024 * 1024) return null;
      const buf = new ArrayBuffer(stat.size);
      const fd = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      const bytesRead = fileIo.readSync(fd.fd, buf);
      fileIo.closeSync(fd.fd);
      if (bytesRead === 0) return null;
      const textDecoder = new util.TextDecoder('utf-8');
      const text = textDecoder.decodeToString(new Uint8Array(buf, 0, bytesRead));
      const obj: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
      const meta = new SessionMeta();
      meta.id = (obj['id'] as string) || '';
      meta.startTime = (obj['startTime'] as number) || 0;
      meta.endTime = (obj['endTime'] as number) || 0;
      meta.durationSec = (obj['durationSec'] as number) || 0;
      const s = obj['stats'] as Record<string, number> | undefined;
      if (s) {
        meta.stats = {
          avgAtt: (s['avgAtt'] as number) || 0,
          avgMed: (s['avgMed'] as number) || 0,
          maxAtt: (s['maxAtt'] as number) || 0,
          maxMed: (s['maxMed'] as number) || 0,
          totalBlinks: (s['totalBlinks'] as number) || 0,
          dataPoints: (s['dataPoints'] as number) || 0
        };
      }
      return meta;
    } catch (e) {
      console.error('[Session] readMeta failed: ' + filename + ' ' + JSON.stringify(e));
      return null;
    }
  }

  private cleanup(): void {
    try {
      const files = fileIo.listFileSync(SESSIONS_DIR);
      const jsonFiles: string[] = [];
      for (let i = 0; i < files.length; i++) {
        if (files[i].endsWith('.json')) jsonFiles.push(files[i]);
      }
      if (jsonFiles.length <= MAX_SESSIONS) return;
      jsonFiles.sort();
      const toDelete = jsonFiles.length - MAX_SESSIONS;
      for (let i = 0; i < toDelete; i++) {
        try { fileIo.unlinkSync(SESSIONS_DIR + jsonFiles[i]); } catch (e) {}
      }
    } catch (e) {}
  }

  private clearTimers(): void {
    if (this.snapshotTimer >= 0) { clearInterval(this.snapshotTimer); this.snapshotTimer = -1; }
    if (this.saveTimer >= 0) { clearInterval(this.saveTimer); this.saveTimer = -1; }
  }
}
