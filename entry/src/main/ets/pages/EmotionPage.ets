import { EEGDataStore } from '../store/EEGDataStore';
import { EmotionKind, getEmotionDisplay } from '../utils/EEGConstants';
import { EmotionDetector, VAPoint, BandItem } from '../detectors/EmotionDetector';
import { drawVA, drawTL, drawEmotionRadar } from '../renderers/EmotionRenderer';
import { MockDataService } from '../service/MockDataService';
import { router } from '@kit.ArkUI';

const store = EEGDataStore.getInstance();
const mockService = MockDataService.getInstance();

const BREATH_PHASE_LABELS: string[] = ['吸气', '屏息', '呼气', '屏息'];
const BREATH_TICKS: number = 80;

@Component
export struct EmotionPage {
  @Prop readOnly: boolean = false;
  @State showSoothing: boolean = false;

  // ===== 情绪检测状态 =====
  @State emo: EmotionKind = EmotionKind.NEUTRAL;
  @State v: number = 50;
  @State a: number = 50;
  @State bandItems: BandItem[] = [];
  @State hasData: boolean = false;
  @State att: number = 0;
  @State bandVals: number[] = [520,380,240,180,120,80,60,40];
  @State liveTick: number = 0;
  @StorageProp('dark_mode_on') darkModeOn: number = 0;
  private detector: EmotionDetector = new EmotionDetector();
  private vaCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D();
  private radarCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D();
  private tlCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D();
  private vaOk: boolean = false;
  private radarOk: boolean = false;
  private tlOk: boolean = false;
  private trail: VAPoint[] = [];
  private tline: EmotionKind[] = [];
  private tick: number = 0;
  private lastUiAt: number = 0;
  private unsub: (() => void) | null = null;
  private pollTimer: number = -1;

  // ===== 情绪舒缓状态 =====
  @State breathPhase: number = 0;
  @State breathSecLeft: number = 4;
  @State breathAnim: number = 0;
  @State breathCycleCount: number = 0;
  @State soothMeditation: number = 0;
  private breathTimer: number = -1;
  private breathPhaseTick: number = 0;

  aboutToAppear(): void {
    this.readBandData();
    this.unsub = store.subscribe(() => {
      this.soothMeditation = store.latestData.med;
      this.loop();
    });
    this.pollTimer = setInterval(() => { this.readBandData(); }, 200);
    this.startBreathTimer();
  }

  aboutToDisappear(): void {
    if (this.unsub) { this.unsub(); this.unsub = null; }
    if (this.pollTimer >= 0) { clearInterval(this.pollTimer); this.pollTimer = -1; }
    if (this.breathTimer >= 0) { clearInterval(this.breathTimer); this.breathTimer = -1; }
  }

  private readBandData(): void {
    this.liveTick++;
    this.soothMeditation = store.latestData.med;
    console.info('[Emotion] med=' + store.latestData.med + ' sooth=' + this.soothMeditation + ' dev=' + store.getDeviceIds().length);
    const vn = this.v / 100; const an = this.a / 100;
    this.bandVals = [
      Math.round(450 + an * 80 + Math.sin(this.liveTick * 0.3) * 30),
      Math.round(350 + an * 60 + Math.cos(this.liveTick * 0.5) * 25),
      Math.round(200 + vn * 80 + Math.sin(this.liveTick * 0.4) * 20),
      Math.round(160 + vn * 60 + Math.cos(this.liveTick * 0.35) * 18),
      Math.round(100 + an * 80 + Math.sin(this.liveTick * 0.6) * 15),
      Math.round(65 + an * 50 + Math.cos(this.liveTick * 0.45) * 12),
      Math.round(45 + an * 40 + Math.sin(this.liveTick * 0.7) * 10),
      Math.round(30 + an * 25 + Math.cos(this.liveTick * 0.55) * 8),
    ];
  }

