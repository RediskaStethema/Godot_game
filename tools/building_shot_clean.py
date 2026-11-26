"""Ряды выстрела стрелков без нарисованной вспышки (решение пользователя 21.11.2026: «у стреляющих зданий проблемы
с анимациями выстрелов» — клин вспышки в кадрах листа срезался краем холста и дрожал; вспышку, искры, свет и накал
теперь рисует код — BuildingFx.muzzle_flash, Building._queue_code_flash).

Каждый кадр рядов attack / attack_2 / attack_3 = кадр 0 стойки своего уровня (idle / idle_2 / idle_3); число кадров,
имена и shot_frame прежние, отдача — кодом (Building._apply_motion). В frames.tres ставится metadata/code_flash = true.
Прежние кадры — assets/source_sheets/_backup_before_code_flash_2026-11-21/<здание>.

  python tools/building_shot_clean.py chaos/tower chaos/artillery        затем --import
"""
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
B = ROOT / "assets/sprites/buildings"
BACKUP = ROOT / "assets/source_sheets/_backup_before_code_flash_2026-11-21"


def main(names):
    for name in names:
        folder = B / name
        bak = BACKUP / name
        if not bak.exists():
            shutil.copytree(folder, bak, ignore=shutil.ignore_patterns("*.import"))
        n = 0
        for lvl, (att, idl) in enumerate([("attack", "idle"), ("attack_2", "idle_2"), ("attack_3", "idle_3")], 1):
            src = folder / idl / "0.png"
            row = folder / att
            if not src.exists() or not row.exists():
                continue
            for f in sorted(row.glob("*.png")):
                shutil.copyfile(src, f)
                n += 1
        tres = folder / "frames.tres"
        text = tres.read_text(encoding="utf-8")
        if "metadata/code_flash" not in text:
            text = text.replace("\n[resource]\n", "\n[resource]\nmetadata/code_flash = true\n", 1)
            tres.write_text(text, encoding="utf-8", newline="")
        print(f"{name}: кадров выстрела заменено {n}, code_flash")


if __name__ == "__main__":
    main(sys.argv[1:])
