import { EEGDataStore } from '../store/EEGDataStore';

const store = EEGDataStore.getInstance();

interface NavItem {
  label: string;
  icon: string;
}

const INDIVIDUAL_ITEMS: NavItem[] = [
  { label: '设备管理',  icon: '📡' },
  { label: '脑波数据',  icon: '🧠' },
  { label: '脑控游戏',  icon: '🎮' },
  { label: '情绪识别',  icon: '😊' },
  { label: '运动想象',  icon: '🤚' },
  { label: '专注训练',  icon: '🎯' },
  { label: '个人中心',  icon: '👤' },
];

const SUPERVISOR_ITEMS: NavItem[] = [
  { label: '设备管理',   icon: '📡' },
  { label: '多设备监测',  icon: '📊' },
];

@Component
export struct SideBar {
  @Link expanded: boolean;
  @Link mode: string;
  @Prop activeIndex: number;
  onNavigate: (index: number) => void = () => {};

  private getItems(): NavItem[] {
    return this.mode === 'supervisor' ? SUPERVISOR_ITEMS : INDIVIDUAL_ITEMS;
  }

  build() {
    Column() {
      // Logo 区
      Column() {
        if (this.expanded) {
          Stack() {
            Circle().width(38).height(38).fill($r('app.color.primary'))
            Text('🧠').fontSize(18)
          }
          Text('EEG Monitor')
            .fontSize(13).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .margin({ top: 8 })
        } else {
          Stack() {
            Circle().width(34).height(34).fill($r('app.color.primary'))
            Text('🧠').fontSize(16)
          }
        }
      }
      .width('100%').padding({ top: 20, bottom: 14 })
      .alignItems(HorizontalAlign.Center)

      Divider().width('55%').height(1).color($r('app.color.divider'))

      // 导航项
      List() {
        ForEach(this.getItems(), (item: NavItem, idx: number) => {
          ListItem() {
            Row() {
              Text(item.icon).fontSize(this.expanded ? 17 : 19)
              if (this.expanded) {
                Text(item.label)
                  .fontSize(13)
                  .fontWeight(this.activeIndex === idx ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(this.activeIndex === idx ?
                    $r('app.color.primary') : $r('app.color.text_secondary'))
                  .margin({ left: 12 })
              }
            }
            .width('100%').height(44)
            .justifyContent(this.expanded ? FlexAlign.Start : FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .padding({ left: this.expanded ? 18 : 0, right: this.expanded ? 8 : 0 })
            .borderRadius(12)
            .backgroundColor(this.activeIndex === idx ?
              $r('app.color.primary_light') : '#00000000')
            .margin({ top: 3, bottom: 3 })
            .onClick(() => { this.onNavigate(idx); })
          }
        }, (_item: NavItem, idx: number): string => idx.toString())
      }
      .width('100%').layoutWeight(1).padding({ top: 8, left: 6, right: 6 })

      // 折叠按钮
      Divider().width('55%').height(1).color($r('app.color.divider'))
      Row() {
        Text(this.expanded ? '◀' : '▶')
          .fontSize(16).fontColor($r('app.color.text_tertiary'))
      }
      .width('100%').height(44).justifyContent(FlexAlign.Center)
      .onClick(() => { this.expanded = !this.expanded; })

      // 角色切换
      Row() {
        Row() {
          Text('👤').fontSize(11)
          if (this.expanded) {
            Text('个人').fontSize(11).fontColor(this.mode === 'individual' ?
              '#21C77A' : $r('app.color.text_secondary')).margin({ left: 4 })
          }
        }
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .backgroundColor(this.mode === 'individual' ?
          'rgba(33,199,122,0.12)' : '#00000000')
        .borderRadius(10)
        .onClick(() => {
          this.mode = 'individual';
          this.onNavigate(0);
        })

        Row() {
          Text('🛡').fontSize(11)
          if (this.expanded) {
            Text('管理').fontSize(11).fontColor(this.mode === 'supervisor' ?
              '#3B82F6' : $r('app.color.text_secondary')).margin({ left: 4 })
          }
        }
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .backgroundColor(this.mode === 'supervisor' ?
          'rgba(59,130,246,0.12)' : '#00000000')
        .borderRadius(10)
        .onClick(() => {
          this.mode = 'supervisor';
          this.onNavigate(0);
        })
      }
      .width('100%').justifyContent(FlexAlign.SpaceEvenly)
      .padding({ top: 8, bottom: 8 })

      if (this.expanded) {
        Text('v1.2 · 嵌入式竞赛作品')
          .fontSize(9).fontColor($r('app.color.text_muted'))
          .margin({ bottom: 12 })
      }
    }
    .width(this.expanded ? 200 : 56)
    .height('100%')
    .backgroundColor($r('app.color.card_bg'))
    .animation({ duration: 220, curve: Curve.EaseOut })
  }
}
