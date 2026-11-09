"""Плита реки → прямое бесшовное русло с рябью вдоль течения (кадры анимации).

    python tools/river_straight.py <плита.png> <top> <выход_префикс> [кадров]

Решение пользователя 09.11.2026 (Screenshot 2026-11-09 093925.png: «река течёт перпендикулярно и
каменные перемычки»): у нарисованной плиты русло к одному концу шире, на концах — светлая кромка и
обломки, рябь пакета v2 в отражённой плите текла назад. Вдоль реки плита и её отражение чередовались —
на каждом стыке встречались концы с «губами» (перемычка), течение шло туда-сюда.

Здесь верхняя грань ромба разворачивается в квадрат (строки — вдоль русла, по оси v плиты; столбцы —
поперёк), берега каждой строки сдвигаются на общие (русло постоянной ширины), концы плиты заменяются
её серединой по шву наименьшей разницы (DP по столбцам) — плита стыкуется сама с собой, отражение не
нужно. Значки на воде стёрты, рябь — свои вытянутые вдоль течения блики, период — половина плиты:
за `кадров` кадров рябь проходит период и цикл замыкается, а на стыке плит рябь непрерывна (все клетки
реки играют в одной фазе — IsoGridRenderer). Над ромбом и боковые стенки — как были, кроме камней над
концом русла (ложились на соседнюю плиту). Выход: <префикс>_00.png … ; исходник не меняется.
"""
import sys

import numpy as np
from PIL import Image

N = 420                 # сторона квадрата развёртки, px
END_ZONE = 80           # строк у каждого конца, где идёт шов к середине
SEAM_MIN = 48           # шов не ближе стольких строк к концу плиты: кромка и обломки конца — до 45 строк
SEAM_MARGIN = 8         # и не ближе стольких к внутреннему краю зоны
FEATHER = 3             # растушёвка шва, строк
EDGE_SMOOTH = 41        # окно сглаживания берегов по строкам
GLYPH_LIFT = 22         # пиксель воды светлее медианы на столько — значок, стереть
RIPPLES = 7             # бликов на период
RIPPLE_COLOR = np.array([118.0, 142.0, 120.0])   # серо-зелёный блик (как рябь пакета)
RIPPLE_ALPHA = 0.42
BANK_FADE = 14          # блики гаснут к берегу, px квадрата


def water_mask(sq):
    r, g, b, a = sq[..., 0], sq[..., 1], sq[..., 2], sq[..., 3]
    return (a > 128) & (g - r >= 11) & (g - b >= 4)


def longest_run(row_mask, win=15):
    """Самый длинный отрезок строки, где в окне win больше половины — вода."""
    dens = np.convolve(row_mask.astype(float), np.ones(win) / win, mode="same") > 0.5
    best, start, cur = (0, 0), None, 0
    for i, v in enumerate(np.append(dens, False)):
        if v and start is None:
            start = i
        elif not v and start is not None:
            if i - start > best[1] - best[0]:
                best = (start, i - 1)
            start = None
    return best


def smooth(v, k):
    pad = k // 2
    p = np.pad(v, pad, mode="edge")
    med = np.array([np.median(p[i:i + k]) for i in range(len(v))])
    ker = np.ones(9) / 9
    return np.convolve(np.pad(med, 4, mode="edge"), ker, mode="valid")


def sample(img, ys, xs):
    """Билинейная выборка img[H, W, C] в точках (ys, xs)."""
    h, w = img.shape[:2]
    x0 = np.clip(np.floor(xs).astype(int), 0, w - 2)
    y0 = np.clip(np.floor(ys).astype(int), 0, h - 2)
    fx = np.clip(xs - x0, 0, 1)[..., None]
    fy = np.clip(ys - y0, 0, 1)[..., None]
    return (img[y0, x0] * (1 - fx) * (1 - fy) + img[y0, x0 + 1] * fx * (1 - fy)
            + img[y0 + 1, x0] * (1 - fx) * fy + img[y0 + 1, x0 + 1] * fx * fy)


def seam_rows(diff):
    """Шов через полосу diff[rows, cols]: строка для каждого столбца, соседние — не дальше 1."""
    rows, cols = diff.shape
    cost = diff.copy()
    back = np.zeros((rows, cols), dtype=int)
    for c in range(1, cols):
        prev = cost[:, c - 1]
        cand = np.stack([np.roll(prev, 1), prev, np.roll(prev, -1)])
        cand[0, 0] = np.inf
        cand[2, -1] = np.inf
        k = np.argmin(cand, axis=0)
        cost[:, c] += cand[k, np.arange(rows)]
        back[:, c] = np.arange(rows) + (k - 1)   # k = 0 — из строки выше, 2 — из строки ниже
    out = np.zeros(cols, dtype=int)
    out[-1] = int(np.argmin(cost[:, -1]))
    for c in range(cols - 1, 0, -1):
        out[c - 1] = np.clip(back[out[c], c], 0, rows - 1)
    return out


