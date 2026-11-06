"""Ряд выстрела 2-го / 3-го уровня заново: стойка уровня + вспышка и дым 1-го уровня, перенесённые к стволам уровня.

    python tools/building_levels_attack_rebuild.py [папка здания …]     # по умолчанию — REBUILD
    python tools/building_levels_muzzle.py <папка здания>                # ствол уровня — по новой вспышке

Зачем (06.11.2026): у Bolter Turret ряды attack_2 / attack_3 — из пакета 26.10, там поверх модели уровня наложены
целые кадры 1-го уровня (старая турель и её вспышка): в бою при выстреле сквозь новую турель проступала старая.
В пакете 05.11 турели нет. Кадр ряда = кадр 0 стойки уровня (idle_<уровень>/0.png) + слой выстрела кадра k
1-го уровня: пиксели attack/k, отличающиеся от attack/0, яркие тёплые (огонь) и светло-серые (дым) у ствола —
не корпус; левый край вспышки 1-го уровня ставится на конец ствола уровня. Конец ствола — самая правая точка
силуэта кадра (средняя высота строк в BARREL_SLACK px от неё). Движения корпуса нет — ряд остаётся в
metadata/level_static: отдачу даёт Building._apply_motion.
Запускать после building_levels_add.py (он снова кладёт ряды пакета 26.10).
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

BUILDINGS = Path("assets/sprites/buildings")
REBUILD = []   # 06.11.2026: Bolter Turret — свои листы 2 / 3 уровня (building_levels_sheets.py), пересборка не нужна
BARREL_SLACK = 6     # px: строки, где силуэт доходит почти до самой правой точки, — ствол
REACH = 70           # px: слой выстрела — не дальше REACH позади конца ствола 1-го уровня
MOUTH = 12           # px: вспышка заходит на ствол (как у 1-го уровня)
# Холст шире на PAD px с каждой стороны — вспышка у стволов уровня не срезается краем (раз: по исходной ширине)
PAD = {"tower": (428, 60)}
DIFF = 60            # сумма |ΔRGB| (0..765): пиксель изменился
ALPHA = 160


def barrel_tip(img):
    a = np.array(img)[..., 3] > ALPHA
    ys, xs = np.nonzero(a)
    right = xs.max()
    rows = np.unique(ys[xs >= right - BARREL_SLACK])
    return float(right), float(rows.mean())


def shot_layer(frame, first, tip_x):
    """Вспышка и дым кадра выстрела: пиксели, которых нет в кадре 0 ряда, яркие тёплые (огонь) или светло-серые
    (дым), не дальше REACH px позади конца ствола (корпус не берётся)."""
    f = np.array(frame).astype(int)
    z = np.array(first).astype(int)
    changed = (np.abs(f[..., :3] - z[..., :3]).sum(-1) > DIFF) | (np.abs(f[..., 3] - z[..., 3]) > 40)
    r, g, b = f[..., 0] / 255, f[..., 1] / 255, f[..., 2] / 255
    mx, mn = np.maximum(np.maximum(r, g), b), np.minimum(np.minimum(r, g), b)
    fire = (mx > 0.7) & (r >= g) & (g >= b)
    smoke = (mx > 0.4) & ((mx - mn) < 0.12)
    near = np.zeros(changed.shape, bool)
    near[:, max(0, int(tip_x) - REACH):] = True
    keep = changed & (fire | smoke) & near & (f[..., 3] > 0)
    layer = f.copy()
    layer[~keep] = 0
    return Image.fromarray(layer.astype(np.uint8)), keep


def pad_canvas(folder, name):
    """Все ряды здания — на холст шире на px с каждой стороны (низ на месте). Масштаб модели — по непрозрачной
    ширине (Building body_width), ствол — от центра низа кадра: не меняются."""
    if name not in PAD:
        return
    width, px = PAD[name]
    if Image.open(folder / "idle" / "0.png").width != width:
        return
    for f in folder.glob("*/*.png"):
        im = Image.open(f).convert("RGBA")
        c = Image.new("RGBA", (im.width + 2 * px, im.height))
        c.paste(im, (px, 0))
        c.save(f)
    print(f"  холст +{px} px с каждой стороны")


def rebuild(folder):
    l1 = sorted((folder / "attack").glob("*.png"), key=lambda p: int(p.stem))
    frames1 = [Image.open(p).convert("RGBA") for p in l1]
    tip1 = barrel_tip(Image.open(folder / "idle" / "0.png").convert("RGBA"))
    layers = [shot_layer(f, frames1[0], tip1[0]) for f in frames1]
    # якорь — левый край и середина вспышки на кадре с наибольшей вспышкой: там рот ствола 1-го уровня
    peak = max(range(len(layers)), key=lambda k: layers[k][1].sum())
    ys, xs = np.nonzero(layers[peak][1])
    anchor = (float(np.percentile(xs, 3)), float(ys.mean()))
    for level in (2, 3):
        row = folder / f"attack_{level}"
        if not row.is_dir():
            continue
        base = Image.open(folder / f"idle_{level}" / "0.png").convert("RGBA")
        tip = barrel_tip(base)
        dx, dy = round(tip[0] - anchor[0]) - MOUTH, round(tip[1] - anchor[1])
        for k, (layer, _) in enumerate(layers):
            out = base.copy()
            out.alpha_composite(_shift(layer, dx, dy))
            out.save(row / f"{k}.png")
        print(f"  уровень {level}: ствол {tip}, вспышка 1-го от {anchor} (кадр {peak}), сдвиг ({dx}, {dy}), кадров {len(layers)}")


def _shift(img, dx, dy):
    c = Image.new("RGBA", img.size)
    c.paste(img, (dx, dy))
    return c


def main(args):
    for name in args or REBUILD:
        print(name)
        pad_canvas(BUILDINGS / name, name)
        rebuild(BUILDINGS / name)


if __name__ == "__main__":
    main(sys.argv[1:])
