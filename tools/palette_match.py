"""Цветокоррекция ассетов расы под одну палитру (поле Хаоса): яркость и насыщенность — к целевым средним,
тёплые оттенки — к тону грунта, фиолетовые (варп-пламя) — к малиновому. Форма и прозрачность не меняются.

    python tools/palette_match.py <выход: папка или файл> <файл> [<файл> …]

Цель — константы ниже (подобраны под красный грунт Хаоса red_terrain.png: оттенок 0.992; яркость деталей
чуть выше грунта, чтобы читались, насыщенность — между грунтом и серым камнем крепости).
Средние считаются по плотным пикселям (альфа > 200) каждого файла; кадры одной анимации стоит
передавать одним вызовом с --group — тогда множители общие, и кадры не мигают яркостью.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

TARGET_HUE = 0.992     # тон грунта
TARGET_VAL = 0.21      # средняя яркость
TARGET_SAT = 0.56      # средняя насыщенность
HUE_PULL = 0.6         # доля, на которую тёплые оттенки (красный…оранжевый) тянутся к тону грунта
WARM_RANGE = 0.12      # тёплые — в пределах этой доли круга от тона грунта
PURPLE = (0.66, 0.86)  # фиолетовые оттенки (варп-пламя)…
PURPLE_TO = 0.93       # …сдвигаются к малиновому на PURPLE_PULL
PURPLE_PULL = 0.6
SAT_BLEND = 0.7        # насколько подтягивать насыщенность к цели (1 — полностью)
MIN_SAT = 0.12         # почти серые пиксели (металл) — тон не трогаем
BONE = (0.45, 0.5)     # светлые (яркость > 0.45) и не яркие цветом (насыщенность < 0.5) — кость, черепа: как есть


def _hsv(img):
    rgb = Image.fromarray(np.array(img)[:, :, :3])
    return np.array(rgb.convert("HSV")).astype(float) / 255.0


def _means(images):
    vs, ss = [], []
    for img in images:
        a = np.array(img)[:, :, 3] > 200
        hsv = _hsv(img)
        vs.append(hsv[..., 2][a])
        ss.append(hsv[..., 1][a])
    v = np.concatenate(vs)
    s = np.concatenate(ss)
    return v.mean(), s.mean()


def grade(img, v_gain, s_gain):
    alpha = np.array(img)[:, :, 3]
    hsv = _hsv(img)
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    d = ((h - TARGET_HUE + 0.5) % 1.0) - 0.5   # знаковое расстояние по кругу
    bone = (v > BONE[0]) & (s < BONE[1])
    warm = (np.abs(d) < WARM_RANGE) & (s > MIN_SAT) & ~bone
    h = np.where(warm, (TARGET_HUE + d * (1.0 - HUE_PULL)) % 1.0, h)
    purple = (h > PURPLE[0]) & (h < PURPLE[1]) & (s > MIN_SAT)
    h = np.where(purple, h + (PURPLE_TO - h) * PURPLE_PULL, h)
    s = np.where(bone, s, np.clip(s * s_gain, 0.0, 1.0))
    v = np.clip(v * v_gain, 0.0, 1.0)
    out = Image.merge("HSV", [Image.fromarray((c * 255).astype(np.uint8)) for c in (h, s, v)]).convert("RGBA")
    out.putalpha(Image.fromarray(alpha))
    return out


def main(args):
    group = "--group" in args
    args = [a for a in args if a != "--group"]
    out, files = Path(args[0]), args[1:]
    images = [Image.open(f).convert("RGBA") for f in files]
    if group:
        v_mean, s_mean = _means(images)
        gains = [(TARGET_VAL / v_mean, 1.0 + (TARGET_SAT / s_mean - 1.0) * SAT_BLEND)] * len(images)
    else:
        gains = []
        for img in images:
            v_mean, s_mean = _means([img])
            gains.append((TARGET_VAL / v_mean, 1.0 + (TARGET_SAT / s_mean - 1.0) * SAT_BLEND))
    for f, img, (vg, sg) in zip(files, images, gains):
        dst = out / Path(f).name if out.is_dir() else out
        grade(img, vg, sg).save(dst)
        print(f"{Path(f).name}: яркость x{vg:.2f}, насыщенность x{sg:.2f} -> {dst}")


if __name__ == "__main__":
    main(sys.argv[1:])
