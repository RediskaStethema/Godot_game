"""Выстрел турели кодом поверх кадров художника (решение пользователя 13.11.2026: «Heretic Autocannon — нет анимации
стрельбы»: в пакете Хаоса 13.11.2026 ряды attack / attack_2 / attack_3 — стойка и дымок в 15 px перед дулом, после
пиксель-прохода выстрела не видно).

По кадрам ряда выстрела (shot_frame — выстрел):
  кадр shot-1 — жерло накаляется;
  кадр shot   — отдача ствола (RECOIL пикселей арта назад по оси), пламя по оси ствола (кромка → ядро), жерло горит;
  shot+1      — пламя короче, ствол возвращается, клуб дыма, гильзы вылетают вверх-назад;
  shot+2..    — дым поднимается и тает, жерло остывает.
Жерло — крайний плотный пиксель стойки уровня по оси от прежней точки вспышки назад; ось — metadata/level_barrel_dir.
Стволы уровня — metadata/level_barrels, иначе level_muzzle / muzzle. Точки вылета (жерло + MUZZLE_AHEAD по оси)
записываются в frames.tres (muzzle / level_muzzle / level_barrels).

Порядок: tools/building_pixelize.py по зданию, затем этот скрипт. Он сохраняет чистые ряды выстрела после
пиксель-прохода в assets/source_sheets/buildings_redraw_2026-11-13/<здание>_attack_pixel/ и рисует поверх них
(повтор — от них; после нового пиксель-прохода эту папку удалить). Эффект — сразу в пикселях арта PX и своими цветами
огня FIRE (через общую палитру пиксель-прохода пламя гасло в бежевое).

  PYTHONIOENCODING=utf-8 python tools/building_shot_fx.py chaos/tower
"""
import math
import re
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
BUILDINGS = ROOT / "assets/sprites/buildings"
STASH = ROOT / "assets/source_sheets/building_pixel_orig"
KEEP = ROOT / "assets/source_sheets/buildings_redraw_2026-11-13"

PX = 4                            # пиксель арта здания (building_pixelize: у турели Хаоса — 4 px кадра)
RECOIL = [0, 2, 1, 0, 0]          # отдача ствола по кадрам ряда (0 — кадр shot-1), пикселей арта
FLAME_LEN = [0, 24, 12, 0, 0]     # длина пламени, пикселей арта
FLAME_W = [0, 11, 6, 0, 0]         # ширина у основания
HEAT = [0.5, 1.0, 0.9, 0.65, 0.35]   # накал жерла
SMOKE = [0, 0, 1.0, 0.85, 0.5]  # плотность дыма
SMOKE_RISE = [0, 0, 1, 4, 7]      # подъём дыма, пикселей арта
SHELLS = [0, 0, 1, 1, 0]
BARREL_BACK = 70                  # px ствола от жерла назад — что откатывается
BARREL_R = 22                     # полуширина полосы ствола
MUZZLE_AHEAD = 6                  # точка вылета — перед жерлом, px кадра
FIRE = [(110, 14, 6), (200, 40, 10), (255, 110, 20), (255, 190, 60), (255, 245, 190)]
SMOKE_RGB = [(78, 70, 64), (104, 95, 86), (128, 118, 106)]

# Свой вид выстрела у здания (значения выше — турель Хаоса, пламя автопушки): Bolter Turret (решение пользователя
# 13.11.2026: «ассеты и фреймы прыгают» — ряды выстрела собраны из стойки уровня, tools/building_rows_hold.py) —
# короткая жёлто-белая вспышка болтера, отдача в пиксель, дымок меньше; PX — пиксель арта здания (building_pixelize)
STYLES = {
    "tower": {"PX": 4, "RECOIL": [0, 1, 1, 0, 0], "FLAME_LEN": [0, 11, 5, 0, 0], "FLAME_W": [0, 10, 6, 0, 0],
              "HEAT": [0.4, 1.0, 0.8, 0.55, 0.3], "SMOKE": [0, 0, 0.8, 0.6, 0.35], "SMOKE_RISE": [0, 0, 1, 3, 6],
              "BARREL_BACK": 50, "BARREL_R": 16,
              "FIRE": [(150, 50, 10), (235, 120, 25), (255, 190, 60), (255, 230, 120), (255, 252, 225)]},
}


