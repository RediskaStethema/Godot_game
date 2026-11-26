"""Стойка продавца оживает кодом (решение пользователя 23.11.2026: «добавь анимацию IDLE: свечение фонаря, моргание зародыша
с бульканьем в колбе за ним»). Из кадра 0 стойки (`<пакет>/out/idle/0.png`, после tools/vendor_stabilize.py) строит ряд из N кадров:
  алхимик (space_marines): мерцает фонарь (яркость пламени, дрожит кончик, ступенчатый ореол), зародыш в колбе моргает
    (глаз закрывается веком по кадрам 15–17 цикла), в жидкости за ним поднимаются пузыри (рисуются только по пикселям жидкости,
    поэтому за зародышем и стеклом их не видно);
  торговец (chaos): мерцает фонарь (яркость стекла, ореол).
Тело не трогается — только эти места: кадры не «кипят». Цикл замкнут (кадр N−1 → кадр 0).
  python tools/vendor_idle_anim.py <алхимик|торговец> <папка пакета (с out/idle/0.png)>
Пишет <папка>/out/idle/0..N-1.png; прежний кадр 0 — <папка>/out/idle_base.png (повтор — от него).
"""
import math
import shutil
import sys
from pathlib import Path
import numpy as np
from PIL import Image

N = 24
EYE_DISC = 14.0     # радиус диска глаза зародыша, px (кольцо глаза доходит до 13.5)
FLICKER = [1.00, 0.88, 1.10, 0.94, 1.16, 0.90, 1.05, 0.84, 1.12, 0.96, 1.18, 0.92,
           1.02, 0.86, 1.14, 0.93, 1.08, 0.85, 1.13, 0.97, 1.17, 0.89, 1.06, 0.95]
# области в кадре 480x760 (после vendor_redraw_slice: фигура 641 / 650 px, стопы x 226)
ALCH = {
    "lantern": (396, 252, 466, 312),      # x0, y0, x1, y1: стекло фонаря с двумя огнями
    "eye": (277, 252),                    # центр глаза зародыша (оранжевое кольцо, щель зрачка)
    "eye_r": 15,
    "flask": (236, 205, 330, 318),        # внутри колбы
}
PED = {"lantern": (372, 372, 432, 428)}


def is_glow(a: np.ndarray) -> np.ndarray:
    r, g, b, al = (a[..., i].astype(int) for i in range(4))
    return (al > 0) & (r > 200) & (g > 105) & (b < 150) & (r - b > 90)


def hsv(a: np.ndarray):
    f = a[..., :3].astype(np.float64) / 255.0
    mx, mn = f.max(2), f.min(2)
    d = mx - mn
    h = np.zeros_like(mx)
    r, g, b = f[..., 0], f[..., 1], f[..., 2]
    m = d > 1e-6
    rc = m & (mx == r)
    gc = m & (mx == g) & ~rc
    bc = m & ~rc & ~gc
    h[rc] = ((g - b)[rc] / d[rc]) % 6
    h[gc] = (b - r)[gc] / d[gc] + 2
    h[bc] = (r - g)[bc] / d[bc] + 4
    return h * 60.0, np.where(mx > 0, d / np.maximum(mx, 1e-6), 0), mx


def put(f: np.ndarray, y: int, x: int, col, k: float = 1.0) -> None:
    if 0 <= y < f.shape[0] and 0 <= x < f.shape[1]:
        f[y, x, :3] = np.clip(np.array(col, dtype=np.float64) * k + f[y, x, :3].astype(np.float64) * (1 - k), 0, 255).astype(np.uint8)
        f[y, x, 3] = max(f[y, x, 3], 255 if k >= 1.0 else f[y, x, 3])


