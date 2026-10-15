"""Плита реки → её отражение вдоль течения: широкий конец русла — с другой стороны.

    python tools/river_mirror.py <плита.png> <top> <выход.png>

Русло плиты идёт по оси v (от северо-восточного края ромба к юго-западному) и к одному концу
шире. Отражение v → -v в плоскости земли (на экране — (x, y) → (2y, x/2) от центра ромба) меняет
концы местами, а берега оставляет на своих сторонах: плита и её отражение стыкуются широкий
к широкому, отражение и следующая плита — узкий к узкому (IsoGridRenderer чередует их вдоль реки).
Отражается только верхняя грань ромба; боковые стенки и то, что торчит над ромбом, — как были.
"""
import sys

import numpy as np
from PIL import Image


def main(src, top, out_path):
    a = np.array(Image.open(src).convert("RGBA")).astype(float)
    h, w = a.shape[:2]
    cx, cy = w / 2, float(top) + w / 4
    ys, xs = np.mgrid[0:h, 0:w]
    rx, ry = xs + 0.5 - cx, ys + 0.5 - cy
    inside = (np.abs(rx) / (w / 2) + np.abs(ry) / (w / 4)) <= 1.0
    # Отражение — само себе обратное: пиксель (x, y) берётся из (2y, x/2), билинейно
    sx, sy = 2 * ry + cx - 0.5, rx / 2 + cy - 0.5
    x0 = np.clip(np.floor(sx).astype(int), 0, w - 2)
    y0 = np.clip(np.floor(sy).astype(int), 0, h - 2)
    fx = np.clip(sx - x0, 0, 1)[..., None]
    fy = np.clip(sy - y0, 0, 1)[..., None]
    sample = (a[y0, x0] * (1 - fx) * (1 - fy) + a[y0, x0 + 1] * fx * (1 - fy)
              + a[y0 + 1, x0] * (1 - fx) * fy + a[y0 + 1, x0 + 1] * fx * fy)
    out = a.copy()
    out[inside] = sample[inside]
    Image.fromarray(out.astype(np.uint8)).save(out_path)


if __name__ == "__main__":
    main(*sys.argv[1:4])
