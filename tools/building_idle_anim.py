"""Живые кадры стойки и выстрела зданий из кадра 0 уровня (решение пользователя 21.11.2026: «перерисуй кадры idle / attack,
чтобы кадры стоек отличались — утверди со мной, как нарисуешь»).

Модель Layer рисовала кадры по-разному и дрожала (кадры «накладывались»), поэтому кадры строятся из самого кадра 0
детерминированно: все движения привязаны к сетке пикселя арта (блок BLOCK = 3 px), корпус не двигается, живое —
  • ствол (пучок): сдвиг вдоль оси ствола растёт от казённика к дулу (плавное «сжатие», без швов) — в стойке дышит на
    ±IDLE_BARREL px, в выстреле отдаёт назад и возвращается (профиль RECOIL);
  • жерла стволов: накал (яркость) пульсирует, в выстреле белеет;
  • полотнища (оранжевая ткань): качаются, низ сильнее;
  • огни свечей и ламп: язычки мерцают (сдвиг на блок вверх, яркость).
Кадры пишутся в <выход>/<здание>/<ряд>/N.png (превью — полоса кадров и GIF рядом); в игру — отдельным шагом --install
после утверждения (frames.tres переписывается под новое число кадров).

  python tools/building_idle_anim.py chaos/tower [--install]
"""
import colorsys
import math
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
GAME = ROOT / "assets/sprites/buildings"
OUT = ROOT / "assets/source_sheets/building_anim_v1_2026-11-21"
BLOCK = 3
IDLE_FRAMES = 12           # цикл стойки, 8 к/с — 1.5 с
ATTACK_FRAMES = 8          # выстрел, 20 к/с — 0.4 с
SPEEDS = {"idle": 8.0, "attack": 20.0}
IDLE_BARREL = 20.0         # px, дыхание ствола у дула (v4: было 11 — всё равно мало)
RECOIL = [-0.15, 1.0, 0.8, 0.55, 0.35, 0.2, 0.1, 0.0]   # отдача башни по кадрам выстрела (кадр 1 — shot_frame)
RECOIL_MORTAR = [-0.1, -0.3, 1.0, 0.7, 0.45, 0.25, 0.1, 0.0]   # мортира: замах вниз, отдача на кадре 2 (shot_frame)
RECOIL_PX = 54.0           # px у дула (v4: было 36)
CLOTH_AMP = 5.5            # блоков у нижней кромки полотнища (v4: было 3.6)
FILL = (24, 18, 20)        # тёмный фон за полотнищем

# Ось ствола каждого уровня: точка у казённика, направление (экран, y вниз), расстояние казённик → дуло, ширина зоны
BARRELS = {
    "chaos/tower": {
        "idle": dict(pivot=(235, 150), dir=(0.96, -0.28), length=150, width=75, muzzle=(362, 108)),
        "idle_2": dict(pivot=(290, 155), dir=(0.98, -0.2), length=105, width=60, muzzle=(372, 135)),
        "idle_3": dict(pivot=(250, 160), dir=(0.985, -0.17), length=100, width=90, muzzle=(345, 155)),
    },
}
BARRELS["chaos/artillery"] = {
    "idle": dict(kind="mortar", pivot=(195, 205), dir=(0.1, -0.995), length=85, width=45, muzzle=(198, 128),
                 flame_box=(165, 80, 235, 150), rim_y=128),
    "idle_2": dict(kind="mortar", pivot=(180, 175), dir=(0.31, -0.95), length=95, width=50, muzzle=(213, 85),
                   flame_box=(170, 25, 290, 115), rim_y=88),
    "idle_3": dict(kind="mortar", pivot=(190, 175), dir=(0.38, -0.92), length=95, width=55, muzzle=(222, 92),
                   flame_box=(150, 25, 300, 125), rim_y=95),
}
ATTACK_OF = {"idle": "attack", "idle_2": "attack_2", "idle_3": "attack_3"}


