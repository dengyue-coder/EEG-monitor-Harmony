import { EEGDataStore, TrendPoint } from '../store/EEGDataStore';
import { drawTrend, drawWave, drawSpectrum, drawBandTrend } from '../renderers/WaveRenderer';
import { signalColor } from '../utils/ColorUtils';
import { getSignalText } from '../utils/TimeUtils';
import { MockDataService } from '../service/MockDataService';

const store = EEGDataStore.getInstance();
const mockService = MockDataService.getInstance();

@Component
export struct BrainwavePage {
  @State connected: boolean = false;
  @State sigText: string = '未连接';
  @State sigColor: string = '#484F58';
  @State attention: number = 0;
  @State meditation: number = 0;
  @State rawPreview: number[] = [];
  @State bandPower: number[] = [0, 0, 0, 0, 0, 0, 0, 0];
  @State bandHistory: number[][] = [[], [], [], [], [], [], [], []];
  @State trendHistory: TrendPoint[] = [];
  @State liveTick: number = 0;
  @State contactLost: boolean = false;
  @StorageProp('dark_mode_on') darkModeOn: number = 0;
  private trendCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D();
  private waveCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D();
  private spectrumCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D();
  private bandTrendCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D();
  private trendReady: boolean = false;
  private waveReady: boolean = false;
  private spectrumReady: boolean = false;
  private bandTrendReady: boolean = false;
  private unsubUpdate: (() => void) | null = null;
  private unsubRaw: (() => void) | null = null;
  private pollTimer: number = -1;
  private emaAtt: number = -1;
  private emaMed: number = -1;

  aboutToAppear(): void {
    this.readStore();
    this.unsubUpdate = store.subscribe(() => { this.readStore(); });
    this.unsubRaw = store.subscribeRaw(() => {
      this.rawPreview = store.rawHistory.slice(-512);
      if (this.waveReady) this.drawWaveChart();
    });
    // 轮询兜底：确保任何时序下都能读到最新数据
    this.pollTimer = setInterval(() => { this.readStore(); }, 300);
  }
  private readStore(): void {
    this.connected = store.connected;
    this.contactLost = store.contactLost;
    this.sigText = getSignalText(store.latestData.sig);
    this.sigColor = signalColor(store.latestData.sig);
    // 显示层轻量 EMA 平滑：钉子电极信号本身有抖动，直接显示原始值会来回跳
    const rawAtt = store.latestData.att;
    const rawMed = store.latestData.med;
    if (this.emaAtt < 0) {
      this.emaAtt = rawAtt;
      this.emaMed = rawMed;
    } else {
      this.emaAtt = this.emaAtt + (rawAtt - this.emaAtt) * 0.35;
      this.emaMed = this.emaMed + (rawMed - this.emaMed) * 0.35;
    }
    this.attention = Math.round(this.emaAtt);
    this.meditation = Math.round(this.emaMed);
    this.bandPower = store.bandPower; this.bandHistory = store.bandHistory; this.trendHistory = store.trendHistory; this.liveTick++;
    console.info('[BW] conn=' + this.connected + ' sig=' + store.latestData.sig + ' contactLost=' + this.contactLost + ' att=' + this.attention + ' med=' + this.meditation);
    if (this.trendReady) this.drawTrendChart(); if (this.spectrumReady) this.drawSpectrumChart(); if (this.bandTrendReady) this.drawBandTrendChart();
  }
  aboutToDisappear(): void {
    if (this.unsubUpdate) { this.unsubUpdate(); this.unsubUpdate = null; }
    if (this.unsubRaw) { this.unsubRaw(); this.unsubRaw = null; }
    if (this.pollTimer >= 0) { clearInterval(this.pollTimer); this.pollTimer = -1; }
  }

