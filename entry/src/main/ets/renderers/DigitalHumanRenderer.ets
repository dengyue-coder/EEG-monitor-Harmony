import { EmotionKind, getEmotionDisplay } from '../utils/EEGConstants';

export function drawDigitalHuman(
  ctx: CanvasRenderingContext2D,
  w: number, h: number,
  att: number, med: number, sig: number,
  emo: EmotionKind, blink: number, t: number
): void {
  ctx.clearRect(0, 0, w, h);
  ctx.fillStyle = '#F5F6FA';
  ctx.fillRect(0, 0, w, h);

  const cx = w / 2;
  const cy = h / 2 - 10;
  const R = Math.min(w, h) * 0.28;
  const emoDisp = getEmotionDisplay(emo);
  const emoClr = emoDisp.color;

  // ---- 呼吸光晕 ----
  const breath = 0.5 + 0.5 * Math.sin(t * 0.8);
  const auraSize = R * (1.35 + breath * 0.25);
  const auraAlpha = 0.08 + breath * 0.06 + (med / 100) * 0.10;
  const aura = ctx.createRadialGradient(cx, cy, R * 0.9, cx, cy, auraSize);
  aura.addColorStop(0, emoClr + Math.floor(auraAlpha * 255).toString(16).padStart(2, '0'));
  aura.addColorStop(1, 'rgba(255,255,255,0)');
  ctx.fillStyle = aura;
  ctx.beginPath();
  ctx.arc(cx, cy, auraSize, 0, Math.PI * 2);
  ctx.fill();

  // ---- 信号质量外环 ----
  const ringR = R * 1.18;
  ctx.strokeStyle = signalRingColor(sig);
  ctx.lineWidth = 3;
  ctx.beginPath();
  const ringLen = signalRingLen(sig);
  ctx.arc(cx, cy, ringR, -Math.PI / 2, -Math.PI / 2 + ringLen * Math.PI * 2);
  ctx.stroke();

  // ---- 脸 ----
  const faceGrad = ctx.createRadialGradient(cx - R * 0.2, cy - R * 0.25, R * 0.05, cx, cy, R);
  faceGrad.addColorStop(0, '#FFFEFC');
  faceGrad.addColorStop(0.55, '#FEF0DC');
  faceGrad.addColorStop(1, '#F2D8B4');
  ctx.fillStyle = faceGrad;
  ctx.beginPath();
  ctx.arc(cx, cy, R, 0, Math.PI * 2);
  ctx.fill();
  ctx.strokeStyle = '#E0C8A8';
  ctx.lineWidth = 2;
  ctx.stroke();

  // ---- 耳朵 ----
  ctx.fillStyle = '#FDE8CC';
  const earW = R * 0.22;
  const earH = R * 0.35;
  ctx.beginPath();
  ctx.ellipse(cx - R * 0.92, cy - R * 0.05, earW, earH, -0.15, 0, Math.PI * 2);
  ctx.fill();
  ctx.beginPath();
  ctx.ellipse(cx + R * 0.92, cy - R * 0.05, earW, earH, 0.15, 0, Math.PI * 2);
  ctx.fill();

  // ---- 眉毛 ----
  const browY = cy - R * 0.32;
  const browW = R * 0.28;
  ctx.strokeStyle = '#6B5A4E';
  ctx.lineWidth = 2.8;
  ctx.lineCap = 'round';
  const leftBx = cx - R * 0.38;
  const rightBx = cx + R * 0.38;
  if (emo === EmotionKind.ANGRY) {
    drawLine(ctx, leftBx - browW, browY + 6, leftBx + browW, browY - 6);
    drawLine(ctx, rightBx - browW, browY - 6, rightBx + browW, browY + 6);
  } else if (emo === EmotionKind.SAD || emo === EmotionKind.ANXIOUS) {
    drawLine(ctx, leftBx - browW, browY, leftBx + browW, browY + 5);
    drawLine(ctx, rightBx - browW, browY + 5, rightBx + browW, browY);
  } else if (emo === EmotionKind.HAPPY || emo === EmotionKind.EXCITED) {
    const lift = emo === EmotionKind.EXCITED ? 8 : 4;
    drawLine(ctx, leftBx - browW, browY + lift, leftBx + browW, browY - lift);
    drawLine(ctx, rightBx - browW, browY - lift, rightBx + browW, browY + lift);
  } else {
    drawLine(ctx, leftBx - browW, browY + 1, leftBx + browW, browY - 1);
    drawLine(ctx, rightBx - browW, browY - 1, rightBx + browW, browY + 1);
  }

  // ---- 眼睛 ----
  const eyeY = cy - R * 0.1;
  const eyeW = R * 0.24;
  const eyeH = R * 0.16;
  drawEnhancedEye(ctx, cx - R * 0.35, eyeY, eyeW, eyeH, emo, att, blink);
  drawEnhancedEye(ctx, cx + R * 0.35, eyeY, eyeW, eyeH, emo, att, blink);

  // ---- 鼻子 ----
  ctx.strokeStyle = '#D4B896';
  ctx.lineWidth = 1.5;
  ctx.lineCap = 'round';
  ctx.beginPath();
  ctx.moveTo(cx, cy + R * 0.04);
  ctx.quadraticCurveTo(cx + R * 0.06, cy + R * 0.14, cx + R * 0.03, cy + R * 0.16);
  ctx.stroke();
  ctx.beginPath();
  ctx.moveTo(cx + R * 0.03, cy + R * 0.16);
  ctx.quadraticCurveTo(cx + R * 0.06, cy + R * 0.19, cx + R * 0.01, cy + R * 0.19);
  ctx.stroke();

  // ---- 嘴巴 ----
  const mouthY = cy + R * 0.33;
  const mouthW = R * 0.35;
  drawEnhancedMouth(ctx, cx, mouthY, mouthW, emo);

  // ---- 腮红 ----
  if (emo === EmotionKind.HAPPY || emo === EmotionKind.EXCITED || emo === EmotionKind.RELAXED) {
    const blushAlpha = emo === EmotionKind.EXCITED ? 0.25 : 0.14;
    ctx.globalAlpha = blushAlpha;
    ctx.fillStyle = '#FFA0A0';
    const by = cy + R * 0.08;
    ctx.beginPath();
    ctx.ellipse(cx - R * 0.55, by, R * 0.15, R * 0.09, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.beginPath();
    ctx.ellipse(cx + R * 0.55, by, R * 0.15, R * 0.09, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.globalAlpha = 1;
  }

  // ---- 汗水滴 (紧张/焦虑) ----
  if (emo === EmotionKind.ANXIOUS || emo === EmotionKind.ANGRY) {
    ctx.fillStyle = '#74B9FF60';
    const sx = cx + R * 0.7;
    const sy = cy - R * 0.75;
    ctx.beginPath();
    ctx.moveTo(sx, sy + R * 0.2);
    ctx.quadraticCurveTo(sx - R * 0.1, sy + R * 0.1, sx, sy);
    ctx.quadraticCurveTo(sx + R * 0.1, sy + R * 0.1, sx, sy + R * 0.2);
    ctx.fill();
  }

  // ---- 头顶数据标签 ----
  ctx.fillStyle = '#7B8FA1';
  ctx.font = 'bold 11px monospace';
  ctx.textAlign = 'center';
  ctx.fillText(`专注 ${att}`, cx - R * 0.6, cy - R * 1.3);
  ctx.fillText(`冥想 ${med}`, cx + R * 0.6, cy - R * 1.3);

  // ---- 底部设备信息 ----
  ctx.fillStyle = signalRingColor(sig);
  ctx.font = '10px sans-serif';
  ctx.textAlign = 'center';
  const sigLabel = sig === 0 ? '信号优秀' : sig < 50 ? '信号良好' : sig < 100 ? '信号一般' : sig < 200 ? '信号较差' : '未接触';
  ctx.fillText(sigLabel, cx, cy + R * 1.35);
}

// ===== 增强版眼睛 =====

function drawEnhancedEye(
  ctx: CanvasRenderingContext2D,
  ex: number, ey: number, ew: number, eh: number,
  emo: EmotionKind, att: number, blink: number
): void {
  // 眨眼缩放
  const blinkScale = 1 - blink * 0.95;
  const curEh = eh * blinkScale;

  // 眼白
  ctx.fillStyle = '#FFFFFF';
  ctx.strokeStyle = '#C8B898';
  ctx.lineWidth = 1.3;
  ctx.beginPath();
  ctx.ellipse(ex, ey, ew, curEh, 0, 0, Math.PI * 2);
  ctx.fill();
  if (blinkScale > 0.05) ctx.stroke();

  if (blinkScale < 0.1) return; // 闭眼时跳过内部

  // 虹膜
  const irisR = eh * 0.55;
  const irisColors: string[] = [
    '#6DB38A', // HAPPY
    '#5DAE8B', // RELAXED
    '#3A6FB5', // FOCUSED
    '#E89040', // EXCITED
    '#8B9DC3', // ANXIOUS
    '#7E8C9E', // SAD
    '#C0392B', // ANGRY
    '#8B929A', // TIRED
    '#6B7D8E'  // NEUTRAL
  ];
  const irisGrad = ctx.createRadialGradient(ex - irisR * 0.2, ey - irisR * 0.2, irisR * 0.1, ex, ey, irisR);
  const irisClr = irisColors[emo] ?? '#6B7D8E';
  irisGrad.addColorStop(0, irisClr);
  irisGrad.addColorStop(1, '#1A1A2E');
  ctx.fillStyle = irisGrad;
  ctx.beginPath();
  ctx.arc(ex, ey, irisR, 0, Math.PI * 2);
  ctx.fill();

  // 瞳孔 (专注度越高瞳孔越小)
  const pupilBase = irisR * 0.48;
  const pupilVary = att / 100 * irisR * 0.18;
  const pupilR = pupilBase - pupilVary;
  ctx.fillStyle = '#0A0A14';
  ctx.beginPath();
  ctx.arc(ex, ey, pupilR, 0, Math.PI * 2);
  ctx.fill();

  // 高光
  ctx.fillStyle = '#FFFFFF';
  ctx.beginPath();
  ctx.arc(ex - pupilR * 0.4, ey - pupilR * 0.45, pupilR * 0.4, 0, Math.PI * 2);
  ctx.fill();
}

// ===== 增强版嘴巴 =====

function drawEnhancedMouth(
  ctx: CanvasRenderingContext2D,
  mx: number, my: number, mw: number, emo: EmotionKind
): void {
  ctx.lineCap = 'round';

  if (emo === EmotionKind.HAPPY) {
    ctx.fillStyle = '#E8786A';
    ctx.strokeStyle = '#D06055';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.arc(mx, my - mw * 0.2, mw * 0.65, 0.1, Math.PI - 0.1);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
  } else if (emo === EmotionKind.EXCITED) {
    ctx.fillStyle = '#E86050';
    ctx.strokeStyle = '#C05040';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.arc(mx, my - mw * 0.25, mw * 0.75, 0.1, Math.PI - 0.1);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
    // 牙齿
    ctx.fillStyle = '#FFFFFF';
    ctx.beginPath();
    ctx.moveTo(mx - mw * 0.35, my - mw * 0.25);
    ctx.lineTo(mx - mw * 0.15, my + mw * 0.05);
    ctx.lineTo(mx + mw * 0.15, my + mw * 0.05);
    ctx.lineTo(mx + mw * 0.35, my - mw * 0.25);
    ctx.closePath();
    ctx.fill();
  } else if (emo === EmotionKind.SAD || emo === EmotionKind.TIRED) {
    ctx.strokeStyle = '#C08070';
    ctx.lineWidth = 2.2;
    ctx.beginPath();
    ctx.arc(mx, my + mw * 0.4, mw * 0.5, Math.PI + 0.3, Math.PI * 2 - 0.3);
    ctx.stroke();
  } else if (emo === EmotionKind.ANGRY) {
    ctx.strokeStyle = '#C07060';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(mx - mw * 0.45, my);
    ctx.lineTo(mx + mw * 0.45, my - 2);
    ctx.stroke();
  } else if (emo === EmotionKind.ANXIOUS) {
    ctx.strokeStyle = '#C09085';
    ctx.lineWidth = 1.8;
    // 锯齿状小嘴
    ctx.beginPath();
    ctx.moveTo(mx - mw * 0.35, my - 2);
    ctx.lineTo(mx - mw * 0.12, my + 2);
    ctx.lineTo(mx + mw * 0.12, my - 1);
    ctx.lineTo(mx + mw * 0.35, my + 2);
    ctx.stroke();
  } else {
    // 中性 - 微弧线
    ctx.strokeStyle = '#C09080';
    ctx.lineWidth = 1.8;
    ctx.beginPath();
    ctx.arc(mx, my + 1, mw * 0.42, 0.08, Math.PI - 0.08);
    ctx.stroke();
  }
}

// ===== 辅助 =====

function drawLine(ctx: CanvasRenderingContext2D, x1: number, y1: number, x2: number, y2: number): void {
  ctx.beginPath();
  ctx.moveTo(x1, y1);
  ctx.lineTo(x2, y2);
  ctx.stroke();
}

function signalRingColor(sig: number): string {
  if (sig === 0) return '#6CBE8A';
  if (sig < 50) return '#6CBE8A';
  if (sig < 100) return '#F5A623';
  if (sig < 200) return '#E87461';
  return '#95A5A6';
}

function signalRingLen(sig: number): number {
  if (sig === 0) return 0.92;
  if (sig < 50) return 0.78;
  if (sig < 100) return 0.50;
  if (sig < 200) return 0.30;
  return 0.15;
}
