import { preferences } from '@kit.ArkData';
import { common, ConfigurationConstant } from '@kit.AbilityKit';

const STORE_NAME = 'eeg_monitor';

export class StorageService {
  private static instance: StorageService;
  private prefs: preferences.Preferences | null = null;
  private appContext: common.ApplicationContext | null = null;

  static getInstance(): StorageService {
    if (!StorageService.instance) {
      StorageService.instance = new StorageService();
    }
    return StorageService.instance;
  }

  async init(context: common.Context): Promise<void> {
    try {
      this.prefs = await preferences.getPreferences(context, STORE_NAME);
      this.appContext = context.getApplicationContext();
    } catch (e) {
      this.prefs = null;
    }
  }

  setColorMode(isDark: boolean): void {
    if (this.appContext) {
      try {
        this.appContext.setColorMode(
          isDark ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
        );
      } catch (e) {
        // ignore
      }
    }
  }

  getNumber(key: string, def: number = 0): number {
    if (!this.prefs) return def;
    try {
      return this.prefs.getSync(key, def) as number;
    } catch (e) {
      return def;
    }
  }

  setNumber(key: string, value: number): void {
    if (!this.prefs) return;
    try {
      this.prefs.putSync(key, value);
      this.prefs.flush();
    } catch (e) {
      // ignore
    }
  }

  getString(key: string, def: string = ''): string {
    if (!this.prefs) return def;
    try {
      return this.prefs.getSync(key, def) as string;
    } catch (e) {
      return def;
    }
  }

  setString(key: string, value: string): void {
    if (!this.prefs) return;
    try {
      this.prefs.putSync(key, value);
      this.prefs.flush();
    } catch (e) {
      // ignore
    }
  }
}
