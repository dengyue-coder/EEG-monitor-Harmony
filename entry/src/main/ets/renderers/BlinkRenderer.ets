export function drawBlinkChart(
  ctx: CanvasRenderingContext2D,
  chartData: number[],
  w: number,
  h: number
): void {
  const padL = 32, padR = 12, padT = 10, padB = 24;
  const chartW = w - padL - padR;
  const chartH = h - padT - padB;

  ctx.clearRect(0, 0, w, h);

  const maxVal = Math.max(40, ...chartData);
  const barW = chartW / 10 - 5;

  ctx.fillStyle = '#95A5A6';
  ctx.font = '9px sans-serif';
  ctx.textAlign = 'right';
  const step = Math.ceil(maxVal / 4);
  for (let v = 0; v <= maxVal; v += step) {
    const y = padT + chartH - (v / maxVal) * chartH;
    ctx.fillText(v.toString(), padL - 4, y + 3);
    ctx.strokeStyle = '#F0F0F0';
    ctx.lineWidth = 0.5;
    ctx.beginPath();
    ctx.moveTo(padL, y);
    ctx.lineTo(w - padR, y);
    ctx.stroke();
  }

  const y15 = padT + chartH - (15 / maxVal) * chartH;
  const y20 = padT + chartH - (20 / maxVal) * chartH;
  ctx.strokeStyle = '#B2DFC9';
  ctx.lineWidth = 0.5;
  ctx.setLineDash([4, 4]);
  [y15, y20].forEach(yy => {
    ctx.beginPath();
    ctx.moveTo(padL, yy);
    ctx.lineTo(w - padR, yy);
    ctx.stroke();
  });
  ctx.setLineDash([]);

  for (let i = 0; i < 10; i++) {
    const d = chartData[i];
    const barH = Math.max(2, (d / maxVal) * chartH);
    const x = padL + i * (chartW / 10) + 2;
    const y = padT + chartH - barH;

    let barColor = '#6CBE8A';
    if (d < 5) barColor = '#E74C3C';
    else if (d < 10) barColor = '#F5A623';
    else if (d < 15) barColor = '#F9D423';
    else if (d > 30) barColor = '#E74C3C';
    else if (d > 25) barColor = '#F5A623';
    else if (d > 20) barColor = '#F9D423';

    ctx.fillStyle = barColor;
    ctx.fillRect(x, y, barW, barH);

    const minLabel = 9 - i;
    ctx.fillStyle = '#BDC3C7';
    ctx.font = '8px sans-serif';
    ctx.textAlign = 'center';
    ctx.fillText(minLabel === 0 ? '现在' : `${minLabel}分前`, x + barW / 2, h - 4);
  }
}