  private getAttLabel(): string { if(this.attention>=80)return'高度专注';if(this.attention>=60)return'专注良好';if(this.attention>=40)return'一般水平';if(this.attention>=20)return'偏低';return'未检测' }
  private getAttSuggestion(): string { if(this.attention>=80)return'状态极佳，继续维持';if(this.attention>=60)return'专注力在线，表现稳定';if(this.attention>=40)return'建议进行专注训练';return'请放松后重新检测' }
  private getMedLabel(): string { if(this.meditation>=80)return'深度放松';if(this.meditation>=60)return'平稳放松';if(this.meditation>=40)return'轻度放松';if(this.meditation>=20)return'较活跃';return'未检测' }
  private getMedSuggestion(): string { if(this.meditation>=80)return'身心深度平静';if(this.meditation>=60)return'冥想状态良好';if(this.meditation>=40)return'建议尝试深呼吸';return'思绪较多，尝试冥想' }
  private getBrainScore(): number { return Math.round((this.attention+this.meditation)/2) }
  private getBrainStatus(): string { const s=this.getBrainScore();if(s>=75)return'状态优秀';if(s>=55)return'状态良好';if(s>=35)return'状态一般';return'需要关注' }
  private getBrainTip(): string { const s=this.getBrainScore();if(s>=75)return'脑波活跃度极佳，适合进行创意工作';if(s>=55)return'当前状态稳定，建议保持节奏';if(s>=35)return'可以尝试专注训练来提升状态';return'建议放松休息，或进行一次冥想' }

  build() {
    Scroll() {
      Column() {
        this.deviceBar();
        if (this.connected && this.contactLost) { this.contactWarningBanner() }
        this.brainStatusCard(); this.miniCardsRow(); this.aiAnalysisCard();
        this.gaugeSection(); this.trendSection(); this.rawWaveSection(); this.spectrumSection(); this.bandTrendSection();
      }.width('100%').padding({bottom:24})
    }.width('100%').height('100%').scrollBar(BarState.Off)
    .linearGradient({direction:GradientDirection.Bottom,colors:[[$r('app.color.page_bg_gradient_top'),0.0],[$r('app.color.page_bg_gradient_mid'),0.5],[$r('app.color.page_bg_gradient_bottom'),1.0]]})
  }

