"""Круговая загрузка (UI_NEEDED 11.1, 25.11.2026): кольцо и фонарь — мастеры Layer, движение — кодом.

Кольцо ring_B (алхимический круг) вращается по часовой за цикл на 360°, фонарь lamp_A стоит в центре, пламя в нём
снимается с мастера и деформируется по кадрам (рост, покачивание, кончик), фоновое стекло подсвечивается пламенем,
над пламенем всплывают искры; по кольцу по часовой бежит огонёк с хвостом (2 оборота за цикл).
16 кадров, 256×256, прозрачный фон, общая палитра на все кадры, жёсткий альфа-край.

Запуск (из корня проекта):
  python tools/loading_spinner_build.py [папка мастеров] [папка кадров]
По умолчанию: assets/source_sheets/loading_spinner_2026-11-25 → assets/ui/loading/spin.
Пишет ещё превью (preview_sheet.png, preview.gif) в папку мастеров. Откат — удалить assets/ui/loading/spin.
"""
import math
import os
import sys

import numpy as np
from PIL import Image

SRC = sys.argv[1] if len(sys.argv) > 1 else "assets/source_sheets/loading_spinner_2026-11-25"
OUT = sys.argv[2] if len(sys.argv) > 2 else "assets/ui/loading/spin"
FRAMES = 16
CANVAS = 1024          # рабочий холст мастера
FINAL = 256            # кадр в игре
PALETTE_COLORS = 72
ALPHA_CUT = 140

RING_SAT = 0.80        # медь мастера ярче палитры игры (Palette.SHOP_FRAME) — глушим
RING_VAL = 0.90
EMBER_REVS = 2         # оборотов огонька за цикл
EMBER_TRAIL = 9        # точек в хвосте
EMBER_STEP_DEG = 6.0   # шаг хвоста
LAMP_FIT = 0.86        # высота фонаря от диаметра отверстия кольца

# Пламя в мастере фонаря: рамки двух огней и порог цвета (см. dbg_flame_mask2.png)
FLAME_BOXES = {"L": (395, 500, 495, 708), "R": (535, 500, 630, 708)}


def hsv_adjust(img: Image.Image, sat: float, val: float) -> Image.Image:
    rgba = img.convert("RGBA")
    a = rgba.getchannel("A")
    h, s, v = rgba.convert("RGB").convert("HSV").split()
    s = s.point(lambda x: min(255, int(x * sat)))
    v = v.point(lambda x: min(255, int(x * val)))
    out = Image.merge("HSV", (h, s, v)).convert("RGB").convert("RGBA")
    out.putalpha(a)
    return out


def alpha_bbox(img: Image.Image, cut: int = 20):
    a = np.array(img.getchannel("A"))
    ys, xs = np.where(a > cut)
    return xs.min(), ys.min(), xs.max(), ys.max()


def ring_geometry(ring: Image.Image):
    """Центр, радиус отверстия и радиус тела кольца (без зубцов)."""
    x0, y0, x1, y1 = alpha_bbox(ring)
    cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
    a = np.array(ring.getchannel("A")) > 20
    r_in = []
    r_body = []
    for deg in range(0, 360, 5):
        t = math.radians(deg)
        inner = None
        last = 0
        for r in range(0, 520):
            x, y = int(cx + r * math.cos(t)), int(cy + r * math.sin(t))
            if not (0 <= x < ring.width and 0 <= y < ring.height):
                break
            if a[y, x]:
                if inner is None:
                    inner = r
                last = r
        if inner is not None:
            r_in.append(inner)
            r_body.append(last)
    return cx, cy, float(np.median(r_in)), float(np.percentile(r_body, 20))


def fill_background(arr: np.ndarray, mask: np.ndarray) -> np.ndarray:
    """Закрасить маску цветом окружения (стекло фонаря за пламенем): растёт от известных пикселей."""
    out = arr.copy()
    known = ~mask
    for _ in range(80):
        if known.all():
            break
        acc = np.zeros_like(out[:, :, :3])
        cnt = np.zeros(mask.shape, dtype=float)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dy == 0 and dx == 0:
                    continue
                sh_k = np.roll(np.roll(known, dy, 0), dx, 1)
                sh_c = np.roll(np.roll(out[:, :, :3], dy, 0), dx, 1)
                acc += sh_c * sh_k[:, :, None]
                cnt += sh_k
        new = (~known) & (cnt > 0)
        out[:, :, :3][new] = acc[new] / cnt[new][:, None]
        known = known | new
    return out


