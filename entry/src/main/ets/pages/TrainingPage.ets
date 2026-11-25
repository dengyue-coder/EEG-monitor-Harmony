import { EEGDataStore } from '../store/EEGDataStore';
import { shuffleGrid } from '../utils/MathUtils';
import { hsla } from '../utils/ColorUtils';
import { formatTime, getSignalText } from '../utils/TimeUtils';
import { signalColor } from '../utils/ColorUtils';
import { StorageService } from '../service/StorageService';

const store = EEGDataStore.getInstance();

@Component
export struct TrainingPage {
  @State modeIdx: number = 0;
  @StorageProp('dark_mode_on') darkModeOn: number = 0;
  @State grid: number[] = shuffleGrid();
  @State schulteNext: number = 1;
  @State schulteSeconds: number = 0;
  @State schulteErrors: number = 0;
  @State schulteDone: boolean = false;
  @State schulteBest: number = 999;
  @State schulteAvgAtt: number = 0;
  @State endAttention: number = 0;
  @State endSeconds: number = 0;
  @State endBest: number = 0;
  @State endActive: boolean = false;
  @State ballAtt: number = 0;
  @State ballMed: number = 0;
  @State ballAlpha: number = 0;
  @State ballBeta: number = 0;
  private ballCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D();
  private ballReady: boolean = false;
  private ballTimer: number = -1;
  private smoothBallY: number = 200;
  private smoothBallR: number = 30;
  private smoothHue: number = 60;
  private trailPoints: number[][] = [];
  @State signalText: string = '未连接';
  @State signalColor: string = '#95A5A6';
  private totalAttSamples: number = 0;
  private attSampleCount: number = 0;
  private unsub: (() => void) | null = null;

  aboutToAppear(): void {
    const ss = StorageService.getInstance();
    this.schulteBest = ss.getNumber('schulte_best', 999);
    this.endBest = ss.getNumber('endurance_best', 0);
    this.unsub = store.subscribe(() => { this.onPoll(); });
  }
  aboutToDisappear(): void {
    if (this.unsub) { this.unsub(); this.unsub = null; }
    if (this.ballTimer >= 0) { clearInterval(this.ballTimer); this.ballTimer = -1; }
  }

  private onPoll(): void {
    this.signalText = getSignalText(store.latestData.sig);
    this.signalColor = signalColor(store.latestData.sig);
    const att = store.latestData.att; const med = store.latestData.med;
    if (!this.schulteDone && this.schulteNext > 1) { this.schulteSeconds += 0.05; this.totalAttSamples += att; this.attSampleCount++; }
    if (this.endActive && att >= 60) { this.endSeconds += 0.05; }
    this.endAttention = att;
    this.ballAtt = this.ballAtt * 0.85 + att * 0.15;
    this.ballMed = this.ballMed * 0.85 + med * 0.15;
    this.ballAlpha = this.ballAlpha * 0.85 + (store.latestData.aL + store.latestData.aH) * 0.15;
    this.ballBeta = this.ballBeta * 0.85 + (store.latestData.bL + store.latestData.bH) * 0.15;
  }

  build() {
    Column() { Scroll() { Column() {
      this.focusCockpit(); this.modeSelector(); this.focusInstrument();
      if (this.modeIdx === 0) { this.schulteCabin(); }
      else if (this.modeIdx === 1) { this.enduranceCabin(); }
      else { this.neuroBallCabin(); }
    }.width('100%').alignItems(HorizontalAlign.Center).padding({ top: 8, bottom: 24 }) }
    .layoutWeight(1).scrollBar(BarState.Off) }
    .width('100%').height('100%').linearGradient({
      direction: GradientDirection.Bottom,
      colors: [[$r('app.color.page_bg_gradient_top'), 0.0], [$r('app.color.page_bg_gradient_mid'), 0.5], [$r('app.color.page_bg_gradient_bottom'), 1.0]]
    })
  }

