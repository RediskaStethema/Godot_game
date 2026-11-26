"""Весь конвейер юнитов Космодесанта одной командой (16.11.2026: ручной порядок шагов легко ломался — переустановка кадров
сбрасывала цветокор и стилизацию у всех юнитов, а повторяли их у одного).

  python tools/units_pipeline.py [--skip-slice] [--skip-import] [юнит ...]

Шаги (каждый — для ВСЕХ юнитов, кроме помеченных; юнит в аргументах ограничивает только нарезку и стволы, установка
перезаписывает кадры всех юнитов, поэтому цветокор и стилизация всегда идут по всем):
  1. units_reg.py              нарезка листов v2 (+ удар ближников, стойка с дыханием) -> unit_redesign_staging/<юнит>/frames2
  2. install_units.py          frames2 -> assets/units/space_marines/<юнит>  (сбрасывает цветокор!)
  3. sm_grade.py               цветокор под палитру поля (--target 0.34 --pull 0.5 --blue-sat 1 --metal-sat 0.12)
  4. unit_style.py             сбить пересвет (света брони и кости сжаты, огонь и энергия — нет)
  5. firedrakes_fx.py          струя огня Firedrakes на расширенном холсте attack (+ muzzle)
  6. muzzle_units.py           shot_frame и muzzle стрелков по вспышке
  7. muzzle_color.py           цвет вспышки для снарядов
  8. godot --import            (если не --skip-import)
Scout не трогается (оригинальные кадры). Исходники — assets/source_sheets/unit_redesign_staging; прежний арт —
assets/source_sheets/_backup_before_redesign_2026-11-15. Метрики после прогона: godot --headless -s tests/test_unit_frames.gd
"""
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STAGING = ROOT / "assets/source_sheets/unit_redesign_staging"
UNITS = ["apothecary", "assault", "centurion", "chaplain", "chapter_master", "devastator", "dreadnought", "firedrakes",
         "honour_guard", "land_speeder", "librarian", "sanguinary_guard", "tactical", "terminator", "thunderwolf"]
SHOOTERS = ["tactical", "devastator", "centurion", "chaplain", "land_speeder", "librarian", "firedrakes"]
GODOT = os.environ.get("GODOT", "C:/Godot/Godot_v4.6.2-stable_win64_console.exe")
ENV = {**os.environ, "PYTHONIOENCODING": "utf-8", "PYTHONPATH": str(ROOT / "tools")}


def run(title: str, args: list, cwd: Path = ROOT) -> None:
    print(f"== {title}", flush=True)
    r = subprocess.run([str(a) for a in args], cwd=cwd, env=ENV)
    if r.returncode != 0:
        sys.exit(f"шаг «{title}» завершился с кодом {r.returncode}")


def main(argv: list) -> None:
    flags = {a for a in argv if a.startswith("--")}
    only = [a for a in argv if not a.startswith("--")]
    py = sys.executable
    if "--skip-slice" not in flags:
        run("нарезка листов", [py, "units_reg.py", *[("sm_" + u if u != "tactical" else u) for u in only]], STAGING)
    run("установка кадров", [py, STAGING / "install_units.py"])
    for u in UNITS:
        run(f"цветокор {u}", [py, "tools/sm_grade.py", "--target", "0.34", "--pull", "0.5", "--blue-sat", "1",
                              "--metal-sat", "0.12", *sorted(str(p) for p in (ROOT / f"assets/units/space_marines/{u}").glob("*/*.png"))])
    run("стилизация (пересвет)", [py, STAGING / "unit_style.py"])
    run("огнемёт Firedrakes", [py, STAGING / "firedrakes_fx.py"])
    run("кадр выстрела и стволы", [py, STAGING / "muzzle_units.py"])
    for u in SHOOTERS:
        run(f"цвет вспышки {u}", [py, "tools/muzzle_color.py", f"assets/units/space_marines/{u}"])
    if "--skip-import" not in flags:
        run("импорт Godot", [GODOT, "--headless", "--path", ROOT, "--import"])
    print("конвейер юнитов готов — проверка: godot --headless --path . -s tests/test_unit_frames.gd")


if __name__ == "__main__":
    main(sys.argv[1:])