_DEFAULTS = {k: globals()[k] for k in ("PX", "RECOIL", "FLAME_LEN", "FLAME_W", "HEAT", "SMOKE", "SMOKE_RISE",
                                         "SHELLS", "BARREL_BACK", "BARREL_R", "FIRE", "SMOKE_RGB")}


def apply_style(rel):
    globals().update(_DEFAULTS)
    globals().update(STYLES.get(rel, {}))


def meta(text, key):
    m = re.search(rf"metadata/{key} = ([^\n]*)", text)
    return m.group(1) if m else ""


def vecs(s):
    return [(float(x), float(y)) for x, y in re.findall(r"Vector2\(([-\d.]+), ([-\d.]+)\)", s)]


def level_points(text, level):
    """Точки ствола уровня (мера muzzle: от центра низа кадра) и ось."""
    bar = re.search(rf"\b{level}: \[([^\]]*)\]", meta(text, "level_barrels"))
    lm = re.search(rf"\b{level}: (Vector2\([^)]*\))", meta(text, "level_muzzle"))
    if bar:
        pts = vecs(bar.group(1))
    elif level > 1 and lm:
        pts = vecs(lm.group(1))
    else:
        pts = vecs(meta(text, "muzzle"))
    d = re.search(rf"\b{level}: (Vector2\([^)]*\))", meta(text, "level_barrel_dir"))
    dx, dy = vecs(d.group(1))[0] if d else (1.0, 0.0)
    n = math.hypot(dx, dy)
    return pts, (dx / n, dy / n)


def find_tip(alpha, p, d):
    """Жерло: от точки вспышки назад по оси до первого плотного места стойки (окно ±3 px поперёк)."""
    h, w = alpha.shape
    nx, ny = -d[1], d[0]
    for t in range(0, 80):
        x, y = p[0] - d[0] * t, p[1] - d[1] * t
        hits = 0
        for s in range(-3, 4):
            xi, yi = int(round(x + nx * s)), int(round(y + ny * s))
            if 0 <= xi < w and 0 <= yi < h and alpha[yi, xi] > 200:
                hits += 1
        if hits >= 4:
            return (x, y)
    return p


def barrel_mask(alpha, tip, d):
    h, w = alpha.shape
    yy, xx = np.mgrid[0:h, 0:w]
    rx, ry = xx - tip[0], yy - tip[1]
    along = rx * d[0] + ry * d[1]
    across = -rx * d[1] + ry * d[0]
    return (along <= 4) & (along >= -BARREL_BACK) & (np.abs(across) <= BARREL_R) & (alpha > 0)


def recoil(a, mask, d, n):
    """Ствол назад на n пикселей арта (сдвиг кратен PX — сетка арта не ломается)."""
    if n == 0:
        return a
    a = a.copy()
    part = np.zeros_like(a)
    part[mask] = a[mask]
    a[mask] = 0
    sx = -int(round(d[0] * n)) * PX
    sy = -int(round(d[1] * n)) * PX
    part = np.roll(np.roll(part, sy, 0), sx, 1)
    on = part[..., 3] > 0
    a[on] = part[on]
    return a


def put(g, x, y, rgb, alpha=255):
    h, w = g.shape[:2]
    x, y = int(round(x)), int(round(y))
    if 0 <= x < w and 0 <= y < h and alpha >= g[y, x, 3]:
        g[y, x] = (*rgb, alpha)


def step_alpha(v):
    return max(64, min(255, int(round(v / 64.0)) * 64))


