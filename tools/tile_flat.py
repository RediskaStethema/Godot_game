"""Плоская плита без боковой грани (решение пользователя 23.11.2026: «слишком явно выбивается поле боя» — вдоль основания стены торчал
каменный уступ: у плиты грунта темы снизу нарисована грань толщиной ~43 px листа, на внешнем кольце под стеной за ней раньше была
пустота, а с землёй FieldSurround она стала читаться как бортик). Режет плиту по ромбу верхней грани (ширина W, высота W/2, под
верхним полем TOP px листа), остальное — прозрачно. Размер листа и поле top не меняются — подстановка в тему без правок координат.
  python tools/tile_flat.py <плита.png> <top> <выход.png>
"""
import sys
import numpy as np
from PIL import Image

src, top, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
im = np.array(Image.open(src).convert("RGBA"))
h, w = im.shape[:2]
dh = w / 2.0
ys, xs = np.mgrid[0:h, 0:w]
inside = (np.abs(xs - (w - 1) / 2.0) / (w / 2.0) + np.abs(ys - (top + dh / 2.0)) / (dh / 2.0)) <= 1.0
# запас в 1 px по кромке ромба, чтобы шов с соседями не открылся
inside |= (np.abs(xs - (w - 1) / 2.0) / (w / 2.0 + 1.0) + np.abs(ys - (top + dh / 2.0)) / (dh / 2.0 + 1.0)) <= 1.0
im[..., 3] = np.where(inside, im[..., 3], 0)
Image.fromarray(im).save(out)
print(out, "ромб", w, "x", int(dh), "над ним", top, "px; листа", w, "x", h)
