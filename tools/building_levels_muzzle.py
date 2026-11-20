"""Стволы рядов выстрела 2-го и 3-го уровня зданий → metadata/level_muzzle {уровень: Vector2} в frames.tres.

    python tools/building_levels_muzzle.py [папка здания …]      # по умолчанию — все здания с рядом attack_2

Нужен после каждого прогона building_levels_add.py (он снимает все metadata/level_*). У нового рисунка
(пакет 05.11.2026) стволы не там, где у 1-го уровня: Building._sprite_muzzle берёт точку уровня, если она есть.
Мера — как у metadata/muzzle: от центра низа кадра, px холста ряда. Точка — по пикселям, которые загораются
только в кадре выстрела (shot_frame) относительно стойки уровня: у прямой наводки — передний (правый) край
вспышки, у мортиры (UP) — верх самого крупного пятна, жерло (не летящий снаряд над ним).
Шпиль варпа (TIP) — вершина силуэта стойки уровня.
Залп (решение пользователя 06.11.2026 «залп из всех стволов»): metadata/level_barrels {уровень: [Vector2, …]} —
по стволу на каждую отдельную вспышку кадра выстрела (уровни 1–3, только где стволов больше одного): пятно
не меньше BARREL_MIN_SHARE крупнейшего (слившиеся вспышки соседних стволов — делит split_valley) и BARREL_MIN_PIXELS, передний край — не дальше BARREL_FRONT px позади
самого переднего (огни корпуса и гильзы не в счёт). Building стреляет из каждого, урон делится поровну. Ряды OLD_FLASH (вспышка 1-го уровня на прежнем месте) и ряд без вспышки — точка 1-го уровня
(неживой по движению корпуса ряд — metadata/level_static — может быть новым рисунком со своими стволами).
"""
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

BUILDINGS = Path("assets/sprites/buildings")
UP = {"chaos/artillery"}
# Ряды выстрела с вспышкой 1-го уровня на прежнем месте холста (пусто: Bolter Turret 06.11.2026 пересобран —
# building_levels_attack_rebuild.py, вспышка у стволов уровня)
OLD_FLASH = set()
# Выстрел без вспышки в листе (снаряд — молния варпа): ствол уровня — вершина силуэта (ТЗ: «молния из своей вершины»)
TIP = {"warp_spire"}
TIP_DEPTH = 10   # px под вершиной
MIN_PIXELS = 40
BARREL_MIN_SHARE = 0.3
VALLEY = 0.4         # вспышки соседних стволов слились: столбец ≤ VALLEY меньшего из пиков по бокам — граница
BARREL_MIN_PIXELS = 100
# Вспышки мельче у пиксельных кадров (пакет Хаоса 13.11.2026: турель 3-го уровня — пятна 112 и 80 px)
BARREL_MIN_PIXELS_OVERRIDE = {"chaos/tower": 40}
BARREL_FRONT = 90
SETTLED = 3          # кадр ряда выстрела через SETTLED после shot_frame — вспышка погасла (эталон без вспышки)


def new_flash(shot, idle):
    a = np.array(Image.open(shot).convert("RGBA")).astype(float) / 255
    r, g, b, al = np.moveaxis(a, -1, 0)
    mx = np.maximum(np.maximum(r, g), b)
    bright = (al > 0.5) & (mx > 0.8) & (r >= b) & (r > 0.75)
    # пакет 13.11.2026: стойка живая — огни корпуса мигают; вспышка — то, что не горит ни в одном кадре стойки уровня
    # и ни в одном кадре ряда выстрела дальше SETTLED от выстрела (вспышки ещё / уже нет; ряд стойки стоит на холсте
    # иначе — золото корпуса Imperial Fists отличалось от неё и шло за вспышку)
    refs = sorted(Path(idle).parent.glob("*.png"), key=lambda p: int(p.stem))
    row = sorted(Path(shot).parent.glob("*.png"), key=lambda p: int(p.stem))
    refs += [p for p in row if abs(int(p.stem) - int(Path(shot).stem)) >= SETTLED]   # до выстрела и после
    for ref in refs:
        i = np.array(Image.open(ref).convert("RGBA")).astype(float) / 255
        if i.shape != a.shape:
            continue
        bright &= np.abs(a[..., :3] - i[..., :3]).sum(-1) > 0.5
    return bright


def largest_blob(mask, gap=3):
    pts = set(zip(*np.nonzero(mask)))
    best = []
    while pts:
        stack, blob = [pts.pop()], []
        while stack:
            y, x = stack.pop()
            blob.append((y, x))
            for dy in range(-gap, gap + 1):
                for dx in range(-gap, gap + 1):
                    q = (y + dy, x + dx)
                    if q in pts:
                        pts.remove(q)
                        stack.append(q)
        if len(blob) > len(best):
            best = blob
    out = np.zeros_like(mask)
    for y, x in best:
        out[y, x] = True
    return out


