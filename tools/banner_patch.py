"""Центр баннера итога боя перерисован в Layer и вклеен в полный баннер (23.11.2026, решение пользователя: «давай с баннера» —
UI_NEEDED: крылатый череп = канон; у «ПОБЕДЫ» орлиные крылья + корона + клинок → череп в простом кольце + лампа с двумя огнями).

Порядок: `victory_center_x4.png` (вырезка центра ×4 на ровном тёмном фоне) → Layer `image.edit` → правка (любого размера,
тот же кадр) → этот скрипт: правка уменьшается до вырезки, цвета привязываются к палитре оригинала (без дизеринга), внутри
`--region` (колонки вырезки) берётся правка, снаружи — оригинал; прозрачность — как у оригинала: над планкой рамки (строки выше
верхнего края планки, он берётся по соседним колонкам вне области) тёмный фон правки → прозрачно, остальное непрозрачно.

    python tools/banner_patch.py <оригинал.png> <правка.png> <выход.png> [--box 360,0,664,112] [--region 22,282] [--colors 48]
"""
import sys

import numpy as np
from PIL import Image

args = [a for a in sys.argv[1:] if not a.startswith("--")]
opts = {a.split("=")[0]: a.split("=")[1] for a in sys.argv[1:] if a.startswith("--") and "=" in a}
ORIG, EDIT, OUT = args[:3]
BOX = tuple(int(v) for v in opts.get("--box", "360,0,664,112").split(","))
REG = tuple(int(v) for v in opts.get("--region", "22,282").split(","))
COLORS = int(opts.get("--colors", "48"))
BG = np.array([18, 18, 20])   # фон, на котором уходила вырезка
BG_TOL = 14


def main() -> None:
    orig = Image.open(ORIG).convert("RGBA")
    w, h = BOX[2] - BOX[0], BOX[3] - BOX[1]
    edit = Image.open(EDIT).convert("RGB").resize((w, h), Image.LANCZOS)
    # палитра оригинала
    arr = np.asarray(orig).copy()
    pal_src = Image.fromarray(arr[arr[..., 3] > 200][:, :3].reshape(1, -1, 3))
    pal = pal_src.quantize(COLORS, method=Image.Quantize.MEDIANCUT)
    edit_q = np.asarray(edit.quantize(palette=pal, dither=Image.Dither.NONE).convert("RGB")).astype(int)
    # верх планки: первая непрозрачная строка в соседних колонках вне области
    a_orig = arr[BOX[1]:BOX[3], BOX[0]:BOX[2], 3]
    outside = list(range(0, REG[0] - 4)) + list(range(REG[1] + 4, w))
    tops = [int(np.nonzero(a_orig[:, x] > 128)[0].min()) for x in outside if (a_orig[:, x] > 128).any()]
    y_top = int(np.median(tops))
    print("верх планки (строка вырезки):", y_top)
    bg_like = np.abs(edit_q - BG).sum(2) < BG_TOL * 3
    patch = np.dstack([edit_q, np.full((h, w), 255)]).astype(np.uint8)
    above = np.arange(h)[:, None] < y_top
    patch[..., 3] = np.where(bg_like & above, 0, 255)
    # мягкая кромка области по бокам: 4 px смешивания с оригиналом
    out = arr.copy()
    x0, x1 = REG
    for x in range(x0, x1):
        k = min(1.0, (x - x0 + 1) / 4.0, (x1 - x) / 4.0)
        col_o = out[BOX[1]:BOX[3], BOX[0] + x].astype(float)
        col_n = patch[:, x].astype(float)
        mixed = col_o * (1 - k) + col_n * k
        out[BOX[1]:BOX[3], BOX[0] + x] = mixed.astype(np.uint8)
    Image.fromarray(out, "RGBA").save(OUT)
    print("сохранено:", OUT)


if __name__ == "__main__":
    main()