def hsv(rgb):
    return colorsys.rgb_to_hsv(rgb[0] / 255, rgb[1] / 255, rgb[2] / 255)


def to_blocks(img: Image.Image):
    a = np.asarray(img.convert("RGBA"))
    h, w = a.shape[0] // BLOCK, a.shape[1] // BLOCK
    return a[BLOCK // 2:h * BLOCK:BLOCK, BLOCK // 2:w * BLOCK:BLOCK].copy()


def from_blocks(b, size):
    big = np.repeat(np.repeat(b, BLOCK, 0), BLOCK, 1)
    out = np.zeros((size[1], size[0], 4), np.uint8)
    out[:big.shape[0], :big.shape[1]] = big[:size[1], :size[0]]
    return Image.fromarray(out)


def components(mask):
    """Связные области маски (4-связность) — без scipy."""
    h, w = mask.shape
    lab = np.zeros((h, w), np.int32)
    n = 0
    comps = []
    for y in range(h):
        for x in range(w):
            if mask[y, x] and not lab[y, x]:
                n += 1
                stack = [(y, x)]
                lab[y, x] = n
                pts = []
                while stack:
                    cy, cx = stack.pop()
                    pts.append((cy, cx))
                    for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                        if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not lab[ny, nx]:
                            lab[ny, nx] = n
                            stack.append((ny, nx))
                comps.append(pts)
    return comps


def barrel_weight(cfg, shape):
    """Вес сдвига пикселя блока: 0 у казённика и вне пучка, 1 у дула (растёт вдоль оси, мягко по ширине)."""
    h, w = shape
    ys, xs = np.mgrid[0:h, 0:w]
    px = xs * BLOCK + BLOCK // 2 - cfg["pivot"][0]
    py = ys * BLOCK + BLOCK // 2 - cfg["pivot"][1]
    dx, dy = cfg["dir"]
    t = px * dx + py * dy
    perp = np.abs(px * dy - py * dx)
    wt = np.clip(t / cfg["length"], 0, 1) ** 1.4
    wp = 1.0 - np.clip((perp - cfg["width"] * 0.6) / (cfg["width"] * 0.4), 0, 1)
    return wt * wp


def warp_barrels(b, cfg, shift_px):
    """Сдвиг пучка вдоль оси: out(p) = in(p + shift·dir·вес); shift_px > 0 — ствол втянут к казённику."""
    h, w = b.shape[:2]
    wgt = barrel_weight(cfg, (h, w))
    ys, xs = np.mgrid[0:h, 0:w]
    dx, dy = cfg["dir"]
    sx = np.clip(np.round(xs + shift_px * wgt * dx / BLOCK).astype(int), 0, w - 1)
    sy = np.clip(np.round(ys + shift_px * wgt * dy / BLOCK).astype(int), 0, h - 1)
    out = b[sy, sx]
    return out


def find_cloth(b):
    """Оранжевая ткань: тон 0.05–0.13, насыщенная, не огонь (v < 0.88), ниже середины кадра."""
    h, w = b.shape[:2]
    mask = np.zeros((h, w), bool)
    for y in range(h // 2, h):
        for x in range(w):
            r, g, bl, a = b[y, x]
            if a < 200:
                continue
            hh, ss, vv = hsv((r, g, bl))
            if 0.05 <= hh <= 0.13 and ss > 0.5 and 0.45 <= vv < 0.9:
                mask[y, x] = True
    return [c for c in components(mask) if len(c) >= 25]


def find_flames(b, barrel_cfg):
    """Язычки свечей и ламп: яркий тёплый пиксель вне зоны жерл."""
    h, w = b.shape[:2]
    wgt = barrel_weight(barrel_cfg, (h, w))
    mask = np.zeros((h, w), bool)
    for y in range(h):
        for x in range(w):
            r, g, bl, a = b[y, x]
            if a < 200 or wgt[y, x] > 0.05:
                continue
            hh, ss, vv = hsv((r, g, bl))
            if (hh <= 0.16 or hh >= 0.95) and ss > 0.45 and vv >= 0.8:
                mask[y, x] = True
    return [c for c in components(mask) if 2 <= len(c) <= 80]


def find_muzzles(b, cfg):
    """Жерла: тёплые пиксели у дула (не дальше 45 px от метки muzzle)."""
    h, w = b.shape[:2]
    mx, my = cfg["muzzle"]
    pts = []
    for y in range(h):
        for x in range(w):
            if abs(x * BLOCK - mx) > 55 or abs(y * BLOCK - my) > 70:
                continue
            r, g, bl, a = b[y, x]
            if a < 200:
                continue
            hh, ss, vv = hsv((r, g, bl))
            if (hh <= 0.1 or hh >= 0.95) and ss > 0.5 and vv > 0.45:
                pts.append((y, x))
    return pts


def lit(px, k):
    r, g, b, a = [int(v) for v in px]
    if k >= 1.0:   # к белому
        t = min(k - 1.0, 1.0)
        return np.array([r + (255 - r) * t, g + (240 - g) * t, b + (200 - b) * t, a], np.uint8)
    return np.array([r * k, g * k, b * k, a], np.uint8)


def add_halo(out, y, x, color, radius, k):
    """Свечение вокруг огня: мягкое пятно в блоках пикселя арта (4 ступени яркости), сложением с кадром; k — сила (0…1.8).
    Вне силуэта становится видимым ореолом — кадры стойки и выстрела заметно меняются (решение пользователя 21.11.2026:
    «менялись свечения, горение, движения пушек»)."""
    h, w = out.shape[:2]
    r = int(math.ceil(radius))
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            yy, xx = int(y) + dy, int(x) + dx
            if not (0 <= yy < h and 0 <= xx < w):
                continue
            d = math.hypot(dy, dx) / radius
            if d >= 1.0:
                continue
            a = min((1.0 - d) ** 1.6 * k, 1.0)
            a = math.floor(a * 4.0 + 0.5) / 4.0
            if a <= 0.0:
                continue
            px = out[yy, xx]
            add = np.array(color, np.float32) * a * 0.9
            if px[3] < 20:
                out[yy, xx] = (*[int(min(c, 255)) for c in add], int(min(a * 200, 200)))
            else:
                out[yy, xx] = (*[int(min(px[i] + add[i], 255)) for i in range(3)], px[3])


def body_warp(out, frame, total, attack, cfg):
    """Дыхание корпуса и толчок выстрела: верх здания (выше основания) сдвигается по вертикали плавной волной, в выстреле —
    толчок назад вдоль оси и возврат (v4 21.11.2026: кадры были слишком похожи — движения не было видно)."""
    h, w = out.shape[:2]
    ys, xs = np.mgrid[0:h, 0:w]
    opaque = out[..., 3] > 20
    rows = np.where(opaque.any(1))[0]
    if len(rows) == 0:
        return out
    top, bot = rows[0], rows[-1]
    up = np.clip((bot - ys) / max(bot - top, 1), 0.0, 1.0) ** 1.2        # 0 у основания, 1 на макушке
    ph = frame / total * math.tau
    if attack:
        kick = [0.0, 1.0, 0.75, 0.45, 0.25, 0.12, 0.05, 0.0][frame % 8]
        dy = -1.0 * kick * up * 3.0
        dx = -cfg["dir"][0] * kick * up * 4.0
        dy = dy + 0.0
    else:
        dy = 1.8 * math.sin(ph) * up + 0.6 * math.sin(ph * 2.0 + 1.0) * up
        dx = 0.9 * math.sin(ph + 0.7) * up
    sy = np.clip(np.round(ys - dy).astype(int), 0, h - 1)
    sx = np.clip(np.round(xs - dx).astype(int), 0, w - 1)
    return out[sy, sx]


def particles(out, sources, frame, total, attack, shot_frame):
    """Искры и дым над источниками огня — по кадрам цикла (петля без шва): у каждого источника свои частицы, положение
    зависит от возраста; в выстреле пучок вылетает с кадра выстрела."""
    h, w = out.shape[:2]
    for si, (sy, sx, col, kind) in enumerate(sources):
        n, rise, spread = (14, 12.0, 4.0) if kind == "mouth" else (6, 9.0, 2.5) if kind == "muzzle" else (2, 6.0, 1.5)
        for j in range(n):
            phase = (j * 0.618 + si * 0.37) % 1.0
            t = (frame / total + phase) % 1.0
            if attack and frame < shot_frame:
                continue
            px = sx + (((j * 7 + si * 3) % 11) - 5) / 5.0 * spread * t + math.sin(t * 5 + j) * 1.2
            py = sy - rise * t * (0.7 + 0.3 * ((j * 5) % 3))
            xx, yy = int(round(px)), int(round(py))
            if 0 <= yy < h and 0 <= xx < w:
                a = 1.0 - t
                c = np.array(col, np.float32)
                c = c * 0.5 + np.array([255, 190, 80], np.float32) * 0.5 if kind != "candle" else c
                out[yy, xx] = (*[int(min(v, 255)) for v in c], int(max(90, 255 * a)))
        if kind in ("mouth", "muzzle"):   # дым: два серых клуба выше
            for j in range(2):
                t = (frame / total + j * 0.5 + si * 0.2) % 1.0
                if attack and frame < shot_frame:
                    continue
                cx = int(round(sx + math.sin(t * 4 + j * 2) * 3 + t * 3))
                cy = int(round(sy - 4 - t * (rise + 6)))
                a = (1.0 - t) * 0.6
                for dy in (0, 1):
                    for dx in (0, 1):
                        yy, xx = cy + dy, cx + dx
                        if 0 <= yy < h and 0 <= xx < w:
                            base = out[yy, xx]
                            g = np.array([88, 78, 80], np.float32)
                            if base[3] < 20:
                                out[yy, xx] = (*[int(v) for v in g], int(a * 170))
                            else:
                                out[yy, xx] = (*[int(base[i] * (1 - a * 0.5) + g[i] * a * 0.5) for i in range(3)], base[3])
    return out


def animate(base_img, cfg, row, frame, total):
    if cfg.get("kind") == "mortar":
        return animate_mortar(base_img, cfg, row, frame, total)
    b = to_blocks(base_img)
    h, w = b.shape[:2]
    attack = row.startswith("attack")
    ph = frame / total * math.tau
    # --- ствол
    if attack:
        shift = RECOIL[frame % len(RECOIL)] * RECOIL_PX
    else:
        shift = IDLE_BARREL * math.sin(ph)
    out = warp_barrels(b, cfg, shift) if abs(shift) > 0.4 else b.copy()
    # --- жерла
    for (y, x) in find_muzzles(b, cfg):
        if attack:
            k = 1.0 + (0.9 if frame == 1 else 0.45 if frame == 2 else 0.0) if frame in (1, 2) else 0.95
        else:
            k = 0.82 + 0.3 * (0.5 + 0.5 * math.sin(ph * 2.0 + x * 0.3))
        sy = int(np.clip(round(y + (shift * cfg["dir"][1]) / BLOCK * barrel_weight(cfg, (h, w))[y, x]), 0, h - 1))
        sx = int(np.clip(round(x + (shift * cfg["dir"][0]) / BLOCK * barrel_weight(cfg, (h, w))[y, x]), 0, w - 1))
        out[sy, sx] = lit(out[sy, sx], k)
    # --- полотнища
    for comp in find_cloth(b):
        ys = [p[0] for p in comp]
        y0, y1 = min(ys), max(ys)
        cx = float(np.mean([p[1] for p in comp]))
        for (y, x) in comp:
            out[y, x] = (*FILL, 255)
        sway_t = ph if not attack else frame / total * math.pi
        for (y, x) in comp:
            depth = ((y - y0) / max(1, y1 - y0)) ** 1.5
            dx = int(round(CLOTH_AMP * depth * math.sin(sway_t + (y - y0) * 0.18 + cx * 0.05)))
            nx = int(np.clip(x + dx, 0, w - 1))
            out[y, x] = out[y, x]
            out[y, nx] = b[y, x]
    # --- огни
    srcs = []
    for i, comp in enumerate(find_flames(b, cfg)):
        top = min(p[0] for p in comp)
        phase = ph * 1.0 + i * 1.7
        up = 1 if math.sin(phase * 2 + i) > 0.55 else 0
        k = 0.78 + 0.4 * (0.5 + 0.5 * math.sin(phase * 2.0 + i * 2.3))
        if up:
            for (y, x) in comp:
                if y == top and y - 1 >= 0:
                    out[y - 1, x] = b[y, x]
        for (y, x) in comp:
            out[y, x] = lit(out[y, x], k)
        add_halo(out, float(np.mean([p[0] for p in comp])), float(np.mean([p[1] for p in comp])), b[comp[0][0], comp[0][1]][:3], 4.5, 0.55 * k)
        srcs.append((top, float(np.mean([p[1] for p in comp])), tuple(int(v) for v in b[comp[0][0], comp[0][1]][:3]), "candle"))
    # свечение жерл пучка: пульсирует, на выстреле вспыхивает
    mz = find_muzzles(b, cfg)
    if mz:
        my_ = float(np.mean([p[0] for p in mz]))
        mx_ = float(np.mean([p[1] for p in mz]))
        wgt = barrel_weight(cfg, (h, w))[min(int(my_), h - 1), min(int(mx_), w - 1)]
        sy_ = -shift * cfg["dir"][1] * wgt / BLOCK
        sx_ = -shift * cfg["dir"][0] * wgt / BLOCK
        if attack:
            kk = [0.5, 1.7, 1.2, 0.9, 0.7, 0.55, 0.5, 0.45][frame % 8]
        else:
            kk = 0.5 + 0.4 * math.sin(ph * 2.0)
        out = body_warp(out, frame, total, attack, cfg)
        add_halo(out, my_ + sy_, mx_ + sx_, (255, 120, 40), 11.0, kk * 1.25)
        srcs.append((my_ + sy_, mx_ + sx_, (255, 120, 40), "muzzle"))
    else:
        out = body_warp(out, frame, total, attack, cfg)
    out = particles(out, srcs, frame, total, attack, 1)
    return from_blocks(out, base_img.size)


def flame_pixels(b, cfg):
    """Пламя в жерле: яркие тёплые пиксели внутри рамки flame_box."""
    x0, y0, x1, y1 = [v // BLOCK for v in cfg["flame_box"]]
    pts = {}
    for y in range(max(y0, 0), min(y1, b.shape[0])):
        for x in range(max(x0, 0), min(x1, b.shape[1])):
            r, g, bl, a = b[y, x]
            if a < 200:
                continue
            hh, ss, vv = hsv((r, g, bl))
            if (hh <= 0.13 or hh >= 0.95) and ss > 0.45 and vv > 0.5:
                pts[(y, x)] = (int(r), int(g), int(bl))
    return pts


def remove_flame(b, pts):
    """Кадр без пламени: под ним — ствол (ближайшие непламенные цвета, темнее) или пустота над чашей."""
    out = b.copy()
    h, w = b.shape[:2]
    for (y, x) in pts:
        around = []
        for dy in range(-2, 3):
            for dx in range(-2, 3):
                yy, xx = y + dy, x + dx
                if 0 <= yy < h and 0 <= xx < w and (yy, xx) not in pts and b[yy, xx][3] >= 200:
                    around.append(b[yy, xx][:3])
        if len(around) >= 7:
            m = np.median(np.array(around), axis=0) * 0.7
            out[y, x] = (*[int(v) for v in m], 255)
        else:
            out[y, x] = (0, 0, 0, 0)
    return out


def animate_mortar(base_img, cfg, row, frame, total):
    b = to_blocks(base_img)
    h, w = b.shape[:2]
    attack = row.startswith("attack")
    ph = frame / total * math.tau
    pts = flame_pixels(b, cfg)
    body = remove_flame(b, pts)
    if attack:
        prof = RECOIL_MORTAR[frame % len(RECOIL_MORTAR)]
        shift = prof * RECOIL_PX
        stretch = [0.7, 0.5, 2.8, 2.0, 1.5, 1.2, 1.05, 1.0][frame % 8]
        glow = 1.0 + (0.3 if frame == 2 else 0.15 if frame in (3, 4) else 0.0)
    else:
        shift = IDLE_BARREL * 0.6 * math.sin(ph)
        stretch = 1.0 + 0.5 * math.sin(ph * 2.0) + 0.2 * math.sin(ph * 3.0 + 1.0)
        glow = 0.88 + 0.3 * (0.5 + 0.5 * math.sin(ph * 2.0 + 0.6))
    out = warp_barrels(body, cfg, shift) if abs(shift) > 0.4 else body.copy()
    # --- пламя: растяжка вверх от кромки чаши, качание, накал; следует за жерлом при отдаче
    rim = cfg["rim_y"] // BLOCK
    mw = barrel_weight(cfg, (h, w))
    my, mx = min(max(cfg["muzzle"][1] // BLOCK, 0), h - 1), min(max(cfg["muzzle"][0] // BLOCK, 0), w - 1)
    off = (-cfg["dir"][1] * shift * mw[my, mx] / BLOCK, -cfg["dir"][0] * shift * mw[my, mx] / BLOCK)   # (dy, dx) за жерлом
    for (y, x), col in sorted(pts.items(), key=lambda kv: -kv[0][0]):
        hgt = rim - y
        if hgt > 0:
            ny = rim - hgt * stretch
            dx = CLOTH_AMP * 0.6 * (hgt / 14.0) ** 1.2 * math.sin(ph * 2.0 + hgt * 0.3 + x * 0.2) * (0.6 if attack else 1.0)
        else:
            ny = y
            dx = 0.0
        ny = int(round(ny + off[0]))
        nx = int(round(x + dx + off[1]))
        c = lit(np.array([*col, 255], np.uint8), glow)
        for yy in range(ny, ny + (2 if stretch > 1.3 and hgt > 0 else 1)):
            if 0 <= yy < h and 0 <= nx < w:
                out[yy, nx] = c
    out = body_warp(out, frame, total, attack, cfg)
    srcs = []
    if pts:
        srcs.append((float(np.mean([q[0] for q in pts])) + off[0] - 3, float(np.mean([q[1] for q in pts])) + off[1], (255, 150, 50), "mouth"))
    # --- свечение чаши: пульсирует, на выстреле вспыхивает столбом
    if pts:
        py = float(np.mean([q[0] for q in pts])) + off[0]
        px_ = float(np.mean([q[1] for q in pts])) + off[1]
        kk = ([0.5, 0.4, 1.8, 1.3, 0.95, 0.7, 0.55, 0.5][frame % 8]) if attack else 0.6 + 0.4 * math.sin(ph * 2.0 + 0.6)
        add_halo(out, py - 2, px_, (255, 140, 40), 11.0, kk)
    # --- полотнища и огни, как у башни
    for comp in find_cloth(b):
        ys = [p[0] for p in comp]
        y0, y1 = min(ys), max(ys)
        cx = float(np.mean([p[1] for p in comp]))
        for (y, x) in comp:
            out[y, x] = (*FILL, 255)
        sway_t = ph if not attack else frame / total * math.pi
        for (y, x) in comp:
            depth = ((y - y0) / max(1, y1 - y0)) ** 1.5
            dx = int(round(CLOTH_AMP * depth * math.sin(sway_t + (y - y0) * 0.18 + cx * 0.05)))
            out[y, int(np.clip(x + dx, 0, w - 1))] = b[y, x]
    fb = cfg["flame_box"]
    for i, comp in enumerate(find_flames(b, cfg)):
        if all(fb[0] <= p[1] * BLOCK <= fb[2] and fb[1] <= p[0] * BLOCK <= fb[3] for p in comp[:1]):
            continue
        top = min(p[0] for p in comp)
        phase = ph + i * 1.7
        k = 0.78 + 0.4 * (0.5 + 0.5 * math.sin(phase * 2.0 + i * 2.3))
        if math.sin(phase * 2 + i) > 0.5:
            for (y, x) in comp:
                if y == top and y - 1 >= 0:
                    out[y - 1, x] = b[y, x]
        for (y, x) in comp:
            out[y, x] = lit(out[y, x], k)
        add_halo(out, float(np.mean([p[0] for p in comp])), float(np.mean([p[1] for p in comp])), b[comp[0][0], comp[0][1]][:3], 4.5, 0.55 * k)
        srcs.append((top, float(np.mean([p[1] for p in comp])), tuple(int(v) for v in b[comp[0][0], comp[0][1]][:3]), "candle"))
    out = particles(out, srcs, frame, total, attack, 2)
    return from_blocks(out, base_img.size)


LAYER = ROOT / "assets/source_sheets/building_anim_layer_2026-11-21"
SHORT = {"chaos/tower": "tower", "chaos/artillery": "mortar"}
ORIG = ROOT / "assets/source_sheets/_backup_before_anim_v1_2026-11-21"


def layer_base(name, row):
    """Кадр 0 листа Layer (перерисованное здание) на холсте игры: яркость и насыщенность — как у прежнего кадра 0
    (здания Хаоса приглушены цветокором 21.11.2026), блоки пикселя арта BLOCK усредняются (Layer рисует плавно)."""
    import json
    lv = 1 if row == "idle" else int(row.split("_")[1])
    info = json.load(open(LAYER / "info.json"))[f"{SHORT[name]}_L{lv}"]
    x0, y0, cw, ch = info["box"]
    gen = Image.open(LAYER / f"{SHORT[name]}_L{lv}_gen.png").convert("RGBA").crop((0, 0, cw, ch))
    orig = Image.open(ORIG / name / row / "0.png").convert("RGBA")
    canvas = Image.new("RGBA", orig.size, (0, 0, 0, 0))
    canvas.alpha_composite(gen, (x0, y0))
    a = np.asarray(canvas).astype(np.float32)
    o = np.asarray(orig).astype(np.float32)
    ma, mo = a[..., 3] > 200, o[..., 3] > 200
    va, vo = a[..., :3].max(-1)[ma].mean(), o[..., :3].max(-1)[mo].mean()
    a[..., :3] *= vo / max(va, 1e-3)
    # насыщенность к прежней
    def sat(x, m):
        mx, mn = x[..., :3].max(-1)[m], x[..., :3].min(-1)[m]
        return float(((mx - mn) / np.maximum(mx, 1)).mean())
    k = sat(o, mo) / max(sat(a, ma), 1e-3)
    g = a[..., :3].mean(-1, keepdims=True)
    a[..., :3] = np.clip(g + (a[..., :3] - g) * min(k, 1.0), 0, 255)
    img = Image.fromarray(a.clip(0, 255).astype(np.uint8))
    # усреднение блоками
    w, h = img.size
    small = img.resize((w // BLOCK, h // BLOCK), Image.BOX)
    arr = np.asarray(small).copy()
    arr[..., 3] = np.where(arr[..., 3] > 110, 255, 0)
    return from_blocks(arr, img.size)


def build(name):
    cfgs = BARRELS[name]
    folder = GAME / name
    res = {}
    for row, cfg in cfgs.items():
        base = layer_base(name, row) if "--layer" in sys.argv else Image.open(folder / row / "0.png").convert("RGBA")
        res[row] = [animate(base, cfg, row, i, IDLE_FRAMES) for i in range(IDLE_FRAMES)]
        res[ATTACK_OF[row]] = [animate(base, cfg, ATTACK_OF[row], i, ATTACK_FRAMES) for i in range(ATTACK_FRAMES)]
    return res


def preview(name, res):
    out = OUT / name
    for row, frames in res.items():
        d = out / row
        d.mkdir(parents=True, exist_ok=True)
        for f in d.glob("*.png"):
            f.unlink()
        for i, im in enumerate(frames):
            im.save(d / f"{i}.png")
    # полосы кадров и GIF
    for row, frames in res.items():
        bb = frames[0].getchannel("A").point(lambda v: 255 if v > 40 else 0).getbbox()
        pad = 12
        box = (max(bb[0] - pad, 0), max(bb[1] - pad, 0), bb[2] + pad + 20, bb[3] + pad)
        crops = [Image.alpha_composite(Image.new("RGBA", f.size, (30, 34, 44, 255)), f).crop(box).convert("RGB") for f in frames]
        k = 0.5
        cw, ch = int(crops[0].width * k), int(crops[0].height * k)
        strip = Image.new("RGB", (cw * len(crops), ch))
        for i, c in enumerate(crops):
            strip.paste(c.resize((cw, ch), Image.NEAREST), (i * cw, 0))
        strip.save(out / f"strip_{row}.png")
        crops[0].save(out / f"{row}.gif", save_all=True, append_images=crops[1:], duration=120 if row.startswith("idle") else 60, loop=0)


def install(name, res):
    folder = GAME / name
    bak = ROOT / "assets/source_sheets/_backup_before_anim_v1_2026-11-21" / name
    if not bak.exists():
        shutil.copytree(folder, bak, ignore=shutil.ignore_patterns("*.import"))
    for row, frames in res.items():
        d = folder / row
        for f in d.glob("*.png*"):
            f.unlink()
        for i, im in enumerate(frames):
            im.save(d / f"{i}.png")
    tres = folder / "frames.tres"
    text = tres.read_text(encoding="utf-8")
    base = text[:text.index("\n[ext_resource")]
    head = text[text.index("[resource]"):text.index("animations = [")]
    rel = f"res://assets/sprites/buildings/{name}"
    ext, anims = [], []
    speeds = SPEEDS
    for row, frames in res.items():
        for i in range(len(frames)):
            ext.append(f'[ext_resource type="Texture2D" path="{rel}/{row}/{i}.png" id="{row}_{i}"]')
        fr = ", ".join('{\n"duration": 1.0,\n"texture": ExtResource("%s_%d")\n}' % (row, i) for i in range(len(frames)))
        anims.append('{\n"frames": [%s],\n"loop": %s,\n"name": &"%s",\n"speed": %.1f\n}' % (
            fr, "true" if row.startswith("idle") else "false", row, speeds["idle" if row.startswith("idle") else "attack"]))
    ext_text = "\n".join(ext)
    out = f'[gd_resource type="SpriteFrames" load_steps={len(ext) + 1} format=3]\n\n{ext_text}\n\n{head}animations = [{", ".join(anims)}]\n'
    tres.write_text(out, encoding="utf-8", newline="")
    print("установлено:", {r: len(f) for r, f in res.items()})


if __name__ == "__main__":
    names = [a for a in sys.argv[1:] if not a.startswith("--")]
    for n in names:
        r = build(n)
        preview(n, r)
        print(n, "превью:", OUT / n)
        if "--install" in sys.argv:
            install(n, r)
