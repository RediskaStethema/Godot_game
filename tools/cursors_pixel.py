"""Курсоры игры пиксель-артом кодом (решение пользователя 24.11.2026: «перерисовать курсор в новой стилистике игры»).
Прежние (пакет ui_n, 32 px, смазанные тёмно-золотые) растягивались в игре кубической интерполяцией ×1.625. Новые — 26×26 px,
чёткий тёмный контур 1 px, железо с светотенью сверху слева, медная кромка и янтарь (палитра интерфейса), в игре — ровно ×2
без сглаживания (`UITheme.CURSOR_SCALE` 2.0, NEAREST → 52 px, как было).
  cursor_default — стрелка-копьё (горячая точка 1,1), cursor_point — латная перчатка с указательным пальцем (выбор:
  жетоны, карты выбора; 8,1), cursor_grab — латный кулак (тащим карту; 13,3), cursor_target — прицел орудия (13,13).
  python tools/cursors_pixel.py [--preview папка]   # → assets/ui/cursor/*.png; прежние — assets/source_sheets/cursor_orig_2026-11-24
Затем `godot --headless --path . --import`. Откат — скопировать прежние файлы обратно (cursor_point прежнего набора нет — вернуть
в UITheme.CURSORS cursor_grab для CURSOR_POINTING_HAND).
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets/ui/cursor"
N = 26
K = (10, 6, 9, 255)                     # контур (Palette.OUTLINE, плотный)
IRON = [(150, 140, 146), (96, 88, 96), (52, 46, 54)]          # свет / середина / тень
COPPER = [(214, 150, 78), (156, 98, 48), (92, 56, 30)]
AMBER = (255, 196, 84)
BONE = (236, 222, 188)


def rgba(c):
    return (*c, 255)


def mask_poly(points):
    from PIL import ImageDraw
    im = Image.new("L", (N, N), 0)
    ImageDraw.Draw(im).polygon(points, fill=255)
    return np.array(im) > 0


def mask_rect(x0, y0, x1, y1):
    m = np.zeros((N, N), bool)
    m[y0:y1 + 1, x0:x1 + 1] = True
    return m


def shade(mask, ramp, light=(0.55, 0.45)):
    """Светотень по маске: светлее сверху слева, тёмная кромка снизу справа."""
    ys, xs = np.where(mask)
    out = {}
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    w, h = max(x1 - x0, 1), max(y1 - y0, 1)
    for y, x in zip(ys, xs):
        s = light[0] * (x - x0) / w + light[1] * (y - y0) / h
        out[(x, y)] = ramp[0] if s < 0.30 else ramp[1] if s < 0.66 else ramp[2]
    return out


def compose(parts):
    """parts: [(маска, рампа)] снизу вверх → RGBA 26×26 с контуром и кромкой."""
    img = np.zeros((N, N, 4), np.uint8)
    for mask, ramp in parts:
        for (x, y), c in shade(mask, ramp).items():
            img[y, x] = rgba(c)
    solid = img[..., 3] > 0
    # кромка света: пиксель, у которого сверху или слева пусто — на ступень светлее
    out = img.copy()
    for y in range(N):
        for x in range(N):
            if not solid[y, x]:
                continue
            up = y == 0 or not solid[y - 1, x]
            left = x == 0 or not solid[y, x - 1]
            if up or left:
                c = np.array(img[y, x, :3], int)
                out[y, x, :3] = np.clip(c * 1.25 + 14, 0, 255)
    # контур: прозрачный пиксель рядом (4 стороны) с цветным
    res = out.copy()
    for y in range(N):
        for x in range(N):
            if solid[y, x]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                xx, yy = x + dx, y + dy
                if 0 <= xx < N and 0 <= yy < N and solid[yy, xx]:
                    res[y, x] = K
                    break
    return res


def put(img, pts, c):
    for x, y in pts:
        img[y, x] = rgba(c)


def arrow():
    # классическая стрелка, остриё не у самого края (контур слева виден); хвост — медное древко с янтарным навершием
    full = mask_poly([(2, 2), (2, 20), (6, 16), (9, 22), (12, 21), (9, 15), (15, 15)])
    tail = full.copy()
    tail[:16, :] = False
    head = full & ~tail
    img = compose([(head, IRON), (tail, COPPER)])
    put(img, [(10, 21), (11, 21)], AMBER)
    for y in range(6, 14):                                      # грань клинка: линия посередине острия
        img[y, 2 + (y - 2) // 2 + 1] = rgba(IRON[2])
    return img


def point():
    finger = mask_rect(8, 2, 11, 13)
    finger[2, 8] = finger[2, 11] = False                       # скруглённый кончик
    k1, k2, k3 = mask_rect(12, 11, 14, 16), mask_rect(15, 12, 17, 16), mask_rect(18, 13, 20, 17)
    for k in (k1, k2, k3):                                     # скруглённые костяшки
        ys, xs = np.where(k)
        k[ys.min(), xs.min()] = k[ys.min(), xs.max()] = False
    palm = mask_rect(8, 13, 20, 20)
    thumb = mask_rect(5, 13, 8, 18)
    thumb[13, 5] = False
    cuff = mask_rect(8, 21, 20, 24)
    img = compose([(palm | k1 | k2 | k3 | thumb | finger, IRON), (cuff, COPPER)])
    put(img, [(10, 22), (14, 22), (18, 22)], AMBER)
    for x in (13, 16, 19):                                     # щели между сложенными пальцами
        img[16, x] = rgba(IRON[2])
        img[17, x] = rgba(IRON[2])
    for x in range(8, 12):                                     # суставы указательного
        img[6, x] = rgba(IRON[2])
        img[10, x] = rgba(IRON[2])
    for x in range(5, 9):                                      # шов большого пальца
        img[15, x] = rgba(IRON[2])
    return img


def grab():
    ks = [mask_rect(5, 6, 8, 10), mask_rect(9, 5, 12, 10), mask_rect(13, 5, 16, 10), mask_rect(17, 6, 20, 10)]
    for k in ks:                                               # скруглённые костяшки
        ys, xs = np.where(k)
        k[ys.min(), xs.min()] = k[ys.min(), xs.max()] = False
    knuckles = ks[0] | ks[1] | ks[2] | ks[3]
    palm = mask_rect(5, 10, 20, 18)
    thumb = mask_rect(4, 14, 14, 17)
    cuff = mask_rect(6, 19, 19, 23)
    img = compose([(palm | knuckles | thumb, IRON), (cuff, COPPER)])
    put(img, [(8, 21), (12, 21), (16, 21)], AMBER)
    for x in (8, 12, 16):                                      # щели между костяшками
        for y in range(6, 11):
            img[y, x] = rgba(IRON[2])
    for x in range(4, 15):                                     # линия большого пальца поперёк пальцев
        img[14, x] = rgba(IRON[2])
    return img


def target():
    from PIL import ImageDraw
    ring = Image.new("L", (N, N), 0)
    d = ImageDraw.Draw(ring)
    d.ellipse((5, 5, 20, 20), outline=255, width=2)
    m = np.array(ring) > 0
    ticks = mask_rect(12, 0, 13, 5) | mask_rect(12, 20, 13, 25) | mask_rect(0, 12, 5, 13) | mask_rect(20, 12, 25, 13)
    img = compose([(m | ticks, COPPER)])
    put(img, [(12, 12), (13, 12), (12, 13), (13, 13)], AMBER)
    return img


SPRITES = {"cursor_default": arrow, "cursor_point": point, "cursor_grab": grab, "cursor_target": target}


def main(argv):
    OUT.mkdir(parents=True, exist_ok=True)
    prev = None
    if "--preview" in argv:
        prev = Path(argv[argv.index("--preview") + 1])
        prev.mkdir(parents=True, exist_ok=True)
        sheet = Image.new("RGBA", (len(SPRITES) * (N * 8 + 12), N * 8), (46, 30, 34, 255))
    for i, (name, fn) in enumerate(SPRITES.items()):
        im = Image.fromarray(fn(), "RGBA")
        if prev is None:
            im.save(OUT / f"{name}.png")
        else:
            sheet.alpha_composite(im.resize((N * 8, N * 8), Image.NEAREST), (i * (N * 8 + 12), 0))
            im.save(prev / f"{name}.png")
    if prev is not None:
        sheet.convert("RGB").save(prev / "sheet.png")
        print("превью:", prev / "sheet.png")


if __name__ == "__main__":
    main(sys.argv[1:])
