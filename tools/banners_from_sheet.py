"""Знамёна листа UI_assets.png (раздел BANNERS / FLAGS) → декор поля боя в палитре расы.

    python tools/banners_from_sheet.py UI_assets.png

На листе знамёна висят на перекладине без древка — скрипт дорисовывает древко до земли и подножие
(цвет — металл перекладины), чтобы знамя стояло на клетке. Точка основания — низ подножия (печатает
`base` для FactionTheme). Палитра (решение пользователя 17.10.2026 — знамёна в цветах расы):
  Космодесант — красное полотнище → синее (тон грунта и брони), кость и металл как есть; на поле
      поверх — GOTHIC_TINT, как у готики;
  Хаос — сине-чёрные тона → красно-чёрные, затем tools/palette_match.py (тон красного грунта, общие
      множители на все знамёна, ярче не делает).
Какие знамёна у какой расы — SETS (у Империума — аквилы и череп, у Хаоса — черепа и скелет).
"""
import colorsys
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

import palette_match

BANNERS = [   # рамки знамён на листе 1536×1024
    (743, 415, 826, 614),    # 0 красное, аквила
    (834, 415, 916, 624),    # 1 чёрное, череп
    (926, 415, 1007, 618),   # 2 белое, аквила
    (1015, 416, 1096, 616),  # 3 красно-чёрное, череп
    (1102, 415, 1181, 633),  # 4 чёрное, скелет
]
SETS = {
    "space_marines": [0, 2, 1],
    "chaos": [3, 4, 1],
}
OUT = {"space_marines": Path("assets/sprites/props/space_marines"), "chaos": Path("assets/sprites/props/chaos")}
POLE_BELOW = 34       # древко ниже полотнища, px листа
POLE_W = 4
FOOT = (18, 7)        # подножие: ширина, высота
POLE = (52, 56, 66, 255)
POLE_LIGHT = (96, 104, 120, 255)
SM_HUE = 0.61         # синий Космодесанта
SM_DIM = 0.85         # всё знамя Космодесанта глуше (белое полотнище не должно светиться на тёмном поле)
RED_HUES = (0.94, 0.06)
COOL_HUES = (0.45, 0.8)   # холодные тёмные тона листа (сине-чёрное полотнище) — у Хаоса в красно-чёрный


def with_pole(banner):
    """Знамя + древко по центру до земли + подножие. Возвращает картинку и точку основания."""
    w, h = banner.size
    out = Image.new("RGBA", (w, h + POLE_BELOW + FOOT[1]), (0, 0, 0, 0))
    d = ImageDraw.Draw(out)
    cx = w // 2
    d.rectangle((cx - POLE_W // 2, 4, cx + POLE_W // 2 - 1, h + POLE_BELOW), fill=POLE)
    d.line((cx - POLE_W // 2, 4, cx - POLE_W // 2, h + POLE_BELOW), fill=POLE_LIGHT)
    fy = h + POLE_BELOW
    d.ellipse((cx - FOOT[0] // 2, fy - FOOT[1] // 2, cx + FOOT[0] // 2, fy + FOOT[1] // 2), fill=(30, 32, 38, 255))
    d.ellipse((cx - FOOT[0] // 2 + 3, fy - FOOT[1] // 2, cx + FOOT[0] // 2 - 3, fy + 1), fill=POLE)
    out.alpha_composite(banner)
    return out, (cx, fy + FOOT[1] // 2)


def to_blue(img):
    """Красное полотнище → синее: насыщенные красные пиксели меняют тон, яркость та же (чуть глуше)."""
    a = np.array(img).astype(float) / 255.0
    out = a.copy()
    for y in range(a.shape[0]):
        for x in range(a.shape[1]):
            r, g, b, al = a[y, x]
            if al == 0:
                continue
            h, s, v = colorsys.rgb_to_hsv(r, g, b)
            if s > 0.35 and (h > RED_HUES[0] or h < RED_HUES[1]):
                out[y, x, :3] = colorsys.hsv_to_rgb(SM_HUE, s * 0.85, v * 0.9 * SM_DIM)
            else:
                out[y, x, :3] = colorsys.hsv_to_rgb(h, s, v * SM_DIM)
    return Image.fromarray((out * 255).astype(np.uint8))


def warm_darks(img):
    """Хаос: холодные (сине-чёрные) пиксели — в тон красного грунта, насыщенность не ниже трети."""
    a = np.array(img).astype(float) / 255.0
    for y in range(a.shape[0]):
        for x in range(a.shape[1]):
            r, g, b, al = a[y, x]
            if al == 0:
                continue
            h, s, v = colorsys.rgb_to_hsv(r, g, b)
            if COOL_HUES[0] < h < COOL_HUES[1] and s > 0.08:
                a[y, x, :3] = colorsys.hsv_to_rgb(palette_match.TARGET_HUE, max(s, 0.35), v)
    return Image.fromarray((a * 255).astype(np.uint8))


def main(sheet):
    img = Image.open(sheet).convert("RGBA")
    img.putalpha(img.getchannel("A").point(lambda a: 0 if a < 16 else a))
    for faction, ids in SETS.items():
        made = []
        for n, i in enumerate(ids):
            banner = img.crop(BANNERS[i])
            banner = to_blue(banner) if faction == "space_marines" else warm_darks(banner)
            made.append(with_pole(banner))
        if faction == "chaos":   # общие множители — знамёна одной яркости
            v_gain, s_gain = palette_match._means([m[0] for m in made])
            # ярче не делать: знамёна и так светлее грунта (кость черепов)
            v_gain, s_gain = min(palette_match.TARGET_VAL / v_gain, 1.0), palette_match.TARGET_SAT / max(s_gain, 1e-3)
            s_gain = 1.0 + (s_gain - 1.0) * palette_match.SAT_BLEND
            made = [(palette_match.grade(m, v_gain, s_gain), base) for m, base in made]
        for n, (m, base) in enumerate(made):
            path = OUT[faction] / f"war_banner_{n + 1}.png"
            m.save(path)
            print(f'{path.as_posix()}  base = Vector2({base[0]}, {base[1]})  size {m.size}')


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "UI_assets.png")
