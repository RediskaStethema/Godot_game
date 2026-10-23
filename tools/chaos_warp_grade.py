"""Поле Хаоса — палитра «бордо + варп» (решение пользователя 23.10.2026: «стилизуй поле Хаоса по цветовой
палитре», вариант «Бордо + варп (малиновый)»): тёмное и средне-яркое цветное (камень, грунт, плоть) — тон
бордо HUE_BORDO, светлое цветное (кристаллы, глаза, свечение ямы, огонь) — холодный малиновый варп HUE_WARP;
серое (кость, сталь, черепа — насыщенность ниже SAT_LO) не трогается. Тон сдвигается по кругу, яркость и
насыщенность — как были (форма и свет листа те же). Повторный прогон даёт тот же тон — можно гнать снова.

    python tools/chaos_warp_grade.py <файл.png> …      — поверх
"""
import sys

import numpy as np
from PIL import Image

HUE_BORDO = 0.985       # тёмное цветное
HUE_WARP = 0.925        # светлое цветное (малиновый варп)
SAT_LO, SAT_HI = 0.12, 0.3     # насыщенность: ниже LO — серое, не трогать; выше HI — сдвиг целиком
VAL_LO, VAL_HI = 0.22, 0.55    # яркость: ниже LO — бордо, выше HI — варп
WARP_SAT = 1.3          # светлое — насыщеннее: свечение читается на тёмном поле


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def warp(img: Image.Image) -> Image.Image:
    rgba = img.convert("RGBA")
    a = np.array(rgba)[..., 3:4]
    hsv = np.array(rgba.convert("RGB").convert("HSV")).astype(float) / 255.0
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    w = smooth(SAT_LO, SAT_HI, s)
    glow = smooth(VAL_LO, VAL_HI, v)
    target = HUE_BORDO + (HUE_WARP - HUE_BORDO) * glow
    dh = (target - h + 0.5) % 1.0 - 0.5
    h = (h + dh * w) % 1.0
    s = np.clip(s * (1.0 + (WARP_SAT - 1.0) * glow * w), 0.0, 1.0)
    out = (np.stack([h, s, v], axis=2) * 255).round().astype(np.uint8)
    rgb = np.array(Image.frombytes("HSV", rgba.size, out.tobytes()).convert("RGB"))
    return Image.fromarray(np.concatenate([rgb, a], axis=2))


if __name__ == "__main__":
    for f in sys.argv[1:]:
        warp(Image.open(f)).save(f)
        print(f)
