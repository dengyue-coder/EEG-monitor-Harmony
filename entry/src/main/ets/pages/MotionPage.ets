import { EEGDataStore } from '../store/EEGDataStore';
import { MotorImageryDetector, MIMotorState, MICalibPhase } from '../detectors/MotorImageryDetector';
import { drawBrain, drawMIBandBars } from '../renderers/MotorImageryRenderer';
import { BlinkDetector, getHealthInfo } from '../detectors/BlinkDetector';
import { drawBlinkChart } from '../renderers/BlinkRenderer';
import { getSignalText } from '../utils/TimeUtils';
import { signalColor } from '../utils/ColorUtils';
import { MockDataService } from '../service/MockDataService';
import { SessionService } from '../service/SessionService';

const store = EEGDataStore.getInstance();
const sessionService = SessionService.getInstance();
const mockService = MockDataService.getInstance();

@Component
export struct MotionPage {
  @State pageTab: number = 0;
  @StorageProp('dark_mode_on') darkModeOn: number = 0;
  @State miCalibPhase: number = MICalibPhase.IDLE;
  @State miCalibSecondsLeft: number = 0;
  @State miCalibSecondsTotal: number = 0;
  @State miCalibrated: boolean = false;
  @State miState: number = 0;
  @State miConfidence: number = 0;
  @State miLabel: string = '空闲';
  @State miColor: string = '#95A5A6';
  @State miLeftScore: number = 0;
  @State miRIGHT: number = 0;
  @State miREST: number = 0;
  @State miPhaseLabel: string = '';
  @State miPhaseColor: string = '#95A5A6';
  @State bandValues: number[] = [0, 0, 0, 0, 0, 0, 0, 0];
  @State miSignalText: string = '未连接';
  @State miSignalColor: string = '#95A5A6';
  @State blTotalBlinks: number = 0;
  @State blBPM: number = 0;
  @State blLastMinuteBlinks: number = 0;
  @State blHealthStatus: string = '采集中...';
  @State blHealthColor: string = '#95A5A6';
  @State blHealthTip: string = '正在收集眨眼数据，请稍候...';
  @State blEyeClosed: boolean = false;
  @State blChartData: number[] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
  @State blTimerSeconds: number = 180;
  @State blSessionBlinks: number = 0;
  @State blTimerStatus: number = 0;
  @State blTimerDuration: number = 180;
  @State blSessionRate: string = '';
  @State liveTick: number = 0;
  private miDetector: MotorImageryDetector = new MotorImageryDetector();
  private blinkDetector: BlinkDetector = new BlinkDetector();
  private brainCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D();
  private bandCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D();
  private blinkChartCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D();
  private brainReady: boolean = false;
  private bandReady: boolean = false;
  private blinkChartReady: boolean = false;
  private loopTimer: number = -1;
  private pollTimer: number = -1;
  private pollTick: number = 0;
  private blinkTimestamps: number[] = [];
  private currentMinuteBlinks: number = 0;
  private eyeCloseTimer: number = 0;
  private blinkLastFedRawCount: number = 0;

  private getPhaseIndex(phase: number): number {
    if (phase === MICalibPhase.IDLE) return 0;
    if (phase === MICalibPhase.LEFT_CUE) return 1;
    if (phase === MICalibPhase.RIGHT_CUE) return 2;
    if (phase === MICalibPhase.REST_CUE) return 3;
    if (phase === MICalibPhase.COMPLETE) return 3;
    return 0;
  }
  private getTrainingLevel(): number {
    if (this.miCalibrated) return 3;
    if (this.miCalibPhase !== MICalibPhase.IDLE) return 2;
    return 1;
  }

  aboutToAppear(): void {
    this.miDetector.reset(); this.blinkDetector.reset();
    this.loopTimer = setInterval(() => { this.onTick(); }, 50);
    this.pollTimer = setInterval(() => { this.liveTick++; }, 200);
  }
  aboutToDisappear(): void {
    if (this.loopTimer >= 0) { clearInterval(this.loopTimer); this.loopTimer = -1; }
    if (this.pollTimer >= 0) { clearInterval(this.pollTimer); this.pollTimer = -1; }
  }

