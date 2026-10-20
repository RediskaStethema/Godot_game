"""Стабилизация кадров здания: каждый кадр каждого ряда подгоняется к 1-му кадру idle по масштабу и сдвигу
(решение пользователя 21.10.2026: у турели и казарм Хаоса кадры выстрела и пополнения нарисованы
в разном масштабе и со сдвигом — здание прыгает и меняет размер). building_rows_fit.py --align двигал
кадры, но не масштабировал; здесь — масштаб + сдвиг по наибольшему пересечению масок «тела» здания.

    python tools/building_stabilize.py <папка здания> [<папка здания> …] [--dry]

Тело — непрозрачные тёмные пиксели (камень, металл): огонь, варп, вспышки и дым светлее, по ним не
равняем. Поиск грубо (¼ разрешения), затем точно. Ствол (metadata/muzzle в frames.tres, от центра низа
холста) пересчитывается тем же преобразованием кадра выстрела. Холст не меняется.
"""
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

BODY_ALPHA = 200
BODY_MAX_VALUE = 150          # ярче — эффект, не тело
SCALES = (0.8, 1.25)
COARSE = 4                    # грубый поиск — в 4 раза мельче
COARSE_SCALE_STEP = 0.01
COARSE_SHIFT = 14             # ± px грубой сетки (×4 — в кадре)
FINE_SCALE = (0.012, 0.003)   # ± и шаг уточнения масштаба
FINE_SHIFT = 5
KEEP_SCALE = 0.004            # масштаб ближе к 1 — только сдвиг, без пересэмплирования
MIN_GAIN = 0.004              # подгонка лучше «как есть» меньше чем на столько — кадр не трогаем


def frames_of(d):
    return sorted(d.glob("*.png"), key=lambda p: int(p.stem))


def body_mask(img):
    a = np.array(img).astype(np.int32)
    return (a[..., 3] > BODY_ALPHA) & (a[..., :3].max(axis=2) < BODY_MAX_VALUE)


def anchor_of(mask):
    ys, xs = np.nonzero(mask)
    return np.array([(xs.min() + xs.max()) / 2.0, float(ys.max())])


def warp_mask(mask, k, anchor, target, shape):
    """Маска, масштабированная ×k вокруг anchor и перенесённая так, что anchor → target."""
    h, w = shape
    yy, xx = np.mgrid[0:h, 0:w]
    sx = np.round((xx - target[0]) / k + anchor[0]).astype(int)
    sy = np.round((yy - target[1]) / k + anchor[1]).astype(int)
    ok = (sx >= 0) & (sx < mask.shape[1]) & (sy >= 0) & (sy < mask.shape[0])
    out = np.zeros(shape, bool)
    out[ok] = mask[sy[ok], sx[ok]]
    return out


def iou(a, b):
    u = (a | b).sum()
    return (a & b).sum() / u if u else 0.0


def shrink(mask, f):
    h, w = mask.shape[0] // f * f, mask.shape[1] // f * f
    return mask[:h, :w].reshape(h // f, f, w // f, f).mean(axis=(1, 3)) > 0.5


def register(mask, ref, anchor):
    """(k, сдвиг anchor, iou): кадр ×k вокруг anchor, затем сдвиг — лучшее совпадение с ref."""
    sm, sr, sa = shrink(mask, COARSE), shrink(ref, COARSE), anchor / COARSE
    best = (iou(sm, sr), 1.0, np.zeros(2))
    for k in np.arange(SCALES[0], SCALES[1] + 1e-9, COARSE_SCALE_STEP):
        base = warp_mask(sm, k, sa, sa, sr.shape)
        for dy in range(-COARSE_SHIFT, COARSE_SHIFT + 1):
            rolled = np.roll(base, dy, axis=0)
            for dx in range(-COARSE_SHIFT, COARSE_SHIFT + 1):
                s = iou(np.roll(rolled, dx, axis=1), sr)
                if s > best[0]:
                    best = (s, k, np.array([dx, dy], float))
    _, k0, d0 = best
    d0 = d0 * COARSE
    best = (iou(mask, ref), 1.0, np.zeros(2))
    for k in np.arange(k0 - FINE_SCALE[0], k0 + FINE_SCALE[0] + 1e-9, FINE_SCALE[1]):
        base = warp_mask(mask, k, anchor, anchor, ref.shape)
        for dy in range(int(d0[1]) - FINE_SHIFT, int(d0[1]) + FINE_SHIFT + 1):
            rolled = np.roll(base, dy, axis=0)
            for dx in range(int(d0[0]) - FINE_SHIFT, int(d0[0]) + FINE_SHIFT + 1):
                s = iou(np.roll(rolled, dx, axis=1), ref)
                if s > best[0]:
                    best = (s, k, np.array([dx, dy], float))
    return best[1], best[2], best[0]


def apply(img, k, anchor, shift):
    size = img.size
    if abs(k - 1.0) < KEEP_SCALE:
        out = Image.new("RGBA", size, (0, 0, 0, 0))
        out.paste(img, (int(shift[0]), int(shift[1])), img)
        return out
    # Точка p кадра → anchor + (p − anchor)·k + shift; affine у PIL — обратное отображение
    t = anchor + shift
    return img.transform(size, Image.AFFINE, (1 / k, 0, anchor[0] - t[0] / k, 0, 1 / k, anchor[1] - t[1] / k),
                         resample=Image.BICUBIC)


def shot_frame(tres):
    m = re.search(r"metadata/shot_frame = (\d+)", tres.read_text(encoding="utf-8"))
    return int(m.group(1)) if m else -1


def move_muzzle(tres, size, k, anchor, shift):
    text = tres.read_text(encoding="utf-8")
    m = re.search(r"metadata/muzzle = Vector2\(([-\d.]+), ([-\d.]+)\)", text)
    if not m:
        return
    p = np.array([size[0] / 2 + float(m.group(1)), size[1] + float(m.group(2))])
    q = anchor + (p - anchor) * k + shift - np.array([size[0] / 2, size[1]])
    tres.write_text(text.replace(m.group(0), "metadata/muzzle = Vector2(%.1f, %.1f)" % (q[0], q[1])), encoding="utf-8")


def stabilize(folder, dry):
    ref_img = Image.open(folder / "idle" / "0.png").convert("RGBA")
    ref = body_mask(ref_img)
    anchor = anchor_of(ref)
    tres = folder / "frames.tres"
    shot = shot_frame(tres) if tres.exists() else -1
    for sub in sorted(p for p in folder.iterdir() if p.is_dir()):
        for f in frames_of(sub):
            if sub.name == "idle" and f.stem == "0":
                continue
            img = Image.open(f).convert("RGBA")
            mask = body_mask(img)
            if not mask.any():
                continue
            before = iou(mask, ref)
            k, shift, after = register(mask, ref, anchor)
            if after - before < MIN_GAIN or (abs(k - 1) < KEEP_SCALE and not shift.any()):
                print(f"  {folder.name}/{sub.name}/{f.name}: как есть ({before:.3f})")
                continue
            print(f"  {folder.name}/{sub.name}/{f.name}: x{k:.3f} сдвиг {shift.astype(int)}  {before:.3f} -> {after:.3f}")
            if dry:
                continue
            apply(img, k, anchor, shift).save(f)
            if sub.name == "attack" and f.stem == str(shot):
                move_muzzle(tres, img.size, k, anchor, shift)


def main(args):
    dry = "--dry" in args
    for a in args:
        if not a.startswith("--"):
            stabilize(Path(a), dry)


if __name__ == "__main__":
    main(sys.argv[1:])
