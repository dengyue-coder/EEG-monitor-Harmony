import { TrendPoint } from '../store/EEGDataStore';

// ============================================================
//  图1: 专注 & 冥想 趋势（干净双折线，零填充）
// ============================================================
export function drawTrend(
  ctx: CanvasRenderingContext2D,
  data: TrendPoint[],
  w: number,
  h: number,
  bgColor?: string
): void {
  if (data.length < 2) return;

  const pTop = 24, pRight = 16, pBottom = 32, pLeft = 36;
  const chartW = w - pLeft - pRight;
  const chartH = h - pTop - pBottom;

  const xFn = (i: number) => pLeft + (i / (data.length - 1)) * chartW;
  const yFn = (v: number) => pTop + chartH - (v / 100) * chartH;

  ctx.clearRect(0, 0, w, h);

  // 水平网格线 + Y轴标签
  ctx.strokeStyle = '#E8ECF0';
  ctx.lineWidth = 0.5;
  ctx.setLineDash([4, 4]);
  const yTicks = [0, 25, 50, 75, 100];
  for (const tick of yTicks) {
    const y = yFn(tick);
    ctx.beginPath();
    ctx.moveTo(pLeft, y);
    ctx.lineTo(pLeft + chartW, y);
    ctx.stroke();
    ctx.fillStyle = '#8E99A4';
    ctx.font = '10px sans-serif';
    ctx.textAlign = 'right';
    ctx.fillText(`${tick}`, pLeft - 8, y + 4);
  }
  ctx.setLineDash([]);

  // 图例（左上角）
  ctx.fillStyle = '#6CBE8A';
  ctx.fillRect(pLeft, 4, 10, 3);
  ctx.fillStyle = '#7B8FA1';
  ctx.font = '10px sans-serif';
  ctx.textAlign = 'left';
  ctx.fillText('专注', pLeft + 14, 10);

  ctx.fillStyle = '#74B9FF';
  ctx.fillRect(pLeft + 52, 4, 10, 3);
  ctx.fillText('冥想', pLeft + 66, 10);

  // 专注折线
  ctx.strokeStyle = '#6CBE8A';
  ctx.lineWidth = 2;
  ctx.lineJoin = 'round';
  ctx.beginPath();
  ctx.moveTo(xFn(0), yFn(data[0].att));
  for (let i = 1; i < data.length; i++) ctx.lineTo(xFn(i), yFn(data[i].att));
  ctx.stroke();

  // 冥想折线
  ctx.strokeStyle = '#74B9FF';
  ctx.beginPath();
  ctx.moveTo(xFn(0), yFn(data[0].med));
  for (let i = 1; i < data.length; i++) ctx.lineTo(xFn(i), yFn(data[i].med));
  ctx.stroke();

  // X轴基线
  ctx.strokeStyle = '#D0D5DD';
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.moveTo(pLeft, pTop + chartH);
  ctx.lineTo(pLeft + chartW, pTop + chartH);
  ctx.stroke();

  // X轴时间刻度（每1秒=10采样点）
  const PTS_PER_SEC = 10;
  const maxIdx = data.length - 1;
  for (let s = 0; s * PTS_PER_SEC <= maxIdx; s += 5) {
    const idx = s * PTS_PER_SEC;
    if (idx > maxIdx) break;
    const x = xFn(idx);
    ctx.strokeStyle = '#C0C8D0';
    ctx.lineWidth = 0.5;
    ctx.beginPath();
    ctx.moveTo(x, pTop + chartH);
    ctx.lineTo(x, pTop + chartH + 5);
    ctx.stroke();
    ctx.fillStyle = '#8E99A4';
    ctx.font = '9px monospace';
    ctx.textAlign = 'center';
    ctx.fillText(`${s}s`, x, pTop + chartH + 18);
  }
}

// ============================================================
//  图2: 原始脑波（医学监护仪风格）
// ============================================================
const WAVE_Y_MAX = 20000;

