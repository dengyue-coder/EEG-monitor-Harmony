import { router } from '@kit.ArkUI';

@Entry
@Component
struct EmotionInfoPage {
  build() {
    Scroll() {
      Column() {
        this.titleSection()
        this.russellModel()
        this.emotionTable()
        this.bandTable()
        this.flowSection()
      }
      .width('100%').alignItems(HorizontalAlign.Center).padding({ top: 8, bottom: 32 })
    }
    .width('100%').height('100%').backgroundColor($r('app.color.background')).scrollBar(BarState.Off)
  }

  @Builder
  titleSection() {
    Row() {
      Button('← 返回')
        .fontSize(13).fontColor('#6CBE8A')
        .backgroundColor($r('app.color.primary_light')).borderRadius(8)
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .onClick(() => { router.back(); })

      Blank()

      Text('算法原理').fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))

      Blank()
      // 占位对称
      Row().width(56).height(1)
    }
    .width('92%').padding({ top: 12, bottom: 12 })
  }

  // ===== Russell 环状模型说明 =====

  @Builder
  russellModel() {
    Column() {
      Row() {
        Text('Russell 环状模型')
          .fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      }.width('100%').padding({ left: 16, right: 16, top: 16, bottom: 8 })

      Text('情绪由两个维度决定：效价（Valence）和唤醒度（Arousal），构成一个二维环状空间。')
        .fontSize(13).fontColor($r('app.color.text_tertiary')).lineHeight(22)
        .width('100%').padding({ left: 16, right: 16, bottom: 10 })

      Row() {
        Column() {
          Text('V · 效价 Valence').fontSize(13).fontWeight(FontWeight.Medium).fontColor('#6CBE8A')
          Text('愉悦 ⇄ 不愉悦').fontSize(11).fontColor($r('app.color.text_secondary')).margin({ top: 2 })
          Text('由 α/β 比值 + 专注度驱动')
            .fontSize(11).fontColor($r('app.color.text_muted')).margin({ top: 2 })
        }.alignItems(HorizontalAlign.Start).layoutWeight(1).padding(12)
        .backgroundColor('#F0FAF4').borderRadius(12).margin({ right: 6 })

        Column() {
          Text('A · 唤醒度 Arousal').fontSize(13).fontWeight(FontWeight.Medium).fontColor('#F5A623')
          Text('激动 ⇄ 平静').fontSize(11).fontColor($r('app.color.text_secondary')).margin({ top: 2 })
          Text('由 (β+γ)/(δ+θ) + 冥想度驱动')
            .fontSize(11).fontColor($r('app.color.text_muted')).margin({ top: 2 })
        }.alignItems(HorizontalAlign.Start).layoutWeight(1).padding(12)
        .backgroundColor('#FFF9F0').borderRadius(12).margin({ left: 6 })
      }
      .width('100%').padding({ left: 16, right: 16, bottom: 14 })
    }
    .width('92%').backgroundColor($r('app.color.card_bg')).borderRadius(22)
    .border({ width: 1, color: $r('app.color.card_border') }).margin({ bottom: 12 })
  }

  // ===== 情绪分类映射表 =====

  @Builder
  emotionTable() {
    Column() {
      Row() {
        Text('情绪分类映射表')
          .fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Blank()
        Text('9种情绪').fontSize(11).fontColor($r('app.color.text_muted'))
      }.width('100%').padding({ left: 16, right: 16, top: 16, bottom: 10 })

      // 表头
      this.tableHeader()

      // 行
      this.emotionRow('😄', '开心快乐', 'V > 62', 'A > 58', '—', '#FF9500')
      this.emotionRow('🤩', '兴奋激动', 'V > 45', 'A > 75', '—', '#C544F0')
      this.emotionRow('🎯', '高度专注', 'V 35~85', 'A 25~75', 'Att > 70', '#4A90D9')
      this.emotionRow('😌', '放松宁静', 'V > 65', 'A < 38', '—', '#6CBE8A')
      this.emotionRow('😰', '焦虑紧张', 'V < 38', 'A > 62', '—', '#F5A623')
      this.emotionRow('😢', '悲伤低落', 'V < 35', 'A < 35', '—', '#7B8FA1')
      this.emotionRow('😠', '愤怒烦躁', 'V < 25', 'A > 72', '—', '#E74C3C')
      this.emotionRow('😴', '疲惫困倦', '—', 'A < 22', 'Med > 65', '#8E6FAD')
      this.emotionRow('😐', '平静安稳', '—', '—', '默认', '#95A5A6')
    }
    .width('92%').backgroundColor($r('app.color.card_bg')).borderRadius(22)
    .border({ width: 1, color: $r('app.color.card_border') }).margin({ bottom: 12 })
  }

  @Builder
  tableHeader() {
    Row() {
      Text('情绪').fontSize(11).fontColor($r('app.color.text_tertiary')).width(60)
      Text('效价 V').fontSize(11).fontColor($r('app.color.text_tertiary')).width(60)
      Text('唤醒 A').fontSize(11).fontColor($r('app.color.text_tertiary')).width(60)
      Text('条件').fontSize(11).fontColor($r('app.color.text_tertiary')).width(55)
    }
    .width('100%').padding({ left: 16, right: 16, top: 6, bottom: 6 })
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  emotionRow(emoji: string, name: string, vRange: string, aRange: string, cond: string, color: string) {
    Row() {
      Text(emoji + ' ' + name).fontSize(11).fontColor(color).width(60)
      Text(vRange).fontSize(11).fontColor($r('app.color.text_secondary')).width(60)
      Text(aRange).fontSize(11).fontColor($r('app.color.text_secondary')).width(60)
      Text(cond).fontSize(11).fontColor($r('app.color.text_tertiary')).width(55)
    }
    .width('100%').padding({ left: 16, right: 16, top: 5, bottom: 5 })
    Divider().strokeWidth(0.5).color($r('app.color.divider')).margin({ left: 16, right: 16 })
  }

  // ===== 脑波频段速查 =====

  @Builder
  bandTable() {
    Column() {
      Row() {
        Text('脑波频段速查')
          .fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      }.width('100%').padding({ left: 16, right: 16, top: 16, bottom: 10 })

      Row() {
        Text('频段').fontSize(11).fontColor($r('app.color.text_tertiary')).width(50)
        Text('频率').fontSize(11).fontColor($r('app.color.text_tertiary')).width(70)
        Text('关联心理状态').fontSize(11).fontColor($r('app.color.text_tertiary'))
      }
      .width('100%').padding({ left: 16, right: 16, top: 6, bottom: 6 })
      .backgroundColor($r('app.color.background'))

      this.bandRow('δ Delta', '0.5–4 Hz', '深度睡眠、无意识')
      this.bandRow('θ Theta', '4–8 Hz', '冥想、困倦、潜意识')
      this.bandRow('α Alpha', '8–13 Hz', '放松清醒、闭眼休息')
      this.bandRow('β Beta', '13–30 Hz', '活跃思考、专注警觉')
      this.bandRow('γ Gamma', '30–50 Hz', '高级认知、信息整合')
    }
    .width('92%').backgroundColor($r('app.color.card_bg')).borderRadius(22)
    .border({ width: 1, color: $r('app.color.card_border') }).margin({ bottom: 12 })
  }

  @Builder
  bandRow(name: string, freq: string, desc: string) {
    Row() {
      Text(name).fontSize(12).fontColor($r('app.color.text_primary')).width(50)
      Text(freq).fontSize(11).fontColor($r('app.color.text_secondary')).width(70)
      Text(desc).fontSize(11).fontColor($r('app.color.text_tertiary')).layoutWeight(1)
    }
    .width('100%').padding({ left: 16, right: 16, top: 5, bottom: 5 })
    Divider().strokeWidth(0.5).color($r('app.color.divider')).margin({ left: 16, right: 16 })
  }

  // ===== 分类流程 =====

  @Builder
  flowSection() {
    Column() {
      Row() {
        Text('分类流程')
          .fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      }.width('100%').padding({ left: 16, right: 16, top: 16, bottom: 12 })

      Row() {
        this.flowStep('1', '数据采集', 'BLE 接收\n脑波数据包', '#6CBE8A')
        Text('→').fontSize(18).fontColor($r('app.color.text_muted')).margin({ left: 4, right: 4 })
        this.flowStep('2', '特征提取', '计算 V/A\n六个维度', '#4A90D9')
        Text('→').fontSize(18).fontColor($r('app.color.text_muted')).margin({ left: 4, right: 4 })
        this.flowStep('3', '规则匹配', 'if/else 逐条\n优先级排序', '#F5A623')
        Text('→').fontSize(18).fontColor($r('app.color.text_muted')).margin({ left: 4, right: 4 })
        this.flowStep('4', '情绪输出', '显示面孔\n+ 心灵寄语', '#C544F0')
      }
      .width('100%').padding({ left: 8, right: 8, bottom: 16 })
      .justifyContent(FlexAlign.Center)

      Text('注意：这是基于规则的单通道前额脑电估算，非临床级多导联 EEG 分析。')
        .fontSize(11).fontColor($r('app.color.text_muted')).lineHeight(18)
        .width('100%').padding({ left: 16, right: 16, bottom: 4 })
    }
    .width('92%').backgroundColor($r('app.color.card_bg')).borderRadius(22)
    .border({ width: 1, color: $r('app.color.card_border') }).margin({ bottom: 12 })
  }

  @Builder
  flowStep(num: string, title: string, desc: string, color: string) {
    Column() {
      Text(num)
        .fontSize(14).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
        .width(28).height(28).borderRadius(14)
        .backgroundColor(color).textAlign(TextAlign.Center)
      Text(title).fontSize(11).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).margin({ top: 6, bottom: 2 })
      Text(desc).fontSize(9).fontColor($r('app.color.text_tertiary')).textAlign(TextAlign.Center).lineHeight(14)
    }
    .alignItems(HorizontalAlign.Center)
  }
}
