"""Десантник живой сцены главного меню (assets/ui/menu/anim/marine_NN.png) — в свет и цвет сцены.

Решение пользователя 06.11.2026: «десантник выглядит инородно, будто парит» — добавить освещение и стилизацию.
Брак пакета и что делает скрипт (исходники не трогает — assets/source_sheets/menu_anim/marine_orig/):
  1. Стабилизация: ноги в кадрах пакета ездят до 4 px по x и на 1 px по y (герой скользил по плитам) —
     каждый кадр сдвигается так, чтобы синие поножи (нижние LEGS_ROWS холста) легли на кадр 0.
  2. Цвет: насыщенность и яркость фигуры к башне (у сцены насыщенность 0.30 и яркость 0.23,
     у пакета 0.67 / 0.27); тени — к холодной стали башни; красные линзы шлема и золото гаснут слабее.
  3. Свет сцены: планета слева снизу — холодный контровой свет у левого края силуэта под чёрным контуром (RIM_*),
     правая сторона фигуры — в тень (SIDE_SHADE), к ногам темнее (FOOT_AO) — фигура «садится» на площадку.
  4. Тень на плитах — отдельный слой marine_shadow.png (MenuSceneArt кладёт его под десантника):
     мягкое пятно под сапогами + короткая падающая тень вправо-назад (свет планеты слева).

  python tools/menu_marine_fix.py
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets/source_sheets/menu_anim/marine_orig"
DST = ROOT / "assets/ui/menu/anim"
FRAMES = 8

LEGS_ROWS = (680, 806)      # полоса поножей и сапог на холсте 712×1172
LEGS_COLS = (200, 390)
SEARCH = 6                  # поиск сдвига ± px

SAT_MUL = 0.58              # насыщенность × (07.11.2026: было 0.76 — сат. 0.47 против 0.30 у башни)
VAL_MUL = 0.86              # яркость ×
COLD = np.array([46, 52, 70], dtype=np.float32)   # сталь башни в тени
COLD_MIX = 0.26             # тёмные тона — к ней
KEEP_HOT = 0.6              # яркие насыщенные (линзы, золото) — меньше приглушения

RIM_COLOR = np.array([150, 190, 255], dtype=np.float32)   # отсвет планеты
# 1-й, 2-й… пиксель от левого края силуэта. 07.11.2026 (Screenshot 2026-11-07 112423.png, «оторван от картинки»):
# было (0.75, 0.42, 0.18) — светлым стал сам чёрный контур, фигура смотрелась наклейкой; контур (1-й) остаётся
# чёрным, как у башни, свет — тонко внутри
RIM_STRENGTH = (0.0, 0.30, 0.16, 0.06)
RIM_FEET_FADE = 0.25        # нижняя доля фигуры (сапоги на плитах) — без контрового света
RIM_TOP_BONUS = 0.35        # верх фигуры (плечо, шлем) ловит свет сильнее
SIDE_SHADE = 0.22           # правая сторона фигуры темнее на долю
FOOT_AO = 0.30              # у самых ног темнее на долю
FOOT_AO_HEIGHT = 70         # px над низом силуэта

SHADOW_ALPHA = 0.62
SHADOW_CENTER_DY = -4       # центр пятна над нижней точкой сапог
SHADOW_RADII = (92, 15)     # px холста — пятно по плитам
CAST_OFFSET = (34, -6)      # падающая тень вправо-назад
CAST_RADII = (70, 11)
CAST_ALPHA = 0.32
SHADOW_BLUR = 7


def legs_mask(rgba: np.ndarray) -> np.ndarray:
    r, g, b, a = (rgba[..., i].astype(np.int32) for i in range(4))
    return (a > 128) & (b > r + 8)


def find_shift(ref: np.ndarray, frame: np.ndarray) -> tuple[int, int]:
    y0, y1 = LEGS_ROWS
    x0, x1 = LEGS_COLS
    target = ref[y0:y1, x0:x1]
    best = (None, 0, 0)
    for dy in range(-SEARCH, SEARCH + 1):
        for dx in range(-SEARCH, SEARCH + 1):
            cut = frame[y0 + dy:y1 + dy, x0 + dx:x1 + dx]
            err = int(np.count_nonzero(cut != target))
            if best[0] is None or err < best[0]:
                best = (err, dx, dy)
    return best[1], best[2]


def shift(img: np.ndarray, dx: int, dy: int) -> np.ndarray:
    """Сдвиг содержимого на (-dx, -dy): кадр, где ноги на +dx, возвращается к кадру 0."""
    out = np.zeros_like(img)
    h, w = img.shape[:2]
    sx, sy = -dx, -dy
    src = img[max(0, -sy):h - max(0, sy), max(0, -sx):w - max(0, sx)]
    out[max(0, sy):max(0, sy) + src.shape[0], max(0, sx):max(0, sx) + src.shape[1]] = src
    return out


def grade(img: np.ndarray) -> np.ndarray:
    rgb = img[..., :3].astype(np.float32)
    alpha = img[..., 3]
    hsv = np.asarray(Image.fromarray(img[..., :3]).convert("HSV"), dtype=np.float32) / 255.0
    sat, val = hsv[..., 1], hsv[..., 2]
    hot = np.clip((sat - 0.55) * 2.5, 0, 1) * np.clip((val - 0.45) * 2.5, 0, 1)   # линзы, золото
    keep = hot * KEEP_HOT
    sat2 = sat * (SAT_MUL + (1 - SAT_MUL) * keep)
    val2 = val * (VAL_MUL + (1 - VAL_MUL) * keep)
    hsv2 = np.stack([hsv[..., 0], sat2, val2], axis=-1)
    hsv8 = (np.clip(hsv2, 0, 1) * 255).astype(np.uint8)
    out = np.asarray(Image.merge("HSV", [Image.fromarray(hsv8[..., c]) for c in range(3)]).convert("RGB"),
                     dtype=np.float32)
    dark = np.clip(1.0 - val2 / 0.35, 0, 1)[..., None] * COLD_MIX * (1 - keep[..., None])
    out = out * (1 - dark) + COLD * dark
    return np.dstack([np.clip(out, 0, 255), alpha]).astype(np.float32)


def light(img: np.ndarray) -> np.ndarray:
    rgb = img[..., :3]
    solid = img[..., 3] > 128
    ys, xs = np.nonzero(solid)
    top, bottom = ys.min(), ys.max()
    left, right = xs.min(), xs.max()
    h, w = solid.shape
    # Контровой свет: расстояние до прозрачного слева (1..3 px)
    rim = np.zeros((h, w), dtype=np.float32)
    taken = np.zeros_like(solid)
    for k, s in enumerate(RIM_STRENGTH, start=1):   # k-й пиксель от левого края: в k px левее — пусто
        empty_left = np.ones_like(solid)
        empty_left[:, k:] = ~solid[:, :-k]
        m = solid & empty_left & ~taken
        rim[m] = s
        taken |= m
    yy = np.arange(h, dtype=np.float32)[:, None]
    xx = np.arange(w, dtype=np.float32)[None, :]
    up = np.clip(1.0 - (yy - top) / max(1, bottom - top), 0, 1)
    rim *= 1.0 + RIM_TOP_BONUS * up
    rim *= np.clip(up / RIM_FEET_FADE, 0, 1)
    rgb = rgb + (RIM_COLOR[None, None, :] - rgb) * np.clip(rim, 0, 1)[..., None] * 0.9
    # Теневая сторона и затенение к ногам
    across = np.clip((xx - left) / max(1, right - left), 0, 1)
    side = 1.0 - SIDE_SHADE * across ** 1.5
    feet = 1.0 - FOOT_AO * np.clip(1.0 - (bottom - yy) / FOOT_AO_HEIGHT, 0, 1) ** 2
    rgb = rgb * (side * feet)[..., None]
    return np.dstack([np.clip(rgb, 0, 255), img[..., 3]]).astype(np.uint8)


def ellipse(h: int, w: int, cx: float, cy: float, rx: float, ry: float) -> np.ndarray:
    yy = np.arange(h, dtype=np.float32)[:, None]
    xx = np.arange(w, dtype=np.float32)[None, :]
    d = ((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2
    return np.clip(1.0 - d, 0, 1) ** 0.7


def shadow_layer(frame0: np.ndarray) -> Image.Image:
    solid = legs_mask(frame0)
    ys, xs = np.nonzero(solid)
    bottom = ys.max()
    feet = xs[ys > bottom - 20]
    cx = (feet.min() + feet.max()) / 2.0
    cy = bottom + SHADOW_CENTER_DY
    h, w = frame0.shape[:2]
    a = ellipse(h, w, cx, cy, *SHADOW_RADII) * SHADOW_ALPHA
    a = np.maximum(a, ellipse(h, w, cx + CAST_OFFSET[0], cy + CAST_OFFSET[1], *CAST_RADII) * CAST_ALPHA)
    img = Image.fromarray(np.dstack([np.zeros((h, w, 3), np.uint8), (a * 255).astype(np.uint8)]))
    return img.filter(ImageFilter.GaussianBlur(SHADOW_BLUR))


def main() -> None:
    import sys
    sys.stdout.reconfigure(encoding="utf-8")
    frames = [np.asarray(Image.open(SRC / f"marine_{i:02d}.png").convert("RGBA")) for i in range(FRAMES)]
    ref = legs_mask(frames[0])
    for i, f in enumerate(frames):
        dx, dy = (0, 0) if i == 0 else find_shift(ref, legs_mask(f))
        out = light(grade(shift(f, dx, dy)))
        Image.fromarray(out).save(DST / f"marine_{i:02d}.png")
        print(f"marine_{i:02d}: сдвиг ({-dx:+d}, {-dy:+d})")
    shadow_layer(frames[0]).save(DST / "marine_shadow.png")
    print("marine_shadow.png")


if __name__ == "__main__":
    main()
