"""Кадры модельки — на месте: корпус по x на корпус эталонного кадра стойки, нижний пиксель — на землю (низ холста).

Решение пользователя 07.11.2026: «Firedrakes и Thunderwolf всё ещё слишком дёрганые и оторваны от земли».
Брак листов (замер по кадрам): Thunderwolf — стойка ±3 px, бег уезжает на 14 px и подпрыгивает до 11 px над
землёй, атака мечется на 45 px и висит на 7–17 px; Firedrakes — стойка уезжает на 13 px, бег подскакивает
0 / 4 / 6 px вразнобой каждый кадр. Игра ставит модельку низом холста на точку бойца (Soldier: offset −h/2),
так что зазор под ногами — висит, сдвиг корпуса между кадрами — дёргается.

Корпус — средний x непрозрачных пикселей в полосе TORSO (доли роста силуэта сверху): ноги в беге расходятся,
корпус — нет. Эталон — 1-й кадр стойки, как его играет игра (frames.tres). Холст и размер не меняются (по холсту
Soldier считает рост); что уходит за край — печатается. Ствол (metadata/muzzle) — у ряда атаки; ряд атаки
стрелка не трогать (--anims без attack). Исходники — STASH/<папка юнита>/ (повторный прогон берёт их).

  python tools/unit_stabilize.py <папка юнита> --anims idle,run[,attack] [--hover] [--dry]
  --hover — парящий (Land Speeder, Raptor на ранце): зазор под ногами не 0, а постоянный — медиана ряда
  (папки рядов — как на диске: idle / run / attack), затем godot --headless --path . --import
"""
import re
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
STASH = ROOT / "assets/source_sheets/unit_stabilize_orig"
TORSO = (0.35, 0.75)   # полоса корпуса — доли роста эталона над нижним пикселем кадра (не от верха силуэта: дым над
                       # головой Havoc и крылья Сангвинарной стражи меняют верх и сдвигали полосу)
ALPHA = 128


def height(a):
    ys = np.nonzero(a[..., 3] > ALPHA)[0]
    return ys.max() - ys.min()


def measure(a, h):
    m = a[..., 3] > ALPHA
    bot = np.nonzero(m)[0].max()
    band = m[max(0, int(bot - h * TORSO[1])):int(bot - h * TORSO[0])]
    return float(np.nonzero(band)[1].mean()), a.shape[0] - 1 - bot


def shift(a, dx, dy):
    out = np.zeros_like(a)
    h, w = a.shape[:2]
    sx0, sx1 = max(0, -dx), min(w, w - dx)
    sy0, sy1 = max(0, -dy), min(h, h - dy)
    out[sy0 + dy:sy1 + dy, sx0 + dx:sx1 + dx] = a[sy0:sy1, sx0:sx1]
    return out


def first_idle(unit):
    text = (unit / "frames.tres").read_text(encoding="utf-8")
    ext = {i: p for p, i in re.findall(r'path="res://[^"]*?/([^/"]+/[^/"]+\.png)" id="([^"]+)"', text)}
    blocks = re.findall(r'\{\n"frames": \[(.*?)\],\n"loop": \w+,\n"name": &"(\w+)"', text, re.S)
    for body, name in blocks:
        if name == "idle":
            return ext[re.search(r'ExtResource\("([^"]+)"\)', body).group(1)]
    raise SystemExit("нет анимации idle")


def main(args):
    unit = Path(args[0])
    anims = next(a.split("=", 1)[1] if "=" in a else args[args.index(a) + 1] for a in args if a.startswith("--anims")).split(",")
    dry = "--dry" in args
    hover = "--hover" in args
    stash = STASH / unit.name
    for an in anims:   # исходники — один раз; повторный прогон — от них
        src = stash / an
        if not src.exists() and not dry:
            shutil.copytree(unit / an, src, ignore=shutil.ignore_patterns("*.import"))
    ref_file = first_idle(unit)
    ref_dir = stash if (stash / ref_file).exists() else unit
    ref = np.array(Image.open(ref_dir / ref_file).convert("RGBA"))
    ref_h = height(ref)
    ref_x, _ = measure(ref, ref_h)
    print(f"{unit.name}: эталон корпуса — {ref_file}, x {ref_x:.1f}")
    for an in anims:
        src = stash / an if (stash / an).exists() else unit / an
        files = sorted(src.glob("*.png"), key=lambda p: int(p.stem))
        frames = [np.array(Image.open(f).convert("RGBA")) for f in files]
        keep = int(np.median([measure(a, ref_h)[1] for a in frames])) if hover else 0
        for f, a in zip(files, frames):
            cx, gap = measure(a, ref_h)
            dx, dy = round(ref_x - cx), gap - keep
            out = shift(a, dx, dy)
            lost = int((a[..., 3] > ALPHA).sum() - (out[..., 3] > ALPHA).sum())
            print(f"  {an}/{f.name}: x {dx:+d}, вниз {dy:+d}" + (f" — за краем {lost} px" if lost > 0 else ""))
            if not dry:
                Image.fromarray(out).save(unit / an / f.name)


if __name__ == "__main__":
    main(sys.argv[1:])
