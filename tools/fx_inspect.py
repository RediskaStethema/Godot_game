"""Замер выравнивания листа эффекта: куда кадры «уезжают», где касаются края, куда ставить pivot.
Читает запись вида из Vfx.EFFECTS (или параметры руками), берёт тот же файл, что грузит игра (graded, если есть),
режет на кадры как Vfx._get_frames (сетка слева направо, сверху вниз, `from`, `frames`) и печатает по кадрам:
bbox эффекта, центр масс, самый нижний непрозрачный пиксель, касание краёв кадра. В конце — сводка (дрейф по кадрам,
срезы по краю, пустые хвосты) и подсказка pivot. Рядом кладёт контактный лист с перекрестием pivot.

  python tools/fx_inspect.py blood_1                       — вид из Vfx.EFFECTS
  python tools/fx_inspect.py fireball --out папка          — лист в другую папку (по умолчанию assets/source_sheets/contact_out)
  python tools/fx_inspect.py --sheet assets/effects/x/spritesheet.png --size 64x64 --frames 12 --pivot 32,56 [--from 0]
  python tools/fx_inspect.py blood_1 --pivot 47,50         — примерить другой pivot (в листе и подсказке)

Что значит вывод — в .claude/skills/effect-alignment/SKILL.md. Godot не нужен, только Pillow и numpy.
"""
import argparse
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
VFX = ROOT / "scripts/battle/Vfx.gd"
ALPHA_MIN = 24            # пиксель с альфой не ниже — «эффект» (слабый ореол листа не считаем)
EDGE_BAND = 2             # толщина полосы у края кадра, px
EDGE_TOUCH_PX = 3         # столько пикселей эффекта у кромки — эффект упирается в край (срез)
EDGE_ALPHA = 60           # у кромки считаем только плотное (как fx_edge_feather.py): уже затухающий край — не срез
DYING_SHARE = 0.35      # кадр с меньшей долей пикселей от самого плотного — «затухающий хвост»
DRIFT_WARN = 6.0          # дрейф центра масс / низа между кадрами больше этого (px кадра) — «плывёт»
CONSTS = {
    "SHEETS_DIR": "res://assets/Spritesheets/",
    "PIXEL_DIR": "res://assets/effects/Pixel/PNG_native/",
    "BLOOD_DIR": "res://assets/effects/NEw pack blood/",
    "FX_DIR": "res://assets/effects/",
    "STATUS_DIR": "res://assets/effects/status/",
    "GRADED_DIR": "res://assets/graded/",
}


def resolve_sheet(expr: str) -> str:
    """`BLOOD_DIR + "1.png"` / `"Blood Splat.png"` / `"res://..."` → res:// путь (как Vfx._sheet_path)."""
    out = ""
    for p in re.findall(r'"[^"]*"|\w+', expr):          # части склеены "+", а "+" бывает и в имени файла
        out += p.strip('"') if p.startswith('"') else CONSTS.get(p, "")
    if not out.startswith("res://"):
        out = CONSTS["SHEETS_DIR"] + out
    return out


def load_entry(kind: str) -> dict:
    text = VFX.read_text(encoding="utf-8")
    m = re.search(r'"%s":\s*\{(.*?)\}' % re.escape(kind), text, re.S)
    if not m:
        sys.exit("вид %r не найден в Vfx.EFFECTS" % kind)
    body = m.group(1)

    def vec(name):
        v = re.search(r'"%s":\s*Vector2i?\(\s*([-\d.]+),\s*([-\d.]+)\)' % name, body)
        return (float(v.group(1)), float(v.group(2))) if v else None

    sheet = re.search(r'"sheet":\s*([^,\n]+?)\s*,', body)
    frames = re.search(r'"frames":\s*(\d+)', body)
    start = re.search(r'"from":\s*(\d+)', body)
    flags = [k for k in ("add", "loop", "hold", "flat", "behind") if re.search(r'"%s":\s*true' % k, body)]
    return {"sheet": resolve_sheet(sheet.group(1)), "size": vec("size"), "pivot": vec("pivot"),
            "frames": int(frames.group(1)) if frames else 1, "from": int(start.group(1)) if start else 0,
            "frame": vec("frame"), "flags": flags,
            "scale": float(re.search(r'"scale":\s*([\d.]+)', body).group(1)) if re.search(r'"scale":\s*([\d.]+)', body) else 1.0}


def sheet_file(res_path: str) -> Path:
    rel = res_path.removeprefix("res://")
    graded = ROOT / "assets/graded" / rel.removeprefix("assets/")
    if rel.startswith("assets/") and not rel.startswith("assets/graded/") and graded.exists():
        return graded                      # игра берёт перекрашенный лист (Vfx.graded_path)
    return ROOT / rel


