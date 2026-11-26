"""Лист поз продавца (Layer, 8x2: ряды buy / no_money) -> пакет кадров 480x760 для tools/vendor_stabilize.py
(решение пользователя 23.11.2026: «перерисуй продавцов в стиле игры, концепции оставь», вариант A).
Как assets/source_sheets/shop_vendor_v3_2026-11-21/slice_vendor.py, но размер ячейки берётся из листа (3264x1296 -> 408x648):
фигура целиком приводится к росту TARGET_H прежних кадров (641 алхимик / 650 торговец — раскладка магазина не едет), без сглаживания
(пиксель-арт), стопы на нижней строке холста (y 759), центр стоп по x 226 (медиана по всем кадрам).
  python tools/vendor_redraw_slice.py <лист.png> <папка пакета> <TARGET_H>
Пакет: <папка>/buy/0..7, no_money/0..7, idle/0 (= buy/0).
"""
import os
import sys
import numpy as np
from PIL import Image

sheet_path, out_dir, target_h = sys.argv[1], sys.argv[2], int(sys.argv[3])
sheet = np.asarray(Image.open(sheet_path).convert("RGBA")).copy()
sheet[sheet[..., 3] < 24] = 0
H, W = sheet.shape[:2]
CW, CH = W // 8, H // 2
frames = {}
for r, row in enumerate(["buy", "no_money"]):
    for i in range(8):
        frames[(row, i)] = Image.fromarray(sheet[r * CH:(r + 1) * CH, i * CW:(i + 1) * CW])


def box(im):
    a = np.asarray(im)[..., 3] > 40
    ys = np.where(a.any(1))[0]
    xs = np.where(a.any(0))[0]
    return ys[0], ys[-1], xs[0], xs[-1]


def feet_cx(im, bot):
    a = np.asarray(im)[..., 3] > 40
    band = a[max(0, bot - 50):bot + 1]
    xs = np.where(band.any(0))[0]
    return (xs[0] + xs[-1]) / 2


h0 = float(np.median([box(f)[1] - box(f)[0] + 1 for f in frames.values()]))
k = target_h / h0
print("cell", CW, CH, "median figure height", h0, "scale", round(k, 3))
res = {key: im.resize((round(im.width * k), round(im.height * k)), Image.NEAREST) for key, im in frames.items()}
bots = {key: box(s)[1] for key, s in res.items()}
cxs = {key: feet_cx(s, bots[key]) for key, s in res.items()}
bot_m = int(np.median(list(bots.values())))
cx_m = np.median(list(cxs.values()))
dx, dy = int(round(226 - cx_m)), 759 - bot_m
for (row, i), s in res.items():
    c = Image.new("RGBA", (480, 760), (0, 0, 0, 0))
    c.alpha_composite(s, (dx, dy))
    out = os.path.join(out_dir, row)
    os.makedirs(out, exist_ok=True)
    c.save(os.path.join(out, "%d.png" % i))
os.makedirs(os.path.join(out_dir, "idle"), exist_ok=True)
Image.open(os.path.join(out_dir, "buy", "0.png")).save(os.path.join(out_dir, "idle", "0.png"))
b = box(Image.open(os.path.join(out_dir, "buy", "0.png")))
print("bbox y %d..%d x %d..%d" % (b[0], b[1], b[2], b[3]))
