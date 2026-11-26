"""Размер модельки не прыгает при смене кадров (17.11.2026, решение пользователя: «у части ассетов прыгает размер моделек при
смене фреймов»). Кадры рядов walk / attack масштабируются вокруг ног к размеру тела стойки: размер — площадь «тела»
(`unit_rescale.body_area`: тёмные непрозрачные пиксели, вспышки и свечение не в счёт), эталон — медиана кадров idle; масштаб
кадра √(эталон / площадь), не больше ±MAX_K, ближе KEEP к 1 не трогается; кадр, который от масштаба вылез бы за холст, не
трогается (печатается). Ряд правится, только если хоть один кадр выходит за TRIGGER. Ствол (`metadata/muzzle`) на кадре выстрела
пересчитывается. В отличие от `unit_rescale.py <ряд>:even` (эталон — 1-й кадр ряда: у замаха он самый мелкий) эталон — стойка.
Не идемпотентно по смыслу, но повторный прогон ничего не меняет (кадры уже в пределах KEEP).

  python tools/unit_size_lock.py [--dry] [--rows walk,attack] assets/units/chaos/lord [...]   (без папок — все юниты)
затем godot --headless --path . --import
"""
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import unit_rescale as ur  # noqa: E402

ROOT = ur.ROOT
MAX_K = 1.15
KEEP = 0.03
TRIGGER = 0.06
SKIP = {"bosses/daemon_angron"}   # нет ряда стойки на общем холсте — при необходимости вручную


def lock(folder: Path, rows, dry):
    tres = folder / "frames.tres"
    raw = tres.read_bytes().decode("utf-8")
    crlf = "\r\n" in raw
    text = orig = raw.replace("\r\n", "\n")
    try:
        idle = [ur.body_area(Image.open(f).convert("RGBA")) for f in ur.frame_files(text, "idle")]
    except SystemExit:
        return 0
    target = float(np.median(idle))
    if target <= 0:
        return 0
    shot = re.search(r"metadata/shot_frame = (\d+)", text)
    shot = int(shot.group(1)) if shot else -1
    changed = 0
    for anim in rows:
        try:
            files = ur.frame_files(text, anim)
        except SystemExit:
            continue
        ks = []
        for f in files:
            a = ur.body_area(Image.open(f).convert("RGBA"))
            ks.append(float(np.clip((target / max(a, 1)) ** 0.5, 1 / MAX_K, MAX_K)))
        if max(abs(k - 1.0) for k in ks) <= TRIGGER:
            continue
        done = {}
        for n, (f, k) in enumerate(zip(files, ks)):
            if f in done:
                if anim == "attack" and n == shot:
                    text = ur.move_muzzle(tres, text, img_size, *done[f])
                continue
            if abs(k - 1.0) < KEEP:
                continue
            img = Image.open(f).convert("RGBA")
            if not (np.array(img)[..., 3] > 40).any():
                continue
            p = ur.feet(img)
            out = ur.scale_about(img, k, p)
            a = np.array(out)[..., 3] > 40
            if a[0].any() or a[:, 0].any() or a[:, -1].any():
                print("  %s/%s: ×%.3f пропущен — вылез бы за холст" % (anim, f.name, k))
                continue
            print("  %s/%s: ×%.3f" % (anim, f.name, k))
            if dry:
                continue
            out.save(f)
            done[f] = (k, p)
            img_size = img.size
            changed += 1
            if anim == "attack" and n == shot:
                text = ur.move_muzzle(tres, text, img.size, k, p)
    if not dry and text != orig:
        tres.write_bytes((text.replace("\n", "\r\n") if crlf else text).encode("utf-8"))
    return changed


def main(args):
    dry = "--dry" in args
    rows = ["walk", "attack"]
    if "--rows" in args:
        rows = args[args.index("--rows") + 1].split(",")
    dirs = [Path(a).resolve() for a in args if not a.startswith("--") and "/" in a.replace("\\", "/")]
    if not dirs:
        dirs = sorted(p.parent for p in (ROOT / "assets/units").glob("*/*/frames.tres"))
    total = 0
    for d in dirs:
        rel = d.relative_to(ROOT / "assets/units").as_posix()
        if rel in SKIP:
            continue
        print(rel)
        total += lock(d, rows, dry)
    print("кадров изменено: %d" % total)


if __name__ == "__main__":
    main(sys.argv[1:])
