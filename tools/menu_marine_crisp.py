"""Десантник живой сцены меню — чётче и с тёмным контуром (решение пользователя 08.11.2026, образец
assets/FInalUI/exampel.png: «десантник выглядит более органично»). Кадры поворота из пакета assets/FInalUI мягкие
(увеличены художником), а в меню их ещё и уменьшают (MenuSceneArt.MARINE_SCALE) — фигура расплывалась. Здесь:
резкость (нерезкое маскирование), тёмный контур снаружи силуэта толщиной OUTLINE px холста (как у башни), чуть
глубже тени. Холст и место ног прежние (712×1172, ноги — MenuSceneArt.MARINE_FEET).

  python tools/menu_marine_crisp.py

Вход:  assets/source_sheets/menu_anim/marine_orig/marine_NN.png (кадры пакета, не меняются)
Выход: assets/ui/menu/anim/marine_NN.png, потом godot --headless --import
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets/source_sheets/menu_anim/marine_orig"
OUT = ROOT / "assets/ui/menu/anim"
FRAMES = 8
OUTLINE = 4                       # px холста (на экране при MARINE_SCALE 0.5 и холсте ×0.55 — ~1 px)
OUTLINE_COLOR = (10, 11, 16)
FEET_Y = 804                      # линия ног на холсте (MenuSceneArt.MARINE_FEET.y)
SHARPEN = dict(radius=3, percent=140, threshold=2)
SHADOW_DEEPEN = 0.9               # тёмные тона чуть глубже — объём


def crisp(img: Image.Image) -> Image.Image:
    rgba = img.convert("RGBA")
    alpha = rgba.getchannel("A")
    rgb = rgba.convert("RGB").filter(ImageFilter.UnsharpMask(**SHARPEN))
    arr = np.asarray(rgb).astype(np.float32)
    lum = arr.mean(axis=2, keepdims=True) / 255.0
    arr *= 1.0 - (1.0 - SHADOW_DEEPEN) * (1.0 - np.clip(lum * 2.0, 0.0, 1.0))   # глубже только тени
    a = np.asarray(alpha)
    solid = a > 128
    # контур: силуэт, раздутый на OUTLINE px, минус сам силуэт
    grown = Image.fromarray((solid * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(OUTLINE * 2 + 1))
    ring = (np.asarray(grown) > 0) & ~solid
    ring[FEET_Y - OUTLINE:, :] = False   # под сапогами контура нет — иначе ровная полоса по низу кадра
    out = np.zeros((*a.shape, 4), np.uint8)
    out[..., :3] = np.clip(arr, 0, 255).astype(np.uint8)
    out[..., 3] = np.where(solid, 255, 0)
    out[ring, :3] = OUTLINE_COLOR
    out[ring, 3] = 235
    return Image.fromarray(out)


def main() -> None:
    for i in range(FRAMES):
        src = SRC / f"marine_{i:02d}.png"
        crisp(Image.open(src)).save(OUT / f"marine_{i:02d}.png")
        print(f"marine_{i:02d}.png")


if __name__ == "__main__":
    main()
