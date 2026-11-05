"""Кадры анимированной клетки на непрозрачном тёмном фоне (сетка редактора) → PNG плит темы одним окном.

Красные глаза Хаоса (решение пользователя 23.10.2026, assets/source_sheets/red_eyes: eyes2…eyes2_5 — моргание 575×368,
eyes1, 3, 4, 5 — яма затягивается 800×512): фон вырезается заливкой от краёв по «не красным» тёмным пикселям
(сетка — сине-зелёная, плита — красно-бурая), кадр обрезается по плите и сводится к ширине WIDTH (кадры разного
разрешения — одна плита), все кадры — на общий холст, основание плиты — внизу. Цвет — к тону и яркости грунта
темы (эталон --ref): насыщенность и яркость множителями к средним эталона, светлое (глаза, свечение ямы, выше
KEEP) гаснет слабее — читается на тёмном поле. Печатает top ромба для FactionTheme: от низа плиты (толщина THICK,
верхняя грань — половина ширины); проверить контуром ромба на кадре.

    python tools/tile_frames_cutout.py --ref <грунт.png> [--warp] [--ground <грунт.png> <top>] <папка> <префикс> <кадр.png> …

--warp — палитра поля Хаоса «бордо + варп» (tools/chaos_warp_grade.py). --ground — клетка без квадратной плиты
(решение пользователя 23.10.2026: «тайлы слишком резко квадратные, сгладь углы»): кадр обрезается по ромбу
верхней грани со скруглёнными углами (ROUND) и мягким краем (FEATHER) — обрыв плиты и выступы углов уходят — и
ложится на плиту грунта (верхние углы граней совпадают): клетка переходит в соседний грунт без шва.
"""
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

from chaos_warp_grade import warp

WIDTH = 400           # px — ширина плиты в кадре (в игре — клетка 140, запас под зум камеры)
BG_MAX_VAL = 70       # фон тёмный: max(r, g, b) не больше
BG_RED_MARGIN = 6     # фон не красный: r <= max(g, b) + это
KEEP = 0.35           # яркость выше — гаснет слабее (глаза, свечение)
LIFT = 1.7            # клетка светлее грунта эталона на эту долю — деталь читается на поле (×1: яма тонула)
GLOW_KEEP = 1.0       # доля яркости, которую ядро свечения сохраняет (1 — как в исходнике)
DENSE = 200
ROUND = 4.0           # степень скругления ромба (2 — эллипс, больше — ближе к ромбу с углами)
FEATHER = (0.72, 0.97)   # мягкий край: от этой доли «радиуса» ромба до этой — прозрачнее
THICK = 0.085         # толщина плиты (боковая грань под нижним углом) в долях ширины — как red_terrain.png


def cutout(img: Image.Image) -> Image.Image:
    rgb = np.array(img.convert("RGB")).astype(int)
    h, w, _ = rgb.shape
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    bgish = (np.maximum(np.maximum(r, g), b) <= BG_MAX_VAL) & (r <= np.maximum(g, b) + BG_RED_MARGIN)
    seen = np.zeros((h, w), bool)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if bgish[y, x] and not seen[y, x]:
                seen[y, x] = True
                q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if bgish[y, x] and not seen[y, x]:
                seen[y, x] = True
                q.append((y, x))
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and not seen[ny, nx] and bgish[ny, nx]:
                seen[ny, nx] = True
                q.append((ny, nx))
    alpha = np.where(seen, 0, 255).astype(np.uint8)
    out = np.dstack([rgb.astype(np.uint8), alpha])
    im = Image.fromarray(out)
    return im.crop(im.getchannel("A").getbbox())


def hsv_stats(img: Image.Image):
    a = np.array(img)[..., 3] > DENSE
    hsv = np.array(img.convert("RGB").convert("HSV")).astype(float) / 255.0
    return hsv[a][:, 1].mean(), hsv[a][:, 2].mean()


