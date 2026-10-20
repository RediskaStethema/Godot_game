"""Лист объектов на прозрачном фоне → отдельные PNG объектов (руины, декор, цитадель).

    python tools/props_from_sheet.py assets/source_sheets/goticImperial.png assets/sprites/props/space_marines gothic

Объект — связное пятно плотных пикселей (альфа > ALPHA_MIN), куски одного объекта склеиваются
через зазор JOIN px. Порядок — по рядам сверху вниз (ROW_PX), в ряду слева направо: <имя>_00.png, …
У каждого объекта остаются только его пиксели (тень и ореол соседа в рамку не попадут).
Печатает размер и основание — точку земли под объектом (центр ромба его площадки: ширина / 4
выше низа) — для FactionTheme ("base").
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

from tiles_from_sheet import components, dilate

ALPHA_MIN = 100
JOIN = 3
MIN_AREA = 1500
ROW_PX = 170


def main(sheet, out_dir, prefix):
    img = np.array(Image.open(sheet).convert("RGBA"))
    label, ids = components(dilate(img[:, :, 3] > ALPHA_MIN, JOIN))
    boxes = []
    for n in ids:
        ys, xs = np.nonzero(label == n)
        if len(ys) >= MIN_AREA:
            boxes.append((ys.min(), xs.min(), ys.max() + 1, xs.max() + 1, n))
    boxes.sort(key=lambda b: (round((b[0] + b[2]) / 2 / ROW_PX), b[1]))
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    for i, (y0, x0, y1, x1, n) in enumerate(boxes):
        crop = img[y0:y1, x0:x1].copy()
        crop[label[y0:y1, x0:x1] != n] = 0
        name = f"{prefix}_{i:02d}.png"
        Image.fromarray(crop).save(out / name)
        w, h = x1 - x0, y1 - y0
        print(f"{name}: {w}x{h}, base ({w / 2:.0f}, {h - w / 4:.0f})")


if __name__ == "__main__":
    main(*sys.argv[1:4])