  private onTick(): void {
    this.miDetector.feed(); const det = this.miDetector;
    this.miCalibPhase = det.calibPhase; this.miCalibSecondsLeft = det.calibSecondsLeft; this.miCalibSecondsTotal = det.calibSecondsTotal;
    this.miCalibrated = det.calibrated; this.miPhaseLabel = det.calibPhaseLabel; this.miPhaseColor = det.calibPhaseColor;
    const r = det.current; this.miState = r.state; this.miConfidence = r.confidence;
    this.miLabel = r.label; this.miColor = r.color;
    this.miLeftScore = r.leftScore; this.miRIGHT = r.rightScore; this.miREST = r.restScore;
    this.miSignalText = getSignalText(store.latestData.sig); this.miSignalColor = signalColor(store.latestData.sig);
    const d = store.latestData; this.bandValues = [d.d, d.t, d.aL, d.aH, d.bL, d.bH, d.gL, d.gM];
    if (this.brainReady && this.pageTab === 0) { drawBrain(this.brainCtx, this.miLeftScore, this.miRIGHT, this.miState, this.miConfidence, this.brainCtx.width, this.brainCtx.height, this.darkModeOn === 1 ? '#1A1E25' : undefined); }
    if (this.bandReady && this.pageTab === 0) { drawMIBandBars(this.bandCtx, ['δ','θ','αL','αH','βL','βH','γL','γM'], this.bandValues, ['#6CBE8A','#74B9FF','#F5A623','#E87461','#A29BFE','#FD79A8','#00CEC9','#FDCB6E'], this.bandCtx.width, this.bandCtx.height, this.darkModeOn === 1 ? '#1A1E25' : undefined); }
    this.pollTick++;
    // 眨眼检测：消费 rawHistory 里新增的原始波形样本（过滤无效值），
    // 避免固件帧缺 raw 字段时把 undefined 喂进检测器导致计数恒为 0
    const blinkHist = store.rawHistory;
    if (this.blinkLastFedRawCount > blinkHist.length) {
      this.blinkLastFedRawCount = 0;
    }
    let blinked = false;
    for (let bi = this.blinkLastFedRawCount; bi < blinkHist.length; bi++) {
      const bv = blinkHist[bi];
      if (typeof bv === 'number' && isFinite(bv)) {
        if (this.blinkDetector.feed(bv)) {
          blinked = true;
        }
      }
    }
    this.blinkLastFedRawCount = blinkHist.length;
    if (blinked) { sessionService.incrementBlinks(); this.blTotalBlinks++; this.currentMinuteBlinks++; this.blinkTimestamps.push(this.pollTick); this.blEyeClosed = true; this.eyeCloseTimer = 4; if (this.blTimerStatus === 1) { this.blSessionBlinks++; } }
    if (this.eyeCloseTimer > 0) { this.eyeCloseTimer--; if (this.eyeCloseTimer === 0) this.blEyeClosed = false; }
    const cutoff = this.pollTick - 1200; while (this.blinkTimestamps.length > 0 && this.blinkTimestamps[0] < cutoff) this.blinkTimestamps.shift();
    this.blBPM = this.blinkTimestamps.length;
    if (this.pollTick % 1200 === 0) { this.blLastMinuteBlinks = this.currentMinuteBlinks; const nc = [...this.blChartData]; nc.push(this.currentMinuteBlinks); if (nc.length > 10) nc.shift(); this.blChartData = nc; this.currentMinuteBlinks = 0; const info = getHealthInfo(this.blLastMinuteBlinks); this.blHealthStatus = info.status; this.blHealthColor = info.color; this.blHealthTip = info.tip; }
    if (this.blTimerStatus === 1 && this.pollTick % 20 === 0) {
      this.blTimerSeconds--;
      if (this.blTimerSeconds <= 0) {
        this.blTimerSeconds = 0;
        this.blTimerStatus = 3;
        this.blSessionRate = (this.blSessionBlinks / (this.blTimerDuration / 60)).toFixed(1);
      }
    }
    if (this.blinkChartReady && this.pageTab === 1) { drawBlinkChart(this.blinkChartCtx, this.blChartData, this.blinkChartCtx.width, this.blinkChartCtx.height); }
  }