def blobs(mask, gap=2):
    """Связные пятна маски (соседство до gap px), крупные — первыми."""
    pts = set(zip(*np.nonzero(mask)))
    out = []
    while pts:
        stack, blob = [pts.pop()], []
        while stack:
            y, x = stack.pop()
            blob.append((y, x))
            for dy in range(-gap, gap + 1):
                for dx in range(-gap, gap + 1):
                    q = (y + dy, x + dx)
                    if q in pts:
                        pts.remove(q)
                        stack.append(q)
        out.append(np.array(blob))
    return sorted(out, key=len, reverse=True)


def split_valley(b):
    """Две вспышки стволов рядом слились в одно пятно (Bolter Turret 2-го уровня): делит по самому тонкому столбцу,
    если он тоньше VALLEY меньшего из пиков слева и справа и обе части не меньше трети пятна."""
    xs = b[:, 1]
    x0 = xs.min()
    cols = np.bincount(xs - x0)
    best = None
    for i in range(2, len(cols) - 2):
        left, right = cols[:i].max(), cols[i + 1:].max()
        if cols[i] <= VALLEY * min(left, right):
            a, c = (xs < x0 + i).sum(), (xs > x0 + i).sum()
            if min(a, c) >= len(b) / 3 and (best is None or cols[i] < cols[best]):
                best = i
    if best is None:
        return [b]
    return [b[xs < x0 + best], b[xs > x0 + best]]


def barrels(folder, shot, up):
    """{уровень: [(x, y), …]} — ствол на каждую вспышку кадра выстрела, где их больше одной (мера — как у muzzle)."""
    found = {}
    min_px = BARREL_MIN_PIXELS_OVERRIDE.get(folder.relative_to(BUILDINGS).as_posix(), BARREL_MIN_PIXELS)
    for level in (1, 2, 3):
        sfx = "" if level == 1 else f"_{level}"
        f = folder / f"attack{sfx}" / f"{shot}.png"
        if not f.exists():
            continue
        bs = blobs(new_flash(f, folder / f"idle{sfx}" / "0.png"))
        if not up:
            bs = sorted((part for b in bs for part in (split_valley(b) if len(b) >= min_px else [b])),
                        key=len, reverse=True)
        if not bs:
            continue
        front = (lambda b: -b[:, 0].min()) if up else (lambda b: b[:, 1].max())
        lead = max(front(b) for b in bs if len(b) >= min_px) if len(bs[0]) >= min_px else 0
        keep = [b for b in bs if len(b) >= max(min_px, BARREL_MIN_SHARE * len(bs[0]))
                and front(b) >= lead - BARREL_FRONT]
        if len(keep) < 2:
            continue
        w, h = Image.open(f).size
        pts = []
        for b in keep:
            ys, xs = b[:, 0], b[:, 1]
            sel = (ys <= np.percentile(ys, 10)) if up else (xs >= np.percentile(xs, 85))
            pts.append((round(float(xs[sel].mean()) - w / 2.0, 1), round(float(ys[sel].mean()) - h, 1)))
        found[level] = sorted(pts, key=lambda q: q[1])
        print(f"  залп, уровень {level}: стволов {len(pts)} {found[level]}")
    return found


DIR_MAX_ANGLE = 60.0   # градусов от горизонтали — больше не бывает (крупная вспышка-звезда сбивает ось)
DIR_SKIP = {"artillery", "chaos/artillery"}   # орудия игрока — ракета по дуге в точку клика (Projectile.arc_height)
# Ось по вспышке ошибается, где вспышка — мелкая звезда с дымом или стволов два (06.11.2026: Heretic Autocannon 2–3
# и Bolter Turret 2–3 уровня — до 30° мимо): угол от горизонтали в градусах (+ — вниз), замерен по стволам на
# кадре стойки уровня с сеткой. Бастион Imperial Fists — по вспышке (совпало с рисунком)
DIR_OVERRIDE = {
    "tower": {1: 0.0, 2: 15.0, 3: 12.0},
    "chaos/tower": {1: -16.0, 2: -12.0, 3: -10.0},   # пакет 13.11.2026
}


