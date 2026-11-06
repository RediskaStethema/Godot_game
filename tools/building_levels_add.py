"""Кадры зданий на 2-й и 3-й уровень (пакет художника, отдельные кадры <анимация>_<уровень>_NN.png)
→ папки ряда <анимация>_<уровень>/N.png рядом с листом здания и анимации в его frames.tres.

    python tools/building_levels_add.py <папка пакета> [здание …]

Повторный прогон — заново с исходников пакета (прежние ряды уровней и метаданные снимаются).
- Скорость и цикл анимации уровня — как у ряда 1-го уровня.
- Цветокор (решение пользователя 26.10.2026 «стилизуй новые ассеты»): кадры уровня — к статистике кадров
  1-го уровня этого здания (они уже после sm_grade и ручной правки): средняя яркость, тон и насыщенность
  камня / металла, насыщенность золота и синего — `sm_grade.grade`, все кадры уровня одной группой.
- Сдвиг: художник рисовал уровни на холсте 1-го, но здание на нём съехало (до ~50 px), а вспышка выстрела
  осталась на месте 1-го уровня. Кадры не двигаются (сдвиг срезал бы края) — metadata/level_shift
  {уровень: Vector2}: на сколько px холста подвинуть кадр уровня, чтобы постамент совпал с постаментом 1-го
  (наибольшее IoU масок нижних ALIGN_ZONE силуэта). Building ставит спрайт уровня со сдвигом, ствол — тоже.
- Высота (решение пользователя 26.10.2026: улучшенное здание чуть выше прежнего уровня, пусть и шире):
  metadata/level_scale {уровень: k} — масштаб кадров уровня, чтобы рост над точкой основания был не
  ниже LEVEL_GROWTH высоты прежнего уровня (часть зданий художник нарисовал на 2/3 уровне ниже 1-го).
- Неживые ряды (пакет 26.10.2026: стойка — копии одного кадра, выстрел и пополнение — неподвижное здание
  с наложенной вспышкой 1-го уровня): движение «тела» здания между кадрами (непрозрачные пиксели без огней и
  свечения) меньше STATIC_MOTION % — ряд в metadata/level_static, Building оживляет его кодом (дыхание стойки,
  отдача выстрела, толчок пополнения). У живых рядов 1-го уровня — 32–68 %, у пакета 0–15 %.
Затем: godot --headless --path . --import
"""
import re
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image

from gif_to_frames import IMPORT_PARAMS
import sm_grade

BUILDINGS = Path("assets/sprites/buildings")
# Пакет — по id карты, листы — по building_type (у Хаоса — chaos/<тип>)
FOLDERS = {
    "bolter_turret": "tower", "heretic_autocannon": "chaos/tower",
    "thunderfire_cannon": "artillery", "hellfire_mortar": "chaos/artillery",
    "barracks": "barracks", "cult_shrine": "chaos/barracks",
    "plasma_generatorium": "generator", "dark_altar": "chaos/generator",
    "apothecarion": "apothecarion", "warp_rift": "chaos/apothecarion",
}
WHITE_STONE = {"apothecarion", "codex_bastion"}   # белый камень — не «раскалённое» белое (sm_grade --white-hot)
ALIGN_ZONE = 0.35
ALIGN_RANGE = (90, 14)   # поиск сдвига ± px по x, y
ALPHA = 200
HEIGHT_ALPHA = 128
LEVEL_GROWTH = 1.06      # уровень выше прежнего на 6%
SAT_RATIO = (0.6, 1.3)
STATIC_MOTION = 20.0     # % пикселей тела, сменившихся между кадрами ряда: меньше — ряд неживой
CALM = (0.7, 0.75)       # тело — яркость и насыщенность ниже (огни, вспышки, свечение не в счёт)   # пределы множителей насыщенности золота / синего