export function drawWave(
  ctx: CanvasRenderingContext2D,
  data: number[],
  w: number,
  h: number,
  bgColor?: string,
  darkMode?: boolean
): void {
  if (data.length < 2) return;

  const pTop = 12, pRight = 4, pBottom = 24, pLeft = 48;
  const chartW = w - pLeft - pRight;
  const chartH = h - pTop - pBottom;

  const yMid = pTop + chartH / 2;
  const yScale = chartH / (2 * WAVE_Y_MAX);

  const xFn = (i: number) => pLeft + (i / (data.length - 1)) * chartW;
  const yFn = (v: number) => yMid - v * yScale;

  // 背景
  ctx.clearRect(0, 0, w, h);
  ctx.fillStyle = bgColor || '#FAFBFC';
  ctx.fillRect(pLeft, pTop, chartW, chartH);

  const isDark = darkMode === true;
  const gridColor = isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)';
  const lineColor = isDark ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.12)';
  const labelColor = isDark ? 'rgba(255,255,255,0.35)' : 'rgba(0,0,0,0.35)';
  const labelStrong = isDark ? 'rgba(255,255,255,0.55)' : 'rgba(0,0,0,0.55)';

  // 水平网格
  ctx.strokeStyle = gridColor;
  ctx.lineWidth = 0.5;
  for (let i = 1; i < 10; i++) {
    const y = pTop + (chartH / 10) * i;
    ctx.beginPath();
    ctx.moveTo(pLeft, y);
    ctx.lineTo(pLeft + chartW, y);
    ctx.stroke();
  }

  // 垂直网格
  for (let i = 0; i < 10; i++) {
    const x = pLeft + (chartW / 10) * i;
    ctx.beginPath();
    ctx.moveTo(x, pTop);
    ctx.lineTo(x, pTop + chartH);
    ctx.stroke();
  }

  // 零线
  ctx.strokeStyle = lineColor;
  ctx.setLineDash([8, 12]);
  ctx.lineWidth = 0.6;
  ctx.beginPath();
  ctx.moveTo(pLeft, yFn(0));
  ctx.lineTo(pLeft + chartW, yFn(0));
  ctx.stroke();
  ctx.setLineDash([]);

  // 外框
  ctx.strokeStyle = lineColor;
  ctx.lineWidth = 1;
  ctx.strokeRect(pLeft, pTop, chartW, chartH);

  // Y轴标签
  ctx.font = '9px monospace';
  ctx.textAlign = 'right';
  const yLabels = [20000, 10000, 0, -10000, -20000];
  for (const gv of yLabels) {
    const y = yFn(gv);
    ctx.fillStyle = gv === 0 ? labelStrong : labelColor;
    const label = gv === 0 ? '0' : (gv > 0 ? `+${(gv / 1000).toFixed(0)}K` : `${(gv / 1000).toFixed(0)}K`);
    ctx.fillText(label, pLeft - 6, y + 4);
  }

  // 波形
  ctx.strokeStyle = '#1B9C4A';
  ctx.lineWidth = 0.8;
  ctx.lineJoin = 'round';
  ctx.lineCap = 'round';
  ctx.beginPath();
  for (let i = 0; i < data.length; i++) {
    const v = Math.max(-WAVE_Y_MAX, Math.min(WAVE_Y_MAX, data[i]));
    if (i === 0) ctx.moveTo(xFn(i), yFn(v));
    else ctx.lineTo(xFn(i), yFn(v));
  }
  ctx.stroke();

  // 波形辉光
  ctx.strokeStyle = 'rgba(27,156,74,0.10)';
  ctx.lineWidth = 3;
  ctx.beginPath();
  for (let i = 0; i < data.length; i++) {
    const v = Math.max(-WAVE_Y_MAX, Math.min(WAVE_Y_MAX, data[i]));
    if (i === 0) ctx.moveTo(xFn(i), yFn(v));
    else ctx.lineTo(xFn(i), yFn(v));
  }
  ctx.stroke();

  // X轴时间刻度
  const PTS_PER_SEC = 50;
  const maxIdx = data.length - 1;
  ctx.fillStyle = labelColor;
  ctx.font = '8px monospace';
  ctx.textAlign = 'center';
  for (let s = 0; s * PTS_PER_SEC <= maxIdx; s += 2) {
    const idx = s * PTS_PER_SEC;
    if (idx > maxIdx) break;
    const x = xFn(idx);
    ctx.fillText(`${s}s`, x, pTop + chartH + 14);
  }
}

