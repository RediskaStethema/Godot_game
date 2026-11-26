"""Декор и грунт за стеной поля (Layer, 23.11.2026, решение пользователя: «так очень неплохо» + анимация).

Режет листы `assets/source_sheets/surround_v1_2026-11-23` на отдельные спрайты и грунт:
  python tools/surround_slice.py           # спрайты -> assets/source_sheets/surround_v1_2026-11-23/cut/<раса>/NN.png (родное разрешение, ореол снят)
Дальше анимация и сборка — tools/surround_build.py.
"""
import sys
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets/source_sheets/surround_v1_2026-11-23"
ALPHA_MIN = 200      # ниже — ореол нейросети (мягкое тёмное свечение вокруг предметов)
BLK = 8
GLUE = 2            # блоков: зазор, который склеивает части предмета
MIN_AREA = 4000      # px родного листа: обрывки меньше — шум


def cut(race: str) -> None:
    img = Image.open(SRC / f"decor_{race}.png").convert("RGBA")
    a = np.array(img)
    solid = a[..., 3] >= ALPHA_MIN
    # предмет = связная область грубой сетки (блок BLK px, соседние склеены с запасом GLUE блоков: ветки, камни у подножия)
    h, w = solid.shape
    g = solid[:h // BLK * BLK, :w // BLK * BLK].reshape(h // BLK, BLK, w // BLK, BLK).any(axis=(1, 3))
    lab = np.zeros(g.shape, dtype=np.int32)
    n = 0
    for sy, sx in zip(*np.where(g)):
        if lab[sy, sx]:
            continue
        n += 1
        stack = [(sy, sx)]
        lab[sy, sx] = n
        while stack:
            y, x = stack.pop()
            for dy in range(-GLUE, GLUE + 1):
                for dx in range(-GLUE, GLUE + 1):
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < g.shape[0] and 0 <= xx < g.shape[1] and g[yy, xx] and not lab[yy, xx]:
                        lab[yy, xx] = n
                        stack.append((yy, xx))
    full = np.kron(lab, np.ones((BLK, BLK), dtype=np.int32))
    full = np.pad(full, ((0, h - full.shape[0]), (0, w - full.shape[1])))
    items = []
    for i in range(1, n + 1):
        m = (full == i) & solid
        if m.sum() < MIN_AREA:
            continue
        ys, xs = np.where(m)
        sl = (slice(ys.min(), ys.max() + 1), slice(xs.min(), xs.max() + 1))
        items.append((sl, m[sl]))
    # порядок: ряды сверху вниз (по центру), внутри ряда слева направо
    items.sort(key=lambda t: ((t[0][0].start + t[0][0].stop) // 2 // 1000, (t[0][1].start + t[0][1].stop) // 2))
    out = SRC / "cut" / race
    out.mkdir(parents=True, exist_ok=True)
    for old in out.glob("*.png"):
        old.unlink()
    for k, (sl, mask) in enumerate(items):
        crop = a[sl].copy()
        crop[..., 3] = np.where(mask, 255, 0)
        crop[..., :3] = np.where(mask[..., None], crop[..., :3], 0)
        Image.fromarray(crop).save(out / f"{k:02d}.png")
        print(race, k, crop.shape[1], "x", crop.shape[0])


if __name__ == "__main__":
    for r in (sys.argv[1:] or ["chaos", "marines"]):
        cut(r)