def shift_to(ref_path, img_path):
    """(dx, dy): пиксель кадра уровня (x, y) ложится на (x + dx, y + dy) холста 1-го уровня."""
    a = np.array(Image.open(ref_path).convert("RGBA"))[..., 3] > ALPHA
    b = np.array(Image.open(img_path).convert("RGBA"))[..., 3] > ALPHA
    ys = np.nonzero(a)[0]
    y1 = ys.max() + 1
    y0 = y1 - int((y1 - ys.min()) * ALIGN_ZONE)
    rx, ry = ALIGN_RANGE
    ref = np.pad(a[y0:y1], ((0, 0), (rx, rx)))
    best, shift = -1.0, (0, 0)
    for dy in range(-ry, ry + 1):
        if y0 - dy < 0 or y1 - dy > b.shape[0]:
            continue
        m = b[y0 - dy:y1 - dy]
        for dx in range(-rx, rx + 1):
            r = ref[:, rx + dx:rx + dx + m.shape[1]]
            score = (r & m).sum() / max(1, (r | m).sum())
            if score > best:
                best, shift = score, (dx, dy)
    return shift, best


def base_y(path):
    """Точка основания по y, как Building.find_base: самая широкая строка силуэта в нижних 40% кадра,
    выше нижнего пикселя на четверть её ширины."""
    a = np.array(Image.open(path).convert("RGBA"))[..., 3] > 127
    ys = np.nonzero(a)[0]
    top, bottom = ys.min(), ys.max() + 1
    best = 0
    for y in range(bottom - 1, max(top, bottom - int((bottom - top) * 0.4)) - 1, -1):
        xs = np.nonzero(a[y])[0]
        if len(xs) and xs[-1] - xs[0] + 1 > best:
            best = xs[-1] - xs[0] + 1
    return bottom - best / 4.0


def height_of(path, ground):
    """Рост над землёй: от точки основания (ground, px холста этого кадра) до верхнего пикселя силуэта."""
    ys = np.nonzero(np.array(Image.open(path).convert("RGBA"))[..., 3] > HEIGHT_ALPHA)[0]
    return float(ground - ys.min())


def stats(images, white_hot):
    """Плотные пиксели группы: яркость (и маска огней), тон и насыщенность камня, насыщенность золота и синего."""
    v_all, g_all, n_h, n_s, gold_s, blue_s = [], [], [], [], [], []
    for img in images:
        dense = np.array(img)[:, :, 3] > sm_grade.DENSE
        h, s, v = np.moveaxis(sm_grade.hsv_of(img), -1, 0)
        glow, gold, blue, neutral = sm_grade.masks(h, s, v, white_hot)
        v_all.append(v[dense])
        g_all.append(glow[dense])
        n_h.append(h[dense & neutral])
        n_s.append(s[dense & neutral])
        gold_s.append(s[dense & gold])
        blue_s.append(s[dense & blue])
    cat = [np.concatenate(x) for x in (v_all, g_all, n_h, n_s, gold_s, blue_s)]
    v, g, nh, ns, gs, bs = cat
    hue = (np.angle(np.exp(2j * np.pi * nh).mean()) / (2 * np.pi)) % 1.0 if len(nh) else sm_grade.STEEL_HUE
    return {"v": v, "glow": g, "hue": hue, "metal_sat": ns.mean() if len(ns) else sm_grade.NEUTRAL_SAT_TO,
            "gold": gs.mean() if len(gs) > 50 else None, "blue": bs.mean() if len(bs) > 50 else None}


def ratio(ref, own):
    return 1.0 if ref is None or own is None or own <= 0 else float(np.clip(ref / own, *SAT_RATIO))


