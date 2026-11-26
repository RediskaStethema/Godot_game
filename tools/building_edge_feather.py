"""Срез края холста у кадров зданий → мягкое затухание (решение пользователя 06.11.2026: «во время работы зданий
в некоторых местах слишком ярко видно, как обрезан спрайт»).

Листы художника срезали эффекты рамкой кадра: пламя выстрела Хаос-мортиры по верху, разряд Святилища культа,
дым генератора, свет из дверей Казарм по низу, край Кузни Вулкана и генератора Хаоса сбоку. Холст не расширяется
(по нему считаются основание, стволы и сдвиги уровней — metadata frames.tres), вместо этого у края, где силуэт
упирается в рамку, альфа гаснет на FEATHER px (как FEATHER у tools/fx_fix.py):
  - верх, лево, право — всё, что касается края;
  - низ — только в рядах работы (attack / refill / shield; в стойке основание гуляет по кадрам — гасить нельзя)
    и только столбцы вне основания (не меньше MIN_BOTTOM_OUTSIDE px): основание здания стоит на нижнем краю (стойка 1-го кадра того же уровня,
    `idle` / `idle_2` / `idle_3`, + BASE_PAD), постамент не трогается, гаснет свет и эффекты рядом с ним.
Исходные кадры — в assets/source_sheets/building_edge_orig/ (пути как в buildings/). Повторный прогон ничего не меняет: после затухания у края альфа ниже EDGE_HIT.

  python tools/building_edge_feather.py [--dry] [папка здания …]   (без папок — все в assets/sprites/buildings)
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
BUILDINGS = ROOT / "assets/sprites/buildings"
FEATHER = 14          # px затухания от края — верх и низ (пламя, дым, свет)
FEATHER_SIDE = 6      # бока — край самого здания (генератор Хаоса, Кузня): шире — полупрозрачная полоса по стене
BACKUP = ROOT / "assets/source_sheets/building_edge_orig"   # кадры до затухания (пути как в buildings/)
EDGE_HIT = 60         # альфа «касается края»
MIN_HITS = 3          # столько пикселей края — уже срез
BASE_PAD = 4          # px — запас основания по бокам
MIN_BOTTOM_OUTSIDE = 20   # px нижнего края вне основания — это свет / эффект, не сдвиг постамента


def level_of(anim: str) -> str:
    return anim.rsplit("_", 1)[1] if anim[-2:-1] == "_" and anim[-1].isdigit() else ""


def base_columns(building: Path, anim: str, width: int) -> np.ndarray:
    lvl = level_of(anim)
    idle = building / ("idle" if lvl == "" else f"idle_{lvl}") / "0.png"
    cols = np.zeros(width, dtype=bool)
    if not idle.exists():
        return cols
    a = np.asarray(Image.open(idle).convert("RGBA"))[..., 3]
    if a.shape[1] != width:
        return cols
    hit = np.nonzero(a[-1] > EDGE_HIT)[0]
    for x in hit:
        cols[max(0, x - BASE_PAD):x + BASE_PAD + 1] = True
    return cols


def feather(img: np.ndarray, base: np.ndarray, work: bool) -> tuple[np.ndarray, list[str]]:
    a = img[..., 3].astype(np.float32)
    h, w = a.shape
    ramp = np.clip((np.arange(FEATHER, dtype=np.float32) + 0.5) / FEATHER, 0, 1)
    side = np.clip((np.arange(FEATHER_SIDE, dtype=np.float32) + 0.5) / FEATHER_SIDE, 0, 1)
    done = []
    if (a[0] > EDGE_HIT).sum() >= MIN_HITS:
        a[:FEATHER] *= ramp[:, None]
        done.append("верх")
    if (a[:, 0] > EDGE_HIT).sum() >= MIN_HITS:
        a[:, :FEATHER_SIDE] *= side[None, :]
        done.append("лево")
    if (a[:, -1] > EDGE_HIT).sum() >= MIN_HITS:
        a[:, -FEATHER_SIDE:] *= side[::-1][None, :]
        done.append("право")
    outside = (a[-1] > EDGE_HIT) & ~base
    if work and outside.sum() >= MIN_BOTTOM_OUTSIDE:
        a[-FEATHER:, ~base] *= ramp[::-1][:, None]
        done.append("низ вне основания")
    out = img.copy()
    out[..., 3] = np.clip(a, 0, 255).astype(np.uint8)
    return out, done


def main() -> None:
    args = [x for x in sys.argv[1:] if not x.startswith("--")]
    dry = "--dry" in sys.argv
    roots = [BUILDINGS / x for x in args] if args else [BUILDINGS]
    total = 0
    for root in roots:
        for png in sorted(root.rglob("*.png")):
            anim_dir = png.parent
            building = anim_dir.parent
            img = np.asarray(Image.open(png).convert("RGBA"))
            work = not anim_dir.name.startswith("idle")   # ряды работы: attack / refill / shield
            out, done = feather(img, base_columns(building, anim_dir.name, img.shape[1]), work)
            if not done:
                continue
            total += 1
            print(f"{png.relative_to(BUILDINGS).as_posix()}: {', '.join(done)}")
            if not dry:
                keep = BACKUP / png.relative_to(BUILDINGS)
                if not keep.exists():
                    keep.parent.mkdir(parents=True, exist_ok=True)
                    keep.write_bytes(png.read_bytes())
                Image.fromarray(out).save(png)
    print(f"кадров: {total}" + (" (--dry, не записано)" if dry else ""))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