def cut_frames(img: Image.Image, size, start, count):
    w, h = int(size[0]), int(size[1])
    cols = max(img.width // w, 1)
    frames = []
    for i in range(start, start + count):
        x, y = (i % cols) * w, (i // cols) * h
        if y + h > img.height:
            break
        frames.append(img.crop((x, y, x + w, y + h)))
    return frames


def measure(frame: Image.Image):
    a = np.asarray(frame.convert("RGBA"))[..., 3]
    mask = a >= ALPHA_MIN
    n = int(mask.sum())
    if n == 0:
        return None
    ys, xs = np.nonzero(mask)
    wts = a[mask].astype(np.float64)
    h, w = a.shape
    dense = a >= EDGE_ALPHA
    edges = {"L": int(dense[:, :EDGE_BAND].sum()), "R": int(dense[:, -EDGE_BAND:].sum()),
             "T": int(dense[:EDGE_BAND, :].sum()), "B": int(dense[-EDGE_BAND:, :].sum())}
    return {"n": n, "box": (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())),
            "bx": float(xs.min() + xs.max()) / 2.0, "by": float(ys.min() + ys.max()) / 2.0,
            "cx": float((xs * wts).sum() / wts.sum()), "cy": float((ys * wts).sum() / wts.sum()),
            "bottom": int(ys.max()), "touch": "".join(k for k, v in edges.items() if v >= EDGE_TOUCH_PX)}


def contact_sheet(frames, ms, pivot, size, path: Path):
    w, h = int(size[0]), int(size[1])
    z = max(1, min(4, 256 // max(w, h)))
    cols = min(len(frames), 8)
    rows = (len(frames) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * w * z, rows * (h * z + 14)), (46, 50, 62, 255))
    d = ImageDraw.Draw(sheet)
    for i, (f, m) in enumerate(zip(frames, ms)):
        ox, oy = (i % cols) * w * z, (i // cols) * (h * z + 14)
        cell = Image.new("RGBA", (w, h), (30, 33, 42, 255))
        cell.alpha_composite(f.convert("RGBA"))
        sheet.paste(cell.resize((w * z, h * z), Image.NEAREST), (ox, oy + 14))
        d.rectangle((ox, oy + 14, ox + w * z - 1, oy + 14 + h * z - 1), outline=(90, 96, 112))
        d.text((ox + 2, oy + 1), str(i), fill=(230, 230, 220))
        if m:
            x0, y0, x1, y1 = m["box"]
            d.rectangle((ox + x0 * z, oy + 14 + y0 * z, ox + (x1 + 1) * z - 1, oy + 14 + (y1 + 1) * z - 1), outline=(80, 200, 120))
            if m["touch"]:
                d.text((ox + w * z - 6 * len(m["touch"]) - 4, oy + 1), m["touch"], fill=(240, 90, 70))
        px, py = ox + pivot[0] * z, oy + 14 + pivot[1] * z
        d.line((px - 6, py, px + 6, py), fill=(255, 60, 60))     # красный крест — точка, что встанет в позицию эффекта
        d.line((px, py - 6, px, py + 6), fill=(255, 60, 60))
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("kind", nargs="?")
    ap.add_argument("--sheet")
    ap.add_argument("--size")
    ap.add_argument("--frames", type=int)
    ap.add_argument("--from", dest="start", type=int)
    ap.add_argument("--pivot")
    ap.add_argument("--out", default=str(ROOT / "assets/source_sheets/contact_out"))
    a = ap.parse_args()
    if a.kind:
        e = load_entry(a.kind)
        name = a.kind
    elif a.sheet and a.size:
        sw, sh = a.size.lower().split("x")
        e = {"sheet": "res://" + a.sheet.replace("\\", "/").removeprefix("res://"), "size": (float(sw), float(sh)),
             "pivot": None, "frames": a.frames or 1, "from": 0, "frame": None, "flags": [], "scale": 1.0}
        name = Path(a.sheet).stem
    else:
        ap.error("нужен вид из Vfx.EFFECTS или --sheet и --size")
    if a.frames:
        e["frames"] = a.frames
    if a.start is not None:
        e["from"] = a.start
    if a.pivot:
        px, py = a.pivot.split(",")
        e["pivot"] = (float(px), float(py))
    if e["pivot"] is None:
        e["pivot"] = (e["size"][0] / 2, e["size"][1] / 2)
    path = sheet_file(e["sheet"])
    if not path.exists():
        sys.exit("нет файла %s" % path)
    img = Image.open(path).convert("RGBA")
    size = e["size"]
    # Перекрашенный лист бывает крупнее исходного (vfx_grade.py paint, ×4): как Vfx._get_frames, кадр и pivot — ×k
    orig = ROOT / e["sheet"].removeprefix("res://")
    if path != orig and orig.exists():
        k = max(1, round(img.width / Image.open(orig).width))
        if k > 1:
            size = (size[0] * k, size[1] * k)
            e["pivot"] = (e["pivot"][0] * k, e["pivot"][1] * k)
            print("лист в graded крупнее исходного в %d раза — размеры кадра и pivot ниже в пикселях graded (×%d)" % (k, k))
    frames = cut_frames(img, size, e["from"], e["frames"])
    ms = [measure(f) for f in frames]
    print("%s: %s  лист %dx%d  кадр %dx%d  from %d  кадров %d (вырезано %d)  pivot %s  флаги %s" % (
        name, path.relative_to(ROOT), img.width, img.height, size[0], size[1], e["from"], e["frames"], len(frames),
        e["pivot"], ",".join(e["flags"]) or "-"))
    if img.width % int(size[0]) or img.height % int(size[1]):
        print("  !! размер листа не кратен кадру — сетка в Vfx.EFFECTS (size) не совпадает с файлом")
    print("  кадр  bbox(x0,y0..x1,y1)   центр масс      низ  px    касание")
    for i, m in enumerate(ms):
        if m is None:
            print("  %3d   пусто" % i)
            continue
        print("  %3d   %3d,%3d..%3d,%3d     %6.1f,%6.1f   %3d  %5d  %s" % (
            i, *m["box"], m["cx"], m["cy"], m["bottom"], m["n"], m["touch"] or "-"))
    ok = [m for m in ms if m]
    if not ok:
        sys.exit("все кадры пусты — не тот файл / сетка")
    # Затухающий хвост (кадры, где эффект почти выгорел: < DYING_SHARE плотных пикселей) в дрейф рамки не считается —
    # у сгорающих эффектов (card_sell) рамка сужается с одного края законно
    biggest = max(m["n"] for m in ok)
    bxs = [m["bx"] for m in ok if m["n"] >= DYING_SHARE * biggest] or [m["bx"] for m in ok]
    cxs = [m["cx"] for m in ok]
    cys = [m["cy"] for m in ok]
    bots = [m["bottom"] for m in ok]
    empty_tail = 0
    for m in reversed(ms):
        if m is None:
            empty_tail += 1
        else:
            break
    first_empty = [i for i, m in enumerate(ms) if m is None and i < len(ms) - empty_tail]
    print("\nСВОДКА")
    print("  дрейф центра масс: x %.1f px, y %.1f px; центр рамки по x %.1f px; низ эффекта: %d..%d (разброс %d)" % (
        max(cxs) - min(cxs), max(cys) - min(cys), max(bxs) - min(bxs), min(bots), max(bots), max(bots) - min(bots)))
    print("  (брызги, дым и взрыв расширяются — центр масс у них плывёт законно; смотри на лист: стоит ли эффект на pivot)")
    problems = []
    if max(bxs) - min(bxs) > DRIFT_WARN:
        problems.append("центр рамки эффекта гуляет по x на %.0f px — кадры сдвинуты сеткой? (fx_fix.py center / segments)" %
                        (max(bxs) - min(bxs)))
    if len(ok) > 2 and (bots[-1] - bots[0]) > 3 * DRIFT_WARN and all(b2 >= b1 - 1 for b1, b2 in zip(bots, bots[1:])):
        problems.append("низ эффекта ползёт вниз от кадра к кадру на %d px — съезд сетки или завёрнутый кусок (fx_fix.py bottom)" %
                        (bots[-1] - bots[0]))
    touched = {}
    for i, m in enumerate(ms):
        if m and m["touch"]:
            for k in m["touch"]:
                touched.setdefault(k, []).append(i)
    for k, idx in touched.items():
        name_k = {"L": "левый", "R": "правый", "T": "верхний", "B": "нижний"}[k]
        problems.append("упирается в %s край кадров %s — на экране ровный срез (fx_edge_feather.py или расширить холст)" % (
            name_k, idx if len(idx) <= 8 else "%s…(%d)" % (idx[:6], len(idx))))
    if empty_tail:
        problems.append("пустой хвост %d кадров — уменьшить frames в Vfx.EFFECTS (иначе эффект «висит» невидимым)" % empty_tail)
    if first_empty:
        problems.append("пустые кадры внутри ряда %s — лист собран с дырами" % first_empty)
    for p in problems:
        print("  !! " + p)
    if not problems:
        print("  выравнивание ровное, срезов нет")
    med_cx = float(np.median(cxs))
    med_bot = float(np.median(bots))
    med_cy = float(np.median(cys))
    print("  подсказка pivot: у земли (ноги / удар по земле) ≈ (%.0f, %.0f); по центру массы ≈ (%.0f, %.0f); текущий %s" % (
        med_cx, med_bot, med_cx, med_cy, e["pivot"]))
    out = Path(a.out) / ("fx_%s.png" % name)
    contact_sheet(frames, ms, e["pivot"], size, out)
    print("  лист: %s  (зелёная рамка — bbox, красный крест — pivot, красные буквы — касание краёв кадра)" % out)


if __name__ == "__main__":
    main()
