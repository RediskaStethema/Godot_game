"""Листы уровней зданий 6×4 (пакет художника 05.11.2026) → кадры <анимация>_<уровень>_NN.png на холсте 1-го
уровня — пакет для building_levels_add.py.

    python tools/building_levels_sheets.py <папка листов> <папка пакета кадров> [здание …]   # без зданий — все
    PYTHONPATH=tools python tools/building_levels_add.py <папка пакета кадров> <здание …>
    python tools/building_levels_muzzle.py            # стволы рядов выстрела 2 / 3 уровня

Лист — 24 кадра сеткой 6×4 (ячейки ≈ 336 px, у Апотекариона и Кодекс-бастиона — свои; здание в ячейках съезжает — align): кадры 0–11 — стойка,
12–23 — работа / выстрел (нарастание, вспышка, затухание). Раскладка по рядам (решение 06.11.2026):
- у здания только стойка (IDLE_ONLY) — все 24 кадра одной стойкой: работа идёт в цикле, иначе пропала бы;
- Казармы и Святилище культа — 0–11 стойка, 12–23 пополнение (refill);
- стрелки (ATTACK) — 0–11 стойка; выстрел — столько кадров, сколько у ряда 1-го уровня, окно из 12–23 так,
  чтобы кадр вспышки (наибольшая яркая оранжевая площадь) стоял на metadata/shot_frame 1-го уровня: кадр
  вылета снаряда в коде один на все уровни.
Холст — как у кадров 1-го уровня (building_levels_add.py сравнивает их попиксельно). Силуэт кадра 0 ставится на
место силуэта 1-го уровня (не помещается ряд — ближе к нему, насколько позволяет холст), низ — на низ 1-го;
точный сдвиг постамента найдёт building_levels_add.py (metadata/level_shift). Что вылезает за холст — печатается
и срезается: 06.11.2026 холст 1-го уровня расширен по бокам у Шатра Слаанеш (+58 px с каждой стороны),
Варп-разлома (+60), Святилища культа (+27) и Thunderfire (+28 и +37 сверху) — эффекты нового рисунка шире;
сверху — только где масштаб здания задан шириной (Building._base_scale берёт полную высоту холста).
"""
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

BUILDINGS = Path("assets/sprites/buildings")
FOLDERS = {"bolter_turret": "tower", "heretic_autocannon": "chaos/tower", "thunderfire_cannon": "artillery", "hellfire_mortar": "chaos/artillery",
           "barracks": "barracks", "cult_shrine": "chaos/barracks", "apothecarion": "apothecarion",
           "warp_rift": "chaos/apothecarion"}
# Листы без обычного имени <здание>_*_l<уровень>.png
SHEETS = {"codex_bastion": {2: "exec-8e6a41ed-4c87-44ee-ac38-ea4dff43b8a1.png",
                            3: "exec-ae0fd419-b3bd-4052-a36d-6b2443bd06f1.png"},
          "apothecarion": {2: "apothecarion_idle_work_spritesheet.png", 3: "apothecarion_idle_work_spritesheet_l3.png"}}
IDLE_ONLY = ["apothecarion", "pleasure_shrine", "skull_altar", "vulkan_forge", "warp_rift", "codex_bastion"]
REFILL = ["barracks", "cult_shrine"]
ATTACK = ["bolter_turret", "fists_bastion", "hellfire_mortar", "heretic_autocannon", "thunderfire_cannon"]
COLS, ROWS = 6, 4


def cells(path):
    im = Image.open(path).convert("RGBA")
    cw, ch = im.width / COLS, im.height / ROWS
    return align([im.crop((round(c * cw), round(r * ch), round((c + 1) * cw), round((r + 1) * ch)))
                  for r in range(ROWS) for c in range(COLS)])


