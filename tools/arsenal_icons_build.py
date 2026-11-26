"""Значки Арсенала без аквилы (25.11.2026, решение пользователя: «переделать арсенал, там остались следы warhammer»).

Мастер — лист Layer с пятью значками (assets/source_sheets/arsenal_icons_2026-11-25/sheet_<вариант>.png: сверху слева направо сундук
резервов, стена с кругом-оберегом, седоусый ветеран; снизу грамота Ревизской палаты и венок Славы с фонарём). Значки находятся сами
(связные области альфы), режутся по квадрату, ужимаются до SIZE (BOX), общая палитра, жёсткий альфа-край. Запуск (из корня проекта):
  python tools/arsenal_icons_build.py A|B [--install]
--elixir A|B — значок «veterans» (пассивка «Эликсир Ведьминой кухни», Гёте, «Фауст» I) берётся из отдельного мастера elixir_<вариант>.png
(решение пользователя 25.11.2026: вместо портрета седоусого — образ из Гёте), а не из листа.
Без --install — в папку мастеров (out_<вариант>/*.png и preview_<вариант>.png). С --install — assets/ui/passives/{reserves,walls,veterans,
munitorum}.png и assets/ui/hud/glory.png (прежние — assets/source_sheets/arsenal_icons_old_2026-11-25).
"""
import os
import sys

import numpy as np
from PIL import Image

VARIANT = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else "A"
INSTALL = "--install" in sys.argv
SRC = "assets/source_sheets/arsenal_icons_2026-11-25"
SIZE = 96
PAD = 0.04
PALETTE_COLORS = 56
ALPHA_CUT = 128
ORDER = ["reserves", "walls", "veterans", "munitorum", "glory"]   # строки сверху вниз, слева направо
TARGETS = {"reserves": "passives", "walls": "passives", "veterans": "passives", "munitorum": "passives", "glory": "hud"}


def components(img):
    a = np.array(img.getchannel("A")) > 30
    h4, w4 = a.shape[0] // 4, a.shape[1] // 4
    g = a[:h4 * 4, :w4 * 4].reshape(h4, 4, w4, 4).any(axis=(1, 3))
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
        if len(xs) < 300:
            continue
        out.append((xs.min() * 4, ys.min() * 4, (xs.max() + 1) * 4, (ys.max() + 1) * 4))
    return out


def square(img, box):
    x0, y0, x1, y1 = box
    side = int(max(x1 - x0, y1 - y0) * (1 + PAD * 2))
    cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
    left, top = int(cx - side / 2), int(cy - side / 2)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.alpha_composite(img.crop((max(left, 0), max(top, 0), min(left + side, img.width), min(top + side, img.height))),
                           (max(-left, 0), max(-top, 0)))
    return canvas.resize((SIZE, SIZE), Image.BOX)


def main():
    sheet = Image.open(os.path.join(SRC, "sheet_%s.png" % VARIANT)).convert("RGBA")
    comps = components(sheet)
    if len(comps) != 5:
        print("найдено значков:", len(comps), comps)
        raise SystemExit("ожидалось 5")
    comps.sort(key=lambda b: ((b[1] + b[3]) / 2.0 // 380, (b[0] + b[2]) / 2.0))   # строки по ~ трети высоты листа, затем слева направо
    icons = {name: square(sheet, box) for name, box in zip(ORDER, comps)}
    if "--elixir" in sys.argv:
        ev = sys.argv[sys.argv.index("--elixir") + 1]
        el = Image.open(os.path.join(SRC, "elixir_%s.png" % ev)).convert("RGBA")
        ea = np.array(el.getchannel("A")) > 20
        ys, xs = np.where(ea)
        icons["veterans"] = square(el, (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    mosaic = Image.new("RGB", (SIZE * 5, SIZE))
    for i, name in enumerate(ORDER):
        im = icons[name]
        a = im.getchannel("A").point(lambda v: 255 if v > ALPHA_CUT else 0)
        rgb = Image.new("RGB", im.size, (0, 0, 0))
        rgb.paste(im.convert("RGB"), mask=a)
        mosaic.paste(rgb, (i * SIZE, 0))
    pal = mosaic.quantize(PALETTE_COLORS, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    tag = VARIANT + ("_elixir" + sys.argv[sys.argv.index("--elixir") + 1] if "--elixir" in sys.argv else "")
    out_dir = os.path.join(SRC, "out_" + tag)
    os.makedirs(out_dir, exist_ok=True)
    finals = {}
    for name, im in icons.items():
        a = im.getchannel("A").point(lambda v: 255 if v > ALPHA_CUT else 0)
        q = im.convert("RGB").quantize(palette=pal, dither=Image.Dither.NONE).convert("RGB").convert("RGBA")
        q.putalpha(a)
        finals[name] = q
        q.save(os.path.join(out_dir, name + ".png"))
        if INSTALL:
            q.save("assets/ui/%s/%s.png" % (TARGETS[name], name))
    prev = Image.new("RGBA", (5 * 130, 340), (30, 22, 25, 255))
    for i, name in enumerate(ORDER):
        q = finals[name]
        prev.alpha_composite(q, (i * 130 + 16, 8))                               # 96
        prev.alpha_composite(q.resize((56, 56), Image.LANCZOS), (i * 130 + 36, 112))   # узел Арсенала 56
        prev.alpha_composite(q.resize((30, 30), Image.LANCZOS), (i * 130 + 49, 176))   # «Слава» 30
        prev.alpha_composite(q.resize((192, 192), Image.NEAREST), (i * 130 - 30, 150)) if False else None
    prev.convert("RGB").resize((prev.width * 2, prev.height * 2), Image.NEAREST).save(os.path.join(SRC, "preview_%s.png" % tag))
    print("готово ->", out_dir, "(установлено)" if INSTALL else "")


if __name__ == "__main__":
    main()
