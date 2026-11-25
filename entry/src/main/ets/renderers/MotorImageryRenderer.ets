export function drawBrain(
  ctx: CanvasRenderingContext2D,
  leftPower: number,
  rightPower: number,
  state: number,
  confidence: number,
  width: number,
  height: number,
  bgColor?: string
): void {
  ctx.clearRect(0, 0, width, height);

  const cx = width / 2;
  const cy = height / 2;
  const hemiR = Math.min(width * 0.22, height * 0.32);
  const gap = hemiR * 0.25;
  const leftCx = cx - hemiR - gap / 2;
  const rightCx = cx + hemiR + gap / 2;

  // 背景
  ctx.fillStyle = bgColor || '#F5F6FA';
  ctx.fillRect(0, 0, width, height);

  // 左半球辉光
  if (leftPower > 10) {
    const lg = ctx.createRadialGradient(leftCx, cy, hemiR * 0.4, leftCx, cy, hemiR * 1.6);
    lg.addColorStop(0, `rgba(108,190,138,${leftPower / 200})`);
    lg.addColorStop(1, 'rgba(108,190,138,0)');
    ctx.fillStyle = lg;
    ctx.beginPath();
    ctx.arc(leftCx, cy, hemiR * 1.6, 0, Math.PI * 2);
    ctx.fill();
  }

  // 右半球辉光
  if (rightPower > 10) {
    const rg = ctx.createRadialGradient(rightCx, cy, hemiR * 0.4, rightCx, cy, hemiR * 1.6);
    rg.addColorStop(0, `rgba(116,185,255,${rightPower / 200})`);
    rg.addColorStop(1, 'rgba(116,185,255,0)');
    ctx.fillStyle = rg;
    ctx.beginPath();
    ctx.arc(rightCx, cy, hemiR * 1.6, 0, Math.PI * 2);
    ctx.fill();
  }

  // 左半球
  const leftGrad = ctx.createLinearGradient(leftCx - hemiR, cy - hemiR, leftCx + hemiR, cy + hemiR);
  const leftIntensity = leftPower / 100;
  leftGrad.addColorStop(0, `rgb(${Math.round(80 + 28 * leftIntensity)},${Math.round(150 + 40 * leftIntensity)},${Math.round(120 + 18 * leftIntensity)})`);
  leftGrad.addColorStop(1, `rgb(${Math.round(60 + 48 * leftIntensity)},${Math.round(120 + 70 * leftIntensity)},${Math.round(100 + 38 * leftIntensity)})`);
  ctx.fillStyle = leftGrad;
  ctx.beginPath();
  ctx.arc(leftCx, cy, hemiR, 0, Math.PI * 2);
  ctx.fill();
  ctx.strokeStyle = leftPower > 50 ? '#6CBE8A' : '#C8D6CF';
  ctx.lineWidth = leftPower > 50 ? 2.5 : 1;
  ctx.stroke();

  // 右半球
  const rightGrad = ctx.createLinearGradient(rightCx - hemiR, cy - hemiR, rightCx + hemiR, cy + hemiR);
  const rightIntensity = rightPower / 100;
  rightGrad.addColorStop(0, `rgb(${Math.round(90 + 26 * rightIntensity)},${Math.round(140 + 45 * rightIntensity)},${Math.round(200 + 55 * rightIntensity)})`);
  rightGrad.addColorStop(1, `rgb(${Math.round(70 + 46 * rightIntensity)},${Math.round(110 + 75 * rightIntensity)},${Math.round(170 + 85 * rightIntensity)})`);
  ctx.fillStyle = rightGrad;
  ctx.beginPath();
  ctx.arc(rightCx, cy, hemiR, 0, Math.PI * 2);
  ctx.fill();
  ctx.strokeStyle = rightPower > 50 ? '#74B9FF' : '#C8D3E0';
  ctx.lineWidth = rightPower > 50 ? 2.5 : 1;
  ctx.stroke();

  // 胼胝体（桥接）
  ctx.fillStyle = '#D0D8E0';
  ctx.fillRect(leftCx + hemiR - 4, cy - 3, rightCx - leftCx - 2 * hemiR + 8, 6);
  ctx.fillStyle = '#B0B8C0';
  ctx.beginPath();
  ctx.arc(cx, cy, 5, 0, Math.PI * 2);
  ctx.fill();

  // 左标签
  ctx.fillStyle = '#5A6D7E';
  ctx.font = '11px sans-serif';
  ctx.textAlign = 'center';
  ctx.fillText('左脑', leftCx, cy + hemiR + 18);
  ctx.fillText(`${leftPower}%`, leftCx, cy + hemiR + 33);

  // 右标签
  ctx.fillText('右脑', rightCx, cy + hemiR + 18);
  ctx.fillText(`${rightPower}%`, rightCx, cy + hemiR + 33);

  // 中央分类标签
  const label = state === 0 ? '休息' : state === 1 ? '← 左手' : '右手 →';
  const labelColor = state === 0 ? '#95A5A6' : state === 1 ? '#6CBE8A' : '#74B9FF';
  ctx.fillStyle = labelColor;
  ctx.font = 'bold 14px sans-serif';
  ctx.fillText(label, cx, cy + 4);

  // 置信度环
  ctx.strokeStyle = labelColor;
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.arc(cx, cy - 30, 20, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * confidence / 100);
  ctx.stroke();
  ctx.fillStyle = '#5A6D7E';
  ctx.font = '9px sans-serif';
  ctx.fillText(`${confidence}%`, cx, cy - 30 + 3);
}

function drawRoundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number): void {
  ctx.moveTo(x + r, y);
  ctx.lineTo(x + w - r, y);
  ctx.arcTo(x + w, y, x + w, y + r, r);
  ctx.lineTo(x + w, y + h - r);
  ctx.arcTo(x + w, y + h, x + w - r, y + h, r);
  ctx.lineTo(x + r, y + h);
  ctx.arcTo(x, y + h, x, y + h - r, r);
  ctx.lineTo(x, y + r);
  ctx.arcTo(x, y, x + r, y, r);
  ctx.closePath();
}

export function drawMIBandBars(
  ctx: CanvasRenderingContext2D,
  bandLabels: string[],
  bandValues: number[],
  bandColors: string[],
  width: number,
  height: number,
  bgColor?: string
): void {
  ctx.clearRect(0, 0, width, height);
  ctx.fillStyle = bgColor || '#F8F9FB';
  ctx.fillRect(0, 0, width, height);

  const barH = 18;
  const gap = 10;
  const leftW = 36;
  const totalH = bandLabels.length * (barH + gap);
  const startY = (height - totalH) / 2;
  const maxW = width - leftW - 50;

  for (let i = 0; i < bandLabels.length; i++) {
    const y = startY + i * (barH + gap);
    const v = Math.min(1, bandValues[i] / 200);

    ctx.fillStyle = '#5A6D7E';
    ctx.font = '10px sans-serif';
    ctx.textAlign = 'right';
    ctx.fillText(bandLabels[i], leftW - 4, y + barH / 2 + 3);

    ctx.fillStyle = '#E8ECF0';
    ctx.beginPath();
    drawRoundRect(ctx, leftW + 4, y, maxW, barH, barH / 2);
    ctx.fill();

    if (v > 0.01) {
      ctx.fillStyle = bandColors[i];
      ctx.beginPath();
      drawRoundRect(ctx, leftW + 4, y, maxW * v, barH, barH / 2);
      ctx.fill();
    }

    ctx.fillStyle = '#5A6D7E';
    ctx.font = '9px sans-serif';
    ctx.textAlign = 'left';
    ctx.fillText(bandValues[i].toFixed(0), leftW + maxW + 8, y + barH / 2 + 3);
  }
}