def main(src, top, prefix, frames=12):
    top = float(top)
    frames = int(frames)
    img = np.asarray(Image.open(src).convert("RGBA")).astype(float)
    h, w = img.shape[:2]
    hw, hh, cx, cy = w / 2, w / 4, w / 2, top

    # 1. Развёртка верхней грани: строка — b (вдоль русла), столбец — a (поперёк)
    bb, aa = np.mgrid[0:N, 0:N] / (N - 1)
    sq = sample(img, cy + hh * (aa + bb) - 0.5, cx + hw * (aa - bb) - 0.5)

    # 2. Берега строки → общие (русло постоянной ширины)
    water = water_mask(sq)
    lo = np.zeros(N)
    hi = np.zeros(N)
    for r in range(N):
        a0, a1 = longest_run(water[r])
        lo[r], hi[r] = (a0, a1) if a1 - a0 > 40 else (np.nan, np.nan)
    good = ~np.isnan(lo)
    lo = np.interp(np.arange(N), np.nonzero(good)[0], lo[good])
    hi = np.interp(np.arange(N), np.nonzero(good)[0], hi[good])
    lo, hi = smooth(lo, EDGE_SMOOTH), smooth(hi, EDGE_SMOOTH)
    mid = slice(END_ZONE, N - END_ZONE)
    l0, r0 = float(np.median(lo[mid])), float(np.median(hi[mid]))
    xs = np.arange(N, dtype=float)
    src_x = np.zeros((N, N))
    for r in range(N):
        src_x[r] = np.interp(xs, [0, l0, r0, N - 1], [0, lo[r], hi[r], N - 1])
    straight = sample(sq, np.repeat(np.arange(N, dtype=float)[:, None], N, 1), src_x)

    # 3. Значки на воде — стереть (вода под ними — размытая вода вокруг)
    inner = np.zeros((N, N), dtype=bool)
    inner[:, int(l0) + 6:int(r0) - 6] = True
    lum = straight[..., :3].mean(-1)
    wmed = np.median(lum[inner])
    glyph = inner & (lum > wmed + GLYPH_LIFT)
    glyph = glyph | np.roll(glyph, 1, 0) | np.roll(glyph, -1, 0) | np.roll(glyph, 1, 1) | np.roll(glyph, -1, 1)
    keep = inner & ~glyph
    blur = straight[..., :3] * keep[..., None]
    wsum = keep.astype(float)
    for _ in range(6):
        for ax in (0, 1):
            blur = (np.roll(blur, 3, ax) + blur + np.roll(blur, -3, ax)) / 3
            wsum = (np.roll(wsum, 3, ax) + wsum + np.roll(wsum, -3, ax)) / 3
    fill = blur / np.maximum(wsum, 1e-3)[..., None]
    straight[glyph, :3] = fill[glyph]

    # 4. Концы — середина плиты по шву: плита стыкуется сама с собой
    rolled = np.roll(straight, N // 2, axis=0)
    out = straight.copy()
    for zone in (np.arange(0, END_ZONE), np.arange(N - END_ZONE, N)[::-1]):
        d = np.abs(straight[zone, :, :3] - rolled[zone, :, :3]).sum(-1)
        d[:SEAM_MIN] = 1e9       # концы плиты (кромка, обломки) — всегда из середины
        d[-SEAM_MARGIN:] = 1e9
        cut = seam_rows(d)
        for c in range(N):
            for i, r in enumerate(zone):
                t = np.clip((i - cut[c]) / FEATHER + 0.5, 0, 1)   # 0 — середина плиты (у края), 1 — своё
                out[r, c] = rolled[r, c] * (1 - t) + straight[r, c] * t

    # 5. Кадры: рябь вдоль течения, период — половина плиты
    period = N // 2
    rng = np.random.default_rng(7)
    streaks = []
    for i in range(RIPPLES):
        streaks.append({
            "a": rng.uniform(l0 + BANK_FADE, r0 - BANK_FADE),
            "b": (i + rng.uniform(-0.3, 0.3)) * period / RIPPLES,
            "len": rng.uniform(34, 70),
            "wid": rng.uniform(2.6, 4.2),
            "amp": rng.uniform(0.6, 1.0),
            "wob": rng.uniform(0, np.pi * 2),
        })
    rows = np.arange(N, dtype=float)[:, None]
    cols = np.arange(N, dtype=float)[None, :]
    bank = np.clip(np.minimum(cols - l0, r0 - cols) / BANK_FADE, 0, 1)
    py, px = np.mgrid[0:h, 0:w]
    rx, ry = (px + 0.5 - cx) / hw, (py + 0.5 - cy) / hh
    pa, pb = (rx + ry) / 2, (ry - rx) / 2
    inside = (pa >= 0) & (pa <= 1) & (pb >= 0) & (pb <= 1)
    # камни над концом русла (над верхним правым краем ромба, b ≈ 0) ложились на соседнюю плиту
    above_end = (pb < 0) & (pa > 0.02) & (pa < 1.02) & (pb > -0.08)
    base = img.copy()
    base[above_end, 3] = 0
    for f in range(frames):
        shift = f * period / frames
        layer = np.zeros((N, N))
        for s in streaks:
            for rep in (-1, 0, 1, 2):
                b0 = s["b"] + shift + rep * period
                along = (rows - b0) / (s["len"] / 2)
                a0 = s["a"] + 3.0 * np.sin(rows / 23.0 + s["wob"])
                across = (cols - a0) / s["wid"]
                layer += s["amp"] * np.exp(-along ** 2 * 2.2 - across ** 2)
        alpha = np.clip(layer, 0, 1) * bank * RIPPLE_ALPHA
        frame_sq = out.copy()
        frame_sq[..., :3] = frame_sq[..., :3] * (1 - alpha[..., None]) + RIPPLE_COLOR * alpha[..., None]
        res = base.copy()
        res[inside] = sample(frame_sq, pb[inside] * (N - 1), pa[inside] * (N - 1))
        res[inside, 3] = img[inside, 3]
        Image.fromarray(np.clip(res, 0, 255).astype(np.uint8)).save("%s_%02d.png" % (prefix, f))
    print("русло: столбцы %.0f–%.0f из %d, кадров %d" % (l0, r0, N, frames))


if __name__ == "__main__":
    main(*sys.argv[1:5])
