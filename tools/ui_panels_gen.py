"""Текстуры панелей интерфейса (стилизация 20.10.2026): пиксель-арт железной пластины для 9-slice UITheme.

Готовых подложек в пакете интерфейса нет — рисуем сами в палитре Palette.gd: тёмное железо с зерном и
царапинами, фаска (свет сверху слева, тень снизу справа), латунные уголки с заклёпками. Рисуется в 1x
и увеличивается в SCALE раз без сглаживания — пиксели крупные, как у спрайтов поля.

    python tools/ui_panels_gen.py [assets/ui/panels]

Выход (поля 9-slice — в UITheme.PANEL_TEXTURES, в пикселях выхода = поле 1x × SCALE):
  card_common / card_rare / card_epic — карта магазина, руки и скамейки (кант — цвет редкости)
  panel — панели магазина, синергий, справки
  hud — полоса шапки (латунные рейки сверху и снизу)
  card_select — карточка окон выбора (раса, орден, сложность)
"""
import random
import sys
from pathlib import Path

from PIL import Image

SCALE = 2
SEED = 40

IRON = (14, 19, 27)          # PANEL
IRON_DARK = (9, 12, 19)      # PANEL_DARK
STEEL = (59, 67, 80)         # GOLD_DIM — сталь рамок
STEEL_LIGHT = (98, 108, 122)
BRASS = (150, 108, 48)
BRASS_LIGHT = (214, 160, 76)
BRASS_DARK = (78, 54, 24)
BLACK = (4, 6, 10)

RARITY = {                   # UITheme.RARITY_COLORS
    "common": (154, 145, 127),
    "rare": (83, 132, 184),
    "epic": (154, 98, 184),
}


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def shade(c, k):
    return tuple(max(0, min(255, int(round(v * k)))) for v in c)


def plate(w, h, base, rng, grain=0.10, scratches=0):
    """Пластина: зерно ± grain яркости, редкие светлые и тёмные пятна, царапины по диагонали."""
    img = Image.new("RGBA", (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            k = 1.0 + rng.uniform(-grain, grain)
            if rng.random() < 0.02:
                k += 0.18
            elif rng.random() < 0.02:
                k -= 0.2
            px[x, y] = shade(base, k) + (255,)
    for _ in range(scratches):
        x, y = rng.randrange(w), rng.randrange(h)
        for i in range(rng.randint(3, 7)):
            if 0 <= x + i < w and 0 <= y + i // 2 < h:
                px[x + i, y + i // 2] = shade(base, 1.35) + (255,)
    return img


def bevel(img, rim, inset=0, thick=2):
    """Кант: чёрный контур, металл в thick px (свет сверху слева, тень снизу справа), тёмная линия внутрь."""
    w, h = img.size
    px = img.load()
    for i in range(inset, inset + thick + 2):
        for x in range(i, w - i):
            for y in (i, h - 1 - i):
                px[x, y] = _rim_pixel(i - inset, thick, rim, top=(y == i)) + (255,)
        for y in range(i, h - i):
            for x in (i, w - 1 - i):
                px[x, y] = _rim_pixel(i - inset, thick, rim, top=(x == i)) + (255,)


def _rim_pixel(depth, thick, rim, top):
    if depth == 0:
        return BLACK
    if depth == thick + 1:
        return shade(IRON_DARK, 0.7)
    light = depth == 1
    if top:
        return shade(rim, 1.3 if light else 1.0)
    return shade(rim, 0.75 if light else 0.55)


def corner_caps(img, size, rivet=True):
    """Латунные уголки: треугольник со срезом, фаска, заклёпка у вершины — во всех четырёх углах."""
    w, h = img.size
    px = img.load()
    for cy in range(size):
        for cx in range(size - cy):
            if cx + cy == size - 1:
                c = BRASS_DARK
            elif cx == 0 or cy == 0:
                c = BLACK
            elif cx == 1 or cy == 1:
                c = BRASS_LIGHT
            else:
                c = BRASS
            for x, y, flip in ((cx, cy, False), (w - 1 - cx, cy, True), (cx, h - 1 - cy, True),
                               (w - 1 - cx, h - 1 - cy, True)):
                cc = c
                if flip and c == BRASS_LIGHT:
                    cc = BRASS   # свет — только сверху слева
                px[x, y] = cc + (255,)
    if rivet:
        r = 2
        for x, y in ((r, r), (w - 1 - r, r), (r, h - 1 - r), (w - 1 - r, h - 1 - r)):
            px[x, y] = BRASS_LIGHT + (255,)
            px[x + 1 if x < w // 2 else x - 1, y] = BRASS_DARK + (255,)


def card(rarity, rng):
    w, h = 40, 56
    rim = mix(STEEL, RARITY[rarity], 0.6)
    img = plate(w, h, IRON, rng, scratches=4)
    bevel(img, rim)
    corner_caps(img, 8)
    return img


def panel(rng):
    img = plate(48, 48, IRON, rng, grain=0.08, scratches=3)
    bevel(img, STEEL)
    corner_caps(img, 6)
    return img


def hud(rng):
    w, h = 48, 30
    img = plate(w, h, IRON_DARK, rng, grain=0.08, scratches=2)
    px = img.load()
    for x in range(w):   # латунные рейки сверху и снизу
        for y, c in ((0, BLACK), (1, BRASS_DARK), (2, BRASS), (3, BRASS_DARK),
                     (h - 1, BLACK), (h - 2, BRASS_DARK), (h - 3, BRASS), (h - 4, BRASS_DARK)):
            px[x, y] = c + (255,)
    for x in range(4, w, 12):   # заклёпки по рейкам
        px[x, 2] = BRASS_LIGHT + (255,)
        px[x, h - 3] = BRASS_LIGHT + (255,)
    return img


def card_select(rng):
    img = plate(48, 64, IRON, rng, scratches=5)
    bevel(img, STEEL)
    corner_caps(img, 9)
    return img


def save(img, path):
    img.resize((img.width * SCALE, img.height * SCALE), Image.NEAREST).save(path)
    print(path, img.width * SCALE, img.height * SCALE)


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "assets/ui/panels")
    out.mkdir(parents=True, exist_ok=True)
    rng = random.Random(SEED)
    for r in RARITY:
        save(card(r, rng), out / f"card_{r}.png")
    save(panel(rng), out / "panel.png")
    save(hud(rng), out / "hud.png")
    save(card_select(rng), out / "card_select.png")


if __name__ == "__main__":
    main()
