"""Лист изометрических плит на чёрном фоне → отдельные PNG плит с прозрачным фоном.

    python tools/tiles_from_sheet.py assets/FightFleed/photo_2026-10-13_12-08-49.png assets/sprites/tiles/space_marines

Плита — крупное связное пятно ярче фона (BG_MAX); дыры внутри (тёмные кратеры) остаются,
снаружи всё прозрачно, контур — +EDGE px. Порядок — сверху вниз, слева направо: tile_0.png, …
В tiles.json для каждой плиты: width — ширина ромба (= левый…правый угол), top — y верхнего угла
ромба верхней грани в картинке (может быть > 0: руины и знамёна торчат выше) — для FactionTheme.
"""
import json
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

BG_MAX = 24          # фон — почти чёрный (max канала ≤ этого)
MIN_AREA = 2000      # меньше — пыль, не плита
EDGE = 1             # px контура вокруг плиты
JOIN = 6             # px — куски одной плиты (тёмный контур рвёт её) склеиваются через такой зазор
CORNER_COLS = 3      # ширина края, по которому ищется угол ромба


def components(mask):
    h, w = mask.shape
    label = np.zeros((h, w), np.int32)
    out = []
    n = 0
    for y in range(h):
        for x in range(w):
            if not mask[y, x] or label[y, x]:
                continue
            n += 1
            label[y, x] = n
            q = deque([(y, x)])
            pts = []
            while q:
                cy, cx = q.popleft()
                pts.append((cy, cx))
                for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not label[ny, nx]:
                        label[ny, nx] = n
                        q.append((ny, nx))
            if len(pts) >= MIN_AREA:
                out.append(n)
    return label, out


def fill_holes(m):
    """Всё, до чего нельзя дойти от края по фону, — плита."""
    h, w = m.shape
    outside = np.zeros_like(m)
    q = deque()
    for y in range(h):
        for x in (0, w - 1):
            if not m[y, x] and not outside[y, x]:
                outside[y, x] = True
                q.append((y, x))
    for x in range(w):
        for y in (0, h - 1):
            if not m[y, x] and not outside[y, x]:
                outside[y, x] = True
                q.append((y, x))
    while q:
        cy, cx = q.popleft()
        for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
            if 0 <= ny < h and 0 <= nx < w and not m[ny, nx] and not outside[ny, nx]:
                outside[ny, nx] = True
                q.append((ny, nx))
    return ~outside


def dilate(m, r):
    out = m.copy()
    for _ in range(r):
        grown = out.copy()
        grown[1:, :] |= out[:-1, :]
        grown[:-1, :] |= out[1:, :]
        grown[:, 1:] |= out[:, :-1]
        grown[:, :-1] |= out[:, 1:]
        out = grown
    return out


def erode(m, r):
    return ~dilate(~m, r)


def main(sheet, out_dir):
    img = np.array(Image.open(sheet).convert("RGB"))
    mask = img.max(axis=2) > BG_MAX
    label, ids = components(dilate(mask, JOIN))
    tiles = []
    for n in ids:
        ys, xs = np.nonzero(label == n)
        tiles.append((ys.min(), xs.min(), ys.max() + 1, xs.max() + 1, n))
    # Сверху вниз по рядам (центр по y с допуском), в ряду — слева направо
    tiles.sort(key=lambda t: (round((t[0] + t[2]) / 2 / 150), t[1]))

    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    meta = []
    for i, (y0, x0, y1, x1, n) in enumerate(tiles):
        # Закрытие: расширенное пятно без дыр, сжатое обратно, + контур EDGE
        m = fill_holes(label[y0:y1, x0:x1] == n)
        m = np.pad(m, 1)   # сжатие не должно «съедать» плиту от края рамки
        m = dilate(erode(m, JOIN), EDGE)[1:-1, 1:-1]
        cols, rows = np.nonzero(m.any(axis=0))[0], np.nonzero(m.any(axis=1))[0]
        m = m[rows.min():rows.max() + 1, cols.min():cols.max() + 1]
        y0, x0 = y0 + rows.min(), x0 + cols.min()
        y1, x1 = y0 + m.shape[0], x0 + m.shape[1]
        rgba = np.dstack([img[y0:y1, x0:x1], (m * 255).astype(np.uint8)])
        Image.fromarray(rgba).save(out / f"tile_{i}.png")
        # Угол ромба верхней грани — самая верхняя точка плиты у левого и правого края
        cols = np.nonzero(m.any(axis=0))[0]
        left, right = cols.min(), cols.max()
        ly = np.nonzero(m[:, left:left + CORNER_COLS].any(axis=1))[0].min()
        ry = np.nonzero(m[:, right - CORNER_COLS + 1:right + 1].any(axis=1))[0].min()
        width = int(right - left + 1)
        top = round((ly + ry) / 2 - width / 4)
        meta.append({"file": f"tile_{i}.png", "width": width, "top": int(top), "size": [int(x1 - x0), int(y1 - y0)]})
        print(meta[-1])
    (out / "tiles.json").write_text(json.dumps(meta, indent=1), encoding="utf-8")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