def draw_fx(g, tip, d, j, seed, before):
    """Эффекты в пикселях арта на сетке g (h/PX × w/PX); tip — в px кадра."""
    rng = np.random.default_rng(seed)
    nx, ny = -d[1], d[0]
    tx, ty = tip[0] / PX, tip[1] / PX
    k = 0 if before else SMOKE[j]
    if k > 0:   # дым — под огнём
        for i in range(10):
            L = 1.5 + i * 1.3 + rng.normal(0, 0.5)
            cx = tx + d[0] * L + rng.normal(0, 0.8)
            cy = ty + d[1] * L - SMOKE_RISE[j] - i * 0.35 + rng.normal(0, 0.6)
            r = 1.2 + i * 0.18 + SMOKE_RISE[j] * 0.12
            col = SMOKE_RGB[int(rng.integers(0, 3))]
            for yy in range(int(cy - r - 1), int(cy + r + 2)):
                for xx in range(int(cx - r - 1), int(cx + r + 2)):
                    if (xx - cx) ** 2 + (yy - cy) ** 2 <= r * r:
                        put(g, xx, yy, col, step_alpha(255 * k * (1 - i / 14)))
    length = 0 if before else FLAME_LEN[j]
    width = FLAME_W[j]
    if length > 0:   # пламя: слои от кромки к ядру, рваный край
        jag = rng.normal(0, 0.18, 128)
        for li, (lk, wk) in enumerate(((1.0, 1.0), (0.85, 0.78), (0.65, 0.55), (0.45, 0.36), (0.25, 0.2))):
            ll, wl = length * lk, width * wk / 2
            for t3 in range(int(ll * 3) + 1):
                L = t3 / 3
                r = wl * (1 - L / max(ll, 1)) ** 0.7 * (1 + jag[t3 % 128])
                for s3 in range(-int(r * 3) - 1, int(r * 3) + 2):
                    sv = s3 / 3
                    if abs(sv) <= r:
                        put(g, tx + d[0] * L + nx * sv, ty + d[1] * L + ny * sv, FIRE[li])
        for _ in range(4):   # искры впереди
            L = length * (0.9 + rng.random() * 0.4)
            sv = rng.normal(0, width * 0.35)
            put(g, tx + d[0] * L + nx * sv, ty + d[1] * L + ny * sv, FIRE[3 + int(rng.integers(0, 2))])
    hk = HEAT[0] if before else HEAT[j]
    if hk > 0.3:   # накал жерла: пятно 3×3, центр ярче
        cx, cy = tx - d[0] * 0.6, ty - d[1] * 0.6
        for oy in (-1, 0, 1):
            for ox in (-1, 0, 1):
                core = ox == 0 and oy == 0
                col = FIRE[3] if (core and hk > 0.8) else (FIRE[2] if (hk > 0.6 or core) else FIRE[1])
                put(g, cx + ox, cy + oy, col, 255 if core else step_alpha(255 * hk))
    if not before and SHELLS[j]:   # гильзы — вверх и назад от казённой части
        bx, by = tx - d[0] * 10, ty - d[1] * 10
        for i in range(2):
            t = j - 1 + i * 0.6
            x = bx - 1.5 - 2.5 * t + rng.normal(0, 0.4)
            y = by - 3.5 * t + 2.2 * t * t
            put(g, x, y, (215, 165, 70))
            put(g, x + 1, y, (150, 105, 40))


