"""Разлом варпа Хаоса (EFFECTS_NEEDED 11.1, ТЗ ART_TZ_EFFECTS_2026-11-24 п. 1, 25.11.2026): мастер Layer + движение кодом.

Мастер — открытый разлом (трещина-эллипс на земле, рваная кромка из камня, багровый край, фиолетовый провал) от
Layer: assets/source_sheets/chaos_rift_2026-11-25/rift_<вариант>.png. Фазы ТЗ (16 кадров, ~18 к/с):
  0–3   трещина проступает: мастер растёт из центра с рваным растворением, багровый свет
  4–8   провал раскрыт, пик света на 6–7 (отряд проявляется поверх — игра)
  9–12  края сходятся, свет гаснет
  13–15 остаточный дым и тлеющие искры на земле, последний кадр почти пуст
Два листа (кадр 384×384, точка привязки — центр трещины на земле (192, 288), кадры в одну строку слева направо):
  rift_back.png  — провал, трещина, верхушки (RGBA, обычное смешивание; тенденции кончиков качаются сдвигом)
  rift_front.png — рваные дуги варпа, искры, низкий дым (свет на ЧЁРНОМ фоне, ADD), рисуется «пикселями» ×PIX
Запуск (из корня проекта):
  python tools/chaos_rift_build.py A|B [папка мастеров]
Пишет в <папка мастеров>/out_<вариант>/ (rift_back.png, rift_front.png, превью preview_<вариант>.png / .gif). В игру кладёт
отдельная команда (после утверждения).
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

VARIANT = sys.argv[1] if len(sys.argv) > 1 else "B"
SRC = sys.argv[2] if len(sys.argv) > 2 else "assets/source_sheets/chaos_rift_2026-11-25"
OUT = os.path.join(SRC, "out_" + VARIANT)

FRAMES = 24                  # 25.11.2026: было 16 (18 к/с) — плавнее: 24 кадра при 27 к/с, та же длительность
TL = 16.0                    # опорная шкала фаз ТЗ: кадр t соответствует T = t · TL / FRAMES
SIZE = 384
ANCHOR = (192, 288)
ELL_W = 250.0                # ширина кромки разлома в кадре, px
PIX = 2                      # размер «пикселя» слоя front
PALETTE_COLORS = 72

# Раскрытие по кадрам (0 — нет, 1 — раскрыт); пик света — 6–7
OPEN = [0.14, 0.30, 0.48, 0.66, 0.84, 0.96, 1.0, 1.0, 0.94, 0.80, 0.60, 0.38, 0.18, 0.07, 0.025, 0.0]
LIGHT = [0.35, 0.50, 0.65, 0.78, 0.90, 0.97, 1.0, 1.0, 0.88, 0.70, 0.50, 0.32, 0.16, 0.07, 0.03, 0.0]

VIOLET_D, VIOLET_M, VIOLET_L, BONE = (122, 31, 162), (200, 80, 224), (230, 150, 245), (246, 200, 255)
EMBER_O, EMBER_Y = (222, 68, 30), (255, 150, 60)


def cur(curve, T):
    """Значение кривой (список по 16-кадровой шкале) в момент T с линейной интерполяцией."""
    x = min(max(T, 0.0), len(curve) - 1.0)
    i = int(x)
    j = min(i + 1, len(curve) - 1)
    return curve[i] + (curve[j] - curve[i]) * (x - i)


def smooth_noise(seed, size=SIZE):
    rng = np.random.RandomState(seed)
    out = np.zeros((size, size), dtype=np.float32)
    for grid, w in ((10, 0.55), (22, 0.3), (46, 0.15)):
        g = rng.rand(grid, grid).astype(np.float32)
        out += w * np.array(Image.fromarray((g * 255).astype(np.uint8)).resize((size, size), Image.BICUBIC)).astype(np.float32) / 255.0
    return out


def master_geometry(img):
    """Центр и полуоси кромки (по сплошным пикселям) в координатах мастера."""
    al = np.array(img.getchannel("A")) > 200
    ys, xs = np.where(al)
    cy0 = int(np.mean(np.where(al.any(1))[0]))
    void = al & (np.array(img.convert("RGB")).max(2) < 80)
    vy, vx = np.where(void)
    cx, cy = float(vx.mean()), float(vy.mean())
    row = np.where(al[int(cy)])[0]
    col = np.where(al[:, int(cx)])[0]
    return (row.min() + row.max()) / 2.0, (col.min() + col.max()) / 2.0, (row.max() - row.min()) / 2.0, (col.max() - col.min()) / 2.0


def back_frame(base, t, noise):
    """Кадр rift_back: мастер, масштаб и растворение по OPEN, качание верхушек, свет по LIGHT."""
    T = t * TL / FRAMES
    o = cur(OPEN, T)
    if o <= 0.005:
        return Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    s = 0.34 + 0.66 * math.sqrt(o)
    w, h = base.size
    sc = base.resize((max(int(w * s), 2), max(int(h * s), 2)), Image.BICUBIC)
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    canvas.alpha_composite(sc, (int(ANCHOR[0] - (sc.width * base_anchor[0])), int(ANCHOR[1] - (sc.height * base_anchor[1]))))
    arr = np.array(canvas).astype(np.float32)
    arr = animate_inside(arr, t, o, s)
    # качание верхушек (дым и усики над кромкой): сдвиг растёт вверх от центра трещины
    amp = 4.0 * math.sin(2 * math.pi * T / TL * 2.0) + 2.0 * math.sin(2 * math.pi * T / TL * 3.0 + 1.0)
    yy = np.arange(SIZE)
    shear = amp * np.clip((ANCHOR[1] - 20 - yy) / 120.0, 0, 1) ** 1.5
    for y in range(SIZE):
        d = int(round(shear[y]))
        if d:
            arr[y] = np.roll(arr[y], d, axis=0)
    # растворение по шуму: рваный край раскрытия и схлопывания
    thr = np.clip(o * 1.25, 0, 1.25)
    n = noise[: SIZE, : SIZE]
    keep = np.clip((thr - n) * 6.0, 0, 1)
    arr[:, :, 3] *= keep * min(1.0, o * 2.5)
    # свет: насыщенные пиксели (кромка и провал) ярче в пик и тусклее в начале и конце
    rgb = arr[:, :, :3]
    sat = np.clip((rgb.max(2) - rgb.min(2)) / 128.0, 0, 1)[:, :, None]
    k = 0.5 + 0.9 * cur(LIGHT, T)   # 25.11.2026: ярче на пике (было 0.45 + 0.65)
    arr[:, :, :3] = np.clip(rgb * (1 + (k - 1) * sat * 1.0), 0, 255)
    return Image.fromarray(arr.astype(np.uint8))


def bilinear(arr, xs, ys):
    """Выборка RGBA (float) по дробным координатам, края — прозрачные."""
    h, w = arr.shape[:2]
    x0 = np.floor(xs).astype(int)
    y0 = np.floor(ys).astype(int)
    fx = (xs - x0)[:, :, None]
    fy = (ys - y0)[:, :, None]
    out = np.zeros_like(arr)
    for dx, dy, wt in ((0, 0, (1 - fx) * (1 - fy)), (1, 0, fx * (1 - fy)), (0, 1, (1 - fx) * fy), (1, 1, fx * fy)):
        xi, yi = x0 + dx, y0 + dy
        ok = (xi >= 0) & (xi < w) & (yi >= 0) & (yi < h)
        vals = arr[np.clip(yi, 0, h - 1), np.clip(xi, 0, w - 1)]
        out += vals * wt * ok[:, :, None]
    return out


def animate_inside(arr, t, o, s):
    T = t * TL / FRAMES
    """Движение мастера: провал закручивается, кромка мерцает бегущей волной, фиолетовое свечение пульсирует, земля дрожит."""
    a_s = ELL_W / 2.0 * s
    b_s = rift_b_ratio * a_s
    yy, xx = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32)
    u = (xx - ANCHOR[0]) / a_s
    v = (yy - ANCHOR[1]) / b_s
    rho = np.sqrt(u * u + v * v)
    # 1. закрутка провала: сильнее у центра, к кромке затухает; направление не меняется в течение раскрытия
    w = np.clip(1.0 - rho / 0.80, 0.0, 1.0) ** 0.8
    phi = (0.20 * T) * w * (0.4 + 0.6 * min(o * 1.6, 1.0))
    c, sn = np.cos(phi), np.sin(phi)
    su = u * c - v * sn
    sv = u * sn + v * c
    src_x = ANCHOR[0] + su * a_s
    src_y = ANCHOR[1] + sv * b_s
    swirled = bilinear(arr, src_x, src_y)
    blend = np.clip((0.86 - rho) / 0.10, 0.0, 1.0)[:, :, None]   # внутри провала — закрученный, у кромки — исходный
    arr = arr * (1 - blend) + swirled * blend
    # 2. кромка (красно-оранжевый): бегущая волна яркости по углу + дрожь
    ang = np.arctan2(v, u)
    rgb = arr[:, :, :3] / 255.0
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    hot = np.clip((r - 0.45) * 3.0, 0, 1) * np.clip((0.55 - b) * 3.0, 0, 1) * (r > g * 1.2)
    wave = 1.0 + 0.30 * np.sin(ang * 3.0 - 2 * math.pi * T / TL * 2.0) + 0.12 * np.sin(ang * 7.0 + T * 1.3)
    arr[:, :, :3] = np.clip(arr[:, :, :3] * (1 + (wave - 1)[:, :, None] * hot[:, :, None]), 0, 255)
    # 3. фиолетовое свечение: пульс, чуть другой темп
    viol = np.clip((b - 0.30) * 3.0, 0, 1) * np.clip((b - r * 0.7), 0, 1) * (rho < 0.95)
    pulse = 1.0 + 0.22 * math.sin(2 * math.pi * T / TL * 3.0) + 0.08 * math.sin(T * 2.1)
    arr[:, :, :3] = np.clip(arr[:, :, :3] * (1 + (pulse - 1) * viol[:, :, None]), 0, 255)
    # 4. земля дрожит: камни кромки смещаются на пиксель, пока разлом раскрыт
    if 2 <= T <= 11:
        dx, dy = ((t * 5) % 3) - 1, ((t * 7) % 3) - 1
        shifted = np.roll(np.roll(arr, dx, axis=1), dy, axis=0)
        rim = np.clip((rho - 0.82) / 0.1, 0.0, 1.0)[:, :, None] * 0.55
        arr = arr * (1 - rim) + shifted * rim
    return arr


def jag_line(draw, pts, colors):
    for (col, wd) in colors:
        draw.line(pts, fill=col, width=wd)


def front_frame(t):
    """Кадр rift_front: дуги, искры, дым — свет на чёрном, по сетке PIX."""
    L = SIZE // PIX
    img = Image.new("RGB", (L, L), (0, 0, 0))
    d = ImageDraw.Draw(img)
    T = t * TL / FRAMES
    e = cur(LIGHT, T)
    cxl, cyl = ANCHOR[0] / PIX, ANCHOR[1] / PIX
    al, bl = ELL_W / 2.0 / PIX * 0.78, ELL_W / 2.0 / PIX * 0.78 * 0.42
    # отсвет на земле вокруг кромки (25.11.2026: «ярче»): ADD-слой, багровый снаружи, фиолетовый ближе к провалу — по LIGHT
    glow = np.zeros((L, L, 3), dtype=np.float32)
    gy0, gx0 = np.mgrid[0:L, 0:L].astype(np.float32)
    gnx = (gx0 - cxl) / (al * 1.3)
    gny = (gy0 - cyl) / (bl * 1.3)
    grho = np.sqrt(gnx * gnx + gny * gny)
    ge = e * min(cur(OPEN, T) * 1.4, 1.0)    # свет только пока разлом есть (в кадрах 0–1 и 13–15 его нет)
    outer = np.exp(-(((grho - 1.0) / 0.34) ** 2)) * ge
    inner = np.clip(1.0 - grho * 0.9, 0.0, 1.0) * ge
    glow += outer[:, :, None] * np.array([58, 12, 14], dtype=np.float32)
    glow += inner[:, :, None] * np.array([30, 9, 40], dtype=np.float32)
    glow = np.floor(glow / 14.0) * 14.0       # ступени вместо гладкого градиента (пиксель-арт, без «мыла»)
    # низкий дым: мягкие пятна, поднимаются от дальнего края
    smoke = glow.copy()
    rngs = np.random.RandomState(11)
    yy, xx = np.mgrid[0:L, 0:L]
    for i in range(6):
        ph = (T / TL + i / 6.0) % 1.0
        sx = cxl + rngs.uniform(-al * 0.8, al * 0.8) + 4 * math.sin(2 * math.pi * (ph + i))
        sy = cyl - bl * 0.6 - ph * 26
        r = 9 + 11 * ph
        amp = 0.30 * e * (1 - ph) * (ph < 0.98)
        g = np.exp(-(((xx - sx) ** 2 + (yy - sy) ** 2) / (2 * (r * 0.55) ** 2)))
        smoke += g[:, :, None] * np.array([46, 22, 58], dtype=np.float32) * amp
    # остаточный дым и угольки на земле (кадры 13–15)
    if T >= 12:
        res = [0.8, 0.5, 0.25, 0.12][min(int(T - 12), 3)]
        for i in range(5):
            sx = cxl + rngs.uniform(-al, al)
            sy = cyl + rngs.uniform(-bl, bl)
            g = np.exp(-(((xx - sx) ** 2 + (yy - sy) ** 2) / (2 * 5.0 ** 2)))
            smoke += g[:, :, None] * np.array([40, 16, 20], dtype=np.float32) * res * 0.5
    img = Image.fromarray(np.clip(smoke, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    # рваные дуги варпа: низкие дуги, перебрасываются через провал от кромки к кромке (не столбы); пара кадров на дугу —
    # мерцание; только пока разлом открыт, чтобы дуги не висели в пустоте
    n_arcs = int(round(0.8 + 3.0 * e)) if (e > 0.6 and cur(OPEN, T) > 0.6) else 0
    for i in range(n_arcs):
        rng = np.random.RandomState(1000 + (t // 3) * 17 + i * 31)
        a0 = rng.uniform(math.pi * 1.0, math.pi * 2.0) if rng.rand() < 0.65 else rng.uniform(0.0, math.pi)
        a1 = a0 + rng.choice([-1, 1]) * rng.uniform(0.7, 1.5)
        p0 = (cxl + al * math.cos(a0), cyl + bl * math.sin(a0))
        p1 = (cxl + al * math.cos(a1), cyl + bl * math.sin(a1))
        lift = rng.uniform(7.0, 13.0) * (0.7 + 0.5 * e)
        mid = ((p0[0] + p1[0]) / 2.0, (p0[1] + p1[1]) / 2.0 - lift)
        pts = []
        steps = 8
        for s_i in range(steps + 1):
            u = s_i / steps
            x = (1 - u) ** 2 * p0[0] + 2 * (1 - u) * u * mid[0] + u ** 2 * p1[0]
            y = (1 - u) ** 2 * p0[1] + 2 * (1 - u) * u * mid[1] + u ** 2 * p1[1]
            if 0 < s_i < steps:
                x += rng.uniform(-1.6, 1.6)
                y += rng.uniform(-1.6, 1.6)
            pts.append((x, y))
        dim = 0.55 + 0.45 * e
        outer = tuple(int(c * dim * 0.75) for c in VIOLET_D)
        core = tuple(int(c * dim) for c in VIOLET_M)
        d.line(pts, fill=outer, width=2)
        d.line(pts, fill=core, width=1)
        if rng.rand() < 0.2 * e:
            px, py = pts[len(pts) // 2]
            d.point((int(px), int(py)), fill=tuple(int(c * 0.85) for c in VIOLET_L))
    # усики варпа: извиваются над кромкой, низкие
    if e > 0.45 and cur(OPEN, T) > 0.5:
        for i in range(4):
            rngt = np.random.RandomState(300 + i)
            ang = rngt.uniform(math.pi * 1.05, math.pi * 1.95)
            bx, by = cxl + al * 0.9 * math.cos(ang), cyl + bl * 0.95 * math.sin(ang)
            hgt = rngt.uniform(9.0, 16.0) * (0.6 + 0.6 * e)
            ph = rngt.uniform(0, 6.28)
            amp = rngt.uniform(2.0, 3.6)
            pts = []
            for k in range(11):
                u = k / 10.0
                pts.append((bx + amp * math.sin(2 * math.pi * (u * 1.1 + T / TL * 2.0) + ph) * u, by - u * hgt))
            fade = 0.5 + 0.5 * e
            d.line(pts, fill=tuple(int(c * fade * 0.7) for c in VIOLET_D), width=2)
            d.line(pts, fill=tuple(int(c * fade * 0.8) for c in VIOLET_M), width=1)
            d.point((int(pts[-1][0]), int(pts[-1][1])), fill=tuple(int(c * fade * 0.8) for c in VIOLET_L))
    # искры: взлетают из провала на кадрах 3–11 и падают
    rngp = np.random.RandomState(77)
    for i in range(18):
        t0 = 3 + (i % 9)
        age = T - t0
        spx = cxl + rngp.uniform(-al * 0.9, al * 0.9)
        spy = cyl + rngp.uniform(-bl * 0.6, bl * 0.6)
        vx = rngp.uniform(-1.2, 1.2)
        vy = rngp.uniform(-4.6, -2.2)
        if age < 0 or age > 5:
            continue
        x = spx + vx * age
        y = spy + vy * age + 0.55 * age * age
        a = 1.0 - age / 6.0
        col = EMBER_Y if i % 3 else (VIOLET_L if i % 2 else EMBER_O)
        c = tuple(int(v * a * (0.4 + 0.6 * e)) for v in col)
        d.point((int(x), int(y)), fill=c)
        if i % 4 == 0:
            d.point((int(x) + 1, int(y)), fill=tuple(int(v * 0.6) for v in c))
    return img.resize((SIZE, SIZE), Image.NEAREST)


base_anchor = (0.5, 0.5)
rift_b_ratio = 0.375   # полуось b / a кромки (уточняется по мастеру)


def main():
    global base_anchor, rift_b_ratio
    master = Image.open(os.path.join(SRC, "rift_%s.png" % VARIANT)).convert("RGBA")
    mcx, mcy, ma, mb = master_geometry(master)
    k = ELL_W / (2 * ma)
    rift_b_ratio = mb / ma
    print("centre %.0f %.0f  a %.0f  b %.0f  scale %.3f" % (mcx, mcy, ma, mb, k))
    sm = master.resize((int(master.width * k), int(master.height * k)), Image.LANCZOS)
    base_anchor = (mcx / master.width, mcy / master.height)
    noise = smooth_noise(5)
    backs = [back_frame(sm, t, noise) for t in range(FRAMES)]
    fronts = [front_frame(t) for t in range(FRAMES)]

    # общая палитра для back (цвета без альфы), альфа сохраняется плавной — материал игры ступенит её сам
    mosaic = Image.new("RGB", (SIZE * 6, SIZE * 4))
    for i, f in enumerate(backs):
        rgb = Image.new("RGB", f.size, (0, 0, 0))
        rgb.paste(f.convert("RGB"), mask=f.getchannel("A").point(lambda v: 255 if v > 30 else 0))
        mosaic.paste(rgb, ((i % 6) * SIZE, (i // 6) * SIZE))
    pal = mosaic.quantize(PALETTE_COLORS, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    os.makedirs(OUT, exist_ok=True)
    back_q = []
    for f in backs:
        a = f.getchannel("A")
        q = f.convert("RGB").quantize(palette=pal, dither=Image.Dither.NONE).convert("RGB").convert("RGBA")
        q.putalpha(a)
        back_q.append(q)
    sheet_b = Image.new("RGBA", (SIZE * FRAMES, SIZE), (0, 0, 0, 0))
    sheet_f = Image.new("RGBA", (SIZE * FRAMES, SIZE), (0, 0, 0, 255))
    for i in range(FRAMES):
        sheet_b.paste(back_q[i], (i * SIZE, 0))
        sheet_f.paste(fronts[i].convert("RGBA"), (i * SIZE, 0))
    sheet_b.save(os.path.join(OUT, "rift_back.png"))
    sheet_f.save(os.path.join(OUT, "rift_front.png"))

    # превью: back обычным смешиванием, front — сложением, на тёмном грунте Хаоса
    prev = []
    for i in range(FRAMES):
        ground = np.zeros((SIZE, SIZE, 3), dtype=np.float32) + np.array([30, 22, 25], dtype=np.float32)
        bk = np.array(back_q[i]).astype(np.float32)
        a = bk[:, :, 3:4] / 255.0
        ground = ground * (1 - a) + bk[:, :, :3] * a
        ground = np.clip(ground + np.array(fronts[i]).astype(np.float32), 0, 255)
        prev.append(Image.fromarray(ground.astype(np.uint8)))
    sheet = Image.new("RGB", (SIZE * 6, SIZE * 4))
    for i, p in enumerate(prev):
        sheet.paste(p, ((i % 6) * SIZE, (i // 6) * SIZE))
    sheet.resize((1800, 1200), Image.LANCZOS).save(os.path.join(SRC, "preview_%s.png" % VARIANT))
    prev[0].save(os.path.join(SRC, "preview_%s.gif" % VARIANT), save_all=True, append_images=prev[1:], duration=37, loop=0)
    print("готово ->", OUT)


if __name__ == "__main__":
    main()
