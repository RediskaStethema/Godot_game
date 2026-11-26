"""Появление цитадели (EFFECTS_NEEDED 12.1, ТЗ ART_TZ_EFFECTS_2026-11-24 п. 3, 25.11.2026): мастер Layer + движение кодом.

Мастер — кольцо трещин вокруг площадки (пустой центр) от Layer: assets/source_sheets/citadel_spawn_2026-11-25/<сm|ch>_<вариант>.png
(sm — Космодесант, сухая земля, плиты, янтарь в трещинах; ch — Хаос, кольцевой разлом, багровый край и варп). Фазы ТЗ (16 кадров,
~12 к/с ≈ 1.3 с):
  0–3   земля вздрагивает, трещины проступают; 4–9 пик — ударная волна, пыль / свет, цитадель проявляется (игра);
  10–13 оседает; 14–15 остаточный дым, последний кадр почти пуст.
Два листа на расу (кадр 640×400, точка — центр ромба основания площадки (320, 300), кадры в одну строку слева направо):
  <раса>_back.png  — кольцо, ударная волна по земле, задний дым (RGBA, обычное смешивание; цитадель стоит поверх)
  <раса>_front.png — передняя пыль / языки варпа, крошка, искры (RGBA, обычное смешивание; цитадель под ним)
Запуск (из корня проекта):
  python tools/citadel_spawn_build.py sm|ch A|B [папка мастеров]
Пишет в <папка мастеров>/out_<раса>_<вариант>/ (<раса>_back.png, <раса>_front.png) и превью preview_<раса>_<вариант>.png / .gif.
В игру кладёт отдельная команда (после утверждения).
"""
import math
import os
import sys

import numpy as np
from PIL import Image

RACE = sys.argv[1] if len(sys.argv) > 1 else "sm"
VARIANT = sys.argv[2] if len(sys.argv) > 2 else "B"
SRC = sys.argv[3] if len(sys.argv) > 3 else "assets/source_sheets/citadel_spawn_2026-11-25"
OUT = os.path.join(SRC, "out_%s_%s" % (RACE, VARIANT))

FRAMES = 24                    # 25.11.2026: было 16 — плавнее (та же длительность, 18 к/с вместо 12); тайминг кодом — в 16-кадровой шкале T
TL = 16.0                      # длина «опорной» шкалы времени: фазы ТЗ заданы в ней, кадр t соответствует T = t · TL / FRAMES
W, H = 640, 400
ANCHOR = (320.0, 300.0)
RING_W = 330.0                 # внешняя ширина кольца в кадре, px (площадка ~280×140 в мире)
PIX = 2                        # «пиксель» слоя front
PALETTE_COLORS = 72
OPEN = [0.20, 0.45, 0.72, 0.92, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.86, 0.62, 0.36, 0.14, 0.04, 0.0]
LIGHT = [0.35, 0.55, 0.75, 0.9, 1.0, 1.0, 1.0, 0.95, 0.85, 0.75, 0.6, 0.45, 0.30, 0.15, 0.05, 0.0]
HEAVE = [0, 0, -2, -4, -5, -4, -3, -2, -1, 0, 0, 0, 0, 0, 0, 0]   # плиты подпрыгивают и садятся, px кадра
SM_RING_DARKEN = 0.70          # светлая земля и плиты мастера Космодесанта приглушаются (25.11.2026: кремовая пыль была главным пятном кадра)
CH_GLOW = (150, 30, 30)        # багровый отсвет Хаоса на земле вокруг кольца (слой front), пик на LIGHT

