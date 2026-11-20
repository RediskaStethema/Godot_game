"""Корабли меню (ship_1..3): убрать светлую кайму и крошки по краю вырезки (решение пользователя 16.11.2026:
«корабль слишком плохо вырезан»). Исходники — assets/source_sheets/menu_ships_orig_2026-11-16, повторный прогон — от них:
python tools/menu_ships_defringe.py"""
import numpy as np
from PIL import Image
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets/source_sheets/menu_ships_orig_2026-11-16"
DST = ROOT / "assets/ui/menu/anim"
FRINGE_LUM = 120       # край ярче этого и ярче соседей внутри — кайма фона
FRINGE_RATIO = 1.5
SPECK_MIN = 3          # пиксель с меньшим числом соседей в маске — крошка
BAND = 2               # ширина кромки в px, где ищется кайма


def shift(a, dy, dx, fill):
    out = np.full_like(a, fill)
    h, w = a.shape[:2]
    ys, yd = (slice(max(dy, 0), h + min(dy, 0)), slice(max(-dy, 0), h + min(-dy, 0)))
    xs, xd = (slice(max(dx, 0), w + min(dx, 0)), slice(max(-dx, 0), w + min(-dx, 0)))
    out[ys, xs] = a[yd, xd]
    return out


def neighbours(mask):
    n = np.zeros(mask.shape, int)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dy or dx:
                n += shift(mask.astype(int), dy, dx, 0)
    return n


def lum(rgb):
    return rgb @ np.array([0.299, 0.587, 0.114])


def process(path):
    im = np.array(Image.open(path).convert("RGBA")).astype(float)
    a = im[..., 3]
    mask = a > 128
    # крошки: изолированные пиксели и пары
    for _ in range(2):
        mask &= neighbours(mask) >= SPECK_MIN
    # кромка: расстояние до пустоты ≤ BAND
    dist = np.full(mask.shape, 99)
    cur = ~mask
    dist[cur] = 0
    for d in range(1, BAND + 1):
        grow = neighbours(cur) > 0
        new = grow & ~cur
        dist[new] = d
        cur = cur | grow
    edge = mask & (dist <= BAND)
    inner = mask & ~edge
    rgb = im[..., :3]
    l = lum(rgb)
    # средняя яркость и цвет «внутри» вокруг каждого пикселя (окно 7×7, только внутренние)
    acc_l = np.zeros(mask.shape); acc_c = np.zeros(mask.shape + (3,)); cnt = np.zeros(mask.shape)
    for dy in range(-3, 4):
        for dx in range(-3, 4):
            m = shift(inner.astype(float), dy, dx, 0.0)
            acc_l += shift(l * inner, dy, dx, 0.0)
            acc_c += shift(rgb * inner[..., None], dy, dx, 0.0)
            cnt += m
    ok = cnt > 0
    mean_l = np.where(ok, acc_l / np.maximum(cnt, 1), l)
    mean_c = acc_c / np.maximum(cnt, 1)[..., None]
    fringe = edge & ok & (l > FRINGE_LUM) & (l > mean_l * FRINGE_RATIO)
    rgb[fringe] = mean_c[fringe] * 0.55   # тёмный контур вместо белой каймы
    thin = edge & ~ok & (l > 150)         # тонкие детали (мачта): внутри нет — просто тёмный
    rgb[thin] = (42, 32, 30)
    fringe = fringe | thin
    out = np.dstack([rgb, np.where(mask, 255.0, 0.0)])
    Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)).save(DST / path.name)
    return int(fringe.sum()), int((np.array(Image.open(path).convert('RGBA'))[..., 3] > 128).sum() - mask.sum())


for p in sorted(SRC.glob("ship_?.png")):
    print(p.name, "кайма:", process(p)[0], "px, крошек убрано:", process(p)[1])