def grade_group(ref_files, files, white_hot):
    """Кадры уровня — к кадрам 1-го уровня: множитель яркости подбирается так, чтобы средняя легла на среднюю
    1-го (огни гаснут слабее — как в sm_grade), камень — к его тону и насыщенности, золото и синий — к его."""
    ref = stats([Image.open(f).convert("RGBA") for f in ref_files], white_hot)
    images = [Image.open(f).convert("RGBA") for f in files]
    own = stats(images, white_hot)
    goal = ref["v"].mean()
    lo, hi = 0.05, 2.0
    for _ in range(40):
        gain = (lo + hi) / 2
        mean = np.where(own["glow"], (own["v"] * gain ** sm_grade.GLOW_KEEP).clip(0, 1),
                        (own["v"] * gain).clip(0, 1)).mean()
        lo, hi = (gain, hi) if mean < goal else (lo, gain)
    gold, blue = ratio(ref["gold"], own["gold"]), ratio(ref["blue"], own["blue"])
    print(f"    цвет: яркость {own['v'].mean():.3f} -> {goal:.3f} (x{gain:.2f}), камень тон {ref['hue']:.2f} "
          f"нас. {ref['metal_sat']:.2f}, золото x{gold:.2f}, синий x{blue:.2f}")
    return [sm_grade.grade(img, gain, ref["hue"], blue, ref["metal_sat"], 1.0, white_hot, gold) for img in images]


def body_motion(files):
    """Доля (%) пикселей тела здания, сменившихся между 1-м кадром ряда и остальными (наибольшая)."""
    rgba = [np.array(Image.open(f).convert("RGBA")).astype(float) for f in files]
    hsv = [np.array(Image.open(f).convert("RGB").convert("HSV")).astype(float) / 255.0 for f in files]
    body = np.all([a[..., 3] > ALPHA for a in rgba], axis=0) &         np.all([(h[..., 2] < CALM[0]) & (h[..., 1] < CALM[1]) for h in hsv], axis=0)
    if len(files) < 2 or not body.any():
        return 0.0
    return max(float((np.abs(a[..., :3] - rgba[0][..., :3]).sum(-1)[body] > 40).mean() * 100) for a in rgba[1:])


def anim_params(text):
    return {m.group(2): (m.group(1), m.group(3)) for m in re.finditer(
        r'"loop": (true|false),\n"name": &"(\w+)",\n"speed": ([\d.]+)', text)}


def strip_levels(dst, text):
    """Снять прежние ряды уровней (повторный прогон): ресурсы, анимации, метаданные, папки."""
    text = re.sub(r'\[ext_resource [^\n]*id="[a-z]+_\d_\d+"\]\n', "", text)
    text = re.sub(r"metadata/level_\w+ = [^\n]*\n", "", text)
    head, body = text.split("animations = [", 1)
    blocks = re.findall(r'\{\n"frames": \[.*?\n"speed": [\d.]+\n\}', body, re.S)
    keep = [b for b in blocks if not re.search(r'"name": &"[a-z]+_\d"', b)]
    for d in dst.iterdir():
        if d.is_dir() and re.fullmatch(r"[a-z]+_\d", d.name):
            shutil.rmtree(d)
    text = head + "animations = [" + ", ".join(keep) + "]\n"
    n = len(re.findall(r"\[ext_resource ", text))
    return re.sub(r"load_steps=\d+", f"load_steps={n + 1}", text)


