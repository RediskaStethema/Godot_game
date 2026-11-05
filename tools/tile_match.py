"""Плита поля → в цвет грунта: средние насыщенность и яркость и тон — как у эталонной плиты (грунта той
же темы). Большие кратеры листа серее и светлее осыпи, на поле — пятна другого цвета (решение
пользователя 19.10.2026). Форма, прозрачность и рисунок не меняются, файл пишется поверх.

    python tools/tile_match.py <эталон.png> <плита.png> …
    python tools/tile_match.py --to h,s,v <эталон.png> <плита.png> …   — сдвинуть всю группу: множители, при
        которых эталон получает тон h, насыщенность s и яркость v, — ко всем плитам (поле Хаоса темнее и глуше,
        решение пользователя 19.10.2026: грунт, стена, руины, кратеры и окопы остаются согласованы между собой)

Тон: все пиксели — в тон эталона (тонировка: бурые пятна кратера иначе стали бы рыжими от прибавки
насыщенности); насыщенность и яркость — множителями к средним эталона (по плотным пикселям, альфа > DENSE).
"""
import sys

import numpy as np
from PIL import Image

DENSE = 200
HUE_SAT_MIN = 0.1


def hsv(img):
    return np.array(img.convert("RGB").convert("HSV")).astype(float) / 255.0


def stats(img):
    a = np.array(img)[..., 3] > DENSE
    h = hsv(img)[a]
    return np.median(h[h[:, 1] > HUE_SAT_MIN, 0]), h[:, 1].mean(), h[:, 2].mean()


def main(ref, files, to=None):
    rh, rs, rv = stats(Image.open(ref).convert("RGBA"))
    if to:   # группа: множители эталона → цели, одни на все плиты
        ks, kv = to[1] / rs, to[2] / rv
    for f in files:
        img = Image.open(f).convert("RGBA")
        th, ts, tv = stats(img)
        if to:
            rh, rs, rv = to[0], ts * ks, tv * kv
        alpha = img.getchannel("A")
        h, s, v = np.moveaxis(hsv(img), -1, 0)
        h = np.full_like(h, rh)
        s = (s * rs / ts).clip(0, 1)
        v = (v * rv / tv).clip(0, 1)
        out = Image.merge("HSV", [Image.fromarray((c * 255 + 0.5).astype(np.uint8)) for c in (h, s, v)]).convert("RGBA")
        out.putalpha(alpha)
        out.save(f)
        print(f"{f}: тон {th:.3f}->{rh:.3f}, насыщ. {ts:.3f}->{rs:.3f}, яркость {tv:.3f}->{rv:.3f}")


if __name__ == "__main__":
    args = sys.argv[1:]
    to = None
    if args[0] == "--to":
        to = [float(x) for x in args[1].split(",")]
        args = args[2:]
    main(args[0], args[1:], to)
