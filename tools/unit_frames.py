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

--buildings — то же для зданий (assets/sprites/buildings/<тип> и chaos/<тип>, по умолчанию
assets/source_sheets/building_frames, имена <тип>_… / chaos_<тип>_…). Лист стены (wall) не выгружается — стену
владений рисует KingdomWall. Низ кадра здания — не точка опоры: основание ищет Building.find_base по силуэту,
так что размер холста тоже держать прежним.

--citadels — кадры цитаделей рас (FactionTheme "citadel": лист сеткой "sheet", "frame_size", "rows"), по умолчанию
в assets/source_sheets/citadel_frames, имена <раса>_<анимация>_NN.png. Выгружаются только кадры, которые играет
игра; загрузка вписывает правленый кадр обратно в его ячейку листа (ячейка очищается, кадр — того же размера:
по ячейке стоят основание "anchor" и ствол "muzzle").
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
DEFAULT_BUILDINGS_DIR = os.path.join(ROOT, "assets", "source_sheets", "building_frames")
BUILDINGS = os.path.join("assets", "sprites", "buildings")
UNUSED_BUILDINGS = ("wall",)   # стена владений рисуется кодом (KingdomWall)
DEFAULT_CITADELS_DIR = os.path.join(ROOT, "assets", "source_sheets", "citadel_frames")
THEME = os.path.join(ROOT, "scripts", "data", "FactionTheme.gd")
FACTORY = os.path.join(ROOT, "scripts", "data", "UnitFactory.gd")
ANIM_RE = re.compile(r'\{\n"frames": \[(.*?)\],\n"loop": \w+,\n"name": &"(\w+)",', re.S)


def unit_folders():
    """Папки спрайтов, на которые ссылаются юниты (UnitFactory.sprite_path), по алфавиту."""
    text = open(FACTORY, encoding="utf-8").read()
    names = sorted(set(re.findall(r'res://assets/sprites/([a-z_]+)"', text)))
    return [n for n in names if os.path.exists(os.path.join(ROOT, "assets", "sprites", n, "frames.tres"))]


def building_folders():
    """Папки спрайтов зданий от assets/sprites (buildings/tower, buildings/chaos/tower), по алфавиту."""
    found = []
    for sub in ("", "chaos"):
        base = os.path.join(ROOT, BUILDINGS, sub)
        for name in sorted(os.listdir(base)):
            if name in UNUSED_BUILDINGS or not os.path.exists(os.path.join(base, name, "frames.tres")):
                continue
            found.append("/".join(p for p in ("buildings", sub, name) if p))
    return found


def animations(unit):
    """[(анимация, [путь кадра от корня проекта, …])] в порядке frames.tres."""
    text = open(os.path.join(ROOT, "assets", "sprites", unit, "frames.tres"), encoding="utf-8").read()
    ext = {i: p.replace("res://", "") for p, i in re.findall(r'path="([^"]+)" id="([^"]+)"', text)}
    body = text[text.find("animations = ["):]
    return [(name, [ext[i] for i in re.findall(r'ExtResource\("([^"]+)"\)', ids)]) for ids, name in ANIM_RE.findall(body)]


def citadels():
    """[(раса, путь листа от корня, (ширина, высота кадра), {анимация: (ряд, кадров)})] из FactionTheme.gd."""
    text = open(THEME, encoding="utf-8").read()
    consts = dict(re.findall(r'^const (\w+) = "res://([^"]+)"', text, re.M))
    found = []
    for race, body in re.findall(r'^	"(\w+)": \{(.*?)^	\},?$', text, re.M | re.S):
        m = re.search(r'"citadel": \{"sheet": (\w+) \+ "([^"]+)", "frame_size": Vector2i\((\d+), (\d+)\)(.*?)"rows": \{(.*?)\}\}', body, re.S)
        if not m:
            continue
        rows = {a: (int(r), int(n)) for a, r, n in re.findall(r'"(\w+)": \[(\d+), (\d+)', m.group(6))}
        found.append((race, consts[m.group(1)] + m.group(2), (int(m.group(3)), int(m.group(4))), rows))
    return found