# ramp — ступени плотности пыли / дыма (тёмная кромка не берётся: чёрная обводка превращала облако в «пузырь»), alpha — их прозрачность
PAL = {
    "sm": {"ramp": [(88, 76, 62), (124, 110, 92), (170, 156, 136)], "alpha": [95, 140, 185],
           "dust": [(20, 16, 14), (88, 76, 62), (182, 168, 148)], "chip": [(28, 31, 41), (51, 56, 71), (96, 104, 124)],
           "spark": [(168, 128, 66), (211, 154, 58), (240, 176, 74)], "smoke": (70, 60, 50)},
    "ch": {"ramp": [(54, 20, 40), (84, 36, 80), (124, 60, 128)], "alpha": [90, 130, 170],
           "wave": [(70, 14, 20), (128, 18, 24), (190, 50, 28)],
           "dust": [(30, 6, 10), (128, 18, 24), (222, 68, 30)], "chip": [(30, 6, 10), (58, 26, 20), (163, 145, 122)],
           "spark": [(222, 68, 30), (255, 150, 60), (200, 80, 224)], "smoke": (52, 28, 52)},
}[RACE]
VIOLET_D, VIOLET_M, VIOLET_L = (122, 31, 162), (200, 80, 224), (230, 150, 245)


def cur(curve, T):
    """Значение кривой (список по 16-кадровой шкале) в момент T с линейной интерполяцией."""
    x = min(max(T, 0.0), len(curve) - 1.0)
    i = int(x)
    j = min(i + 1, len(curve) - 1)
    return curve[i] + (curve[j] - curve[i]) * (x - i)


def smooth_noise(seed, size):
    rng = np.random.RandomState(seed)
    out = np.zeros(size[::-1], dtype=np.float32)
    for grid, w in ((8, 0.55), (18, 0.3), (40, 0.15)):
        g = rng.rand(grid, int(grid * size[0] / size[1])).astype(np.float32)
        out += w * np.array(Image.fromarray((g * 255).astype(np.uint8)).resize(size, Image.BICUBIC)).astype(np.float32) / 255.0
    return out


def ring_geometry(img):
    """Центр кольца, внешние и внутренние полуоси (в координатах мастера)."""
    al = np.array(img.getchannel("A")) > 200
    ys, xs = np.where(al)
    cx = (np.percentile(xs, 1) + np.percentile(xs, 99)) / 2.0
    cy = (np.percentile(ys, 1) + np.percentile(ys, 99)) / 2.0
    a_out = (np.percentile(xs, 99) - np.percentile(xs, 1)) / 2.0
    b_out = (np.percentile(ys, 99) - np.percentile(ys, 1)) / 2.0
    row = al[int(cy)]
    xr = np.where(row[int(cx):])[0]
    yc = np.where(al[int(cy):, int(cx)])[0]
    a_in = float(xr.min()) if len(xr) else a_out * 0.7
    b_in = float(yc.min()) if len(yc) else b_out * 0.7
    return cx, cy, a_out, b_out, a_in, b_in


def bayer_quant(density, levels, rng_noise):
    """Плотность 0..1 → ступени 0..len(levels) с лёгким шумом границы (крупными кластерами, не сеткой)."""
    d = density + (rng_noise - 0.5) * 0.30
    out = np.zeros(density.shape, dtype=np.int32)
    for i, lv in enumerate(levels):
        out[d > lv] = i + 1
    return out


