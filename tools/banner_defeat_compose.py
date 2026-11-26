"""Баннер «ПОРАЖЕНИЕ» без звезды Хаоса (решение пользователя 24.11.2026: «права: авторы и канон»; на баннере три звезды Хаоса — большая
сверху в центре, две малые на боковых плашках, малая за черепом снизу). Layer image.edit (gpt-image-2.6-sunburst, 2 варианта 3.4 CU):
баннер ×1.5 на пурпурном холсте 1536×512 (макс. отношение сторон модели 3:1) → ответ 1776×592 → сюда. Заменено на: кольцо с черепом и
потухшим фонарём сверху, кольцо-руна с огарком на боковых плашках, кольцо вокруг нижнего черепа. Остальное — пиксель в пиксель
оригинал (правка накладывается только в областях `REGIONS`, край мягкий `FEATHER`); пурпурный фон срезается (альфа из «пурпурности» пикселя,
кайма контура восстанавливается). Фонарь выше прежнего верха баннера — поля `PAD` сверху и снизу поровну (иначе заголовок в `BattleHud`
съехал бы с тёмного поля: он центрируется по высоте картинки).
  python tools/banner_defeat_compose.py <ответ_layer.png> <выход.png> [--orig defeat_orig.png]
Оригинал — assets/source_sheets/banner_redraw_2026-11-23/defeat_orig.png (первый запуск сохраняет его из assets/ui/banners/defeat.png).
"""
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
GAME = ROOT / "assets/ui/banners/defeat.png"
ORIG = ROOT / "assets/source_sheets/banner_redraw_2026-11-23/defeat_orig.png"
SCALE_IN = 1.5            # баннер → холст модели
CANVAS = (1536, 512)
BANNER_Y = 129            # верх баннера на холсте модели, px холста
PAD = 34                  # поля сверху и снизу, px баннера
FEATHER = 3
# Области правки в px баннера (x0, y0, x1, y1), y — от верха оригинала (отрицательные — над ним)
REGIONS = [(430, -40, 600, 108), (196, 52, 262, 122), (762, 52, 830, 122), (468, 108, 556, 170)]


def keyed(rgb):
    """Пурпурный фон → альфа; цвет без примеси пурпура (чёрный контур: c = (1−a)·M → K)."""
    a = rgb.astype(float)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    p = np.clip(np.minimum(r - g, b - g) / 255.0, 0.0, 1.0)
    alpha = 1.0 - np.clip((p - 0.04) / 0.86, 0.0, 1.0)
    M = np.array([255.0, 0.0, 255.0])
    with np.errstate(divide="ignore", invalid="ignore"):
        fg = (a - p[..., None] * M) / np.maximum(1.0 - p[..., None], 1e-3)
    fg = np.clip(fg, 0, 255)
    out = np.dstack([fg, alpha * 255.0])
    out[alpha < 0.02] = 0
    return out.astype(np.uint8)


def main(argv):
    src, dst = Path(argv[0]), Path(argv[1])
    if not ORIG.exists():
        shutil.copy2(GAME, ORIG)
    orig = Image.open(ORIG).convert("RGBA")
    w, h = orig.size
    e = Image.open(src).convert("RGB")
    k = 1.0 / (e.width / CANVAS[0] * SCALE_IN)                     # px ответа → px баннера
    eb = e.resize((round(e.width * k), round(e.height * k)), Image.LANCZOS)
    y_banner = round(BANNER_Y / SCALE_IN)                          # верх баннера в системе ответа, px баннера
    top = y_banner - PAD
    crop = eb.crop((0, top, w, top + h + 2 * PAD))
    patch = Image.fromarray(keyed(np.array(crop)), "RGBA")
    base = Image.new("RGBA", (w, h + 2 * PAD), (0, 0, 0, 0))
    base.alpha_composite(orig, (0, PAD))
    mask = Image.new("L", base.size, 0)
    from PIL import ImageDraw
    d = ImageDraw.Draw(mask)
    for x0, y0, x1, y1 in REGIONS:
        d.rectangle((x0, y0 + PAD, x1, y1 + PAD), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(FEATHER / 2.0))
    m = np.array(mask).astype(float)[..., None] / 255.0
    out = np.array(base).astype(float) * (1 - m) + np.array(patch).astype(float) * m
    out[..., 3] = np.maximum(out[..., 3] * 0 + (np.array(base)[..., 3] * (1 - m[..., 0]) + np.array(patch)[..., 3] * m[..., 0]), 0)
    res = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")
    res.save(dst)
    print(dst, res.size)


if __name__ == "__main__":
    main(sys.argv[1:])
