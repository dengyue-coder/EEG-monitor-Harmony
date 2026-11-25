export enum EmotionKind {
  HAPPY, RELAXED, FOCUSED, EXCITED,
  ANXIOUS, SAD, ANGRY, TIRED, NEUTRAL
}

export const BAND_LABELS: string[] = [
  'Delta', 'Theta', 'Low α', 'High α',
  'Low β', 'High β', 'Low γ', 'Mid γ'
];

export class EmotionDisplay {
  name: string; emoji: string; color: string; bg: string; darkBg: string; desc: string;
  encourage: string; blessing: string;
  constructor(n: string, e: string, c: string, b: string, db: string, d: string, ec: string, bl: string) {
    this.name = n; this.emoji = e; this.color = c; this.bg = b; this.darkBg = db;
    this.desc = d; this.encourage = ec; this.blessing = bl;
  }
}

export const EMOTION_DISPLAYS: EmotionDisplay[] = [
  new EmotionDisplay('开心快乐', '😄', '#FF9500', '#FFF8EE', '#2D2010', '愉悦度高 · 精力充沛',
    '你现在的状态非常棒！保持这份好心情，用笑容感染身边的每一个人吧。',
    '愿你今天遇到的每件事都如阳光般温暖，快乐加倍，好运连连！'),
  new EmotionDisplay('放松宁静', '😌', '#6CBE8A', '#F0FAF4', '#1A2820', '内心平静 · 身心舒缓',
    '内心平静是一种难得的力量。此刻的宁静让你更清晰地听见内心的声音。',
    '宁静致远，愿你在这份安然中收获内心的丰盈与满足。'),
  new EmotionDisplay('高度专注', '🎯', '#4A90D9', '#EEF5FC', '#182838', '注意力集中 · 心无旁骛',
    '专注的你正在闪闪发光！这份专注力是你达成目标的最强武器，继续保持！',
    '心之所向，行之所往。专注的每一刻都在为未来的自己铺路。'),
  new EmotionDisplay('兴奋激动', '🤩', '#C544F0', '#F9F0FD', '#2A1838', '高能状态 · 充满热情',
    '你的能量正在爆棚！这种热情和冲劲是创造奇迹的动力，尽情释放吧！',
    '激情点燃灵感，热爱可抵岁月漫长。愿你永远保持这份炙热的心！'),
  new EmotionDisplay('焦虑紧张', '😰', '#F5A623', '#FFF9F0', '#2D2010', '压力较大 · 需要放松',
    '深呼吸，放轻松。紧张和焦虑只是暂时的访客，它们不能定义你。你已经做得很好了。',
    '别着急，慢慢来。真正的强大不是从不紧张，而是紧张时依然能从容前行。'),
  new EmotionDisplay('悲伤低落', '😢', '#7B8FA1', '#F4F6F8', '#1D2228', '情绪低落 · 需要关爱',
    '每个人都会有低落的时刻，这完全没关系。请允许自己感受这份情绪，然后温柔地抱抱自己。',
    '风雨过后总会有彩虹，黑夜再长也挡不住黎明。你比想象中更坚强。'),
  new EmotionDisplay('愤怒烦躁', '😠', '#E74C3C', '#FFF0F0', '#2D1818', '情绪激动 · 需要冷静',
    '先深呼吸三次——愤怒解决不了问题，但冷静可以。给自己十秒钟，让理智回归。',
    '真正的强者不是没有情绪，而是能驾驭情绪。平静下来的你，无所不能。'),
  new EmotionDisplay('疲惫困倦', '😴', '#8E6FAD', '#F6F3FA', '#221D28', '精力不足 · 需要休息',
    '该休息时就好好休息，这不是懈怠，而是为了让自己更好地重新出发。',
    '好好休息也是一种修行。愿你醒来时精神饱满，世界依旧温柔待你。'),
  new EmotionDisplay('平静安稳', '😐', '#95A5A6', '#F8F9FA', '#1D2228', '状态平稳 · 心态平和',
    '平和的心态是最宝贵的财富。不急不躁，从容面对生活中的每一件事。',
    '内心安宁，方能行稳致远。愿这份平静伴你度过充实的一天。')
];

export function getEmotionDisplay(kind: EmotionKind): EmotionDisplay {
  return EMOTION_DISPLAYS[kind] || EMOTION_DISPLAYS[EmotionKind.NEUTRAL];
}
