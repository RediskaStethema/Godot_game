"""Кадры цитадели одной расы (<раса>_<анимация>_NN.png: idle — 1 кадр, attack / hit / fall — по N) →
лист кадров для FactionTheme "citadel" (ряды idle, attack, hit, fall; кадр — размер файлов).

    python tools/citadel_frames_fit.py <папка кадров> <раса> <лист.png> <anchor x> <anchor y> <scale> [эталон]

эталон — ряд, к 1-му кадру которого подгоняются остальные (по умолчанию attack; пакет Космодесанта 10.11.2026 —
idle: стойку видно чаще всего, её кадры не пересэмплируются).

Ряды пакета нарисованы в разном масштабе (25.10.2026: у Хаоса попадание на 20% мельче выстрела, стойка —
крупнее) — цитадель прыгала бы в размере. Эталон — 1-й кадр выстрела (решение пользователя): 1-й кадр
каждого другого ряда подгоняется к нему по силуэту тела (масштаб + сдвиг основания, register из
citadel_from_sheet.py), весь ряд — тем же преобразованием (движение внутри ряда не трогается).
anchor / scale — нынешние из FactionTheme (для прежней стойки): печатаются новые — основание в пространстве
эталона и масштаб, при котором стойка на поле прежнего размера.
Обрывки (тонкие полосы над крышей, крошки вдали от крепости) стираются.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
import citadel_from_sheet  # noqa: E402
from citadel_from_sheet import REG_BODY, register, silhouette  # noqa: E402
from tiles_from_sheet import components, dilate  # noqa: E402

ROWS = ["idle", "attack", "hit", "fall"]
SCALE_EPS = 0.02      # подгонка мельче — только сдвиг (без пересэмплирования)
SCRAP_PX = 80         # обрывок: пятно меньше…
SCRAP_FAR = 10        # …дальше этого от крепости, или тонкая полоса (высота ≤ STRIP_H, ширина ≥ STRIP_W)
STRIP_H = 6
STRIP_W = 20
# Брак рядов, который clean не берёт (полоса прилипла к дымке): (раса, анимация) → стереть строки кадра выше y.
# Хаос, выстрел: тёмная полоса над шпилем в кадрах 3–9 (y 54–56), сама крепость начинается с y 58
STRAY_ABOVE = {("chaos", "attack"): 57}
REG_SHIFT = 16        # ряды пакета смещены сильнее, чем кадры прежнего листа (там ±8)


def load_rows(folder, race):
    rows = {}
    for anim in ROWS:
        files = sorted(Path(folder).glob("%s_%s_*.png" % (race, anim)))
        rows[anim] = [np.array(Image.open(f).convert("RGBA")) for f in files]
        if (race, anim) in STRAY_ABOVE:
            for frame in rows[anim]:
                frame[:STRAY_ABOVE[(race, anim)]] = 0
    return rows


def clean(frame):
    """Стирает обрывки: тонкие полосы и мелкие пятна вдали от самого крупного куска (крепости)."""
    label, ids = components(frame[..., 3] > 30)
    if not ids:
        return frame
    sizes = {n: int((label == n).sum()) for n in ids}
    main = max(sizes, key=sizes.get)
    near = dilate(label == main, SCRAP_FAR)
    for n in ids:
        if n == main:
            continue
        ys, xs = np.nonzero(label == n)
        strip = ys.max() - ys.min() + 1 <= STRIP_H and xs.max() - xs.min() + 1 >= STRIP_W
        if strip or (sizes[n] < SCRAP_PX and not near[ys, xs].any()):
            frame[label == n] = 0
    return frame


def transform(frame, anchor, scale, dx, dy):
    """Масштаб вокруг основания anchor и сдвиг (как в register): p → anchor + scale·(p − anchor) + d."""
    h, w = frame.shape[:2]
    im = Image.fromarray(frame)
    if abs(scale - 1.0) > SCALE_EPS:
        im = im.resize((round(w * scale), round(h * scale)), Image.LANCZOS)
    else:
        scale = 1.0
    out = Image.new("RGBA", (w, h))
    ox = round(anchor[0] - anchor[0] * scale + dx)
    oy = round(anchor[1] - anchor[1] * scale + dy)
    out.paste(im, (ox, oy), im)
    return np.array(out)


def main(folder, race, out_path, ax, ay, theme_scale, ref_anim="attack"):
    citadel_from_sheet.REG_SHIFT = REG_SHIFT
    anchor = (float(ax), float(ay))
    rows = load_rows(folder, race)
    ref = silhouette(rows[ref_anim][0], anchor, 1.0, REG_BODY)
    fits = {ref_anim: (1.0, 1.0, 0, 0)}
    for anim in [a for a in ROWS if a != ref_anim]:
        fits[anim] = register(rows[anim][0], anchor, ref, REG_BODY)
    h, w = rows[ref_anim][0].shape[:2]
    cols = max(len(rows[a]) for a in ROWS)
    sheet = Image.new("RGBA", (w * cols, h * len(ROWS)))
    for r, anim in enumerate(ROWS):
        iou, s, dx, dy = fits[anim]
        print("%-6s IoU %.3f  масштаб %.2f  сдвиг (%d, %d)  кадров %d" % (anim, iou, s, dx, dy, len(rows[anim])))
        for i, frame in enumerate(rows[anim]):
            f = clean(transform(frame, anchor, s, dx, dy))
            sheet.paste(Image.fromarray(f), (i * w, r * h))
    sheet.save(out_path)
    s_idle, dx_idle, dy_idle = fits["idle"][1:]
    print("frame_size: Vector2i(%d, %d)" % (w, h))
    print("anchor: Vector2(%.0f, %.0f)" % (anchor[0] + dx_idle, anchor[1] + dy_idle))
    print("scale: %.3f (стойка на поле — прежнего размера)" % (float(theme_scale) / s_idle))
    print("rows: " + ", ".join('"%s": [%d, %d]' % (a, r, len(rows[a])) for r, a in enumerate(ROWS)))


if __name__ == "__main__":
    main(*sys.argv[1:8])
