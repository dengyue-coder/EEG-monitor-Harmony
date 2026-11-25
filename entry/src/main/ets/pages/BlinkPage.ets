import { EEGDataStore } from '../store/EEGDataStore';
import { BlinkDetector, getHealthInfo } from '../detectors/BlinkDetector';
import { drawBlinkChart } from '../renderers/BlinkRenderer';
import { getSignalText, formatTime } from '../utils/TimeUtils';
import { signalColor } from '../utils/ColorUtils';

const store = EEGDataStore.getInstance();

@Component
export struct BlinkPage {
  @State totalBlinks: number = 0;
  @State bpm: number = 0;
  @State lastMinuteBlinks: number = 0;
  @State healthStatus: string = '采集中...';
  @State healthColor: string = '#95A5A6';
  @State healthTip: string = '正在收集眨眼数据，请稍候...';
  @State eyeClosed: boolean = false;
  @State chartData: number[] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

  private detector: BlinkDetector = new BlinkDetector();
  private chartCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D();
  private chartReady: boolean = false;
  private blinkTimes: number[] = [];
  private eyeCloseTimer: number = 0;
  private lastHealthAt: number = 0;
  private unsubRaw: (() => void) | null = null;
  private lastFedRawCount: number = 0;

  aboutToAppear(): void {
    this.unsubRaw = store.subscribeRaw(() => {
      this.onTick();
    });
  }

  aboutToDisappear(): void {
    if (this.unsubRaw) {
      this.unsubRaw();
      this.unsubRaw = null;
    }
  }

  private onTick(): void {
    // 优先消费 rawHistory 里新增的原始波形样本（支持固件一帧携带多个采样）
    const history = store.rawHistory;
    if (this.lastFedRawCount > history.length) {
      this.lastFedRawCount = 0;
    }
    let blinked = false;
    for (let i = this.lastFedRawCount; i < history.length; i++) {
      const v = history[i];
      if (typeof v === 'number' && isFinite(v)) {
        if (this.detector.feed(v)) {
          blinked = true;
        }
      }
    }
    this.lastFedRawCount = history.length;
    // 兜底：若历史为空，直接喂最新 raw 单值（跳过 undefined/NaN）
    if (!blinked) {
      const raw = store.latestData.raw;
      if (typeof raw === 'number' && isFinite(raw)) {
        blinked = this.detector.feed(raw);
      }
    }
    const now = Date.now();

    if (blinked) {
      this.totalBlinks++;
      this.blinkTimes.push(now);
      this.eyeClosed = true;
      this.eyeCloseTimer = 4;
    }

    if (this.eyeCloseTimer > 0) {
      this.eyeCloseTimer--;
      if (this.eyeCloseTimer === 0) {
        this.eyeClosed = false;
      }
    }

    // 滑动窗口: 最近 60 秒内的眨眼数即为当前每分钟眨眼数
    const cutoff = now - 60000;
    while (this.blinkTimes.length > 0 && this.blinkTimes[0] < cutoff) {
      this.blinkTimes.shift();
    }
    this.bpm = this.blinkTimes.length;

    // 每 10 秒汇总一次健康状态, 随眨眼次数实时变化
    if (now - this.lastHealthAt >= 10000) {
      this.lastHealthAt = now;
      this.lastMinuteBlinks = this.bpm;
      const newChart = [...this.chartData];
      newChart.push(this.bpm);
      if (newChart.length > 10) newChart.shift();
      this.chartData = newChart;
      const info = getHealthInfo(this.bpm);
      this.healthStatus = info.status;
      this.healthColor = info.color;
      this.healthTip = info.tip;
    }

    if (this.chartReady) {
      drawBlinkChart(this.chartCtx, this.chartData, this.chartCtx.width, this.chartCtx.height);
    }
  }

