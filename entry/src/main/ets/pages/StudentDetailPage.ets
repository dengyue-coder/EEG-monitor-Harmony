import { EEGDataStore, TrendPoint } from '../store/EEGDataStore';
import { BrainwavePage } from './Brainwave';
import { EmotionPage } from './EmotionPage';

const store = EEGDataStore.getInstance();

const SUBJ_STUDENT = 1;
const SUBJ_ELDERLY = 2;
const SUBJ_PATIENT = 3;

@Component
export struct StudentDetailPage {
  @State tab: number = 0;
  @State tabInit: boolean[] = [true, false, false];
  @State reportVersion: number = 0;
  @State subjectType: number = 0;
  @State pendingSubjectType: number = 0;
  @State showHelpPopup: boolean = false;
  onBack: () => void = () => {};

  private getDeviceLabel(): string {
    const info = store.getDeviceInfo(store.getActiveDeviceId());
    return info?.deviceName ?? '未知设备';
  }

  build() {
    Column() {
      Row() {
        Text('← 返回课堂')
          .fontSize(14).fontColor('#4A90D9').fontWeight(FontWeight.Medium)
          .padding({ left: 4, right: 10, top: 10, bottom: 10 })
          .onClick(() => { this.onBack(); })
        Blank()
        Text(this.getDeviceLabel())
          .fontSize(13).fontColor($r('app.color.text_secondary'))
      }
      .width('100%').padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .backgroundColor($r('app.color.card_bg'))

      Tabs({ barPosition: BarPosition.End, index: this.tab }) {
        TabContent() {
          if (this.tabInit[0]) { BrainwavePage() }
        }.tabBar(this.studentTabBuilder('脑波', '波', 0))

        TabContent() {
          if (this.tabInit[1]) { EmotionPage({ readOnly: true }) }
        }.tabBar(this.studentTabBuilder('情绪', '绪', 1))

        TabContent() {
          if (this.tabInit[2]) { this.reportView() }
        }.tabBar(this.studentTabBuilder('报告', '报', 2))
      }
      .barWidth('100%').barHeight(56).width('100%').layoutWeight(1)
      .barBackgroundColor($r('app.color.background'))
      .scrollable(false).animationDuration(180)
      .onChange((index: number) => {
        this.tab = index;
        const init = [...this.tabInit];
        init[index] = true;
        this.tabInit = init;
        if (index === 2) { this.reportVersion++; }
      })
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  studentTabBuilder(label: string, icon: string, idx: number) {
    Column() {
      Text(icon)
        .fontSize(this.tab === idx ? 18 : 14)
        .fontColor(this.tab === idx ? '#4A90D9' : '#B0B0B0')
        .fontWeight(FontWeight.Bold)
      Text(label)
        .fontSize(10)
        .fontColor(this.tab === idx ? '#4A90D9' : '#B0B0B0')
        .fontWeight(this.tab === idx ? FontWeight.Medium : FontWeight.Normal)
        .margin({ top: 2, bottom: 4 })
      Circle({ width: 4, height: 4 })
        .fill(this.tab === idx ? '#4A90D9' : '#00000000')
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
  }

  // ================================================================
  //  报告页入口
  // ================================================================

  @Builder
  reportView() {
    if (this.subjectType === 0) {
      this.subjectSelectionView();
    } else {
      this.generatedReportView();
    }
  }

  // ================================================================
  //  对象类型选择
  // ================================================================

  @Builder
  subjectSelectionView() {
    Column() {
      Blank()
      Column() {
        Text('请选择报告类型')
          .fontSize(17).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ bottom: 8 })
        Text('根据被监测对象选择对应的报告模板，将生成针对性的分析结果')
          .fontSize(12).fontColor($r('app.color.text_secondary'))
          .margin({ bottom: 20 }).lineHeight(17)

        this.subjectCard(
          '学生', SUBJ_STUDENT,
          '🎓', '#4A90D9',
          '分析课堂专注度、学习状态、情绪变化，提供个性化教学建议'
        )
        this.subjectCard(
          '老人', SUBJ_ELDERLY,
          '🧓', '#6CBE8A',
          '评估认知健康、睡眠质量、痴呆风险指标，提供健康监护建议'
        )
        this.subjectCard(
          '植物人', SUBJ_PATIENT,
          '🏥', '#E87461',
          '检测意识迹象、α波阻断事件、对外界刺激的脑电反应'
        )

        Button('生成报告')
          .fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor(this.pendingSubjectType > 0 ? '#FFFFFF' : '#B0B0B0')
          .backgroundColor(this.pendingSubjectType > 0 ? '#4A90D9' : $r('app.color.background'))
          .borderRadius(10).height(42).width('100%')
          .margin({ top: 12 })
          .enabled(this.pendingSubjectType > 0)
          .onClick(() => {
            if (this.pendingSubjectType > 0) {
              this.subjectType = this.pendingSubjectType;
            }
          })
      }
      .width('90%').padding(20)
      .backgroundColor($r('app.color.card_bg')).borderRadius(14)
      .shadow({ radius: 12, color: '#30000000', offsetX: 0, offsetY: 4 })
      Blank()
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  subjectCard(label: string, type: number, icon: string, color: string, desc: string) {
    Row() {
      Column() {
        Text(icon).fontSize(28)
        Text(label).fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor(this.pendingSubjectType === type ? color : $r('app.color.text_secondary'))
      }
      .width(60).alignItems(HorizontalAlign.Center)

      Column() {
        Text(desc)
          .fontSize(11).fontColor($r('app.color.text_secondary'))
          .lineHeight(16).maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1).margin({ left: 12 })
    }
    .width('100%').padding(12)
    .backgroundColor(this.pendingSubjectType === type ? color + '18' : $r('app.color.surface'))
    .borderRadius(10)
    .border({ width: 1.5, color: this.pendingSubjectType === type ? color : '#E8E8E8' })
    .margin({ bottom: 10 })
    .onClick(() => { this.pendingSubjectType = type; })
  }

  // ================================================================
  //  已生成报告
  // ================================================================

  @Builder
  generatedReportView() {
    Stack() {
      Scroll() {
        Column() {
          Row() {
            Text(this.getSubjectLabel())
              .fontSize(11).fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF').padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .backgroundColor(this.getSubjectColor()).borderRadius(10)
            Blank()
            Text('原理')
              .fontSize(11).fontColor('#FFFFFF')
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .backgroundColor('#999').borderRadius(10)
              .margin({ right: 8 })
              .onClick(() => { this.showHelpPopup = true; })
            Text('重新选择')
              .fontSize(11).fontColor('#4A90D9')
              .onClick(() => { this.subjectType = 0; this.pendingSubjectType = 0; })
          }
          .width('100%').margin({ bottom: 10 })

          this.reportOverviewCard()
          this.reportAnalysisCards()
          this.reportBandCard()
          this.reportSuggestionsCard()

          Blank().height(20)
        }
        .width('100%').padding({ left: 14, right: 14, top: 10 })
      }
      .width('100%').height('100%')

      // 诊断原理弹窗
      if (this.showHelpPopup) {
        Column() {
          Column() {
            Row() {
              Text('诊断原理说明')
                .fontSize(16).fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
              Blank()
              Text('✕')
                .fontSize(18).fontColor('#999')
                .onClick(() => { this.showHelpPopup = false; })
            }
            .width('100%').margin({ bottom: 14 })

            Scroll() {
              Column() {
                this.helpSection('脑电频段基础',
                  '脑电图（EEG）将大脑电活动按频率分为五个频段：\n' +
                  '• δ（0.5-4Hz）：深度睡眠或严重脑损伤时占主导\n' +
                  '• θ（4-8Hz）：放松冥想、浅睡或注意力涣散时增强\n' +
                  '• α（8-13Hz）：清醒放松、闭眼时最明显，是大脑"待机"状态\n' +
                  '• β（13-30Hz）：活跃思考、专注、焦虑时增强\n' +
                  '• γ（30-50Hz）：高级认知加工、信息整合，与意识密切相关')
                this.helpSection('金牛座脑波模块的 Attention/Meditation',
                  '金牛座脑波模块对原始脑电信号进行实时频谱分析，\n' +
                  '输出 0-100 的专注度（Attention）和冥想度（Meditation）指数。\n' +
                  '这两个指标基于各频段的功率比值和时域特征综合计算，\n' +
                  '而非直接对应某个单一频段。')
                this.helpSection('学生报告分析逻辑',
                  '• 专注度 >60 且放松度适中 → 理想学习状态\n' +
                  '• 专注度 >60 且放松度 <25 → 紧张专注，易疲劳\n' +
                  '• 专注度 <20 → 严重注意力缺失\n' +
                  '• δ 波 >530 且专注度低 → 困倦/睡眠不足\n' +
                  '• θ 波 >350 且专注度低 → 走神/白日梦\n' +
                  '• β/α >1.6 且专注度低 → 焦虑型分心')
                this.helpSection('老人报告分析逻辑',
                  '• δ/θ 比值：反映深度睡眠占比，正常范围 1.2-1.8\n' +
                  '  ——比值偏低 → 深睡不足，是痴呆的独立风险因素\n' +
                  '• 认知评分：综合 α + β + γ 活性减去过量 δ\n' +
                  '  ——快速频段（β/γ）下降是认知衰退的早期标志\n' +
                  '• δ/α 比值 >3.5 → 脑退行性变化的典型慢波化特征\n' +
                  '• γ 波 <25 → 高级认知网络功能减退预警')
                this.helpSection('植物人报告分析逻辑',
                  '• α 阻断事件：外界刺激时 α 功率下降 >30%\n' +
                  '  ——这是意识存在的关键脑电标志（Berger效应）\n' +
                  '  ——连续监测 α 阻断比单次检测更可靠\n' +
                  '• 意识波动：γ 或 β 功率突增 >50% 的瞬时事件\n' +
                  '  ——可能与残存的认知加工或外界刺激响应有关\n' +
                  '• δ/α 比值：弥漫性慢波（高 δ/α）vs 保留部分快波（低 δ/α）\n' +
                  '  ——比值持续下降是积极信号\n' +
                  '• 注意：本分析为辅助筛查工具，不可替代临床 CRS-R 量表、\n' +
                  '  fMRI 或 PET 等金标准检查。')
                this.helpSection('免责声明',
                  '本应用基于金牛座脑波模块采集数据，\n' +
                  '仅提供辅助参考，不具备医疗诊断资质。\n' +
                  '任何健康相关的担忧，请咨询专业医师。\n' +
                  'EEG 数据解读需结合完整的临床背景，\n' +
                  '单一指标异常不等于疾病。')
              }
              .width('100%')
            }
            .height(360).width('100%')
          }
          .width('88%').padding(18)
          .backgroundColor($r('app.color.card_bg')).borderRadius(14)
          .shadow({ radius: 16, color: '#40000000', offsetX: 0, offsetY: 6 })
        }
        .width('100%').height('100%')
        .backgroundColor('#66000000')
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%').height('100%')
  }

  @Builder
  helpSection(title: string, body: string) {
    Column() {
      Text(title)
        .fontSize(13).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .alignSelf(ItemAlign.Start).margin({ bottom: 6 })
      Text(body)
        .fontSize(11).fontColor($r('app.color.text_secondary'))
        .lineHeight(18).width('100%')
        .margin({ bottom: 16 })
    }
    .width('100%')
  }

  // -------------------------------------------------------
  //  数据概览卡片（按类型切换指标）
  // -------------------------------------------------------

  @Builder
  reportOverviewCard() {
    Column() {
      Text('数据概览')
        .fontSize(14).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .alignSelf(ItemAlign.Start).margin({ bottom: 10 })

      if (this.subjectType === SUBJ_STUDENT) {
        this.reportRow('采集数据点数', this.getTrendCount().toString() + ' 条')
        this.reportRow('平均专注度', this.getAvgAtt().toFixed(0))
        this.reportRow('平均冥想度', this.getAvgMed().toFixed(0))
        this.reportRow('信号质量', this.getSignalLabel())
      }

      if (this.subjectType === SUBJ_ELDERLY) {
        this.reportRow('采集数据点数', this.getTrendCount().toString() + ' 条')
        this.reportRow('认知健康评分', this.getCognitiveScore().toFixed(0) + ' / 100')
        this.reportRow('睡眠质量指数', this.getSleepQualityLabel())
        this.reportRow('情绪稳定性', this.getEmotionStabilityLabel())
        this.reportRow('信号质量', this.getSignalLabel())
      }

      if (this.subjectType === SUBJ_PATIENT) {
        this.reportRow('采集数据点数', this.getTrendCount().toString() + ' 条')
        this.reportRow('α 阻断疑似事件', this.getAlphaBlockingCount().toString() + ' 次')
        this.reportRow('意识波动标记', this.getConsciousnessFluctuationCount().toString() + ' 次')
        this.reportRow('外部刺激反应评分', this.getStimulusResponseScore().toFixed(0) + ' / 100')
        this.reportRow('信号质量', this.getSignalLabel())
      }
    }
    .width('100%').padding(14)
    .backgroundColor($r('app.color.card_bg')).borderRadius(14)
    .border({ width: 1, color: $r('app.color.card_border') })
    .margin({ bottom: 10 })
  }

  // -------------------------------------------------------
  //  专项分析卡片（按类型）
  // -------------------------------------------------------

  @Builder
  reportAnalysisCards() {
    if (this.subjectType === SUBJ_STUDENT) {
      this.studentAttentionCard()
      this.studentRelaxationCard()
    }
    if (this.subjectType === SUBJ_ELDERLY) {
      this.elderlySleepCard()
      this.elderlyCognitiveCard()
    }
    if (this.subjectType === SUBJ_PATIENT) {
      this.patientAlphaBlockingCard()
      this.patientConsciousnessCard()
    }
  }

  // ===================== 学生：专注度分析 =====================

  @Builder
  studentAttentionCard() {
    Column() {
      Text('专注度分析')
        .fontSize(14).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .alignSelf(ItemAlign.Start).margin({ bottom: 10 })
      Row() {
        Text('专注度趋势').fontSize(12).fontColor($r('app.color.text_secondary'))
        Blank()
        Text(this.getAttTrendLabel())
          .fontSize(12).fontWeight(FontWeight.Medium)
          .fontColor(this.getAttTrendColor())
      }
      .width('100%').margin({ bottom: 8 })
      Row() {
        Row()
          .width(`${Math.min(this.getAvgAtt(), 100)}%`)
          .height(8).backgroundColor('#4A90D9').borderRadius(4)
      }
      .width('100%').height(8)
      .backgroundColor($r('app.color.background')).borderRadius(4)
      Text(this.getAttSuggestion())
        .fontSize(11).fontColor($r('app.color.text_secondary'))
        .margin({ top: 8 }).lineHeight(17)
    }
    .width('100%').padding(14)
    .backgroundColor($r('app.color.card_bg')).borderRadius(14)
    .border({ width: 1, color: $r('app.color.card_border') })
    .margin({ bottom: 10 })
  }

  // ===================== 学生：放松度分析 =====================

  @Builder
  studentRelaxationCard() {
    Column() {
      Text('放松度分析')
        .fontSize(14).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .alignSelf(ItemAlign.Start).margin({ bottom: 10 })
      Row() {
        Text('冥想度水平').fontSize(12).fontColor($r('app.color.text_secondary'))
        Blank()
        Text(this.getMedLevelLabel())
          .fontSize(12).fontWeight(FontWeight.Medium)
          .fontColor(this.getMedLevelColor())
      }
      .width('100%').margin({ bottom: 8 })
      Row() {
        Row()
          .width(`${Math.min(this.getAvgMed(), 100)}%`)
          .height(8).backgroundColor('#6CBE8A').borderRadius(4)
      }
      .width('100%').height(8)
      .backgroundColor($r('app.color.background')).borderRadius(4)
      Text(this.getMedSuggestion())
        .fontSize(11).fontColor($r('app.color.text_secondary'))
        .margin({ top: 8 }).lineHeight(17)
    }
    .width('100%').padding(14)
    .backgroundColor($r('app.color.card_bg')).borderRadius(14)
    .border({ width: 1, color: $r('app.color.card_border') })
    .margin({ bottom: 10 })
  }

  // ===================== 老人：睡眠质量分析 =====================

  @Builder
  elderlySleepCard() {
    Column() {
      Text('睡眠质量分析')
        .fontSize(14).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .alignSelf(ItemAlign.Start).margin({ bottom: 10 })
      Row() {
        Text('δ/θ 睡眠指数').fontSize(12).fontColor($r('app.color.text_secondary'))
        Blank()
        Text(this.getSleepQualityLabel())
          .fontSize(12).fontWeight(FontWeight.Medium)
          .fontColor(this.getSleepQualityColor())
      }
      .width('100%').margin({ bottom: 8 })
      Row() {
        Row()
          .width(`${Math.min(this.getSleepQualityPercent(), 100)}%`)
          .height(8).backgroundColor('#74B9FF').borderRadius(4)
      }
      .width('100%').height(8)
      .backgroundColor($r('app.color.background')).borderRadius(4)
      Text(this.getSleepSuggestion())
        .fontSize(11).fontColor($r('app.color.text_secondary'))
        .margin({ top: 8 }).lineHeight(17)
    }
    .width('100%').padding(14)
    .backgroundColor($r('app.color.card_bg')).borderRadius(14)
    .border({ width: 1, color: $r('app.color.card_border') })
    .margin({ bottom: 10 })
  }

  // ===================== 老人：认知健康评估 =====================

  @Builder
  elderlyCognitiveCard() {
    Column() {
      Text('认知健康评估')
        .fontSize(14).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .alignSelf(ItemAlign.Start).margin({ bottom: 10 })
      Row() {
        Text('综合认知评分').fontSize(12).fontColor($r('app.color.text_secondary'))
        Blank()
        Text(this.getCognitiveScore().toFixed(0) + ' 分')
          .fontSize(12).fontWeight(FontWeight.Medium)
          .fontColor(this.getCognitiveScoreColor())
      }
      .width('100%').margin({ bottom: 8 })
      Row() {
        Row()
          .width(`${Math.min(this.getCognitiveScore(), 100)}%`)
          .height(8).backgroundColor('#A29BFE').borderRadius(4)
      }
      .width('100%').height(8)
      .backgroundColor($r('app.color.background')).borderRadius(4)
      Text(this.getCognitiveSuggestion())
        .fontSize(11).fontColor($r('app.color.text_secondary'))
        .margin({ top: 8 }).lineHeight(17)
    }
    .width('100%').padding(14)
    .backgroundColor($r('app.color.card_bg')).borderRadius(14)
    .border({ width: 1, color: $r('app.color.card_border') })
    .margin({ bottom: 10 })
  }

  // ===================== 植物人：α 阻断检测 =====================

  @Builder
  patientAlphaBlockingCard() {
    Column() {
      Text('α 波阻断检测')
        .fontSize(14).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .alignSelf(ItemAlign.Start).margin({ bottom: 10 })
      Text('α 波阻断（睁眼/外界刺激时 α 功率下降）是意识存在的重要标志。当外界给予声音、光线或触觉刺激时，脑电图中的 α 节律若出现明显衰减，提示大脑皮层对外界信息有感知和处理能力。')
        .fontSize(11).fontColor($r('app.color.text_secondary'))
        .lineHeight(17).margin({ bottom: 10 })
      this.reportRow('疑似 α 阻断事件', this.getAlphaBlockingCount().toString() + ' 次')
      this.reportRow('α 波变异系数', this.getAlphaCV().toFixed(2))
      this.reportRow('对外刺激反应评分', this.getStimulusResponseScore().toFixed(0) + ' / 100')
    }
    .width('100%').padding(14)
    .backgroundColor($r('app.color.card_bg')).borderRadius(14)
    .border({ width: 1, color: $r('app.color.card_border') })
    .margin({ bottom: 10 })
  }

  // ===================== 植物人：意识波动分析 =====================

  @Builder
  patientConsciousnessCard() {
    Column() {
      Text('意识波动记录')
        .fontSize(14).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .alignSelf(ItemAlign.Start).margin({ bottom: 10 })
      Text('持续监测 γ 和 β 频段的异常波动，这些波动可能与意识活动相关。同时追踪 δ/α 比值的变化趋势，比值下降往往意味着大脑对外界的响应能力有所提升。')
        .fontSize(11).fontColor($r('app.color.text_secondary'))
        .lineHeight(17).margin({ bottom: 10 })
      this.reportRow('γ 波异常波动', this.getConsciousnessFluctuationCount().toString() + ' 次')
      this.reportRow('δ/α 比值', this.getDeltaAlphaRatio().toFixed(2))
      this.reportRow('β 波活跃度', this.getBetaActivityLabel())
    }
    .width('100%').padding(14)
    .backgroundColor($r('app.color.card_bg')).borderRadius(14)
    .border({ width: 1, color: $r('app.color.card_border') })
    .margin({ bottom: 10 })
  }

  // -------------------------------------------------------
  //  脑波频段分布（共享，按类型切换描述）
  // -------------------------------------------------------

  @Builder
  reportBandCard() {
    Column() {
      Text('脑波频段分布')
        .fontSize(14).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .alignSelf(ItemAlign.Start).margin({ bottom: 10 })
      this.bandRow('δ Delta', this.getDeltaAvg(), '#A29BFE', this.getBandDesc(0))
      this.bandRow('θ Theta', this.getThetaAvg(), '#74B9FF', this.getBandDesc(1))
      this.bandRow('α Alpha', this.getAlphaAvg(), '#6CBE8A', this.getBandDesc(2))
      this.bandRow('β Beta', this.getBetaAvg(), '#F5A623', this.getBandDesc(3))
      this.bandRow('γ Gamma', this.getGammaAvg(), '#E87461', this.getBandDesc(4))
    }
    .width('100%').padding(14)
    .backgroundColor($r('app.color.card_bg')).borderRadius(14)
    .border({ width: 1, color: $r('app.color.card_border') })
    .margin({ bottom: 10 })
  }

  // -------------------------------------------------------
  //  综合建议（按类型）
  // -------------------------------------------------------

  @Builder
  reportSuggestionsCard() {
    Column() {
      Text('综合建议')
        .fontSize(14).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .alignSelf(ItemAlign.Start).margin({ bottom: 10 })
      ForEach(this.getTypedSuggestions(), (tip: string) => {
        Row() {
          Text('•').fontSize(12).fontColor('#4A90D9').fontWeight(FontWeight.Bold)
          Text(tip)
            .fontSize(12).fontColor($r('app.color.text_primary'))
            .margin({ left: 6 }).lineHeight(18)
        }
        .width('100%').margin({ bottom: 8 })
        .alignItems(VerticalAlign.Top)
      }, (tip: string) => tip)
    }
    .width('100%').padding(14)
    .backgroundColor($r('app.color.card_bg')).borderRadius(14)
    .border({ width: 1, color: $r('app.color.card_border') })
    .margin({ bottom: 10 })
  }

  // ================================================================
  //  共享 UI 组件
  // ================================================================

  @Builder
  reportRow(label: string, value: string) {
    Row() {
      Text(label).fontSize(12).fontColor($r('app.color.text_secondary'))
      Blank()
      Text(value).fontSize(12).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
    }
    .width('100%').padding({ top: 5, bottom: 5 })
  }

  @Builder
  bandRow(label: string, value: number, color: string, desc: string) {
    Row() {
      Text(label).fontSize(11).fontColor($r('app.color.text_secondary')).width(70)
      Row() {
        Row()
          .width(Math.min(value / 12, 60)).height(8)
          .backgroundColor(color).borderRadius(4)
      }
      .width(60).justifyContent(FlexAlign.Start)
      Text(value.toFixed(0))
        .fontSize(12).fontWeight(FontWeight.Bold)
        .fontColor(color).width(40).textAlign(TextAlign.End)
      Text(desc)
        .fontSize(10).fontColor($r('app.color.text_muted'))
        .margin({ left: 8 }).layoutWeight(1)
    }
    .width('100%').padding({ top: 5, bottom: 5 })
  }

  // ================================================================
  //  类型标签
  // ================================================================

  private getSubjectLabel(): string {
    switch (this.subjectType) {
      case SUBJ_STUDENT: return '学生报告';
      case SUBJ_ELDERLY: return '老人报告';
      case SUBJ_PATIENT: return '植物人报告';
      default: return '';
    }
  }

  private getSubjectColor(): string {
    switch (this.subjectType) {
      case SUBJ_STUDENT: return '#4A90D9';
      case SUBJ_ELDERLY: return '#6CBE8A';
      case SUBJ_PATIENT: return '#E87461';
      default: return '#999';
    }
  }

  private getBandDesc(idx: number): string {
    if (this.subjectType === SUBJ_STUDENT) {
      const descs = ['深度睡眠相关', '放松/浅睡', '放松专注', '活跃思考', '高度集中'];
      return descs[idx] || '';
    }
    if (this.subjectType === SUBJ_ELDERLY) {
      const descs = ['慢波睡眠/脑萎缩指标', '记忆巩固相关', '放松警戒', '认知活跃度', '信息整合能力'];
      return descs[idx] || '';
    }
    // 植物人
    const descs = ['脑功能基础节律', '意识水平参考', '感觉门控指标', '觉醒反应指标', '高级认知潜力'];
    return descs[idx] || '';
  }

  // ================================================================
  //  共享数据计算
  // ================================================================

  private getLatestData() {
    return store.getLatestData(store.getActiveDeviceId());
  }

  private getTrendData(): TrendPoint[] {
    return store.getTrendHistory(store.getActiveDeviceId());
  }

  private getTrendCount(): number {
    return this.getTrendData().length;
  }

  private getSignalLabel(): string {
    return store.getSignalTextFor(store.getActiveDeviceId());
  }

  private getAvgAtt(): number {
    const pts = this.getTrendData();
    if (pts.length === 0) return 0;
    let s = 0;
    for (let p of pts) s += p.att;
    return s / pts.length;
  }

  private getAvgMed(): number {
    const pts = this.getTrendData();
    if (pts.length === 0) return 0;
    let s = 0;
    for (let p of pts) s += p.med;
    return s / pts.length;
  }

  private getBandAvg(idx: number): number {
    const all = store.getBandHistory(store.getActiveDeviceId());
    const arr = all[idx];
    if (!arr || arr.length === 0) return 0;
    let s = 0;
    for (let v of arr) s += v;
    return s / arr.length;
  }

  private getDeltaAvg(): number { return this.getBandAvg(0); }
  private getThetaAvg(): number { return this.getBandAvg(1); }
  private getAlphaAvg(): number { return this.getBandAvg(2) + this.getBandAvg(3); }
  private getBetaAvg(): number { return this.getBandAvg(4) + this.getBandAvg(5); }
  private getGammaAvg(): number { return this.getBandAvg(6) + this.getBandAvg(7); }

  // ================================================================
  //  学生 — 标签/颜色/建议
  // ================================================================

  private getAttTrendLabel(): string {
    const avg = this.getAvgAtt();
    if (avg > 60) return '优秀 ↑';
    if (avg > 40) return '良好 →';
    if (avg > 20) return '偏低 ↓';
    return '需关注 ⚠';
  }

  private getAttTrendColor(): string {
    const avg = this.getAvgAtt();
    if (avg > 60) return '#6CBE8A';
    if (avg > 40) return '#4A90D9';
    if (avg > 20) return '#F5A623';
    return '#E74C3C';
  }

  private getMedLevelLabel(): string {
    const avg = this.getAvgMed();
    if (avg > 70) return '深度放松';
    if (avg > 45) return '适度放松';
    if (avg > 20) return '轻度紧张';
    return '紧张';
  }

  private getMedLevelColor(): string {
    const avg = this.getAvgMed();
    if (avg > 70) return '#9B59B6';
    if (avg > 45) return '#6CBE8A';
    if (avg > 20) return '#F5A623';
    return '#E74C3C';
  }

  private getAttSuggestion(): string {
    const avg = this.getAvgAtt();
    if (avg > 60) return '专注度处于较高水平，该学生在课堂上能够持续集中注意力，学习效率高。建议保持当前教学节奏。';
    if (avg > 40) return '专注度处于中等水平，基本能跟上课堂节奏。建议通过互动提问或小组讨论进一步提升参与度。';
    if (avg > 20) return '专注度偏低，可能存在注意力分散的情况。建议调整教学方式，增加趣味性内容，或安排短暂休息。';
    return '专注度极低，该学生可能需要个别关注。建议课后沟通了解原因，考虑是否存在学习障碍或情绪困扰。';
  }

  private getMedSuggestion(): string {
    const avg = this.getAvgMed();
    if (avg > 70) return '学生处于深度放松状态，适合进行创意写作、艺术表达或冥想类活动。若在讲课时出现此状态，可能表示困倦。';
    if (avg > 45) return '放松度适中，心态平稳，是理想的学习状态。既不过度紧张也不过分放松，有利于知识吸收。';
    if (avg > 20) return '存在轻度紧张，可能对课堂内容感到压力。建议适当放慢节奏，给予更多鼓励和正面反馈。';
    return '紧张程度较高，学生可能处于焦虑状态。建议课后单独交流，了解压力来源，提供心理支持。';
  }

  // ================================================================
  //  老人 — 专项指标
  // ================================================================

  private getDeltaThetaRatio(): number {
    const d = this.getDeltaAvg();
    const t = this.getThetaAvg();
    return t > 0 ? d / t : 0;
  }

  private getSleepQualityPercent(): number {
    const ratio = this.getDeltaThetaRatio();
    // δ/θ 在 1.2~1.8 正常，偏高=深睡多（好），偏低=浅睡多
    if (ratio >= 1.5) return 85 + Math.min((ratio - 1.5) * 40, 15);
    if (ratio >= 1.2) return 50 + (ratio - 1.2) * 116;
    if (ratio >= 0.9) return 20 + (ratio - 0.9) * 100;
    return Math.max(5, ratio * 22);
  }

  private getSleepQualityLabel(): string {
    const pct = this.getSleepQualityPercent();
    if (pct > 80) return '良好';
    if (pct > 60) return '一般';
    if (pct > 40) return '偏差';
    return '需关注';
  }

  private getSleepQualityColor(): string {
    const pct = this.getSleepQualityPercent();
    if (pct > 80) return '#6CBE8A';
    if (pct > 60) return '#74B9FF';
    if (pct > 40) return '#F5A623';
    return '#E74C3C';
  }

  private getSleepSuggestion(): string {
    const ratio = this.getDeltaThetaRatio();
    const pct = this.getSleepQualityPercent();
    if (pct > 80) return 'δ/θ 比值良好（' + ratio.toFixed(1) + '），深睡占比充足。当前睡眠质量较为理想，有助于记忆巩固和认知健康维护。';
    if (pct > 60) return 'δ/θ 比值偏低（' + ratio.toFixed(1) + '），深度睡眠占比不足。建议保持规律作息，睡前避免强光刺激和咖啡因摄入。';
    if (pct > 40) return 'δ/θ 比值明显偏低（' + ratio.toFixed(1) + '），深睡严重不足。长期深睡缺乏会增加认知衰退和痴呆风险，建议咨询睡眠专科医生。';
    return 'δ/θ 比值异常（' + ratio.toFixed(1) + '），睡眠结构可能存在紊乱。阿尔茨海默病早期常见 δ 波相对减少和 θ 波增加，建议进行专业睡眠监测和认知评估。';
  }

  private getCognitiveScore(): number {
    const alpha = this.getAlphaAvg();
    const beta = this.getBetaAvg();
    const gamma = this.getGammaAvg();
    const delta = this.getDeltaAvg();
    // 综合评分：α 活性 + β 活性 + γ 活性 — δ 过多扣分
    let score = 50;
    score += Math.min(alpha / 10, 20);
    score += Math.min(beta / 10, 15);
    score += Math.min(gamma / 6, 10);
    score -= Math.max((delta - 400) / 10, 0);
    return Math.max(5, Math.min(98, score));
  }

  private getCognitiveScoreColor(): string {
    const s = this.getCognitiveScore();
    if (s > 70) return '#6CBE8A';
    if (s > 50) return '#74B9FF';
    if (s > 30) return '#F5A623';
    return '#E74C3C';
  }

  private getCognitiveSuggestion(): string {
    const score = this.getCognitiveScore();
    const beta = this.getBetaAvg();
    const alpha = this.getAlphaAvg();
    if (score > 70) return '认知健康评分良好，α 和 β 频段活跃度正常，提示大脑皮层功能维持较好。建议保持社交活动、阅读和轻度体育锻炼。';
    if (score > 50) return '认知功能处于中等水平，β 频段活跃度略有下降。建议增加认知刺激活动，如下棋、学习新技能、适量户外运动。';
    if (score > 30) return '认知评分偏低，脑电活跃度明显下降。如排除设备佩戴问题，建议进行 MMSE 等专业认知量表评估，排查轻度认知障碍（MCI）风险。';
    return '认知评分显著偏低，δ 波占比过高，提示可能存在脑功能减退。强烈建议尽快就医，进行全面的神经心理评估和脑部影像学检查。';
  }

  private getEmotionStabilityLabel(): string {
    const med = this.getAvgMed();
    const ratio = this.getAlphaAvg() > 0 ? this.getBetaAvg() / this.getAlphaAvg() : 0;
    if (ratio < 0.8 && med > 45) return '稳定';
    if (ratio < 1.3 && med > 30) return '一般';
    if (ratio < 1.8 || med > 20) return '轻度波动';
    return '需关注';
  }

  // ================================================================
  //  植物人 — 专项指标
  // ================================================================

  private getAlphaBlockingCount(): number {
    const all = store.getBandHistory(store.getActiveDeviceId());
    const aL = all[2] || [];
    const aH = all[3] || [];
    // 统计 α 总功率的显著下降事件（下降 >30% 视为疑似阻断）
    let count = 0;
    let prevTotal = 0;
    for (let i = 0; i < Math.min(aL.length, aH.length); i++) {
      const total = aL[i] + aH[i];
      if (prevTotal > 0 && total < prevTotal * 0.70) {
        count++;
      }
      prevTotal = total;
    }
    return count;
  }

  private getAlphaCV(): number {
    const all = store.getBandHistory(store.getActiveDeviceId());
    const aL = all[2] || [];
    const aH = all[3] || [];
    const values: number[] = [];
    for (let i = 0; i < Math.min(aL.length, aH.length); i++) {
      values.push(aL[i] + aH[i]);
    }
    if (values.length === 0) return 0;
    let mean = 0;
    for (let v of values) mean += v;
    mean /= values.length;
    if (mean === 0) return 0;
    let variance = 0;
    for (let v of values) variance += (v - mean) * (v - mean);
    variance /= values.length;
    return Math.sqrt(variance) / mean;
  }

  private getStimulusResponseScore(): number {
    const blockCount = this.getAlphaBlockingCount();
    const cv = this.getAlphaCV();
    // α 变异系数越高 + 阻断事件越多 → 反应评分越高
    let score = 30;
    score += Math.min(blockCount * 5, 40);
    score += Math.min(cv * 80, 30);
    return Math.min(98, score);
  }

  private getConsciousnessFluctuationCount(): number {
    const all = store.getBandHistory(store.getActiveDeviceId());
    const gL = all[6] || [];
    const gM = all[7] || [];
    const bL = all[4] || [];
    const bH = all[5] || [];
    const len = Math.min(gL.length, gM.length, bL.length, bH.length);
    let count = 0;
    let prevG = 0;
    let prevB = 0;
    for (let i = 0; i < len; i++) {
      const g = gL[i] + gM[i];
      const b = bL[i] + bH[i];
      // γ 或 β 突增 >50% 视为意识波动
      if (prevG > 0 && (g > prevG * 1.5 || b > prevB * 1.5)) {
        count++;
      }
      prevG = g;
      prevB = b;
    }
    return count;
  }

  private getDeltaAlphaRatio(): number {
    const alpha = this.getAlphaAvg();
    return alpha > 0 ? this.getDeltaAvg() / alpha : 0;
  }

  private getBetaActivityLabel(): string {
    const beta = this.getBetaAvg();
    if (beta > 180) return '活跃';
    if (beta > 100) return '中等';
    if (beta > 50) return '偏低';
    return '极低';
  }

  // ================================================================
  //  各类型的综合建议
  // ================================================================

  private getTypedSuggestions(): string[] {
    switch (this.subjectType) {
      case SUBJ_STUDENT: return this.getStudentSuggestions();
      case SUBJ_ELDERLY: return this.getElderlySuggestions();
      case SUBJ_PATIENT: return this.getPatientSuggestions();
      default: return [];
    }
  }

  // ===================== 学生建议 =====================

  private getStudentSuggestions(): string[] {
    const tips: string[] = [];
    const data = this.getLatestData();
    const att = this.getAvgAtt();
    const med = this.getAvgMed();
    const alpha = this.getAlphaAvg();
    const beta = this.getBetaAvg();
    const delta = this.getDeltaAvg();
    const theta = this.getThetaAvg();
    const gamma = this.getGammaAvg();
    const ratio = alpha > 0 ? beta / alpha : 0;
    const sig = data?.sig ?? 200;

    if (sig >= 100) {
      tips.push('当前信号质量较差，电极可能接触不良。请先调整设备佩戴位置，确保前额干燥、电极贴紧皮肤，待信号恢复后再查看分析报告。');
      return tips;
    }

    if (att < 20) {
      tips.push('专注度严重偏低，该学生基本未参与课堂活动。建议课后单独沟通，排查是否存在学习障碍、情绪困扰或身体不适。');
      tips.push('短期应对：可尝试一对一辅导、降低任务难度、给予即时正面反馈来重建学习信心。');
    }

    if (delta > 530 && att < 40) {
      tips.push('δ 波（深度睡眠相关）偏高，结合低专注度，学生可能处于困倦或半睡眠状态。建议检查近期睡眠状况，可在课前安排短时身体活动帮助提神。');
    }

    if (theta > 350 && att < 40 && delta <= 530) {
      tips.push('θ 波（放松/浅睡相关）偏高伴随低专注，学生可能处于走神或做白日梦状态。建议通过随机提问、点名互动等方式将其注意力拉回课堂。');
    }

    if (beta > 230 && ratio > 1.6 && att < 40) {
      tips.push('β 波异常活跃伴随高 β/α 比值和低专注，呈现焦虑型分心特征。该学生可能因学业压力或课堂内容难度过高而感到紧张，建议降低任务难度、增加鼓励性反馈。');
    }

    if (att > 60 && med < 25) {
      tips.push('该学生处于"紧张专注"状态——虽然注意力集中，但放松度较低，长时间维持易导致疲劳和厌学。建议每 20 分钟安排短暂休息或轻松互动环节。');
    }

    if (att > 60 && med >= 25 && med <= 60) {
      tips.push('学生处于理想学习状态：专注度高且放松度适中，大脑高效运转。可适当布置拓展性任务，充分利用当前的良好状态。');
    }

    if (att > 60 && med > 60) {
      tips.push('该学生处于"放松专注"的心流状态，大脑既清醒又放松，非常适合进行深度阅读、创意写作或复杂问题求解。这是最理想的学习状态。');
    }

    if (att >= 20 && att < 40 && med > 65) {
      tips.push('专注度偏低但放松度偏高，学生可能处于放松过度/困倦状态。建议安排站立活动、小组讨论或动手实验来调动积极性。');
    }

    if (att >= 40 && att <= 60 && med < 25) {
      tips.push('专注度尚可但放松度偏低，学生可能带着紧张情绪在听课。建议给予更多正面反馈，营造轻松包容的课堂氛围。');
    }

    if (att >= 40 && att <= 60 && med >= 25 && med <= 65) {
      tips.push('专注度和放松度均处于中等水平，该学生基本能跟上教学节奏。可通过小组竞赛、趣味问答等方式进一步提升课堂参与度。');
    }

    if (att >= 20 && att < 40 && med >= 25 && med <= 65) {
      tips.push('专注度略低于正常水平，建议增加课堂互动频率，如每 10 分钟设置一次提问或讨论环节，帮助学生保持注意力。');
    }

    if (ratio > 1.8 && att >= 40) {
      tips.push('β/α 比值显著偏高，提示大脑处于高认知负荷状态。虽然专注度尚可，但长期维持此状态易导致精神疲劳。建议适当降低教学内容的密度和难度。');
    }

    if (ratio < 0.4 && med > 50 && att >= 40) {
      tips.push('α 波占主导，大脑处于放松且清醒的"待机就绪"状态，非常适合进行阅读理解和创意表达类学习活动。');
    }

    if (gamma > 250) {
      tips.push('γ 波（高度集中相关）异常活跃，通常出现在信息高度整合时。若伴随高专注度，说明学生正处于深度学习状态；若伴随低专注度，可能是神经紧张的表现，需综合判断。');
    }

    if (tips.length === 0) {
      tips.push('该学生整体状态良好，各项脑电指标均在正常范围内，课堂参与度和精神状态均衡。继续保持当前教学方式即可。');
      tips.push('建议每周至少查看一次趋势报告，关注专注度和放松度的长期变化曲线，及早发现潜在问题。');
    }

    return tips;
  }

  // ===================== 老人建议 =====================

  private getElderlySuggestions(): string[] {
    const tips: string[] = [];
    const data = this.getLatestData();
    const sig = data?.sig ?? 200;
    const sleepPct = this.getSleepQualityPercent();
    const cogScore = this.getCognitiveScore();
    const dtRatio = this.getDeltaThetaRatio();
    const daRatio = this.getDeltaAlphaRatio();
    const beta = this.getBetaAvg();
    const alpha = this.getAlphaAvg();
    const gamma = this.getGammaAvg();
    const baRatio = alpha > 0 ? beta / alpha : 0;

    if (sig >= 100) {
      tips.push('当前信号质量较差，电极可能接触不良。请确保前额皮肤干燥、电极贴紧、设备电量充足，待信号恢复后重新生成报告。');
      return tips;
    }

    // 睡眠质量
    if (sleepPct < 40) {
      tips.push('睡眠质量严重偏低：δ/θ 比值仅 ' + dtRatio.toFixed(1) + '，深度睡眠时长可能严重不足。长期深睡缺乏是阿尔茨海默病的重要风险因素之一，建议尽快预约睡眠监测（PSG）。');
      tips.push('日常改善：固定就寝和起床时间，卧室保持黑暗安静，睡前 1 小时避免使用电子屏幕，可尝试白噪音助眠。');
    } else if (sleepPct < 60) {
      tips.push('睡眠质量偏低：δ/θ 比值为 ' + dtRatio.toFixed(1) + '，深睡占比不足。建议增加日间运动量（散步 30 分钟以上），避免午睡过长，睡前可饮用温牛奶。');
    }

    // 认知健康
    if (cogScore < 30) {
      tips.push('认知评分严重偏低（' + cogScore.toFixed(0) + ' 分），δ 波占比过高而 β/γ 频段活跃度极低，提示可能存在显著脑功能减退。强烈建议到神经内科就诊，完成 MMSE 和 MoCA 量表筛查。');
    } else if (cogScore < 50) {
      tips.push('认知评分偏低（' + cogScore.toFixed(0) + ' 分），快速频段（β/γ）活跃度下降。建议进行专业认知评估，同时增加日常脑力活动：下棋、拼图、学习新技能等。');
    }

    // δ/α 比值 — 脑萎缩/退行指标
    if (daRatio > 3.5) {
      tips.push('δ/α 比值显著偏高（' + daRatio.toFixed(1) + '），是脑功能退行性变化的常见脑电特征。建议结合 MRI 影像学检查，排查脑白质病变或轻度认知障碍（MCI）。');
    }

    // β/α 比值 — 情绪认知平衡
    if (baRatio < 0.5 && beta < 80) {
      tips.push('β 波活跃度偏低，可能表现为反应迟钝、兴趣减退。建议增加社交互动和新鲜刺激，如参加社区活动、与家人多交流。');
    }

    if (baRatio > 1.8) {
      tips.push('β/α 比值偏高，可能提示焦虑或烦躁情绪。建议进行放松训练，如深呼吸、太极、聆听舒缓音乐。');
    }

    // γ 波 — 高级认知
    if (gamma < 25) {
      tips.push('γ 频段功率极低，该频段与注意力、工作记忆和感知整合密切相关。持续低迷需警惕认知网络的退行性改变。');
    }

    if (tips.length === 0) {
      tips.push('该老人的脑电各项指标均在正常范围内，认知活跃度和睡眠质量保持良好。建议继续维持现有的生活习惯和社交节奏。');
      tips.push('建议每 2-4 周复查一次，持续追踪 δ/θ 比值和认知评分的变化趋势。如发现短期内指标显著下滑，及时就医评估。');
      tips.push('日常保养：保持社交、适度运动（太极拳/散步）、均衡饮食（地中海饮食模式）、充足睡眠。');
    }

    return tips;
  }

  // ===================== 植物人建议 =====================

  private getPatientSuggestions(): string[] {
    const tips: string[] = [];
    const data = this.getLatestData();
    const sig = data?.sig ?? 200;
    const blockCount = this.getAlphaBlockingCount();
    const fluctCount = this.getConsciousnessFluctuationCount();
    const daRatio = this.getDeltaAlphaRatio();
    const beta = this.getBetaAvg();
    const gamma = this.getGammaAvg();
    const stimulusScore = this.getStimulusResponseScore();
    const alphaCV = this.getAlphaCV();

    if (sig >= 100) {
      tips.push('当前信号质量较差，电极可能接触不良。对于植物人监测，信号质量至关重要——请确保电极与头皮接触良好，排除环境电磁干扰后重新检测。');
      return tips;
    }

    // α 阻断事件 — 意识迹象的核心指标
    if (blockCount >= 15) {
      tips.push('检测到 ' + blockCount.toString() + ' 次疑似 α 阻断事件，这是一个积极信号——提示大脑皮层可能保留了对外界刺激的感知和反应能力。α 阻断是意识存在的重要标志，建议加强外界刺激的频率和多样性。');
      tips.push('刺激建议：交替使用听觉（呼唤姓名、熟悉的声音）、视觉（家人照片、光闪烁）、触觉（手部轻触、温度变化）刺激，每次刺激间隔 30 秒以上，观察 α 波变化。');
    } else if (blockCount >= 5) {
      tips.push('检测到 ' + blockCount.toString() + ' 次疑似 α 阻断事件，数量偏少但并非完全没有反应。建议增加刺激的种类和频率，记录哪些刺激类型能触发更明显的 α 波抑制反应。');
    } else {
      tips.push('α 阻断事件极少（' + blockCount.toString() + ' 次），目前脑电图对刺激的反应不显著。这并不一定意味着完全没有意识——部分患者可能存在"认知-运动分离"（CMD），即意识存在但无法表达。');
      tips.push('建议使用更复杂的刺激范式（如语义刺激——讲述熟悉的故事、播放有情感意义的音乐），并结合 fMRI 或 EEG-fMRI 进行更深入的意识检测。');
    }

    // δ/α 比值
    if (daRatio < 2.0 && alphaCV > 0.3) {
      tips.push('δ/α 比值较低（' + daRatio.toFixed(1) + '）且 α 波变异性较高，这是相对积极的脑电特征。α 波的动态变化往往与残存的脑网络可塑性相关。');
    } else if (daRatio > 4.0) {
      tips.push('δ/α 比值较高（' + daRatio.toFixed(1) + '），提示弥漫性慢波活动占主导。需结合临床评估排除代谢紊乱、感染或药物影响等可逆因素。');
    }

    // γ 波和 β 波
    if (gamma > 80 || beta > 150) {
      tips.push('检测到 γ 或 β 频段相对活跃，这是值得关注的信号——部分研究表明，植物人患者若保留一定的高频脑电活动，预后相对更好。建议持续监测这些频段的变化趋势。');
    }

    if (fluctCount > 20) {
      tips.push('γ/β 频段波动较为频繁（' + fluctCount.toString() + ' 次），可能与潜在的脑网络活动有关。建议记录波动发生的时间规律，看是否与护理操作、访客探视或昼夜节律相关。');
    }

    // 刺激反应评分
    if (stimulusScore > 60) {
      tips.push('对外刺激反应评分较高（' + stimulusScore.toFixed(0) + ' 分），提示脑电对刺激有一定响应能力。建议家属多进行床边交流，即使患者没有明显行为反应，大脑可能仍在处理部分信息。');
    }

    if (tips.length === 0) {
      tips.push('当前脑电数据显示慢波活动占主导，对外界刺激的反应不显著。建议采用多模态评估（EEG + 行为量表如 CRS-R + 影像学）综合判断意识水平。');
      tips.push('坚持定期监测：意识恢复是一个缓慢波动的过程，单次检测容易遗漏微弱的意识信号，建议每周至少进行 2-3 次 EEG 监测。');
      tips.push('家属参与：鼓励家人在监测期间与患者交流，提供情感刺激，同时记录 EEG 变化。熟悉的语音和故事是最有效的刺激之一。');
    }

    return tips;
  }
}
