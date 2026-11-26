"""Единый размер пикселя (17.11.2026, скилл game-stylization, «миксели»): сколько экранных пикселей занимает один пиксель арта
у зданий, плит поля и юнитов — при масштабе, в котором их показывает игра (камера ×1).

  python tools/pixel_audit.py            — таблица и выбросы
  python tools/pixel_audit.py --all      — построчно все здания и ряды

Как считается:
  блок арта — самая частая длина горизонтальной серии одинакового цвета (≥ 2 px) в кадре: у пиксель-арта это шаг сетки
  (здания после building_pixelize.py — 3–5 px холста), у сглаженных кадров серий нет (юниты) — «гладкий»;
  масштаб на экране — как в игре: здание — ширина непрозрачной части idle → TILE_WIDTH × SPRITE_WIDTH (140 × 0.68 = 95 px),
  юнит — рост по кадру idle → TARGET_SPRITE_HEIGHT (31 px) × sprite_scale (берётся 1.0: у разных юнитов 1.0–1.35),
  плита поля — 1:1 (ромб 140 × 70);
  пиксель на экране = блок × масштаб.
Выброс — пиксель на экране больше 1.6 или меньше 0.6 медианы категории «здания». Читает PNG напрямую, Godot не нужен.
"""
import argparse
import glob
import os
import statistics
import sys
from collections import Counter
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
TILE_WIDTH = 140.0
SPRITE_WIDTH = 0.68          # Building.SPRITE_WIDTH
SPRITE_MAX_HEIGHT = 1.0625   # Building.SPRITE_MAX_HEIGHT: узкие и высокие (тотем, шпиль, чаша) — по высоте, не по ширине
UNIT_HEIGHT = 31.0           # Soldier.TARGET_SPRITE_HEIGHT
ALPHA = 128


def runs(img: np.ndarray):
    """длины горизонтальных серий одного цвета (непрозрачных) — по каждой 3-й строке (быстро)"""
    out = Counter()
    h, w = img.shape[:2]
    for y in range(0, h, 3):
        row = img[y]
        if row[:, 3].max() < ALPHA:
            continue
        start = 0
        for x in range(1, w + 1):
            if x == w or tuple(row[x]) != tuple(row[start]):
                n = x - start
                if row[start][3] >= ALPHA and n >= 2:
                    out[n] += 1
                start = x
    return out


def block(img: np.ndarray):
    c = runs(img)
    if not c:
        return None, 0.0
    total = sum(c.values())
    # блок = наименьшая длина серии, на которую приходится не меньше 12% всех серий (мелкие шумовые не считаются)
    for n in sorted(c):
        if c[n] / total >= 0.12:
            smooth = c.get(2, 0) / total < 0.05 and (c.get(1, 0) == 0)
            return n, c[n] / total
    return None, 0.0


def bbox(img: np.ndarray):
    a = img[..., 3] > ALPHA
    ys, xs = np.nonzero(a)
    if len(xs) == 0:
        return None
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def audit_building(path: Path):
    img = np.asarray(Image.open(path).convert("RGBA"))
    bb = bbox(img)
    if bb is None:
        return None
    width = bb[2] - bb[0]
    scale = min(TILE_WIDTH * SPRITE_WIDTH / width, TILE_WIDTH * SPRITE_MAX_HEIGHT / img.shape[0])   # как Building._base_scale
    b, share = block(img[bb[1]:bb[3], bb[0]:bb[2]])
    return {"block": b, "scale": scale, "px": (b * scale) if b else None, "share": share, "width": width}


def audit_unit(path: Path):
    img = np.asarray(Image.open(path).convert("RGBA"))
    bb = bbox(img)
    if bb is None:
        return None
    height = bb[3] - bb[1]
    scale = UNIT_HEIGHT / height
    b, share = block(img[bb[1]:bb[3], bb[0]:bb[2]])
    return {"block": b, "scale": scale, "px": (b * scale) if b else None, "share": share, "height": height}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--all", action="store_true")
    a = ap.parse_args()
    bpx = []
    rows = []
    for d in sorted(glob.glob(str(ROOT / "assets/sprites/buildings/*/frames.tres")) + glob.glob(str(ROOT / "assets/sprites/buildings/chaos/*/frames.tres"))):
        folder = Path(d).parent
        name = folder.name if folder.parent.name == "buildings" else "chaos/" + folder.name
        if folder.name.endswith("wall"):
            continue
        p = folder / "idle" / "0.png"
        if not p.exists():
            continue
        r = audit_building(p)
        if r is None:
            continue
        rows.append((name, r))
        if r["px"]:
            bpx.append(r["px"])
    med = statistics.median(bpx) if bpx else 1.0
    print("ЗДАНИЯ (idle/0): блок арта (px холста) × масштаб = пиксель на экране; медиана %.2f" % med)
    out = []
    for name, r in rows:
        flag = ""
        if r["px"] and (r["px"] > med * 1.6 or r["px"] < med * 0.6):
            flag = "  !! выброс"
            out.append(name)
        if a.all or flag:
            print("  %-22s блок %s × %.2f = %s%s" % (name, r["block"], r["scale"], ("%.2f" % r["px"]) if r["px"] else "гладкий", flag))
    print("  здания в пределах 0.6–1.6 медианы: %d из %d" % (len(rows) - len(out), len(rows)))
    print()
    print("ЮНИТЫ (idle/0, sprite_scale = 1): блок × масштаб = пиксель на экране")
    unit_px = []
    for d in sorted(glob.glob(str(ROOT / "assets/units/space_marines/*/idle/0.png")) + glob.glob(str(ROOT / "assets/units/chaos/*/idle/0.png"))):
        p = Path(d)
        r = audit_unit(p)
        if r is None:
            continue
        race = p.parent.parent.parent.name
        unit = p.parent.parent.name
        if r["px"]:
            unit_px.append(r["px"])
        if a.all:
            print("  %-26s рост %3d → ×%.2f, блок %s, пиксель на экране %s" % (race + "/" + unit, r["height"], r["scale"], r["block"], ("%.2f" % r["px"]) if r["px"] else "гладкий"))
    smooth = sum(1 for d in glob.glob(str(ROOT / "assets/units/*/*/idle/0.png")) if (audit_unit(Path(d)) or {}).get("px") is None)
    print("  юнитов с блочным рисунком: %d, гладких: %d (гладкие кадры сжимаются фильтром — «миксели» не образуются)" % (len(unit_px), smooth))
    if unit_px:
        print("  блочные юниты: пиксель на экране %.2f … %.2f (медиана %.2f)" % (min(unit_px), max(unit_px), statistics.median(unit_px)))
    print()
    print("ВЫВОД: цель — у зданий и блочных юнитов пиксель на экране в пределах 0.6–1.6 медианы зданий (%.2f)." % med)
    if out:
        print("  вне предела: " + ", ".join(out))
        sys.exit(1)


if __name__ == "__main__":
    main()