  build() {
    Column() { Scroll() { Column() {
        this.cockpitBar(); this.navPills();
        if (this.pageTab === 0) { this.neuralCenter(); this.taskCards(); this.neuralSpectrum(); this.aiFeedbackCard(); }
        else { this.blinkCockpit(); this.blinkTimerCard(); this.blinkDetailCard(); this.blinkTrendCard(); this.blinkKnowledgeCard(); }
    }.width('100%').alignItems(HorizontalAlign.Center).padding({ top: 10, bottom: 24 }) }
    .layoutWeight(1).scrollBar(BarState.Off) }
    .width('100%').height('100%').linearGradient({ direction: GradientDirection.Bottom, colors: [[$r('app.color.page_bg_gradient_top'), 0.0], [$r('app.color.page_bg_gradient_mid'), 0.5], [$r('app.color.page_bg_gradient_bottom'), 1.0]] })
  }

  @Builder cockpitBar() { Row() {
    Stack() { Circle().width(40).height(40).fill('rgba(69,230,165,0.08)'); Circle().width(12).height(12).fill(this.miSignalColor).shadow({ radius: 6, color: this.miSignalColor + '40', offsetX: 0, offsetY: 0 }); Circle().width(20).height(20).fill('#00000000').stroke('rgba(69,230,165,0.2)').strokeWidth(1) }
    Column() { Text('脑控训练状态舱').fontSize(15).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')); Text('Lv.' + this.getTrainingLevel().toString() + ' · ' + this.miSignalText).fontSize(10).fontColor($r('app.color.text_tertiary')).margin({ top:1 }) }.alignItems(HorizontalAlign.Start).margin({ left:10 })
    Blank()
    Column() { Text(this.miCalibrated ? '已校准' : '待校准').fontSize(11).fontWeight(FontWeight.Bold).fontColor('#45E6A5'); Text('稳定度').fontSize(8).fontColor($r('app.color.text_tertiary')) }.alignItems(HorizontalAlign.Center)
  }.width('92%').padding({ left:14, right:14, top:10, bottom:10 }).linearGradient({ angle:145, colors:[['rgba(255,255,255,0.05)',0.0],['rgba(255,255,255,0.0)',0.35]] }).backgroundColor($r('app.color.card_bg')).borderRadius(24).border({ width:1, color:$r('app.color.card_border') }).margin({ bottom:10 }) }

  @Builder navPills() { Row() { this.pill('🧠 意念分类',0); this.pill('👁 眨眼检测',1) }.width('92%').backgroundColor('rgba(255,255,255,0.02)').borderRadius(16).border({ width:1, color:$r('app.color.card_border') }).padding(4).margin({ bottom:10 }) }
  @Builder pill(label:string, idx:number) { Text(label).fontSize(12).fontColor(this.pageTab===idx?'#080D18':$r('app.color.text_secondary')).fontWeight(this.pageTab===idx?FontWeight.Medium:FontWeight.Normal).padding({ top:12, bottom:12 }).layoutWeight(1).textAlign(TextAlign.Center).backgroundColor(this.pageTab===idx?'#45E6A5':'#00000000').borderRadius(13).onClick(()=>{this.pageTab=idx}) }

  @Builder neuralCenter() { Stack() {
    Image($r('app.media.bg_neural')).width('100%').height('100%').objectFit(ImageFit.Cover)
    Circle({ width:180, height:180 }).fill('#00000000').stroke('rgba(69,230,165,0.12)').strokeWidth(1).strokeDashArray([4,20]).position({ x:'50%', y:'50%' }).translate({ x:'-90vp', y:'-90vp' })
    Circle({ width:140, height:140 }).fill('#00000000').stroke('rgba(76,163,255,0.15)').strokeWidth(0.5).position({ x:'50%', y:'50%' }).translate({ x:'-70vp', y:'-70vp' })
    Circle({ width:100, height:100 }).fill('#00000000').stroke('rgba(139,124,255,0.2)').strokeWidth(1).strokeDashArray([8,4]).position({ x:'50%', y:'50%' }).translate({ x:'-50vp', y:'-50vp' })
    Stack() { Circle({ width:100, height:100 }).fill('rgba(69,230,165,0.08)').shadow({ radius:30, color:'rgba(69,230,165,0.15)', offsetX:0, offsetY:0 }); Circle({ width:68, height:68 }).fill('rgba(69,230,165,0.2)'); Circle({ width:36, height:36 }).fill('#45E6A5').shadow({ radius:18, color:'#4045E6A5', offsetX:0, offsetY:0 }); Text('脑').fontSize(18).fontColor('#080D18').fontWeight(FontWeight.Bold) }.position({ x:'50%', y:'50%' }).translate({ x:'-50vp', y:'-50vp' })
    Circle({ width:3, height:3 }).fill('#45E6A5').opacity(0.1+Math.sin(this.liveTick*0.3)*0.2).position({ x:'30%', y:'20%' })
    Circle({ width:2, height:2 }).fill('#4CA3FF').opacity(0.1+Math.cos(this.liveTick*0.4)*0.2).position({ x:'70%', y:'30%' })
    Circle({ width:2.5, height:2.5 }).fill('#8B7CFF').opacity(0.1+Math.sin(this.liveTick*0.35)*0.2).position({ x:'40%', y:'70%' })
    Column() { Text(this.miCalibrated?this.miLabel:'待校准').fontSize(14).fontWeight(FontWeight.Bold).fontColor('#45E6A5'); Text('识别准确率').fontSize(8).fontColor($r('app.color.text_tertiary')).margin({ top:2 }); Row().width(40).height(2).backgroundColor('rgba(69,230,165,0.3)').borderRadius(1).margin({ top:4 }); Text(this.miConfidence.toString()+'%').fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).fontFamily('monospace').margin({ top:4 }) }.alignItems(HorizontalAlign.Center).position({ x:'72%', y:'50%' }).translate({ x:0, y:'-40vp' })
    Text('神经校准中心').fontSize(10).fontColor('#45E6A5').padding({ left:8, right:8, top:2, bottom:2 }).backgroundColor('rgba(69,230,165,0.06)').borderRadius(8).position({ x:'50%', y:16 }).translate({ x:'-50%' })
  }.width('92%').height(260).clip(true).borderRadius(24).border({ width:1, color:$r('app.color.card_border') }).margin({ bottom:10 }) }

