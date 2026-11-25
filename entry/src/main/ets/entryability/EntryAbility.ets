import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { StorageService } from '../service/StorageService';
import { SessionService } from '../service/SessionService';
import { RoleStore } from '../store/RoleStore';
import { ensureBluetoothPermission } from '../utils/PermissionUtils';

const sessionService = SessionService.getInstance();

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Promise<void> {
    await StorageService.getInstance().init(this.context);

    const storageService = StorageService.getInstance();
    const darkModeOn = storageService.getNumber('dark_mode_on', 0) === 1;
    AppStorage.setOrCreate('dark_mode_on', darkModeOn ? 1 : 0);
    AppStorage.setOrCreate('dark_mode_version', 0);
    if (darkModeOn) {
      storageService.setColorMode(true);
    }
    RoleStore.getInstance().init();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    // 状态栏/导航栏透明，由页面 background + expandSafeArea 控制颜色
    windowStage.getMainWindow().then((win) => {
      win.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        statusBarContentColor: '#FFFFFF',
        navigationBarColor: '#00000000',
        navigationBarContentColor: '#2C3E50'
      });
    });

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });

    // 启动时动态申请蓝牙权限（user_grant，不申请则扫描 API 直接抛 201）
    try {
      ensureBluetoothPermission(this.context).then((ok: boolean) => {
        hilog.info(DOMAIN, 'testTag', '%{public}s', ok ? '蓝牙权限已授予' : '蓝牙权限未授予');
      }).catch((e: Error) => {
        hilog.error(DOMAIN, 'testTag', '蓝牙权限申请异常: %{public}s', JSON.stringify(e));
      });
    } catch (e) { }
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
    if (sessionService.isActive()) {
      sessionService.doSave();
    }
  }
}