// ============================================================
//  图3: 频段能量分布（垂直柱状图，均衡器风格）
// ============================================================
const BAND_NAMES_SHORT = ['δ', 'θ', 'Lα', 'Hα', 'Lβ', 'Hβ', 'Lγ', 'Mγ'];
const BAND_NAMES_CN   = ['Delta', 'Theta', 'Low α', 'High α', 'Low β', 'High β', 'Low γ', 'Mid γ'];
const BAND_COLORS = [
  '#1A237E',  // Delta  - 深蓝
  '#283593',  // Theta  - 靛蓝
  '#4A90D9',  // Low Alpha - 亮蓝
  '#6CBE8A',  // High Alpha - 绿色
  '#F5A623',  // Low Beta - 橙色
  '#E87461',  // High Beta - 红橙
  '#C544F0',  // Low Gamma - 紫色
  '#E91E63',  // Mid Gamma - 粉红
];
const SPECTRUM_Y_MAX = 1000;

export function drawSpectrum(
  ctx: CanvasRenderingContext2D,
  bandPower: number[],
  w: number,
  h: number,
  bgColor?: string
): void {
  if (bandPower.length < 8) return;

  const pTop = 8, pRight = 14, pBottom = 108, pLeft = 80;
  const chartW = w - pLeft - pRight;
  const chartH = h - pTop - pBottom;
  const barCount = 8;
  const barGap = 8;
  const barW = (chartW - barGap * (barCount + 1)) / barCount;

  ctx.clearRect(0, 0, w, h);

  // 水平网格线
  ctx.strokeStyle = '#E8ECF0';
  ctx.lineWidth = 0.8;
  ctx.setLineDash([6, 6]);
  const gridVals = [0, 250, 500, 750, 1000];
  for (const gv of gridVals) {
    const y = pTop + chartH - (gv / SPECTRUM_Y_MAX) * chartH;
    ctx.beginPath();
    ctx.moveTo(pLeft, y);
    ctx.lineTo(pLeft + chartW, y);
    ctx.stroke();
    ctx.fillStyle = '#4A5568';
    ctx.font = 'bold 24px monospace';
    ctx.textAlign = 'right';
    ctx.fillText(`${gv}`, pLeft - 14, y + 8);
  }
  ctx.setLineDash([]);

  // 绘图柱
  for (let b = 0; b < 8; b++) {
    const val = Math.min(bandPower[b], SPECTRUM_Y_MAX);
    const barH = (val / SPECTRUM_Y_MAX) * chartH;
    const barX = pLeft + barGap + b * (barW + barGap);
    const barY = pTop + chartH - barH;

    // 柱子渐变（从底部到顶部）
    const grad = ctx.createLinearGradient(0, pTop + chartH, 0, barY);
    grad.addColorStop(0, BAND_COLORS[b] + 'CC');
    grad.addColorStop(1, BAND_COLORS[b]);
    ctx.fillStyle = grad;
    ctx.fillRect(barX, barY, barW, barH);

    // 柱子顶部圆角
    ctx.fillStyle = BAND_COLORS[b];
    ctx.beginPath();
    ctx.arc(barX + barW / 2, barY, barW / 2, Math.PI, 0);
    ctx.fill();

    // 数值标注（柱子顶部上方 — 深色加粗大字）
    ctx.fillStyle = '#2D3748';
    ctx.font = 'bold 26px monospace';
    ctx.textAlign = 'center';
    const label = val >= 100 ? val.toFixed(0) : val.toFixed(1);
    ctx.fillText(label, barX + barW / 2, barY - 12);

    // 频段符号（底部第一行 — 希腊字母，加粗大字）
    ctx.fillStyle = '#2D3748';
    ctx.font = 'bold 28px sans-serif';
    ctx.fillText(BAND_NAMES_SHORT[b], barX + barW / 2, pTop + chartH + 32);

    // 频段英文全称（底部第二行）
    ctx.fillStyle = '#6B7785';
    ctx.font = '22px sans-serif';
    ctx.fillText(BAND_NAMES_CN[b], barX + barW / 2, pTop + chartH + 64);
  }

  // X 轴基线
  ctx.strokeStyle = '#D0D5DD';
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.moveTo(pLeft, pTop + chartH);
  ctx.lineTo(pLeft + chartW, pTop + chartH);
  ctx.stroke();
}