def to_canvas(img, canvas):
    """Кадр пакета — на холст 1-го уровня, если тот расширен (по бокам поровну, сверху): низ и середина — на месте."""
    if img.size == canvas:
        return img
    c = Image.new("RGBA", canvas)
    c.paste(img, ((canvas[0] - img.width) // 2, canvas[1] - img.height), img)
    return c


def add_levels(name, src, dst):
    tres = dst / "frames.tres"
    text = strip_levels(dst, tres.read_text(encoding="utf-8"))
    white_hot = 1.01 if name in WHITE_STONE else sm_grade.WHITE_HOT
    groups = {}
    for f in sorted(src.glob("*.png")):
        m = re.fullmatch(r"([a-z]+)_(\d)_(\d+)", f.stem)
        if m:
            groups.setdefault((m.group(1), int(m.group(2))), []).append(f)
    params = anim_params(text)
    ref_files = sorted(p for a in params for p in (dst / a).glob("*.png"))
    res = "res://" + dst.as_posix()
    ext, anims, shifts, heights, static = [], [], {}, {}, []
    canvas = Image.open(dst / "idle" / "0.png").size   # кадры уровня — на холст 1-го (его могли расширить)
    ground = base_y(dst / "idle" / "0.png")   # основание 1-го уровня; у кадров уровня — со сдвигом
    heights[1] = height_of(dst / "idle" / "0.png", ground)
    for level in sorted({lv for _, lv in groups}):
        rows = sorted((a for a, lv in groups if lv == level), key=lambda a: (a != "idle", a))
        for a in [a for a in rows if a not in params]:
            print(f"  {a}_{level}: у 1-го уровня нет ряда {a} — пропуск")
        rows = [a for a in rows if a in params]
        graded = iter(grade_group(ref_files, [f for a in rows for f in groups[(a, level)]], white_hot))
        for anim in rows:
            row = f"{anim}_{level}"
            out = dst / row
            out.mkdir()
            refs = []
            for i in range(len(groups[(anim, level)])):
                to_canvas(next(graded), canvas).save(out / f"{i}.png")
                (out / f"{i}.png.import").write_text(IMPORT_PARAMS, encoding="utf-8")
                ext.append(f'[ext_resource type="Texture2D" path="{res}/{row}/{i}.png" id="{row}_{i}"]')
                refs.append(f'{{\n"duration": 1.0,\n"texture": ExtResource("{row}_{i}")\n}}')
            loop, speed = params[anim]
            anims.append('{\n"frames": [' + ", ".join(refs) + f'],\n"loop": {loop},\n"name": &"{row}",\n'
                         f'"speed": {speed}\n}}')
            if anim == "idle":
                shifts[level], score = shift_to(dst / "idle" / "0.png", out / "0.png")
                heights[level] = height_of(out / "0.png", ground - shifts[level][1])
                print(f"  уровень {level}: сдвиг {shifts[level]} (IoU постамента {score:.2f})")
            motion = body_motion(groups[(anim, level)])
            if motion < STATIC_MOTION:
                static.append(row)
            print(f"  {row}: {len(groups[(anim, level)])} кадров, {speed} к/с, движение {motion:.0f}%"
                  + (" — неживой, оживит код" if motion < STATIC_MOTION else ""))
    if not anims:
        return
    scales, prev = {}, heights[1]
    for level in sorted(shifts):
        scales[level] = max(1.0, prev * LEVEL_GROWTH / heights[level])
        prev = heights[level] * scales[level]
        print(f"  уровень {level}: высота {heights[level]:.0f} px, масштаб x{scales[level]:.2f}")
    m = re.search(r"load_steps=(\d+)", text)
    text = text.replace(m.group(0), f"load_steps={int(m.group(1)) + len(ext)}")
    meta = ("metadata/level_shift = {" + ", ".join(f"{lv}: Vector2({dx}, {dy})" for lv, (dx, dy) in sorted(shifts.items()))
            + "}\nmetadata/level_scale = {" + ", ".join(f"{lv}: {k:.3f}" for lv, k in sorted(scales.items())) + "}\n"
            + "metadata/level_static = [" + ", ".join(f'"{r}"' for r in static) + "]\n")
    text = text.replace("\n[resource]\n", "\n".join([""] + ext) + "\n\n[resource]\n" + meta, 1)
    end = text.rstrip().rfind("}]")
    text = text[:end] + "}, " + ", ".join(anims) + "]\n"
    tres.write_text(text, encoding="utf-8")


def main(args):
    pack = Path(args[0])
    names = args[1:] or sorted(p.name for p in pack.iterdir() if p.is_dir())
    for name in names:
        dst = BUILDINGS / FOLDERS.get(name, name)
        print(f"{name} -> {dst}")
        add_levels(name, pack / name, dst)


if __name__ == "__main__":
    main(sys.argv[1:])
