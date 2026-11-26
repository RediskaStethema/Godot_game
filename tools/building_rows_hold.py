"""Ряды здания — из кадра 0 стойки своего уровня (решение пользователя 13.11.2026: «bolter turret ассеты и фреймы
прыгают»): в пакете 13.11.2026 у Bolter Turret ряд выстрела 1-го уровня — другая модель турели (крупнее, другая
башня), выстрел 3-го — мельче стойки, стойка 2-го — башня перерисована в каждом кадре (дрожит), стойка 1-го
проседает на 4 px. Сдвигом и масштабом (building_rows_lock / building_stabilize) это не лечится.

В исходниках пиксель-прохода (assets/source_sheets/building_pixel_orig/<здание>) каждый кадр рядов ROWS уровня
заменяется кадром idle_<уровень>/0 (число кадров и холст прежние, frames.tres не трогается). Прежние исходники —
assets/source_sheets/buildings_redraw_2026-11-13/<здание>_hold_orig/ (повтор — от них). Затем:
tools/building_pixelize.py (пиксель-проход) и tools/building_shot_fx.py (выстрел кодом поверх стойки — отдача,
вспышка, дым; папку <здание>_attack_pixel перед ним удалить).

  PYTHONIOENCODING=utf-8 python tools/building_rows_hold.py tower
"""
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STASH = ROOT / "assets/source_sheets/building_pixel_orig"
KEEP = ROOT / "assets/source_sheets/buildings_redraw_2026-11-13"
ROWS = ("idle", "attack")


def hold(rel):
    stash = STASH / rel
    keep = KEEP / (rel.replace("/", "_") + "_hold_orig")
    if not keep.exists():
        shutil.copytree(stash, keep)
    for level in (1, 2, 3):
        sfx = "" if level == 1 else f"_{level}"
        ref = keep / f"idle{sfx}" / "0.png"
        if not ref.exists():
            continue
        for base in ROWS:
            row = stash / f"{base}{sfx}"
            if not row.exists():
                continue
            files = sorted(row.glob("*.png"), key=lambda p: int(p.stem))
            for f in files:
                shutil.copyfile(ref, f)
            print(f"{rel}/{row.name}: {len(files)} кадров ← idle{sfx}/0")


if __name__ == "__main__":
    for r in sys.argv[1:]:
        hold(r)
