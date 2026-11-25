import { EEGDataStore } from '../store/EEGDataStore';
import { GamePage } from './GamePage';

const store = EEGDataStore.getInstance();

@Component
export struct GameHubPage {
  @State showGame: boolean = false;
  @StorageProp('dark_mode_on') darkModeOn: number = 0;
  @StorageLink('hub_reset') @Watch('onHubReset') hubReset: number = 0;

  onHubReset(): void {
    this.showGame = false;
  }

  build() {
    if (this.showGame) {
      GamePage()
    } else {
      Column() {
        Scroll() {
          Column() {
            this.deviceBar()
            this.heroCard()
            this.guideCard()
            this.readyCard()
          }
          .width('100%').alignItems(HorizontalAlign.Center)
          .padding({ top: 12, bottom: 24 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .linearGradient({
        direction: GradientDirection.Bottom,
        colors: [[$r('app.color.page_bg_gradient_top'), 0.0], [$r('app.color.page_bg_gradient_mid'), 0.5], [$r('app.color.page_bg_gradient_bottom'), 1.0]]
      })
    }
  }

  // ===== 1. 设备状态卡 =====
  @Builder
  deviceBar() {
    Row() {
      Row() {
        Stack() {
          Circle().width(36).height(36)
            .fill($r('app.color.primary_light'))
          Circle().width(10).height(10)
            .fill($r('app.color.status_online'))
            .shadow({ radius: 6, color: $r('app.color.shadow_glow_green'), offsetX: 0, offsetY: 0 })
        }
        Column() {
          Row() {
            Text('脑波连接正常')
              .fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
          }
          Text('NeuroOS 脑机交互')
            .fontSize(10).fontColor($r('app.color.text_tertiary')).margin({ top: 1 })
        }
        .alignItems(HorizontalAlign.Start).margin({ left: 10 })
      }

      Blank()

      Column() {
        Text('100%')
          .fontSize(13).fontWeight(FontWeight.Bold).fontColor($r('app.color.secondary')).fontFamily('monospace')
        Text('控制稳定度')
          .fontSize(8).fontColor($r('app.color.text_tertiary'))
      }
      .alignItems(HorizontalAlign.Center).margin({ right: 16 })

      Row() {
        Circle().width(5).height(5).fill($r('app.color.status_online'))
        Text('优秀')
          .fontSize(11).fontColor($r('app.color.status_online')).margin({ left: 4 })
      }
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .backgroundColor($r('app.color.primary_light')).borderRadius(8)
    }
    .width('92%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .linearGradient({
      angle: 145,
      colors: [['rgba(255,255,255,0.05)', 0.0], ['rgba(255,255,255,0.0)', 0.35]]
    })
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(24)
    .border({ width: 1, color: $r('app.color.card_border') })
    .margin({ bottom: 12 })
  }

  // ===== 2. 主视觉入口卡 =====
  @Builder
  heroCard() {
    Column() {
      Stack() {
        // 深空背景
        Image($r('app.media.bg_gamehub')).width('100%').height(320).objectFit(ImageFit.Cover).borderRadius(24)
        Column().width('100%').height(320).backgroundColor('rgba(6,14,31,0.5)').borderRadius(24)

        // 背景星点
        Circle({ width: 1.5, height: 1.5 }).fill('rgba(255,255,255,0.25)').position({ x: '10%', y: '25%' })
        Circle({ width: 1, height: 1 }).fill('rgba(255,255,255,0.2)').position({ x: '25%', y: '15%' })
        Circle({ width: 2, height: 2 }).fill('rgba(255,255,255,0.3)').position({ x: '75%', y: '20%' })
        Circle({ width: 1, height: 1 }).fill('rgba(255,255,255,0.18)').position({ x: '88%', y: '35%' })
        Circle({ width: 1.5, height: 1.5 }).fill('rgba(255,255,255,0.22)').position({ x: '15%', y: '55%' })

        // 标题区
        Text('脑控交互实验')
          .fontSize(20).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .position({ x: '50%', y: 24 })
          .translate({ x: '-50%' })

        // === 中央实验舱体 ===
        // 外光环（大）
        Circle({ width: 160, height: 160 })
          .fill('#00000000')
          .stroke('rgba(77,163,255,0.15)').strokeWidth(1)
          .position({ x: '50%', y: '50%' })
          .translate({ x: '-80vp', y: '-80vp' })

        // 中光环
        Circle({ width: 120, height: 120 })
          .fill('#00000000')
          .stroke('rgba(70,230,165,0.20)').strokeWidth(0.5)
          .strokeDashArray([4, 12])
          .position({ x: '50%', y: '50%' })
          .translate({ x: '-60vp', y: '-60vp' })

        // 底部光环台座
        Ellipse({ width: 120, height: 24 })
          .fill('rgba(70,230,165,0.08)')
          .stroke('rgba(70,230,165,0.25)').strokeWidth(1)
          .position({ x: '50%', y: '65%' })
          .translate({ x: '-60vp', y: 0 })

        // 底部光柱（从台座向上）
        Column()
          .width(2).height(30)
          .linearGradient({
            direction: GradientDirection.Top,
            colors: [['rgba(77,163,255,0)', 0.0], ['rgba(77,163,255,0.4)', 1.0]]
          })
          .position({ x: '50%', y: '65%' })
          .translate({ x: '-20vp', y: '-30vp' })

        Column()
          .width(2).height(40)
          .linearGradient({
            direction: GradientDirection.Top,
            colors: [['rgba(77,163,255,0)', 0.0], ['rgba(77,163,255,0.35)', 1.0]]
          })
          .position({ x: '50%', y: '65%' })
          .translate({ x: '15vp', y: '-40vp' })

        Column()
          .width(1.5).height(25)
          .linearGradient({
            direction: GradientDirection.Top,
            colors: [['rgba(70,230,165,0)', 0.0], ['rgba(70,230,165,0.3)', 1.0]]
          })
          .position({ x: '50%', y: '65%' })
          .translate({ x: '-35vp', y: '-25vp' })

        // 中央脑球体
        Stack() {
          // 光晕
          Circle({ width: 80, height: 80 })
            .fill('rgba(77,163,255,0.1)')
            .shadow({ radius: 30, color: 'rgba(77,163,255,0.2)', offsetX: 0, offsetY: 0 })
          // 核心
          Circle({ width: 56, height: 56 })
            .fill('rgba(70,230,165,0.25)')
          Circle({ width: 38, height: 38 })
            .fill('rgba(70,230,165,0.5)')
            .shadow({ radius: 16, color: 'rgba(70,230,165,0.4)', offsetX: 0, offsetY: 0 })
          Text('脑')
            .fontSize(18).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
        }
        .position({ x: '50%', y: '50%' })
        .translate({ x: '-40vp', y: '-40vp' })

        // 右上数据标签：专注度
        Column() {
          Text('专注控制')
            .fontSize(8).fontColor($r('app.color.text_tertiary'))
          Text('Altitude')
            .fontSize(7).fontColor('rgba(77,163,255,0.6)')
        }
        .alignItems(HorizontalAlign.Center)
        .position({ x: '72%', y: '28%' })
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .backgroundColor('rgba(255,255,255,0.03)')
        .border({ width: 0.5, color: 'rgba(77,163,255,0.15)', radius: 6 })

        // 左上数据标签：放松度
        Column() {
          Text('冥想调节')
            .fontSize(8).fontColor($r('app.color.text_tertiary'))
          Text('Velocity')
            .fontSize(7).fontColor('rgba(70,230,165,0.6)')
        }
        .alignItems(HorizontalAlign.Center)
        .position({ x: '12%', y: '35%' })
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .backgroundColor('rgba(255,255,255,0.03)')
        .border({ width: 0.5, color: 'rgba(70,230,165,0.15)', radius: 6 })

        // 左下数据标签：眨眼
        Column() {
          Text('眨眼触发')
            .fontSize(8).fontColor($r('app.color.text_tertiary'))
          Text('Shoot')
            .fontSize(7).fontColor('rgba(70,230,165,0.6)')
        }
        .alignItems(HorizontalAlign.Center)
        .position({ x: '18%', y: '55%' })
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .backgroundColor('rgba(255,255,255,0.03)')
        .border({ width: 0.5, color: 'rgba(70,230,165,0.15)', radius: 6 })

        // 底部文字 + 按钮
        Column() {
          Text('通过专注与意念控制飞船移动，进入脑机交互体验')
            .fontSize(10).fontColor($r('app.color.text_secondary'))

          Button('进入实验')
            .width(160).height(40)
            .linearGradient({
              angle: 135,
              colors: [['#46E6A5', 0.0], ['#2ECC71', 1.0]]
            })
            .borderRadius(20)
            .fontSize(14).fontColor($r('app.color.primary_text_on')).fontWeight(FontWeight.Bold)
            .shadow({ radius: 12, color: 'rgba(70,230,165,0.35)', offsetX: 0, offsetY: 3 })
            .margin({ top: 10 })
            .onClick(() => { this.showGame = true; })
        }
        .width('100%').alignItems(HorizontalAlign.Center)
        .position({ x: '50%', y: '78%' })
        .translate({ x: '-50%' })
      }
    }
    .width('92%').height(320)
    .clip(true)
    .borderRadius(24)
    .border({ width: 1, color: $r('app.color.card_border') })
    .margin({ bottom: 12 })
  }

  // ===== 3. 玩法说明卡 =====
  @Builder
  guideCard() {
    Column() {
      Text('玩法说明')
        .fontSize(14).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: 14 })
        .alignSelf(ItemAlign.Start)

      Row() {
        this.guideStep('01', '保持设备连接', '确保 BrainPi\n已正确佩戴')
        Column() {
          Text('→')
            .fontSize(16).fontColor($r('app.color.text_muted'))
            .margin({ top: 14 })
        }
        this.guideStep('02', '集中注意力', '专注度控制\n飞船高度移动')
        Column() {
          Text('→')
            .fontSize(16).fontColor($r('app.color.text_muted'))
            .margin({ top: 14 })
        }
        this.guideStep('03', '实时脑控反馈', '在实验页实时\n感受脑控反馈')
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceEvenly)
    }
    .width('92%').padding(18)
    .linearGradient({
      angle: 145,
      colors: [['rgba(255,255,255,0.05)', 0.0], ['rgba(255,255,255,0.0)', 0.35]]
    })
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(24)
    .border({ width: 1, color: $r('app.color.card_border') })
    .margin({ bottom: 12 })
  }

  @Builder
  guideStep(num: string, title: string, desc: string) {
    Column() {
      Text(num)
        .fontSize(14).fontWeight(FontWeight.Bold)
        .fontColor('#46E6A5').fontFamily('monospace')
        .padding({ left: 8, right: 8, top: 2, bottom: 2 })
        .backgroundColor('rgba(70,230,165,0.08)').borderRadius(6)
      Text(title)
        .fontSize(11).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 8 })
      Text(desc)
        .fontSize(9).fontColor($r('app.color.text_tertiary'))
        .textAlign(TextAlign.Center).lineHeight(14)
        .margin({ top: 4 })
    }
    .alignItems(HorizontalAlign.Center)
  }

  // ===== 4. 实验准备卡 =====
  @Builder
  readyCard() {
    Row() {
      this.readyItem('设备', '已连接', '#46E6A5')
      Column().width(1).height(32).backgroundColor($r('app.color.card_border'))
      this.readyItem('模式', '脑控飞行', '#4DA3FF')
      Column().width(1).height(32).backgroundColor($r('app.color.card_border'))
      this.readyItem('状态', '可开始', '#46E6A5')
    }
    .width('92%').padding({ top: 18, bottom: 18 })
    .linearGradient({
      angle: 145,
      colors: [['rgba(255,255,255,0.05)', 0.0], ['rgba(255,255,255,0.0)', 0.35]]
    })
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(24)
    .border({ width: 1, color: $r('app.color.card_border') })
    .justifyContent(FlexAlign.SpaceEvenly)
    .margin({ bottom: 12 })
  }

  @Builder
  readyItem(label: string, value: string, color: string) {
    Column() {
      Circle({ width: 6, height: 6 }).fill(color)
        .shadow({ radius: 4, color: color + '40', offsetX: 0, offsetY: 0 })
      Text(value)
        .fontSize(14).fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 8 })
      Text(label)
        .fontSize(10)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ top: 2 })
    }
    .alignItems(HorizontalAlign.Center)
    .layoutWeight(1)
  }
}
