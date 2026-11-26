"""Струя огнемёта (EFFECTS_NEEDED 10.1, ТЗ ART_TZ_EFFECTS_2026-11-24 п. 2, 25.11.2026): мастер Layer + движение кодом.

Мастер — лист с четырьмя элементами огня (assets/source_sheets/flamethrower_v2_2026-11-25/sheet_<вариант>.png, вправо):
длинная струя, вспышка у дула, огонь на цели, оторвавшийся язык. Элементы находятся сами (связные области альфы). Четыре листа
тех же размеров, что у FlameStream (код не меняется), кадры в одну строку слева направо:
  start.png  384×64  — 6 кадров 64×64, вспышка растёт и гаснет, якорь — левый край, середина высоты (дуло)
  jet.png   1024×48  — 8 кадров 128×48, бесшовное тело: плитка из мастера, зашитая по краям, течёт вправо на 1/8 периода за кадр
                       (цикл замкнут), лёгкая волна по высоте (период — длина кадра); сверху и снизу запас ≥ 4 px
  hit.png    512×64  — 8 кадров 64×64, огонь на цели растёт, расходится и гаснет, якорь — центр
  tail.png   256×48  — 4 кадра 64×48, язык догорает и тает вверх, якорь — левый край, середина высоты
Запуск (из корня проекта):
  python tools/flamethrower_build.py A|B [--install]
Без --install пишет в <папка мастеров>/out_<вариант>/ и превью preview_<вариант>.png; с --install — в assets/effects/flamethrower.
"""
import math
import os
import sys

import numpy as np
from PIL import Image

VARIANT = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else "B"
INSTALL = "--install" in sys.argv
SRC = "assets/source_sheets/flamethrower_v2_2026-11-25"
OUT = "assets/effects/flamethrower" if INSTALL else os.path.join(SRC, "out_" + VARIANT)
PALETTE_COLORS = 48
JET_PERIOD = 128
JET_H = 48
JET_BODY = 40        # толщина тела струи в кадре (запас ≥ 4 px сверху и снизу)


def components(img: Image.Image):
    """Связные области альфы по сетке 1/4 с расширением: список (x0, y0, x1, y1, площадь)."""
    a = np.array(img.getchannel("A")) > 30
    h4, w4 = a.shape[0] // 4, a.shape[1] // 4
    g = a[:h4 * 4, :w4 * 4].reshape(h4, 4, w4, 4).any(axis=(1, 3))
    # расширение на 3 клетки: искры и дым склеиваются со своим элементом
    d = g.copy()
    for _ in range(3):
        d = d | np.roll(d, 1, 0) | np.roll(d, -1, 0) | np.roll(d, 1, 1) | np.roll(d, -1, 1)
    lab = np.zeros(d.shape, dtype=np.int32)
    n = 0
    for y in range(d.shape[0]):
        for x in range(d.shape[1]):
            if d[y, x] and lab[y, x] == 0:
                n += 1
                stack = [(y, x)]
                lab[y, x] = n
                while stack:
                    cy, cx = stack.pop()
                    for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                        if 0 <= ny < d.shape[0] and 0 <= nx < d.shape[1] and d[ny, nx] and lab[ny, nx] == 0:
                            lab[ny, nx] = n
                            stack.append((ny, nx))
    out = []
    for i in range(1, n + 1):
        ys, xs = np.where((lab == i) & g)
        if len(xs) < 40:
            continue
        out.append((xs.min() * 4, ys.min() * 4, (xs.max() + 1) * 4, (ys.max() + 1) * 4, int(len(xs))))
    return out


def classify(comps):
    comps = [c for c in comps if c[4] >= 150]   # отдельные искры и крошки не считаются элементами
    jet = max(comps, key=lambda c: c[2] - c[0])
    rest = [c for c in comps if c is not jet]
    lick = max(rest, key=lambda c: (c[1] + c[3]) / 2.0)
    rest = [c for c in rest if c is not lick]
    hit = max(rest, key=lambda c: c[4])
    muzzle = max([c for c in rest if c is not hit], key=lambda c: c[4])
    return jet, muzzle, hit, lick


def crop(img, box, pad=6):
    x0, y0, x1, y1 = box[:4]
    return img.crop((max(x0 - pad, 0), max(y0 - pad, 0), min(x1 + pad, img.width), min(y1 + pad, img.height)))


