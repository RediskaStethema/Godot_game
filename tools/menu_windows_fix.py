"""Огни окон живой сцены главного меню (assets/ui/menu/anim/windows_NN.png) — по проёмам башни.

Решение пользователя 07.11.2026 (Screenshot 2026-11-07 112423.png): «огни горят не в окнах» — в пакете художника
слой окон — узкие янтарные полоски, сдвинутые от проёмов layer_tower.png на 10–40 px (на стене, на пилястрах).
Скрипт рисует свет заново прямо в проёмах башни:
  1. Проём — заливка от точки внутри (WINDOWS: точка, рамка поиска) по тёмным пикселям башни (яркость < DARK).
  2. Свет — тёплый янтарь, к низу проёма ярче (свеча / лампа стоит внизу), к краю проёма мягче (край стрельчатой
     рамы остаётся камнем), слабый ореол на откосах.
  3. Мерцание — FRAMES кадров, у каждого окна своя фаза и глубина (не мигают разом).
Исходники пакета не трогает — assets/source_sheets/menu_anim/windows_orig/.

  python tools/menu_windows_fix.py
"""
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
DIR = ROOT / "assets/ui/menu/anim"
FRAMES = 4
DARK = 46                   # max(r, g, b) — тёмная глубина проёма

# точка внутри проёма, рамка поиска (x0, y0, x1, y1) — холст 712×1172
WINDOWS = [
    ((615, 270), (596, 205, 636, 312)),    # башня, верхнее окно
    ((615, 420), (596, 352, 636, 478)),    # башня, второе
    ((466, 595), (450, 520, 486, 668)),    # башня, левое нижнее
    ((540, 610), (520, 515, 562, 670)),    # башня, среднее нижнее
    ((628, 635), (608, 570, 652, 698)),    # башня, правое нижнее
    ((160, 955), (140, 890, 186, 1012)),   # нижний ярус, левое
    ((280, 1000), (254, 928, 302, 1068)),  # нижний ярус, большое
]

GLOW_TOP = np.array([150, 70, 18], dtype=np.float32)     # верх проёма — глубокий тёплый
GLOW_BOTTOM = np.array([255, 178, 82], dtype=np.float32)  # низ — светлый янтарь
ALPHA_MAX = 0.74
EDGE_SOFT = 1.6             # px размытия края проёма
HALO_BLUR = 5               # ореол на откосах вокруг проёма
HALO_ALPHA = 0.22
FLICKER = (0.78, 1.0)       # множитель яркости окна: мин, макс


def window_mask(dark: np.ndarray, seed, box) -> np.ndarray:
    x0, y0, x1, y1 = box
    m = np.zeros_like(dark)
    sx, sy = seed
    if not dark[sy, sx]:
        # точка попала на светлый пиксель — ближайший тёмный в рамке
        ys, xs = np.nonzero(dark[y0:y1, x0:x1])
        k = np.argmin((xs + x0 - sx) ** 2 + (ys + y0 - sy) ** 2)
        sx, sy = xs[k] + x0, ys[k] + y0
    stack = [(sy, sx)]
    m[sy, sx] = True
    while stack:
        y, x = stack.pop()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if y0 <= ny < y1 and x0 <= nx < x1 and dark[ny, nx] and not m[ny, nx]:
                m[ny, nx] = True
                stack.append((ny, nx))
    return m


def blur(a: np.ndarray, r: float) -> np.ndarray:
    img = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))
    return np.asarray(img.filter(ImageFilter.GaussianBlur(r)), dtype=np.float32) / 255.0


def main() -> None:
    import sys
    sys.stdout.reconfigure(encoding="utf-8")
    tower = np.asarray(Image.open(DIR / "layer_tower.png").convert("RGBA")).astype(np.int32)
    dark = (tower[..., 3] > 200) & (tower[..., :3].max(axis=2) < DARK)
    h, w = dark.shape
    yy = np.arange(h, dtype=np.float32)[:, None]
    rng = np.random.default_rng(7)
    lights = []
    for seed, box in WINDOWS:
        m = window_mask(dark, seed, box)
        ys, xs = np.nonzero(m)
        top, bottom = ys.min(), ys.max()
        down = np.clip((yy - top) / max(1, bottom - top), 0, 1)   # 0 верх → 1 низ
        core = blur(m.astype(np.float32), EDGE_SOFT) * m           # внутри проёма, край мягче
        halo = blur(m.astype(np.float32), HALO_BLUR) * (~m) * HALO_ALPHA
        lights.append({"core": core * (0.55 + 0.45 * down), "halo": halo, "down": down,
                       "phase": rng.uniform(0, 1), "speed": rng.choice([1, 2])})
        print(f"окно {seed}: x {xs.min()}–{xs.max()}, y {top}–{bottom}, {len(ys)} px")
    for f in range(FRAMES):
        rgb = np.zeros((h, w, 3), dtype=np.float32)
        alpha = np.zeros((h, w), dtype=np.float32)
        for L in lights:
            t = (f / FRAMES * L["speed"] + L["phase"]) * math.tau
            k = FLICKER[0] + (FLICKER[1] - FLICKER[0]) * (0.5 + 0.5 * math.sin(t))
            a = np.clip((L["core"] + L["halo"]) * ALPHA_MAX * k, 0, 1)
            col = GLOW_TOP + (GLOW_BOTTOM - GLOW_TOP) * L["down"][..., None]
            new = np.maximum(alpha, a)
            take = a > alpha
            rgb[take] = np.broadcast_to(col, rgb.shape)[take]
            alpha = new
        out = np.dstack([np.clip(rgb, 0, 255), alpha * 255]).astype(np.uint8)
        Image.fromarray(out).save(DIR / f"windows_{f:02d}.png")
        print(f"windows_{f:02d}.png")


if __name__ == "__main__":
    main()
