"""Контактные листы для быстрого просмотра кадров (16.11.2026; сводит одноразовые скрипты сессии перерисовки).

  python tools/contact_sheet.py unit <юнит> [<юнит> ...] [--out папка]      assets/units/space_marines/<юнит>
  python tools/contact_sheet.py building <здание> [...] [--out папка]       assets/sprites/buildings/<здание>

Лист юнита: ряды idle, run, attack, death — все кадры подряд; на каждом кадре линия земли (низ холста — туда Soldier ставит ноги)
и тень под ногами (в беге видно, висят ли ноги); на attack — зелёная точка ствола (metadata/muzzle), красная рамка кадра выстрела
(metadata/shot_frame). Лист здания: все ряды (idle, attack, idle_2, …) по уровням, линия земли — низ силуэта 1-го кадра idle.
По умолчанию листы — в assets/source_sheets/contact_out (внутри source_sheets, с .gdignore). Читает .tres как текст, Godot не нужен.
"""
import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
BG = (46, 50, 62)
TH = 150


def meta(tres: Path):
    t = tres.read_text(encoding="utf-8") if tres.exists() else ""
    shot = re.search(r"shot_frame = (\d+)", t)
    mz = re.search(r"metadata/muzzle = Vector2\(([-\d.]+), ([-\d.]+)\)", t)
    return (int(shot.group(1)) if shot else None), ((float(mz.group(1)), float(mz.group(2))) if mz else None)


def frames(folder: Path) -> list:
    return [Image.open(f).convert("RGBA") for f in sorted(folder.glob("*.png"), key=lambda p: int(p.stem))]


def row(ims: list, anim: str, shot, muzzle) -> Image.Image:
    sc = TH / max(i.size[1] for i in ims)
    widths = [int(i.size[0] * sc) for i in ims]
    out = Image.new("RGB", (sum(widths) + 3 * len(ims), TH + 20), BG)
    d = ImageDraw.Draw(out)
    x = 0
    for n, (im, w) in enumerate(zip(ims, widths)):
        t = im.resize((w, int(im.size[1] * sc)), Image.NEAREST)
        base = TH + 10
        d.ellipse((x + w // 2 - 20, base - 7, x + w // 2 + 20, base + 5), fill=(28, 28, 34))   # тень под ногами
        out.paste(t, (x, base - t.size[1]), t)
        d.line((x, base, x + w, base), fill=(255, 220, 90))                                   # земля — низ холста
        if anim == "attack" and muzzle:
            mx = x + (muzzle[0] + im.size[0] / 2) * sc
            my = base - t.size[1] + (muzzle[1] + im.size[1]) * sc
            d.ellipse((mx - 3, my - 3, mx + 3, my + 3), outline=(0, 255, 0), width=2)
        if anim == "attack" and shot == n:
            d.rectangle((x, 0, x + w - 1, TH + 19), outline=(255, 60, 60), width=2)
        x += w + 3
    return out


def sheet(rows: list, path: Path) -> None:
    W = max(r.size[0] for r in rows)
    out = Image.new("RGB", (W, sum(r.size[1] for r in rows)), BG)
    y = 0
    for r in rows:
        out.paste(r, (0, y))
        y += r.size[1]
    path.parent.mkdir(parents=True, exist_ok=True)
    out.save(path, quality=90)
    print(path)


def unit(name: str, outdir: Path) -> None:
    folder = ROOT / "assets/units/space_marines" / name
    shot, mz = meta(folder / "frames.tres")
    rows = [row(frames(folder / a), a, shot, mz) for a in ("idle", "run", "attack", "death") if (folder / a).exists()]
    sheet(rows, outdir / f"unit_{name}.jpg")


def building(name: str, outdir: Path) -> None:
    folder = ROOT / "assets/sprites/buildings" / name
    shot, mz = meta(folder / "frames.tres")
    rows = []
    for a in sorted((p.name for p in folder.iterdir() if p.is_dir()), key=lambda s: (s.split("_")[-1] if "_" in s else "1", s)):
        rows.append(row(frames(folder / a), "attack" if a.startswith("attack") else a, shot, mz))
    sheet(rows, outdir / f"building_{name}.jpg")


def main(argv: list) -> None:
    outdir = ROOT / "assets/source_sheets/contact_out"
    if "--out" in argv:
        i = argv.index("--out")
        outdir = Path(argv[i + 1])
        argv = argv[:i] + argv[i + 2:]
    if len(argv) < 2 or argv[0] not in ("unit", "building"):
        sys.exit(__doc__)
    for n in argv[1:]:
        (unit if argv[0] == "unit" else building)(n, outdir)


if __name__ == "__main__":
    main(sys.argv[1:])
