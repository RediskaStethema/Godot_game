"""Пакеты финальных боссов художника (assets/source_sheets/bosses_pack/WH40KINGS_Bosses_P1 / P2, 09.11.2026) → кадры + frames.tres для Soldier.

    python tools/boss_frames.py [папка пакета …] [--out assets/units/bosses] [id …]

Пакет: <id>/<анимация>/NN.png, кадры 384×384, ряды idle 12 / walk 12 / attack 12 / special 16 / death 16 /
appear 16, удар — кадр 7 атаки, приём — кадр 10 (README пакета). Босс смотрит вправо.

Брак пакета P2 (Дорн, Русс, Сангвиний, Вулкан; P1 чистый) — чинится здесь, исходники не меняются:
- обрывок соседнего ряда листа над фигурой (полоса ног у верха кадра) — тонкий кусок выше тела через пустую
  полосу стирается (`strip_bleed`);
- серый ореол фона вокруг стойки Дорна (`HALO`) — полупрозрачные серые пиксели стираются;
- ряды приём / смерть / появление нарисованы мельче стойки (Дорн ×0.68, Сангвиний ×0.75) — ряд целиком
  масштабируется вокруг ног к росту стойки, если стоячий кадр ряда ниже стойки больше чем на `SMALL_ROW`;
- линия земли ряда (медиана низа кадров) — на линию земли стойки;
- появление Вулкана нарисовано крупнее кадра, в рамке и обрезано краями — не берётся (`SKIP`): Soldier
  без ряда appear босса не задерживает.

Выход: общий холст на босса (ноги — по центру низа, как у остальных юнитов), кадры уменьшены ×`DOWNSCALE`
(в бою босс ~80 px, 384 px кадр не нужен), `metadata/hit_frame` 7, `metadata/special_frame` 10,
`metadata/figure_height` — рост фигуры стойки в пикселях холста: Soldier меряет рост по нему, а не по холсту
(холст выше стойки — крылья появления, замах).
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

from gif_to_frames import IMPORT_PARAMS
import sm_grade

ANIMS = ["idle", "walk", "attack", "special", "death", "appear"]
FOLDERS = {"idle": "idle", "walk": "run", "attack": "attack", "special": "special", "death": "death", "appear": "appear"}
FPS = {"idle": 8.0, "walk": 10.0, "attack": 14.0, "special": 12.0, "death": 10.0, "appear": 12.0}
LOOPING = {"idle", "walk"}
HIT_FRAME = 7
SPECIAL_FRAME = 10
ALPHA_MIN = 40
DOWNSCALE = 0.5
SMALL_ROW = 0.88       # стоячий кадр ряда ниже этой доли стойки — ряд нарисован мельче, тянем к стойке
GROUND_TOL = 6         # кадр «стоит», если его низ не выше линии земли ряда на столько px
BLEED_GAP = 4          # пустая полоса (px) между обрывком и телом
BLEED_MAX = 0.3        # обрывок не выше этой доли тела
HALO = {"primarch_dorn": ["idle"]}
SKIP = {"primarch_vulkan": ["appear"]}
# Цветокор под палитру поля (решение пользователя 09.11.2026): все кадры босса — одной группой через sm_grade, как
# бойцы своей расы (tools.md: Хаос --target 0.28 --hue 0.03, Космодесант --target 0.36; --pull 0.5 --blue-sat 1
# --metal-sat 0.12): нейтральные тона — к стали грунта, средняя яркость — к цели наполовину, огни гаснут слабее
# Лоялисты: тон нейтральных к стали — слабее (neutral_pull), светлые от white_hot не трогаются — белые крылья Сангвиния,
# кремовый плащ Жиллимана, мех Русса посинели бы (первый прогон 09.11.2026); и выходят они на красное поле Хаоса
GRADE_CHAOS = {"target": 0.28, "pull": 0.5, "hue": 0.03, "blue_sat": 1.0, "metal_sat": 0.12,
    "neutral_pull": sm_grade.NEUTRAL_PULL, "white_hot": sm_grade.WHITE_HOT}
GRADE_SM = {"target": 0.36, "pull": 0.5, "hue": sm_grade.STEEL_HUE, "blue_sat": 1.0, "metal_sat": 0.12,
    "neutral_pull": 0.25, "white_hot": 0.62}


def grade_params(boss_id):
    return GRADE_CHAOS if boss_id.startswith("daemon_") else GRADE_SM


def grade_group(images, params):
    """sm_grade.main без файлов: множитель яркости по плотным пикселям группы, огни — слабее."""
    vals, glows = [], []
    for img in images:
        dense = np.array(img)[:, :, 3] > sm_grade.DENSE
        h, s, v = np.moveaxis(sm_grade.hsv_of(img), -1, 0)
        vals.append(v[dense])
        glows.append(sm_grade.masks(h, s, v, params["white_hot"])[0][dense])
    v_all, g_all = np.concatenate(vals), np.concatenate(glows)
    goal = v_all.mean() * (params["target"] / v_all.mean()) ** params["pull"]
    lo, hi = 0.05, 2.0
    for _ in range(40):
        gain = (lo + hi) / 2
        mean = np.where(g_all, (v_all * gain ** sm_grade.GLOW_KEEP).clip(0, 1), (v_all * gain).clip(0, 1)).mean()
        lo, hi = (gain, hi) if mean < goal else (lo, gain)
    print(f"  цветокор: яркость {v_all.mean():.3f} -> {goal:.3f} (x{gain:.2f})")
    sm_grade.NEUTRAL_PULL, keep = params["neutral_pull"], sm_grade.NEUTRAL_PULL
    try:
        return [sm_grade.grade(img, gain, params["hue"], params["blue_sat"], params["metal_sat"],
                               white_hot=params["white_hot"]) for img in images]
    finally:
        sm_grade.NEUTRAL_PULL = keep


PACKS = ["assets/source_sheets/bosses_pack/WH40KINGS_Bosses_P1", "assets/source_sheets/bosses_pack/WH40KINGS_Bosses_P2"]   # с .gdignore
OUT = "assets/units/bosses"


def mask(img):
    return np.array(img.getchannel("A")) > ALPHA_MIN


def row_segments(m):
    rows = np.where(m.any(1))[0]
    if len(rows) == 0:
        return []
    segs, start = [], rows[0]
    for a, b in zip(rows[:-1], rows[1:]):
        if b - a > BLEED_GAP:
            segs.append((start, a + 1))
            start = b
    segs.append((start, rows[-1] + 1))
    return segs


def strip_bleed(img):
    """Обрывок соседнего ряда листа над фигурой — стереть."""
    m = mask(img)
    segs = row_segments(m)
    if len(segs) < 2:
        return img
    weight = [m[a:b].sum() for a, b in segs]
    main = int(np.argmax(weight))
    body_h = segs[main][1] - segs[main][0]
    arr = np.array(img)
    for i, (a, b) in enumerate(segs):
        if i < main and b - a < body_h * BLEED_MAX:
            arr[a:b, :, 3] = 0
    return Image.fromarray(arr)


def strip_halo(img):
    arr = np.array(img).astype(np.int32)
    rgb, al = arr[..., :3], arr[..., 3]
    mx, mn = rgb.max(2), rgb.min(2)
    sat = (mx - mn) / np.maximum(mx, 1)
    halo = (al < 200) & (sat < 0.2) & (mx > 120)
    arr[..., 3][halo] = 0
    return Image.fromarray(arr.astype(np.uint8))


def bbox(img):
    return img.getchannel("A").point(lambda v: 255 if v > ALPHA_MIN else 0).getbbox()


def standing_height(frames):
    """Рост стоячих кадров ряда (низ у линии земли): наибольший; и линия земли — медиана низа."""
    boxes = [bbox(f) for f in frames]
    boxes = [b for b in boxes if b]
    ground = float(np.median([b[3] for b in boxes]))
    tall = [b[3] - b[1] for b in boxes if b[3] >= ground - GROUND_TOL]
    return max(tall), ground, boxes


def scale_about(img, k, pivot):
    """Масштаб кадра вокруг точки pivot (ноги) на холсте того же размера."""
    w, h = img.size
    big = img.resize((max(1, round(w * k)), max(1, round(h * k))), Image.LANCZOS)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.paste(big, (round(pivot[0] - pivot[0] * k), round(pivot[1] - pivot[1] * k)))   # холст пуст — копия без маски
    return out


def shift(img, dx, dy):
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.paste(img, (round(dx), round(dy)))
    return out


def load_boss(root):
    rows = {}
    for anim in ANIMS:
        if anim in SKIP.get(root.name, []):
            continue
        files = sorted((root / anim).glob("*.png"))
        frames = [strip_bleed(Image.open(f).convert("RGBA")) for f in files]
        if anim in HALO.get(root.name, []):
            frames = [strip_halo(f) for f in frames]
        rows[anim] = frames
    idle_h, idle_ground, idle_boxes = standing_height(rows["idle"])
    idle_cx = float(np.median([(b[0] + b[2]) / 2 for b in idle_boxes]))
    for anim, frames in rows.items():
        if anim == "idle":
            continue
        h, ground, boxes = standing_height(frames)
        k = idle_h / h if h < idle_h * SMALL_ROW else 1.0
        if k != 1.0:
            cx = float(np.median([(b[0] + b[2]) / 2 for b in boxes if b[3] >= ground - GROUND_TOL]))
            frames = [scale_about(f, k, (cx, ground)) for f in frames]
            frames = [shift(f, idle_cx - cx, 0) for f in frames]
            print(f"  {anim}: ряд ×{k:.2f}")
        if abs(ground - idle_ground) >= 1:
            frames = [shift(f, 0, idle_ground - ground) for f in frames]
        rows[anim] = frames
    return rows, idle_h, idle_ground, idle_cx


def export(root, out_root, graded=True):
    print(root.name)
    rows, idle_h, ground, cx = load_boss(root)
    # Общий холст: по x симметрично вокруг тела стойки, сверху — выше всех кадров, снизу — линия земли
    boxes = [b for fr in rows.values() for b in map(bbox, fr) if b]
    half = max(max(cx - b[0], b[2] - cx) for b in boxes) + 2
    top = min(b[1] for b in boxes) - 2
    crop = (round(cx - half), round(top), round(cx + half), round(ground))
    out = out_root / root.name
    res = "res://" + out.as_posix()
    ext, anims = [], []
    cut = {}
    for anim, frames in rows.items():
        cut[anim] = []
        for f in frames:
            c = Image.new("RGBA", (crop[2] - crop[0], crop[3] - crop[1]), (0, 0, 0, 0))
            c.alpha_composite(f.crop((max(crop[0], 0), max(crop[1], 0), min(crop[2], f.width), min(crop[3], f.height))),
                              (max(-crop[0], 0), max(-crop[1], 0)))
            cut[anim].append(c.resize((round(c.width * DOWNSCALE), round(c.height * DOWNSCALE)), Image.LANCZOS))
    if graded:
        flat = [c for fr in cut.values() for c in fr]
        done = iter(grade_group(flat, grade_params(root.name)))
        cut = {anim: [next(done) for _ in fr] for anim, fr in cut.items()}
    for anim, frames in cut.items():
        d = out / FOLDERS[anim]
        d.mkdir(parents=True, exist_ok=True)
        for old in d.glob("*.png*"):
            old.unlink()
        refs = []
        for i, c in enumerate(frames):
            c.save(d / f"{i}.png")
            (d / f"{i}.png.import").write_text(IMPORT_PARAMS, encoding="utf-8")
            ext.append(f'[ext_resource type="Texture2D" path="{res}/{FOLDERS[anim]}/{i}.png" id="{anim}_{i}"]')
            refs.append(f'{{\n"duration": 1.0,\n"texture": ExtResource("{anim}_{i}")\n}}')
        anims.append(f'{{\n"frames": [{", ".join(refs)}],\n"loop": {"true" if anim in LOOPING else "false"},\n'
                     f'"name": &"{anim}",\n"speed": {FPS[anim]}\n}}')
    fig_h = idle_h * DOWNSCALE
    meta = (f"metadata/hit_frame = {HIT_FRAME}\nmetadata/special_frame = {SPECIAL_FRAME}\n"
            f"metadata/figure_height = {fig_h:.1f}\n")
    tres = (f'[gd_resource type="SpriteFrames" load_steps={len(ext) + 1} format=3]\n\n' + "\n".join(ext)
            + f'\n\n[resource]\n{meta}animations = [{", ".join(anims)}]\n')
    (out / "frames.tres").write_text(tres, encoding="utf-8")
    w, h = round((crop[2] - crop[0]) * DOWNSCALE), round((crop[3] - crop[1]) * DOWNSCALE)
    print(f"  холст {w}x{h}, рост стойки {fig_h:.0f}, рядов {len(rows)}")


def main(argv):
    out_root = Path(OUT)
    if "--out" in argv:
        i = argv.index("--out")
        out_root = Path(argv[i + 1])
        argv = argv[:i] + argv[i + 2:]
    graded = "--no-grade" not in argv
    argv = [a for a in argv if a != "--no-grade"]
    packs = [Path(a) for a in argv if Path(a).is_dir()] or [Path(p) for p in PACKS]
    only = {a for a in argv if not Path(a).is_dir()}
    for pack in packs:
        for root in sorted(p for p in pack.iterdir() if p.is_dir() and (p / "idle").is_dir()):
            if not only or root.name in only:
                export(root, out_root, graded)


if __name__ == "__main__":
    main(sys.argv[1:])
