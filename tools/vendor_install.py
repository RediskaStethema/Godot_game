"""Перерисованный продавец -> игра (решение пользователя 23.11.2026: «перерисуй продавцов в стиле игры» + анимация стойки).
Берёт <папка пакета>/out/{idle,buy,no_money} (tools/vendor_redraw_slice.py -> vendor_stabilize.py -> vendor_idle_anim.py), приглушает
цвет к яркости прежних кадров (новый рисунок ярче: множитель на всё, кроме огня и свечения), кладёт кадры в
assets/ui/shop/vendor/<раса> и пишет frames.tres: idle — ЦИКЛ из N кадров (8 к/с), buy / no_money как были (12 к/с).
  python tools/vendor_install.py <space_marines|chaos> <папка пакета> [lens_x lens_y]
Прежние кадры — assets/source_sheets/vendor_pixel_orig_2026-11-23/<раса> (откат: tools/vendor_pixelize.py --restore, frames.tres — git).
"""
import re
import shutil
import sys
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
GAME = ROOT / "assets/ui/shop/vendor"
ORIG = ROOT / "assets/source_sheets/vendor_pixel_orig_2026-11-23"
IDLE_FPS = 8.0


def lum(a):
    return (0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]) / 255.0


def glow(a):
    r, g, b, al = (a[..., i].astype(int) for i in range(4))
    return (al > 0) & (r > 200) & (g > 105) & (b < 150) & (r - b > 90)


def main(race: str, pack: Path, lens) -> None:
    src = pack / "out"
    old = np.array(Image.open(ORIG / race / "buy" / "0.png").convert("RGBA")).astype(np.float64)
    new = np.array(Image.open(src / "buy" / "0.png").convert("RGBA")).astype(np.float64)
    om = lum(old)[old[..., 3] > 200].mean()
    nm = lum(new)[new[..., 3] > 200].mean()
    gain = float(np.clip(om / nm, 0.7, 1.05))
    print(race, "яркость было", round(om, 3), "стало", round(nm, 3), "→ множитель", round(gain, 3))
    dst = GAME / race
    counts = {}
    for anim in ("idle", "buy", "no_money"):
        shutil.rmtree(dst / anim, ignore_errors=True)
        (dst / anim).mkdir(parents=True)
        files = sorted((src / anim).glob("*.png"), key=lambda p: int(p.stem))
        counts[anim] = len(files)
        for f in files:
            a = np.array(Image.open(f).convert("RGBA"))
            g = glow(a)
            rgb = a[..., :3].astype(np.float64)
            rgb[~g] *= gain
            a[..., :3] = np.clip(rgb, 0, 255).astype(np.uint8)
            Image.fromarray(a).save(dst / anim / f.name)
    # frames.tres: прежние metadata сохраняем, анимации пишем заново
    tres = (dst / "frames.tres").read_text(encoding="utf-8")
    meta = re.findall(r"^metadata/.*$", tres, flags=re.M)
    meta = [m for m in meta if not m.startswith("metadata/lens")] + ["metadata/lens = Vector2(%d, %d)" % lens]
    ids = []
    lines = []
    for anim in ("idle", "buy", "no_money"):
        for i in range(counts[anim]):
            ids.append((anim, i))
    head = ['[gd_resource type="SpriteFrames" load_steps=%d format=3]' % (len(ids) + 1), ""]
    for anim, i in ids:
        head.append('[ext_resource type="Texture2D" path="res://assets/ui/shop/vendor/%s/%s/%d.png" id="%s_%d"]' % (race, anim, i, anim, i))
    body = ["", "[resource]"] + meta + ["animations = [" + ", ".join(_anim(anim, counts[anim]) for anim in ("idle", "buy", "no_money")) + "]", ""]
    (dst / "frames.tres").write_text("\n".join(head + body), encoding="utf-8", newline="\n")
    print("  кадры:", counts, "| frames.tres записан, lens", lens)


def _anim(name: str, n: int) -> str:
    frames = ", ".join('{\n"duration": 1.0,\n"texture": ExtResource("%s_%d")\n}' % (name, i) for i in range(n))
    loop = "true" if name == "idle" else "false"
    speed = IDLE_FPS if name == "idle" else 12.0
    return '{\n"frames": [%s],\n"loop": %s,\n"name": &"%s",\n"speed": %.1f\n}' % (frames, loop, name, speed)


if __name__ == "__main__":
    race = sys.argv[1]
    pack = Path(sys.argv[2])
    lens = (int(sys.argv[3]), int(sys.argv[4])) if len(sys.argv) > 4 else None
    if lens is None:
        t = (GAME / race / "frames.tres").read_text(encoding="utf-8")
        m = re.search(r"metadata/lens = Vector2\(([\d.]+), ([\d.]+)\)", t)
        lens = (int(float(m.group(1))), int(float(m.group(2))))
    main(race, pack, lens)