def lantern(frames: list, base: np.ndarray, box) -> None:
    """Мерцание: яркость огня по таблице, кончики пламени дрожат на пиксель, вокруг — ступенчатый тёплый ореол."""
    x0, y0, x1, y1 = box
    glow = is_glow(base)
    region = np.zeros_like(glow)
    region[y0:y1, x0:x1] = True
    flame = glow & region
    ys, xs = np.where(flame)
    cy, cx = (ys.min() + ys.max()) / 2.0, (xs.min() + xs.max()) / 2.0
    # верхние 2 пикселя каждой колонки пламени — кончик
    tips = []
    for x in np.unique(xs):
        col = ys[xs == x]
        tips.append((col.min(), x))
    for i, f in enumerate(frames):
        k = FLICKER[i % len(FLICKER)]
        for y, x in zip(ys, xs):
            c = f[y, x, :3].astype(np.float64)
            f[y, x, :3] = np.clip(c * (0.8 + 0.3 * k) + np.array([40, 25, 0]) * max(0.0, k - 1.0) * 3.0, 0, 255).astype(np.uint8)
        # кончик: при слабой вспышке пропадает верхний пиксель колонки, при сильной — поднимается на 1 px
        for ty, tx in tips:
            if k < 0.9:
                f[ty, tx, :3] = (f[ty, tx, :3].astype(np.float64) * 0.55).astype(np.uint8)
            elif k > 1.12 and ty - 1 >= 0 and f[ty - 1, tx, 3] > 0:
                f[ty - 1, tx, :3] = np.clip(f[ty - 1, tx, :3].astype(np.float64) * 0.4 + np.array([255, 200, 90]) * 0.6, 0, 255).astype(np.uint8)
        # ореол: три ступени вокруг фонаря на прозрачных пикселях (твёрдая кромка, без мягкого градиента)
        rad = (x1 - x0) * 0.62
        for ring, (rr, a_) in enumerate(((rad * 1.00, 0.10), (rad * 0.80, 0.16), (rad * 0.60, 0.22))):
            ys_, xs_ = np.ogrid[:f.shape[0], :f.shape[1]]
            d = np.hypot((xs_ - cx), (ys_ - cy) * 1.15)
            ring_mask = (d <= rr * (0.9 + 0.1 * k)) & (f[..., 3] == 0)
            f[ring_mask, :3] = np.array([255, 170, 70], dtype=np.uint8)
            f[ring_mask, 3] = np.maximum(f[ring_mask, 3], int(255 * a_ * (0.75 + 0.25 * k)))