// ============================================================
//  图4: 8波段趋势（干净8线，零填充）
// ============================================================

export function drawBandTrend(
  ctx: CanvasRenderingContext2D,
  history: number[][],
  w: number,
  h: number,
  bgColor?: string
): void {
  const maxLen = Math.max(...history.map(a => a.length), 0);
  if (maxLen < 2) return;

  const pTop = 24, pRight = 16, pBottom = 32, pLeft = 38;
  const chartW = w - pLeft - pRight;
  const chartH = h - pTop - pBottom;

  // 计算固定 Y 轴上界：取所有波段数据的95分位，加10%上浮
  let allVals: number[] = [];
  for (let b = 0; b < 8; b++) {
    allVals = allVals.concat(history[b]);
  }
  allVals.sort((a, b) => a - b);
  const p95 = allVals[Math.floor(allVals.length * 0.95)] || 500;
  const yMax = Math.max(50, Math.ceil(p95 * 1.15 / 50) * 50);

  const xFn = (i: number) => pLeft + (i / (maxLen - 1)) * chartW;
  const yFn = (v: number) => pTop + chartH - (v / yMax) * chartH;

  ctx.clearRect(0, 0, w, h);

  // 图例（双行，每行4个）
  ctx.font = '9px sans-serif';
  for (let b = 0; b < 8; b++) {
    const row = b < 4 ? 0 : 1;
    const col = b % 4;
    const lx = pLeft + col * 70;
    const ly = 4 + row * 10;
    ctx.fillStyle = BAND_COLORS[b];
    ctx.fillRect(lx, ly, 10, 2);
    ctx.fillStyle = '#7B8FA1';
    ctx.textAlign = 'left';
    ctx.fillText(BAND_NAMES_SHORT[b], lx + 13, ly + 4);
  }

  // 水平网格线
  ctx.strokeStyle = '#E8ECF0';
  ctx.lineWidth = 0.5;
  ctx.setLineDash([4, 4]);
  const gridCount = 4;
  for (let i = 0; i <= gridCount; i++) {
    const val = (yMax / gridCount) * i;
    const y = yFn(val);
    ctx.beginPath();
    ctx.moveTo(pLeft, y);
    ctx.lineTo(pLeft + chartW, y);
    ctx.stroke();
    ctx.fillStyle = '#8E99A4';
    ctx.font = '9px monospace';
    ctx.textAlign = 'right';
    ctx.fillText(val.toFixed(0), pLeft - 8, y + 4);
  }
  ctx.setLineDash([]);

  // 8条折线（无填充）
  for (let b = 0; b < 8; b++) {
    const pts = history[b];
    if (pts.length < 2) continue;
    ctx.strokeStyle = BAND_COLORS[b];
    ctx.lineWidth = b < 2 ? 1.2 : 0.9; // 低频稍粗
    ctx.lineJoin = 'round';
    ctx.beginPath();
    ctx.moveTo(xFn(0), yFn(pts[0]));
    for (let i = 1; i < pts.length; i++) ctx.lineTo(xFn(i), yFn(pts[i]));
    ctx.stroke();
  }

  // X轴基线
  ctx.strokeStyle = '#D0D5DD';
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.moveTo(pLeft, pTop + chartH);
  ctx.lineTo(pLeft + chartW, pTop + chartH);
  ctx.stroke();

  // X轴时间刻度
  const PTS_PER_SEC = 10;
  const maxIdx = maxLen - 1;
  for (let s = 0; s * PTS_PER_SEC <= maxIdx; s += 5) {
    const idx = s * PTS_PER_SEC;
    if (idx > maxIdx) break;
    const x = xFn(idx);
    ctx.strokeStyle = '#C0C8D0';
    ctx.lineWidth = 0.5;
    ctx.beginPath();
    ctx.moveTo(x, pTop + chartH);
    ctx.lineTo(x, pTop + chartH + 5);
    ctx.stroke();
    ctx.fillStyle = '#8E99A4';
    ctx.font = '9px monospace';
    ctx.textAlign = 'center';
    ctx.fillText(`${s}s`, x, pTop + chartH + 18);
  }
}
