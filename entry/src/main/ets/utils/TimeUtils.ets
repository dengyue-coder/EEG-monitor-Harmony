export function formatTime(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  const ds = Math.floor((seconds % 1) * 10);
  const mm = m < 10 ? '0' + m : m.toString();
  const ss = s < 10 ? '0' + s : s.toString();
  return mm + ':' + ss + '.' + ds.toString();
}

export function getSignalText(sig: number): string {
  if (sig === 0) return '优秀';
  if (sig < 50) return '良好';
  if (sig < 100) return '一般';
  if (sig < 200) return '较差';
  if (sig === 200) return '等待接触';
  return '未知';
}