  private loop(): void {
    this.tick++;
    this.detector.feed();

    // 按 200ms 节流刷新 UI: 1Hz 数据下每帧都刷, 50Hz 模拟数据下每秒最多 5 次
    const now = Date.now();
    if (now - this.lastUiAt < 200) return;
    this.lastUiAt = now;

    // 实时刷新情绪标签与 VA, 保证跟随小程序发送的数据
    this.emo = this.detector.classify();
    this.v = this.detector.v; this.a = this.detector.a;
    this.att = store.latestData.att;
    this.trail.push(new VAPoint(this.v, this.a));
    if (this.trail.length > 60) this.trail.shift();
    this.tline.push(this.emo);
    if (this.tline.length > 60) this.tline.shift();
    this.bandItems = this.detector.bands();
    if (!this.hasData && this.trail.length >= 2) this.hasData = true;
    if (this.vaOk) this.drawVACanvas();
    if (this.radarOk) this.drawRadarCanvas();
    if (this.tlOk) this.drawTLCanvas();
  }

  private drawVACanvas(): void { drawVA(this.vaCtx, this.trail, this.v, this.a, this.emo, this.vaCtx.width, this.vaCtx.height); }
  private drawRadarCanvas(): void {
    const vals: number[] = this.hasData ? [
      store.latestData.d, store.latestData.t, store.latestData.aL + store.latestData.aH,
      store.latestData.bL + store.latestData.bH, store.latestData.gL + store.latestData.gM, store.latestData.att
    ] : [0, 0, 0, 0, 0, 0];
    drawEmotionRadar(this.radarCtx, vals, this.att, this.radarCtx.width, this.radarCtx.height,
      this.darkModeOn === 1 ? '#0A1020' : '#FFFFFF');
  }
  private drawTLCanvas(): void { drawTL(this.tlCtx, this.tline, this.tlCtx.width, this.tlCtx.height); }

  // ===== ui2 情绪图片 =====
  private getEmotionImage(): Resource {
    switch (this.emo) {
      case EmotionKind.HAPPY: return $r('app.media.emotion_happy');
      case EmotionKind.RELAXED: return $r('app.media.emotion_relaxed');
      case EmotionKind.FOCUSED: return $r('app.media.emotion_focused');
      case EmotionKind.EXCITED: return $r('app.media.emotion_excited');
      case EmotionKind.ANXIOUS: return $r('app.media.emotion_anxious');
      case EmotionKind.SAD: return $r('app.media.emotion_sad');
      case EmotionKind.ANGRY: return $r('app.media.emotion_angry');
      case EmotionKind.TIRED: return $r('app.media.emotion_tired');
      default: return $r('app.media.emotion_neutral');
    }
  }
  private getStability(): number { return Math.round(100 - Math.abs(this.v - 50) * 1.2 - Math.abs(this.a - 50) * 0.8); }
  private getStressLabel(): string { if (this.a > 65) return '偏高'; if (this.a < 30) return '低'; return '正常'; }
  private getStressColor(): string { if (this.a > 65) return '#FF6675'; if (this.a < 30) return '#8899AA'; return '#4EEFA3'; }

  build() {
    if (this.showSoothing) {
      this.emotionSoothingView()
    } else {
      this.emotionDetectView()
    }
  }

  // ==================== 情绪检测（ui2 原版） ====================

  @Builder
  emotionDetectView() {
    Scroll() {
      Column() {
        // 顶栏：标题 + 舒缓入口 + 算法原理
        Row() {
          Text('AI 情绪分析')
            .fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          Blank()
          // 舒缓入口按钮
          if (!this.readOnly) {
            Button('🌿 情绪舒缓')
              .fontSize(10).fontColor($r('app.color.primary')).fontWeight(FontWeight.Medium)
              .height(34).padding({ left: 12, right: 12 })
              .backgroundColor($r('app.color.primary_light')).borderRadius(12)
              .margin({ right: 8 })
              .onClick(() => { this.showSoothing = true; })
          }
          // 算法原理
          Text('算法原理 〉')
            .fontSize(11).fontColor($r('app.color.text_emotion_purple')).fontWeight(FontWeight.Medium)
            .padding({ left: 12, right: 12, top: 9, bottom: 9 })
            .backgroundColor($r('app.color.accent_light')).borderRadius(12)
            .onClick(() => { router.pushUrl({ url: 'pages/EmotionInfoPage' }); })
        }
        .width('92%').padding({ top: 10, bottom: 6 })

        // 已连接状态指示
        if (store.connected) {
          Row() {
            Circle().width(5).height(5).fill($r('app.color.status_online'))
            Text('设备已连接 · 实时监测中').fontSize(10).fontColor($r('app.color.text_tertiary')).margin({ left: 5 })
          }
          .width('92%').padding({ bottom: 4 })
        }

        this.brainHero()
        this.brainActivityChart()
        this.metricsRow()
        this.aiReportCard()
        this.vaCard()
        this.radarCard()
        this.tlCard()
      }
      .width('100%').alignItems(HorizontalAlign.Center).padding({ top: 4, bottom: 24 })
    }
    .width('100%').height('100%')
    .linearGradient({
      direction: GradientDirection.Bottom,
      colors: [[$r('app.color.page_bg_gradient_top'), 0.0], [$r('app.color.page_bg_gradient_mid'), 0.5], [$r('app.color.page_bg_gradient_bottom'), 1.0]]
    })
    .scrollBar(BarState.Off)
  }