def barrel_dir(folder, shot, level):
    """Ось ствола уровня (решение пользователя 06.11.2026: «снаряд турели должен лететь по направлению дула»):
    от задней части вспышки кадра выстрела (15% по x) к передней (85%) — вспышка вытянута вдоль ствола.
    Единичный вектор, «смотрит вправо» (x > 0), как и лист; None — вспышки нет."""
    sfx = "" if level == 1 else f"_{level}"
    f = folder / f"attack{sfx}" / f"{shot}.png"
    idle = folder / f"idle{sfx}" / "0.png"
    if not f.exists() or not idle.exists():
        return None
    name = folder.relative_to(BUILDINGS).as_posix()
    if level in DIR_OVERRIDE.get(name, {}):
        a = np.radians(DIR_OVERRIDE[name][level])
        return round(float(np.cos(a)), 3), round(float(np.sin(a)), 3)
    mask = largest_blob(new_flash(f, idle))
    ys, xs = np.nonzero(mask)
    if len(xs) < MIN_PIXELS:
        return None
    back = xs <= np.percentile(xs, 15)
    front = xs >= np.percentile(xs, 85)
    d = np.array([xs[front].mean() - xs[back].mean(), ys[front].mean() - ys[back].mean()])
    if d[0] <= 0:
        return None
    ang = float(np.clip(np.degrees(np.arctan2(d[1], d[0])), -DIR_MAX_ANGLE, DIR_MAX_ANGLE))
    return round(float(np.cos(np.radians(ang))), 3), round(float(np.sin(np.radians(ang))), 3)


def muzzle(folder):
    tres = folder / "frames.tres"
    text = tres.read_text(encoding="utf-8")
    m = re.search(r"shot_frame = (\d+)", text)
    name = folder.relative_to(BUILDINGS).as_posix()
    if not m and name not in TIP:
        print("  нет metadata/shot_frame — пропуск")
        return
    shot = int(m.group(1)) if m else 0
    found = {}
    for level in (2, 3):
        f = folder / f"attack_{level}" / f"{shot}.png"
        if not f.exists():
            continue
        if name in TIP:   # вспышки в листе нет — заряд с вершины силуэта стойки уровня
            a = np.array(Image.open(folder / f"idle_{level}" / "0.png").convert("RGBA"))[..., 3] > 200
            ys, xs = np.nonzero(a)
            top = ys.min()
            w, h = a.shape[1], a.shape[0]
            found[level] = (round(float(xs[ys <= top + TIP_DEPTH].mean()) - w / 2.0, 1), round(float(top + TIP_DEPTH) - h, 1))
            print(f"  уровень {level}: вершина {found[level]}")
            continue
        if name in OLD_FLASH:
            print(f"  уровень {level}: вспышка 1-го уровня на прежнем месте (OLD_FLASH) — ствол 1-го уровня")
            continue
        mask = new_flash(f, folder / f"idle_{level}" / "0.png")
        if name in UP:
            mask = largest_blob(mask)
        ys, xs = np.nonzero(mask)
        if len(xs) < MIN_PIXELS:
            print(f"  уровень {level}: вспышки нет — ствол 1-го уровня")
            continue
        sel = (ys <= np.percentile(ys, 10)) if name in UP else (xs >= np.percentile(xs, 85))
        w, h = Image.open(f).size
        found[level] = (round(float(xs[sel].mean()) - w / 2.0, 1), round(float(ys[sel].mean()) - h, 1))
        print(f"  уровень {level}: ствол {found[level]}")
    text = re.sub(r"metadata/level_muzzle = [^\n]*\n", "", text)
    text = re.sub(r"metadata/level_barrels = [^\n]*\n", "", text)
    text = re.sub(r"metadata/level_barrel_dir = [^\n]*\n", "", text)
    if name not in TIP and name not in DIR_SKIP:
        dirs = {lv: d for lv in (1, 2, 3) if (d := barrel_dir(folder, shot, lv)) is not None}
        for lv, d in sorted(dirs.items()):
            print(f"  уровень {lv}: ось ствола {d}")
        if dirs:
            line = "metadata/level_barrel_dir = {" + ", ".join(
                f"{lv}: Vector2({x}, {y})" for lv, (x, y) in sorted(dirs.items())) + "}\n"
            text = text.replace("\n[resource]\n", "\n[resource]\n" + line, 1)
    if name not in TIP:
        volley = barrels(folder, shot, name in UP)
        if volley:
            line = "metadata/level_barrels = {" + ", ".join(f"{lv}: [" + ", ".join(
                f"Vector2({x}, {y})" for x, y in pts) + "]" for lv, pts in sorted(volley.items())) + "}\n"
            text = text.replace("\n[resource]\n", "\n[resource]\n" + line, 1)
    if found:
        line = "metadata/level_muzzle = {" + ", ".join(
            f"{lv}: Vector2({x}, {y})" for lv, (x, y) in sorted(found.items())) + "}\n"
        text = text.replace("\n[resource]\n", "\n[resource]\n" + line, 1)
    tres.write_text(text, encoding="utf-8")


def main(args):
    folders = [BUILDINGS / a for a in args] or sorted({p.parent for p in BUILDINGS.rglob("attack_2")})
    for folder in folders:
        print(folder.relative_to(BUILDINGS).as_posix())
        muzzle(folder)


if __name__ == "__main__":
    main(sys.argv[1:])