def export_citadels(folder):
    os.makedirs(folder, exist_ok=True)
    open(os.path.join(folder, ".gdignore"), "w").close()
    manifest = {}
    for race, sheet, (fw, fh), rows in citadels():
        img = Image.open(os.path.join(ROOT, sheet)).convert("RGBA")
        for anim, (row, count) in rows.items():
            for i in range(count):
                name = "%s_%s_%02d.png" % (race, anim, i)
                rect = [i * fw, row * fh, fw, fh]
                img.crop((rect[0], rect[1], rect[0] + fw, rect[1] + fh)).save(os.path.join(folder, name))
                manifest[name] = {"sheet": sheet, "rect": rect}
    with open(os.path.join(folder, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1)
    print("выгружено %d кадров %d цитаделей → %s" % (len(manifest), len(citadels()), folder))


def import_citadels(folder, dry):
    manifest = json.load(open(os.path.join(folder, "manifest.json"), encoding="utf-8"))
    sheets, changed, skipped = {}, 0, 0
    for name, entry in manifest.items():
        path = os.path.join(folder, name)
        if not os.path.exists(path):
            continue
        sheet = entry["sheet"]
        if sheet not in sheets:
            sheets[sheet] = Image.open(os.path.join(ROOT, sheet)).convert("RGBA")
        x, y, w, h = entry["rect"]
        edited = Image.open(path).convert("RGBA")
        if edited.size != (w, h):
            print("ПРОПУЩЕН %s: размер %s, а ячейка %s" % (name, edited.size, (w, h)))
            skipped += 1
            continue
        if edited.tobytes() == sheets[sheet].crop((x, y, x + w, y + h)).tobytes():
            continue
        print("%s %s → %s %s" % ("будет" if dry else "загружен", name, sheet, entry["rect"]))
        sheets[sheet].paste((0, 0, 0, 0), (x, y, x + w, y + h))
        sheets[sheet].paste(edited, (x, y))
        changed += 1
    if not dry:
        for sheet, img in sheets.items():
            img.save(os.path.join(ROOT, sheet))
    print("изменённых кадров: %d, пропущено: %d%s" % (changed, skipped,
        "" if dry or changed == 0 else ". Дальше: godot --headless --import"))


def export(folder, folders):
    os.makedirs(folder, exist_ok=True)
    open(os.path.join(folder, ".gdignore"), "w").close()
    manifest = {}
    seen = {}   # исходный файл → имя выгрузки (кадр стоит в анимации дважды — один файл)
    for unit in folders:
        prefix = unit.replace("buildings/", "").replace("/", "_")
        for anim, paths in animations(unit):
            for n, src in enumerate(paths):
                if src in seen:
                    continue
                name = "%s_%s_%02d.png" % (prefix, anim, n)
                shutil.copy2(os.path.join(ROOT, src), os.path.join(folder, name))
                manifest[name] = src
                seen[src] = name
    with open(os.path.join(folder, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1)
    print("выгружено %d кадров из %d папок → %s" % (len(manifest), len(folders), folder))


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
    buildings = "--buildings" in sys.argv
    if "--citadels" in sys.argv:
        target = args[1] if len(args) > 1 else DEFAULT_CITADELS_DIR
        if args[0] == "export":
            export_citadels(target)
        else:
            import_citadels(target, "--dry" in sys.argv)
        sys.exit(0)
    target = args[1] if len(args) > 1 else (DEFAULT_BUILDINGS_DIR if buildings else DEFAULT_DIR)
    if args[0] == "export":
        export(target, building_folders() if buildings else unit_folders())
    else:
        import_back(target, "--force" in sys.argv, "--dry" in sys.argv)
