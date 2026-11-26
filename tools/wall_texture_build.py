"""Текстура кладки стены края поля Космодесанта (решение пользователя 23.11.2026: «нарисуй текстуру стены вокруг поля боя у
космодесанта»). Лист Layer (вариант A: 5 рядов тёсаных блоков, вид строго спереди, gpt-image-2.6-sunburst, ссылка на плиту стены и
цитадель) — `assets/source_sheets/wall_marines_v1_2026-11-23/wall_A.png` -> `assets/sprites/walls/space_marines/wall.png`:
шов по горизонтали сшит (сдвиг на полширины + смешивание в центре), ÷DIV усреднением, палитра PALETTE цветов, средняя яркость WALL_LUM
(в игре на неё умножается оттенок стороны: дальняя ×1.12, ближняя ×0.7 — `FieldWall.FAR_LIGHT / NEAR_SHADE`).
Грань стены берёт верхние HEIGHT / высота_текстуры (≈ 3 ряда) и повторяет текстуру вдоль стены (`FieldWall.Segment._textured_face`).
  python tools/wall_texture_build.py
"""
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets/source_sheets/wall_marines_v1_2026-11-23/wall_A.png"
OUT = ROOT / "assets/sprites/walls/space_marines/wall.png"
DIV = 14
PALETTE = 36
WALL_LUM = 0.16

img = np.array(Image.open(SRC).convert("RGB")).astype(np.float64)
h, w = img.shape[:2]
j = np.roll(img, w // 2, axis=1)
t = 1.0 - np.abs(np.linspace(-1, 1, w))     # 0 у краёв, 1 в центре
t = t * t * (3 - 2 * t)
img = img * t[None, :, None] + j * (1 - t[None, :, None])
h2, w2 = h // DIV * DIV, w // DIV * DIV
small = img[:h2, :w2].reshape(h2 // DIV, DIV, w2 // DIV, DIV, 3).mean(axis=(1, 3))
q = Image.fromarray(np.clip(small, 0, 255).astype(np.uint8)).quantize(colors=PALETTE, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
a = np.array(q).astype(np.float64) / 255.0
lum = (0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]).mean()
a = np.clip(a * (WALL_LUM / lum), 0, 1)
OUT.parent.mkdir(parents=True, exist_ok=True)
Image.fromarray((a * 255 + 0.5).astype(np.uint8)).save(OUT)
print(OUT.relative_to(ROOT), a.shape[1], "x", a.shape[0], "яркость было", round(float(lum), 3), "→", WALL_LUM)