  build() {
    Column() {
      this.titleBar()
      Scroll() {
        Column() {
          this.eyeCard()
          this.statsRow()
          this.trendChart()
          this.healthInfoCard()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
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

  @Builder
  titleBar() {
    Row() {
      Text('眨眼检测')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))

      Blank()

      Text(getSignalText(store.latestData.sig))
        .fontSize(11)
        .fontColor(signalColor(store.latestData.sig))
        .padding({ left: 8, right: 8, top: 2, bottom: 2 })
        .border({ width: 1, color: signalColor(store.latestData.sig), radius: 8 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 8 })
  }

  @Builder
  eyeCard() {
    Column() {
      Stack() {
        Circle().width(72).height(72)
          .fill($r('app.color.eye_bg'))
          .stroke($r('app.color.eye_border')).strokeWidth(2.5)
        Circle().width(24).height(24)
          .fill($r('app.color.eye_core'))
          .shadow({ radius: 10, color: $r('app.color.eye_glow'), offsetX: 0, offsetY: 0 })
      }
      .scale(this.eyeClosed ? { x: 1, y: 0.1 } : { x: 1, y: 1 })
      .animation({ duration: 80, curve: Curve.Sharp })

      Text('实时眨眼计数')
        .fontSize(12).fontColor($r('app.color.text_secondary')).margin({ top: 14, bottom: 4 })

      Text(this.totalBlinks.toString())
        .fontSize(48).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).fontFamily('monospace')

      if (this.eyeClosed) {
        Text('眨眼!').fontSize(12).fontColor($r('app.color.secondary')).margin({ top: 4 })
      } else {
        Text('').fontSize(12).height(4)
      }
    }
    .width('90%').padding({ top: 24, bottom: 20 })
    .backgroundColor($r('app.color.card_bg'))
    .border({ width: 1, color: $r('app.color.card_border'), radius: 18 })
    .margin({ top: 10 }).alignItems(HorizontalAlign.Center)
  }

  @Builder
  statsRow() {
    Row() {
      this.statItem('每分钟眨眼', this.bpm.toString(), '次/分', '#4BA8FF')
      this.statItem('健康状态', this.healthStatus, '', this.healthColor)
      this.statItem('最近1分钟', this.lastMinuteBlinks.toString(), '次', '#4EEFA3')
    }
    .width('90%')
    .justifyContent(FlexAlign.SpaceBetween)
    .margin({ top: 12 })
  }

  @Builder
  statItem(label: string, value: string, unit: string, color: string) {
    Column() {
      Text(label).fontSize(10).fontColor($r('app.color.text_tertiary')).margin({ bottom: 6 })
      Row() {
        Text(value).fontSize(22).fontWeight(FontWeight.Bold).fontColor(color)
        if (unit !== '') {
          Text(unit).fontSize(11).fontColor($r('app.color.text_secondary')).margin({ left: 2 })
        }
      }
    }
    .width('30%').padding({ top: 14, bottom: 14 })
    .backgroundColor($r('app.color.card_bg'))
    .border({ width: 1, color: $r('app.color.card_border'), radius: 16 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  trendChart() {
    Column() {
      Text('眨眼趋势（最近10分钟）')
        .fontSize(12).fontColor($r('app.color.text_tertiary')).margin({ bottom: 10 })
        .alignSelf(ItemAlign.Start)

      Canvas(this.chartCtx)
        .width('100%').height(110)
        .backgroundColor($r('app.color.canvas_fill')).borderRadius(10)
        .onReady(() => {
          this.chartReady = true;
          drawBlinkChart(this.chartCtx, this.chartData, this.chartCtx.width, this.chartCtx.height);
        })
    }
    .width('90%').padding(14)
    .backgroundColor($r('app.color.card_bg'))
    .border({ width: 1, color: $r('app.color.card_border'), radius: 18 })
    .margin({ top: 12 })
  }

  @Builder
  healthInfoCard() {
    Column() {
      Text('健康眨眼小知识')
        .fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        .margin({ bottom: 12 }).alignSelf(ItemAlign.Start)

      this.knowledgeItem('#4BA8FF',
        '正常成年人每分钟眨眼 15~20 次，每次持续约 100~400 毫秒。')
      this.knowledgeItem('#FFB84D',
        '看屏幕时眨眼频率骤降至 5~7 次/分钟，是"电脑视觉综合征"的主因之一。')
      this.knowledgeItem('#4EEFA3',
        '眨眼能分泌泪液润滑眼球、清除灰尘，并在瞬间让大脑获得短暂休息。')
      this.knowledgeItem('#A878FF',
        '遵循"20-20-20 法则"：每工作 20 分钟，看 6 米远的物体 20 秒。')
      this.knowledgeItem('#FF6675',
        '若持续 < 10 次/分钟，请立即休息；> 30 次/分钟持续不退，建议就医。')
    }
    .width('90%').padding(16)
    .backgroundColor($r('app.color.card_bg'))
    .border({ width: 1, color: $r('app.color.card_border'), radius: 18 })
    .margin({ top: 12, bottom: 16 })
  }

  @Builder
  knowledgeItem(color: string, text: string) {
    Row() {
      Circle().width(6).height(6).fill(color).margin({ right: 10, top: 5 })
      Text(text).fontSize(12).fontColor($r('app.color.text_secondary')).lineHeight(18).layoutWeight(1)
    }
    .width('100%').alignItems(VerticalAlign.Top).margin({ bottom: 8 })
  }
}
