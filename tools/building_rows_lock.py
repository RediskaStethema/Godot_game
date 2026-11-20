"""Перерисованный пакет здания на месте (кадры уже лежат в папке здания на прежнем холсте) → без прыжков.

Решение пользователя 12.11.2026 («ассеты apothecarion прыгают во время игры»): в пакете художника (листы 3×2 / 6×4,
кадры «вписаны пропорционально в холст») здание 1-го уровня от кадра к кадру уезжало на 7 px и прыгало на 13 назад,
низ — на 5 px; а 1-й и 2–3 уровни стоят на холсте по-разному, metadata/level_shift и level_scale в frames.tres были
посчитаны под прежний арт — при улучшении здание прыгнуло бы.

  1. каждый кадр ряда — целым сдвигом на постамент 1-го кадра своего ряда (наибольшее перекрытие масок нижних
     ALIGN_ZONE силуэта, building_levels_add.shift_to; поиск ±ROW_RANGE);
  2. level_shift / level_scale заново — как building_levels_add.py: постамент уровня на постамент 1-го, рост уровня
     ≥ LEVEL_GROWTH прежнего, основание не шире MAX_BASE_GROWTH основания 1-го; level_static — как было.
Холст и число кадров не меняются; исходники пакета — в assets/source_sheets/<здание>_redraw_<дата>/frames_raw
(повтор: скопировать их обратно и прогнать снова). Затем tools/building_pixelize.py по зданию (его исходники в
building_pixel_orig/<здание> — удалить) и --import.

  PYTHONIOENCODING=utf-8 PYTHONPATH=tools python tools/building_rows_lock.py <папка здания> [--dry] [--levels-only]
"""
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

import building_levels_add as bla

ROW_RANGE = (64, 32)   # ± px по x, y внутри ряда (апотекарион гулял до 13 px; пакет 13.11.2026 — до 45 по x
                       # у Кузни Вулкана и турели, 21 по y у Казарм и Шпиля варпа)
LEVEL_RANGE = (90, 60)  # ± px сдвига уровня к 1-му (building_levels_add — ±14 по y: у Апотекариона 2026-11-12 уровни
                        # стоят на холсте на ~40 px ниже 1-го)


def shift_in_row(ref: Path, img: Path):
    a = np.array(Image.open(ref).convert("RGBA"))[..., 3] > bla.ALPHA
    b = np.array(Image.open(img).convert("RGBA"))[..., 3] > bla.ALPHA
    ys = np.nonzero(a)[0]
    y1 = ys.max() + 1
    y0 = y1 - int((y1 - ys.min()) * bla.ALIGN_ZONE)
    best, shift = -1.0, (0, 0)
    rx, ry = ROW_RANGE
    for dy in range(-ry, ry + 1):
        for dx in range(-rx, rx + 1):
            m = np.roll(np.roll(b, dy, axis=0), dx, axis=1)[y0:y1]
            r = a[y0:y1]
            score = (r & m).sum() / max(1, (r | m).sum())
            if score > best:
                best, shift = score, (dx, dy)
    return shift, best


def move(path: Path, dx: int, dy: int) -> None:
    img = Image.open(path).convert("RGBA")
    out = Image.new("RGBA", img.size)
    out.paste(img, (dx, dy))
    out.save(path)


def main(args):
    dry = "--dry" in args
    folder = Path(next(a for a in args if not a.startswith("--")))
    rows = sorted(p for p in folder.iterdir() if p.is_dir())
    if "--levels-only" in args:   # кадры уже закреплены (корпус из одного кадра): только level_shift / level_scale
        rows = []
    for row in rows:
        files = sorted(row.glob("*.png"), key=lambda p: int(p.stem))
        for f in files[1:]:
            (dx, dy), score = shift_in_row(files[0], f)
            if (dx, dy) != (0, 0):
                print(f"  {row.name}/{f.name}: сдвиг ({dx}, {dy}), постамент {score:.2f}")
                if not dry:
                    move(f, dx, dy)
    # сдвиг и рост уровней — как building_levels_add.add_levels
    bla.ALIGN_RANGE = LEVEL_RANGE
    tres = folder / "frames.tres"
    text = tres.read_text(encoding="utf-8")
    idle0 = folder / "idle" / "0.png"
    ground = bla.base_y(idle0)
    heights, shifts, bases = {1: bla.height_of(idle0, ground)}, {}, {}
    for level in (2, 3):
        f = folder / f"idle_{level}" / "0.png"
        if not f.exists():
            continue
        shifts[level], score = bla.shift_to(idle0, f)
        heights[level] = bla.height_of(f, ground - shifts[level][1])
        bases[level] = bla.base_width(f)
        print(f"  уровень {level}: сдвиг {shifts[level]} (IoU постамента {score:.2f})")
    scales, prev = {}, heights[1]
    for level in sorted(shifts):
        k = max(1.0, prev * bla.LEVEL_GROWTH / heights[level])
        cap = bla.MAX_BASE_GROWTH * bla.base_width(idle0) / max(bases[level], 1.0)
        scales[level] = min(k, cap)
        prev = heights[level] * scales[level]
        print(f"  уровень {level}: высота {heights[level]:.0f} px (1-й {heights[1]:.0f}), масштаб x{scales[level]:.3f}"
              + (" (предел основания)" if k > cap else ""))
    if dry or not shifts:
        return
    shift_txt = "{" + ", ".join(f"{lv}: Vector2({dx}, {dy})" for lv, (dx, dy) in sorted(shifts.items())) + "}"
    scale_txt = "{" + ", ".join(f"{lv}: {k:.3f}" for lv, k in sorted(scales.items())) + "}"
    text = re.sub(r"metadata/level_shift = \{[^\n]*\}", "metadata/level_shift = " + shift_txt, text)
    text = re.sub(r"metadata/level_scale = \{[^\n]*\}", "metadata/level_scale = " + scale_txt, text)
    tres.write_text(text, encoding="utf-8")


if __name__ == "__main__":
    main(sys.argv[1:])
