"""Весь визуал, который грузит игра, — копией в одну папку visual_export/ по категориям (решение пользователя
13.11.2026: «переработать ассеты, чтобы не попасть под IP — собери все элементы визуала в одну папку»).

Копируются картинки (.png/.jpg/.webp/.svg/.gif) и шрифты (.ttf/.otf) — без .import, .tres, архивов; внутри
категории — прежняя структура подпапок. Игра продолжает грузить со старых путей (копия, не перенос).
Не копируется то, что игра не грузит: assets/source_sheets/ (исходники художника), архивы, ChangeAsssets/,
citadel_sprite_list/, одиночные png в корне assets/.

Рядом — опись: INVENTORY.md (по папкам: сколько файлов, размер кадра, ряды анимаций, откуда) и inventory.csv
(строка на файл: путь в экспорте, исходный res:// путь, ширина × высота — по нему перерисованное возвращается
на место). В visual_export/ — .gdignore (Godot копии не импортирует); папка — в .gitignore.
Повторный прогон — папка собирается заново.

  python tools/collect_visuals.py
"""
import csv
import shutil
import sys
from collections import defaultdict
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets"
OUT = ROOT / "visual_export"
IMAGES = {".png", ".jpg", ".jpeg", ".webp", ".svg", ".gif"}
FONTS = {".ttf", ".otf"}
UI_ICONS = ["emblems", "races", "hud", "passives", "stats", "difficulty", "rarity", "ribbon", "banners", "cursor"]
SPRITES_MAP = ["tiles", "props", "map_sprite", "critters"]

# (категория, папка-источник от assets/, подпапка в категории, только шрифты / без шрифтов)
SOURCES = [
    ("01_units", "units/space_marines", "space_marines", None),
    ("01_units", "units/chaos", "chaos", None),
    ("02_bosses", "units/bosses", "", None),
    ("03_buildings", "sprites/buildings", "", None),
    *[("04_map", f"sprites/{d}", d, None) for d in SPRITES_MAP],
    ("05_cards", "ui/card_art", "card_art", None),
    ("05_cards", "ui/cards", "cards", None),
    *[("06_icons", f"ui/{d}", d, None) for d in UI_ICONS],
    ("08_effects", "effects", "effects", None),
    ("08_effects", "graded", "graded", None),
    ("08_effects", "Spritesheets", "Spritesheets", None),
    ("09_fonts", "fonts", "fonts", "fonts"),
    ("09_fonts", "ui/assets", "ui_assets", "fonts"),
    ("10_other", "FightFleed", "FightFleed", None),
    ("10_other", "chaos_assets", "chaos_assets", None),
    ("10_other", "flag", "flag", None),
]
TITLES = {
    "01_units": "Юниты игрока и врагов (кадры анимаций: папка ряда — idle / run / attack / death …)",
    "02_bosses": "Финальные боссы (демоны и примархи)",
    "03_buildings": "Здания обеих рас (ряды idle / attack / refill, уровни _2 / _3; chaos/ — версии Хаоса)",
    "04_map": "Поле боя: плиты, объекты, тайлсет, существа по краям",
    "05_cards": "Игральные карты: иллюстрации, рамки, масти, рубашки",
    "06_icons": "Значки: эмблемы орденов и богов, расы, шапка боя, пассивки, сложность, редкость, лента забега, курсоры",
    "07_ui": "Интерфейс: меню, магазин и продавец, панели, справки, экраны, события, атлас UI",
    "08_effects": "Эффекты и снаряды (+ перекрашенные копии graded/)",
    "09_fonts": "Шрифты",
    "10_other": "Прочее, что упоминается в коде",
}


def files_of(src: Path, kind):
    for p in sorted(src.rglob("*")):
        if not p.is_file() or "source_sheets" in p.parts:
            continue
        ext = p.suffix.lower()
        if kind == "fonts":
            if ext in FONTS:
                yield p
        elif ext in IMAGES or ext in FONTS:
            yield p