def pedestal_iou(a, b, dx, dy, y0, y1):
    """Совпадение постамента: строки y0..y1 маски a против b, сдвинутой на (dx, dy)."""
    h, w = a.shape
    if y0 + dy < 0 or y1 + dy > h:
        return -1.0
    ra = a[y0:y1]
    rb = b[y0 + dy:y1 + dy]
    if dx >= 0:
        ra, rb = ra[:, :w - dx], rb[:, dx:]
    else:
        ra, rb = ra[:, -dx:], rb[:, :w + dx]
    return (ra & rb).sum() / max(1, (ra | rb).sum())


ALIGN_RANGE = (90, 30)   # px: поиск сдвига ячейки по x, y
ALIGN_STEP = 3           # px: шаг грубого поиска, затем точно ±шаг
ALIGN_PAD = 80       # px: запас холста ячейки — выровненный кадр не срезается


def drop_neighbours(c, alpha=8, scale=2):
    """Сетка художника неровная — в ячейку заходит край соседнего кадра листа (06.11.2026: полоска у левого края
    Кодекс-бастиона 3-го уровня). Убираются куски, которые касаются края ячейки и не связаны с крупнейшим
    (зданием); связность — по маске в 1/scale (кусок дыма / свечения, оторванный от здания, но не у края — остаётся)."""
    a = np.array(c)
    m = a[::scale, ::scale, 3] > alpha
    h, w = m.shape
    label = np.zeros(m.shape, int)
    sizes, edge = [0], [False]
    n = 0
    for y0, x0 in zip(*np.nonzero(m)):
        if label[y0, x0]:
            continue
        n += 1
        label[y0, x0] = n
        stack, size, touches = [(y0, x0)], 0, False
        while stack:
            y, x = stack.pop()
            size += 1
            touches = touches or y in (0, h - 1) or x in (0, w - 1)
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < h and 0 <= nx < w and m[ny, nx] and not label[ny, nx]:
                        label[ny, nx] = n
                        stack.append((ny, nx))
        sizes.append(size)
        edge.append(touches)
    if n < 2:
        return c
    main = int(np.argmax(sizes))
    drop = [i for i in range(1, n + 1) if i != main and edge[i]]
    if not drop:
        return c
    full = np.kron(np.isin(label, drop), np.ones((scale, scale), bool))[:a.shape[0], :a.shape[1]]
    a[full] = 0
    return Image.fromarray(a)


def align(cs):
    """Сетка художника не равна «лист / 6×4»: здание в ячейках съезжает (06.11.2026: у Варп-разлома, Шатра Слаанеш,
    Кузни, Святилища культа, Апотекариона — до 40–70 px по ряду, назад — с новой строкой листа; в игре здание
    ползло по клетке). Каждая ячейка — постаментом на постамент ячейки 0: наибольшее совпадение нижних 35% силуэта,
    поиск в ±ALIGN_RANGE шагом ALIGN_STEP и точно вокруг (точка основания не годится — свечение у основания
    сбивает самую широкую строку)."""
    cs = [drop_neighbours(c) for c in cs]
    masks = [np.array(c)[..., 3] > 200 for c in cs]
    ys = np.nonzero(masks[0])[0]
    y1 = ys.max() + 1
    y0 = y1 - int((y1 - ys.min()) * 0.35)
    out = []
    for c, m in zip(cs, masks):
        best, dx, dy = -1.0, 0, 0
        for ddy in range(-ALIGN_RANGE[1], ALIGN_RANGE[1] + 1, ALIGN_STEP):   # грубо — шагом
            for ddx in range(-ALIGN_RANGE[0], ALIGN_RANGE[0] + 1, ALIGN_STEP):
                s = pedestal_iou(masks[0], m, ddx, ddy, y0, y1)
                if s > best:
                    best, dx, dy = s, ddx, ddy
        gx, gy = dx, dy
        for ddy in range(gy - ALIGN_STEP, gy + ALIGN_STEP + 1):   # точно — вокруг
            for ddx in range(gx - ALIGN_STEP, gx + ALIGN_STEP + 1):
                s = pedestal_iou(masks[0], m, ddx, ddy, y0, y1)
                if s > best:
                    best, dx, dy = s, ddx, ddy
        a = Image.new("RGBA", (c.width + 2 * ALIGN_PAD, c.height + 2 * ALIGN_PAD))
        a.paste(c, (ALIGN_PAD - dx, ALIGN_PAD - dy), c)
        out.append(a)
    return out


