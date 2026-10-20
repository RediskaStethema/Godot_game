"""Лист анимации цитадели без надёжных меток основания (ряды idle / attack / hit / fall, шапки рядов
слева, номера кадров под рядом, свечение и дым связывают соседние кадры) → лист кадров для
FactionTheme "citadel", как tools/citadel_from_sheet.py.

    python tools/citadel_from_bands.py Сitadel_spacemarine_spritesheeld.png assets/sprites/props/space_marines/citadel

Ряды — полосы плотных пикселей (альфа > DENSE) по вертикали; шапка ряда (низкое пятно у левого
края) стирается. Кадры в ряду — по номерам под рядом: граница кадров — самый пустой столбец
около середины между соседними номерами (кадры, слипшиеся свечением, так тоже делятся).
Основание кадра — низ силуэта, по x — центр площадки (нижние BASE_BAND px). Стабилизация:
каждый стоящий кадр подгоняется к первому кадру idle по силуэту тела (масштаб + сдвиг —
citadel_from_sheet.register), руины обрушения — масштабом последнего стоящего кадра; следы
снарядов срезаны (снаряд рисует игра), вспышка у ствола остаётся. Стилизация — та же
(citadel_from_sheet.stylize: камень холоднее и глуше, огни и синий ордена — как есть).
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
from citadel_from_sheet import ROWS, PAD, FALL_STANDING, REG_BODY, drop_scraps, red_marker, register, silhouette, stylize  # noqa: E402
from tiles_from_sheet import dilate  # noqa: E402

DENSE = 200          # плотный пиксель
ALPHA_CUT = 40       # ореол фона листа — прочь
ROW_MIN_H = 120      # полоса ниже — подписи / шапка
HEADER_W = 380       # шапка ряда — у левого края, не шире
HEADER_H = 64        # и не выше
SPLIT_WINDOW = 45    # px вокруг середины между номерами, где ищется пустой столбец
BASE_BAND = 22       # нижняя полоса силуэта — площадка, по ней центр основания
TRAIL_KEEP = 14      # след снаряда за центром вспышки: столько px остаётся,
TRAIL_FADE = 10      # дальше гаснет на столько px (жёсткий срез дыма виден)
MARKER_BAND = 26     # метка основания — в нижних px кадра,
MARKER_NEAR = 45     # не дальше от центра основания
# 4-й кадр попадания — уже груда обломков (начало обрушения), в цикле мигал бы; idle 11–12 листа
# нарисованы сжатыми по ширине — после подгонки по высоте крепость в них толще (в шапке — 8 кадров)
SKIP = {"idle": [8, 9], "hit": [3]}
# Высота: кадры листа нарисованы с разными пропорциями — ширина после подгонки одна, а крыша
# гуляет на ±10% (крепость «дышит»). Крыша — верх строк шире ROOF_WIDE ширины корпуса; кадр
# тянется по вертикали, пока крыша не встанет на высоту эталона (не больше чем на ±STRETCH_MAX)
ROOF_WIDE = 0.6
BODY_ROW = 40        # корпус — строка на столько px выше основания
STRETCH_MAX = 0.2


def runs(mask_1d, min_len=1):
    out, start = [], None
    for i, v in enumerate(mask_1d):
        if v and start is None:
            start = i
        elif not v and start is not None:
            out.append((start, i))
            start = None
    if start is not None:
        out.append((start, len(mask_1d)))
    return [r for r in out if r[1] - r[0] >= min_len]


def label_centers(img, y0, y1):
    """x номеров кадров (белые цифры) в полосе подписей."""
    band = (img[y0:y1, :, 3] > DENSE) & (img[y0:y1, :, :3].min(axis=2) > 150)
    merged = []
    for r in runs(band.any(axis=0)):
        if merged and r[0] - merged[-1][1] < 8:   # двузначный номер
            merged[-1] = (merged[-1][0], r[1])
        else:
            merged.append(r)
    return [(a + b) // 2 for a, b in merged]


def find_rows(img):
    """[(верх, низ ряда кадров, верх, низ подписей)]: полосы плотных пикселей по вертикали; верх
    ряда — от подписей ряда выше (шапка ряда и верхушки кадров — знамя, шпили — в одной полосе)."""
    bands = runs((img[..., 3] > DENSE).sum(axis=1) > 3)
    rows, prev_end = [], 0
    for k, (y0, y1) in enumerate(bands):
        if y1 - y0 >= ROW_MIN_H and k + 1 < len(bands):
            rows.append((prev_end, y1, *bands[k + 1]))
            prev_end = bands[k + 1][1]
    return rows


def erase_header(img, top):
    """Шапка ряда («1. IDLE (8 кадров)») — первая сверху полоса у левого края, плотная больше чем
    наполовину HEADER_W, в первых HEADER_H px ряда (ниже — уже кадры, два кадра тоже бывают такими)."""
    full = (img[top:top + HEADER_H + 20, :HEADER_W, 3] > DENSE).sum(axis=1) > HEADER_W * 0.5
    found = runs(full)
    if found and found[0][1] - found[0][0] < HEADER_H:
        y0, y1 = found[0]
        img[max(top + y0 - 4, 0):top + y1 + 4, :HEADER_W, 3] = 0


def marker_mask(frame, anchor):
    """Ромб-метка основания (бурый красный) — в нижней полосе кадра у центра основания."""
    r, g, b, a = [frame[..., i].astype(int) for i in range(4)]
    m = (r > 100) & (r - g > 45) & (r - b > 55) & (a > 100)
    m[:int(anchor[1]) - MARKER_BAND] = False
    m[:, :max(int(anchor[0]) - MARKER_NEAR, 0)] = False
    m[:, int(anchor[0]) + MARKER_NEAR:] = False
    return m


def erase_markers(frame, anchor):
    """Метка основания → камень площадки (медиана цвета вокруг)."""
    m = marker_mask(frame, anchor)
    if not m.any():
        return
    spot = dilate(m, 2) & (frame[..., 3] > 0)
    ring = dilate(m, 6) & ~spot & (frame[..., 3] > DENSE)
    if ring.any():
        frame[spot, :3] = np.median(frame[ring][:, :3], axis=0).astype(np.uint8)


def roof_height(frame, anchor):
    """Высота крыши над основанием: верх строк, где крепость шире ROOF_WIDE ширины корпуса."""
    a = frame[..., 3] > DENSE
    body = np.nonzero(a[int(round(anchor[1])) - BODY_ROW])[0]
    wide = np.nonzero(a.sum(axis=1) > ROOF_WIDE * (body.max() - body.min()))[0]
    return anchor[1] - wide.min()


def flash_center(frame):
    """Центр вспышки выстрела — ярко-жёлтые пиксели в верхней половине кадра."""
    r, g, b, a = [frame[..., i].astype(int) for i in range(4)]
    m = (r > 235) & (g > 170) & (b < 140) & (a > DENSE)
    m[frame.shape[0] // 2:] = False
    ys, xs = np.nonzero(m)
    return (float(np.median(xs)), float(np.median(ys))) if len(xs) else None


def cut_trail(frame, flash):
    """След снаряда — за вспышкой вправо-вверх: гаснет за TRAIL_KEEP px от её центра."""
    cx, cy = flash
    h, w = frame.shape[:2]
    xs = np.arange(w)
    fade = np.clip(1.0 - (xs - cx - TRAIL_KEEP) / TRAIL_FADE, 0.0, 1.0)
    rows = slice(0, min(int(cy) + 25, h))
    frame[rows, :, 3] = (frame[rows, :, 3] * fade[None, :]).astype(np.uint8)


def base_point(frame):
    a = frame[..., 3] > DENSE
    ys, xs = np.nonzero(a)
    bottom = ys.max()
    sel = ys > bottom - BASE_BAND
    return float(xs[sel].min() + xs[sel].max()) / 2.0, float(bottom)


def main(sheet, out_dir):
    img = np.array(Image.open(sheet).convert("RGBA"))
    rows = find_rows(img)
    assert len(rows) == len(ROWS), f"рядов {len(rows)}, ждали {len(ROWS)}"
    cut, ref, standing, muzzles = [], None, None, []
    ref_roof, standing_sy = None, 1.0
    for name, (y0, y1, ly0, ly1) in zip(ROWS, rows):
        erase_header(img, y0)
        centers = label_centers(img, ly0, ly1)
        dense_x = (img[y0:y1, :, 3] > DENSE).sum(axis=0)
        edges = [0]
        for c0, c1 in zip(centers, centers[1:]):
            mid = (c0 + c1) // 2
            lo = max(mid - SPLIT_WINDOW, c0 + 1)
            edges.append(lo + int(np.argmin(dense_x[lo:min(mid + SPLIT_WINDOW, c1)])))
        edges.append(img.shape[1])
        for k in range(len(centers)):
            frame = img[y0:y1, edges[k]:edges[k + 1]].copy()
            frame[frame[..., 3] < ALPHA_CUT] = 0
            frame = drop_scraps(frame)
            anchor = base_point(frame)
            erase_markers(frame, anchor)
            flash = flash_center(frame) if name == "attack" else None
            if flash:
                cut_trail(frame, flash)
                frame = drop_scraps(frame, detached=True)
            if k in SKIP.get(name, []):
                continue
            if ref is None:
                ref = silhouette(frame, anchor, 1.0, REG_BODY)
                iou, scale, dx, dy = 1.0, 1.0, 0, 0
            elif name == "fall" and k >= FALL_STANDING:
                iou, scale, dx, dy = standing
            else:
                iou, scale, dx, dy = register(frame, anchor, ref, REG_BODY)
                if name == "fall":
                    standing = (iou, scale, dx, dy)
            if abs(scale - 1.0) > 1e-3:
                im = Image.fromarray(frame)
                frame = np.array(im.resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS))
            anchor = (anchor[0] * scale - dx, anchor[1] * scale - dy)
            if flash:
                flash = (flash[0] * scale - dx, flash[1] * scale - dy)
            # По вертикали — крыша на высоту эталона; руины — растяжкой последнего стоящего кадра
            if ref_roof is None:
                ref_roof, sy = roof_height(frame, anchor), 1.0
            elif name == "fall" and k >= FALL_STANDING:
                sy = standing_sy
            else:
                sy = float(np.clip(ref_roof / roof_height(frame, anchor), 1.0 - STRETCH_MAX, 1.0 + STRETCH_MAX))
                if name == "fall":
                    standing_sy = sy
            if abs(sy - 1.0) > 1e-3:
                im = Image.fromarray(frame)
                frame = np.array(im.resize((im.width, round(im.height * sy)), Image.LANCZOS))
                # основание остаётся на месте: всё, что выше него, тянется от него
                anchor = (anchor[0], anchor[1] * sy)
                if flash:
                    flash = (flash[0], flash[1] * sy)
            if flash:   # ствол — центр вспышки относительно основания
                muzzles.append((flash[0] - anchor[0], flash[1] - anchor[1]))
            print(f"  {name} {k + 1}: масштаб {scale:.2f}, по высоте ×{sy:.2f}, сдвиг ({dx}, {dy}), совпадение {iou:.2f}")
            ys, xs = np.nonzero(frame[..., 3])
            frame = frame[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
            cut.append((name, stylize(frame), (anchor[0] - xs.min(), anchor[1] - ys.min())))
        print(f"{name}: {len(centers) - len(SKIP.get(name, []))} кадров")
    if muzzles:
        mx, my = np.median(np.array(muzzles), axis=0)
    left = max(a[0] for _, _, a in cut)
    up = max(a[1] for _, _, a in cut)
    right = max(f.shape[1] - a[0] for _, f, a in cut)
    down = max(f.shape[0] - a[1] for _, f, a in cut)
    fw, fh = int(np.ceil(left + right)) + 2 * PAD, int(np.ceil(up + down)) + 2 * PAD
    counts = {n: sum(1 for c in cut if c[0] == n) for n in ROWS}
    sheet_img = Image.new("RGBA", (fw * max(counts.values()), fh * len(ROWS)), (0, 0, 0, 0))
    col = {n: 0 for n in ROWS}
    for name, frame, (ax, ay) in cut:
        x = col[name] * fw + PAD + int(round(left - ax))
        y = ROWS.index(name) * fh + PAD + int(round(up - ay))
        sheet_img.alpha_composite(Image.fromarray(frame), (x, y))
        col[name] += 1
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    sheet_img.save(out / "sheet.png")
    print(f'"frame_size": Vector2i({fw}, {fh}), "anchor": Vector2({PAD + left:.0f}, {PAD + up:.0f}),')
    if muzzles:
        print(f'"muzzle": Vector2({PAD + left + mx:.0f}, {PAD + up + my:.0f}),')
    print('"rows": {' + ", ".join(f'"{n}": [{i}, {counts[n]}]' for i, n in enumerate(ROWS)) + "}")


if __name__ == "__main__":
    main(*sys.argv[1:3])