def main():
    if OUT.exists():
        if OUT.name != "visual_export":
            sys.exit("неожиданная папка вывода")
        shutil.rmtree(OUT)
    OUT.mkdir()
    (OUT / ".gdignore").write_text("", encoding="utf-8")
    sources = list(SOURCES)
    # остальное из assets/ui (меню, магазин, панели, справки, экраны, события, fx, атлас, корневые png)
    for d in sorted((ASSETS / "ui").iterdir()):
        if d.is_dir() and d.name not in UI_ICONS and d.name not in ("card_art", "cards"):
            sources.append(("07_ui", f"ui/{d.name}", d.name, None))
    sources.append(("07_ui", "ui", "_root", "root"))
    rows = []
    groups = defaultdict(list)   # (категория, подпапка группы) → [(dst, src, w, h)]
    found = defaultdict(int)
    for cat, rel, sub, kind in sources:
        src = ASSETS / rel
        if not src.exists():
            print(f"  нет {rel} — пропуск")
            continue
        it = [p for p in src.iterdir() if p.is_file() and p.suffix.lower() in IMAGES] if kind == "root" \
            else list(files_of(src, kind))
        if kind is None and rel == "ui/assets":
            it = [p for p in it if p.suffix.lower() in IMAGES]
        for p in it:
            found[cat] += 1
            dst = OUT / cat / sub / p.relative_to(src) if sub else OUT / cat / p.relative_to(src)
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(p, dst)
            w = h = ""
            if p.suffix.lower() in IMAGES and p.suffix.lower() != ".svg":
                try:
                    with Image.open(p) as im:
                        w, h = im.size
                except Exception:
                    pass
            r = dst.relative_to(OUT).as_posix()
            res = "res://" + p.relative_to(ROOT).as_posix()
            rows.append((r, res, w, h))
            # группа описи: юнит / здание — до папки ряда анимации; иначе — папка файла
            parts = Path(r).parts
            depth = {"01_units": 3, "02_bosses": 2, "03_buildings": 2}.get(cat, len(parts) - 1)
            if cat == "03_buildings" and len(parts) > 2 and parts[1] == "chaos":
                depth = 3
            key = "/".join(parts[:min(depth, len(parts) - 1)])
            groups[key].append((r, res, w, h))
    with open(OUT / "inventory.csv", "w", newline="", encoding="utf-8-sig") as f:
        wr = csv.writer(f, delimiter=";")
        wr.writerow(["файл в экспорте", "исходный путь в игре", "ширина", "высота"])
        wr.writerows(rows)
    _write_md(groups, len(rows))
    total = 0
    for cat in sorted(found):
        n = sum(1 for r in rows if r[0].startswith(cat + "/"))
        total += n
        print(f"{cat}: скопировано {n} / найдено {found[cat]}")
    print(f"всего файлов: {total} → {OUT}")


def _write_md(groups, total):
    lines = ["# Визуал игры — опись", "",
             f"Копия всего визуала, который грузит игра ({total} файлов), по категориям. Собрано "
             "`tools/collect_visuals.py`; исходный путь каждого файла — `inventory.csv` (по нему перерисованное "
             "кладётся на место). Исходники художника (`assets/source_sheets/`) сюда не входят.", ""]
    by_cat = defaultdict(list)
    for key in sorted(groups):
        by_cat[key.split("/")[0]].append(key)
    for cat in sorted(by_cat):
        n = sum(len(groups[k]) for k in by_cat[cat])
        lines += [f"## {cat} — {TITLES.get(cat, '')} ({n})", "",
                  "| папка | файлов | размер кадра | ряды / подпапки | откуда |", "|---|---|---|---|---|"]
        for key in by_cat[cat]:
            items = groups[key]
            sizes = sorted({f"{w}×{h}" for _, _, w, h in items if w})
            size = sizes[0] if len(sizes) == 1 else (f"{len(sizes)} размеров" if sizes else "—")
            subs = defaultdict(int)
            for r, _, _, _ in items:
                rest = Path(r).relative_to(key).parts
                subs[rest[0] if len(rest) > 1 else "."] += 1
            rows_txt = ", ".join(f"{s} {c}" if s != "." else f"{c} файл." for s, c in sorted(subs.items()))
            src = items[0][1].rsplit("/", 1)[0]   # строкой: Path схлопнул бы res:// в res:/
            if len(subs) > 1 or "." not in subs:
                src = src.rsplit("/", 1)[0]
            lines.append(f"| `{key}` | {len(items)} | {size} | {rows_txt} | `{src}` |")
        lines.append("")
    (OUT / "INVENTORY.md").write_text("\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    main()
