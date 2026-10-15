"""Туман с кадров чужой палитры → на свою плиту: кадры анимации «воронки в тумане».

    python tools/fog_overlay.py <плита.png> <top плиты> <кадр.png> <top кадра> <выход.png>

Кадры тумана (ScatteredDebrisTilecrator1/2 → tools/tiles_from_png.py) нарисованы на серой плите, а поле
Космодесанта — тёмно-синее. Из кадра берётся только туман: альфа светлого слоя — насколько пиксель
ярче камня (FOG_FROM), цвет — FOG_COLOR; слой кладётся на плиту (та же клетка, ромбы совмещены по
верхнему углу при одной ширине). Выход — размером с плиту, top тот же, что у плиты.
"""
import sys

import numpy as np
from PIL import Image

FOG_FROM = 40.0      # яркость камня без тумана
FOG_RANGE = 170.0    # на сколько ярче — туман непрозрачен
FOG_MAX = 0.7
FOG_COLOR = (196, 204, 214)


def main(base_path, base_top, fog_path, fog_top, out_path):
    base = Image.open(base_path).convert("RGBA")
    fog = Image.open(fog_path).convert("RGBA")
    k = base.width / fog.width
    fog = fog.resize((base.width, round(fog.height * k)), Image.LANCZOS)
    f = np.array(fog).astype(float)
    alpha = np.clip((f[:, :, :3].mean(axis=2) - FOG_FROM) / FOG_RANGE, 0.0, FOG_MAX) * f[:, :, 3] / 255.0
    layer = np.zeros(f.shape, np.uint8)
    layer[:, :, :3] = FOG_COLOR
    layer[:, :, 3] = (alpha * 255).astype(np.uint8)
    out = base.copy()
    # Верхние углы ромбов совпадают: сдвиг слоя по y
    dy = round(float(base_top) - float(fog_top) * k)
    out.alpha_composite(Image.fromarray(layer), (0, max(dy, 0)), (0, max(-dy, 0)))
    # Туман только над плитой: альфа выхода — как у плиты
    o = np.array(out)
    o[:, :, 3] = np.array(base)[:, :, 3]
    Image.fromarray(o).save(out_path)


if __name__ == "__main__":
    main(*sys.argv[1:6])