def bbox(img, thr=128):
    ys, xs = np.nonzero(np.array(img)[..., 3] > thr)
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def flash(img):
    """Пикселей вспышки: яркий насыщенный оранжево-жёлтый."""
    r, g, b, al = np.moveaxis(np.array(img).astype(float) / 255, -1, 0)
    mx, mn = np.maximum(np.maximum(r, g), b), np.minimum(np.minimum(r, g), b)
    return int(((al > 0.5) & (mx > 0.9) & ((mx - mn) / np.maximum(mx, 1e-6) > 0.35) & (r >= g) & (g > b)).sum())


def place(frames, canvas, ref_box):
    """Все кадры уровня — одним сдвигом на холст 1-го уровня. Возвращает кадры и вылет за холст по сторонам."""
    boxes = [bbox(f, 8) for f in frames]
    ux0, ux1 = min(b[0] for b in boxes), max(b[2] for b in boxes)
    fx0, _, fx1, fy1 = bbox(frames[0])
    want = round((ref_box[0] + ref_box[2]) / 2 - (fx0 + fx1) / 2)
    lo, hi = -ux0, canvas[0] - ux1
    dx = round((canvas[0] - (ux1 - ux0)) / 2 - ux0) if lo > hi else min(max(want, lo), hi)
    dy = ref_box[3] - fy1
    out = []
    for f in frames:
        c = Image.new("RGBA", canvas)
        c.paste(f, (dx, dy), f)
        out.append(c)
    over = {"слева": -(ux0 + dx), "справа": ux1 + dx - canvas[0],
            "сверху": -(min(b[1] for b in boxes) + dy), "снизу": max(b[3] for b in boxes) + dy - canvas[1]}
    return out, {k: int(v) for k, v in over.items() if v > 0}


def sheet_of(src, name, level):
    named = SHEETS.get(name, {}).get(level)
    return src / named if named else next(src.glob(f"{name}_*_l{level}.png"))


def main(src, out, only=()):
    for name in [n for n in IDLE_ONLY + REFILL + ATTACK if not only or n in only]:
        dst = BUILDINGS / FOLDERS.get(name, name)
        l1 = Image.open(dst / "idle" / "0.png").convert("RGBA")
        tres = (dst / "frames.tres").read_text(encoding="utf-8")
        m = re.search(r"shot_frame = (\d+)", tres)
        shot = int(m.group(1)) if m else 0
        n_attack = len(list((dst / "attack").glob("*.png"))) if (dst / "attack").is_dir() else 0
        (out / name).mkdir(parents=True, exist_ok=True)
        for level in (2, 3):
            cs = cells(sheet_of(src, name, level))
            if name in IDLE_ONLY:
                rows = {"idle": cs}
            elif name in REFILL:
                rows = {"idle": cs[:12], "refill": cs[12:]}
            else:
                fl = [flash(c) for c in cs]
                peak = 12 + int(np.argmax(fl[12:]))
                start = max(12, min(peak - shot, len(cs) - n_attack))
                rows = {"idle": cs[:12], "attack": cs[start:start + n_attack]}
                print(f"  выстрел: вспышка на кадре листа {peak}, ряд {start}..{start + n_attack - 1}, "
                      f"вспышка на кадре ряда {peak - start} (shot_frame {shot})")
            placed, over = place(sum(rows.values(), []), l1.size, bbox(l1))
            frames = iter(placed)
            for anim, row in rows.items():
                for k in range(len(row)):
                    next(frames).save(out / name / f"{anim}_{level}_{k:02d}.png")
            print(f"{name} уровень {level}: " + ", ".join(f"{a} {len(r)}" for a, r in rows.items())
                  + f", холст {l1.size}" + (f", срезано за холстом {over} px" if over else ""))


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3:])
