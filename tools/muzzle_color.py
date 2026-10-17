"""Цвет вспышки выстрела модели → metadata/muzzle_color в frames.tres (снаряд перекрашивается в него,
Projectile.launch — решение пользователя 17.10.2026: снаряд того же цвета, что выстрел на листе).

    python tools/muzzle_color.py assets/sprites/space_marine_tactical [папка …]

Берёт кадр shot_frame анимации attack, окно у точки muzzle (ствол → вперёд по выстрелу) и в нём
яркие насыщенные пиксели — вспышку (оранжевую у болтеров, синюю у лучей). Цвет — медиана по ним,
приведённая к полной яркости (снаряд сам даёт тени). Без shot_frame / вспышки — ничего не пишет.
Повторный запуск заменяет старое значение. sheet_to_frames.py пишет его сам (flash_color).
"""
import colorsys
import math
import re
import sys
from pathlib import Path

from PIL import Image

WINDOW = (-6, 44, 14)   # от ствола: назад, вперёд, ± по высоте, px кадра
MIN_VALUE = 0.55
MIN_SAT = 0.3


def flash_color(frame, mx, my):
    """(r, g, b) 0..1 или None. mx, my — ствол в координатах кадра."""
    px = frame.load()
    back, ahead, half = WINDOW
    xs = range(int(mx + back), int(mx + ahead))   # на листах выстрел — вправо
    picked = []
    for y in range(int(my - half), int(my + half)):
        for x in xs:
            if not (0 <= x < frame.width and 0 <= y < frame.height):
                continue
            r, g, b, a = px[x, y]
            if a < 128:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            if v >= MIN_VALUE and s >= MIN_SAT:
                picked.append((h, s, v))
    if len(picked) < 8:
        return None
    # тон — по кругу (красный рядом с 0 и 1): средний вектор
    hx = sum(math.cos(2 * math.pi * h) for h, _, _ in picked)
    hy = sum(math.sin(2 * math.pi * h) for h, _, _ in picked)
    hue = (math.atan2(hy, hx) / (2 * math.pi)) % 1.0
    sats = sorted(s for _, s, _ in picked)
    sat = sats[len(sats) // 2]
    return colorsys.hsv_to_rgb(hue, sat, 1.0)


def patch(folder):
    folder = Path(folder)
    tres = folder / "frames.tres"
    text = tres.read_text(encoding="utf-8")
    shot = re.search(r"metadata/shot_frame = (\d+)", text)
    muzzle = re.search(r"metadata/muzzle = Vector2\(([-\d.]+), ([-\d.]+)\)", text)
    if not shot:
        print(f"{folder}: нет shot_frame — пропуск")
        return
    frame = Image.open(folder / "attack" / f"{shot.group(1)}.png").convert("RGBA")
    if muzzle:   # muzzle — от ног (низ по центру кадра)
        mx = frame.width / 2 + float(muzzle.group(1))
        my = frame.height + float(muzzle.group(2))
    else:        # ствола нет (Librarian: луч из посоха) — вспышка правее центра на уровне груди
        mx, my = frame.width * 0.62, frame.height * 0.55
    color = flash_color(frame, mx, my)
    if color is None:
        print(f"{folder}: вспышки у ствола нет — пропуск")
        return
    line = "metadata/muzzle_color = Color(%.3f, %.3f, %.3f, 1)" % color
    text = re.sub(r"metadata/muzzle_color = Color\([^)]*\)\n", "", text)
    text = text.replace("[resource]\n", "[resource]\n" + line + "\n", 1)
    tres.write_text(text, encoding="utf-8")
    print(f"{folder}: {line}")


if __name__ == "__main__":
    for f in sys.argv[1:]:
        patch(f)