  // ---- brainHero ----
  @Builder brainHero() {
    Stack() {
      Image($r('app.media.bg_emotion')).width('100%').height(240).objectFit(ImageFit.Cover).borderRadius(24)
      Column().width('100%').height(240).backgroundColor('rgba(6,14,31,0.4)').borderRadius(24)
      Stack() {
        Image(this.getEmotionImage()).width(100).height(100).objectFit(ImageFit.Cover).borderRadius(50)
        Circle({ width: 110, height: 110 }).fill('#00000000').stroke(getEmotionDisplay(this.emo).color + '30').strokeWidth(2)
          .shadow({ radius: 20, color: getEmotionDisplay(this.emo).color + '30', offsetX: 0, offsetY: 0 })
        Circle({ width: 140, height: 140 }).fill('#00000000').stroke(getEmotionDisplay(this.emo).color + '15').strokeWidth(1).strokeDashArray([3, 15])
      }.position({ x: '26%', y: '45%' }).translate({ x: '-70vp', y: '-70vp' })
      Row() { Text('AI · 情绪感知').fontSize(9).fontColor($r('app.color.text_emotion_purple')).padding({ left: 8, right: 8, top: 2, bottom: 2 }).backgroundColor($r('app.color.accent_light')).borderRadius(6) }.position({ x: '50%', y: 18 })
      Column() {
        Text(getEmotionDisplay(this.emo).name).fontSize(26).fontWeight(FontWeight.Bold).fontColor(getEmotionDisplay(this.emo).color)
        Text(getEmotionDisplay(this.emo).desc).fontSize(12).fontColor($r('app.color.text_secondary')).margin({ top: 4 })
        Row() { Circle().width(5).height(5).fill($r('app.color.status_online')); Text('AI 置信度 ' + Math.round(this.att).toString() + '%').fontSize(11).fontColor($r('app.color.text_tertiary')).margin({ left: 5 }) }.margin({ top: 8 })
      }.alignItems(HorizontalAlign.Start).position({ x: '52%', y: '45%' }).translate({ x: 0, y: '-50vp' }).width('44%')
      Row() {
        this.heroPill('V', this.v.toString(), '#4EEFA3'); this.heroPill('A', this.a.toString(), '#FFB84D')
        this.heroPill('稳定', this.getStability().toString(), '#4BA8FF'); this.heroPill('压力', this.getStressLabel(), this.getStressColor())
      }.width('92%').justifyContent(FlexAlign.SpaceEvenly).position({ x: '50%', y: '82%' }).translate({ x: '-46%' })
    }
    .width('92%').height(240).clip(true).borderRadius(24).border({ width: 1, color: $r('app.color.card_border') }).margin({ bottom: 12 })
  }

  @Builder heroPill(label: string, value: string, color: string) {
    Column() {
      Text(value).fontSize(14).fontWeight(FontWeight.Bold).fontColor(color).fontFamily('monospace')
      Text(label).fontSize(8).fontColor($r('app.color.text_tertiary'))
    }.alignItems(HorizontalAlign.Center).padding({ left: 8, right: 8, top: 4, bottom: 4 }).backgroundColor('rgba(255,255,255,0.03)').border({ width: 0.5, color: color + '18', radius: 8 })
  }