def back_frame(base_arr, t, noise, geo):
    """RGBA: кольцо (раскрытие, подскок плит, свет), ударная волна по земле, задний дым."""
    T = t * TL / FRAMES
    o = cur(OPEN, T)
    canvas = np.zeros((H, W, 4), dtype=np.float32)
    if o > 0.005:
        by = base_arr.shape[0]
        bx = base_arr.shape[1]
        ox = int(round(ANCHOR[0] - geo["cx"] * geo["k"] + (((t * 5) % 3) - 1 if 1 <= T <= 9 else 0)))
        oy = int(round(ANCHOR[1] - geo["cy"] * geo["k"] + cur(HEAVE, T)))
        x0, y0 = max(ox, 0), max(oy, 0)
        x1, y1 = min(ox + bx, W), min(oy + by, H)
        if x1 > x0 and y1 > y0:
            canvas[y0:y1, x0:x1] = base_arr[y0 - oy:y1 - oy, x0 - ox:x1 - ox]
        thr = o * 1.25
        n = noise
        keep = np.clip((thr - n) * 6.0, 0, 1)
        canvas[:, :, 3] *= keep
        rgb = canvas[:, :, :3]
        sat = np.clip((rgb.max(2) - rgb.min(2)) / 128.0, 0, 1)[:, :, None]
        k = 0.4 + 0.75 * cur(LIGHT, T)
        rgb = np.clip(rgb * (1 + (k - 1) * sat), 0, 255)
        if RACE == "sm":   # светлая земля и плиты — серые тона без насыщенности: к тёмному грунту, янтарь в трещинах остаётся
            pale = (1.0 - sat) * (canvas[:, :, :3].max(2, keepdims=True) > 90)
            rgb = rgb * (1 - pale * (1 - SM_RING_DARKEN))
        canvas[:, :, :3] = np.clip(rgb, 0, 255)
    # ударная волна: расширяющееся эллиптическое кольцо пыли по земле, кадры 3–9
    if 3 <= T <= 10:
        u = (T - 3) / 7.0
        yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
        nx = (xx - ANCHOR[0]) / (geo["a_px"] * 1.0)
        ny = (yy - ANCHOR[1]) / (geo["b_px"] * 1.0)
        rho = np.sqrt(nx * nx + ny * ny)
        s = 0.62 + 0.95 * u
        band = np.exp(-(((rho - s) / 0.11) ** 2))
        n2 = noise
        dens = band * (0.40 + 0.60 * n2) * (1 - u) ** 1.2 * 0.8
        lv = bayer_quant(dens, [0.14, 0.32, 0.55], n2)
        col = np.array(PAL.get("wave", PAL["ramp"]), dtype=np.float32)
        wave = np.zeros((H, W, 4), dtype=np.float32)
        for i, a in ((1, 60), (2, 100), (3, 140)):
            m = lv == i
            wave[m, :3] = col[i - 1]
            wave[m, 3] = a
        a_w = wave[:, :, 3:4] / 255.0
        a_c = canvas[:, :, 3:4] / 255.0
        oa = a_w + a_c * (1 - a_w)
        canvas[:, :, :3] = np.where(oa > 0, (wave[:, :, :3] * a_w + canvas[:, :, :3] * a_c * (1 - a_w)) / np.maximum(oa, 1e-6), 0)
        canvas[:, :, 3:4] = oa * 255
    return Image.fromarray(np.clip(canvas, 0, 255).astype(np.uint8))


def put(arr, x, y, color, a=255):
    xi, yi = int(x), int(y)
    if 0 <= xi < arr.shape[1] and 0 <= yi < arr.shape[0]:
        arr[yi, xi, :3] = color
        arr[yi, xi, 3] = max(arr[yi, xi, 3], a)