  @Builder deviceBar() {
    Row() {
      Row() {
        Stack() { Circle().width(44).height(44).fill($r('app.color.primary_light')); Circle().width(14).height(14).fill(this.connected?$r('app.color.primary'):$r('app.color.error')).shadow({radius:6,color:this.connected?$r('app.color.shadow_glow_green'):$r('app.color.shadow_glow_red'),offsetX:0,offsetY:0}); Circle().width(22).height(22).fill('#00000000').stroke(this.connected?$r('app.color.border_accent_green'):$r('app.color.error_light')).strokeWidth(1) }
        Column() {
          Row(){Text('NeuroOS').fontSize(15).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'));Text(' · 脑波监测').fontSize(11).fontColor($r('app.color.text_tertiary')).margin({left:4})}
          Text(this.connected ? ('BrainPi H3863 · ' + (this.contactLost ? '信号丢失，请检查电极' : this.sigText)) : 'BrainPi H3863 · 未连接')
            .fontSize(10).fontColor(this.contactLost ? $r('app.color.warning') : $r('app.color.text_tertiary')).margin({top:2})
        }.alignItems(HorizontalAlign.Start).margin({left:10})
      }
      Blank()
      Row() {
        Circle().width(6).height(6).fill(this.connected ? (this.contactLost ? $r('app.color.warning') : $r('app.color.primary')) : $r('app.color.text_muted'))
          .opacity(this.liveTick%6<2?1:0.4).animation({duration:400,curve:Curve.EaseInOut})
        Text(this.connected ? (this.contactLost ? '信号中断' : '实时') : '离线')
          .fontSize(10).fontColor(this.contactLost ? $r('app.color.warning') : $r('app.color.text_secondary')).margin({left:5})
      }.padding({left:10,right:10,top:4,bottom:4}).backgroundColor($r('app.color.card_bg_strong')).borderRadius(10)
    }.width('92%').padding({left:14,right:14,top:12,bottom:12})
    .linearGradient({angle:145,colors:[['rgba(255,255,255,0.05)',0.0],['rgba(255,255,255,0.0)',0.35]]}).backgroundColor($r('app.color.card_bg')).borderRadius({topLeft:18,topRight:18,bottomLeft:6,bottomRight:18}).border({width:1,color:$r('app.color.card_border')}).margin({top:12,bottom:10})
  }

  @Builder contactWarningBanner() {
    Row() {
      Text('⚠').fontSize(14).fontColor($r('app.color.warning'))
      Text('电极接触不良，信号不稳定：请按压/调整电极位置，确保与皮肤充分接触')
        .fontSize(11).fontColor($r('app.color.text_secondary')).layoutWeight(1).margin({ left: 8 }).lineHeight(17)
    }.width('92%').padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .backgroundColor($r('app.color.warning_light')).borderRadius(12)
    .border({ width: 1, color: $r('app.color.border_accent_orange') }).margin({ bottom: 10 })
  }

  @Builder brainStatusCard() {
    Stack() {
      Image($r('app.media.bg_brainwave')).width('100%').height('100%').objectFit(ImageFit.Cover)
      Column() {
        Row() { Text('今日脑状态').fontSize(12).fontColor($r('app.color.text_secondary')).fontWeight(FontWeight.Medium); Blank(); Row(){Circle().width(5).height(5).fill(this.contactLost?$r('app.color.warning'):$r('app.color.primary'));Text(this.contactLost?'无信号':'实时评分').fontSize(10).fontColor(this.contactLost?$r('app.color.warning'):$r('app.color.primary')).margin({left:4})}.padding({left:8,right:8,top:2,bottom:2}).backgroundColor(this.contactLost?$r('app.color.warning_light'):$r('app.color.primary_light')).borderRadius(8) }.width('100%').padding({left:4,right:4})
        Text(this.contactLost ? '--' : this.getBrainScore().toString()).fontSize(64).fontWeight(FontWeight.Bold).fontColor(this.contactLost?$r('app.color.text_muted'):$r('app.color.text_primary')).fontFamily('monospace').shadow({radius:20,color:$r('app.color.score_glow'),offsetX:0,offsetY:0}).margin({top:8})
        Row(){Circle().width(7).height(7).fill(this.contactLost?$r('app.color.warning'):(this.getBrainScore()>=55?$r('app.color.primary'):$r('app.color.warning')));Text(this.contactLost?'未检测到电极信号':this.getBrainStatus()).fontSize(14).fontColor($r('app.color.text_secondary')).margin({left:5})}.margin({top:4})
        Text(this.contactLost ? '请佩戴设备并确保电极与皮肤充分接触' : this.getBrainTip()).fontSize(11).fontColor($r('app.color.text_tertiary')).margin({top:8}).textAlign(TextAlign.Center)
        Row(){Text('↑').fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.primary'));Text('+8%').fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.primary')).fontFamily('monospace').margin({left:4});Text('比昨日').fontSize(11).fontColor($r('app.color.text_tertiary')).margin({left:8})}.margin({top:12}).padding({top:10,bottom:10,left:16,right:16}).backgroundColor($r('app.color.primary_light')).borderRadius(14)
      }.padding({left:18,right:18,top:18,bottom:18}).alignItems(HorizontalAlign.Center)
    }
    .width('92%').height(250).clip(true)
    .borderRadius({topLeft:22,topRight:22,bottomLeft:7,bottomRight:22}).border({width:1,color:$r('app.color.border_accent_green')}).shadow({radius:24,color:'#10000000',offsetX:0,offsetY:8}).margin({bottom:12})
  }

  @Builder miniCardsRow() {
    Row() {
      this.miniCard('专注度', '#4BA8FF', 0, '↑')
      this.miniCard('情绪', '#A878FF', 1, '↑')
      this.miniCard('活跃度', '#FFB84D', 2, '—')
    }.width('92%').justifyContent(FlexAlign.SpaceBetween).margin({bottom:12})
  }
  @Builder miniCard(label: string, color: string, kind: number, trend: string) {
    Column() {
      Text(label).fontSize(10).fontColor($r('app.color.text_tertiary')).margin({bottom:6})
      Row() {
        // 在 @Builder 内通过方法引用 @State，ArkUI 保证跟踪刷新
        Text(this.connected ? (this.contactLost ? '--' : this.miniVal(kind).toString() + '%') : '--')
          .fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.contactLost?$r('app.color.text_muted'):$r('app.color.text_primary')).fontFamily('monospace')
        Text(trend).fontSize(12).fontWeight(FontWeight.Bold)
          .fontColor(trend === '↑' ? $r('app.color.primary') : (trend === '↓' ? $r('app.color.error') : $r('app.color.text_secondary')))
          .margin({left:6})
      }
    }.width('30%').padding({top:14,bottom:14}).backgroundColor($r('app.color.card_bg'))
    .borderRadius({topLeft:16,topRight:16,bottomLeft:5,bottomRight:16})
    .border({width:1,color:$r('app.color.card_border')}).alignItems(HorizontalAlign.Center)
  }
  private miniVal(kind: number): number {
    if (kind === 0) return this.attention;
    if (kind === 1) return Math.round((this.attention + this.meditation) / 2);
    return Math.round(this.attention * 0.7 + this.meditation * 0.3);
  }

  @Builder aiAnalysisCard() {
    Row() { Stack(){Circle().width(36).height(36).fill($r('app.color.secondary_light'));Text('AI').fontSize(12).fontWeight(FontWeight.Bold).fontColor($r('app.color.secondary'))}.margin({right:12})
      Column(){Text('AI 脑波助手').fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Text(this.connected ? (this.contactLost ? '未检测到电极信号，请佩戴设备' : this.getAiStatus()) : '等待设备连接，暂无数据').fontSize(11).fontColor($r('app.color.text_secondary')).margin({top:2})
        Text(this.connected ? (this.contactLost ? '电极接触正常后自动开始分析' : this.getAiTip()) : '连接设备后自动开始分析').fontSize(11).fontColor($r('app.color.text_tertiary')).margin({top:2})
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Text('〉').fontSize(16).fontColor($r('app.color.text_muted'))
    }.width('92%').padding({left:14,right:14,top:12,bottom:12}).backgroundColor($r('app.color.secondary_light')).borderRadius({topLeft:16,topRight:16,bottomLeft:5,bottomRight:16}).border({width:1,color:$r('app.color.secondary_light')}).margin({bottom:12})
  }

  private getAiStatus(): string {
    if (this.attention >= 70) return '当前状态：高度专注，脑波活跃';
    if (this.attention >= 40) return '当前状态：注意力集中，Alpha 波稳定';
    if (this.attention >= 20) return '当前状态：注意力偏低，建议调整';
    return '当前状态：正在采集，数据积累中';
  }
  private getAiTip(): string {
    if (this.attention >= 70) return '建议：保持当前节奏，效果最佳';
    if (this.attention >= 40) return '建议：继续保持当前节奏';
    if (this.attention >= 20) return '建议：短暂休息后重新聚焦';
    return '建议：放松身心，等待数据稳定';
  }

  @Builder gaugeSection() {
    Row() {
      this.gaugeAttCard()
      this.gaugeMedCard()
    }.width('92%').justifyContent(FlexAlign.SpaceBetween).margin({bottom:12})
  }
  @Builder gaugeAttCard() {
    Column() {
      Stack() {
        Circle().width(130).height(130).fill('#00000000').stroke($r('app.color.gauge_track')).strokeWidth(8)
        Circle().width(130).height(130).fill('#00000000').stroke('#4BA8FF').strokeWidth(8)
          .strokeDashArray([Math.PI * 110 * Math.min(Math.max(this.attention, 0), 100) / 100, Math.PI * 110])
          .strokeLineCap(LineCapStyle.Round).shadow({ radius: 8, color: '#4BA8FF40', offsetX: 0, offsetY: 0 })
        Column() {
          Text(this.connected ? this.attention.toString() : '--')
            .fontSize(40).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).fontFamily('monospace')
          Text('/100').fontSize(11).fontColor($r('app.color.text_tertiary'))
        }
      }
      Text('专注度').fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).margin({ top: 14 })
    }.width('48.5%').padding({top:20,bottom:18}).backgroundColor($r('app.color.card_bg'))
    .borderRadius({topLeft:18,topRight:18,bottomLeft:6,bottomRight:18})
    .border({width:1,color:$r('app.color.card_border')}).alignItems(HorizontalAlign.Center)
  }
  @Builder gaugeMedCard() {
    Column() {
      Stack() {
        Circle().width(130).height(130).fill('#00000000').stroke($r('app.color.gauge_track')).strokeWidth(8)
        Circle().width(130).height(130).fill('#00000000').stroke('#A878FF').strokeWidth(8)
          .strokeDashArray([Math.PI * 110 * Math.min(Math.max(this.meditation, 0), 100) / 100, Math.PI * 110])
          .strokeLineCap(LineCapStyle.Round).shadow({ radius: 8, color: '#A878FF40', offsetX: 0, offsetY: 0 })
        Column() {
          Text(this.connected ? this.meditation.toString() : '--')
            .fontSize(40).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).fontFamily('monospace')
          Text('/100').fontSize(11).fontColor($r('app.color.text_tertiary'))
        }
      }
      Text('冥想度').fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).margin({ top: 14 })
    }.width('48.5%').padding({top:20,bottom:18}).backgroundColor($r('app.color.card_bg'))
    .borderRadius({topLeft:18,topRight:18,bottomLeft:6,bottomRight:18})
    .border({width:1,color:$r('app.color.card_border')}).alignItems(HorizontalAlign.Center)
  }

  @Builder chartCard(title:string,badge:string,badgeColor:string,height:number,canvasCtx:CanvasRenderingContext2D,onReadyAction:()=>void) {
    Column() { Row(){Text(title).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'));Row(){Circle().width(4).height(4).fill(badgeColor);Text(badge).fontSize(10).fontColor(badgeColor).margin({left:4})}.padding({left:8,right:8,top:2,bottom:2}).backgroundColor(badgeColor+'12').borderRadius(6).margin({left:8})}.width('100%').padding({left:14,right:14,top:12,bottom:6})
      Canvas(canvasCtx).width('100%').height(height).onReady(onReadyAction)
    }.width('92%').backgroundColor($r('app.color.card_bg')).borderRadius({topLeft:18,topRight:18,bottomLeft:6,bottomRight:18}).border({width:1,color:$r('app.color.card_border')}).margin({bottom:12})
  }

  @Builder trendSection() {
    Column() {
      Row() { Text('专注 & 冥想 趋势').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')); Row(){Circle().width(4).height(4).fill($r('app.color.secondary'));Text('实时').fontSize(10).fontColor($r('app.color.secondary')).margin({left:4})}.padding({left:8,right:8,top:2,bottom:2}).backgroundColor($r('app.color.secondary_light')).borderRadius(6).margin({left:8}); Blank(); Text('专注 '+this.attention.toString()).fontSize(11).fontWeight(FontWeight.Bold).fontColor($r('app.color.secondary')).fontFamily('monospace'); Text(' · ').fontSize(11).fontColor($r('app.color.text_muted')); Text('冥想 '+this.meditation.toString()).fontSize(11).fontWeight(FontWeight.Bold).fontColor($r('app.color.accent')).fontFamily('monospace') }.width('100%').padding({left:14,right:14,top:12,bottom:6})
      Canvas(this.trendCtx).width('100%').height(200).onReady(()=>{this.trendReady=true;this.drawTrendChart()})
    }.width('92%').backgroundColor($r('app.color.card_bg')).borderRadius({topLeft:18,topRight:18,bottomLeft:6,bottomRight:18}).border({width:1,color:$r('app.color.card_border')}).margin({bottom:12})
  }

  @Builder rawWaveSection() { this.chartCard('原始脑波','实时监测','#4BA8FF',200,this.waveCtx,()=>{this.waveReady=true;this.drawWaveChart()}) }
  @Builder spectrumSection() { this.chartCard('频段能量分布','频谱','#A878FF',440,this.spectrumCtx,()=>{this.spectrumReady=true;this.drawSpectrumChart()}) }
  @Builder bandTrendSection() { this.chartCard('波段趋势','60s','#FFB84D',200,this.bandTrendCtx,()=>{this.bandTrendReady=true;this.drawBandTrendChart()}) }

  private drawTrendChart(): void { drawTrend(this.trendCtx, this.trendHistory, this.trendCtx.width, this.trendCtx.height, this.darkModeOn===1?'#0F1419':undefined) }
  private drawWaveChart(): void { drawWave(this.waveCtx, this.rawPreview, this.waveCtx.width, this.waveCtx.height, this.darkModeOn===1?'#0F1419':undefined, this.darkModeOn===1) }
  private drawSpectrumChart(): void { drawSpectrum(this.spectrumCtx, this.bandPower, this.spectrumCtx.width, this.spectrumCtx.height, this.darkModeOn===1?'#0F1419':undefined) }
  private drawBandTrendChart(): void { drawBandTrend(this.bandTrendCtx, this.bandHistory, this.bandTrendCtx.width, this.bandTrendCtx.height, this.darkModeOn===1?'#0F1419':undefined) }
}
