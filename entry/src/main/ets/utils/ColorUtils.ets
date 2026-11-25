export function hexToRgba(hex: string, alpha: number): string {
  const r = parseInt(hex.slice(1, 3), 16);
  const g = parseInt(hex.slice(3, 5), 16);
  const b = parseInt(hex.slice(5, 7), 16);
  return `rgba(${r},${g},${b},${alpha})`;
}

export function hsla(h: number, s: number, l: number, a: number): string {
  const c = (1 - Math.abs(2 * l - 1)) * s;
  const hp = (h / 60) % 6;
  const x = c * (1 - Math.abs((hp % 2) - 1));
  const m = l - c / 2;
  let r = 0, g = 0, b = 0;
  if (hp < 1) { r = c; g = x; }
  else if (hp < 2) { r = x; g = c; }
  else if (hp < 3) { g = c; b = x; }
  else if (hp < 4) { g = x; b = c; }
  else if (hp < 5) { r = x; b = c; }
  else { r = c; b = x; }
  const R = Math.round((r + m) * 255);
  const G = Math.round((g + m) * 255);
  const B = Math.round((b + m) * 255);
  return 'rgba(' + R.toString() + ',' + G.toString() + ',' + B.toString() + ',' + a.toString() + ')';
}

export const BAND_COLORS: string[] = [
  '#6CBE8A', '#74B9FF', '#F5A623', '#E87461',
  '#A29BFE', '#FD79A8', '#00CEC9', '#FDCB6E'
];

export function bandColor(idx: number): string {
  return BAND_COLORS[idx] || '#95A5A6';
}

export function signalColor(sig: number): string {
  if (sig === 0) return '#6CBE8A';
  if (sig < 50) return '#6CBE8A';
  if (sig < 100) return '#F5A623';
  if (sig < 200) return '#E87461';
  return '#95A5A6';
}
