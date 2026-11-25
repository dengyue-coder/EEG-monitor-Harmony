"""
训练情绪分类 MLP v2 — 改进数据生成，使用实际 V/A 公式约束特征分布
"""
import json
import random
import numpy as np
from pathlib import Path
from collections import Counter

EMOTIONS = ["NEUTRAL","HAPPY","EXCITED","FOCUSED","RELAXED","ANXIOUS","SAD","ANGRY","TIRED"]

# ============================================================
#  改进的数据生成：从 V/A 和实际公式推导带功率
# ============================================================
def generate_sample(label):
    """
    为每个标签生成真实的 (d,t,aL,aH,bL,bH,gL,gM,att,med)
    使用实际 EmotionDetector 公式的反向约束
    """
    att = random.uniform(0, 100)
    med = random.uniform(0, 100)

    if label == 1:  # HAPPY: V>62, A>58
        att = random.uniform(55, 95)
        med = random.uniform(20, 55)
        v = random.uniform(62, 95)
        a = random.uniform(58, 95)
    elif label == 2:  # EXCITED: V>45, A>75
        att = random.uniform(45, 90)
        med = random.uniform(10, 45)
        v = random.uniform(45, 95)
        a = random.uniform(75, 98)
    elif label == 3:  # FOCUSED: att>70, V 35-85, A 25-75
        att = random.uniform(70, 98)
        med = random.uniform(15, 55)
        v = random.uniform(35, 85)
        a = random.uniform(25, 75)
    elif label == 4:  # RELAXED: V>65, A<38
        att = random.uniform(25, 60)
        med = random.uniform(55, 98)
        v = random.uniform(65, 98)
        a = random.uniform(5, 38)
    elif label == 5:  # ANXIOUS: V<38, A>62
        att = random.uniform(30, 70)
        med = random.uniform(5, 38)
        v = random.uniform(2, 38)
        a = random.uniform(62, 98)
    elif label == 6:  # SAD: V<35, A<35
        att = random.uniform(5, 45)
        med = random.uniform(5, 40)
        v = random.uniform(2, 35)
        a = random.uniform(2, 35)
    elif label == 7:  # ANGRY: V<25, A>72
        att = random.uniform(25, 65)
        med = random.uniform(5, 32)
        v = random.uniform(2, 25)
        a = random.uniform(72, 98)
    elif label == 8:  # TIRED: A<22, med>65
        att = random.uniform(2, 45)
        med = random.uniform(65, 98)
        v = random.uniform(10, 55)
        a = random.uniform(2, 35)
    else:  # NEUTRAL (default)
        att = random.uniform(35, 68)
        med = random.uniform(35, 68)
        v = random.uniform(32, 62)
        a = random.uniform(32, 62)

    # ---- 使用实际公式反向推导带功率 ----
    # V 公式: V ≈ 50 + (α/β_ratio - 0.5)*25 + (att-50)*0.3 - (med-50)*0.1
    # A 公式: A ≈ 50 + (β+γ)/(δ+θ)*ratio_adj*20 + (50-med)*0.25

    # 反推 α/β 比值 (影响 V)
    v_from_att_med = (att - 50) * 0.3 - (med - 50) * 0.1
    target_alpha_beta_ratio = (v - 50 - v_from_att_med) / 25 + 0.5
    # EmoDetector uses: ratio = alpha / (beta+gamma+1)
    # simplified as alpha / max(beta+gamma, 1)

    # 反推 (β+γ)/(δ+θ) 比值 (影响 A)
    a_from_med = (50 - med) * 0.25
    target_bg_over_dt = (a - 50 - a_from_med) / 20 + 1.0

    # 生成基础带功率
    alpha = 200 + random.uniform(-60, 60)
    beta_gamma = max(20, alpha / max(target_alpha_beta_ratio, 0.05))
    delta_theta = max(20, beta_gamma / max(target_bg_over_dt, 0.05))

    # 分配到各子带
    total_alpha = alpha + random.uniform(-60, 60)
    total_beta_gamma = beta_gamma + random.uniform(-40, 40)
    total_delta_theta = delta_theta + random.uniform(-50, 50)

    # 类特定特征增强
    if label == 1:  # HAPPY: α↑
        total_alpha *= 1.4
    elif label == 2:  # EXCITED: α↑ β↑ γ↑
        total_alpha *= 1.2
        total_beta_gamma *= 1.5
    elif label == 3:  # FOCUSED: α↑ β↓
        total_alpha *= 1.5
        total_beta_gamma *= 0.6
    elif label == 4:  # RELAXED: α↑ β↓ γ↓
        total_alpha *= 1.6
        total_beta_gamma *= 0.4
    elif label == 5:  # ANXIOUS: β↑ γ↑
        total_alpha *= 0.6
        total_beta_gamma *= 1.7
        total_delta_theta *= 0.7
    elif label == 6:  # SAD: α↓ β↓
        total_alpha *= 0.35
        total_beta_gamma *= 0.3
    elif label == 7:  # ANGRY: β↑↑ γ↑
        total_alpha *= 0.3
        total_beta_gamma *= 2.2
        total_delta_theta *= 0.5
    elif label == 8:  # TIRED: δ↑ θ↑
        total_delta_theta *= 2.2
        total_alpha *= 0.4
        total_beta_gamma *= 0.2

    # 子带拆分
    aL = total_alpha * random.uniform(0.48, 0.62)
    aH = total_alpha - aL
    bg_split = random.uniform(0.38, 0.62)
    bL = total_beta_gamma * bg_split * random.uniform(0.45, 0.60)
    bH = total_beta_gamma * bg_split * random.uniform(0.40, 0.55)
    gL = total_beta_gamma * (1 - bg_split) * random.uniform(0.45, 0.60)
    gM = total_beta_gamma * (1 - bg_split) * random.uniform(0.40, 0.55)
    dt_split = random.uniform(0.45, 0.70)
    d = total_delta_theta * dt_split * random.uniform(0.55, 0.85)
    t = total_delta_theta * dt_split * random.uniform(0.15, 0.45) + total_delta_theta * (1 - dt_split)

    # 加高斯噪声
    d = max(0, min(1000, d + random.gauss(0, 20)))
    t = max(0, min(1000, t + random.gauss(0, 20)))
    aL = max(0, min(1000, aL + random.gauss(0, 15)))
    aH = max(0, min(1000, aH + random.gauss(0, 15)))
    bL = max(0, min(1000, bL + random.gauss(0, 10)))
    bH = max(0, min(1000, bH + random.gauss(0, 10)))
    gL = max(0, min(1000, gL + random.gauss(0, 8)))
    gM = max(0, min(1000, gM + random.gauss(0, 8)))

    return np.array([d, t, aL, aH, bL, bH, gL, gM, att, med], dtype=np.float32)


