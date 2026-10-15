"""Отдельные PNG плит с прозрачным фоном → обрезанные плиты для FactionTheme.

    python tools/tiles_from_png.py assets/sprites/tiles/space_marines terrain="assets/.../SeamlessTerrainTile_defult.png" ...

Каждая пара имя=файл: полупрозрачный ореол фона (альфа < ALPHA_CUT) — в ноль, картинка обрезается
по плотным пикселям (альфа > ALPHA_MIN; сверху — по любым видимым: туман над плитой), сохраняется
как <папка>/<имя>.png. Ширина картинки после обрезки = ширина ромба (FactionTheme: ширина PNG = клетка). Печатает top — y верхнего угла ромба
верхней грани (как tools/tiles_from_sheet.py: по верхней точке у левого и правого края).
Кадры анимации (кратер с туманом) — отдельные имена fog_crater_0, fog_crater_1, …
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ALPHA_CUT = 16
ALPHA_MIN = 128
CORNER_COLS = 3


def main(out_dir, pairs):
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    for pair in pairs:
        name, src = pair.split("=", 1)
        img = np.array(Image.open(src).convert("RGBA"))
        img[img[:, :, 3] < ALPHA_CUT] = 0
        m = img[:, :, 3] > ALPHA_MIN
        rows, cols = np.nonzero(m.any(axis=1))[0], np.nonzero(m.any(axis=0))[0]
        y0, y1, x0, x1 = rows.min(), rows.max() + 1, cols.min(), cols.max() + 1
        # Над плитой остаётся и полупрозрачное (туман, дым): верх — по любым видимым пикселям в её ширине
        y0 = np.nonzero(img[:, x0:x1, 3].any(axis=1))[0].min()
        img, m = img[y0:y1, x0:x1], m[y0:y1, x0:x1]
        Image.fromarray(img).save(out / f"{name}.png")
        width = x1 - x0
        ly = np.nonzero(m[:, :CORNER_COLS].any(axis=1))[0].min()
        ry = np.nonzero(m[:, -CORNER_COLS:].any(axis=1))[0].min()
        top = round((ly + ry) / 2 - width / 4)
        print(f'{name}.png: size {width}x{y1 - y0}, "top": {top}')


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2:])