def grade(img: Image.Image, ks: float, kv: float) -> Image.Image:
    a = np.array(img)[..., 3:4]
    hsv = np.array(img.convert("RGB").convert("HSV")).astype(float) / 255.0
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    keep = np.clip((v - KEEP) / (1.0 - KEEP), 0.0, 1.0)   # 0 — тёмное (множитель целиком), 1 — ядро свечения
    v = v * (kv + (1.0 - kv) * keep * GLOW_KEEP)
    s = np.clip(s * ks, 0.0, 1.0)
    out = (np.stack([h, s, np.clip(v, 0, 1)], axis=2) * 255).round().astype(np.uint8)
    rgb = np.array(Image.frombytes("HSV", img.size, out.tobytes()).convert("RGB"))
    return Image.fromarray(np.concatenate([rgb, a], axis=2))


def on_ground(img: Image.Image, top: float, ground_png: str, ground_top: float) -> Image.Image:
    """Кадр — по скруглённому ромбу грани с мягким краем, поверх плиты грунта (верхние углы граней совпадают)."""
    w, h = img.size
    ys, xs = np.mgrid[0:h, 0:w].astype(float)
    u = (xs + 0.5 - w / 2.0) / (w / 2.0)
    v = (ys + 0.5 - (top + w / 4.0)) / (w / 4.0)
    r = (np.abs(u + v) ** ROUND + np.abs(u - v) ** ROUND) ** (1.0 / ROUND)
    t = np.clip((r - FEATHER[0]) / (FEATHER[1] - FEATHER[0]), 0.0, 1.0)
    mask = 1.0 - t * t * (3.0 - 2.0 * t)
    a = np.array(img).astype(float)
    a[..., 3] *= mask
    patch = Image.fromarray(a.round().astype(np.uint8))
    g = Image.open(ground_png).convert("RGBA")
    k = w / g.width
    g = g.resize((w, round(g.height * k)), Image.LANCZOS)
    dy = round(top - ground_top * k)   # верхний угол грани грунта — туда же, где у кадра
    out = Image.new("RGBA", (w, max(h, dy + g.height)), (0, 0, 0, 0))
    out.alpha_composite(g, (0, max(dy, 0)))
    out.alpha_composite(patch, (0, 0))
    return out


def main(args):
    ref = None
    do_warp = False
    ground = None
    while args[0].startswith("--"):
        if args[0] == "--ref":
            ref, args = args[1], args[2:]
        elif args[0] == "--warp":
            do_warp, args = True, args[1:]
        elif args[0] == "--ground":
            ground, args = (args[1], float(args[2])), args[3:]
    out_dir, prefix, files = Path(args[0]), args[1], args[2:]
    out_dir.mkdir(parents=True, exist_ok=True)
    frames = []
    for f in files:
        c = cutout(Image.open(f))
        k = WIDTH / c.width
        c = c.convert("RGBa").resize((WIDTH, round(c.height * k)), Image.LANCZOS).convert("RGBA")
        frames.append(c)
    height = max(f.height for f in frames)
    canvas = []
    for f in frames:
        cv = Image.new("RGBA", (WIDTH, height), (0, 0, 0, 0))
        cv.paste(f, (0, height - f.height))   # основание плиты — внизу
        canvas.append(cv)
    if ref:
        rs, rv = hsv_stats(Image.open(ref).convert("RGBA"))
        fs, fv = np.mean([hsv_stats(c) for c in canvas], axis=0)   # одни множители на все кадры — не мигают
        ks, kv = rs / fs, rv * LIFT / fv
        canvas = [grade(c, ks, kv) for c in canvas]
        print(f"цвет: насыщенность x{ks:.2f}, яркость x{kv:.2f} (грунт s {rs:.3f} v {rv:.3f})")
    if do_warp:
        canvas = [warp(c) for c in canvas]
    # top: по низу плиты — толщина THICK ширины, как у плит грунта темы (по левому краю нельзя: у угла торчат шипы)
    top = height - THICK * WIDTH - WIDTH / 2.0
    if ground:
        canvas = [on_ground(c, top, ground[0], ground[1]) for c in canvas]
    for i, c in enumerate(canvas):
        c.save(out_dir / f"{prefix}_{i}.png")
    print(f"{len(canvas)} кадров {WIDTH}x{height}, top {top:.0f}")


if __name__ == "__main__":
    main(sys.argv[1:])
