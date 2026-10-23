"""Кадры моделек юнитов — в одну папку для правки и обратно в игру.

Выгрузка: все кадры, которые играет игра (по frames.tres каждой папки assets/sprites/<юнит>, на которую ссылается
UnitFactory), копируются в одну папку с именами <юнит>_<анимация>_<номер кадра в анимации>.png
(space_marine_tactical_walk_03.png). Номер — порядок кадра в анимации, как его играет игра, а не номер файла
(у Centurion стойка — файлы 1, 2, 5, 4). Рядом — manifest.json: имя → исходный файл. В папке .gdignore —
Godot копии не импортирует.

Загрузка: правленые файлы папки (отличаются от исходника) копируются на свои места в assets/sprites. Размер кадра
должен остаться прежним — по холсту стоят ноги (низ кадра = точка бойца), считается рост и ствол (muzzle);
файл другого размера пропускается (--force — всё равно). После загрузки — импорт: godot --headless --import.

  python tools/unit_frames.py export [папка]   (по умолчанию assets/source_sheets/unit_frames)
  python tools/unit_frames.py import [папка] [--force] [--dry]
"""
import filecmp
import json
import os
import re
import shutil
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_DIR = os.path.join(ROOT, "assets", "source_sheets", "unit_frames")
FACTORY = os.path.join(ROOT, "scripts", "data", "UnitFactory.gd")
ANIM_RE = re.compile(r'\{\n"frames": \[(.*?)\],\n"loop": \w+,\n"name": &"(\w+)",', re.S)


def unit_folders():
    """Папки спрайтов, на которые ссылаются юниты (UnitFactory.sprite_path), по алфавиту."""
    text = open(FACTORY, encoding="utf-8").read()
    names = sorted(set(re.findall(r'res://assets/sprites/([a-z_]+)"', text)))
    return [n for n in names if os.path.exists(os.path.join(ROOT, "assets", "sprites", n, "frames.tres"))]


def animations(unit):
    """[(анимация, [путь кадра от корня проекта, …])] в порядке frames.tres."""
    text = open(os.path.join(ROOT, "assets", "sprites", unit, "frames.tres"), encoding="utf-8").read()
    ext = {i: p.replace("res://", "") for p, i in re.findall(r'path="([^"]+)" id="([^"]+)"', text)}
    body = text[text.find("animations = ["):]
    return [(name, [ext[i] for i in re.findall(r'ExtResource\("([^"]+)"\)', ids)]) for ids, name in ANIM_RE.findall(body)]


def export(folder):
    os.makedirs(folder, exist_ok=True)
    open(os.path.join(folder, ".gdignore"), "w").close()
    manifest = {}
    seen = {}   # исходный файл → имя выгрузки (кадр стоит в анимации дважды — один файл)
    for unit in unit_folders():
        for anim, paths in animations(unit):
            for n, src in enumerate(paths):
                if src in seen:
                    continue
                name = "%s_%s_%02d.png" % (unit, anim, n)
                shutil.copy2(os.path.join(ROOT, src), os.path.join(folder, name))
                manifest[name] = src
                seen[src] = name
    with open(os.path.join(folder, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1)
    print("выгружено %d кадров %d юнитов → %s" % (len(manifest), len(unit_folders()), folder))


def import_back(folder, force, dry):
    manifest = json.load(open(os.path.join(folder, "manifest.json"), encoding="utf-8"))
    changed, skipped = 0, 0
    for name, src in manifest.items():
        edited = os.path.join(folder, name)
        target = os.path.join(ROOT, src)
        if not os.path.exists(edited) or filecmp.cmp(edited, target, shallow=False):
            continue
        a, b = Image.open(edited).size, Image.open(target).size
        if a != b and not force:
            print("ПРОПУЩЕН %s: размер %s, а в игре %s (кадр должен остаться того же размера; --force — всё равно)" % (name, a, b))
            skipped += 1
            continue
        print("%s %s → %s" % ("будет" if dry else "загружен", name, src))
        if not dry:
            shutil.copy2(edited, target)
        changed += 1
    print("изменённых кадров: %d, пропущено: %d%s" % (changed, skipped,
        "" if dry or changed == 0 else ". Дальше: godot --headless --import"))


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args or args[0] not in ("export", "import"):
        print(__doc__)
        sys.exit(1)
    target = args[1] if len(args) > 1 else DEFAULT_DIR
    if args[0] == "export":
        export(target)
    else:
        import_back(target, "--force" in sys.argv, "--dry" in sys.argv)