  @Builder taskCards() { Column() {
    Text('训练任务').fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).margin({ bottom:8 }).alignSelf(ItemAlign.Start).margin({ left:4 })
    if (this.miCalibPhase===MICalibPhase.IDLE && !this.miCalibrated) {
      Row() { this.taskItem('01','左手运动想象','想象左手抓握/挥手',this.miLeftScore,'#45E6A5'); this.taskItem('02','右手运动想象','想象右手抓握/挥手',this.miRIGHT,'#4CA3FF'); this.taskItem('03','放松基线校准','保持放松不想动作',this.miREST,'#8B7CFF') }.width('92%').justifyContent(FlexAlign.SpaceEvenly)
      Button('开始校准 · 10秒×3').width('88%').height(40).backgroundColor('#45E6A5').borderRadius(20).fontSize(13).fontColor('#080D18').fontWeight(FontWeight.Bold).shadow({ radius:10, color:'#4045E6A5', offsetX:0, offsetY:3 }).margin({ top:12 }).onClick(()=>{this.miDetector.startCalibration()})
    } else if (this.miCalibPhase!==MICalibPhase.IDLE && this.miCalibPhase!==MICalibPhase.COMPLETE) {
      Column() { Text(this.miPhaseLabel).fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.miPhaseColor); Text(this.miCalibSecondsLeft.toString()+'s').fontSize(44).fontWeight(FontWeight.Bold).fontColor(this.miPhaseColor).fontFamily('monospace').margin({ top:4, bottom:6 }); Row(){Row().width(((1-this.miCalibSecondsLeft/this.miCalibSecondsTotal)*100).toFixed(0)+'%').height(4).backgroundColor(this.miPhaseColor).borderRadius(2)}.width('70%').height(4).backgroundColor('rgba(255,255,255,0.06)').borderRadius(2).margin({ bottom:4 }); Row(){this.phaseDot('左手',MICalibPhase.LEFT_CUE,'#45E6A5');Row().width(24).height(1.5).backgroundColor('rgba(255,255,255,0.08)').margin({ bottom:14 });this.phaseDot('右手',MICalibPhase.RIGHT_CUE,'#4CA3FF');Row().width(24).height(1.5).backgroundColor('rgba(255,255,255,0.08)').margin({ bottom:14 });this.phaseDot('空闲',MICalibPhase.REST_CUE,'#8899AA')}.width('76%').justifyContent(FlexAlign.Center) }.width('92%').padding({ top:16, bottom:16 }).backgroundColor($r('app.color.card_bg')).borderRadius(22).border({ width:1, color:$r('app.color.card_border') }).alignItems(HorizontalAlign.Center)
    } else { Row() { this.scoreCard('左手',this.miLeftScore,'#45E6A5'); this.scoreCard('右手',this.miRIGHT,'#4CA3FF'); this.scoreCard('空闲',this.miREST,'#8899AA') }.width('92%').justifyContent(FlexAlign.SpaceEvenly) }
  }.width('100%').alignItems(HorizontalAlign.Center).margin({ bottom:10 }) }

  @Builder taskItem(num:string, title:string, desc:string, score:number, color:string) { Column() { Text(num).fontSize(12).fontWeight(FontWeight.Bold).fontColor(color).fontFamily('monospace').padding({ left:6, right:6, top:2, bottom:2 }).backgroundColor(color+'10').borderRadius(6); Text(title).fontSize(10).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).margin({ top:6 }); Text(desc).fontSize(8).fontColor($r('app.color.text_tertiary')).textAlign(TextAlign.Center).lineHeight(12).margin({ top:2 }); Row().width('60%').height(2).backgroundColor('rgba(255,255,255,0.06)').borderRadius(1).margin({ top:6 }); Text(score.toString()).fontSize(16).fontWeight(FontWeight.Bold).fontColor(color).fontFamily('monospace').margin({ top:2 }) }.width('30%').padding({ top:12, bottom:12 }).backgroundColor($r('app.color.card_bg')).borderRadius(16).border({ width:1, color:$r('app.color.card_border') }).alignItems(HorizontalAlign.Center) }
  @Builder scoreCard(label:string, score:number, color:string) { Column() { Text(label).fontSize(11).fontColor($r('app.color.text_secondary')); Text(score.toString()).fontSize(28).fontWeight(FontWeight.Bold).fontColor(color).fontFamily('monospace').margin({ top:4 }); Row(){Row().width(score.toString()+'%').height(2).backgroundColor(color).borderRadius(1)}.width(48).height(2).backgroundColor('rgba(255,255,255,0.08)').borderRadius(1).margin({ top:4 }) }.width('30%').padding({ top:12, bottom:12 }).backgroundColor($r('app.color.card_bg')).borderRadius(18).border({ width:1, color:$r('app.color.card_border') }).alignItems(HorizontalAlign.Center) }
  @Builder phaseDot(label:string, phase:number, color:string) { Column() { Circle().width(14).height(14).fill(this.miCalibPhase===phase?color:'rgba(255,255,255,0.06)').shadow({ radius:this.miCalibPhase===phase?6:0, color:this.miCalibPhase===phase?color+'40':'#00000000', offsetX:0, offsetY:0 }); Text(label).fontSize(9).fontColor(this.miCalibPhase===phase?color:$r('app.color.text_muted')).margin({ top:3 }) }.alignItems(HorizontalAlign.Center) }

  @Builder neuralSpectrum() { Column() {
    Row() { Text('Neural Spectrum').fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')); Blank(); Text('实时频谱').fontSize(9).fontColor('#45E6A5').padding({ left:6, right:6, top:1, bottom:1 }).backgroundColor('rgba(69,230,165,0.08)').borderRadius(6) }.width('100%').padding({ left:16, right:16, top:14, bottom:6 })
    Canvas(this.bandCtx).width('100%').height(220).onReady(()=>{this.bandReady=true;drawMIBandBars(this.bandCtx,['δ','θ','αL','αH','βL','βH','γL','γM'],this.bandValues,['#6CBE8A','#74B9FF','#F5A623','#E87461','#A29BFE','#FD79A8','#00CEC9','#FDCB6E'],this.bandCtx.width,this.bandCtx.height,this.darkModeOn===1?'#1A1E25':undefined)})
  }.width('92%').linearGradient({ angle:145, colors:[['rgba(255,255,255,0.05)',0.0],['rgba(255,255,255,0.0)',0.35]] }).backgroundColor($r('app.color.card_bg')).borderRadius(22).border({ width:1, color:$r('app.color.card_border') }).margin({ bottom:10 }) }

  @Builder aiFeedbackCard() { Column() {
    Row() { Text('AI 训练反馈').fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')) }.width('100%').padding({ left:16, right:16, top:14, bottom:8 })
    Column() {
      Row(){Circle().width(5).height(5).fill('#45E6A5').margin({ right:6, top:3 });Column(){Text('识别稳定度').fontSize(10).fontColor($r('app.color.text_tertiary'));Text(this.miConfidence>70?'稳定 · 分类准确':'校准中 · 样本不足').fontSize(11).fontColor($r('app.color.text_primary')).margin({ top:2 })}.alignItems(HorizontalAlign.Start).layoutWeight(1)}.width('100%').padding({ top:6, bottom:6 }).border({ width:{ bottom:0.5 }, color:$r('app.color.card_border') })
      Row(){Circle().width(5).height(5).fill('#4CA3FF').margin({ right:6, top:3 });Column(){Text('优化建议').fontSize(10).fontColor($r('app.color.text_tertiary'));Text(this.miCalibrated?'当前识别稳定，可切换页面进行实时分类训练':'请完成三步校准流程以获得准确分类').fontSize(11).fontColor($r('app.color.text_primary')).lineHeight(16).margin({ top:2 })}.alignItems(HorizontalAlign.Start).layoutWeight(1)}.width('100%').padding({ top:6, bottom:6 }).border({ width:{ bottom:0.5 }, color:$r('app.color.card_border') })
      Row(){Circle().width(5).height(5).fill('#8B7CFF').margin({ right:6, top:3 });Column(){Text('训练原理').fontSize(10).fontColor($r('app.color.text_tertiary'));Text('Mu节律检测 · 左右半球对比 · 质心最近邻分类 · 持续学习优化').fontSize(11).fontColor($r('app.color.text_primary')).lineHeight(16).margin({ top:2 })}.alignItems(HorizontalAlign.Start).layoutWeight(1)}.width('100%').padding({ top:6, bottom:6 })
    }.width('100%').padding({ left:12, right:12, bottom:10 })
  }.width('92%').linearGradient({ angle:145, colors:[['rgba(255,255,255,0.05)',0.0],['rgba(255,255,255,0.0)',0.35]] }).backgroundColor($r('app.color.card_bg')).borderRadius(22).border({ width:1, color:$r('app.color.card_border') }).margin({ bottom:12 }) }

  @Builder blinkCockpit() {
    Stack() {
      Image($r('app.media.bg_blink')).width('100%').height('100%').objectFit(ImageFit.Cover)
      Column() {
        Stack() { Circle().width(64).height(64).fill('rgba(76,163,255,0.06)').stroke('rgba(76,163,255,0.35)').strokeWidth(2); Circle().width(20).height(20).fill('#4CA3FF').shadow({ radius:10, color:'#404CA3FF', offsetX:0, offsetY:0 }) }.scale(this.blEyeClosed?{x:1,y:0.1}:{x:1,y:1}).animation({ duration:80, curve:Curve.Sharp }).margin({ top:14 })
        Text(this.blTotalBlinks.toString()).fontSize(56).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).fontFamily('monospace').margin({ top:10 })
        Text('实时眨眼计数').fontSize(11).fontColor($r('app.color.text_secondary')).margin({ top:4 })
        Row(){Circle().width(5).height(5).fill('#4CA3FF');Text(this.blEyeClosed?'眨眼检测中':'监测中').fontSize(10).fontColor($r('app.color.text_tertiary')).margin({ left:4 })}.margin({ top:8 })
      }.padding({ top:10, bottom:18 }).alignItems(HorizontalAlign.Center)
    }
    .width('92%').height(220).clip(true).borderRadius(24).border({ width:1, color:$r('app.color.card_border') }).margin({ bottom:10 })
  }

  @Builder blinkTimerCard() {
    Column() {
      Row() {
        Text('⏱ 计时眨眼测试').fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Blank()
        Text(this.blTimerStatus === 1 ? '计时中' : (this.blTimerStatus === 2 ? '已暂停' : (this.blTimerStatus === 3 ? '已结束' : '未开始')))
          .fontSize(9).fontColor(this.blTimerStatus === 1 ? '#45E6A5' : $r('app.color.text_tertiary'))
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .backgroundColor(this.blTimerStatus === 1 ? 'rgba(69,230,165,0.10)' : 'rgba(255,255,255,0.04)').borderRadius(8)
      }.width('100%').margin({ bottom: 12 })

      Row() {
        Column() {
          Text(this.fmtTimer(this.blTimerSeconds)).fontSize(34).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).fontFamily('monospace')
          Text('剩余时间').fontSize(9).fontColor($r('app.color.text_tertiary')).margin({ top: 2 })
        }.layoutWeight(1).alignItems(HorizontalAlign.Center)
        Column().width(1).height(44).backgroundColor($r('app.color.card_border'))
        Column() {
          Text(this.blSessionBlinks.toString()).fontSize(34).fontWeight(FontWeight.Bold).fontColor('#4CA3FF').fontFamily('monospace')
          Text('计时内眨眼').fontSize(9).fontColor($r('app.color.text_tertiary')).margin({ top: 2 })
        }.layoutWeight(1).alignItems(HorizontalAlign.Center)
        Column().width(1).height(44).backgroundColor($r('app.color.card_border'))
        Column() {
          Text(this.blSessionRate === '' ? '--' : this.blSessionRate).fontSize(34).fontWeight(FontWeight.Bold).fontColor('#45E6A5').fontFamily('monospace')
          Text('次/分').fontSize(9).fontColor($r('app.color.text_tertiary')).margin({ top: 2 })
        }.layoutWeight(1).alignItems(HorizontalAlign.Center)
      }.width('100%')

      Row() {
        this.durChip('1 分钟', 60)
        this.durChip('3 分钟', 180)
        this.durChip('5 分钟', 300)
      }.width('100%').justifyContent(FlexAlign.Center).margin({ top: 12 })

      if (this.blTimerStatus === 3) {
        Text('计时结束 · 共 ' + this.blSessionBlinks.toString() + ' 次眨眼').fontSize(10).fontColor('#45E6A5').margin({ top: 8 })
      }

      Row() {
        Button(this.blTimerStatus === 1 ? '暂停' : (this.blTimerStatus === 2 ? '继续' : '开始'))
          .layoutWeight(1).height(36).backgroundColor(this.blTimerStatus === 1 ? '#F5A623' : '#45E6A5')
          .borderRadius(18).fontSize(13).fontColor('#080D18').fontWeight(FontWeight.Bold)
          .onClick(() => {
            if (this.blTimerStatus === 1) {
              this.pauseBlinkTimer();
            } else {
              this.startBlinkTimer();
            }
          })
        Button('清零')
          .layoutWeight(1).height(36).backgroundColor('rgba(255,255,255,0.06)')
          .borderRadius(18).fontSize(13).fontColor($r('app.color.text_primary')).fontWeight(FontWeight.Medium).margin({ left: 10 })
          .onClick(() => {
            this.resetBlinkTimer();
          })
      }.width('100%').margin({ top: 12 })
    }
    .width('92%').padding(16)
    .linearGradient({ angle: 145, colors: [['rgba(255,255,255,0.05)', 0.0], ['rgba(255,255,255,0.0)', 0.35]] })
    .backgroundColor($r('app.color.card_bg')).borderRadius(22).border({ width: 1, color: $r('app.color.card_border') }).margin({ bottom: 10 })
  }

  @Builder durChip(label: string, seconds: number) {
    Text(label).fontSize(11).fontColor(this.blTimerDuration === seconds ? '#080D18' : $r('app.color.text_secondary'))
      .fontWeight(this.blTimerDuration === seconds ? FontWeight.Bold : FontWeight.Normal)
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .backgroundColor(this.blTimerDuration === seconds ? '#4CA3FF' : 'rgba(255,255,255,0.04)').borderRadius(12)
      .margin({ left: 4, right: 4 })
      .onClick(() => {
        if (this.blTimerStatus === 1) {
          return;
        }
        this.blTimerDuration = seconds;
        this.blTimerSeconds = seconds;
        this.blSessionBlinks = 0;
        this.blSessionRate = '';
        this.blTimerStatus = 0;
      })
  }

  private fmtTimer(sec: number): string {
    const s = sec < 0 ? 0 : sec;
    const m = Math.floor(s / 60);
    const r = s % 60;
    return (m < 10 ? '0' + m.toString() : m.toString()) + ':' + (r < 10 ? '0' + r.toString() : r.toString());
  }

  private startBlinkTimer(): void {
    if (this.blTimerStatus === 1) {
      return;
    }
    if (this.blTimerStatus === 3 || this.blTimerSeconds <= 0) {
      this.blTimerSeconds = this.blTimerDuration;
      this.blSessionBlinks = 0;
      this.blSessionRate = '';
    }
    this.blTimerStatus = 1;
  }

  private pauseBlinkTimer(): void {
    if (this.blTimerStatus === 1) {
      this.blTimerStatus = 2;
    }
  }

  private resetBlinkTimer(): void {
    this.blTimerStatus = 0;
    this.blTimerSeconds = this.blTimerDuration;
    this.blSessionBlinks = 0;
    this.blSessionRate = '';
  }

  @Builder blinkDetailCard() { Row() {
    this.blStat('每分钟',this.blBPM.toString(),'次/分','#4CA3FF'); Column().width(1).height(40).backgroundColor($r('app.color.card_border'))
    this.blStat('健康',this.blHealthStatus,'',this.blHealthColor); Column().width(1).height(40).backgroundColor($r('app.color.card_border'))
    this.blStat('近1分钟',this.blLastMinuteBlinks.toString(),'次','#45E6A5')
  }.width('92%').padding({ top:14, bottom:14 }).backgroundColor($r('app.color.card_bg')).borderRadius(22).border({ width:1, color:$r('app.color.card_border') }).justifyContent(FlexAlign.SpaceEvenly).margin({ bottom:10 }) }
  @Builder blStat(label:string, value:string, unit:string, color:string) { Column() { Text(value).fontSize(20).fontWeight(FontWeight.Bold).fontColor(color).fontFamily('monospace'); Row(){Text(label).fontSize(9).fontColor($r('app.color.text_tertiary'));if(unit!=='')Text(' '+unit).fontSize(9).fontColor($r('app.color.text_muted'))}.margin({ top:2 }) }.alignItems(HorizontalAlign.Center).layoutWeight(1) }

  @Builder blinkTrendCard() { Column() {
    Text('眨眼趋势 · 10分钟').fontSize(12).fontColor($r('app.color.text_secondary')).margin({ bottom:8 }).alignSelf(ItemAlign.Start)
    Canvas(this.blinkChartCtx).width('100%').height(110).backgroundColor($r('app.color.canvas_fill')).borderRadius(10).onReady(()=>{this.blinkChartReady=true;drawBlinkChart(this.blinkChartCtx,this.blChartData,this.blinkChartCtx.width,this.blinkChartCtx.height)})
  }.width('92%').padding(14).backgroundColor($r('app.color.card_bg')).borderRadius(22).border({ width:1, color:$r('app.color.card_border') }).margin({ bottom:10 }) }

  @Builder blinkKnowledgeCard() { Column() {
    Text('健康眨眼小知识').fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).margin({ bottom:10 }).alignSelf(ItemAlign.Start)
    Column() { this.blK('#4CA3FF','正常成年人每分钟眨眼 15~20 次'); this.blK('#FFB84D','看屏幕时眨眼频率骤降至 5~7 次/分钟'); this.blK('#45E6A5','眨眼能分泌泪液润滑眼球、清除灰尘'); this.blK('#8B7CFF','遵循"20-20-20 法则"保护眼睛'); this.blK('#FF6675','持续 <10次/分钟 请立即休息') }.width('100%')
  }.width('92%').padding(16).backgroundColor($r('app.color.card_bg')).borderRadius(22).border({ width:1, color:$r('app.color.card_border') }).margin({ bottom:16 }) }
  @Builder blK(color:string, text:string) { Row(){Circle().width(5).height(5).fill(color).margin({ right:8, top:4 });Text(text).fontSize(11).fontColor($r('app.color.text_secondary')).lineHeight(17).layoutWeight(1)}.width('100%').alignItems(VerticalAlign.Top).margin({ bottom:7 }) }
}
