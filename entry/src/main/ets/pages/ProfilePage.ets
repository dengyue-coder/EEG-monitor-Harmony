import { EEGDataStore } from '../store/EEGDataStore';
import { StorageService } from '../service/StorageService';

const store = EEGDataStore.getInstance();
const storageService = StorageService.getInstance();
const DARK_MODE_KEY = 'dark_mode_on';

@Component
export struct ProfilePage {
  @State connected: boolean = false;
  @State darkMode: boolean = false;
  @StorageProp('dark_mode_on') darkModeOn: number = 0;
  private unsub: (() => void) | null = null;

  aboutToAppear(): void { this.darkMode = storageService.getNumber(DARK_MODE_KEY, 0) === 1; this.unsub = store.subscribe(() => { this.connected = store.connected; }); }
  aboutToDisappear(): void { if (this.unsub) { this.unsub(); this.unsub = null; } }

  private getLevel(): number { const s = storageService.getNumber('schulte_best', 999); const e = storageService.getNumber('endurance_best', 0); if (s <= 40 || e >= 300) return 5; if (s <= 60 || e >= 180) return 4; if (s <= 100 || e >= 90) return 3; if (s < 999) return 2; return 1; }
  private getSchulte(): number { return storageService.getNumber('schulte_best', 999); }
  private getEndurance(): number { return storageService.getNumber('endurance_best', 0); }
  private getFlight(): number { return storageService.getNumber('flight_best', 0); }
  private fmtS(): string { const v = this.getSchulte(); return v < 999 ? Math.round(v).toString() + 's' : '--'; }
  private fmtE(): string { const v = this.getEndurance(); return v > 0 ? Math.round(v).toString() + 's' : '--'; }
  private fmtF(): string { const v = this.getFlight(); return v > 0 ? v.toString() : '--'; }
  private getTotalTrain(): number { return (this.getSchulte() < 999 ? 1 : 0) + (this.getEndurance() > 0 ? 1 : 0) + (this.getFlight() > 0 ? 1 : 0); }
  private getTotalTime(): string { const e = this.getEndurance(); if (e >= 300) return '5.2h'; if (e >= 180) return '3.1h'; if (e >= 90) return '1.6h'; if (e > 0) return Math.round(e / 60 * 10) / 10 + 'h'; return '0h'; }

  build() {
    Scroll() { Column() {
      this.identityCockpit()
      this.brainDataSection()
      this.neuralGrowthSection()
      this.systemPrefSection()
      this.deviceInfoSection()
    }.width('100%').alignItems(HorizontalAlign.Center).padding({ top: 12, bottom: 32 }) }
    .width('100%').height('100%').scrollBar(BarState.Off)
    .linearGradient({ direction: GradientDirection.Bottom, colors: [[$r('app.color.page_bg_gradient_top'), 0.0], [$r('app.color.page_bg_gradient_mid'), 0.5], [$r('app.color.page_bg_gradient_bottom'), 1.0]] })
  }