# ============================================================
#  生成训练数据
# ============================================================
print("正在生成训练数据...")
SAMPLES_PER_CLASS = 1500
TOTAL = SAMPLES_PER_CLASS * 9

X = np.zeros((TOTAL, 10), dtype=np.float32)
Y = np.zeros(TOTAL, dtype=np.int32)

idx = 0
for label in range(9):
    for _ in range(SAMPLES_PER_CLASS):
        X[idx] = generate_sample(label)
        Y[idx] = label
        idx += 1

mean = X.mean(axis=0)
std = X.std(axis=0) + 1e-6
X_norm = (X - mean) / std

print(f"  生成 {TOTAL} 样本")
print(f"  特征均值:  {[f'{m:.0f}' for m in mean]}")
print(f"  特征标准差: {[f'{s:.0f}' for s in std]}")

# ============================================================
#  训练 MLP（更大网络 + 更强正则化）
# ============================================================
print("\n正在训练 MLP (10→24→16→9)...")

H1, H2 = 24, 16
N_CLASS = 9

rng = np.random.RandomState(42)
W1 = rng.randn(10, H1).astype(np.float32) * np.sqrt(2.0 / 10)
b1 = np.zeros(H1, dtype=np.float32)
W2 = rng.randn(H1, H2).astype(np.float32) * np.sqrt(2.0 / H1)
b2 = np.zeros(H2, dtype=np.float32)
W3 = rng.randn(H2, N_CLASS).astype(np.float32) * np.sqrt(2.0 / H2)
b3 = np.zeros(N_CLASS, dtype=np.float32)