def embryo(frames: list, base: np.ndarray) -> None:
    """Зародыш в колбе: глаз закрывается веком (кадры 15–17), в жидкости за ним поднимаются пузыри."""
    ex, ey = ALCH["eye"]
    r = ALCH["eye_r"]
    ys_, xs_ = np.ogrid[:base.shape[0], :base.shape[1]]
    ring = np.hypot(xs_ - ex, ys_ - ey)
    h, s, v = hsv(base)
    eye_mask = ring <= EYE_DISC          # весь диск глаза: оранжевое кольцо и щель зрачка
    # кожа зародыша вокруг глаза (персиковая; не кольцо глаза, не жидкость)
    skin = (base[..., 3] > 0) & (ring > EYE_DISC + 1) & (ring < EYE_DISC + 8) & (h > 12) & (h < 38) & (s > 0.18) & (s < 0.62) & (v > 0.55)
    skin_col = np.median(base[skin][:, :3], axis=0) if skin.sum() > 10 else np.array([226, 170, 140])
    lid_dark = skin_col * 0.5
    ey_ys, ey_xs = np.where(eye_mask)
    ymid = ey
    # веко: цвет кожи с лёгким переходом по высоте (светлее вверху — как кожа вокруг)
    lid_px = {}
    for y, x in zip(ey_ys, ey_xs):
        t = (y - (ey - EYE_DISC)) / (2 * EYE_DISC)           # 0 вверху диска, 1 внизу
        lid_px[(y, x)] = np.clip(skin_col * (1.06 - 0.16 * t), 0, 255).astype(np.uint8)
    # жидкость: оливково-жёлтый тон внутри колбы, не кожа, не блик, не контур
    fx0, fy0, fx1, fy1 = ALCH["flask"]
    inflask = np.zeros(base.shape[:2], dtype=bool)
    inflask[fy0:fy1, fx0:fx1] = True
    liquid = inflask & (base[..., 3] > 0) & (h > 42) & (h < 85) & (s > 0.28) & (s < 0.85) & (v > 0.3) & (v < 0.78)
    print("  глаз:", int(eye_mask.sum()), "px, центр", ex, ey, "| жидкость:", int(liquid.sum()), "px | веко", skin_col.astype(int))
    bubbles = [(0.14, 0.00, 7, 1.0), (0.76, 0.22, 6, 1.0), (0.30, 0.45, 8, 1.0), (0.86, 0.68, 5, 1.0), (0.22, 0.85, 6, 1.0)]   # (x в колбе 0..1, фаза цикла, радиус, сила)
    for i, f in enumerate(frames):
        # веко: 15 — прищур (верхняя половина закрыта), 16 — закрыт, 17 — прищур
        lid = {15: 0.5, 16: 1.0, 17: 0.5}.get(i, 0.0)
        if lid > 0:
            for y, x in zip(ey_ys, ey_xs):
                if lid >= 1.0 or y < ymid:
                    f[y, x, :3] = lid_px[(y, x)]
            rr = int(EYE_DISC)
            for dx in range(-rr + 1, rr):                     # линия века — лёгкая дуга
                yy = ymid + (3 if lid >= 1.0 else 0) - int(round(2 * (dx / EYE_DISC) ** 2))
                if 0 <= yy < f.shape[0]:
                    f[yy, ex + dx, :3] = lid_dark.astype(np.uint8)
        # пузыри
        for bx, ph, br, st in bubbles:
            t = ((i / N) + ph) % 1.0
            cx = fx0 + (fx1 - fx0) * bx + math.sin(t * 2 * math.pi * 2 + ph * 7) * 3.0
            cy = fy1 - 6 - t * (fy1 - fy0 - 30)
            for dy in range(-br, br + 1):
                for dx in range(-br, br + 1):
                    d = math.hypot(dx, dy)
                    y, x = int(round(cy + dy)), int(round(cx + dx))
                    if not (0 <= y < f.shape[0] and 0 <= x < f.shape[1]) or not liquid[y, x]:
                        continue
                    if br - 2.0 <= d <= br + 0.3:                                  # тонкий светлый контур пузыря
                        f[y, x, :3] = np.clip(f[y, x, :3].astype(np.float64) * (1 - 0.8 * st) + np.array([238, 232, 160]) * 0.8 * st, 0, 255).astype(np.uint8)
                    elif d < br - 1.0:                                       # внутри чуть светлее
                        f[y, x, :3] = np.clip(f[y, x, :3].astype(np.float64) * (1 - 0.3 * st) + np.array([225, 215, 135]) * 0.3 * st, 0, 255).astype(np.uint8)
            hx, hy = int(round(cx - br * 0.4)), int(round(cy - br * 0.4))      # блик 2x2
            for ddy in (0, 1):
                for ddx in (0, 1):
                    if 0 <= hy + ddy < f.shape[0] and 0 <= hx + ddx < f.shape[1] and liquid[hy + ddy, hx + ddx]:
                        f[hy + ddy, hx + ddx, :3] = np.array([255, 250, 210], dtype=np.uint8)


def run(who: str, root: Path) -> None:
    out = root / "out" / "idle"
    base_path = root / "out" / "idle_base.png"
    if not base_path.exists():
        shutil.copy(out / "0.png", base_path)
    base = np.array(Image.open(base_path).convert("RGBA"))
    frames = [base.copy() for _ in range(N)]
    if who == "алхимик":
        embryo(frames, base)
        lantern(frames, base, ALCH["lantern"])
    else:
        lantern(frames, base, PED["lantern"])
    for f in out.glob("*.png"):
        f.unlink()
    for i, f in enumerate(frames):
        Image.fromarray(f).save(out / f"{i}.png")
    print(who, N, "кадров →", out)


if __name__ == "__main__":
    run(sys.argv[1], Path(sys.argv[2]))