  // ===== 1. 脑机身份舱 =====
  @Builder identityCockpit() {
    Stack() {
      Image($r('app.media.bg_profile')).width('100%').height(220).objectFit(ImageFit.Cover).borderRadius(24)
      Column().width('100%').height(220).backgroundColor('rgba(6,14,31,0.55)').borderRadius(24)

      // 粒子光效
      Circle({ width: 3, height: 3 }).fill('rgba(69,230,165,0.4)').position({ x: '20%', y: '30%' })
      Circle({ width: 2, height: 2 }).fill('rgba(77,163,255,0.3)').position({ x: '75%', y: '25%' })
      Circle({ width: 2.5, height: 2.5 }).fill('rgba(139,124,255,0.35)').position({ x: '60%', y: '65%' })

      // 3D脑部头像
      Stack() {
        Circle({ width: 100, height: 100 }).fill('rgba(69,230,165,0.05)').shadow({ radius: 30, color: 'rgba(69,230,165,0.12)', offsetX: 0, offsetY: 0 })
        Circle({ width: 80, height: 80 }).fill('rgba(69,230,165,0.10)').stroke('rgba(69,230,165,0.25)').strokeWidth(1.5)
        Circle({ width: 56, height: 56 }).fill('rgba(69,230,165,0.18)')
        Text('脑').fontSize(22).fontColor('#45E6A5').fontWeight(FontWeight.Bold)
      }.position({ x: '50%', y: '42%' }).translate({ x: '-50vp', y: '-50vp' })

      // 右上角等级徽章
      Column() {
        Text('Lv').fontSize(8).fontColor('#FFB84D')
        Text(this.getLevel().toString()).fontSize(22).fontWeight(FontWeight.Bold).fontColor('#FFB84D').fontFamily('monospace')
      }.alignItems(HorizontalAlign.Center).padding({ left: 10, right: 10, top: 6, bottom: 4 })
        .backgroundColor('rgba(255,184,77,0.08)').border({ width: 1, color: 'rgba(255,184,77,0.15)', radius: 12 })
        .position({ x: '82%', y: '20%' })

      // 底部信息区
      Column() {
        Text('启航者').fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
        Row() {
          Circle({ width: 5, height: 5 }).fill(this.connected ? '#45E6A5' : '#FF6675')
          Text(this.connected ? ' Brain Interface Online' : ' Offline').fontSize(10).fontColor($r('app.color.text_secondary')).margin({ left: 2 })
        }.margin({ top: 3 })
        // 神经连接度进度条
        Row() {
          Text('神经连接度').fontSize(9).fontColor($r('app.color.text_tertiary')).width(56)
          Row() { Row().width('97%').height(3).backgroundColor('#45E6A5').borderRadius(1.5) }
            .width(80).height(3).backgroundColor('rgba(255,255,255,0.08)').borderRadius(1.5)
          Text('97%').fontSize(10).fontWeight(FontWeight.Bold).fontColor('#45E6A5').fontFamily('monospace').margin({ left: 6 })
        }.margin({ top: 6 })
      }.alignItems(HorizontalAlign.Center).position({ x: '50%', y: '82%' }).translate({ x: '-50%' })
    }.width('92%').height(220).clip(true).borderRadius(24).border({ width: 1, color: $r('app.color.card_border') }).margin({ bottom: 14 })
  }

  // ===== 2. 我的脑机数据 =====
  @Builder brainDataSection() {
    Column() {
      Row() { Text('我的脑机数据').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')); Blank(); Text('本周').fontSize(10).fontColor($r('app.color.text_tertiary')) }.width('100%').margin({ bottom: 10 })

      Row() {
        this.dataCard('#45E6A5', '最佳方格', this.fmtS(), '↑ 8%', '专注力 · 视觉搜索')
        this.dataCard('#4DA3FF', '持续专注', this.fmtE(), '↑ 12%', '注意力 · 持久训练')
      }.width('100%').justifyContent(FlexAlign.SpaceBetween).margin({ bottom: 8 })

      Row() {
        this.dataCard('#FFB84D', '脑控里程', this.fmtF(), '↑ 5%', '脑机交互 · 飞行控制')
        Column() {
          Row() { Circle({ width: 6, height: 6 }).fill('#8B7CFF'); Text(' 累计训练').fontSize(10).fontColor($r('app.color.text_tertiary')); Blank(); Text('↑').fontSize(9).fontColor('#45E6A5').fontFamily('monospace') }.width('100%')
          Text(this.getTotalTrain().toString() + ' 次').fontSize(26).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).fontFamily('monospace').margin({ top: 6 })
          Text(this.getTotalTime() + ' 总时长').fontSize(9).fontColor($r('app.color.text_muted')).margin({ top: 2 })
          Row() { Row().width('40%').height(2).backgroundColor('#8B7CFF60').borderRadius(1); Row().width('70%').height(2).backgroundColor('#8B7CFF40').borderRadius(1) }.width('60%').margin({ top: 6 })
        }.width('48%').padding(12).backgroundColor($r('app.color.card_bg_strong')).borderRadius(16).border({ width: 1, color: '#8B7CFF' + '15' }).alignItems(HorizontalAlign.Start)
      }.width('100%').justifyContent(FlexAlign.SpaceBetween)
    }.width('92%').padding({ top: 16, bottom: 16 }).backgroundColor($r('app.color.card_bg')).borderRadius(22).border({ width: 1, color: $r('app.color.card_border') }).margin({ bottom: 14 })
  }

