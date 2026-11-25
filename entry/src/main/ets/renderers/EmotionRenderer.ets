import { EmotionKind, getEmotionDisplay } from '../utils/EEGConstants';
import { VAPoint, QUADS } from '../detectors/EmotionDetector';

// ===== 动态情绪面孔 =====

export function drawEmotionFace(
  ctx: CanvasRenderingContext2D,
  emo: EmotionKind,
  v: number,
  a: number,
  w: number,
  h: number,
  bgColor?: string
): void {
  ctx.clearRect(0, 0, w, h);

  const cx = w / 2;
  const cy = h / 2;
  const faceR = Math.min(w, h) * 0.32;
  const clr = getEmotionDisplay(emo).color;
  const intensity = (v + a) / 200;

  // 背景
  ctx.fillStyle = bgColor || '#F5F6FA';
  ctx.fillRect(0, 0, w, h);

  // 外光晕
  const glow = ctx.createRadialGradient(cx, cy, faceR * 0.85, cx, cy, faceR * 1.5);
  glow.addColorStop(0, clr + '30');
  glow.addColorStop(1, 'rgba(255,255,255,0)');
  ctx.fillStyle = glow;
  ctx.beginPath();
  ctx.arc(cx, cy, faceR * 1.5, 0, Math.PI * 2);
  ctx.fill();

  // 脸
  const faceGrad = ctx.createRadialGradient(cx - faceR * 0.2, cy - faceR * 0.2, faceR * 0.1, cx, cy, faceR);
  faceGrad.addColorStop(0, '#FFFEFA');
  faceGrad.addColorStop(0.7, '#FDEBD0');
  faceGrad.addColorStop(1, '#F5D5A0');
  ctx.fillStyle = faceGrad;
  ctx.beginPath();
  ctx.arc(cx, cy, faceR, 0, Math.PI * 2);
  ctx.fill();
  ctx.strokeStyle = '#E8D5C0';
  ctx.lineWidth = 1.5;
  ctx.stroke();

  // 眼睛 (基于情绪)
  const eyeY = cy - faceR * 0.2;
  const leftEyeX = cx - faceR * 0.32;
  const rightEyeX = cx + faceR * 0.32;
  const eyeW = faceR * 0.22;
  const eyeH = faceR * 0.14;

  drawEye(ctx, leftEyeX, eyeY, eyeW, eyeH, emo, intensity);
  drawEye(ctx, rightEyeX, eyeY, eyeW, eyeH, emo, intensity);

  // 眉毛
  ctx.strokeStyle = '#8B7355';
  ctx.lineWidth = 2.5;
  ctx.lineCap = 'round';
  const browY = eyeY - eyeH - 6;
  if (emo === EmotionKind.ANGRY) {
    // 愤怒：内低外高斜眉
    drawBrow(ctx, leftEyeX - eyeW * 0.8, browY + 4, leftEyeX + eyeW * 0.8, browY - 6);
    drawBrow(ctx, rightEyeX - eyeW * 0.8, browY - 6, rightEyeX + eyeW * 0.8, browY + 4);
  } else if (emo === EmotionKind.SAD || emo === EmotionKind.ANXIOUS) {
    // 悲伤/焦虑：内高外低
    drawBrow(ctx, leftEyeX - eyeW * 0.8, browY - 2, leftEyeX + eyeW * 0.8, browY + 3);
    drawBrow(ctx, rightEyeX - eyeW * 0.8, browY + 3, rightEyeX + eyeW * 0.8, browY - 2);
  } else {
    // 正常：略弯
    drawBrow(ctx, leftEyeX - eyeW * 0.8, browY, leftEyeX + eyeW * 0.8, browY);
    drawBrow(ctx, rightEyeX - eyeW * 0.8, browY, rightEyeX + eyeW * 0.8, browY);
  }

  // 嘴巴
  const mouthY = cy + faceR * 0.38;
  drawMouth(ctx, cx, mouthY, faceR * 0.28, emo, intensity);

  // 腮红
  if (emo === EmotionKind.HAPPY || emo === EmotionKind.EXCITED) {
    ctx.globalAlpha = 0.18 + intensity * 0.15;
    ctx.fillStyle = '#FF9999';
    ctx.beginPath();
    ctx.ellipse(leftEyeX - faceR * 0.08, eyeY + faceR * 0.22, faceR * 0.15, faceR * 0.1, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.beginPath();
    ctx.ellipse(rightEyeX + faceR * 0.08, eyeY + faceR * 0.22, faceR * 0.15, faceR * 0.1, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.globalAlpha = 1;
  }
}

function drawBrow(ctx: CanvasRenderingContext2D, x1: number, y1: number, x2: number, y2: number): void {
  ctx.beginPath();
  ctx.moveTo(x1, y1);
  ctx.lineTo(x2, y2);
  ctx.stroke();
}

function drawEye(
  ctx: CanvasRenderingContext2D,
  ex: number, ey: number, ew: number, eh: number,
  emo: EmotionKind, intensity: number
): void {
  // 眼白
  ctx.fillStyle = '#FFFFFF';
  ctx.beginPath();
  ctx.ellipse(ex, ey, ew, eh, 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.strokeStyle = '#C0B090';
  ctx.lineWidth = 1;
  ctx.stroke();

  // 瞳孔
  const pupilR = eh * 0.45;
  ctx.fillStyle = '#3A2A1A';
  ctx.beginPath();
  ctx.arc(ex, ey, pupilR, 0, Math.PI * 2);
  ctx.fill();

  // 高光
  ctx.fillStyle = '#FFFFFF';
  ctx.beginPath();
  ctx.arc(ex - pupilR * 0.35, ey - pupilR * 0.35, pupilR * 0.35, 0, Math.PI * 2);
  ctx.fill();

  // 眼皮/眼形覆盖
  if (emo === EmotionKind.HAPPY || emo === EmotionKind.EXCITED) {
    // 笑眼：下弧遮住下半
    ctx.fillStyle = '#FDEBD0';
    ctx.beginPath();
    ctx.ellipse(ex, ey + eh * 0.55, ew * 1.1, eh * 0.7, 0, Math.PI, Math.PI * 2);
    ctx.fill();
  } else if (emo === EmotionKind.SAD || emo === EmotionKind.TIRED) {
    // 下垂眼：上弧遮住上半部分
    ctx.fillStyle = '#FDEBD0';
    ctx.beginPath();
    ctx.ellipse(ex, ey - eh * 0.4, ew * 1.1, eh * 0.6, 0, 0, Math.PI);
    ctx.fill();
  } else if (emo === EmotionKind.ANGRY) {
    // 怒眼：斜线遮角
    ctx.fillStyle = '#FDEBD0';
    ctx.beginPath();
    ctx.moveTo(ex - ew * 1.1, ey - eh);
    ctx.lineTo(ex + ew * 1.1, ey + eh * 0.3);
    ctx.lineTo(ex + ew * 1.1, ey - eh);
    ctx.closePath();
    ctx.fill();
  }
}

function drawMouth(
  ctx: CanvasRenderingContext2D,
  mx: number, my: number, mw: number,
  emo: EmotionKind, intensity: number
): void {
  ctx.strokeStyle = '#C08070';
  ctx.lineWidth = 2.5;
  ctx.lineCap = 'round';

  if (emo === EmotionKind.HAPPY || emo === EmotionKind.EXCITED) {
    // 微笑/大笑
    const h = emo === EmotionKind.EXCITED ? mw * 0.55 : mw * 0.35;
    ctx.fillStyle = '#E07060';
    ctx.beginPath();
    ctx.arc(mx, my - h * 0.3, mw * 0.75, 0.15, Math.PI - 0.15);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
    // 牙齿线（大笑时）
    if (emo === EmotionKind.EXCITED) {
      ctx.strokeStyle = '#FFFFFF';
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(mx - mw * 0.4, my - h * 0.1);
      ctx.lineTo(mx + mw * 0.4, my - h * 0.1);
      ctx.stroke();
      ctx.strokeStyle = '#C08070';
      ctx.lineWidth = 2.5;
    }
  } else if (emo === EmotionKind.SAD || emo === EmotionKind.TIRED) {
    // 下弯
    ctx.beginPath();
    ctx.arc(mx, my + mw * 0.3, mw * 0.55, Math.PI + 0.25, Math.PI * 2 - 0.25);
    ctx.stroke();
  } else if (emo === EmotionKind.ANGRY) {
    // 小直线（紧闭）
    ctx.beginPath();
    ctx.moveTo(mx - mw * 0.4, my);
    ctx.lineTo(mx + mw * 0.4, my);
    ctx.stroke();
  } else if (emo === EmotionKind.ANXIOUS) {
    // 略微下弯的小嘴
    ctx.beginPath();
    ctx.arc(mx, my + mw * 0.15, mw * 0.4, Math.PI + 0.15, Math.PI * 2 - 0.15);
    ctx.stroke();
  } else {
    // 中性：直线
    ctx.beginPath();
    ctx.moveTo(mx - mw * 0.35, my);
    ctx.lineTo(mx + mw * 0.35, my);
    ctx.stroke();
  }
}

// ===== 六轴情绪脑波雷达图 =====

const RADAR_LABELS: string[] = ['Delta', 'Theta', 'Alpha', 'Beta', 'Gamma', 'Att'];
const RADAR_COLOR: string = '#6CBE8A';

export function drawEmotionRadar(
  ctx: CanvasRenderingContext2D,
  values: number[],
  att: number,
  w: number,
  h: number,
  bgColor?: string
): void {
  ctx.clearRect(0, 0, w, h);

  const n = 6;
  const cx = w / 2;
  const cy = h / 2 - 4;
  const maxR = Math.min(cx, cy) - 28;
  const isDark = bgColor !== undefined && bgColor !== '#FFFFFF' && bgColor !== '#F8F9FB';

  // 不填背景色（让 Stack 下层的图片透过来），深色模式下网格线用半透白
  if (isDark) {
    ctx.strokeStyle = 'rgba(255,255,255,0.28)';
  } else {
    ctx.fillStyle = bgColor || '#F8F9FB';
    ctx.fillRect(0, 0, w, h);
    ctx.strokeStyle = '#C8CDD4';
  }
  // 环形虚线
  ctx.lineWidth = 1;
  ctx.setLineDash([6, 4]);
  for (let ring = 1; ring <= 4; ring++) {
    const r = (maxR / 4) * ring;
    ctx.beginPath();
    for (let i = 0; i < n; i++) {
      const angle = (Math.PI * 2 / n) * i - Math.PI / 2;
      const x = cx + r * Math.cos(angle);
      const y = cy + r * Math.sin(angle);
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    }
    ctx.closePath();
    ctx.stroke();
  }
  ctx.setLineDash([]);

  // 轴线
  ctx.strokeStyle = isDark ? 'rgba(255,255,255,0.20)' : '#B0B8C4';
  ctx.lineWidth = 1;
  for (let i = 0; i < n; i++) {
    const angle = (Math.PI * 2 / n) * i - Math.PI / 2;
    ctx.beginPath();
    ctx.moveTo(cx, cy);
    ctx.lineTo(cx + maxR * Math.cos(angle), cy + maxR * Math.sin(angle));
    ctx.stroke();
  }

  // 数据多边形填充
  const maxVal = 200;
  ctx.fillStyle = '#6CBE8A' + '30';
  ctx.strokeStyle = '#6CBE8A';
  ctx.lineWidth = 2;
  ctx.beginPath();
  for (let i = 0; i < n; i++) {
    const angle = (Math.PI * 2 / n) * i - Math.PI / 2;
    const val = Math.min(values[i], maxVal);
    const r = (val / maxVal) * maxR;
    const x = cx + r * Math.cos(angle);
    const y = cy + r * Math.sin(angle);
    if (i === 0) ctx.moveTo(x, y);
    else ctx.lineTo(x, y);
  }
  ctx.closePath();
  ctx.fill();
  ctx.stroke();

  // 数据点
  for (let i = 0; i < n; i++) {
    const angle = (Math.PI * 2 / n) * i - Math.PI / 2;
    const val = Math.min(values[i], maxVal);
    const r = (val / maxVal) * maxR;
    ctx.fillStyle = '#6CBE8A';
    ctx.beginPath();
    ctx.arc(cx + r * Math.cos(angle), cy + r * Math.sin(angle), 4, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = '#FFFFFF';
    ctx.beginPath();
    ctx.arc(cx + r * Math.cos(angle), cy + r * Math.sin(angle), 2, 0, Math.PI * 2);
    ctx.fill();
  }

  // 标签
  ctx.fillStyle = isDark ? 'rgba(255,255,255,0.7)' : '#4A5568';
  ctx.font = 'bold 13px sans-serif';
  ctx.textAlign = 'center';
  for (let i = 0; i < n; i++) {
    const angle = (Math.PI * 2 / n) * i - Math.PI / 2;
    const lx = cx + (maxR + 18) * Math.cos(angle);
    const ly = cy + (maxR + 18) * Math.sin(angle) + 4;
    ctx.fillText(RADAR_LABELS[i], lx, ly);
  }

  // 中心专注度
  ctx.fillStyle = '#2C3E50';
  ctx.font = 'bold 16px sans-serif';
  ctx.textAlign = 'center';
  ctx.fillText(att.toString(), cx, cy + 4);
  ctx.fillStyle = '#7B8FA1';
  ctx.font = '9px sans-serif';
  ctx.fillText('专注度', cx, cy - 10);
}

export function drawVA(
  ctx: CanvasRenderingContext2D,
  trail: VAPoint[],
  v: number,
  a: number,
  emo: EmotionKind,
  w: number,
  h: number
): void {
  const p = 38;
  const cw = w - p * 2;
  const ch = h - p * 2;
  const ox = p;
  const oy = p + ch;

  ctx.clearRect(0, 0, w, h);

  // 象限底色（加粗边框 + 更明显底色）
  for (const q of QUADS) {
    ctx.fillStyle = q.color + '30';
    const qx = ox + (q.x - 0.25) * cw;
    const qy = oy - (q.y + 0.25) * ch;
    ctx.fillRect(qx, qy, cw * 0.5, ch * 0.5);
    // 象限分割虚线
    ctx.strokeStyle = q.color + '50';
    ctx.lineWidth = 1;
    ctx.setLineDash([5, 8]);
    ctx.strokeRect(qx, qy, cw * 0.5, ch * 0.5);
    ctx.setLineDash([]);
  }

  // 网格虚线
  ctx.strokeStyle = '#C8CDD4';
  ctx.lineWidth = 0.8;
  ctx.setLineDash([4, 6]);
  for (let i = 1; i < 4; i++) {
    const x = ox + (cw / 4) * i;
    const y = oy - (ch / 4) * i;
    ctx.beginPath(); ctx.moveTo(x, oy - ch); ctx.lineTo(x, oy); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(ox, y); ctx.lineTo(ox + cw, y); ctx.stroke();
  }
  ctx.setLineDash([]);

  // 十字中轴（更粗更深）
  ctx.strokeStyle = '#8B95A5';
  ctx.lineWidth = 2;
  ctx.beginPath(); ctx.moveTo(ox + cw / 2, oy - ch); ctx.lineTo(ox + cw / 2, oy); ctx.stroke();
  ctx.beginPath(); ctx.moveTo(ox, oy - ch / 2); ctx.lineTo(ox + cw, oy - ch / 2); ctx.stroke();

  // 中心原点（加大）
  ctx.fillStyle = '#7B8695';
  ctx.beginPath(); ctx.arc(ox + cw / 2, oy - ch / 2, 5, 0, Math.PI * 2); ctx.fill();
  ctx.fillStyle = '#FFF';
  ctx.beginPath(); ctx.arc(ox + cw / 2, oy - ch / 2, 2.5, 0, Math.PI * 2); ctx.fill();

  // 刻度值（加大加粗加深）
  ctx.fillStyle = '#5A6470';
  ctx.font = 'bold 12px monospace';
  ctx.textAlign = 'center';
  for (let i = 0; i <= 4; i++) {
    ctx.fillText(`${i * 25}`, ox + (cw / 4) * i, oy + 16);
  }
  ctx.textAlign = 'right';
  for (let i = 0; i <= 4; i++) {
    ctx.fillText(`${i * 25}`, ox - 8, oy - (ch / 4) * i + 4);
  }

  // 轴标签（加大）
  ctx.fillStyle = '#4A5568';
  ctx.font = 'bold 14px sans-serif';
  ctx.textAlign = 'center';
  ctx.fillText('Valence  →', ox + cw / 2, oy + 34);
  ctx.save();
  ctx.translate(12, oy - ch / 2);
  ctx.rotate(-Math.PI / 2);
  ctx.textAlign = 'center';
  ctx.fillText('Arousal  →', 0, 0);
  ctx.restore();

  // 象限标签（更醒目）
  ctx.font = 'bold 13px sans-serif';
  for (const q of QUADS) {
    const tagW = q.label.length * 13;
    const tagX = ox + q.x * cw;
    const tagY = oy - q.y * ch - 10;
    // 标签背景
    ctx.fillStyle = q.color + '35';
    const bgW = tagW + 16;
    ctx.beginPath();
    ctx.moveTo(tagX - bgW / 2 + 6, tagY - 14);
    ctx.lineTo(tagX + bgW / 2 - 6, tagY - 14);
    ctx.arcTo(tagX + bgW / 2, tagY - 14, tagX + bgW / 2, tagY + 4, 6);
    ctx.arcTo(tagX + bgW / 2, tagY + 4, tagX + bgW / 2 - 6, tagY + 4, 6);
    ctx.lineTo(tagX - bgW / 2 + 6, tagY + 4);
    ctx.arcTo(tagX - bgW / 2, tagY + 4, tagX - bgW / 2, tagY - 14, 6);
    ctx.arcTo(tagX - bgW / 2, tagY - 14, tagX - bgW / 2 + 6, tagY - 14, 6);
    ctx.closePath();
    ctx.fill();
    // 标签文字
    ctx.fillStyle = q.color;
    ctx.textAlign = 'center';
    ctx.fillText(q.label, tagX, tagY);
  }

  // 轨迹线（更粗更亮）
  if (trail.length > 1) {
    ctx.lineWidth = 3.5;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    for (let i = 1; i < trail.length; i++) {
      const pt = trail[i];
      const pr = trail[i - 1];
      const alpha = 0.35 + (i / trail.length) * 0.55;
      ctx.strokeStyle = `rgba(74,144,217,${alpha.toFixed(2)})`;
      ctx.beginPath();
      ctx.moveTo(ox + (pr.v / 100) * cw, oy - (pr.a / 100) * ch);
      ctx.lineTo(ox + (pt.v / 100) * cw, oy - (pt.a / 100) * ch);
      ctx.stroke();
    }
  }

  // 当前位置光点
  const cx = ox + (v / 100) * cw;
  const cy = oy - (a / 100) * ch;
  const clr = getEmotionDisplay(emo).color;

  // 外发光
  const g = ctx.createRadialGradient(cx, cy, 4, cx, cy, 20);
  g.addColorStop(0, clr);
  g.addColorStop(1, 'rgba(255,255,255,0)');
  ctx.fillStyle = g;
  ctx.beginPath(); ctx.arc(cx, cy, 20, 0, Math.PI * 2); ctx.fill();

  // 主圆点
  ctx.fillStyle = clr;
  ctx.beginPath(); ctx.arc(cx, cy, 6, 0, Math.PI * 2); ctx.fill();
  ctx.strokeStyle = '#FFF';
  ctx.lineWidth = 2;
  ctx.stroke();

  // 中心白点
  ctx.fillStyle = '#FFF';
  ctx.beginPath(); ctx.arc(cx, cy, 2.5, 0, Math.PI * 2); ctx.fill();
}

export function drawTL(
  ctx: CanvasRenderingContext2D,
  tline: EmotionKind[],
  w: number,
  h: number
): void {
  ctx.clearRect(0, 0, w, h);
  const n = tline.length;
  if (n < 2) return;
  const barH = h - 10;
  const barW = (w - 12) / n;

  for (let i = 0; i < n; i++) {
    ctx.fillStyle = getEmotionDisplay(tline[i]).color;
    ctx.fillRect(6 + i * barW, 5, Math.max(2, barW - 1), barH);
  }
  ctx.strokeStyle = '#E0E4E8';
  ctx.lineWidth = 0.5;
  ctx.strokeRect(6, 5, w - 12, barH);
}