def run(rel):
    unit = BUILDINGS / rel
    stash = STASH / rel
    text = (unit / "frames.tres").read_text(encoding="utf-8")
    shot = int(re.search(r"shot_frame = (\d+)", text).group(1))
    clean = KEEP / (rel.replace("/", "_") + "_attack_pixel")
    tips = {}
    for level in (1, 2, 3):
        sfx = "" if level == 1 else f"_{level}"
        row = unit / f"attack{sfx}"
        if not row.exists():
            continue
        if not (clean / row.name).exists():
            shutil.copytree(row, clean / row.name, ignore=shutil.ignore_patterns("*.import"))
        idle_src = stash / f"idle{sfx}" / "0.png"
        idle = np.array(Image.open(idle_src if idle_src.exists() else unit / f"idle{sfx}" / "0.png")
                        .convert("RGBA"))[..., 3]
        files = sorted((clean / row.name).glob("*.png"), key=lambda p: int(p.stem))
        w, h = Image.open(files[0]).size
        pts, d = level_points(text, level)
        tl = [find_tip(idle, (w / 2 + x, h + y), d) for x, y in pts]
        tips[level] = (tl, d, (w, h))
        yy, xx = np.mgrid[0:h, 0:w]
        far = np.zeros(idle.shape, bool)   # дымок художника перед дулом — убрать (вместо него свой выстрел)
        for t in tl:
            far |= ((xx - t[0]) * d[0] + (yy - t[1]) * d[1] > 3) & (idle == 0)
        for f in files:
            i = int(f.stem) - shot + 1          # 0 — кадр перед выстрелом, 1 — выстрел
            j = min(max(i, 0), len(RECOIL) - 1)
            a = np.array(Image.open(f).convert("RGBA"))
            a[far] = 0
            g = np.zeros((-(-h // PX), -(-w // PX), 4), np.uint8)
            for n, t in enumerate(tl):
                rn = RECOIL[j] if i >= 1 else 0
                a = recoil(a, barrel_mask(a[..., 3], t, d), d, rn)
                tt = (t[0] - round(d[0] * rn) * PX, t[1] - round(d[1] * rn) * PX)
                draw_fx(g, tt, d, j, level * 10 + n + j * 100, i <= 0)
            big = np.kron(g, np.ones((PX, PX, 1), np.uint8))[:h, :w]
            img = Image.fromarray(a)
            img.alpha_composite(Image.fromarray(big))
            img.save(row / f.name)
        print(f"{rel}/{row.name}: стволов {len(tl)}, жерло {[(round(x - w / 2, 1), round(y - h, 1)) for x, y in tl]}")
    return tips


def write_meta(rel, tips):
    tres = BUILDINGS / rel / "frames.tres"
    text = tres.read_text(encoding="utf-8")

    def p(t, d, size):
        return (round(t[0] + d[0] * MUZZLE_AHEAD - size[0] / 2, 1), round(t[1] + d[1] * MUZZLE_AHEAD - size[1], 1))

    if 1 in tips:
        x, y = p(tips[1][0][0], tips[1][1], tips[1][2])
        text = re.sub(r"metadata/muzzle = [^\n]*", f"metadata/muzzle = Vector2({x}, {y})", text)
    lm = {lv: p(v[0][0], v[1], v[2]) for lv, v in tips.items() if lv > 1}
    if lm:
        text = re.sub(r"metadata/level_muzzle = [^\n]*", "metadata/level_muzzle = {" + ", ".join(
            f"{lv}: Vector2({x}, {y})" for lv, (x, y) in sorted(lm.items())) + "}", text)
    lb = {lv: [p(t, v[1], v[2]) for t in v[0]] for lv, v in tips.items() if len(v[0]) > 1}
    if lb:
        text = re.sub(r"metadata/level_barrels = [^\n]*", "metadata/level_barrels = {" + ", ".join(
            f"{lv}: [" + ", ".join(f"Vector2({x}, {y})" for x, y in pts) + "]" for lv, pts in sorted(lb.items())) + "}",
            text)
    tres.write_text(text, encoding="utf-8")
    print("frames.tres: muzzle / level_muzzle / level_barrels — по жерлу")


if __name__ == "__main__":
    for r in [a for a in sys.argv[1:] if not a.startswith("--")]:
        apply_style(r)
        write_meta(r, run(r))