def flame_mask(lamp_arr: np.ndarray) -> np.ndarray:
    rgb = lamp_arr[:, :, :3] / 255.0
    alpha = lamp_arr[:, :, 3]
    mx, mn = rgb.max(2), rgb.min(2)
    sat = (mx - mn) / np.maximum(mx, 1e-6)
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    cand = (alpha > 200) & (r > 0.7) & (r > g) & (g > b) & (((mx > 0.78) & (sat > 0.55)) | (sat > 0.78))
    mask = np.zeros_like(cand)
    for x0, y0, x1, y1 in FLAME_BOXES.values():
        mask[y0:y1, x0:x1] = cand[y0:y1, x0:x1]
    return mask


class Flame:
    """Пламя из мастера: RGBA-вырезка и опорная точка (низ, центр) — деформируется по кадрам."""

    def __init__(self, lamp_arr, mask, box, phase):
        x0, y0, x1, y1 = box
        sub = mask[y0:y1, x0:x1]
        ys, xs = np.where(sub)
        self.x0, self.y0 = x0 + xs.min(), y0 + ys.min()
        self.x1, self.y1 = x0 + xs.max() + 1, y0 + ys.max() + 1
        patch = lamp_arr[self.y0:self.y1, self.x0:self.x1].copy()
        m = mask[self.y0:self.y1, self.x0:self.x1]
        patch[:, :, 3] = np.where(m, 255, 0)
        self.patch = patch
        bottom = np.where(m[-12:].any(0))[0]
        self.base_x = self.x0 + (bottom.mean() if len(bottom) else m.shape[1] / 2)
        self.base_y = self.y1
        self.h = self.y1 - self.y0
        self.phase = phase

    def render(self, t: int):
        """Кадр пламени: слой RGBA того же размера, что холст лампы (в координатах лампы)."""
        n = FRAMES
        ph = self.phase
        w = 2 * math.pi * t / n
        sy = 1 + 0.10 * math.sin(w + ph) + 0.05 * math.sin(3 * w + 2 * ph)
        sway = 7.0 * math.sin(2 * w + ph + 1.0)
        flick = 6.0 * math.sin(5 * w + ph)
        bright = 1.0 + 0.07 * math.sin(2 * w + ph) + 0.04 * math.sin(3 * w)
        out = np.zeros((CANVAS, CANVAS, 4), dtype=np.float32)
        ph_h, pw = self.patch.shape[:2]
        # обратное отображение: для каждого выходного пикселя вокруг опорной точки — пиксель вырезки
        top = int(self.base_y - ph_h * sy * 1.2)
        for y in range(max(top, 0), int(self.base_y) + 1):
            hgt = (self.base_y - y) / max(sy, 1e-3)          # высота над основанием в исходных пикселях
            sy_src = ph_h - hgt                                # строка вырезки
            if sy_src < 0 or sy_src >= ph_h:
                continue
            rel = hgt / max(ph_h, 1)
            dx = sway * rel + flick * rel * rel
            row = self.patch[int(sy_src)]
            xs_src = np.arange(pw)
            xs_out = (xs_src + self.x0 + dx).astype(int)
            ok = (xs_out >= 0) & (xs_out < CANVAS) & (row[:, 3] > 0)
            if not ok.any():
                continue
            col = row[ok, :3] * bright
            out[y, xs_out[ok], :3] = col
            out[y, xs_out[ok], 3] = 255
        return out, sy


def glow_field(shape, centers, strength):
    yy, xx = np.mgrid[0:shape[0], 0:shape[1]]
    g = np.zeros(shape, dtype=np.float32)
    for (cx, cy), s in zip(centers, strength):
        d2 = (xx - cx) ** 2 + (yy - cy) ** 2
        g += s * np.exp(-d2 / (2 * 95.0 ** 2))
    return g


def paste(dst: np.ndarray, src: np.ndarray):
    """src поверх dst (straight alpha, float)."""
    sa = src[:, :, 3:4] / 255.0
    da = dst[:, :, 3:4] / 255.0
    oa = sa + da * (1 - sa)
    col = np.where(oa > 0, (src[:, :, :3] * sa + dst[:, :, :3] * da * (1 - sa)) / np.maximum(oa, 1e-6), 0)
    dst[:, :, :3] = col
    dst[:, :, 3:4] = oa * 255.0


