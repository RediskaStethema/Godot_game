"""Кадры-файлы 1.png … N.png (паки эффектов, assets/effects/FXpack13/EffectK) → лист кадров в ряд для
Projectile.EFFECTS / Vfx.EFFECTS (кадры одного размера, порядок — по номеру в имени).

    python tools/frames_to_strip.py <папка кадров> <выход.png>
"""
import sys
from pathlib import Path

from PIL import Image


def main(src: str, dst: str) -> None:
    files = sorted(Path(src).glob("*.png"), key=lambda p: int(p.stem) if p.stem.isdigit() else 0)
    frames = [Image.open(f).convert("RGBA") for f in files]
    w, h = frames[0].size
    strip = Image.new("RGBA", (w * len(frames), h))
    for i, f in enumerate(frames):
        strip.paste(f, (i * w, 0))
    strip.save(dst)
    print(f"{len(frames)} frames {w}x{h} -> {dst}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