def front_frame(t, geo):
    """RGBA слоя front на сетке PIX: передняя пыль / языки варпа, крошка, искры."""
    Lw, Lh = W // PIX, H // PIX
    arr = np.zeros((Lh, Lw, 4), dtype=np.uint8)
    T = t * TL / FRAMES
    cxl, cyl = ANCHOR[0] / PIX, ANCHOR[1] / PIX
    am, bm = geo["a_mid"] / PIX, geo["b_mid"] / PIX
    e = cur(LIGHT, T)
    rng = np.random.RandomState(40 + (0 if RACE == "sm" else 100))
    # плотность пыли (SM) / дыма (Chaos): мягкие пятна вдоль кольца, поднимаются и расходятся
    dens = np.zeros((Lh, Lw), dtype=np.float32)
    yy, xx = np.mgrid[0:Lh, 0:Lw].astype(np.float32)
    noise = smooth_noise(9, (Lw, Lh))
    puffs = 34 if RACE == "sm" else 16
    for i in range(puffs):
        ang = rng.uniform(0, 2 * math.pi)
        if RACE == "sm" and rng.rand() < 0.65:
            ang = rng.uniform(0.15, math.pi - 0.15)           # больше пыли спереди (нижняя половина кольца)
        t0 = 2 + (i % 6)
        age = T - t0
        if age < 0 or age > 8:
            continue
        px = cxl + am * 1.05 * math.cos(ang) * (1.0 + 0.045 * age)
        py = cyl + bm * 1.05 * math.sin(ang) * (1.0 + 0.03 * age) - age * (1.2 if RACE == "sm" else 2.0)
        r = 4.5 + 1.2 * age
        a = (1.0 - age / 8.5) ** 1.4 * (0.75 if RACE == "sm" else 0.5)
        dens += np.exp(-(((xx - px) ** 2 + (yy - py) ** 2) / (2 * (r * 0.55) ** 2))) * a
    if T >= 12:   # остаточный дым на кольце
        res = [0.55, 0.30, 0.10, 0.0][min(int(T - 12), 3)]
        for i in range(5):
            ang = rng.uniform(0, 2 * math.pi)
            px, py = cxl + am * math.cos(ang), cyl + bm * math.sin(ang) - 4
            dens += np.exp(-(((xx - px) ** 2 + (yy - py) ** 2) / (2 * 5.0 ** 2))) * res * 0.5
    lv = bayer_quant(dens, [0.16, 0.34, 0.58], noise)
    for i in (1, 2, 3):
        m = lv == i
        arr[m, :3] = PAL["ramp"][i - 1]
        arr[m, 3] = PAL["alpha"][i - 1]
    # Хаос: багровый отсвет на земле вокруг кольца — нарастает к пику, гаснет вместе со светом (25.11.2026: «больше света на пике»)
    if RACE == "ch" and e > 0.05:
        a_o, b_o = geo["a_px"] / PIX, geo["b_px"] / PIX
        gx = (xx - cxl) / (a_o * 1.05)
        gy = (yy - cyl) / (b_o * 1.05)
        gr = np.sqrt(gx * gx + gy * gy)
        halo = np.exp(-(((gr - 1.0) / 0.38) ** 2)) * e * 120.0
        m = halo > 10
        arr[m, :3] = CH_GLOW
        arr[m, 3] = np.maximum(arr[m, 3], halo[m].astype(np.uint8))
    # Хаос: языки варпа из разлома по кольцу
    if RACE == "ch" and e > 0.3:
        for i in range(16):
            r2 = np.random.RandomState(300 + i)
            ang = r2.uniform(0, 2 * math.pi)
            bx, by = cxl + am * math.cos(ang), cyl + bm * math.sin(ang)
            hgt = r2.uniform(10, 26) * (0.5 + 0.8 * e)
            ph = r2.uniform(0, 6.28)
            for k in range(int(hgt)):
                u = k / max(hgt, 1.0)
                x = bx + 2.2 * math.sin(2 * math.pi * (u * 1.0 + T / TL * 2.0) + ph) * u
                y = by - k
                c = VIOLET_D if u < 0.45 else (VIOLET_M if u < 0.85 else VIOLET_L)
                put(arr, x, y, tuple(int(min(v * (0.6 + 0.6 * e), 255)) for v in c))
                if u < 0.5:
                    put(arr, x + 1, y, tuple(int(min(v * (0.5 + 0.55 * e), 255)) for v in c), 220)
    # крошка: плиты и камешки взлетают из кольца на кадрах 3–9 и падают
    rc = np.random.RandomState(7)
    for i in range(16):
        t0 = 3 + (i % 5)
        age = T - t0
        ang = rc.uniform(0, 2 * math.pi)
        px, py = cxl + am * math.cos(ang), cyl + bm * math.sin(ang)
        vx, vy = math.cos(ang) * rc.uniform(1.2, 3.2), rc.uniform(-4.5, -2.0)
        if age < 0 or age > 6:
            continue
        x, y = px + vx * age, py + vy * age + 0.7 * age * age
        c = PAL["chip"][i % 3]
        a = 255 if age < 5 else 140
        for dx in range(2):
            for dy in range(2 if i % 2 else 1):
                put(arr, x + dx, y + dy, c, a)
    # искры (медь / янтарь у Космодесанта, угли и варп у Хаоса)
    rs = np.random.RandomState(21)
    for i in range(20):
        t0 = 3 + (i % 6)
        age = T - t0
        ang = rs.uniform(0, 2 * math.pi)
        px, py = cxl + am * math.cos(ang), cyl + bm * math.sin(ang)
        vx, vy = rs.uniform(-1.5, 1.5), rs.uniform(-5.0, -2.5)
        if age < 0 or age > 5:
            continue
        x, y = px + vx * age, py + vy * age + 0.6 * age * age
        c = PAL["spark"][i % 3]
        a = int(255 * (1 - age / 6.0))
        put(arr, x, y, c, a)
    return Image.fromarray(arr).resize((W, H), Image.NEAREST)


