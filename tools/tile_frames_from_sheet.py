"""Кадры анимированной плиты в ряд на прозрачном листе → PNG кадров одним окном + top для FactionTheme.

    python tools/tile_frames_from_sheet.py <лист.png> <папка> <префикс>

Кадры — слева направо (разделены прозрачными столбцами). Плита в каждом кадре одна и та же, над ней —
свечение / дым разной высоты (terrain_sheet_assets.png: кристаллы Хаоса разгораются). Режется одинаковым
окном: ширина — плита (самая широкая плотная строка), низ — низ плиты, верх — самое высокое свечение
из всех кадров; так ширина = клетка у всех кадров и top общий — анимация не прыгает. Печатает top
(как tiles_from_png.py — по верхним плотным точкам у левого и правого края первого кадра).
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ALPHA_CUT = 16      # ореол фона листа — в ноль
ALPHA_COL = 40      # столбец с такой альфой — часть кадра
ALPHA_DENSE = 200   # плотная часть — плита
CORNER_COLS = 3


def runs(flags):
    out, start = [], None
    for i, f in enumerate(list(flags) + [False]):
        if f and start is None:
            start = i
        elif not f and start is not None:
            out.append((start, i))
            start = None
    return out


def main(sheet, folder, prefix):
    a = np.array(Image.open(sheet).convert("RGBA"))
    a[a[..., 3] < ALPHA_CUT] = 0
    img = Image.fromarray(a)
    alpha = a[..., 3]
    frames = runs((alpha > ALPHA_COL).any(0))
    boxes, widths = [], []
    for x0, x1 in frames:
        dense = alpha[:, x0:x1] > ALPHA_DENSE
        rows = np.nonzero(dense.any(1))[0]
        w, y = max((np.ptp(np.nonzero(dense[r])[0]) + 1, r) for r in rows)   # самая широкая строка — плита
        boxes.append((x0 + np.nonzero(dense[y])[0].min(), rows.max() + 1))
        widths.append(w)
    width = max(widths)
    bottom = max(b for _, b in boxes)
    top_y = min(np.nonzero((alpha[:, x0:x1] > 0).any(1))[0].min() for x0, x1 in frames)
    out = Path(folder)
    out.mkdir(parents=True, exist_ok=True)
    for i, (left, _) in enumerate(boxes):
        img.crop((left, top_y, left + width, bottom)).save(out / f"{prefix}_{i}.png")
    first = np.array(Image.open(out / f"{prefix}_0.png"))[..., 3] > ALPHA_DENSE
    ly = np.nonzero(first[:, :CORNER_COLS].any(1))[0].min()
    ry = np.nonzero(first[:, -CORNER_COLS:].any(1))[0].min()
    print(f"{len(boxes)} кадров {width}x{bottom - top_y}, \"top\": {round((ly + ry) / 2 - width / 4)}")


if __name__ == "__main__":
    main(*sys.argv[1:4])