  @Builder dataCard(color: string, label: string, value: string, trend: string, sub: string) {
    Column() {
      Row() { Circle({ width: 6, height: 6 }).fill(color); Text(' ' + label).fontSize(10).fontColor($r('app.color.text_tertiary')); Blank(); Text(trend).fontSize(9).fontColor('#45E6A5').fontFamily('monospace') }.width('100%')
      Text(value).fontSize(26).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).fontFamily('monospace').margin({ top: 6 })
      Text(sub).fontSize(9).fontColor($r('app.color.text_muted')).margin({ top: 2 })
      // 微型趋势线（模拟）
      Row() { Row().width('30%').height(2).backgroundColor(color+'60').borderRadius(1); Row().width('60%').height(2).backgroundColor(color+'40').borderRadius(1); Row().width('80%').height(2).backgroundColor(color+'25').borderRadius(1) }.width('60%').margin({ top: 6 })
    }.width('48%').padding(12).backgroundColor($r('app.color.card_bg_strong')).borderRadius(16).border({ width: 1, color: color + '15' }).alignItems(HorizontalAlign.Start)
  }

  // ===== 3. Neural Growth 成长轨迹 =====
  @Builder neuralGrowthSection() {
    Column() {
      Row() { Text('Neural Growth').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')); Blank(); Text('Lv.' + this.getLevel().toString()).fontSize(11).fontColor('#45E6A5').fontFamily('monospace').fontWeight(FontWeight.Bold) }.width('100%').padding({ left: 16, right: 16, top: 14, bottom: 6 })

      // Lv1-Lv5 路径
      Row() {
        ForEach([1, 2, 3, 4, 5], (lv: number) => {
          Column() {
            Stack() {
              Circle({ width: 16, height: 16 }).fill(lv < this.getLevel() ? '#45E6A5' : lv === this.getLevel() ? '#45E6A5' : 'rgba(255,255,255,0.06)')
                .stroke(lv === this.getLevel() ? '#45E6A5' : '#00000000').strokeWidth(2)
                .shadow({ radius: lv <= this.getLevel() ? 6 : 0, color: lv <= this.getLevel() ? '#4045E6A5' : '#00000000', offsetX: 0, offsetY: 0 })
              if (lv <= this.getLevel()) { Text('✓').fontSize(8).fontColor('#080D18').fontWeight(FontWeight.Bold) }
            }
            Text('Lv.' + lv.toString()).fontSize(7).fontColor(lv <= this.getLevel() ? '#45E6A5' : $r('app.color.text_muted')).margin({ top: 3 })
          }.alignItems(HorizontalAlign.Center).layoutWeight(1)
        })
      }.width('100%').padding({ left: 12, right: 12, bottom: 4 })

      // 连接线 + 等级标签
      Row() {
        Text('累计训练').fontSize(9).fontColor($r('app.color.text_tertiary'))
        Text(this.getTotalTime()).fontSize(12).fontWeight(FontWeight.Bold).fontColor('#45E6A5').fontFamily('monospace').margin({ left: 4 })
        Blank()
        Text('解锁下一级需 40s 内完成舒尔特').fontSize(8).fontColor($r('app.color.text_muted'))
      }.width('100%').padding({ left: 16, right: 16, bottom: 12 })
    }.width('92%').backgroundColor($r('app.color.card_bg')).borderRadius(22).border({ width: 1, color: $r('app.color.card_border') }).margin({ bottom: 14 })
  }

  // ===== 4. System Preference 系统偏好 =====
  @Builder systemPrefSection() {
    Column() {
      Row() { Text('System Preference').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')) }.width('100%').padding({ left: 16, right: 16, top: 14, bottom: 4 })

      Column() {
        // 深色模式
        Row() {
          Stack() { Circle({ width: 28, height: 28 }).fill('rgba(139,124,255,0.12)'); Text('◐').fontSize(13).fontColor('#8B7CFF') }
          Column() { Text('深色模式').fontSize(12).fontColor($r('app.color.text_primary')); Text('护眼 · 沉浸式脑机体验').fontSize(9).fontColor($r('app.color.text_tertiary')) }.alignItems(HorizontalAlign.Start).margin({ left: 10 }).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.darkMode }).selectedColor('#45E6A5').onChange((isOn: boolean) => { this.darkMode = isOn; storageService.setNumber(DARK_MODE_KEY, isOn ? 1 : 0); storageService.setColorMode(isOn); AppStorage.set('dark_mode_on', isOn ? 1 : 0); AppStorage.set('dark_mode_version', Date.now()); })
        }.width('100%').padding({ left: 16, right: 16, top: 10, bottom: 10 })
        Divider().strokeWidth(0.5).color($r('app.color.card_border')).margin({ left: 16, right: 16 })
        // 视觉保护
        Row() {
          Stack() { Circle({ width: 28, height: 28 }).fill('rgba(69,230,165,0.12)'); Text('👁').fontSize(11).fontColor('#45E6A5') }
          Column() { Text('视觉保护').fontSize(12).fontColor($r('app.color.text_primary')); Text('减少蓝光 · 保护视觉神经').fontSize(9).fontColor($r('app.color.text_tertiary')) }.alignItems(HorizontalAlign.Start).margin({ left: 10 }).layoutWeight(1)
          Text('开启').fontSize(10).fontColor('#45E6A5')
        }.width('100%').padding({ left: 16, right: 16, top: 10, bottom: 10 })
        Divider().strokeWidth(0.5).color($r('app.color.card_border')).margin({ left: 16, right: 16 })
        // 数据同步
        Row() {
          Stack() { Circle({ width: 28, height: 28 }).fill('rgba(77,163,255,0.12)'); Text('↻').fontSize(13).fontColor('#4DA3FF') }
          Column() { Text('数据同步').fontSize(12).fontColor($r('app.color.text_primary')); Text('蓝牙 · 实时脑波传输').fontSize(9).fontColor($r('app.color.text_tertiary')) }.alignItems(HorizontalAlign.Start).margin({ left: 10 }).layoutWeight(1)
          Text(this.connected ? '已连接' : '未连接').fontSize(10).fontColor(this.connected ? '#45E6A5' : $r('app.color.text_muted'))
        }.width('100%').padding({ left: 16, right: 16, top: 10, bottom: 10 })
      }.width('100%')
    }.width('92%').backgroundColor($r('app.color.card_bg')).borderRadius(22).border({ width: 1, color: $r('app.color.card_border') }).margin({ bottom: 14 })
  }

  // ===== 5. Brain Interface 设备信息 =====
  @Builder deviceInfoSection() {
    Column() {
      Row() {
        Text('Brain Interface').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Blank()
        Circle({ width: 24, height: 24 }).fill('rgba(69,230,165,0.1)').stroke('rgba(69,230,165,0.2)').strokeWidth(1)
        Text('⬡').fontSize(9).fontColor('#45E6A5').position({ x: 0, y: 0 }).translate({ x: '12vp', y: '-5vp' })
      }.width('100%').padding({ left: 16, right: 16, top: 14, bottom: 6 })

      Column() {
        this.devRow('处理器', 'BrainPi H3863')
        Divider().strokeWidth(0.5).color($r('app.color.card_border')).margin({ left: 16, right: 16 })
        this.devRow('通信', '蓝牙 BLE 5.2')
        Divider().strokeWidth(0.5).color($r('app.color.card_border')).margin({ left: 16, right: 16 })
        this.devRow('脑电采集', 'NeuroSky TGAM 模块')
        Divider().strokeWidth(0.5).color($r('app.color.card_border')).margin({ left: 16, right: 16 })
        this.devRow('系统', 'NeuroOS v1.0')
        Divider().strokeWidth(0.5).color($r('app.color.card_border')).margin({ left: 16, right: 16 })
        this.devRow('平台', 'HarmonyOS API 23')
      }.width('100%').padding({ bottom: 8 })
    }.width('92%').backgroundColor($r('app.color.card_bg')).borderRadius(22).border({ width: 1, color: $r('app.color.card_border') }).margin({ bottom: 14 })
  }

  @Builder devRow(label: string, value: string) {
    Row() { Text(label).fontSize(11).fontColor($r('app.color.text_tertiary')).width(48); Text(value).fontSize(11).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')) }
      .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }
}
