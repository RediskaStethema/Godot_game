"""Арт игральных карт — в рабочую папку для доработки и обратно (решение пользователя 10.11.2026: «хочу улучшить арты
карт — собери их все в одну папку»).

    python tools/card_art_work.py export <cards.json>    # всё в assets/source_sheets/card_art_work/
    python tools/card_art_work.py import [--dry]         # правленые — обратно в assets/ui/card_art/

cards.json — список карт из игры [{id, title, rarity, type, factions}] (выгрузка CardFactory.test_cards обеих рас).
export:
- cards/<раса>/<тип>/<id>.png — иллюстрация (копия assets/ui/card_art/<id>.png; раса both — карта есть у обеих);
- preview/<раса>/<тип>/<id>.png — карта как в игре: арт в окне рамки своей редкости (UITheme.make_card_face:
  окно CARD_FRAME_LAYOUT + запас CARD_ART_BLEED, арт «по большей стороне», рамка поверх) — видно, что срезано;
- ui/ — рамки редкости, значки мастей, рубашки рас (те же имена, что в игре);
- CARDS.md — таблица: id, название, редкость, тип, раса, видимая часть арта; README.txt — требования;
- manifest.json — рабочий файл → игровой файл и контрольная сумма при выгрузке (import сравнивает с ней).
import: файл отличается от выгруженного → проверка (PNG 360×504, у значков мастей — их размер) → копия в игру;
потом `godot --headless --import`. Новая карта / новый id — не сюда: сначала карта в CardFactory.
"""
import hashlib
import json
import shutil
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
GAME = ROOT / "assets/ui/card_art"
WORK = ROOT / "assets/source_sheets/card_art_work"
ART_SIZE = (360, 504)
# Как в UITheme: окно рамки под иллюстрацию по редкости и запас под брусья
WINDOW = {"common": (38, 54, 284, 402), "rare": (35, 78, 289, 371), "epic": (50, 85, 259, 328)}
BLEED = 10
UI_FILES = ["frame_common", "frame_rare", "frame_epic", "suit_squad", "suit_building", "suit_upgrade", "suit_event",
            "back_space_marines", "back_chaos"]
RACE = {("space_marines",): "space_marines", ("chaos",): "chaos"}
TYPE_RU = {"squad": "отряд", "building": "здание", "upgrade": "улучшение", "event": "событие"}
RARITY_RU = {"common": "Common", "rare": "Rare", "epic": "Epic"}


def md5(p):
    return hashlib.md5(Path(p).read_bytes()).hexdigest()


def visible(rarity):
    """Какая часть арта 360×504 видна в окне рамки: прямоугольник в px арта (x, y, w, h)."""
    x, y, w, h = WINDOW.get(rarity, WINDOW["common"])
    w, h = w + 2 * BLEED, h + 2 * BLEED
    s = max(w / ART_SIZE[0], h / ART_SIZE[1])
    vw, vh = w / s, h / s
    return ((ART_SIZE[0] - vw) / 2, (ART_SIZE[1] - vh) / 2, vw, vh), s


def preview(art_path, rarity):
    x, y, w, h = WINDOW.get(rarity, WINDOW["common"])
    cx, cy, cw, ch = x - BLEED, y - BLEED, w + 2 * BLEED, h + 2 * BLEED
    (vx, vy, vw, vh), s = visible(rarity)
    art = Image.open(art_path).convert("RGBA").crop((round(vx), round(vy), round(vx + vw), round(vy + vh)))
    art = art.resize((cw, ch), Image.LANCZOS)
    out = Image.new("RGBA", ART_SIZE, (0, 0, 0, 0))
    out.paste(art, (cx, cy))
    frame = GAME / ("frame_%s.png" % rarity)
    if frame.exists():
        out.alpha_composite(Image.open(frame).convert("RGBA"))
    return out


def export(cards_json):
    cards = json.loads(Path(cards_json).read_text(encoding="utf-8"))
    if WORK.exists():
        sys.exit("уже есть %s — сначала import или удалить папку (правки не затираются)" % WORK)
    (WORK / "ui").mkdir(parents=True)
    (WORK / ".gdignore").write_text("")
    manifest = {}
    rows = []
    for c in sorted(cards, key=lambda c: (tuple(c["factions"]), c["type"], c["rarity"], c["id"])):
        race = RACE.get(tuple(c["factions"]), "both")
        rel = Path("cards") / race / c["type"] / (c["id"] + ".png")
        src = GAME / (c["id"] + ".png")
        (WORK / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, WORK / rel)
        manifest[str(rel).replace("\\", "/")] = {"game": c["id"] + ".png", "md5": md5(src)}
        pv = Path("preview") / race / c["type"] / (c["id"] + ".png")
        (WORK / pv).parent.mkdir(parents=True, exist_ok=True)
        preview(src, c["rarity"]).save(WORK / pv)
        (vx, vy, vw, vh), _ = visible(c["rarity"])
        rows.append("| %s | %s | %s | %s | %s | x %d–%d, y %d–%d |" % (
            c["id"], c["title"], RARITY_RU.get(c["rarity"], c["rarity"]), TYPE_RU.get(c["type"], c["type"]),
            {"space_marines": "Космодесант", "chaos": "Хаос", "both": "обе"}[race],
            vx, vx + vw, vy, vy + vh))
    for name in UI_FILES:
        src = GAME / (name + ".png")
        rel = Path("ui") / (name + ".png")
        shutil.copy2(src, WORK / rel)
        manifest[str(rel).replace("\\", "/")] = {"game": name + ".png", "md5": md5(src)}
    (WORK / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1), encoding="utf-8")
    head = ["# Карты WH40KINGS — %d иллюстраций" % len(rows), "",
            "Видимая часть — область арта 360×504, которая попадает в окно рамки (по краям её закрывает рамка; "
            "превью — preview/).", "",
            "| id | Название | Редкость | Тип | Раса | Видимая часть арта |", "|---|---|---|---|---|---|"]
    (WORK / "CARDS.md").write_text("\n".join(head + rows) + "\n", encoding="utf-8")
    print("выгружено: %d карт + %d файлов интерфейса → %s" % (len(rows), len(UI_FILES), WORK))


def check(path, game_name):
    im = Image.open(path)
    want = Image.open(GAME / game_name).size
    if im.size != want:
        return "размер %s, нужен %s" % (im.size, want)
    if im.mode not in ("RGBA", "RGB", "P"):
        return "формат %s" % im.mode
    return ""


def do_import(dry):
    manifest = json.loads((WORK / "manifest.json").read_text(encoding="utf-8"))
    changed, bad = 0, 0
    for rel, m in manifest.items():
        p = WORK / rel
        if not p.exists() or md5(p) == m["md5"]:
            continue
        err = check(p, m["game"])
        if err:
            print("ПРОПУЩЕН %s: %s" % (rel, err))
            bad += 1
            continue
        print(("будет: " if dry else "") + "%s → assets/ui/card_art/%s" % (rel, m["game"]))
        if not dry:
            Image.open(p).convert("RGBA").save(GAME / m["game"])
            m["md5"] = md5(p)
        changed += 1
    if not dry:
        (WORK / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1), encoding="utf-8")
    print("правленых: %d, пропущено: %d%s" % (changed, bad, " (проверка, ничего не записано)" if dry else
                                                 "; дальше — godot --headless --path . --import"))


if __name__ == "__main__":
    if sys.argv[1] == "export":
        export(sys.argv[2])
    else:
        do_import("--dry" in sys.argv)
