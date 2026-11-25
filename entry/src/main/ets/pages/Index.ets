import { EEGDataStore, DeviceInfo } from '../store/EEGDataStore';
import { BleService, BleState, DiscoveredDevice } from '../service/BleService';
import { MockDataService } from '../service/MockDataService';
import { SessionService } from '../service/SessionService';
import { GattServerService, GattServerError, GattLogEvent } from '../service/GattServerService';
import { SideBar } from '../components/SideBar';
import { BrainwavePage } from './Brainwave';
import { GameHubPage } from './GameHubPage';
import { EmotionPage } from './EmotionPage';
import { MotionPage } from './MotionPage';
import { TrainingPage } from './TrainingPage';
import { ProfilePage } from './ProfilePage';
import { StudentDetailPage } from './StudentDetailPage';

const store = EEGDataStore.getInstance();
const bleService = BleService.getInstance();
const mockService = MockDataService.getInstance();
const sessionService = SessionService.getInstance();
const gattServerService = GattServerService.getInstance();
// 多设备并发上限：平板 BLE 同时连接过多会挤占带宽，超出后提示先断开
const MAX_DEVICES = 6;

interface DeviceCardData {
  deviceId: string;
  name: string;
  connected: boolean;
  contactLost: boolean;
  stale: boolean;
  simulated: boolean;
  rssi: number;
  att: number;
  med: number;
  sigText: string;
  sigColor: string;
  band: number[];
  trend: number[];
}

@Entry
@Component
struct Index {
  @State activeNav: number = 0;
  @State sidebarExpanded: boolean = true;
  @State currentMode: string = 'individual';
  @State showStudentDetail: boolean = false;
  @State dashboardDevices: DeviceInfo[] = [];
  @State scanning: boolean = false;
  @State discoveredDevices: DiscoveredDevice[] = [];
  @State connectedDeviceIds: string[] = [];
  @State connectingDeviceIds: string[] = [];
  @State serverRunning: boolean = false;
  @State serverConnCount: number = 0;
  @State serverStarting: boolean = false;
  @State serverStatusText: string = '';
  @State serverLogs: GattLogEvent[] = [];
  @State serverFrameCount: number = 0;
  @State showLogPanel: boolean = false;
  @State demoRunning: boolean = false;
  @State previewAtt: number = 0;
  @State previewMed: number = 0;
  @State previewSig: number = 200;
  @State previewBands: number[] = [0,0,0,0,0,0,0,0];
  @State previewLastTime: string = '--:--:--';
  private demoDeviceId: string = 'demo_showcase';
  private demoUnsub: (() => void) | null = null;
  private miniProgUnsub: (() => void) | null = null;
  @State toastMsg: string = '';
  @State toastShow: boolean = false;
  @State errorDialogVisible: boolean = false;
  @State errorDialogMsg: string = '';
  @State errorDialogDeviceId: string = '';
  @State errorDialogDeviceName: string = '';
  @State deviceCards: DeviceCardData[] = [];
  @State overviewOnline: number = 0;
  @State overviewAvgAtt: number = 0;
  @State overviewAvgMed: number = 0;
  @State overviewWeak: number = 0;
  @State simulatedCount: number = 0;
  @State mockRunning: boolean = false;
  @StorageLink('dark_mode_version') darkModeVersion: number = 0;
  private refreshTimer: number = -1;
  private toastTimer: number = -1;
  private storeUnsub: (() => void) | null = null;
  private lastCardsRefresh: number = 0;

  aboutToAppear(): void {
    bleService.onStateChange((s: BleState) => {
      if (s === BleState.CONNECTED) { this.showToast('设备已连接'); sessionService.startSession(); }
      else if (s === BleState.DISCONNECTED) { this.showToast('设备连接中断'); sessionService.endSession(); }
      else if (s === BleState.ERROR) { this.showToast('连接失败'); }
    });
    gattServerService.onStateChange((r: boolean, c: number) => {
      this.serverRunning = r; this.serverConnCount = c;
      this.serverStarting = false; this.serverStatusText = '';
    });
    gattServerService.onError(() => { this.serverRunning = false; this.serverStarting = false; });
    gattServerService.onLog(() => {
      this.serverLogs = [...gattServerService.getLogs()];
      this.serverFrameCount = gattServerService.getFrameCount();
    });
    this.serverRunning = gattServerService.isRunning();
    this.serverConnCount = gattServerService.getConnectedCount();
    this.serverLogs = gattServerService.getLogs();
    this.serverFrameCount = gattServerService.getFrameCount();
    this.miniProgUnsub = store.subscribeGlobal((_a: string, devId: string) => {
      if (devId === 'mini_program' || _a === 'registered') { this.refreshPreview(); }
    });
    this.storeUnsub = store.subscribe(() => { this.refreshDeviceCards(); });
    this.refreshDeviceCards();
    this.refreshPreview();
    this.refreshTimer = setInterval(() => {
      this.connectedDeviceIds = bleService.getConnectedDeviceIds();
      this.connectingDeviceIds = bleService.getConnectingDeviceIds();
      this.refreshDeviceCards();
    }, 1000);
  }