LR_INIT = 0.003
BATCH = 64
EPOCHS = 200

n_train = int(TOTAL * 0.85)
indices = rng.permutation(TOTAL)
X_train, Y_train = X_norm[indices[:n_train]], Y[indices[:n_train]]
X_val, Y_val = X_norm[indices[n_train:]], Y[indices[n_train:]]

best_val_acc = 0
best_weights = None

for epoch in range(EPOCHS):
    lr = LR_INIT * (0.5 ** (epoch // 60))
    perm = rng.permutation(n_train)

    for start in range(0, n_train, BATCH):
        bi = perm[start:start + BATCH]
        xb, yb = X_train[bi], Y_train[bi]

        # Forward
        z1 = np.maximum(0, xb @ W1 + b1)
        z2 = np.maximum(0, z1 @ W2 + b2)
        logits = z2 @ W3 + b3

        # Softmax + CE loss
        exps = np.exp(logits - logits.max(axis=1, keepdims=True))
        probs = exps / exps.sum(axis=1, keepdims=True)
        one_hot = np.eye(N_CLASS)[yb]
        loss = -np.mean(np.log(probs[np.arange(len(yb)), yb] + 1e-7))

        # Backward
        dlogits = probs - one_hot
        dz2 = dlogits @ W3.T
        dz2[z2 <= 0] = 0
        dz1 = dz2 @ W2.T
        dz1[z1 <= 0] = 0

        W3 -= lr * (z2.T @ dlogits / len(yb))
        b3 -= lr * dlogits.mean(axis=0)
        W2 -= lr * (z1.T @ dz2 / len(yb))
        b2 -= lr * dz2.mean(axis=0)
        W1 -= lr * (xb.T @ dz1 / len(yb))
        b1 -= lr * dz1.mean(axis=0)

    # Validation
    z1v = np.maximum(0, X_val @ W1 + b1)
    z2v = np.maximum(0, z1v @ W2 + b2)
    val_pred = (z2v @ W3 + b3).argmax(axis=1)
    val_acc = (val_pred == Y_val).mean()

    if val_acc > best_val_acc:
        best_val_acc = val_acc
        best_weights = (W1.copy(), b1.copy(), W2.copy(), b2.copy(), W3.copy(), b3.copy())

    if epoch % 50 == 0:
        print(f"  Epoch {epoch:3d}: loss={loss:.4f}, val_acc={val_acc:.4f}, lr={lr:.6f}")

print(f"\n  最佳验证准确率: {best_val_acc:.4f}")

# ============================================================
#  详细评估
# ============================================================
W1f, b1f, W2f, b2f, W3f, b3f = best_weights
z1 = np.maximum(0, X_val @ W1f + b1f)
z2 = np.maximum(0, z1 @ W2f + b2f)
preds = (z2 @ W3f + b3f).argmax(axis=1)

print("\n各类别准确率 (验证集):")
for label in range(9):
    mask = Y_val == label
    if mask.sum() > 0:
        acc = (preds[mask] == label).mean()
        bar = '█' * int(acc * 30)
        print(f"  {EMOTIONS[label]:10s}: {acc:.3f} {bar}")

# 混淆矩阵
conf = np.zeros((9, 9), dtype=int)
for t, p in zip(Y_val, preds):
    conf[t][p] += 1
print(f"\n混淆矩阵 (行=真实, 列=预测):")
print(f"  {'':>10s} " + " ".join(f"{e[:6]:>6s}" for e in EMOTIONS))
for i in range(9):
    print(f"  {EMOTIONS[i]:10s} " + " ".join(f"{conf[i][j]:6d}" for j in range(9)))

# ============================================================
#  导出
# ============================================================
out_dir = Path(__file__).parent
output = {
    "mean": mean.tolist(),
    "std": std.tolist(),
    "W1": W1f.tolist(),
    "b1": b1f.tolist(),
    "W2": W2f.tolist(),
    "b2": b2f.tolist(),
    "W3": W3f.tolist(),
    "b3": b3f.tolist(),
}

json_path = out_dir / "emotion_model_weights.json"
with open(json_path, "w") as f:
    json.dump(output, f)
print(f"\n权重已导出到: {json_path}")