def fit(img: Image.Image, canvas, scale, anchor, at, alpha=1.0, dy=0.0):
    """Вписать img в холст canvas (RGBA) с масштабом, точка anchor спрайта (доли) ложится в точку at."""
    w, h = max(int(img.width * scale), 1), max(int(img.height * scale), 1)
    s = img.resize((w, h), Image.LANCZOS)
    if alpha < 1.0:
        a = np.array(s.getchannel("A")).astype(np.float32) * alpha
        s.putalpha(Image.fromarray(a.astype(np.uint8)))
    canvas.alpha_composite(s, (int(round(at[0] - anchor[0] * w)), int(round(at[1] - anchor[1] * h + dy))))


def seamless_tile(strip: np.ndarray, period: int, blend: int):
    """Плитка period×H из полосы шириной ≥ period + blend: левый край перетекает в продолжение правого — бесшовно по горизонтали."""
    h = strip.shape[0]
    tile = strip[:, :period].astype(np.float32).copy()
    for x in range(blend):
        w = x / float(blend)
        tile[:, x] = tile[:, x] * w + strip[:, period + x].astype(np.float32) * (1 - w)
    return tile


def build_jet(jet_img: Image.Image):
    arr = np.array(jet_img).astype(np.float32)
    al = arr[:, :, 3] > 40
    cols = np.where(al.any(0))[0]
    width = cols.max() - cols.min()
    # серединный отрезок тела: 35–70% длины, ось — среднее по высоте
    x0 = int(cols.min() + width * 0.35)
    x1 = int(cols.min() + width * 0.70)
    seg = arr[:, x0:x1]
    sal = al[:, x0:x1]
    ys = np.where(sal.any(1))[0]
    axis = int(np.average(np.arange(sal.shape[0])[:, None] * np.ones((1, sal.shape[1])), weights=sal.astype(float) + 1e-6))
    thick = np.percentile(sal.sum(0), 92)
    scale = JET_BODY / max(thick * 1.25, 1.0)
    seg_h = int(JET_H / scale)
    top = axis - seg_h // 2
    band = np.zeros((seg_h, seg.shape[1], 4), dtype=np.float32)
    sy0, sy1 = max(top, 0), min(top + seg_h, seg.shape[0])
    band[sy0 - top:sy1 - top] = seg[sy0:sy1]
    img = Image.fromarray(band.astype(np.uint8)).resize((int(band.shape[1] * scale), JET_H), Image.LANCZOS)
    a = np.array(img).astype(np.float32)
    need = JET_PERIOD + int(JET_PERIOD * 0.35)
    if a.shape[1] < need:   # отрезок короче нужного — растягиваем по ширине (течение чуть медленнее)
        a = np.array(Image.fromarray(a.astype(np.uint8)).resize((need, JET_H), Image.LANCZOS)).astype(np.float32)
    tile = seamless_tile(a, JET_PERIOD, int(JET_PERIOD * 0.35))
    frames = []
    for k in range(8):
        shift = k * JET_PERIOD // 8
        f = np.roll(tile, shift, axis=1)
        out = f   # без волны по колонкам: целочисленный сдвиг столбцов ломал косые детали вертикальными полосами
        # запас сверху и снизу ≥ 4 px: мягкое гашение
        for r in range(6):
            fade = r / 6.0
            out[r, :, 3] *= fade
            out[JET_H - 1 - r, :, 3] *= fade
        frames.append(Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)))
    return frames


def build_start(img: Image.Image):
    frames = []
    scales = [0.30, 0.52, 0.80, 1.0, 0.86, 0.62]
    alphas = [1.0, 1.0, 1.0, 1.0, 0.85, 0.55]
    base = 58.0 / img.width   # на пике — вся ширина кадра (минус запас под дуло)
    for s, a in zip(scales, alphas):
        c = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
        fit(img, c, base * s, (0.0, 0.5), (2, 32), a)
        frames.append(c)
    return frames


def build_hit(img: Image.Image):
    frames = []
    scales = [0.30, 0.55, 0.80, 1.0, 1.0, 0.92, 0.78, 0.60]
    alphas = [1.0, 1.0, 1.0, 1.0, 0.92, 0.72, 0.45, 0.20]
    base = 62.0 / max(img.width, img.height)
    for i, (s, a) in enumerate(zip(scales, alphas)):
        c = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
        fit(img, c, base * s, (0.5, 0.5), (32, 32), a, dy=-0.06 * i * 4)   # дым и искры чуть поднимаются
        frames.append(c)
    return frames