def main():
    master = Image.open(os.path.join(SRC, "%s_%s.png" % (RACE, VARIANT))).convert("RGBA")
    cx, cy, a_out, b_out, a_in, b_in = ring_geometry(master)
    k = RING_W / (2 * a_out)
    geo = {"cx": cx, "cy": cy, "k": k, "a_px": a_out * k, "b_px": b_out * k, "a_mid": (a_out + a_in) / 2.0 * k, "b_mid": (b_out + b_in) / 2.0 * k}
    print("centre %.0f %.0f  outer %.0f x %.0f  inner %.0f x %.0f  k %.3f" % (cx, cy, a_out, b_out, a_in, b_in, k))
    small = master.resize((int(master.width * k), int(master.height * k)), Image.LANCZOS)
    base = np.array(small).astype(np.float32)
    noise = smooth_noise(5, (W, H))
    backs = [back_frame(base, t, noise, geo) for t in range(FRAMES)]
    fronts = [front_frame(t, geo) for t in range(FRAMES)]

    # общая палитра на кадры back (цвета без альфы), альфа плавная
    cols = Image.new("RGB", (W * 6, H * 4))
    for i, f in enumerate(backs):
        rgb = Image.new("RGB", f.size, (0, 0, 0))
        rgb.paste(f.convert("RGB"), mask=f.getchannel("A").point(lambda v: 255 if v > 30 else 0))
        cols.paste(rgb, ((i % 6) * W, (i // 6) * H))
    pal = cols.quantize(PALETTE_COLORS, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    os.makedirs(OUT, exist_ok=True)
    sheet_b = Image.new("RGBA", (W * FRAMES, H), (0, 0, 0, 0))
    sheet_f = Image.new("RGBA", (W * FRAMES, H), (0, 0, 0, 0))
    back_q = []
    for i, f in enumerate(backs):
        a = f.getchannel("A")
        q = f.convert("RGB").quantize(palette=pal, dither=Image.Dither.NONE).convert("RGB").convert("RGBA")
        q.putalpha(a)
        back_q.append(q)
        sheet_b.paste(q, (i * W, 0))
        sheet_f.paste(fronts[i], (i * W, 0))
    sheet_b.save(os.path.join(OUT, "%s_back.png" % RACE))
    sheet_f.save(os.path.join(OUT, "%s_front.png" % RACE))

    # превью: back, затем «окно» цитадели (серый прямоугольник-силуэт 184×190 над точкой), затем front — на тёмном грунте
    ground = (30, 22, 25) if RACE == "ch" else (40, 34, 38)
    prev = []
    for i in range(FRAMES):
        g = Image.new("RGBA", (W, H), ground + (255,))
        g.alpha_composite(back_q[i])
        sil = Image.new("RGBA", (184, 190), (70, 78, 98, 255) if RACE == "sm" else (60, 30, 36, 255))
        Ti = i * TL / FRAMES
        if Ti >= 4:
            al = min(1.0, (Ti - 3) / 4.0)
            sil.putalpha(int(255 * al))
            g.alpha_composite(sil, (int(ANCHOR[0] - 92), int(ANCHOR[1] - 190)))
        g.alpha_composite(fronts[i])
        prev.append(g.convert("RGB"))
    sheet = Image.new("RGB", (W * 6, H * 4))
    for i, p in enumerate(prev):
        sheet.paste(p, ((i % 6) * W, (i // 6) * H))
    sheet.resize((1800, 750), Image.LANCZOS).save(os.path.join(SRC, "preview_%s_%s.png" % (RACE, VARIANT)))
    prev[0].save(os.path.join(SRC, "preview_%s_%s.gif" % (RACE, VARIANT)), save_all=True, append_images=prev[1:], duration=56, loop=0)
    print("готово ->", OUT)


if __name__ == "__main__":
    main()
