"""Вращающаяся монета (UI_NEEDED 10.4, 25.11.2026): аверс (череп) и реверс (фонарь) — мастер Layer, оборот — кодом.

Лист мастера 1536×768: слева аверс, справа реверс одной монеты (assets/source_sheets/coin_spin_2026-11-25/coin_<вариант>.png).
Оборот вокруг вертикальной оси: ширина лица = диаметр × |cos θ|, лицо — аверс при cos > 0, реверс при cos < 0 (реверс
не зеркалится), боковая грань — толщина × |sin θ| с рифлением и светотенью цилиндра, лицо темнеет к ребру.
Кадры FRAMES (8) × SIZE (96), монета ~78 px, поля ≥ 9 px, общая палитра на все кадры, жёсткий альфа-край.

Запуск (из корня проекта):
  python tools/coin_spin_build.py A|B [папка мастеров] [папка кадров]
По умолчанию кадры — <папка мастеров>/frames_<вариант>; в игру (assets/ui/hud/coin_spin) кладёт отдельная команда
`python tools/coin_spin_build.py A --install`. Превью (strip_<вариант>.png, spin_<вариант>.gif) — в папке мастеров.
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

args = [a for a in sys.argv[1:] if not a.startswith("--")]
VARIANT = args[0] if args else "A"
SRC = args[1] if len(args) > 1 else "assets/source_sheets/coin_spin_2026-11-25"
OUT = args[2] if len(args) > 2 else os.path.join(SRC, "frames_" + VARIANT)
INSTALL = "--install" in sys.argv
GAME_DIR = "assets/ui/hud/coin_spin"

FRAMES = 8
SIZE = 96
DIAMETER = 78          # монета в кадре, px
SS = 8                 # суперсэмплинг рабочего холста
THICK = 7.0            # толщина монеты, px кадра
PALETTE_COLORS = 56
ALPHA_CUT = 140
EDGE_LIGHT = (196, 142, 72)
EDGE_MID = (138, 90, 44)
EDGE_DARK = (58, 36, 20)


def coin_faces(sheet: Image.Image):
    """Две монеты листа: квадратная вырезка по bbox альфы каждой половины."""
    a = np.array(sheet.getchannel("A"))
    faces = []
    for half in (0, 1):
        sub = a[:, half * 768:(half + 1) * 768]
        ys, xs = np.where(sub > 20)
        x0, x1, y0, y1 = xs.min() + half * 768, xs.max() + 1 + half * 768, ys.min(), ys.max() + 1
        side = max(x1 - x0, y1 - y0)
        cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
        box = (int(cx - side / 2), int(cy - side / 2), int(cx - side / 2) + side, int(cy - side / 2) + side)
        faces.append(sheet.crop(box).resize((DIAMETER * SS, DIAMETER * SS), Image.LANCZOS))
    return faces


def shade(img: Image.Image, k: float) -> Image.Image:
    arr = np.array(img).astype(np.float32)
    arr[:, :, :3] *= k
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


def lerp(c0, c1, t):
    return tuple(int(c0[i] + (c1[i] - c0[i]) * t) for i in range(3))


def render_frame(t: int, obverse: Image.Image, reverse: Image.Image) -> Image.Image:
    theta = 2 * math.pi * t / FRAMES
    c, s = math.cos(theta), math.sin(theta)
    big = SIZE * SS
    d = DIAMETER * SS
    canvas = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    face_w = max(int(round(d * abs(c))), 0)
    edge_w = int(round(THICK * SS * abs(s)))
    total = face_w + edge_w
    cx = big // 2
    left = cx - total // 2
    edge_right = s > 0           # в первой половине оборота видна правая грань, во второй — левая
    face_x = left if edge_right else left + edge_w
    edge_x = left + face_w if edge_right else left
    cy0 = (big - d) // 2

    # боковая грань = выдавливание овала лица на edge_w: овал, сдвинутый на edge_w, и прямоугольник между центрами
    if edge_w > 0:
        sgn = 1 if edge_right else -1
        face_cx = face_x + face_w / 2.0
        shift_cx = face_cx + sgn * edge_w
        mask = Image.new("L", (big, big), 0)
        md = ImageDraw.Draw(mask)
        half_w = max(face_w / 2.0, edge_w / 2.0 if face_w == 0 else 0.0)
        md.ellipse([shift_cx - half_w, cy0, shift_cx + half_w, cy0 + d], fill=255)
        md.rectangle([min(face_cx, shift_cx), cy0, max(face_cx, shift_cx), cy0 + d], fill=255)
        if face_w == 0:   # ребро анфас: скруглённые торцы
            md.rounded_rectangle([cx - edge_w / 2.0, cy0, cx + edge_w / 2.0, cy0 + d], radius=edge_w / 2.0, fill=255)
        x_lo, x_hi = (face_cx, shift_cx) if sgn > 0 else (shift_cx, face_cx)
        arr = np.zeros((big, big, 4), dtype=np.uint8)
        m = np.array(mask) > 0
        xs = np.arange(big)
        # цилиндрическая светотень поперёк полосы: свет сверху-слева
        u = np.clip((xs - x_lo) / max(x_hi - x_lo + half_w, 1.0), 0.0, 1.0)
        for ci in range(3):
            col_lo = np.array([EDGE_LIGHT[ci]], dtype=np.float32)
            col = EDGE_LIGHT[ci] + (EDGE_DARK[ci] - EDGE_LIGHT[ci]) * u
            col = np.where((u > 0.3) & (u < 0.7), col * 0.5 + EDGE_MID[ci] * 0.5, col)
            arr[:, :, ci] = np.where(m, col[None, :], 0).astype(np.uint8)
        arr[:, :, 3] = np.where(m, 255, 0)
        edge_img = Image.fromarray(arr)
        # рифление: тёмные поперечные штрихи вдоль окружности
        dd = ImageDraw.Draw(edge_img)
        for y in range(int(cy0 + 14), int(cy0 + d - 10), 18):
            dd.line([(min(face_cx, shift_cx) - half_w, y), (max(face_cx, shift_cx) + half_w, y)], fill=EDGE_DARK + (0,), width=3)
        a_arr = np.array(edge_img.getchannel("A"))
        rgb = np.array(edge_img.convert("RGB")).astype(np.int32)
        stroke = np.zeros((big, big), dtype=bool)
        for y in range(int(cy0 + 14), int(cy0 + d - 10), 18):
            stroke[y - 1:y + 2, :] = True
        rgb[stroke & m] = (rgb[stroke & m] * 0.62).astype(np.int32)
        edge_img = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8)).convert("RGBA")
        edge_img.putalpha(Image.fromarray(a_arr))
        canvas.alpha_composite(edge_img)

    # лицо: аверс при cos > 0, реверс при cos < 0, темнеет к ребру
    if face_w > 0:
        src = obverse if c > 0 else reverse
        face = src.resize((face_w, d), Image.LANCZOS)
        face = shade(face, 0.62 + 0.38 * abs(c))
        canvas.alpha_composite(face, (face_x, cy0))
    return canvas.resize((SIZE, SIZE), Image.BOX)


def main():
    sheet = Image.open(os.path.join(SRC, "coin_%s.png" % VARIANT)).convert("RGBA")
    obverse, reverse = coin_faces(sheet)
    frames = [render_frame(t, obverse, reverse) for t in range(FRAMES)]
    mosaic = Image.new("RGB", (SIZE * FRAMES, SIZE))
    for i, f in enumerate(frames):
        rgb = Image.new("RGB", f.size, (0, 0, 0))
        rgb.paste(f.convert("RGB"), mask=f.getchannel("A").point(lambda v: 255 if v > ALPHA_CUT else 0))
        mosaic.paste(rgb, (i * SIZE, 0))
    pal = mosaic.quantize(PALETTE_COLORS, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    out_dir = GAME_DIR if INSTALL else OUT
    os.makedirs(out_dir, exist_ok=True)
    final = []
    for i, f in enumerate(frames):
        a = f.getchannel("A").point(lambda v: 255 if v > ALPHA_CUT else 0)
        q = f.convert("RGB").quantize(palette=pal, dither=Image.Dither.NONE).convert("RGB").convert("RGBA")
        q.putalpha(a)
        q.save(os.path.join(out_dir, "%d.png" % i))
        final.append(q)
    strip = Image.new("RGBA", (SIZE * FRAMES, SIZE), (30, 22, 25, 255))
    for i, f in enumerate(final):
        strip.alpha_composite(f, (i * SIZE, 0))
    big = strip.convert("RGB").resize((SIZE * FRAMES * 2, SIZE * 2), Image.NEAREST)
    big.save(os.path.join(SRC, "strip_%s.png" % VARIANT))
    gif = []
    for f in final:
        bg = Image.new("RGBA", f.size, (30, 22, 25, 255))
        bg.alpha_composite(f)
        gif.append(bg.convert("RGB").resize((SIZE * 3, SIZE * 3), Image.NEAREST))
    gif[0].save(os.path.join(SRC, "spin_%s.gif" % VARIANT), save_all=True, append_images=gif[1:], duration=85, loop=0)
    print("готово: %d кадров %dx%d -> %s" % (len(final), SIZE, SIZE, out_dir))


if __name__ == "__main__":
    main()
