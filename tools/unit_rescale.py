"""Масштаб кадров модельки юнита вокруг ног — брак листа: ряд нарисован мельче стойки или фигура мельчает к концу
ряда (аудит 23.10.2026: Centurion стреляет на четверть мельче, чем стоит; Land Speeder и Hellbrute на стыке цикла
бега вырастают на 15–25%).

    python tools/unit_rescale.py <папка юнита> <анимация>:<k> …    ряд целиком ×k
    python tools/unit_rescale.py <папка юнита> <анимация>:even …    кадры ряда — к размеру его 1-го кадра
    [--dry] — только напечатать (проходы по одному ряду с --dry не складываются — смотреть по одному)
    Запускать из корня проекта. Не идемпотентно: повторный прогон attack:1.17 увеличит ещё раз — переделывать
    с исходных кадров (git checkout кадров или перенарезка листа).

Сделано 23.10.2026: space_marine_land_speeder walk:even attack:even, chaos_hellbrute walk:even,
space_marine_centurion attack:even attack:1.11 (анимация — имя в frames.tres: walk, хотя папка кадров — run).

Ноги кадра — середина нижних 12% силуэта по x, низ силуэта по y: на этой точке боец стоит, она не сдвигается.
Размер для even — площадь «тела» (непрозрачные тёмные пиксели: вспышки, огонь, свечение светлее и не в счёт),
масштаб = √(площадь 1-го кадра / площадь кадра). Ряд — папка кадров по frames.tres (у бега папка run).
Ствол (metadata/muzzle, от центра низа холста) пересчитывается, если менялся кадр выстрела. Холст не меняется;
вылезло за край — предупреждение. Запускать на кадрах после цветокора (sm_grade.py) — масштаб его не меняет.
"""
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
BODY_ALPHA = 200
BODY_MAX_VALUE = 150
FOOT_SHARE = 0.12
KEEP = 0.01      # масштаб ближе к 1 — кадр не трогаем


def body_area(img):
    a = np.array(img).astype(np.int32)
    return int(((a[..., 3] > BODY_ALPHA) & (a[..., :3].max(axis=2) < BODY_MAX_VALUE)).sum())


def feet(img):
    m = np.array(img)[..., 3] > 40
    ys, xs = np.nonzero(m)
    top, bot = ys.min(), ys.max()
    band = m[int(bot - max(2, (bot - top + 1) * FOOT_SHARE)):bot + 1]
    fx = np.nonzero(band)[1]
    return np.array([fx.mean() if fx.size else xs.mean(), float(bot)])


def scale_about(img, k, p):
    # Точка q кадра → p + (q − p)·k; affine у PIL — обратное отображение. Цвет — с предумножением на альфу:
    # иначе бикубика тянет к краю силуэта цвет прозрачных пикселей (тёмная кайма)
    a = np.array(img).astype(np.float32)
    a[..., :3] *= a[..., 3:4] / 255.0
    m = (1 / k, 0, p[0] - p[0] / k, 0, 1 / k, p[1] - p[1] / k)
    ch = [np.array(Image.fromarray(a[..., c]).transform(img.size, Image.AFFINE, m, resample=Image.BICUBIC))
          for c in range(4)]
    out = np.stack(ch, axis=-1)
    alpha = np.clip(out[..., 3], 0, 255)
    out[..., :3] = np.where(alpha[..., None] > 0, out[..., :3] * 255.0 / np.maximum(alpha[..., None], 1e-3), 0)
    out[..., 3] = alpha
    return Image.fromarray(np.clip(out + 0.5, 0, 255).astype(np.uint8))


def frame_files(text, anim):
    ext = {i: p.replace("res://", "") for p, i in re.findall(r'path="([^"]+)" id="([^"]+)"', text)}
    m = re.search(r'\{\n"frames": \[([^\]]*)\],\n"loop": \w+,\n"name": &"%s",' % anim, text)   # [^\]] — не дальше своей анимации
    if not m:
        sys.exit("нет анимации %s" % anim)
    return [ROOT / ext[i] for i in re.findall(r'ExtResource\("([^"]+)"\)', m.group(1))]


def move_muzzle(tres, text, size, k, p):
    m = re.search(r"metadata/muzzle = Vector2\(([-\d.]+), ([-\d.]+)\)", text)
    if not m:
        return text
    q = np.array([size[0] / 2 + float(m.group(1)), size[1] + float(m.group(2))])
    q = p + (q - p) * k - np.array([size[0] / 2, size[1]])
    print("    muzzle → (%.1f, %.1f)" % (q[0], q[1]))
    return text.replace(m.group(0), "metadata/muzzle = Vector2(%.1f, %.1f)" % (q[0], q[1]))


def main(args):
    dry = "--dry" in args
    args = [a for a in args if not a.startswith("--")]
    folder = Path(args[0])
    tres = folder / "frames.tres"
    raw = tres.read_bytes().decode("utf-8")
    crlf = "\r\n" in raw
    text = orig = raw.replace("\r\n", "\n")
    shot = re.search(r"metadata/shot_frame = (\d+)", text)
    shot = int(shot.group(1)) if shot else -1
    for spec in args[1:]:   # по порядку: attack:even attack:1.11 — выровнять, затем ряд целиком
        done = {}   # файл → (k, ноги): кадр стоит в анимации дважды — масштаб один раз
        anim, how = spec.split(":")
        files = frame_files(text, anim)
        ref = body_area(Image.open(files[0]).convert("RGBA")) if how == "even" else 0
        for n, f in enumerate(files):
            if f in done:
                if anim == "attack" and n == shot:   # выстрел на повторе кадра — ствол тем же преобразованием
                    text = move_muzzle(tres, text, img_size, *done[f])
                continue
            img = Image.open(f).convert("RGBA")
            if not (np.array(img)[..., 3] > 40).any():
                continue   # пустой кадр — ног нет
            k = float(how) if how != "even" else (ref / max(body_area(img), 1)) ** 0.5
            if abs(k - 1.0) < KEEP:
                continue
            p = feet(img)
            out = scale_about(img, k, p)
            a = np.array(out)[..., 3] > 40
            edge = a[0].any() or a[:, 0].any() or a[:, -1].any()
            print("  %s/%s: ×%.3f ноги (%d, %d)%s" % (anim, f.name, k, p[0], p[1], "  ВЫЛЕЗ ЗА КРАЙ" if edge else ""))
            if dry:
                continue
            out.save(f)
            done[f] = (k, p)
            img_size = img.size
            if anim == "attack" and n == shot:
                text = move_muzzle(tres, text, img.size, k, p)
    if not dry and text != orig:   # переводы строк — как были (иначе diff на весь файл)
        tres.write_bytes((text.replace("\n", "\r\n") if crlf else text).encode("utf-8"))


if __name__ == "__main__":
    main(sys.argv[1:])
