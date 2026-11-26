"""Рамка кнопки-значка (UI_NEEDED 10.3, 25.11.2026): мастер Layer → 9-slice normal / hover для значков шапки магазина.

Мастер — квадратная латунная плита со срезанными углами и тёмной вставкой (assets/source_sheets/icon_button_2026-11-25/btn_<вариант>.png,
1024×1024). Скрипт обрезает по альфе, ужимает до SIZE (BOX), общая палитра на оба состояния, жёсткий альфа-край; hover — латунь ярче,
вставка чуть теплее. Пишет assets/ui/shop/icon_button_normal.png и icon_button_hover.png (поля 9-slice MARGIN px текстуры, на экране
×UITheme.UI_ART_SCALE). Запуск (из корня проекта):
  python tools/icon_button_build.py A|B [--install]
Без --install — в папку мастеров (btn_out_<вариант>_<состояние>.png и preview_<вариант>.png: плита растянута на трёх размерах кнопки).
"""
import os
import sys

import numpy as np
from PIL import Image

VARIANT = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else "B"
INSTALL = "--install" in sys.argv
SRC = "assets/source_sheets/icon_button_2026-11-25"
SIZE = 72
MARGIN = 16
PALETTE_COLORS = 40
ALPHA_CUT = 128


def hover_of(img: Image.Image) -> Image.Image:
    arr = np.array(img).astype(np.float32)
    rgb = arr[:, :, :3]
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    brass = (r > g * 1.12) & (r > 70)           # латунь и ржавчина рамки
    plate = (rgb.max(2) < 60)                    # тёмная вставка
    rgb[brass] = np.clip(rgb[brass] * 1.22 + np.array([8, 4, 0]), 0, 255)
    rgb[plate] = np.clip(rgb[plate] + np.array([20, 11, 6]), 0, 255)   # вставка чуть теплее
    arr[:, :, :3] = rgb
    return Image.fromarray(arr.astype(np.uint8))


def nine_slice(tex: Image.Image, w: int, h: int, m: int, scale: float) -> Image.Image:
    ts = tex.width
    d = int(round(m * scale))
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    xs_s = [0, m, ts - m, ts]
    xs_d = [0, d, w - d, w]
    for j in range(3):
        for i in range(3):
            dw, dh = xs_d[i + 1] - xs_d[i], xs_d[j + 1] - xs_d[j]
            if dw <= 0 or dh <= 0:
                continue
            part = tex.crop((xs_s[i], xs_s[j], xs_s[i + 1], xs_s[j + 1])).resize((dw, dh), Image.NEAREST)
            out.alpha_composite(part, (xs_d[i], xs_d[j]))
    return out


def main():
    master = Image.open(os.path.join(SRC, "btn_%s.png" % VARIANT)).convert("RGBA")
    a = np.array(master.getchannel("A")) > 20
    ys, xs = np.where(a)
    box = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
    side = max(box[2] - box[0], box[3] - box[1])
    cx, cy = (box[0] + box[2]) / 2.0, (box[1] + box[3]) / 2.0
    sq = master.crop((int(cx - side / 2), int(cy - side / 2), int(cx - side / 2) + side, int(cy - side / 2) + side))
    normal = sq.resize((SIZE, SIZE), Image.BOX)
    alpha = normal.getchannel("A").point(lambda v: 255 if v > ALPHA_CUT else 0)
    hover = hover_of(normal)
    # общая палитра на оба состояния
    both = Image.new("RGB", (SIZE * 2, SIZE))
    for i, im in enumerate((normal, hover)):
        rgb = Image.new("RGB", im.size, (0, 0, 0))
        rgb.paste(im.convert("RGB"), mask=alpha)
        both.paste(rgb, (i * SIZE, 0))
    pal = both.quantize(PALETTE_COLORS, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    outs = {}
    for name, im in (("normal", normal), ("hover", hover)):
        q = im.convert("RGB").quantize(palette=pal, dither=Image.Dither.NONE).convert("RGB").convert("RGBA")
        q.putalpha(alpha)
        outs[name] = q
        if INSTALL:
            path = os.path.join("assets/ui/shop", "icon_button_%s.png" % name)
        else:
            path = os.path.join(SRC, "btn_out_%s_%s.png" % (VARIANT, name))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        q.save(path)
    prev = Image.new("RGBA", (1100, 320), (30, 22, 25, 255))
    x = 10
    for state in ("normal", "hover"):
        for (pw, ph) in ((36, 36), (44, 44), (120, 40)):
            panel = nine_slice(outs[state], pw * 4, ph * 4, MARGIN, 2.0)   # ×4 зум экрана, art_scale 0.5 → поля ×2 в зуме
            prev.alpha_composite(panel, (x, 10 if state == "normal" else 170))
            x += pw * 4 + 14
        x = 10
    prev.convert("RGB").save(os.path.join(SRC, "preview_%s.png" % VARIANT))
    print("готово, поля 9-slice", MARGIN, "->", "assets/ui/shop" if INSTALL else SRC)


if __name__ == "__main__":
    main()