def disc(canvas, cx, cy, r, color, alpha):
    yy, xx = np.ogrid[max(int(cy - r - 2), 0):min(int(cy + r + 3), CANVAS), max(int(cx - r - 2), 0):min(int(cx + r + 3), CANVAS)]
    y0 = max(int(cy - r - 2), 0)
    x0 = max(int(cx - r - 2), 0)
    d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
    m = d <= r
    layer = np.zeros((CANVAS, CANVAS, 4), dtype=np.float32)
    sub = layer[y0:y0 + m.shape[0], x0:x0 + m.shape[1]]
    sub[m, :3] = color
    sub[m, 3] = alpha * 255
    paste(canvas, layer)


def main():
    ring = hsv_adjust(Image.open(os.path.join(SRC, "ring_B.png")).convert("RGBA"), RING_SAT, RING_VAL)
    lamp = Image.open(os.path.join(SRC, "lamp_A.png")).convert("RGBA")
    cx, cy, r_in, r_body = ring_geometry(ring)
    print("ring centre %.1f %.1f  r_in %.0f  r_body %.0f" % (cx, cy, r_in, r_body))

    # Фонарь: подгонка по высоте отверстия, центр — центр кольца. Пламя считаем в координатах МАСТЕРА фонаря
    lb = alpha_bbox(lamp)
    lamp_crop = lamp.crop((lb[0], lb[1], lb[2] + 1, lb[3] + 1))
    k = LAMP_FIT * 2 * r_in / lamp_crop.height
    lamp_small_size = (int(lamp_crop.width * k), int(lamp_crop.height * k))
    print("lamp scale %.3f -> %s" % (k, lamp_small_size))
    # маска пламени — на полном мастере; затем всё переносится в координаты лампы вместе с масштабом
    lamp_arr = np.array(lamp).astype(np.float32)
    mask = flame_mask(lamp_arr)
    clean = fill_background(lamp_arr, mask)
    clean[:, :, 3] = lamp_arr[:, :, 3]
    flames = [Flame(lamp_arr, mask, FLAME_BOXES["L"], 0.0), Flame(lamp_arr, mask, FLAME_BOXES["R"], 2.3)]

    # Холст мастера лампы ↔ холст кадра: масштаб k вокруг центра bbox лампы, центр — в центре отверстия
    lcx, lcy = (lb[0] + lb[2]) / 2.0, (lb[1] + lb[3]) / 2.0
    ox, oy = cx - lcx * k, cy - lcy * k          # смещение: точка мастера (x, y) → (ox + x*k, oy + y*k)

    ring_arr_img = ring
    frames = []
    glow_centers = [((f.x0 + f.x1) / 2.0, (f.y0 + f.y1) / 2.0) for f in flames]
    for t in range(FRAMES):
        canvas = np.zeros((CANVAS, CANVAS, 4), dtype=np.float32)
        # кольцо — по часовой (PIL rotate: положительный угол — против часовой)
        rot = ring_arr_img.rotate(-360.0 * t / FRAMES, resample=Image.BICUBIC, center=(cx, cy))
        paste(canvas, np.array(rot).astype(np.float32))

        # лампа в координатах мастера: чистое стекло + пламя + свет + искры, потом масштаб
        lamp_layer = clean.copy()
        flame_layers = []
        sys_ = []
        for f in flames:
            fl, sy = f.render(t)
            flame_layers.append(fl)
            sys_.append(sy)
        gl = glow_field(lamp_layer.shape[:2], glow_centers, [0.07 + 0.05 * (s - 1.0) / 0.15 for s in sys_])
        warm = np.array([255.0, 150.0, 60.0], dtype=np.float32)
        inside = (lamp_layer[:, :, 3] > 200)[:, :, None]
        lamp_layer[:, :, :3] = np.where(inside, lamp_layer[:, :, :3] + (warm - lamp_layer[:, :, :3]) * gl[:, :, None], lamp_layer[:, :, :3])
        for fl in flame_layers:
            paste(lamp_layer, fl)
        # искры над пламенем: 3 на огонь, поднимаются и гаснут, цикл замкнут
        rng = np.random.RandomState(5)
        for f in flames:
            for s in range(3):
                phase = (t / FRAMES + s / 3.0 + rng.rand() * 0.2) % 1.0
                sx = (f.x0 + f.x1) / 2.0 + rng.uniform(-25, 25) + 10 * math.sin(2 * math.pi * (phase + s))
                sy_ = f.y0 + 6 - phase * 120
                alpha = (1 - phase) * 0.9 if phase < 0.95 else 0
                color = (255, 212, 102) if s % 2 == 0 else (224, 138, 40)
                disc(lamp_layer, sx, sy_, 6.5 - 3 * phase, color, alpha)
        lamp_img = Image.fromarray(np.clip(lamp_layer, 0, 255).astype(np.uint8), ).crop((lb[0], lb[1], lb[2] + 1, lb[3] + 1))
        lamp_small = lamp_img.resize(lamp_small_size, Image.LANCZOS)
        placed = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
        placed.alpha_composite(lamp_small, (int(round(cx - lamp_small_size[0] / 2.0)), int(round(cy - lamp_small_size[1] / 2.0))))
        paste(canvas, np.array(placed).astype(np.float32))

        # огонёк по кольцу: по часовой, быстрее кольца, хвост позади
        r_mid = (r_in + r_body) / 2.0
        head = 360.0 * EMBER_REVS * t / FRAMES - 90.0
        for i in range(EMBER_TRAIL - 1, -1, -1):
            ang = math.radians(head - i * EMBER_STEP_DEG)
            ex, ey = cx + r_mid * math.cos(ang), cy + r_mid * math.sin(ang)
            fade = 1.0 - i / EMBER_TRAIL
            if i == 0:
                disc(canvas, ex, ey, 40, (150, 60, 18), 0.35)
                disc(canvas, ex, ey, 27, (224, 138, 40), 0.80)
                disc(canvas, ex, ey, 15, (255, 212, 102), 1.0)
            else:
                disc(canvas, ex, ey, 6 + 16 * fade, (224, 138, 40), 0.25 + 0.6 * fade)
                disc(canvas, ex, ey, 3 + 8 * fade, (255, 212, 102), 0.3 + 0.6 * fade)
        frames.append(Image.fromarray(np.clip(canvas, 0, 255).astype(np.uint8)))

    # финал: 1024 → 256 (усреднение), общая палитра, жёсткий альфа-край
    small = [f.resize((FINAL, FINAL), Image.BOX) for f in frames]
    mosaic = Image.new("RGB", (FINAL * 4, FINAL * 4))
    for i, f in enumerate(small):
        rgb = Image.new("RGB", f.size, (0, 0, 0))
        rgb.paste(f.convert("RGB"), mask=f.getchannel("A").point(lambda v: 255 if v > ALPHA_CUT else 0))
        mosaic.paste(rgb, ((i % 4) * FINAL, (i // 4) * FINAL))
    pal = mosaic.quantize(PALETTE_COLORS, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    os.makedirs(OUT, exist_ok=True)
    final = []
    for i, f in enumerate(small):
        a = f.getchannel("A").point(lambda v: 255 if v > ALPHA_CUT else 0)
        q = f.convert("RGB").quantize(palette=pal, dither=Image.Dither.NONE).convert("RGB").convert("RGBA")
        q.putalpha(a)
        q.save(os.path.join(OUT, "%d.png" % i))
        final.append(q)

    # превью: лист 4×4 на тёмном фоне и GIF
    sheet = Image.new("RGBA", (FINAL * 4, FINAL * 4), (30, 22, 25, 255))
    for i, f in enumerate(final):
        sheet.alpha_composite(f, ((i % 4) * FINAL, (i // 4) * FINAL))
    sheet.convert("RGB").save(os.path.join(SRC, "preview_sheet.png"))
    gif = []
    for f in final:
        bg = Image.new("RGBA", f.size, (30, 22, 25, 255))
        bg.alpha_composite(f)
        gif.append(bg.convert("RGB"))
    gif[0].save(os.path.join(SRC, "preview.gif"), save_all=True, append_images=gif[1:], duration=125, loop=0)
    print("готово: %d кадров %dx%d -> %s" % (len(final), FINAL, FINAL, OUT))


if __name__ == "__main__":
    main()
