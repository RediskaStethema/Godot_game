"""Огонь жаровни крупнее (решение пользователя 10.11.2026: «огонёк слишком маленький», жаровня Хаоса у цитадели):
пламя каждого кадра ленты ×SCALE без сглаживания (пиксель-арт) от точки его основания в чаше PIVOT, поверх кадра;
холст растёт вверх на EXTEND px — постамент и точка основания не двигаются (base в теме — +EXTEND по y).

    python tools/brazier_flame.py <лента.png> <кадров> <выход.png>

Пламя — пиксели выше FLAME_BELOW: розово-малиновые (тон ≥ 0.8 или ≤ 0.05, насыщенность и яркость выше порогов) и
белое ядро в полосе пламени по x. Печатает новую высоту кадра, base и центр пламени (для glow_height темы).
"""
import sys

import numpy as np
from PIL import Image

SCALE = 2
PIVOT = (40, 50)       # основание пламени в чаше (px кадра исходника)
FLAME_BELOW = 49       # пламя — выше кромки чаши (ниже — блики кромки, их не трогать)
FLAME_X = (24, 58)     # полоса пламени по x (белое ядро)
EXTEND = 24            # холст вверх, px
SAT, VAL = 0.25, 0.4


def flame_mask(f):
    hsv = np.array(Image.fromarray(f[..., :3]).convert("HSV")).astype(float) / 255.0
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    pink = ((h >= 0.8) | (h <= 0.05)) & (s > SAT) & (v > VAL)
    core = (s < 0.25) & (v > 0.8)
    m = (pink | core) & (f[..., 3] > 40)
    m[:, :FLAME_X[0]] = False
    m[:, FLAME_X[1]:] = False
    m[FLAME_BELOW:] = False
    return m


def main(src, frames, dst):
    strip = np.array(Image.open(src).convert("RGBA"))
    n = int(frames)
    fw, fh = strip.shape[1] // n, strip.shape[0]
    out = np.zeros((fh + EXTEND, fw * n, 4), np.uint8)
    centers = []
    for i in range(n):
        f = strip[:, i * fw:(i + 1) * fw]
        canvas = np.zeros((fh + EXTEND, fw, 4), np.uint8)
        canvas[EXTEND:] = f
        m = flame_mask(f)
        ys, xs = np.nonzero(m)
        for y, x in zip(ys, xs):
            ny = PIVOT[1] + (y - PIVOT[1]) * SCALE + EXTEND
            nx = PIVOT[0] + (x - PIVOT[0]) * SCALE
            for dy in range(SCALE):
                for dx in range(SCALE):
                    yy, xx = ny + dy, nx + dx
                    if 0 <= yy < canvas.shape[0] and 0 <= xx < fw:
                        canvas[yy, xx] = f[y, x]
        out[:, i * fw:(i + 1) * fw] = canvas
        ys2, xs2 = np.nonzero(m)   # центр нового пламени — по исходным пикселям пламени
        if len(ys2):
            centers.append((PIVOT[0] + (xs2.mean() - PIVOT[0]) * SCALE, PIVOT[1] + (ys2.mean() - PIVOT[1]) * SCALE + EXTEND))
    Image.fromarray(out).save(dst)
    c = np.mean(centers, 0) if centers else (0, 0)
    print("кадр %d×%d, base +%d по y, центр пламени (%.0f, %.0f)" % (fw, fh + EXTEND, EXTEND, c[0], c[1]))


if __name__ == "__main__":
    main(*sys.argv[1:4])
