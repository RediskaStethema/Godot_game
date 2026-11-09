"""Знамя на башне живой сцены главного меню (assets/ui/menu/anim/banner_NN.png) — без прыжков.

Решение пользователя 07.11.2026 (Screenshot 2026-11-07 155323.png): «анимация прыгает и флаг то сужается, то
расширяется». Брак пакета (исходники не трогает — assets/source_sheets/menu_anim/banner_orig/):
  - перекладина с навершием в кадрах ездит по x до ±6 px и разной длины (в кадре 3 на 14 px короче);
  - полотно сдвинуто вместе с ней, верх полотна у перекладины то уже, то шире (89–107 px по ширине).
Что делает скрипт:
  1. Перекладина и навершие (строки выше HW_END) — из кадра 0 во всех кадрах: железо не двигается.
  2. Полотно — построчно: сдвиг кадра целиком (центр верха полотна против кадра 0) снимается; у перекладины
     (ATTACH px вниз) центр и ширина строки — как у кадра 0 (полотно пришито), ниже плавно возвращается своё
     колыхание; ширина строки — к медиане по 12 кадрам (WIDTH_KEEP) — полотно не «дышит»; у зубцов хвоста (TAIL)
     ширина своя — строку с зубцами врозь растяжка превращала в полосы.
  Строка растягивается по x линейно (альфа предумножена — край без ореола).

  python tools/menu_banner_fix.py      # затем godot --headless --path . --import
"""
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets/source_sheets/menu_anim/banner_orig"
DST = ROOT / "assets/ui/menu/anim"
FRAMES = 12
REF = 0
HW_END = 138           # строка холста: выше — перекладина и навершие, ниже — полотно
ATTACH = 150           # px: полотно пришито к перекладине — центр и ширина как у кадра 0, ниже — колыхание
WIDTH_KEEP = 0.85      # доля пути ширины строки к медиане по кадрам (1 — ширина не меняется совсем)
TAIL = (460, 500)      # строки: зубцы хвоста — ширина своя (строка с зубцами врозь тянулась в полосы), плавно
TOP_PROBE = 12         # строк под HW_END — по ним сдвиг кадра целиком
ALPHA = 128


def edges(a, y):
    xs = np.nonzero(a[y, :, 3] > ALPHA)[0]
    return (xs.min(), xs.max() + 1) if len(xs) else None


def smooth(t):
    t = min(max(t, 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def remap_row(row, l, r, nl, nr, width):
    """Строка: отрезок [l, r) исходника → [nl, nr) результата, линейно (премультиплицированно)."""
    out = np.zeros_like(row)
    xs = np.arange(width)
    inside = (xs >= nl) & (xs < nr)
    if not inside.any():
        return out
    src = l + (xs[inside] + 0.5 - nl) / (nr - nl) * (r - l) - 0.5
    src = np.clip(src, l, r - 1)
    x0 = np.floor(src).astype(int)
    x1 = np.minimum(x0 + 1, r - 1)
    f = (src - x0)[:, None]
    pm = row.astype(float)
    pm[:, :3] *= pm[:, 3:4] / 255.0
    v = pm[x0] * (1 - f) + pm[x1] * f
    a = v[:, 3:4]
    v[:, :3] = np.where(a > 0, v[:, :3] * 255.0 / np.maximum(a, 1e-6), 0)
    out[inside] = np.clip(np.round(v), 0, 255).astype(row.dtype)
    return out


def main():
    frames = [np.array(Image.open(SRC / f"banner_{i:02d}.png").convert("RGBA")) for i in range(FRAMES)]
    ref = frames[REF]
    h, w = ref.shape[:2]
    rows = range(HW_END, h)
    widths = {}
    for y in rows:
        ws = [e[1] - e[0] for e in (edges(f, y) for f in frames) if e]
        if ws:
            widths[y] = float(np.median(ws))

    def top_center(a):
        cs = [sum(e) / 2.0 for e in (edges(a, y) for y in range(HW_END, HW_END + TOP_PROBE)) if e]
        return float(np.mean(cs))

    ref_top = top_center(ref)
    for i, a in enumerate(frames):
        out = np.zeros_like(a)
        out[:HW_END] = ref[:HW_END]
        shift = top_center(a) - ref_top
        for y in rows:
            e = edges(a, y)
            if e is None:
                continue
            l, r = e
            k = smooth((y - HW_END) / ATTACH)   # 0 — у перекладины, 1 — своё колыхание
            keep = WIDTH_KEEP * (1.0 - smooth((y - TAIL[0]) / (TAIL[1] - TAIL[0])))
            c = (l + r) / 2.0 - shift
            cw = r - l
            er = edges(ref, y)
            if er:
                c = (er[0] + er[1]) / 2.0 * (1 - k) + c * k
                tw = cw + (widths.get(y, cw) - cw) * keep
                cw = (er[1] - er[0]) * (1 - k) + tw * k
            else:
                cw = cw + (widths.get(y, cw) - cw) * keep
            out[y] = remap_row(a[y], l, r, c - cw / 2.0, c + cw / 2.0, w)
        Image.fromarray(out).save(DST / f"banner_{i:02d}.png")
        print(f"banner_{i:02d}: сдвиг кадра {shift:+.1f} px снят")


if __name__ == "__main__":
    main()
