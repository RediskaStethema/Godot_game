"""Продавец магазина без «кипения» (решение пользователя 12.11.2026: «всё ещё очень дёрганый и не плавный»).

Художник перерисовал каждый кадр целиком: между соседними кадрами стойки меняется 15–30% пикселей по всему телу
(рябь текстуры), поэтому фигура дрожит даже при перетекании кадров. Здесь тело во всех кадрах берётся из
кадра 0 стойки, из своего кадра — только крупные движения: пиксели, отличные от кадра 0 (сумма |RGBA| > DIFF),
размытые на BLUR и выше доли THRESH (мелкая рябь гаснет, рука / механодендриты / свечение линзы / щупальца варпа
остаются), расширенные на GROW; ступни и низ рясы (ниже FEET_Y) не двигаются никогда.

    python tools/vendor_stabilize.py <папка пакета с idle/buy/no_money> <папка игры assets/ui/shop/vendor/<раса>>

Пишет кадры idle 0..6 (кадр 7 пакета = кадр 0, не нужен), buy 0..7, no_money 0..7. frames.tres не трогает.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

DIFF = 60
BLUR = 10
THRESH = 0.45
GROW = 9
FEET_Y = 640
ROWS = {"idle": 7, "buy": 8, "no_money": 8}


def load(p: Path) -> np.ndarray:
    return np.array(Image.open(p).convert("RGBA")).astype(np.int32)


def motion_mask(frame: np.ndarray, base: np.ndarray) -> np.ndarray:
    d = (np.abs(frame - base).sum(2) > DIFF).astype(np.uint8) * 255
    soft = np.array(Image.fromarray(d).filter(ImageFilter.GaussianBlur(BLUR))) / 255.0
    m = ((soft > THRESH) * 255).astype(np.uint8)
    m = np.array(Image.fromarray(m).filter(ImageFilter.MaxFilter(GROW))) > 0
    m[FEET_Y:] = False
    return m


def opt(name: str, default: float) -> float:
    """--имя значение (21.11.2026, «продавцы мигают»): --diff / --thresh / --grow / --soft / --settle (кадров в конце ряда плавно к стойке)."""
    a = sys.argv
    return float(a[a.index("--" + name) + 1]) if "--" + name in a else default


def main() -> None:
    global DIFF, THRESH, GROW
    DIFF, THRESH, GROW = opt("diff", DIFF), opt("thresh", THRESH), int(opt("grow", GROW))
    soft_r, settle = opt("soft", 0.0), int(opt("settle", 0))
    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    base = load(src / "idle" / "0.png")
    for anim, count in ROWS.items():
        (dst / anim).mkdir(parents=True, exist_ok=True)
        shares = []
        for i in range(count):
            frame = load(src / anim / f"{i}.png")
            m = motion_mask(frame, base)
            if soft_r > 0:   # мягкий край области движения: жёсткий шов шёл рябью от кадра к кадру
                w = np.array(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(soft_r))) / 255.0
                if anim != "idle" and settle > 0 and i >= count - settle:   # хвост ряда плавно к стойке — без прыжка на возврате
                    w *= (count - 1 - i) / settle
                out = (base * (1 - w[..., None]) + frame * w[..., None]).round()
            else:
                out = base.copy()
                out[m] = frame[m]
            Image.fromarray(out.astype(np.uint8)).save(dst / anim / f"{i}.png")
            shares.append(f"{100 * m.sum() / max(1, (base[..., 3] > 0).sum()):.0f}%")
        print(anim, "своё в кадре:", " ".join(shares))


if __name__ == "__main__":
    main()
