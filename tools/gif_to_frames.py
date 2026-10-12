"""GIF-анимации юнита → кадры PNG для Soldier.gd.

    python tools/gif_to_frames.py assets/sprites/space_marine 325,163 3

Второй и третий аргументы (необязательны) — срез ствола в пикселях attack.gif и кадр вспышки:
искать их автоматически ненадёжно (блики брони похожи на вспышку), снимаются с картинки.

Берёт <папка>/{idle,walk,attack,death}.gif и пишет кадры в <папка>/<idle|run|attack|death>/N.png
(старые PNG в этих папках удаляются) и <папка>/frames.tres — SpriteFrames со скоростью из GIF
и метаданными: muzzle — точка ствола от ног (px кадра, взгляд вправо), shot_frame — кадр вспышки.

Все анимации кладутся на общий холст: ноги — по центру нижнего края (так их ставит Soldier),
масштаб — по росту персонажа в idle (GIF могут быть в разном разрешении).
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageSequence

ANIMS = {"idle": "idle", "walk": "run", "attack": "attack", "death": "death"}
LOOPING = {"idle", "walk"}
# Персонаж занимает такую долю высоты холста (как в прежних кадрах) — рост на экране не меняется
FILL = 0.83
# Рост персонажа в idle на холсте, px
TARGET_CHAR_H = 165
# Бег — с подогнутыми ногами: его рамка ниже стойки на столько
WALK_CROUCH = 0.96
ATTACK_FPS = 12.0
# Фон без прозрачности (бывает в GIF): чистый чёрный, связанный с краем кадра, вырезается.
# Контур персонажа почти чёрный ((4,4,7)), поэтому допуск маленький и заливка — только от краёв.
BG_TOLERANCE = 2   # анимация выстрела успевает до следующего (атак до ~1.6/с)

IMPORT_PARAMS = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=0
mipmaps/generate=true
mipmaps/limit=-1
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
"""


def cut_background(frame):
    """Непрозрачный фон → прозрачность: заливка от каждого непрозрачного почти чёрного пикселя края."""
    px = frame.load()
    w, h = frame.size
    border = [(x, 0) for x in range(w)] + [(x, h - 1) for x in range(w)]         + [(0, y) for y in range(h)] + [(w - 1, y) for y in range(h)]
    for x, y in border:
        r, g, b, a = px[x, y]
        if a > 0 and max(r, g, b) <= BG_TOLERANCE:
            ImageDraw.floodfill(frame, (x, y), (0, 0, 0, 0), thresh=BG_TOLERANCE)
    return frame


def load_frames(path):
    im = Image.open(path)
    frames = [cut_background(f.convert("RGBA")) for f in ImageSequence.Iterator(im)]
    durations = []
    for i in range(im.n_frames):
        im.seek(i)
        durations.append(im.info.get("duration", 100) or 100)
    return frames, durations


def union_bbox(frames):
    boxes = [f.getbbox() for f in frames if f.getbbox()]
    return (min(b[0] for b in boxes), min(b[1] for b in boxes),
            max(b[2] for b in boxes), max(b[3] for b in boxes))


def feet_x(frame):
    """Центр ног: середина непрозрачных пикселей в нижней пятой части силуэта
    (центр всей рамки уводит в сторону оружие — при развороте боец бы прыгал)."""
    box = frame.getbbox()
    y0 = box[3] - (box[3] - box[1]) // 5
    alpha = frame.getchannel("A").load()
    xs = [x for y in range(y0, box[3]) for x in range(box[0], box[2]) if alpha[x, y] > 128]
    return (min(xs) + max(xs)) / 2


def main(folder, muzzle=None):
    folder = Path(folder)
    res_folder = "res://" + folder.as_posix().strip("/")
    src = {a: load_frames(folder / f"{a}.gif") for a in ANIMS}

    idle_box = union_bbox(src["idle"][0])
    walk_box = union_bbox(src["walk"][0])
    idle_h = idle_box[3] - idle_box[1]
    walk_h = walk_box[3] - walk_box[1]
    scale = {a: TARGET_CHAR_H / idle_h for a in ANIMS}
    scale["walk"] = TARGET_CHAR_H * WALK_CROUCH / walk_h

    # Якорь каждой анимации: x — центр ног в первом кадре, y — самая низкая точка
    placed = {}
    half_w = 0
    top = 0
    for a, (frames, _) in src.items():
        s = scale[a]
        ax = feet_x(frames[0])
        bx = union_bbox(frames)
        ay = bx[3]
        half_w = max(half_w, (ax - bx[0]) * s, (bx[2] - ax) * s)
        top = max(top, (ay - bx[1]) * s)
        placed[a] = (ax, ay)
    canvas_h = round(max(top, TARGET_CHAR_H) / FILL)
    canvas_w = 2 * round(half_w + 4)

    tres_anims = []
    ext = []
    for a, (frames, durations) in src.items():
        out_dir = folder / ANIMS[a]
        out_dir.mkdir(exist_ok=True)
        for old in out_dir.iterdir():
            if old.suffix in (".png", ".import") or old.name.endswith(".png.import") or old.name == "2png":
                old.unlink()
        s = scale[a]
        ax, ay = placed[a]
        refs = []
        for i, f in enumerate(frames):
            fw, fh = round(f.width * s), round(f.height * s)
            scaled = f.resize((fw, fh), Image.LANCZOS)
            canvas = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
            canvas.alpha_composite(scaled, (round(canvas_w / 2 - ax * s), round(canvas_h - ay * s)))
            png = out_dir / f"{i}.png"
            canvas.save(png)
            (out_dir / f"{i}.png.import").write_text(IMPORT_PARAMS, encoding="utf-8")
            ext.append(f'[ext_resource type="Texture2D" path="{res_folder}/{ANIMS[a]}/{i}.png" id="{a}_{i}"]')
            refs.append(f'{{\n"duration": 1.0,\n"texture": ExtResource("{a}_{i}")\n}}')
        fps = ATTACK_FPS if a == "attack" else round(1000.0 / (sum(durations) / len(durations)), 2)
        tres_anims.append(
            f'{{\n"frames": [{", ".join(refs)}],\n"loop": {"true" if a in LOOPING else "false"},\n'
            f'"name": &"{a}",\n"speed": {fps}\n}}')

    meta = ""
    if muzzle:
        idx, mx, my = muzzle
        ax, ay = placed["attack"]
        s = scale["attack"]
        meta = (f"metadata/muzzle = Vector2({(mx - ax) * s:.1f}, {(my - ay) * s:.1f})\n"
                f"metadata/shot_frame = {idx}\n")
    tres = (f'[gd_resource type="SpriteFrames" load_steps={len(ext) + 1} format=3]\n\n'
            + "\n".join(ext)
            + f'\n\n[resource]\n{meta}animations = [{", ".join(tres_anims)}]\n')
    (folder / "frames.tres").write_text(tres, encoding="utf-8")
    print(f"canvas {canvas_w}x{canvas_h}, scale {scale}, muzzle {muzzle}")


if __name__ == "__main__":
    muzzle = None
    if len(sys.argv) > 3:
        mx, my = (float(v) for v in sys.argv[2].split(","))
        muzzle = (int(sys.argv[3]), mx, my)
    main(sys.argv[1], muzzle)