  aboutToDisappear(): void {
    if (this.storeUnsub) { this.storeUnsub(); this.storeUnsub = null; }
    if (this.miniProgUnsub) { this.miniProgUnsub(); this.miniProgUnsub = null; }
    if (this.demoUnsub) { this.demoUnsub(); this.demoUnsub = null; }
    if (this.refreshTimer >= 0) { clearInterval(this.refreshTimer); this.refreshTimer = -1; }
    if (this.toastTimer >= 0) { clearTimeout(this.toastTimer); this.toastTimer = -1; }
    if (sessionService.isActive()) { sessionService.endSession(); }
  }

  build() {
    Stack() {
      Row() {
        SideBar({ expanded: $sidebarExpanded, mode: $currentMode, activeIndex: this.activeNav,
          onNavigate: (i: number) => { this.activeNav = i; } })
        Column() {
          this.headerBar()
          Stack() {
            if (this.activeNav === 0) { this.deviceManagerView() }
            else if (this.currentMode === 'supervisor' && this.activeNav === 1) { this.multiMonitorView() }
            else if (this.activeNav === 1) { BrainwavePage() }
            else if (this.activeNav === 2) { GameHubPage() }
            else if (this.activeNav === 3) { EmotionPage() }
            else if (this.activeNav === 4) { MotionPage() }
            else if (this.activeNav === 5) { TrainingPage() }
            else if (this.activeNav === 6) { ProfilePage() }
          }.width('100%').layoutWeight(1)
        }.width('100%').layoutWeight(1).height('100%').backgroundColor($r('app.color.background'))
      }.width('100%').height('100%')

      if (this.currentMode === 'supervisor' && this.showStudentDetail) {
        StudentDetailPage({ onBack: () => { this.showStudentDetail = false; } })
      }

      if (this.toastShow) {
        Row() {
          Circle().width(6).height(6).fill('#21C77A').margin({ right: 8 })
          Text(this.toastMsg).fontSize(13).fontColor($r('app.color.text_primary'))
        }.padding({ left: 18, right: 18, top: 10, bottom: 10 })
        .backgroundColor($r('app.color.surface_glass')).borderRadius(20).backdropBlur(12)
        .position({ bottom: 100 }).animation({ duration: 280, curve: Curve.EaseOut })
      }

      if (this.errorDialogVisible) {
        Stack() {
          // 半透明遮罩，点击空白处关闭
          Column() {}.width('100%').height('100%').backgroundColor($r('app.color.overlay_dark'))
            .onClick(() => { this.closeErrorDialog(); })

          Column() {
            Stack() {
              Circle().width(56).height(56).fill($r('app.color.error_light'))
              Text('⚠').fontSize(26).fontColor($r('app.color.error'))
            }
            Text('连接失败').fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).margin({ top: 16 })
            if (this.errorDialogDeviceName.length > 0) {
              Text(this.errorDialogDeviceName).fontSize(11).fontColor($r('app.color.text_muted')).margin({ top: 6 })
            }
            Text(this.errorDialogMsg).fontSize(13).fontColor($r('app.color.text_secondary'))
              .lineHeight(20).textAlign(TextAlign.Center).margin({ top: 10, left: 18, right: 18 })
            Row() {
              Button('稍后再说').height(42).fontSize(14).fontColor($r('app.color.text_secondary'))
                .backgroundColor($r('app.color.button_ghost_bg')).borderRadius(21)
                .border({ width: 1, color: $r('app.color.button_secondary_border') }).layoutWeight(1)
                .onClick(() => { this.closeErrorDialog(); })
              Button('重试连接').height(42).fontSize(14).fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_inverse')).backgroundColor($r('app.color.primary'))
                .borderRadius(21).layoutWeight(1).margin({ left: 12 })
                .onClick(() => { this.retryConnect(); })
            }.width('100%').margin({ top: 22 })
          }
          .width(332).padding({ left: 22, right: 22, top: 26, bottom: 20 })
          .backgroundColor($r('app.color.surface_glass_raised')).borderRadius(24)
          .border({ width: 1, color: $r('app.color.card_border') })
          .shadow({ radius: 32, color: $r('app.color.shadow_lg'), offsetX: 0, offsetY: 12 })
          .alignItems(HorizontalAlign.Center).onClick(() => { })
        }
        .width('100%').height('100%')
        .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut }))
      }
    }.width('100%').height('100%')
  }

  @Builder headerBar() {
    Row() {
      Text(this.getNavTitle(this.activeNav)).fontSize(16).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary')).margin({ left: 16 })
      Blank()
      Row() {
        Circle().width(6).height(6).fill(this.overviewOnline > 0 ? '#21C77A' : $r('app.color.text_muted'))
        Text(this.overviewOnline.toString() + ' 台在线')
          .fontSize(11).fontColor($r('app.color.text_secondary')).margin({ left: 6 })
      }.margin({ right: 16 })
    }.width('100%').height(44).backgroundColor($r('app.color.card_bg'))
    .border({ width: { bottom: 1 }, color: $r('app.color.card_border') })
  }

  // ===================== 设备管理 =====================

  @Builder deviceManagerView() {
    Scroll() {
      Column() {
        this.deviceOverviewCard()
        this.receiveModeCard()
        if (this.serverRunning) { this.receivePreviewCard() }
        if (this.serverRunning && this.showLogPanel) { this.receiveLogsCard() }
        this.bleScanSection()
        this.connectedDevicesSection()
      }.width('100%').padding({ bottom: 24 }).alignItems(HorizontalAlign.Center)
    }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
  }

  @Builder deviceOverviewCard() {
    Row() {
      Stack() { Circle().width(36).height(36).fill($r('app.color.primary_light')); Text('📡').fontSize(17) }
      Column() {
        Text('已连接 ' + this.overviewOnline.toString() + ' / ' + store.getDeviceCount().toString() + ' 台设备')
          .fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Text('真实 ' + (this.overviewOnline - this.simulatedCount).toString() + ' 台 · 模拟 ' + this.simulatedCount.toString() +
          ' 台 · 平均专注 ' + this.overviewAvgAtt.toString() + ' · 冥想 ' + this.overviewAvgMed.toString())
          .fontSize(11).fontColor($r('app.color.text_secondary')).margin({ top: 2 })
      }.alignItems(HorizontalAlign.Start).margin({ left: 12 })
      Blank()
      if (this.overviewWeak > 0) {
        Text('⚠ 信号弱 ' + this.overviewWeak.toString() + ' 台').fontSize(10).fontColor('#F59E0B')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 }).backgroundColor($r('app.color.warning_light'))
          .borderRadius(8).border({ width: 1, color: $r('app.color.border_accent_orange') })
      }
    }.width('92%').padding(14).backgroundColor($r('app.color.card_bg')).borderRadius(14)
    .border({ width: 1, color: $r('app.color.card_border') }).margin({ top: 12, bottom: 8 })
  }

  @Builder receiveModeCard() {
    Row() {
      Stack() {
        Circle().width(32).height(32).fill(this.serverRunning ? 'rgba(33,199,122,0.12)' : 'rgba(148,163,184,0.1)')
        if (this.serverStarting) { LoadingProgress().width(14).height(14).color('#21C77A') }
        else { Text(this.serverRunning ? '📱' : '💤').fontSize(15) }
      }
      Column() {
        Text(this.serverRunning ? '小程序接收：已开启' : '小程序接收：已关闭')
          .fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Text(this.serverStatusText || (this.serverRunning ?
          (this.serverConnCount > 0 ? '已连接 ' + this.serverConnCount.toString() + ' 台手机' : '等待手机连接…') :
          '开启后接收手机小程序脑波数据'))
          .fontSize(10).fontColor(this.serverRunning ? '#21C77A' : $r('app.color.text_muted')).margin({ top: 2 })
      }.alignItems(HorizontalAlign.Start).layoutWeight(1).margin({ left: 10 })
      if (this.serverRunning && !this.demoRunning) {
        Button('🎬 演示').height(28).fontSize(11).fontColor('#F59E0B')
          .backgroundColor('rgba(245,158,11,0.1)').borderRadius(14).border({ width: 1, color: '#F59E0B44' })
          .padding({ left: 10, right: 10 }).margin({ right: 6 }).onClick(() => { this.startDemo(); })
      }
      if (this.demoRunning) {
        Button('停止演示').height(28).fontSize(11).fontColor('#FFFFFF')
          .backgroundColor('#EF4444').borderRadius(14).padding({ left: 10, right: 10 }).margin({ right: 6 })
          .onClick(() => { this.stopDemo(); })
      }
      Button(this.serverRunning ? '关闭' : '开启').height(28).fontSize(11)
        .fontColor(this.serverRunning ? '#FFFFFF' : '#21C77A')
        .backgroundColor(this.serverRunning ? '#EF4444' : $r('app.color.primary_light'))
        .borderRadius(14).padding({ left: 14, right: 14 }).enabled(!this.serverStarting)
        .onClick(() => {
          if (this.serverRunning) { if (this.demoRunning) this.stopDemo(); gattServerService.stop(); }
          else { this.startReceiveMode(); }
        })
    }.width('92%').padding(12).backgroundColor($r('app.color.card_bg')).borderRadius(14)
    .border({ width: 1, color: $r('app.color.card_border') }).margin({ bottom: 8 })
  }

  @Builder receivePreviewCard() {
    Column() {
      Row() {
        Text(this.demoRunning ? '🎬 演示预览' : '📊 实时预览')
          .fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Blank()
        Text(this.previewLastTime).fontSize(10).fontColor($r('app.color.text_muted'))
        Text(' | ').fontSize(10).fontColor($r('app.color.text_muted'))
        Text(this.showLogPanel ? '收起日志 ▲' : '连接日志 ▼').fontSize(10).fontColor('#21C77A')
          .onClick(() => { this.showLogPanel = !this.showLogPanel; })
      }.width('100%').padding({ left: 4, right: 4, bottom: 8 })
      Row() {
        this.pvStat('信号', this.sigText(this.previewSig), this.sigColor(this.previewSig))
        this.pvStat('专注', this.previewAtt.toString(), '#21C77A')
        this.pvStat('放松', this.previewMed.toString(), '#3B82F6')
        this.pvStat('帧数', this.serverFrameCount.toString(), '#F59E0B')
      }.width('100%').justifyContent(FlexAlign.SpaceEvenly).margin({ bottom: 8 })
      Row() {
        ForEach(this.previewBands, (v: number, i: number) => {
          Column() {
            Column().width(8).height(Math.max(2, v * 0.35)).backgroundColor(this.bandColor(i)).borderRadius(4)
            Text(this.bandLabel(i)).fontSize(8).fontColor($r('app.color.text_muted')).margin({ top: 2 })
          }.alignItems(HorizontalAlign.Center)
        }, (_v: number, i: number): string => i.toString())
      }.width('100%').justifyContent(FlexAlign.SpaceEvenly)
    }.width('92%').padding(12).backgroundColor($r('app.color.card_bg')).borderRadius(14)
    .border({ width: 1, color: $r('app.color.card_border') }).margin({ bottom: 8 })
  }

  @Builder receiveLogsCard() {
    Column() {
      Row() {
        Text('连接日志').fontSize(12).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Blank(); Text('清空').fontSize(10).fontColor($r('app.color.text_secondary')).onClick(() => { this.serverLogs = []; })
      }.width('100%').padding({ left: 4, right: 4, bottom: 4 })
      if (this.serverLogs.length === 0) {
        Text('暂无日志').fontSize(10).fontColor($r('app.color.text_muted')).width('100%').textAlign(TextAlign.Center).padding({ top: 8, bottom: 8 })
      } else {
        ForEach([...this.serverLogs].reverse().slice(0, 6), (evt: GattLogEvent) => {
          Row() {
            Text(this.logIcon(evt.type)).fontSize(11)
            Text(this.formatTs(evt.timestamp)).fontSize(9).fontColor($r('app.color.text_muted')).margin({ left: 4, right: 8 })
            Text(evt.message).fontSize(10).fontColor(this.logColor(evt.type)).maxLines(1)
          }.width('100%').padding({ top: 2, bottom: 2 })
        }, (_evt: GattLogEvent, i: number): string => i.toString())
      }
    }.width('92%').padding(12).backgroundColor($r('app.color.card_bg')).borderRadius(14)
    .border({ width: 1, color: $r('app.color.card_border') }).margin({ bottom: 8 })
  }

  // ===================== 蓝牙 BLE 扫描 =====================

  @Builder bleScanSection() {
    Column() {
      Row() {
        Text('📶 蓝牙 BLE').fontSize(14).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
        Text(' ' + this.connectedDeviceIds.length.toString() + '/' + MAX_DEVICES.toString() + ' 台')
          .fontSize(10).fontColor($r('app.color.text_muted')).margin({ left: 4 })
        Blank()
        Button(this.scanning ? '停止' : '扫描').height(28).fontSize(11).fontColor('#FFFFFF')
          .backgroundColor(this.scanning ? '#EF4444' : '#21C77A').borderRadius(14).padding({ left: 14, right: 14 }).fontWeight(FontWeight.Bold)
          .onClick(() => { if (this.scanning) { bleService.stopScan(); this.scanning = false; } else { this.startBleScan(); } })
        Button(this.mockRunning ? '停止模拟' : '模拟').height(28).fontSize(11)
          .fontColor(this.mockRunning ? '#FFFFFF' : '#21C77A')
          .backgroundColor(this.mockRunning ? '#EF4444' : $r('app.color.primary_light'))
          .borderRadius(14).border({ width: 1, color: this.mockRunning ? '#EF4444' : '#21C77A' })
          .padding({ left: 10, right: 10 }).margin({ left: 6 })
          .onClick(() => {
            if (this.mockRunning) {
              mockService.stop();
              this.showToast('已停止模拟设备');
            } else {
              mockService.stop(); mockService.startMulti(2, '脑环');
              this.showToast('已添加 2 台模拟设备（已标注“模拟”）');
            }
          })
      }.width('100%').padding({ left: 4, right: 4, bottom: 6 })
      if (this.discoveredDevices.length === 0 && !this.scanning) {
        Text('点击扫描搜索 BLE 蓝牙设备').fontSize(10).fontColor($r('app.color.text_muted')).width('100%').textAlign(TextAlign.Center).padding({ top: 6, bottom: 6 })
      } else if (this.scanning && this.discoveredDevices.length === 0) {
        Row() { LoadingProgress().width(12).height(12).color('#21C77A'); Text(' 搜索中…').fontSize(11).fontColor($r('app.color.text_secondary')) }.width('100%').justifyContent(FlexAlign.Center).padding({ top: 8, bottom: 8 })
      } else {
        ForEach(this.discoveredDevices, (dev: DiscoveredDevice) => {
          Row() {
            Column() {
              Text(dev.deviceName || '(未命名)').fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
              Text('RSSI: ' + dev.rssi.toString() + ' dBm').fontSize(10).fontColor($r('app.color.text_secondary')).margin({ top: 2 })
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            if (this.connectedDeviceIds.indexOf(dev.deviceId) >= 0) {
              Text('已连接').fontSize(10).fontColor('#21C77A').padding({ left: 10, right: 10, top: 6, bottom: 6 }).border({ width: 1, color: '#21C77A', radius: 10 })
            } else if (this.connectingDeviceIds.indexOf(dev.deviceId) >= 0) {
              Row() {
                LoadingProgress().width(11).height(11).color('#21C77A')
                Text(' 连接中…').fontSize(10).fontColor('#21C77A')
              }.padding({ left: 10, right: 10, top: 6, bottom: 6 }).border({ width: 1, color: '#21C77A', radius: 10 })
            } else {
              Button('连接').fontSize(10).height(27).backgroundColor('#21C77A').borderRadius(12).fontColor('#FFFFFF')
                .onClick(() => { this.tryConnect(dev.deviceId, dev.deviceName); })
            }
          }.width('100%').padding(10).backgroundColor($r('app.color.background')).borderRadius(10).margin({ top: 3, bottom: 3 })
        }, (dev: DiscoveredDevice): string => dev.deviceId)
      }
    }.width('92%').padding(12).backgroundColor($r('app.color.card_bg')).borderRadius(14)
    .border({ width: 1, color: $r('app.color.card_border') }).margin({ bottom: 8 })
  }

  // ===================== 已连接设备（实时卡片） =====================

  @Builder connectedDevicesSection() {
    Column() {
      Row() {
        Text('🔗 已连接设备 (' + this.overviewOnline.toString() + ')').fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        if (this.deviceCards.length > 0) {
          Text('断开全部').fontSize(10).fontColor('#EF4444').onClick(() => {
            bleService.disconnectAll();
          })
        }
      }.width('100%').padding({ left: 4, right: 4, bottom: 8 })
      if (this.deviceCards.length === 0) {
        Text('暂无设备，请在上方扫描并连接脑环').fontSize(10).fontColor($r('app.color.text_muted'))
          .width('100%').textAlign(TextAlign.Center).padding({ top: 6, bottom: 6 })
      } else {
        ForEach(this.deviceCards, (card: DeviceCardData) => {
          Row() {
            Circle().width(8).height(8).fill(card.connected ? (card.stale ? '#94A3B8' : (card.contactLost ? '#F59E0B' : '#21C77A')) : '#94A3B8')
            Column() {
              Row() {
                Text(card.name).fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
                if (card.simulated) {
                  Text('模拟').fontSize(8).fontColor('#F59E0B').padding({ left: 5, right: 5, top: 1, bottom: 1 })
                    .backgroundColor('rgba(245,158,11,0.12)').borderRadius(6).margin({ left: 6 })
                }
              }
              Text(this.deviceCardStatus(card)).fontSize(10).fontColor(card.connected ? (card.stale ? $r('app.color.text_muted') : (card.contactLost ? '#F59E0B' : '#21C77A')) : $r('app.color.text_muted')).margin({ top: 2 })
              Text('RSSI ' + card.rssi.toString() + ' dBm').fontSize(9).fontColor(card.rssi < -80 ? '#EF4444' : $r('app.color.text_muted')).margin({ top: 2 })
            }.alignItems(HorizontalAlign.Start).margin({ left: 10 }).layoutWeight(1)
            Column() {
              Text('专注 ' + (card.contactLost || card.stale ? '--' : card.att.toString())).fontSize(12).fontWeight(FontWeight.Bold)
                .fontColor(card.contactLost || card.stale ? $r('app.color.text_muted') : '#21C77A').fontFamily('monospace')
              Text('冥想 ' + (card.contactLost || card.stale ? '--' : card.med.toString())).fontSize(11)
                .fontColor(card.contactLost || card.stale ? $r('app.color.text_muted') : '#3B82F6').fontFamily('monospace').margin({ top: 2 })
            }.alignItems(HorizontalAlign.End).margin({ right: 10 })
            if (card.connected) {
              Button('断开').fontSize(10).height(26).backgroundColor('rgba(239,68,68,0.1)').borderRadius(12).fontColor('#EF4444')
                .onClick(() => { this.disconnectAnyDevice(card.deviceId); })
            }
          }.width('100%').padding(10).backgroundColor($r('app.color.background')).borderRadius(10).margin({ top: 3, bottom: 3 })
          .onClick(() => {
            if (card.connected) { this.openDeviceDetail(card.deviceId); }
          })
        }, (card: DeviceCardData): string => card.deviceId)
      }
    }.width('92%').padding(12).backgroundColor($r('app.color.card_bg')).borderRadius(14)
    .border({ width: 1, color: $r('app.color.card_border') }).margin({ bottom: 8 })
  }

  private deviceCardStatus(card: DeviceCardData): string {
    if (!card.connected) return '离线';
    if (card.simulated) return '在线 · 模拟数据（非真实采集）';
    if (card.stale) return '数据中断 · 固件未发送数据';
    if (card.contactLost) return '信号丢失 · 请检查电极';
    return '在线 · ' + card.sigText;
  }

  private disconnectAnyDevice(deviceId: string): void {
    bleService.disconnectDevice(deviceId);
  }

  // 点击已连接设备：切换到该设备，并跳转到对应数据页
  private openDeviceDetail(deviceId: string): void {
    store.setActiveDevice(deviceId);
    if (this.currentMode === 'supervisor') {
      this.showStudentDetail = true;
    } else {
      this.showStudentDetail = false;
      this.activeNav = 1; // 脑波数据页（BrainwavePage），展示活跃设备数据
    }
  }

  // ===================== 多设备总览 =====================

  @Builder multiMonitorView() {
    Scroll() {
      Column() {
        Row() {
          Circle().width(5).height(5).fill('#21C77A').shadow({ radius: 3, color: '#3021C77A', offsetX: 0, offsetY: 0 })
          Text('多设备总览').fontSize(14).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).margin({ left: 6 })
          Blank()
          Text(this.overviewOnline.toString() + ' 台在线（真实 ' + (this.overviewOnline - this.simulatedCount).toString() +
            ' · 模拟 ' + this.simulatedCount.toString() + '）').fontSize(11).fontColor($r('app.color.text_secondary'))
        }.width('92%').padding({ top: 14, bottom: 10 })

        // 顶部统计条
        Row() {
          this.overviewStat('在线设备', this.overviewOnline.toString(), '#21C77A')
          this.overviewStat('平均专注', this.overviewAvgAtt.toString(), '#3B82F6')
          this.overviewStat('平均冥想', this.overviewAvgMed.toString(), '#8B5CF6')
          this.overviewStat('信号异常', this.overviewWeak.toString(), '#F59E0B')
        }.width('92%').padding({ top: 12, bottom: 12 }).backgroundColor($r('app.color.card_bg'))
        .borderRadius(16).border({ width: 1, color: $r('app.color.card_border') }).margin({ bottom: 10 })

        if (this.deviceCards.length === 0) {
          Column() {
            Text('📡').fontSize(34).margin({ top: 40 })
            Text('暂无设备').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).margin({ top: 12 })
            Text('请到「设备管理」页扫描并连接脑环设备').fontSize(11).fontColor($r('app.color.text_muted')).margin({ top: 6 })
          }.width('92%').alignItems(HorizontalAlign.Center)
        } else {
          Grid() {
            ForEach(this.deviceCards, (card: DeviceCardData) => {
              GridItem() {
                Column() {
                  Row() {
                    Circle().width(8).height(8).fill(card.connected ? (card.stale ? '#94A3B8' : (card.contactLost ? '#F59E0B' : '#21C77A')) : '#94A3B8')
                    Text(card.name).fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ left: 6 }).layoutWeight(1)
                    if (card.simulated) {
                      Text('模拟').fontSize(8).fontColor('#F59E0B').padding({ left: 5, right: 5, top: 1, bottom: 1 })
                        .backgroundColor('rgba(245,158,11,0.12)').borderRadius(6).margin({ left: 4 })
                    }
                    Text(card.connected ? (card.stale ? '数据中断' : (card.contactLost ? '信号丢失' : '在线')) : '离线')
                      .fontSize(9).fontColor(card.connected ? (card.stale ? $r('app.color.text_muted') : (card.contactLost ? '#F59E0B' : '#21C77A')) : $r('app.color.text_muted'))
                  }.width('100%')
                  Row() {
                    Column() {
                      Text(card.contactLost || card.stale ? '--' : card.att.toString()).fontSize(24).fontWeight(FontWeight.Bold)
                        .fontColor(card.contactLost || card.stale ? $r('app.color.text_muted') : '#21C77A').fontFamily('monospace')
                      Text('专注').fontSize(9).fontColor($r('app.color.text_muted')).margin({ top: 2 })
                    }.alignItems(HorizontalAlign.Center).layoutWeight(1)
                    Column() {
                      Text(card.contactLost || card.stale ? '--' : card.med.toString()).fontSize(24).fontWeight(FontWeight.Bold)
                        .fontColor(card.contactLost || card.stale ? $r('app.color.text_muted') : '#3B82F6').fontFamily('monospace')
                      Text('冥想').fontSize(9).fontColor($r('app.color.text_muted')).margin({ top: 2 })
                    }.alignItems(HorizontalAlign.Center).layoutWeight(1)
                  }.width('100%').margin({ top: 12 })
                  Text(card.sigText).fontSize(9).fontColor(card.sigColor).margin({ top: 6 })
                  // 迷你八频段条
                  Row() {
                    ForEach(card.band, (v: number, i: number) => {
                      Column().width(7).height(Math.max(2, Math.min(24, v * 0.045))).backgroundColor(this.bandColor(i)).borderRadius(2)
                    }, (_v: number, i: number): string => i.toString())
                  }.width('100%').justifyContent(FlexAlign.SpaceBetween).margin({ top: 8 })
                  // 专注度迷你趋势（最近 24 帧 ≈ 25 秒）
                  Column() {
                    Row() {
                      Text('专注趋势').fontSize(8).fontColor($r('app.color.text_muted'))
                      Blank()
                    }.width('100%')
                    Row() {
                      ForEach(card.trend, (v: number) => {
                        Column().width(3).height(Math.max(2, Math.min(24, v * 0.24)))
                          .backgroundColor(card.contactLost || card.stale ? '#CBD5E1' : '#21C77A')
                          .borderRadius(1).opacity(0.85)
                      }, (_v: number, i: number): string => i.toString())
                    }.width('100%').height(26).justifyContent(FlexAlign.SpaceBetween).alignItems(VerticalAlign.Bottom).margin({ top: 3 })
                  }.width('100%').margin({ top: 8 })
                  if (card.connected) {
                    Text('查看详情 ›').fontSize(10).fontColor('#21C77A').margin({ top: 8 })
                      .onClick(() => { this.openDeviceDetail(card.deviceId); })
                  }
                }.width('100%').padding(12).alignItems(HorizontalAlign.Start)
                .backgroundColor($r('app.color.card_bg')).borderRadius(16)
                .border({ width: 1, color: $r('app.color.card_border') })
              }
            }, (card: DeviceCardData): string => card.deviceId)
          }.columnsTemplate('1fr 1fr').columnsGap(8).rowsGap(8).width('92%').height(Math.ceil(this.deviceCards.length / 2) * 216)
        }
      }.width('100%').alignItems(HorizontalAlign.Center).padding({ bottom: 24 })
    }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
  }

  @Builder overviewStat(label: string, value: string, color: string) {
    Column() {
      Text(value).fontSize(20).fontWeight(FontWeight.Bold).fontColor(color).fontFamily('monospace')
      Text(label).fontSize(9).fontColor($r('app.color.text_muted')).margin({ top: 2 })
    }.alignItems(HorizontalAlign.Center).layoutWeight(1)
  }

  // ===================== 方法 =====================

  private getNavTitle(i: number): string {
    if (this.currentMode === 'supervisor') { if (i === 0) return '设备管理'; if (i === 1) return '多设备监测'; return '未知'; }
    switch (i) {
      case 0: return '设备管理'; case 1: return '脑波数据'; case 2: return '脑控游戏';
      case 3: return '情绪识别'; case 4: return '运动想象'; case 5: return '专注训练';
      case 6: return '个人中心'; default: return '未知';
    }
  }

  private startBleScan(): void {
    this.scanning = true; this.discoveredDevices = [];
    bleService.setOnDeviceDiscovered((d: DiscoveredDevice[]) => { this.discoveredDevices = [...d]; });
    bleService.setOnDeviceConnected(() => {
      this.connectedDeviceIds = bleService.getConnectedDeviceIds();
      this.connectingDeviceIds = bleService.getConnectingDeviceIds();
    });
    bleService.setOnDeviceDisconnected(() => {
      this.connectedDeviceIds = bleService.getConnectedDeviceIds();
      this.connectingDeviceIds = bleService.getConnectingDeviceIds();
    });
    bleService.setOnDeviceError((deviceId: string, name: string, msg: string) => {
      this.showConnectError(deviceId, name, msg);
    });
    bleService.setOnDataReplay((_deviceId: string, name: string) => {
      this.showToast('检测到 ' + name + ' 重复发送相同数据帧，可能为固件异常，请重启设备');
    });
    bleService.startMultiScan();
  }

  private tryConnect(deviceId: string, deviceName: string): void {
    const active = bleService.getConnectedDeviceIds().length + bleService.getConnectingDeviceIds().length;
    if (active >= MAX_DEVICES) {
      this.showToast('已达连接上限（' + MAX_DEVICES.toString() + ' 台），请先断开一台设备');
      return;
    }
    bleService.stopScan();
    this.scanning = false;
    bleService.connectDevice(deviceId, deviceName);
  }

  private refreshDeviceCards(): void {
    // 限频：避免模拟数据（50Hz）等高频更新导致整页重绘卡顿，5Hz 足够实时
    const now = Date.now();
    if (now - this.lastCardsRefresh < 200) return;
    this.lastCardsRefresh = now;
    const cards: DeviceCardData[] = [];
    store.getAllDeviceInfos().forEach((info: DeviceInfo) => {
      const d = store.getLatestData(info.deviceId);
      // 迷你趋势：最近 24 个专注度采样点（约 25 秒）
      const trendPts = store.getTrendHistory(info.deviceId);
      const trend: number[] = [];
      const startIdx = Math.max(0, trendPts.length - 24);
      for (let i = startIdx; i < trendPts.length; i++) {
        trend.push(trendPts[i].att);
      }
      const found = this.discoveredDevices.find((dd: DiscoveredDevice) => dd.deviceId === info.deviceId);
      cards.push({
        deviceId: info.deviceId,
        name: info.deviceName,
        connected: info.connected,
        contactLost: store.getContactLost(info.deviceId),
        stale: info.connected && store.isDataStale(info.deviceId, 4000),
        simulated: this.isSimulatedDevice(info.deviceId),
        rssi: found ? found.rssi : -100,
        att: d?.att ?? 0,
        med: d?.med ?? 0,
        sigText: store.getSignalTextFor(info.deviceId),
        sigColor: store.getSignalColorFor(info.deviceId),
        band: store.getBandPower(info.deviceId),
        trend: trend
      });
    });
    this.deviceCards = cards;
    const online = cards.filter((c: DeviceCardData) => c.connected);
    const valid = online.filter((c: DeviceCardData) => !c.contactLost);
    this.overviewOnline = online.length;
    this.overviewAvgAtt = valid.length > 0 ?
      Math.round(valid.reduce((s: number, c: DeviceCardData) => s + c.att, 0) / valid.length) : 0;
    this.overviewAvgMed = valid.length > 0 ?
      Math.round(valid.reduce((s: number, c: DeviceCardData) => s + c.med, 0) / valid.length) : 0;
    this.overviewWeak = online.filter((c: DeviceCardData) =>
      c.contactLost || c.sigText === '一般' || c.sigText === '较差' || c.sigText === '等待接触').length;
    this.simulatedCount = online.filter((c: DeviceCardData) => c.simulated).length;
    this.mockRunning = mockService.isRunning();
  }

  // 模拟/演示数据源标识：避免被误认为真实脑环数据
  private isSimulatedDevice(deviceId: string): boolean {
    return deviceId.startsWith('mock_') || deviceId === 'demo_showcase' || deviceId === 'mini_program';
  }

  private showConnectError(deviceId: string, deviceName: string, msg: string): void {
    this.errorDialogDeviceId = deviceId;
    this.errorDialogDeviceName = deviceName;
    this.errorDialogMsg = this.friendlyConnectError(msg);
    this.errorDialogVisible = true;
  }

  private closeErrorDialog(): void {
    this.errorDialogVisible = false;
    this.errorDialogDeviceId = '';
    this.errorDialogDeviceName = '';
  }

  private retryConnect(): void {
    const deviceId = this.errorDialogDeviceId;
    const deviceName = this.errorDialogDeviceName;
    this.closeErrorDialog();
    if (deviceId.length > 0) {
      bleService.stopScan();
      this.scanning = false;
      bleService.connectDevice(deviceId, deviceName || deviceId);
    }
  }

  private friendlyConnectError(msg: string): string {
    if (msg.includes('连接超时')) return '连接超时了，请确认设备已开机，并在平板附近';
    if (msg.includes('连接被拒绝')) return '设备拒绝了连接，请确认设备已开机，且没有被其他设备占用';
    if (msg.includes('没有可接收数据的特征')) return '已连接，但没有找到数据通道，请确认固件使用通知方式发送数据';
    if (msg.includes('开启数据通知失败')) return '数据通道开启失败，请重试，或重新开关一下设备电源';
    if (msg.includes('格式无法解析')) return '已连接，但收到的数据格式不匹配';
    if (msg.includes('连接后初始化失败')) return '连接不稳定，请重试';
    if (msg.includes('发起连接失败')) return '发起连接失败，请重试';
    return '连接失败，请重试';
  }

  private startReceiveMode(): void { this.serverStarting = true; this.serverStatusText = '正在启动…'; gattServerService.start(); }

  private startDemo(): void {
    if (this.demoRunning) return;
    store.registerDevice(this.demoDeviceId, '🎬 演示脑波'); store.setActiveDevice(this.demoDeviceId);
    mockService.stop(); mockService.startAs(this.demoDeviceId, '🎬 演示脑波');
    this.demoRunning = true;
    this.demoUnsub = store.subscribeGlobal((_a: string, devId: string) => { if (devId === this.demoDeviceId) { this.refreshPreview(); } });
    this.refreshPreview(); this.showToast('演示模式已开启');
  }

  private stopDemo(): void {
    if (!this.demoRunning) return; mockService.stop();
    if (this.demoUnsub) { this.demoUnsub(); this.demoUnsub = null; }
    this.demoRunning = false; this.refreshPreview();
  }

  private refreshPreview(): void {
    const devId = this.demoRunning ? this.demoDeviceId : 'mini_program';
    const d = store.getLatestData(devId); if (!d) return;
    this.previewAtt = d.att; this.previewMed = d.med; this.previewSig = d.sig;
    this.previewBands = [
      Math.min(100, Math.round(d.d/700*100)), Math.min(100, Math.round(d.t/700*100)),
      Math.min(100, Math.round(d.aL/700*100)), Math.min(100, Math.round(d.aH/700*100)),
      Math.min(100, Math.round(d.bL/700*100)), Math.min(100, Math.round(d.bH/700*100)),
      Math.min(100, Math.round(d.gL/700*100)), Math.min(100, Math.round(d.gM/700*100))
    ];
    const t = new Date();
    this.previewLastTime = t.getHours().toString().padStart(2,'0')+':'+t.getMinutes().toString().padStart(2,'0')+':'+t.getSeconds().toString().padStart(2,'0');
  }

  private showToast(m: string): void { this.toastMsg = m; this.toastShow = true; if (this.toastTimer>=0) clearTimeout(this.toastTimer); this.toastTimer = setTimeout(() => { this.toastShow = false; this.toastTimer = -1; }, 2200); }

  private sigText(s: number): string { if (s===0) return '优秀'; if (s<50) return '良好'; if (s<100) return '一般'; if (s<200) return '较差'; return '--'; }
  private sigColor(s: number): string { if (s===0) return '#22C55E'; if (s<50) return '#6CBE8A'; if (s<100) return '#F59E0B'; if (s<200) return '#EF4444'; return '#94A3B8'; }
  private bandColor(i: number): string { switch (i) { case 0: return '#64748B'; case 1: return '#8E6FAD'; case 2: return '#4A90D9'; case 3: return '#3B82F6'; case 4: return '#F59E0B'; case 5: return '#F97316'; case 6: return '#C544F0'; case 7: return '#EC4899'; default: return '#94A3B8'; } }
  private bandLabel(i: number): string { switch (i) { case 0: return 'δ'; case 1: return 'θ'; case 2: return 'αL'; case 3: return 'αH'; case 4: return 'βL'; case 5: return 'βH'; case 6: return 'γL'; case 7: return 'γM'; default: return '--'; } }
  private logIcon(t: string): string { if (t==='connected') return '🔗'; if (t==='disconnected') return '🔌'; if (t==='data') return '📡'; if (t==='error') return '⚠'; return 'ℹ'; }
  private logColor(t: string): string { if (t==='connected') return '#22C55E'; if (t==='disconnected') return '#F59E0B'; if (t==='data') return '#3B82F6'; if (t==='error') return '#EF4444'; return '#64748B'; }
  private formatTs(ts: number): string { const d = new Date(ts); return d.getHours().toString().padStart(2,'0')+':'+d.getMinutes().toString().padStart(2,'0')+':'+d.getSeconds().toString().padStart(2,'0'); }

  @Builder pvStat(label: string, val: string, color: string) {
    Column() { Text(val).fontSize(16).fontWeight(FontWeight.Bold).fontColor(color).fontFamily('monospace'); Text(label).fontSize(9).fontColor($r('app.color.text_muted')).margin({ top: 2 }) }.alignItems(HorizontalAlign.Center)
  }
}
