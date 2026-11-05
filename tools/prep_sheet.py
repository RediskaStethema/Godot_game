"""Лист пользователя (прозрачный фон, заголовок сверху, ряды кадров) → чистая копия для
tools/sheet_to_frames.py: подписи стёрты, ряды разложены с промежутками.

    python tools/prep_sheet.py <лист.png> <выход.png> [--rows N] [--join i,j] [--flip] [--keep i,j,…]

Ряд — полоса строк с плотными пикселями (альфа > ALPHA_MIN) выше MIN_ROW; полосы ниже (заголовок
листа, подписи, крошки) стираются. --rows N — рядов на листе: слипшиеся полосы (свечение, молния,
крылья достают до соседнего ряда) делятся по самой пустой строке середины самой высокой полосы,
пока рядов не станет N. --join i,j — ряд j (с нуля) дописывается справа к ряду i (кадры ряда
не поместились в ширину листа — орудия). --flip — отразить (здание нарисовано стволом влево:
Building стреляет вправо). --keep — оставить только эти ряды (лишние — не наши анимации).
"""
import sys

import numpy as np
from PIL import Image

ALPHA_MIN = 128
NOISE_ALPHA = 16     # ореол фона листа — в ноль
MIN_ROW = 60
GAP = 40             # промежуток между рядами на выходе
SPLIT_ZONE = (0.3, 0.7)


def bands(a):
    rows = (a > ALPHA_MIN).any(axis=1)
    out, s = [], None
    for y, v in enumerate(rows):
        if v and s is None:
            s = y
        elif not v and s is not None:
            out.append([s, y])
            s = None
    if s is not None:
        out.append([s, len(rows)])
    return [b for b in out if b[1] - b[0] >= MIN_ROW]


def split(a, rows, n):
    while len(rows) < n:
        i = max(range(len(rows)), key=lambda k: rows[k][1] - rows[k][0])
        y0, y1 = rows[i]
        lo, hi = y0 + int((y1 - y0) * SPLIT_ZONE[0]), y0 + int((y1 - y0) * SPLIT_ZONE[1])
        counts = (a[lo:hi] > ALPHA_MIN).sum(axis=1)
        cut = lo + int(np.argmin(counts))
        rows[i:i + 1] = [[y0, cut], [cut, y1]]
    return rows


def main(args):
    src, dst = args[0], args[1]
    opts = {}
    flags = args[2:]
    for k in ("--rows", "--join", "--keep"):
        if k in flags:
            i = flags.index(k)
            opts[k] = flags[i + 1]
            del flags[i:i + 2]
    img = Image.open(src).convert("RGBA")
    if "--flip" in flags:
        img = img.transpose(Image.FLIP_LEFT_RIGHT)
    px = np.array(img)
    px[px[..., 3] < NOISE_ALPHA] = 0
    a = px[..., 3]
    rows = bands(a)
    if "--rows" in opts:
        rows = split(a, rows, int(opts["--rows"]))
    pieces = [px[y0:y1] for y0, y1 in rows]
    if "--join" in opts:
        i, j = (int(v) for v in opts["--join"].split(","))
        left, right = pieces[i], pieces[j]
        h = max(left.shape[0], right.shape[0])
        joined = np.zeros((h, left.shape[1] + right.shape[1], 4), np.uint8)
        joined[h - left.shape[0]:, :left.shape[1]] = left        # по низу: линия земли общая
        joined[h - right.shape[0]:, left.shape[1]:] = right
        pieces[i] = joined
        del pieces[j]
    if "--keep" in opts:
        pieces = [pieces[int(k)] for k in opts["--keep"].split(",")]
    w = max(p.shape[1] for p in pieces)
    out = np.zeros((sum(p.shape[0] for p in pieces) + GAP * (len(pieces) + 1), w, 4), np.uint8)
    y = GAP
    for p in pieces:
        out[y:y + p.shape[0], :p.shape[1]] = p
        y += p.shape[0] + GAP
    Image.fromarray(out).save(dst)
    print(f"{dst}: рядов {len(pieces)}, {[p.shape[0] for p in pieces]}")


if __name__ == "__main__":
    main(sys.argv[1:])