def build_tail(img: Image.Image):
    frames = []
    scales = [1.0, 0.86, 0.66, 0.42]
    alphas = [1.0, 0.9, 0.62, 0.28]
    dys = [0, -4, -9, -15]
    base = 40.0 / img.height
    for s, a, dy in zip(scales, alphas, dys):
        c = Image.new("RGBA", (64, 48), (0, 0, 0, 0))
        fit(img, c, base * s, (0.0, 0.8), (3, 40), a, dy=dy)
        frames.append(c)
    return frames


def strip(frames, w, h):
    s = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        s.paste(f, (i * w, 0))
    return s


def main():
    sheet = Image.open(os.path.join(SRC, "sheet_%s.png" % VARIANT)).convert("RGBA")
    comps = components(sheet)
    jet_c, muzzle_c, hit_c, lick_c = classify(comps)
    print("jet", jet_c[:4], "muzzle", muzzle_c[:4], "hit", hit_c[:4], "lick", lick_c[:4])
    jet = build_jet(crop(sheet, jet_c))
    start = build_start(crop(sheet, muzzle_c))
    hit = build_hit(crop(sheet, hit_c))
    tail = build_tail(crop(sheet, lick_c))
    sheets = {"start": strip(start, 64, 64), "jet": strip(jet, JET_PERIOD, JET_H), "hit": strip(hit, 64, 64), "tail": strip(tail, 64, 48)}
    # общая палитра на все кадры, мягкая альфа сохраняется
    allrgb = Image.new("RGB", (sum(s.width for s in sheets.values()), 64))
    x = 0
    for s in sheets.values():
        rgb = Image.new("RGB", s.size, (0, 0, 0))
        rgb.paste(s.convert("RGB"), mask=s.getchannel("A").point(lambda v: 255 if v > 30 else 0))
        allrgb.paste(rgb, (x, 0))
        x += s.width
    pal = allrgb.quantize(PALETTE_COLORS, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    os.makedirs(OUT, exist_ok=True)
    finals = {}
    for name, s in sheets.items():
        a = s.getchannel("A")
        q = s.convert("RGB").quantize(palette=pal, dither=Image.Dither.NONE).convert("RGB").convert("RGBA")
        q.putalpha(a)
        q.save(os.path.join(OUT, name + ".png"))
        finals[name] = q
    # превью: полосы кадров ×3 и тест бесшовности (три копии jet подряд), макет «струя от дула до цели»
    ground = (30, 22, 25, 255)
    P = Image.new("RGBA", (1536, 520), ground)
    j3 = Image.new("RGBA", (JET_PERIOD * 3, JET_H), (0, 0, 0, 0))
    for i in range(3):
        j3.alpha_composite(finals["jet"].crop((0, 0, JET_PERIOD, JET_H)), (i * JET_PERIOD, 0))
    P.alpha_composite(j3.resize((j3.width * 2, j3.height * 2), Image.NEAREST), (10, 10))   # кадр 0 ×3 копии
    j3b = Image.new("RGBA", (JET_PERIOD * 3, JET_H), (0, 0, 0, 0))
    for i in range(3):
        j3b.alpha_composite(finals["jet"].crop((JET_PERIOD * 4, 0, JET_PERIOD * 5, JET_H)), (i * JET_PERIOD, 0))
    P.alpha_composite(j3b.resize((j3b.width * 2, j3b.height * 2), Image.NEAREST), (10, 120))   # кадр 4 ×3 копии
    P.alpha_composite(finals["start"].resize((finals["start"].width * 2, 128), Image.NEAREST), (10, 230))
    P.alpha_composite(finals["hit"].resize((finals["hit"].width * 2, 128), Image.NEAREST), (10, 370))
    P.alpha_composite(finals["tail"].resize((finals["tail"].width * 3, 144), Image.NEAREST), (1000, 230))
    P.convert("RGB").save(os.path.join(SRC, "preview_%s.png" % VARIANT))
    # макет: дуло слева, цель справа (кадры 3 start, 3 jet-копии, 4 hit)
    mock = Image.new("RGBA", (640, 140), ground)
    mock.alpha_composite(finals["start"].crop((64 * 3, 0, 64 * 4, 64)), (20, 38))
    for i in range(3):
        mock.alpha_composite(finals["jet"].crop((JET_PERIOD * 2, 0, JET_PERIOD * 3, JET_H)), (20 + 56 + i * JET_PERIOD, 46))
    mock.alpha_composite(finals["hit"].crop((64 * 3, 0, 64 * 4, 64)), (470, 38))
    mock.convert("RGB").resize((1280, 280), Image.NEAREST).save(os.path.join(SRC, "mock_%s.png" % VARIANT))
    print("готово ->", OUT)


if __name__ == "__main__":
    main()
