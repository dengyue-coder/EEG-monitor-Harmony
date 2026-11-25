import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { SessionSnapshot, SessionData } from './SessionService';

const SESSIONS_DIR = '/data/storage/el2/base/haps/entry/files/sessions/';
const EXPORTS_DIR = '/data/storage/el2/base/haps/entry/files/exports/';

const CSV_HEADER = 'timestamp,sec,sig,att,med,raw,delta,theta,alpha_low,alpha_high,beta_low,beta_high,gamma_low,gamma_mid';

export class ExportService {
  private static instance: ExportService;

  static getInstance(): ExportService {
    if (!ExportService.instance) {
      ExportService.instance = new ExportService();
    }
    return ExportService.instance;
  }

  private constructor() {}

  exportCSV(sessionId: string): string {
    try {
      const srcPath = SESSIONS_DIR + 'session_' + sessionId + '.json';
      const textDecoder = new util.TextDecoder('utf-8');
      const stat = fileIo.statSync(srcPath);
      const buf = new ArrayBuffer(stat.size);
      const file = fileIo.openSync(srcPath, fileIo.OpenMode.READ_ONLY);
      fileIo.readSync(file.fd, buf);
      fileIo.closeSync(file.fd);
      const text = textDecoder.decodeToString(new Uint8Array(buf));
      const session: SessionData = JSON.parse(text) as SessionData;

      let csv = CSV_HEADER + '\n';
      const snapshots: SessionSnapshot[] = session.snapshots;
      if (snapshots) {
        for (let i = 0; i < snapshots.length; i++) {
          const s: SessionSnapshot = snapshots[i];
          const timestamp = new Date(session.startTime + s.sec * 1000).toISOString();
          const row = [
            timestamp, s.sec, s.sig, s.att, s.med, s.raw,
            s.d, s.theta, s.aL, s.aH, s.bL, s.bH, s.gL, s.gM
          ].join(',');
          csv += row + '\n';
        }
      }

      fileIo.mkdirSync(EXPORTS_DIR, true);
      const outPath = EXPORTS_DIR + 'session_' + sessionId + '.csv';
      const outFile = fileIo.openSync(outPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(outFile.fd, csv);
      fileIo.closeSync(outFile.fd);
      console.info('[Export] CSV saved: ' + outPath);
      return outPath;
    } catch (e) {
      console.error('[Export] CSV failed: ' + JSON.stringify(e));
      return '';
    }
  }

  exportJSON(sessionId: string): string {
    try {
      const srcPath = SESSIONS_DIR + 'session_' + sessionId + '.json';
      const stat = fileIo.statSync(srcPath);
      const buf = new ArrayBuffer(stat.size);
      const file = fileIo.openSync(srcPath, fileIo.OpenMode.READ_ONLY);
      fileIo.readSync(file.fd, buf);
      fileIo.closeSync(file.fd);

      fileIo.mkdirSync(EXPORTS_DIR, true);
      const outPath = EXPORTS_DIR + 'session_' + sessionId + '.json';
      const outFile = fileIo.openSync(outPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(outFile.fd, new util.TextDecoder('utf-8').decodeToString(new Uint8Array(buf)));
      fileIo.closeSync(outFile.fd);
      console.info('[Export] JSON saved: ' + outPath);
      return outPath;
    } catch (e) {
      console.error('[Export] JSON failed: ' + JSON.stringify(e));
      return '';
    }
  }
}