  // ---- brainActivityChart ----
  @Builder brainActivityChart() {
    Column() {
      Row() { Text('Brain Activity').fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')); Blank(); Text('实时').fontSize(9).fontColor($r('app.color.text_emotion_purple')).padding({ left: 6, right: 6, top: 1, bottom: 1 }).backgroundColor($r('app.color.accent_light')).borderRadius(6) }
        .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 10 })
      Row() {
        this.bandChip('δ', this.bandVals[0], '#4EEFA3'); this.bandChip('θ', this.bandVals[1], '#4BA8FF')
        this.bandChip('α', this.bandVals[2] + this.bandVals[3], '#A878FF'); this.bandChip('β', this.bandVals[4] + this.bandVals[5], '#FFB84D')
        this.bandChip('γ', this.bandVals[6] + this.bandVals[7], '#FF6675')
      }.width('100%').padding({ left: 12, right: 12, bottom: 14 }).justifyContent(FlexAlign.SpaceEvenly)
    }
    .width('92%').linearGradient({ angle: 145, colors: [['rgba(255,255,255,0.05)', 0.0], ['rgba(255,255,255,0.0)', 0.35]] })
    .backgroundColor($r('app.color.card_bg')).borderRadius(22).border({ width: 1, color: $r('app.color.card_border') }).margin({ bottom: 12 })
  }

  @Builder bandChip(name: string, value: number, color: string) {
    Column() {
      Text(name).fontSize(11).fontWeight(FontWeight.Bold).fontColor(color).fontFamily('monospace')
      Row().width(20).height(2).backgroundColor(color + '30').borderRadius(1).margin({ top: 2, bottom: 2 })
      Text(value.toFixed(0)).fontSize(10).fontColor($r('app.color.text_secondary'))
    }.alignItems(HorizontalAlign.Center)
  }

  // ---- eegMonitorCard ----
  @Builder eegMonitorCard() {
    Column() {
      Row() { Text('EEG Monitor').fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')) }.width('100%').padding({ left: 16, right: 16, top: 14, bottom: 8 })
      this.barLine('Delta  δ ', this.bandVals[0], '#4EEFA3'); this.barLine('Theta  θ ', this.bandVals[1], '#4BA8FF')
      this.barLine('Low α  ', this.bandVals[2], '#A878FF'); this.barLine('High α ', this.bandVals[3], '#C4B5FD')
      this.barLine('Low β  ', this.bandVals[4], '#FFB84D'); this.barLine('High β ', this.bandVals[5], '#F59E0B')
      this.barLine('Low γ  ', this.bandVals[6], '#FF6675'); this.barLine('Mid γ  ', this.bandVals[7], '#EF4444')
    }
    .width('92%').padding({ bottom: 12 }).linearGradient({ angle: 145, colors: [['rgba(255,255,255,0.05)', 0.0], ['rgba(255,255,255,0.0)', 0.35]] })
    .backgroundColor($r('app.color.card_bg')).borderRadius(22).border({ width: 1, color: $r('app.color.card_border') }).margin({ bottom: 12 })
  }

  @Builder barLine(label: string, value: number, color: string) {
    Row() {
      Text(label + value.toFixed(0)).fontSize(10).fontColor(color).fontFamily('monospace').width(100)
      Row() { Row().width(value * 100 / 600 + '%').height(6).backgroundColor(color).borderRadius(3) }
        .layoutWeight(1).height(6).backgroundColor('rgba(255,255,255,0.04)').borderRadius(3)
    }.width('100%').padding({ left: 16, right: 16, top: 5, bottom: 5 })
  }

  // ---- metricsRow ----
  @Builder metricsRow() {
    Row() {
      this.metricRing('情绪指数', Math.round((this.v + this.a) / 2), getEmotionDisplay(this.emo).color)
      Column().width(1).height(44).backgroundColor($r('app.color.card_border'))
      this.metricRing('稳定度', this.getStability(), '#4BA8FF')
      Column().width(1).height(44).backgroundColor($r('app.color.card_border'))
      this.metricCell('压力态', this.getStressLabel(), this.getStressColor())
    }
    .width('92%').padding({ top: 14, bottom: 14 }).linearGradient({ angle: 145, colors: [['rgba(255,255,255,0.05)', 0.0], ['rgba(255,255,255,0.0)', 0.35]] })
    .backgroundColor($r('app.color.card_bg')).borderRadius(22).border({ width: 1, color: $r('app.color.card_border') }).justifyContent(FlexAlign.SpaceEvenly).margin({ bottom: 12 })
  }

  @Builder metricRing(label: string, value: number, color: string) {
    Column() {
      Stack() {
        Circle({ width: 40, height: 40 }).fill('#00000000').stroke($r('app.color.card_border')).strokeWidth(4)
        Circle({ width: 40, height: 40 }).fill('#00000000').stroke(color).strokeWidth(4).strokeDashArray([Math.PI * 32 * value / 100, Math.PI * 32]).strokeLineCap(LineCapStyle.Round)
        Text(value.toString()).fontSize(12).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).fontFamily('monospace')
      }
      Text(label).fontSize(9).fontColor($r('app.color.text_tertiary')).margin({ top: 6 })
    }.alignItems(HorizontalAlign.Center).layoutWeight(1)
  }

  @Builder metricCell(label: string, value: string, color: string) {
    Column() {
      Row() { Circle().width(6).height(6).fill(color); Text(value).fontSize(15).fontWeight(FontWeight.Bold).fontColor(color).margin({ left: 5 }) }
      Text(label).fontSize(9).fontColor($r('app.color.text_tertiary')).margin({ top: 6 })
    }.alignItems(HorizontalAlign.Center).layoutWeight(1)
  }

  // ---- aiReportCard ----
  @Builder aiReportCard() {
    Column() {
      Row() {
        Text('AI 情绪报告').fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Blank()
        Row() { Circle().width(4).height(4).fill($r('app.color.status_online')); Text('实时生成').fontSize(9).fontColor($r('app.color.text_emotion_purple')).margin({ left: 3 }) }
        .padding({ left: 6, right: 6, top: 1, bottom: 1 }).backgroundColor($r('app.color.accent_light')).borderRadius(6)
      }.width('100%').padding({ left: 16, right: 16, top: 14, bottom: 10 })
      Column() {
        this.reportRow('01', '检测结果', getEmotionDisplay(this.emo).name + ' · ' + getEmotionDisplay(this.emo).desc, getEmotionDisplay(this.emo).color)
        this.reportRow('02', '脑波特征', getEmotionDisplay(this.emo).encourage, '#4BA8FF')
        this.reportRow('03', 'AI 建议', getEmotionDisplay(this.emo).blessing, '#FFB84D')
      }.width('100%').padding({ left: 12, right: 12, bottom: 12 })
    }
    .width('92%').linearGradient({ angle: 145, colors: [['rgba(255,255,255,0.05)', 0.0], ['rgba(255,255,255,0.0)', 0.35]] })
    .backgroundColor($r('app.color.card_bg')).borderRadius(22).border({ width: 1, color: $r('app.color.card_border') }).margin({ bottom: 12 })
  }

  @Builder reportRow(num: string, label: string, content: string, accent: string) {
    Row() {
      Text(num).fontSize(10).fontWeight(FontWeight.Bold).fontColor(accent).fontFamily('monospace').width(18)
      Column() {
        Text(label).fontSize(10).fontColor($r('app.color.text_tertiary')).fontWeight(FontWeight.Medium)
        Text(content).fontSize(12).fontColor($r('app.color.text_primary')).lineHeight(18).margin({ top: 2 })
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
    }.width('100%').padding({ top: 10, bottom: 10 }).border({ width: { bottom: 0.5 }, color: $r('app.color.card_border') })
  }

  // ---- vaCard ----
  @Builder vaCard() {
    Column() {
      Row() {
        Text('情绪空间定位').fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Blank(); Text(`V ${this.v} · A ${this.a}`).fontSize(11).fontColor($r('app.color.text_secondary')).fontFamily('monospace')
      }.width('100%').padding({ left: 16, right: 16, top: 14, bottom: 2 })
      Text('Russell 环状模型 — 当前情绪在二维效价-唤醒空间中的位置').fontSize(10).fontColor($r('app.color.text_tertiary')).width('100%').padding({ left: 16, right: 16, bottom: 6 })
      if (!this.hasData) { Column() { Text('数据采集中...').fontSize(14).fontColor($r('app.color.text_secondary')) }.width('100%').height(260).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center) }
      else { Canvas(this.vaCtx).width('100%').height(260).onReady(() => { this.vaOk = true; this.drawVACanvas(); }) }
    }
    .width('92%').linearGradient({ angle: 145, colors: [['rgba(255,255,255,0.05)', 0.0], ['rgba(255,255,255,0.0)', 0.35]] })
    .backgroundColor($r('app.color.card_bg')).borderRadius(22).border({ width: 1, color: $r('app.color.card_border') }).margin({ bottom: 12 })
  }

  // ---- radarCard ----
  @Builder radarCard() {
    Column() {
      Row() {
        Text('脑波频段分析').fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Text('实时').fontSize(10).fontColor($r('app.color.text_emotion_purple')).backgroundColor($r('app.color.accent_light')).padding({ left: 8, right: 8, top: 2, bottom: 2 }).borderRadius(8).margin({ left: 8 })
      }.width('100%').padding({ left: 16, right: 16, top: 14, bottom: 2 })
      Text('六维脑波频段实时监测 · Delta Theta Alpha Beta Gamma + 专注度').fontSize(10).fontColor($r('app.color.text_tertiary')).width('100%').padding({ left: 16, right: 16, bottom: 6 })
      Stack() {
        if (this.darkModeOn === 1) { Column().width('100%').height(240).linearGradient({ direction: GradientDirection.Bottom, colors: [['#060E1F', 0.0], ['#0A1530', 0.6], ['#0D1A35', 1.0]] }).borderRadius(16) }
        Canvas(this.radarCtx).width('100%').height(240).backgroundColor('#00000000').onReady(() => { this.radarOk = true; this.drawRadarCanvas(); })
      }
    }
    .width('92%').backgroundColor($r('app.color.card_bg')).borderRadius(22).border({ width: 1, color: $r('app.color.card_border') }).clip(true).margin({ bottom: 12 })
  }

  // ---- tlCard ----
  @Builder tlCard() {
    Column() {
      Row() {
        Text('动态情绪轨迹').fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Text('30s').fontSize(10).fontColor($r('app.color.text_tertiary')).padding({ left: 6, right: 6, top: 1, bottom: 1 }).backgroundColor($r('app.color.card_bg_strong')).borderRadius(6).margin({ left: 6 })
      }.width('100%').padding({ left: 16, right: 16, top: 14, bottom: 4 })
      if (!this.hasData) { Column() { Text('等待数据...').fontSize(12).fontColor($r('app.color.text_secondary')) }.width('100%').height(60).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center) }
      else {
        Canvas(this.tlCtx).width('100%').height(80).onReady(() => { this.tlOk = true; this.drawTLCanvas(); })
        Row() {
          Row() { Circle().width(6).height(6).fill('#FF9500'); Text('开心').fontSize(9).fontColor($r('app.color.text_secondary')).margin({ left: 2 }) }.margin({ right: 6 })
          Row() { Circle().width(6).height(6).fill('#4EEFA3'); Text('放松').fontSize(9).fontColor($r('app.color.text_secondary')).margin({ left: 2 }) }.margin({ right: 6 })
          Row() { Circle().width(6).height(6).fill('#4BA8FF'); Text('专注').fontSize(9).fontColor($r('app.color.text_secondary')).margin({ left: 2 }) }.margin({ right: 6 })
          Row() { Circle().width(6).height(6).fill('#FFB84D'); Text('焦虑').fontSize(9).fontColor($r('app.color.text_secondary')).margin({ left: 2 }) }.margin({ right: 6 })
          Row() { Circle().width(6).height(6).fill('#7B8FA1'); Text('低落').fontSize(9).fontColor($r('app.color.text_secondary')).margin({ left: 2 }) }.margin({ right: 6 })
          Row() { Circle().width(6).height(6).fill('#95A5A6'); Text('平静').fontSize(9).fontColor($r('app.color.text_secondary')).margin({ left: 2 }) }
        }.width('100%').padding({ left: 10, right: 10, top: 2, bottom: 10 }).justifyContent(FlexAlign.Center)
      }
    }
    .width('92%').linearGradient({ angle: 145, colors: [['rgba(255,255,255,0.05)', 0.0], ['rgba(255,255,255,0.0)', 0.35]] })
    .backgroundColor($r('app.color.card_bg')).borderRadius(22).border({ width: 1, color: $r('app.color.card_border') }).margin({ bottom: 12 })
  }

  // ==================== 情绪舒缓 ====================

  @Builder
  emotionSoothingView() {
    Scroll() {
      Column() {
        // 返回按钮
        Row() {
          Button('← 返回情绪检测')
            .fontSize(12).fontColor($r('app.color.primary')).fontWeight(FontWeight.Medium)
            .backgroundColor($r('app.color.primary_light')).borderRadius(10)
            .height(32).padding({ left: 14, right: 14 })
            .onClick(() => { this.showSoothing = false; })
          Blank()
        }.width('92%').padding({ top: 12, bottom: 4 })

        this.breathCard()
        this.meditationCard()
        this.soothingTipsCard()
      }
      .width('100%').alignItems(HorizontalAlign.Center).padding({ top: 4, bottom: 24 })
    }
    .width('100%').height('100%')
    .linearGradient({
      direction: GradientDirection.Bottom,
      colors: [[$r('app.color.page_bg_gradient_top'), 0.0], [$r('app.color.page_bg_gradient_mid'), 0.5], [$r('app.color.page_bg_gradient_bottom'), 1.0]]
    })
    .scrollBar(BarState.Off)
  }

  @Builder breathCard() {
    Column() {
      Text('盒式呼吸法').fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).margin({ top: 16, bottom: 4 })
      Text('4-4-4-4 · 海豹突击队训练专用呼吸法').fontSize(11).fontColor($r('app.color.text_muted')).margin({ bottom: 20 })
      Stack() {
        Circle().width(200).height(200).fill($r('app.color.background_secondary')).stroke('#E8E8E8').strokeWidth(3)
        Circle().width(100 + 80 * this.breathAnim).height(100 + 80 * this.breathAnim).fill(this.getBreathColor()).opacity(0.35 + 0.3 * this.breathAnim)
        Circle().width(70 + 50 * this.breathAnim).height(70 + 50 * this.breathAnim).fill(this.getBreathColor()).opacity(0.6 + 0.3 * this.breathAnim)
        Column() {
          Text(BREATH_PHASE_LABELS[this.breathPhase]).fontSize(28).fontWeight(FontWeight.Bold).fontColor(this.getBreathColor())
          Text(this.breathSecLeft.toString()).fontSize(52).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).fontFamily('monospace').margin({ top: 4, bottom: 4 })
          Text('已完成 ' + this.breathCycleCount + ' 轮').fontSize(11).fontColor($r('app.color.text_secondary'))
        }
      }.width(200).height(200).margin({ bottom: 24 })
      Row() { Row().width(`${this.breathAnim * 100}%`).height(4).backgroundColor(this.getBreathColor()).borderRadius(2) }
        .width('80%').height(4).backgroundColor($r('app.color.background_secondary')).borderRadius(2).margin({ bottom: 20 })
      Row() {
        this.phaseHint('吸气 4s', 0, '用鼻子缓缓吸入'); this.phaseHint('屏息 4s', 1, '保持气息不动')
        this.phaseHint('呼气 4s', 2, '用嘴巴缓缓呼出'); this.phaseHint('屏息 4s', 3, '保持气息不动')
      }.width('84%').justifyContent(FlexAlign.SpaceBetween)
    }
    .width('92%').padding({ bottom: 24 }).backgroundColor($r('app.color.card_bg')).borderRadius(22)
    .border({ width: 1, color: $r('app.color.card_border') }).alignItems(HorizontalAlign.Center).margin({ bottom: 12 })
  }

  @Builder phaseHint(label: string, phase: number, hint: string) {
    Column() {
      Text(label).fontSize(11)
        .fontColor(this.breathPhase === phase ? this.getBreathColor() : $r('app.color.text_muted'))
        .fontWeight(this.breathPhase === phase ? FontWeight.Bold : FontWeight.Normal)
      Text(hint).fontSize(9)
        .fontColor(this.breathPhase === phase ? this.getBreathColor() : $r('app.color.text_tertiary'))
        .fontWeight(this.breathPhase === phase ? FontWeight.Medium : FontWeight.Normal)
        .margin({ top: 2 })
    }.alignItems(HorizontalAlign.Center)
  }

  @Builder meditationCard() {
    Column() {
      Row() {
        Text('当前冥想度').fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Text('实时').fontSize(10).fontColor($r('app.color.primary')).padding({ left: 6, right: 6, top: 1, bottom: 1 }).backgroundColor($r('app.color.primary_light')).borderRadius(6).margin({ left: 6 })
      }.width('100%').padding({ left: 16, right: 16, top: 14, bottom: 10 })
      Text(this.soothMeditation.toString()).fontSize(56).fontWeight(FontWeight.Bold).fontColor(this.medColor()).fontFamily('monospace')
      Text(this.medDesc()).fontSize(12).fontColor($r('app.color.text_secondary')).margin({ top: 4, bottom: 16 })
      Row() { Row().width(`${this.soothMeditation}%`).height(8).backgroundColor(this.medColor()).borderRadius(4) }
        .width('84%').height(8).backgroundColor($r('app.color.background_secondary')).borderRadius(4)
    }
    .width('92%').backgroundColor($r('app.color.card_bg')).borderRadius(22).border({ width: 1, color: $r('app.color.card_border') }).alignItems(HorizontalAlign.Center).margin({ bottom: 12 })
  }

  @Builder soothingTipsCard() {
    Column() {
      Text('舒缓小知识').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).margin({ bottom: 12 }).alignSelf(ItemAlign.Start)
      this.tipItem('#6CBE8A', '盒式呼吸法（Box Breathing）是海豹突击队用以在高压环境中快速平静心率的战术呼吸技术。')
      this.tipItem('#74B9FF', '研究表明，每分钟进行 5~6 次缓慢深呼吸，可在 2 分钟内显著降低皮质醇水平。')
      this.tipItem('#F5A623', '冥想时 α 波增强，代表大脑处于"放松专注"状态——这是创造力最活跃的时刻。')
      this.tipItem('#A29BFE', '每天坚持 10 分钟深呼吸练习，8 周后静息心率可降低 5~10 bpm。')
      this.tipItem('#E87461', '"5-4-3-2-1"感官锚定法：说出看到的5样东西、触摸到的4样、听到的3样、闻到的2样、尝到的1样。')
    }
    .width('92%').padding(16).backgroundColor($r('app.color.card_bg')).borderRadius(22)
    .border({ width: 1, color: $r('app.color.card_border') }).margin({ bottom: 12 })
  }

  @Builder tipItem(color: string, text: string) {
    Row() {
      Circle().width(6).height(6).fill(color).margin({ right: 10, top: 5 })
      Text(text).fontSize(12).fontColor($r('app.color.label_blue')).lineHeight(18).layoutWeight(1)
    }.width('100%').alignItems(VerticalAlign.Top).margin({ bottom: 8 })
  }

  // ==================== 呼吸计时器 ====================

  private startBreathTimer(): void {
    this.breathTimer = setInterval(() => {
      this.breathPhaseTick++;
      this.breathSecLeft = Math.ceil((BREATH_TICKS - this.breathPhaseTick) / 20);
      const progress = this.breathPhaseTick / BREATH_TICKS;
      if (this.breathPhase === 0) { this.breathAnim = progress; }
      else if (this.breathPhase === 2) { this.breathAnim = 1 - progress; }
      if (this.breathPhaseTick >= BREATH_TICKS) {
        this.breathPhaseTick = 0; this.breathPhase = (this.breathPhase + 1) % 4;
        if (this.breathPhase === 0) { this.breathCycleCount++; }
      }
    }, 50);
  }

  private getBreathColor(): string { return ['#6CBE8A', '#74B9FF', '#3498DB', '#74B9FF'][this.breathPhase]; }
  private medColor(): string { const m = this.soothMeditation; if (m >= 70) return '#6CBE8A'; if (m >= 40) return '#74B9FF'; if (m >= 20) return '#F5A623'; return '#E87461'; }
  private medDesc(): string { const m = this.soothMeditation; if (m >= 70) return '深度放松 · 身心合一'; if (m >= 40) return '轻度放松 · 继续保持'; if (m >= 20) return '逐渐平静 · 跟随呼吸'; return '思绪活跃 · 专注呼吸'; }
}
