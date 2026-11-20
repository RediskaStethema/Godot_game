"""Конвейер зданий Космодесанта одной командой (перерисовка Layer 15–16.11.2026; порядок шагов — по журналу
assets/source_sheets/building_redesign_staging/STATE.md). Кадры берутся из frames_reg (закреплённые lock_reg.py), для каждого здания:

  python tools/buildings_pipeline.py [--skip-import] [здание ...]      (без аргументов — все 11 зданий)

  1. install.py                    frames_reg -> assets/sprites/buildings/<здание> (дымка альфы < 40 стёрта, холст прежний)
  2. building_rows_lock.py --levels-only   level_shift / level_scale уровней заново (кадры внутри ряда не двигаются)
  3. building_edge_feather.py      срез у края холста -> мягкое затухание (после удаления прежних исходников затухания)
  4. building_pixelize.py          пиксель-арт кадров (после удаления исходников пиксель-прохода здания)
  5. стрелки (tower, artillery, fists_bastion): building_shot_impact.py — ряды выстрела из стойки + крупная вспышка;
     building_levels_muzzle.py — стволы уровней и оси (у tower залп вручную, см. TOWER_BARRELS: скрипт стволов его затирает)
  6. godot --import
Прежний арт зданий — assets/source_sheets/_backup_before_redesign_2026-11-15/sprites/buildings.
"""
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STAGING = ROOT / "assets/source_sheets/building_redesign_staging"
GAME = ROOT / "assets/sprites/buildings"
BUILDINGS = ["apothecarion", "artillery", "barracks", "generator", "tower", "wall", "codex_bastion", "fists_bastion",
             "vulkan_forge", "wolf_totem", "blood_chalice"]
SHOOTERS = ["tower", "artillery", "fists_bastion"]
# Залп Bolter Turret вручную по жерлам кадра стойки (3 ствола на 3-м уровне — вспышки в листе слиты): muzzle-скрипт его затирает
TOWER_BARRELS = ("metadata/level_barrels = {2: [Vector2(169.0, -180.0), Vector2(150.0, -148.0)], 3: [Vector2(172.0, -212.0), "
                 "Vector2(160.0, -176.0), Vector2(146.0, -141.0)]}")
GODOT = os.environ.get("GODOT", "C:/Godot/Godot_v4.6.2-stable_win64_console.exe")
ENV = {**os.environ, "PYTHONIOENCODING": "utf-8", "PYTHONPATH": str(ROOT / "tools")}


def run(title: str, args: list) -> None:
    print(f"== {title}", flush=True)
    r = subprocess.run([str(a) for a in args], cwd=ROOT, env=ENV)
    if r.returncode != 0:
        sys.exit(f"шаг «{title}» завершился с кодом {r.returncode}")


def main(argv: list) -> None:
    skip_import = "--skip-import" in argv
    names = [a for a in argv if not a.startswith("--")] or BUILDINGS
    py = sys.executable
    for b in names:
        run(f"установка {b}", [py, STAGING / "install.py", b])
        run(f"уровни {b}", [py, "tools/building_rows_lock.py", GAME / b, "--levels-only"])
        for stash in (ROOT / "assets/source_sheets/building_pixel_orig" / b, ROOT / "assets/source_sheets/building_edge_orig" / b):
            if stash.exists():
                shutil.rmtree(stash)
        run(f"затухание краёв {b}", [py, "tools/building_edge_feather.py", b])
        run(f"пиксель-арт {b}", [py, "tools/building_pixelize.py", GAME / b])
        if b in SHOOTERS:
            keep = STAGING / b / "attack_pixel_orig"
            if keep.exists():   # чистые ряды прежнего прогона относятся к прежнему пиксель-проходу
                shutil.rmtree(keep)
            run(f"выстрел {b}", [py, "tools/building_shot_impact.py", b])
            run(f"стволы {b}", [py, "tools/building_levels_muzzle.py", b])
            if b == "tower":
                tres = GAME / b / "frames.tres"
                text = re.sub(r"metadata/level_barrels = [^\n]*", TOWER_BARRELS, tres.read_text(encoding="utf-8"))
                tres.write_text(text, encoding="utf-8", newline="")
    if not skip_import:
        run("импорт Godot", [GODOT, "--headless", "--path", ROOT, "--import"])
    print("конвейер зданий готов — проверка: tests/test_buildings.gd, test_sprite_sheets.gd, test_asset_hooks.gd")


if __name__ == "__main__":
    main(sys.argv[1:])
