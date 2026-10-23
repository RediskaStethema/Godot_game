"""Мелкие существа по краям поля (решение пользователя 23.10.2026: «маленькие сайд-NPC, просто двигаются по бокам
карты, стилизуй под игру») из пака Tiny RPG Character Asset Pack 02 (Demon_A, Blood Monster_A: листы кадров
100×100 в ряд, фигурка ~20 px) → листы для scripts/battle/SideCritters.gd.

Кадры анимации режутся одной рамкой (объединение рамок всех кадров + POST px, ноги — внизу), затем как пак Pixel
у эффектов (tools/vfx_grade.py paint): ×UP со сглаживанием, край альфы снова чёткий, но скруглённый (ступеньки
пикселей ушли), край силуэта темнее (объём), лёгкое зерно — рядом с рисованными бойцами не торчат квадраты.
Цвет — палитра поля Хаоса «бордо + варп» (tools/chaos_warp_grade.py) и приглушение VAL: существа — фон, не бойцы.
Выход: <папка>/<имя>/<анимация>.png — кадры в ряд, кадр <ширина>×<высота> печатается (SideCritters.KINDS).

    python tools/critters_from_tiny.py "<папка пака>/Characters(100x100 split)" assets/sprites/critters
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

from chaos_warp_grade import warp

CELL = 100
UP = 4
PAD = 2               # px исходника вокруг рамки
EDGE_DARK = 0.3
GRAIN = 0.12
VAL = 0.8             # яркость × — существа глуше бойцов
CREATURES = {"demon": "Demon_A/Demon_A/Demon_A", "blood_monster": "Blood Monster_A/Blood Monster_A/Blood Monster_A"}
ANIMS = {"idle": "_Idle.png", "walk": "_Walk.png", "attack": "_Attack01.png", "hurt": "_Hurt.png"}   # драки — attack / hurt


def frames_of(sheet: Image.Image) -> list:
    return [sheet.crop((i * CELL, 0, i * CELL + CELL, CELL)) for i in range(sheet.width // CELL)]


def soften(cell: Image.Image, rng) -> Image.Image:
    w, h = cell.size
    big = cell.convert("RGBa").resize((w * UP, h * UP), Image.BICUBIC).convert("RGBA")
    a = np.array(big).astype(float) / 255.0
    alpha = np.clip((a[..., 3] - 0.3) / 0.4, 0.0, 1.0)
    alpha = alpha * alpha * (3.0 - 2.0 * alpha)
    inner = np.array(Image.fromarray((alpha * 255).astype(np.uint8)).filter(
        ImageFilter.GaussianBlur(UP * 0.8))).astype(float) / 255.0
    shade = 1.0 - EDGE_DARK * (1.0 - inner)
    grain = 1.0 + GRAIN * (rng.random(alpha.shape) - 0.5)
    rgb = np.clip(a[..., :3] * (shade * grain * VAL)[..., None], 0.0, 1.0)
    return Image.fromarray((np.dstack([rgb, alpha]) * 255).round().astype(np.uint8))


def main(src_dir: str, out_dir: str) -> None:
    rng = np.random.default_rng(7)
    for name, stem in CREATURES.items():
        sheets = {anim: Image.open(Path(src_dir) / (stem + suffix)).convert("RGBA") for anim, suffix in ANIMS.items()}
        # одна рамка на все анимации существа — ноги в одной точке кадра
        box = None
        for sheet in sheets.values():
            for f in frames_of(sheet):
                b = f.getchannel("A").getbbox()
                if b:
                    box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
        box = (box[0] - PAD, box[1] - PAD, box[2] + PAD, box[3])
        # Ноги и рост — по первому кадру стойки (удар шире и выше: фигурка не в центре кадра) → SideCritters.KINDS
        idle = frames_of(sheets["idle"])[0].getchannel("A").getbbox()
        feet_x = ((idle[0] + idle[2]) / 2.0 - box[0]) * UP
        body_h = (idle[3] - idle[1]) * UP
        print(f"{name}: ноги x {feet_x:.0f}, рост {body_h} (px листа)")
        out = Path(out_dir) / name
        out.mkdir(parents=True, exist_ok=True)
        for anim, sheet in sheets.items():
            cells = [warp(soften(f.crop(box), rng)) for f in frames_of(sheet)]
            fw, fh = cells[0].size
            strip = Image.new("RGBA", (fw * len(cells), fh), (0, 0, 0, 0))
            for i, c in enumerate(cells):
                strip.paste(c, (i * fw, 0))
            strip.save(out / f"{anim}.png")
            print(f"{name}/{anim}.png: {len(cells)} кадров {fw}x{fh}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
