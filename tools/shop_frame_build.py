"""Рамка панели магазина (UI_NEEDED 10.1, 25.11.2026): мастер Layer → 9-slice для ScaledNinePatch.

Мастер — квадратная рамка из ржавой латуни (углы с заклёпкой, прямые планки, прозрачная середина):
assets/source_sheets/shop_frame_2026-11-25/frame_<вариант>.png (1024×1024). Скрипт ужимает до SIZE (BOX), даёт общую палитру,
жёсткий альфа-край и пишет assets/ui/shop/frame.png с полями 9-slice (MARGIN px текстуры; на экране ×UITheme.UI_ART_SCALE).
Запуск (из корня проекта):
  python tools/shop_frame_build.py A|B [--install]
Без --install пишет в папку мастеров (frame_out_<вариант>.png + preview_<вариант>.png: рамка растянута на трёх размерах панели).
"""
import os
import sys

import numpy as np
from PIL import Image

VARIANT = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else "A"
INSTALL = "--install" in sys.argv
SRC = "assets/source_sheets/shop_frame_2026-11-25"
SIZE = 192
MARGIN = {"A": 24, "B": 21}[VARIANT]    # угловая скоба в px текстуры
PALETTE_COLORS = 40
ALPHA_CUT = 128


def nine_slice(tex: Image.Image, w: int, h: int, m: int, scale: float) -> Image.Image:
    ts = tex.width
    d = int(round(m * scale))
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    xs_src = [0, m, ts - m, ts]
    ys_src = [0, m, ts - m, ts]
    xs_dst = [0, d, w - d, w]
    ys_dst = [0, d, h - d, h]
    for j in range(3):
        for i in range(3):
            box = (xs_src[i], ys_src[j], xs_src[i + 1], ys_src[j + 1])
            dw, dh = xs_dst[i + 1] - xs_dst[i], ys_dst[j + 1] - ys_dst[j]
            if dw <= 0 or dh <= 0:
                continue
            part = tex.crop(box).resize((dw, dh), Image.NEAREST)
            out.alpha_composite(part, (xs_dst[i], ys_dst[j]))
    return out


def main():
    master = Image.open(os.path.join(SRC, "frame_%s.png" % VARIANT)).convert("RGBA")
    small = master.resize((SIZE, SIZE), Image.BOX)
    a = small.getchannel("A").point(lambda v: 255 if v > ALPHA_CUT else 0)
    rgb = Image.new("RGB", small.size, (0, 0, 0))
    rgb.paste(small.convert("RGB"), mask=a)
    pal = rgb.quantize(PALETTE_COLORS, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    q = small.convert("RGB").quantize(palette=pal, dither=Image.Dither.NONE).convert("RGB").convert("RGBA")
    q.putalpha(a)
    out = os.path.join("assets/ui/shop", "frame.png") if INSTALL else os.path.join(SRC, "frame_out_%s.png" % VARIANT)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    q.save(out)
    # превью: на экране ×0.5 от текстуры, показано ×2 — три размера панели магазина
    prev = Image.new("RGBA", (1500, 560), (30, 22, 25, 255))
    veil = Image.new("RGBA", (1, 1), (13, 9, 11, 200))
    x = 10
    for (pw, ph) in ((200, 130), (420, 260), (260, 520)):
        panel = Image.new("RGBA", (pw * 2, ph * 2), (13, 9, 11, 190))
        panel.alpha_composite(nine_slice(q, pw * 2, ph * 2, MARGIN, 1.0))
        prev.alpha_composite(panel, (x, 10))
        x += pw * 2 + 20
    prev.convert("RGB").save(os.path.join(SRC, "preview_%s.png" % VARIANT))
    print("готово:", out, "поля 9-slice", MARGIN)


if __name__ == "__main__":
    main()
