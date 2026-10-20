"""Эффект выстрела за спиной стрелка → убрать (решение пользователя 21.10.2026: «выстрел сзади» у Rubric).
На листах Firedrakes и Noise Marines пламя / звуковая волна нарисованы сплошной струёй через соседние кадры:
после нарезки хвост струи кадра N оказывается за спиной (левее ствола) в кадре N+1, поверх тела.
По цвету его от тела не отделить (белое ядро, розовая броня Noise Marines) — поэтому за стволом
(x < ствол − MARGIN) кадр берётся из чистого кадра ref (прицел без выстрела), перед стволом — свой
(вылетающее пламя / волна), шов — плавный на BLEND px. Снаряд игры и так летит из ствола.

    python tools/attack_fx_behind.py <папка спрайта> <ref кадр> <кадры через запятую>
"""
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

MARGIN = 12   # px левее ствола — уже «за спиной»
BLEND = 10    # ширина шва


def main(folder, ref_frame, frames):
    folder = Path(folder)
    text = (folder / "frames.tres").read_text(encoding="utf-8")
    m = re.search(r"metadata/muzzle = Vector2\(([-\d.]+), ([-\d.]+)\)", text)
    ref = np.array(Image.open(folder / "attack" / f"{ref_frame}.png").convert("RGBA")).astype(float)
    cut = int(ref.shape[1] / 2 + float(m.group(1))) - MARGIN
    w = ref.shape[1]
    t = np.clip((np.arange(w) - (cut - BLEND)) / BLEND, 0.0, 1.0)[None, :, None]   # 0 — ref, 1 — свой кадр
    for n in frames:
        f = folder / "attack" / f"{n}.png"
        a = np.array(Image.open(f).convert("RGBA")).astype(float)
        out = ref * (1.0 - t) + a * t
        Image.fromarray(out.round().astype(np.uint8)).save(f)
        print(f"{folder.name}/attack/{f.name}: за стволом (x < {cut}) — кадр {ref_frame}")


if __name__ == "__main__":
    main(sys.argv[1], int(sys.argv[2]), [int(x) for x in sys.argv[3].split(",")])
