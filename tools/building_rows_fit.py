"""Ряды листа здания одного масштаба со стойкой: на листах пользователя выстрел / пополнение / щит
нарисованы мельче idle (Казармы — ×0.75), и здание «сжимается» на время анимации. Каждый ряд
масштабируется так, чтобы ширина основания его первого кадра совпала с idle, и сдвигается — основание
в той же точке холста, что у idle (здание не прыгает). Холст не меняется; ствол (metadata/muzzle в
frames.tres — по ряду attack) пересчитывается тем же преобразованием.

    python tools/building_rows_fit.py <папка здания> [--skip anim,anim] [--scale anim:k] [--align]

--align — ещё и каждый кадр по основанию 1-го кадра idle (кадры листа нарисованы с разбросом).

Основание — как Building.find_base: самая широкая строка силуэта в нижних BASE_ZONE кадра, выше
нижнего пикселя на четверть её ширины. --skip — ряды, где основание шире из-за эффекта (кольца молнии
Шпиля варпа). --scale — масштаб ряда вручную (Hellfire Mortar: ствол в выстреле задран, основание
уже — по нему ряд вышел бы крупнее). Масштаб ближе FIT_TOLERANCE к 1 — только сдвиг.
"""
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

BASE_ZONE = 0.4
ALPHA = 127
FIT_TOLERANCE = 0.04


def find_base(img):
    a = np.array(img)[..., 3]
    ys, xs = np.nonzero(a > 0)
    if not len(ys):
        return None
    y0, y1 = ys.min(), ys.max() + 1
    best, cx = 0, (xs.min() + xs.max() + 1) / 2
    for y in range(y1 - 1, max(y0, y1 - int((y1 - y0) * BASE_ZONE)) - 1, -1):
        r = np.nonzero(a[y] > ALPHA)[0]
        if len(r) and r[-1] - r[0] + 1 > best:
            best, cx = r[-1] - r[0] + 1, (r[0] + r[-1] + 1) / 2
    return best, np.array([cx, y1 - best / 4])


ALIGN_ZONE = 0.35   # постамент — нижняя доля силуэта idle: по нему совпадают кадры
ALIGN_RANGE = (40, 16)   # поиск сдвига ± px по x, y


def _mask(img, y0, y1):
    return (np.array(img)[y0:y1, :, 3] > 200).astype(np.int32)


def align_frames(folder):
    """Каждый кадр каждого ряда сдвигается так, чтобы его постамент (нижние ALIGN_ZONE силуэта) совпал с
    постаментом 1-го кадра idle — по наибольшему перекрытию масок: кадры листа нарисованы с разбросом
    5–25 px, и здание дрожит (решение пользователя 19.10.2026: турель «слишком резко переходит из кадра
    в кадр»). Ширина основания для этого не годится — гильзы и дым у ног её раздувают."""
    ref_img = Image.open(folder / "idle" / "0.png").convert("RGBA")
    ys = np.nonzero(np.array(ref_img)[..., 3] > 200)[0]
    y1 = ys.max() + 1
    y0 = y1 - int((y1 - ys.min()) * ALIGN_ZONE)
    rx, ry = ALIGN_RANGE
    ref = np.pad(_mask(ref_img, y0, y1), ((0, 0), (rx, rx)))
    for sub in sorted(p for p in folder.iterdir() if p.is_dir()):
        for f in frames_of(sub):
            img = Image.open(f).convert("RGBA")
            best, shift = -1, (0, 0)
            for dy in range(-ry, ry + 1):
                if y0 - dy < 0 or y1 - dy > img.height:
                    continue
                m = _mask(img, y0 - dy, y1 - dy)
                for dx in range(-rx, rx + 1):
                    score = int((ref[:, rx + dx:rx + dx + m.shape[1]] & m).sum())
                    if score > best:
                        best, shift = score, (dx, dy)
            if shift == (0, 0):
                continue
            out = Image.new("RGBA", img.size, (0, 0, 0, 0))
            out.paste(img, shift, img)
            out.save(f)
            if sub.name == "attack" and f.stem == str(_shot_frame(folder / "frames.tres")):
                _shift_muzzle(folder / "frames.tres", shift)   # снаряд — из ствола сдвинутого кадра
            print(f"  {sub.name}/{f.name}: сдвиг {shift}")


def _shot_frame(tres):
    m = re.search(r"metadata/shot_frame = (\d+)", tres.read_text(encoding="utf-8"))
    return int(m.group(1)) if m else -1


def _shift_muzzle(tres, shift):
    text = tres.read_text(encoding="utf-8")
    m = re.search(r"metadata/muzzle = Vector2\(([-\d.]+), ([-\d.]+)\)", text)
    if m:
        tres.write_text(text.replace(m.group(0), "metadata/muzzle = Vector2(%.1f, %.1f)" % (
            float(m.group(1)) + shift[0], float(m.group(2)) + shift[1])), encoding="utf-8")


def frames_of(d):
    return sorted(d.glob("*.png"), key=lambda p: int(p.stem))


def main(args):
    folder = Path(args[0])
    skip = set(args[args.index("--skip") + 1].split(",")) if "--skip" in args else set()
    manual = {}
    if "--scale" in args:
        anim, k = args[args.index("--scale") + 1].split(":")
        manual[anim] = float(k)
    idle = find_base(Image.open(folder / "idle" / "0.png").convert("RGBA"))
    for sub in sorted(p for p in folder.iterdir() if p.is_dir() and p.name != "idle"):
        files = frames_of(sub)
        if not files:
            continue
        w, point = find_base(Image.open(files[0]).convert("RGBA"))
        k = idle[0] / w if sub.name not in skip else 1.0
        k = manual.get(sub.name, k)
        if abs(k - 1.0) < FIT_TOLERANCE:
            k = 1.0
        for f in files:
            img = Image.open(f).convert("RGBA")
            size = img.size
            scaled = img.resize((round(size[0] * k), round(size[1] * k)), Image.LANCZOS) if k != 1.0 else img
            shift = idle[1] - point * k
            out = Image.new("RGBA", size, (0, 0, 0, 0))
            out.paste(scaled, (round(shift[0]), round(shift[1])), scaled)
            out.save(f)
        if sub.name == "attack":
            _move_muzzle(folder / "frames.tres", size, point, idle[1], k)
        print(f"{folder.name}/{sub.name}: x{k:.2f}, сдвиг {np.round(idle[1] - point * k, 1)}")
    if "--align" in args:
        align_frames(folder)


def _move_muzzle(tres, size, point, target, k):
    """muzzle — от центра низа холста (sheet_to_frames): в холст, тем же преобразованием, обратно."""
    text = tres.read_text(encoding="utf-8")
    m = re.search(r"metadata/muzzle = Vector2\(([-\d.]+), ([-\d.]+)\)", text)
    if not m:
        return
    p = np.array([size[0] / 2 + float(m.group(1)), size[1] + float(m.group(2))])
    q = target + (p - point) * k - np.array([size[0] / 2, size[1]])
    tres.write_text(text.replace(m.group(0), "metadata/muzzle = Vector2(%.1f, %.1f)" % (q[0], q[1])), encoding="utf-8")


if __name__ == "__main__":
    main(sys.argv[1:])
