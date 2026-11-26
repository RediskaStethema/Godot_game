"""Стена края поля Космодесанта спрайтами (23.11.2026, решение пользователя: «сравни стену вокруг Хаоса и Космодесанта, доделай
стену Космодесанта с помощью Layer»): гранитные пролёты с башнями-жаровнями (лампа с двумя огнями), ворота с цепью и фонарём,
побитый пролёт и высокий столб с кронштейном и фонарём — вместо гладкой кирпичной ленты без зубцов (`wall.png`, `FieldWall` кодом).

Layer: заготовка 2×2 из спрайтов Хаоса (пролёты 0–2 и столб, клетки 192×208, ×4, на зелёном) → `image.edit` с описанием нового
дизайна (геометрия, камера, размер и основание — прежние; рога, череп, звезда, красные жилы → лампа, медь, гранит) → лист
`walls_<вариант>.png` (вернулся 1968×2128, клетка 984×1064, ×1.28 к заготовке).

Скрипт: зелёный ключ → ячейки → пролёты на геометрию спрайтов Хаоса (180×200, совмещение по силуэту ±SHIFT px, чтобы башни легли на
те же точки: anchor (20, 110), period (108, 54)) → общая палитра PALETTE без дизеринга → `assets/sprites/props/space_marines/field_wall/`:
span_0..2.png, post_corner.png (столб без фонаря — угол поля), post_lantern_strip.png (столб с кронштейном и фонарём, 8 кадров огня).

    python tools/wall_sprites_build.py [B]

Столб: клетка 4 листа; корпус столба — колонки, где содержимое занимает ≥ PILLAR_COLS доли высоты (кронштейн и фонарь справа
ниже), масштаб — высота всего столба 180 px (как у Хаоса); холст POST_W × 180 общий у углового столба и ленты, центр корпуса —
`post_base` (x, 179). Лента из LANTERN_FRAMES кадров: огонь (насыщенные оранжевые пиксели) мерцает яркостью и кончиками — кодом.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

VARIANT = next((a for a in sys.argv[1:] if a in ("A", "B")), "B")
SRC = Path("assets/source_sheets/wall_redraw_2026-11-23") / f"walls_{VARIANT}.png"
CHAOS = Path("assets/sprites/props/chaos/field_wall")
OUT = Path("assets/sprites/props/space_marines/field_wall")
K = 1968 / 1536                  # лист вернулся ×1.28 к заготовке
CELL_IN = (192.0, 208.0)         # клетка заготовки (до ×4)
UP = 4.0 * K                     # пикселей листа на пиксель спрайта Хаоса
PUT = {"span": (6, 4), "post": (72, 14)}   # куда в клетке заготовки положен спрайт Хаоса
SPAN_SIZE = (180, 200)
POST_W = 96                     # холст столба: корпус слева, кронштейн и фонарь справа
POST_H = 180
PILLAR_COLS = 0.6
LANTERN_FRAMES = 8
FLICKER = [1.00, 0.90, 1.08, 0.94, 1.12, 0.88, 1.04, 0.96]   # яркость огня по кадрам
POST_SIZE = (48, 180)
SHIFT = 12
PALETTE = 48
KEY_START, KEY_FULL = 25, 140


def key_green(a: np.ndarray) -> np.ndarray:
    d = a[..., 1].astype(int) - np.maximum(a[..., 0], a[..., 2]).astype(int)
    alpha = np.clip(1.0 - (d - KEY_START) / float(KEY_FULL - KEY_START), 0.0, 1.0)
    a = a.copy()
    a[..., 3] = (255 * alpha).astype(np.uint8)
    over = d > 8
    a[..., 1] = np.where(over, np.maximum(a[..., 0], a[..., 2]), a[..., 1])   # зелёный отлив на кромке → нейтральный
    return a


def cell(sheet: Image.Image, i: int) -> Image.Image:
    cw, ch = CELL_IN[0] * UP, CELL_IN[1] * UP
    c, r = i % 2, i // 2
    return sheet.crop((round(c * cw), round(r * ch), round((c + 1) * cw), round((r + 1) * ch)))


def sprite_from_cell(c: Image.Image, put, size) -> Image.Image:
    box = (round(put[0] * UP), round(put[1] * UP), round((put[0] + size[0]) * UP), round((put[1] + size[1]) * UP))
    return c.crop(box).resize(size, Image.LANCZOS)


def alpha_mask(im: Image.Image) -> np.ndarray:
    return np.asarray(im.convert("RGBA"))[..., 3] > 128


def align(new: Image.Image, ref: Image.Image) -> tuple:
    """Сдвиг new, при котором силуэт лучше всего ложится на силуэт ref (башни — на те же точки)."""
    a, b = alpha_mask(ref), alpha_mask(new)
    best, score = (0, 0), -1.0
    for dy in range(-SHIFT, SHIFT + 1):
        for dx in range(-SHIFT, SHIFT + 1):
            s = (a & np.roll(np.roll(b, dy, 0), dx, 1)).sum() / max(1, (a | np.roll(np.roll(b, dy, 0), dx, 1)).sum())
            if s > score:
                best, score = (dx, dy), s
    return best + (score,)


def shift_img(im: Image.Image, dx: int, dy: int) -> Image.Image:
    out = Image.new("RGBA", im.size)
    out.paste(im, (dx, dy), im)
    return out


def quantize(images: list) -> list:
    rgb = np.concatenate([np.asarray(im)[..., :3][np.asarray(im)[..., 3] > 128] for im in images])
    pal = Image.fromarray(rgb.reshape(1, -1, 3).astype(np.uint8)).quantize(PALETTE, method=Image.Quantize.MEDIANCUT)
    out = []
    for im in images:
        a = np.asarray(im).copy()
        q = np.asarray(Image.fromarray(a[..., :3]).quantize(palette=pal, dither=Image.Dither.NONE).convert("RGB"))
        a[..., :3] = q
        a[..., 3] = np.where(a[..., 3] > 128, 255, 0)
        a[..., :3] = np.where(a[..., 3:4] == 0, 0, a[..., :3])
        out.append(Image.fromarray(a, "RGBA"))
    return out


def is_flame(a: np.ndarray) -> np.ndarray:
    r, g, b = a[..., 0].astype(int), a[..., 1].astype(int), a[..., 2].astype(int)
    return (a[..., 3] > 128) & (r > 170) & (g > 70) & (b < 120) & ((r - b) > 110)


def post_images() -> tuple:
    """(угловой столб без фонаря, список кадров ленты) на общем холсте POST_W × POST_H."""
    sheet = Image.fromarray(key_green(np.asarray(Image.open(SRC).convert("RGBA"))), "RGBA")
    c = cell(sheet, 3)
    a = np.asarray(c)
    mask = a[..., 3] > 128
    ys, xs = np.nonzero(mask)
    box = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
    post = c.crop(box)
    k = POST_H / post.height
    post = post.resize((max(1, round(post.width * k)), POST_H), Image.LANCZOS)
    pa = np.asarray(post)
    tall = (pa[..., 3] > 128).sum(0) >= PILLAR_COLS * POST_H * 0.55     # корпус: высокие колонки
    cols = np.nonzero(tall)[0]
    # корпус — самая длинная связная серия высоких колонок
    runs, start = [], cols[0]
    for p0, p1 in zip(cols[:-1], cols[1:]):
        if p1 != p0 + 1:
            runs.append((start, p0)); start = p1
    runs.append((start, cols[-1]))
    r0, r1 = max(runs, key=lambda r: r[1] - r[0])
    center = (r0 + r1) / 2.0
    print("столб:", post.size, "корпус колонки", (int(r0), int(r1)), "центр", round(center, 1))
    ox = round(POST_W * 0.34 - center)    # корпус ближе к левой трети холста — справа место под фонарь
    full = Image.new("RGBA", (POST_W, POST_H)); full.paste(post, (ox, 0), post)
    corner = Image.new("RGBA", (POST_W, POST_H))
    corner.paste(post.crop((0, 0, int(r1) + 3, POST_H)), (ox, 0), post.crop((0, 0, int(r1) + 3, POST_H)))
    full, corner = quantize([full, corner])
    # лента: огонь мерцает
    frames = []
    fa = np.asarray(full).copy()
    flame = is_flame(fa)
    fy, fx = np.nonzero(flame)
    print("пикселей огня:", int(flame.sum()))
    for f in range(LANTERN_FRAMES):
        fr = fa.copy()
        gain = FLICKER[f]
        rgb = fr[..., :3].astype(float)
        rgb[flame] = np.clip(rgb[flame] * gain, 0, 255)
        fr[..., :3] = rgb.astype(np.uint8)
        # кончики огня: верхние строки каждого языка пламени (по колонке) то есть, то нет
        for x in np.unique(fx):
            col = np.nonzero(flame[:, x])[0]
            top = col.min()
            if ((x * 7 + f * 13) % 5) < 2:
                fr[top, x, 3] = 0
        frames.append(Image.fromarray(fr, "RGBA"))
    return corner, frames, int(round(POST_W * 0.34))


def main() -> None:
    sheet = Image.fromarray(key_green(np.asarray(Image.open(SRC).convert("RGBA"))), "RGBA")
    spans, report = [], []
    for i in range(3):
        im = sprite_from_cell(cell(sheet, i), PUT["span"], SPAN_SIZE)
        ref = Image.open(CHAOS / f"span_{i}.png").convert("RGBA")
        dx, dy, iou = align(im, ref)
        report.append((i, dx, dy, round(iou, 3)))
        spans.append(shift_img(im, dx, dy))
    print("пролёты (сдвиг, IoU с Хаосом):", report)
    OUT.mkdir(parents=True, exist_ok=True)
    for i, im in enumerate(quantize(spans)):
        im.save(OUT / f"span_{i}.png")
    print("сохранены пролёты →", OUT)
    corner, frames, base_x = post_images()
    corner.save(OUT / "post_corner.png")
    strip = Image.new("RGBA", (POST_W * LANTERN_FRAMES, POST_H))
    for i, fr in enumerate(frames):
        strip.paste(fr, (i * POST_W, 0))
    strip.save(OUT / "post_lantern_strip.png")
    print(f"столб: холст {POST_W}x{POST_H}, post_base = ({base_x}, {POST_H - 1}), лента {LANTERN_FRAMES} кадров")


if __name__ == "__main__":
    main()
