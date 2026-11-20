"""Дым зданий только в работе (решение пользователя 17.11.2026: «на статичных кадрах apothecarion дым будто часть
строения — дым должен появляться только во время анимации работы здания и во время боя»).

Вне боя стойка здания — кадр 0 ряда idle (Building.hold_idle_outside_battle). У Апотекариона Космодесанта 1-го и 3-го
уровня дымовой шлейф над трубой нарисован во ВСЕХ кадрах стойки, в том числе в нулевом — на расстановке он выглядел частью
здания. Скрипт гасит альфу шлейфа в заданном прямоугольнике по профилю sin(pi * i / N): кадр 0 — без дыма, в середине
цикла — полный, к концу цикла — снова без дыма (петля без скачка). Корпус под прямоугольником не трогается.

Исходные кадры — assets/source_sheets/building_smoke_orig_2026-11-17/<здание>/<ряд>/N.png (повторный прогон — от них).
После building_pixelize.py / building_levels_add.py / unit_frames.py import --buildings по этим зданиям прогнать снова
(они пишут кадры заново, из своих исходников — дым вернётся).

  python tools/building_smoke_fade.py             — все ряды таблицы SPECS
  python tools/building_smoke_fade.py --dry       — только отчёт (сколько пикселей альфы гасится в каждом кадре)
  python tools/building_smoke_fade.py --restore   — вернуть исходные кадры
Затем: godot --headless --path . --import
"""
import argparse
import math
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
BUILDINGS = ROOT / "assets/sprites/buildings"
BACKUP = ROOT / "assets/source_sheets/building_smoke_orig_2026-11-17"

# здание → ряд → прямоугольник дыма (x0, y0, x1, y1) в пикселях кадра: строго над трубой / куполом, где корпуса нет
# (границы подобраны по сетке на увеличенных кадрах: 1-й уровень — шлейф над золотым колпаком трубы (колпак с y 62),
# 3-й — завиток над золотой маковкой (с y 108))
SPECS = {
    "apothecarion": {
        "idle": (150, 0, 300, 62),
        "idle_3": (120, 0, 300, 108),
    },
    # Кузня Вулкана (решение пользователя 17.11.2026): шлейф дыма над горном нарисован во всех кадрах всех трёх уровней —
    # над тёмным кольцом горна (кольцо с y 138 / 175 / 212; огонь горна — ниже границ прямоугольников)
    "vulkan_forge": {
        "idle": (60, 0, 200, 134),
        "idle_2": (70, 0, 210, 172),
        "idle_3": (70, 0, 230, 210),
    },
    # Чумной котёл (17.11.2026, «дым только в работе»): ядовитый пар над ободом котла нарисован во всех кадрах; варево
    # в котле — часть здания, остаётся (границы — по обод котла: 80 / 96 / 98)
    "plague_cauldron": {
        "idle": (30, 0, 190, 80),
        "idle_2": (30, 0, 190, 96),
        "idle_3": (30, 0, 190, 98),
    },
    # Театр Второго акта, 3-й уровень: бледные завитки дыма по бокам; прямоугольников два (слева и справа от сцены)
    "pleasure_shrine": {
        # завитки заходят за колонны сцены — гасятся только бледные малонасыщенные пиксели ("pale"), корпус остаётся
        # (темные контуры завитков не «бледные» — снаружи колонн гасится всё, у колонн — только бледное)
        "idle_3": [(60, 60, 127, 150), (60, 150, 103, 215), (103, 60, 150, 215, "pale"),
                   (220, 110, 270, 215), (205, 110, 220, 215, "pale"),
                   (30, 215, 130, 320, "pale"), (200, 215, 300, 320, "pale")],
    },
}


PALE_SAT = 0.30        # режим "pale": насыщенность ниже — дым (завитки Театра: сиренево-серые)
PALE_MIN_VALUE = 0.22  # и не чёрный контур корпуса


def frame_files(folder: Path):
    return sorted(folder.glob("*.png"), key=lambda p: int(p.stem))


def factor(i: int, n: int) -> float:
    """0 в кадре 0 и 1 в середине цикла; цикл замкнут (кадр n-1 почти без дыма)."""
    return math.sin(math.pi * i / n)


def process(building: str, row: str, rect, dry: bool) -> None:
    folder = BUILDINGS / building / row
    backup = BACKUP / building / row
    files = frame_files(folder)
    if not files:
        print("  %s/%s: нет кадров" % (building, row))
        return
    if not dry and not backup.exists():
        backup.mkdir(parents=True)
        for f in files:
            shutil.copy2(f, backup / f.name)
    n = len(files)
    rects = rect if isinstance(rect, list) else [rect]
    report = []
    for f in files:
        i = int(f.stem)
        src = backup / f.name if backup.exists() else f   # повторный прогон — от исходников
        a = np.asarray(Image.open(src).convert("RGBA")).copy()
        k = factor(i, n)
        before = after = 0
        for r in rects:
            x0, y0, x1, y1 = r[:4]
            region = a[y0:y1, x0:x1, 3].astype(np.float32)
            if len(r) > 4 and r[4] == "pale":   # только дым: бледный, малонасыщенный (корпус — коричневый / пурпурный / золотой)
                rgb = a[y0:y1, x0:x1, :3].astype(np.float32) / 255.0
                mx, mn = rgb.max(-1), rgb.min(-1)
                sat = np.where(mx > 1e-6, (mx - mn) / np.maximum(mx, 1e-6), 0.0)
                smoke = (sat < PALE_SAT) & (mx > PALE_MIN_VALUE)
                factor_map = np.where(smoke, k, 1.0)
            else:
                factor_map = k
            before += int((region > 20).sum())
            a[y0:y1, x0:x1, 3] = np.round(region * factor_map).astype(np.uint8)
            after += int((a[y0:y1, x0:x1, 3] > 20).sum())
        report.append("%d:%d→%d" % (i, before, after))
        if not dry:
            Image.fromarray(a).save(f)
    print("  %s/%s (%d кадров, дым %s): %s" % (building, row, n, rect, " ".join(report[:12]) + (" …" if n > 12 else "")))


def restore() -> None:
    if not BACKUP.exists():
        sys.exit("нет резервной копии %s" % BACKUP)
    for b, rows in SPECS.items():
        for row in rows:
            src = BACKUP / b / row
            for f in frame_files(src):
                shutil.copy2(f, BUILDINGS / b / row / f.name)
    print("исходные кадры возвращены")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry", action="store_true")
    ap.add_argument("--restore", action="store_true")
    a = ap.parse_args()
    if a.restore:
        restore()
        return
    for b, rows in SPECS.items():
        for row, rect in rows.items():
            process(b, row, rect, a.dry)


if __name__ == "__main__":
    main()
