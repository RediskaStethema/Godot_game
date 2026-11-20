"""Пиксель-арт кадров юнитов (решение пользователя 17.11.2026: «огрубить юнитов» — пиксель юнита на экране был 0.3–0.5 px, у
зданий 1.2–2.2; tools/pixel_audit.py). Тот же проход, что у зданий и капсулы (tools/building_pixelize.py): кадр уменьшается в PIXEL раз
(среднее по клетке с весом альфы), цвета — общая палитра на ВСЕ кадры юнита (все ряды одной группой — кадры не мигают), прозрачность
ступенями, кромка силуэта темнее, обратно ×PIXEL без сглаживания; холст прежний (по нему muzzle / shot_frame / metadata в frames.tres).

PIXEL юнита — по его росту на экране: боец нормализуется к Soldier.TARGET_SPRITE_HEIGHT (31 px) по непрозрачной высоте кадра idle/0,
значит масштаб = 31 / высота, а пиксель арта на поле = PIXEL × масштаб; берём PIXEL так, чтобы он был ≈ WORLD_PX (по умолчанию 1.3 —
как у зданий). Меньше `--world-px` → мельче пиксель (0.9 — детальнее, 1.8 — крупнее).

Исходники — assets/source_sheets/unit_pixel_orig/<раса>/<юнит>/ (первый прогон копирует туда, повторный берёт оттуда); `--restore` — вернуть.

  PYTHONIOENCODING=utf-8 python tools/unit_pixelize.py [--world-px 1.3] [--dry] assets/units/space_marines/tactical [...]
  python tools/unit_pixelize.py --restore assets/units/space_marines/tactical
затем godot --headless --path . --import
"""
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import building_pixelize as bp  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
STASH = ROOT / "assets/source_sheets/unit_pixel_orig"
UNIT_HEIGHT = 31.0     # Soldier.TARGET_SPRITE_HEIGHT


def used_height(im: Image.Image) -> int:
    ys = np.nonzero(np.array(im)[:, :, 3].any(axis=1))[0]
    return int(ys.max() - ys.min() + 1) if len(ys) else im.height


def main(args):
    dry = "--dry" in args
    restore = "--restore" in args
    world_px = 1.3
    if "--world-px" in args:
        world_px = float(args[args.index("--world-px") + 1])
    dirs = [Path(a).resolve() for a in args if not a.startswith("--") and not a.replace(".", "").isdigit()]
    if not dirs:
        sys.exit("нужна папка юнита, например assets/units/space_marines/tactical")
    for unit in dirs:
        rel = unit.relative_to(ROOT / "assets/units")
        stash = STASH / rel
        if restore:
            for f in stash.glob("*/*.png"):
                shutil.copy2(f, unit / f.parent.name / f.name)
            print("%s: исходные кадры возвращены" % rel)
            continue
        if not stash.exists() and not dry:
            shutil.copytree(unit, stash, ignore=shutil.ignore_patterns("*.import", "*.tres"))
        src = stash if stash.exists() else unit
        files = sorted(src.glob("*/*.png"))
        idle0 = src / "idle" / "0.png"
        if not files or not idle0.exists():
            print("%s: нет кадров" % rel)
            continue
        h = used_height(Image.open(idle0).convert("RGBA"))
        scale = UNIT_HEIGHT / h
        px = int(np.clip(round(world_px / scale), *bp.PIXEL_RANGE))
        print("%s: рост кадра %d → масштаб %.3f, PIXEL %d (пиксель на экране %.2f), кадров %d" % (rel, h, scale, px, px * scale, len(files)))
        if dry:
            continue
        images = [Image.open(f).convert("RGBA") for f in files]
        sizes = {im.size for im in images}
        out = []
        for size in sizes:   # кадры разных рядов бывают разного холста — каждая группа своим проходом, палитра общая на группу
            group = [(f, im) for f, im in zip(files, images) if im.size == size]
            res = bp.pixelize([im for _, im in group], px)
            out.extend((f, r) for (f, _), r in zip(group, res))
        for f, r in out:
            bp.save(r, unit / f.parent.name / f.name)
        print("  записано %d кадров" % len(out))


if __name__ == "__main__":
    main(sys.argv[1:])