  // ===== 状态驾驶舱 =====
  @Builder focusCockpit() {
    Row() {
      Stack() { Circle().width(38).height(38).fill('rgba(69,230,165,0.08)'); Circle().width(10).height(10).fill(this.signalColor).shadow({radius:5,color:this.signalColor+'40',offsetX:0,offsetY:0}); Circle().width(18).height(18).fill('#00000000').stroke('rgba(69,230,165,0.2)').strokeWidth(1) }
      Column() { Text('Neuro Focus Lab').fontSize(15).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')); Text('Lv.'+this.getLevel().toString()+' · '+this.signalText).fontSize(10).fontColor($r('app.color.text_tertiary')).margin({top:1}) }.alignItems(HorizontalAlign.Start).margin({left:10})
      Blank()
      Column() { Text(this.getTodaySummary()).fontSize(10).fontColor('#45E6A5').fontFamily('monospace'); Text('今日训练').fontSize(8).fontColor($r('app.color.text_tertiary')) }.alignItems(HorizontalAlign.Center).margin({right:12})
      Column() { Text(this.schulteBest<999?formatTime(this.schulteBest):'--').fontSize(15).fontWeight(FontWeight.Bold).fontColor('#FFB84D').fontFamily('monospace'); Text('最佳').fontSize(8).fontColor($r('app.color.text_tertiary')) }.alignItems(HorizontalAlign.Center)
    }.width('92%').padding({left:14,right:14,top:10,bottom:10}).linearGradient({angle:145,colors:[['rgba(255,255,255,0.05)',0.0],['rgba(255,255,255,0.0)',0.35]]}).backgroundColor($r('app.color.card_bg')).borderRadius(24).border({width:1,color:$r('app.color.card_border')}).margin({bottom:10})
  }

  private getTodaySummary(): string { return this.endBest>0?(this.endBest+'s'):'未训练' }
  private getLevel(): number { if(this.schulteBest<=40||this.endBest>=180)return 5; if(this.schulteBest<=60||this.endBest>=120)return 4; if(this.schulteBest<=90||this.endBest>=60)return 3; if(this.schulteBest<999)return 2; return 1 }

  // ===== 模式选择器 =====
  @Builder modeSelector() {
    Row() {
      this.modePill('⊞ 视觉搜索', 0)
      this.modePill('◎ 持续专注', 1)
      this.modePill('◉ 神经反馈', 2)
    }.width('92%').backgroundColor('rgba(255,255,255,0.02)').borderRadius(16).border({width:1,color:$r('app.color.card_border')}).padding(4).margin({bottom:10})
  }
  @Builder modePill(label:string, idx:number) {
    Text(label).fontSize(12).fontColor(this.modeIdx===idx?'#080D18':$r('app.color.text_secondary')).fontWeight(this.modeIdx===idx?FontWeight.Medium:FontWeight.Normal).padding({top:12,bottom:12}).layoutWeight(1).textAlign(TextAlign.Center).backgroundColor(this.modeIdx===idx?'#45E6A5':'#00000000').borderRadius(13).onClick(()=>{this.modeIdx=idx})
  }

  // ===== 专注神经仪（核心视觉，模式0和1共用）=====
  @Builder focusInstrument() {
    Stack() {
      Image($r('app.media.bg_focus_lab')).width('100%').height('100%').objectFit(ImageFit.Cover)
      Column().width('100%').height(220).backgroundColor('rgba(6,14,31,0.55)').borderRadius(24)
      Circle({width:160,height:160}).fill('#00000000').stroke('rgba(69,230,165,0.10)').strokeWidth(1).strokeDashArray([3,18]).position({x:'50%',y:'50%'}).translate({x:'-80vp',y:'-80vp'})
      Circle({width:130,height:130}).fill('#00000000').stroke('rgba(77,163,255,0.12)').strokeWidth(0.5).position({x:'50%',y:'50%'}).translate({x:'-65vp',y:'-65vp'})
      // 中心数值
      Column() {
        Text(store.latestData.att.toString()).fontSize(52).fontWeight(FontWeight.Bold).fontColor('#45E6A5').fontFamily('monospace').shadow({radius:12,color:'#4045E6A5',offsetX:0,offsetY:0})
        Text('专注指数').fontSize(10).fontColor($r('app.color.text_tertiary')).margin({top:2})
      }.position({x:'50%',y:'50%'}).translate({x:'-50%',y:'-50%'})
      // 四角数据浮层
      Column() { Text('α').fontSize(11).fontWeight(FontWeight.Bold).fontColor('#8B7CFF'); Text(Math.round(this.ballAlpha).toString()).fontSize(14).fontColor($r('app.color.text_primary')).fontFamily('monospace'); Text('稳定度').fontSize(7).fontColor($r('app.color.text_tertiary')) }.alignItems(HorizontalAlign.Center).position({x:'18%',y:'20%'})
      Column() { Text('β').fontSize(11).fontWeight(FontWeight.Bold).fontColor('#4DA3FF'); Text(Math.round(this.ballBeta).toString()).fontSize(14).fontColor($r('app.color.text_primary')).fontFamily('monospace'); Text('活跃度').fontSize(7).fontColor($r('app.color.text_tertiary')) }.alignItems(HorizontalAlign.Center).position({x:'72%',y:'20%'})
      Column() { Text('冥想度').fontSize(10).fontWeight(FontWeight.Bold).fontColor('#A878FF'); Text(Math.round(this.ballMed).toString()).fontSize(14).fontColor($r('app.color.text_secondary')).fontFamily('monospace'); Text('放松').fontSize(7).fontColor($r('app.color.text_tertiary')) }.alignItems(HorizontalAlign.Center).position({x:'22%',y:'72%'})
      Column() { Text('疲劳').fontSize(10).fontWeight(FontWeight.Bold).fontColor(this.endAttention<30?'#FF6675':'#45E6A5'); Text(this.endAttention<30?'偏高':'正常').fontSize(12).fontColor($r('app.color.text_primary')); Text('状态').fontSize(7).fontColor($r('app.color.text_tertiary')) }.alignItems(HorizontalAlign.Center).position({x:'68%',y:'72%'})
      Text('专注神经仪').fontSize(10).fontColor('#45E6A5').padding({left:8,right:8,top:2,bottom:2}).backgroundColor('rgba(69,230,165,0.06)').borderRadius(8).position({x:'50%',y:12}).translate({x:'-50%'})
    }.width('92%').height(220).clip(true).borderRadius(24).border({width:1,color:$r('app.color.card_border')}).margin({bottom:10})
  }

  // ===== 舒尔特训练舱 =====
  @Builder schulteCabin() {
    Column() {
      // 训练状态条
      Row() {
        Text(this.schulteDone?'✅ 完成':'🎯 寻找 '+this.schulteNext.toString()).fontSize(14).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
        Blank()
        Text(formatTime(this.schulteSeconds)).fontSize(22).fontColor('#45E6A5').fontFamily('monospace').fontWeight(FontWeight.Bold)
      }.width('92%').margin({bottom:6})
      Row() {
        Text('错误 '+this.schulteErrors.toString()).fontSize(11).fontColor('#FF6675').padding({left:10,right:10,top:3,bottom:3}).backgroundColor($r('app.color.error_light')).borderRadius(8)
        Text('最佳 '+ (this.schulteBest<999?formatTime(this.schulteBest):'--')).fontSize(11).fontColor('#45E6A5').padding({left:10,right:10,top:3,bottom:3}).backgroundColor($r('app.color.primary_light')).borderRadius(8).margin({left:8})
        Blank()
        Text('准确率 '+(this.schulteNext>1?Math.round((this.schulteNext-1)/(this.schulteNext-1+this.schulteErrors)*100):100).toString()+'%').fontSize(10).fontColor($r('app.color.text_secondary'))
      }.width('92%').margin({bottom:8})
      // 方格
      Grid() {
        ForEach(this.grid, (num:number)=>{ GridItem() { Button(num.toString()).width('100%').height('100%').fontSize(18).fontWeight(FontWeight.Bold).backgroundColor(num<this.schulteNext?$r('app.color.schulte_cell_done_bg'):$r('app.color.card_bg_strong')).fontColor(num<this.schulteNext?$r('app.color.schulte_cell_done_text'):$r('app.color.schulte_cell_text')).borderRadius(10).border({width:1,color:num<this.schulteNext?$r('app.color.schulte_cell_done_border'):$r('app.color.schulte_cell_border')}).onClick(()=>{if(this.schulteDone)return;if(num===1&&this.schulteNext===1)this.startSchulte();if(num===this.schulteNext){this.schulteNext++;if(this.schulteNext>25)this.finishSchulte()}else if(num>this.schulteNext)this.schulteErrors++}) } })
      }.columnsTemplate('1fr 1fr 1fr 1fr 1fr').rowsTemplate('1fr 1fr 1fr 1fr 1fr').columnsGap(6).rowsGap(6).width('92%').height(300).margin({bottom:10})
      if (!this.schulteDone) {
        Button('🔄 重新开始').width(132).height(32).backgroundColor('rgba(69,230,165,0.12)').borderRadius(16)
          .fontSize(11).fontColor('#45E6A5').fontWeight(FontWeight.Medium).margin({ bottom: 6 })
          .onClick(() => { this.resetSchulte(); })
      }
      if (this.schulteDone) { this.schulteResultCard() }
    }.width('100%').alignItems(HorizontalAlign.Center)
  }

  private startSchulte(): void { this.schulteSeconds=0;this.schulteErrors=0;this.schulteDone=false;this.totalAttSamples=0;this.attSampleCount=0 }
  private finishSchulte(): void { this.schulteDone=true;this.schulteAvgAtt=this.attSampleCount>0?this.totalAttSamples/this.attSampleCount:0;if(this.schulteSeconds<this.schulteBest){this.schulteBest=this.schulteSeconds;StorageService.getInstance().setNumber('schulte_best',Math.round(this.schulteSeconds))} }
  private getSchulteGrade(): string { if(this.schulteSeconds<=40)return'S';if(this.schulteSeconds<=60)return'A';if(this.schulteSeconds<=90)return'B';if(this.schulteSeconds<=150)return'C';return'D' }
  private resetSchulte(): void { this.grid=shuffleGrid();this.schulteNext=1;this.schulteSeconds=0;this.schulteErrors=0;this.schulteDone=false;this.totalAttSamples=0;this.attSampleCount=0 }

  @Builder schulteResultCard() {
    Column() {
      Row() {
        Column() { Text('平均专注度').fontSize(10).fontColor($r('app.color.text_tertiary')); Text(Math.round(this.schulteAvgAtt).toString()).fontSize(28).fontWeight(FontWeight.Bold).fontColor('#45E6A5').fontFamily('monospace').margin({top:2}) }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Column() { Text('评级').fontSize(10).fontColor($r('app.color.text_tertiary')); Text(this.getSchulteGrade()+' 级').fontSize(28).fontWeight(FontWeight.Bold).fontColor('#FFB84D').fontFamily('monospace').margin({top:2}) }.alignItems(HorizontalAlign.Center).layoutWeight(1)
      }.width('100%').margin({bottom:10})
      Row() {
        Column() { Text('用时').fontSize(9).fontColor($r('app.color.text_tertiary')); Text(formatTime(this.schulteSeconds)).fontSize(14).fontColor($r('app.color.text_primary')).fontFamily('monospace').margin({top:1}) }.alignItems(HorizontalAlign.Center).layoutWeight(1)
        Column().width(1).height(30).backgroundColor($r('app.color.card_border'))
        Column() { Text('错误').fontSize(9).fontColor($r('app.color.text_tertiary')); Text(this.schulteErrors.toString()).fontSize(14).fontColor('#FF6675').fontFamily('monospace').margin({top:1}) }.alignItems(HorizontalAlign.Center).layoutWeight(1)
        Column().width(1).height(30).backgroundColor($r('app.color.card_border'))
        Column() { Text('最佳').fontSize(9).fontColor($r('app.color.text_tertiary')); Text(this.schulteBest<999?formatTime(this.schulteBest):'--').fontSize(14).fontColor('#FFB84D').fontFamily('monospace').margin({top:1}) }.alignItems(HorizontalAlign.Center).layoutWeight(1)
      }.width('100%')
      Button('重新训练').width('70%').height(38).backgroundColor('#45E6A5').borderRadius(19).fontSize(13).fontColor('#080D18').fontWeight(FontWeight.Bold).shadow({radius:10,color:'#4045E6A5',offsetX:0,offsetY:3}).margin({top:12}).onClick(()=>{this.resetSchulte()})
    }.width('92%').padding(18).linearGradient({angle:145,colors:[['rgba(255,255,255,0.05)',0.0],['rgba(255,255,255,0.0)',0.35]]}).backgroundColor($r('app.color.card_bg')).borderRadius(22).border({width:1,color:$r('app.color.card_border')}).alignItems(HorizontalAlign.Center).margin({bottom:12})
  }

  // ===== 持续专注训练舱 =====
  @Builder enduranceCabin() {
    Column() {
      Stack() {
        Circle().width(200).height(200).fill('#00000000').stroke($r('app.color.endurance_ring_bg')).strokeWidth(7)
        Circle().width(200).height(200).fill('#00000000').stroke($r('app.color.endurance_ring_fill')).strokeWidth(7).strokeDashArray([Math.PI*180*this.endAttention/100,Math.PI*180]).strokeLineCap(LineCapStyle.Round).shadow({radius:8,color:$r('app.color.endurance_ring_glow'),offsetX:0,offsetY:0})
        Column() { Text(this.endAttention.toString()).fontSize(46).fontWeight(FontWeight.Bold).fontColor('#45E6A5').fontFamily('monospace'); Text('/100').fontSize(12).fontColor($r('app.color.text_tertiary')) }
      }.width(200).height(200).margin({top:20,bottom:16})
      Text(formatTime(this.endSeconds)).fontSize(36).fontFamily('monospace').fontColor($r('app.color.text_primary')).fontWeight(FontWeight.Bold).margin({bottom:4})
      Row(){Circle().width(5).height(5).fill(this.endActive?'#45E6A5':$r('app.color.text_muted'));Text(this.endActive?(this.endAttention>=80?'专注稳定·状态极佳':'专注持续中'):'需要专注度≥60').fontSize(11).fontColor($r('app.color.text_tertiary')).margin({left:5})}.margin({bottom:4})
      Text('🏆 最佳 '+formatTime(this.endBest)).fontSize(12).fontColor('#FFB84D').margin({bottom:20})
      Button(this.endActive?'停止':'开始训练').width(180).height(40).backgroundColor(this.endActive?'#FF6675':'#45E6A5').borderRadius(20).fontSize(14).fontColor(this.endActive?$r('app.color.text_primary'):'#080D18').fontWeight(FontWeight.Bold).shadow({radius:10,color:this.endActive?'#40FF6675':'#4045E6A5',offsetX:0,offsetY:3}).onClick(()=>{this.endActive=!this.endActive;if(!this.endActive){if(this.endSeconds>this.endBest){this.endBest=this.endSeconds;StorageService.getInstance().setNumber('endurance_best',Math.round(this.endSeconds))}this.endSeconds=0}}).margin({bottom:20})
    }.width('100%').alignItems(HorizontalAlign.Center)
  }

  // ===== 神经反馈训练舱 =====
  @Builder neuroBallCabin() {
    Column() {
      Row() {
        Column(){Text('专注').fontSize(9).fontColor('#45E6A5');Text(Math.round(this.ballAtt).toString()).fontSize(18).fontWeight(FontWeight.Bold).fontColor('#45E6A5').fontFamily('monospace');Text('高度').fontSize(7).fontColor($r('app.color.text_tertiary'))}.alignItems(HorizontalAlign.Center).width('22%')
        Stack() {
          Circle({width:100,height:100}).fill('#00000000').stroke('rgba(69,230,165,0.10)').strokeWidth(0.5).strokeDashArray([3,12])
          Canvas(this.ballCtx).width(160).height(160).backgroundColor('#00000000').onReady(()=>{this.ballReady=true;this.ballTimer=setInterval(()=>{if(this.ballReady)this.drawBall()},33)})
        }.width('56%')
        Column(){Text('冥想').fontSize(9).fontColor('#8B7CFF');Text(Math.round(this.ballMed).toString()).fontSize(18).fontWeight(FontWeight.Bold).fontColor('#8B7CFF').fontFamily('monospace');Text('大小').fontSize(7).fontColor($r('app.color.text_tertiary'))}.alignItems(HorizontalAlign.Center).width('22%')
      }.width('92%').padding({top:12,bottom:12}).backgroundColor($r('app.color.card_bg')).borderRadius(22).border({width:1,color:$r('app.color.card_border')}).justifyContent(FlexAlign.SpaceEvenly).margin({bottom:8})
      Row() {
        Column(){Text('Alpha').fontSize(9).fontColor('#4DA3FF');Text(Math.round(this.ballAlpha).toString()).fontSize(14).fontColor('#4DA3FF').fontFamily('monospace');Text('偏绿').fontSize(7).fontColor($r('app.color.text_tertiary'))}.alignItems(HorizontalAlign.Center).layoutWeight(1)
        Column(){Text('Beta').fontSize(9).fontColor('#FFB84D');Text(Math.round(this.ballBeta).toString()).fontSize(14).fontColor('#FFB84D').fontFamily('monospace');Text('偏橙').fontSize(7).fontColor($r('app.color.text_tertiary'))}.alignItems(HorizontalAlign.Center).layoutWeight(1)
      }.width('92%').padding({top:10,bottom:10}).backgroundColor($r('app.color.card_bg')).borderRadius(22).border({width:1,color:$r('app.color.card_border')})
      Text('专注度↑小球靠上 · α高偏绿 · β高偏橙').fontSize(10).fontColor($r('app.color.text_tertiary')).margin({top:6})
    }.width('100%').alignItems(HorizontalAlign.Center)
  }

  private drawBall(): void {
    const ctx = this.ballCtx; const w = ctx.width; const h = ctx.height;
    ctx.clearRect(0,0,w,h);
    const targetY = h*0.85-(this.ballAtt/100)*h*0.7;
    this.smoothBallY=this.smoothBallY*0.9+targetY*0.1;
    const targetR=25+(this.ballMed/100)*25;
    this.smoothBallR=this.smoothBallR*0.9+targetR*0.1;
    const abRatio=this.ballAlpha/Math.max(this.ballBeta,1);
    const targetHue=30+Math.max(0,Math.min(1,abRatio/3))*90;
    this.smoothHue=this.smoothHue*0.92+targetHue*0.08;
    const cx=w/2; const cy=this.smoothBallY; const r=this.smoothBallR; const hue=this.smoothHue;
    this.trailPoints.push([cx,cy,r,hue]); if(this.trailPoints.length>20)this.trailPoints.shift();
    for(let i=0;i<this.trailPoints.length;i++){const pt=this.trailPoints[i];const alpha=i/this.trailPoints.length*0.3;ctx.fillStyle=hsla(pt[3],0.7,0.55,alpha);ctx.beginPath();ctx.arc(pt[0],pt[1],pt[2]*0.5,0,Math.PI*2);ctx.fill()}
    const glow=ctx.createRadialGradient(cx,cy,r*0.5,cx,cy,r*2.5);glow.addColorStop(0,hsla(hue,0.8,0.65,0.5));glow.addColorStop(1,hsla(hue,0.8,0.65,0));ctx.fillStyle=glow;
    const ballGrad=ctx.createRadialGradient(cx-r*0.3,cy-r*0.3,r*0.1,cx,cy,r);ballGrad.addColorStop(0,hsla(hue,0.8,0.75,1));ballGrad.addColorStop(0.7,hsla(hue,0.7,0.55,1));ballGrad.addColorStop(1,hsla(hue,0.6,0.35,1));ctx.fillStyle=ballGrad;ctx.beginPath();ctx.arc(cx,cy,r,0,Math.PI*2);ctx.fill();
    ctx.fillStyle='rgba(255,255,255,0.6)';ctx.beginPath();ctx.arc(cx-r*0.3,cy-r*0.35,r*0.2,0,Math.PI*2);ctx.fill();
  }
}
