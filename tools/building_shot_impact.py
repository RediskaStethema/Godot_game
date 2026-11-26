"""Ряды выстрела зданий-стрелков без дрожи ствола и с крупной вспышкой (решение пользователя 16.11.2026:
«у зданий проблема с фреймами пушки во время атаки, без импакта» — перерисовка Layer 15–16.11.2026: модель рисовала
стволы в кадрах выстрела чуть иначе, чем в стойке, после закрепления корпуса в зоне стволов оставались куски своего
рисунка кадра — пушка «кипела»; вспышка мелкая).

По кадрам ряда attack / attack_2 / attack_3 (уже после building_pixelize.py):
  корпус и стволы — целиком из idle_<уровень>/0; из своего кадра — только эффект: всё вне силуэта стойки (пламя, дым,
  искры) и огонь поверх корпуса (яркое тёплое, ярче стойки в этом месте);
  эффект — только у жерла (NEAR ширины кадра от точек ствола frames.tres);
  кадр shot_frame — эффект крупнее x FLASH[0] от своего заднего края (растёт вперёд от жерла), следующий — x FLASH[1].
Отдача — кодом в игре (Building.play_once: толчок KICK у любого ряда выстрела).
Чистые ряды после пиксель-прохода — assets/source_sheets/building_redesign_staging/<здание>/attack_pixel_orig/
(повтор — от них; после нового пиксель-прохода здания эту папку удалить).

  PYTHONIOENCODING=utf-8 python tools/building_shot_impact.py tower artillery fists_bastion     затем --import
"""
import re
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

import building_shot_fx as fx

ROOT = Path(__file__).resolve().parent.parent
BUILDINGS = ROOT / "assets/sprites/buildings"
KEEP = ROOT / "assets/source_sheets/building_redesign_staging"
FLASH = (1.6, 1.25)
DIFF = 40
WARM = (0.17, 0.95)
CLOSE = 0.13  # огонь поверх корпуса — только вплотную к жерлу (медь и лампы корпуса того же цвета)
NEAR = 0.3   # эффект — не дальше этой доли ширины кадра от жерла (лампы корпуса и обрывки чужого рисунка — нет)


def hsv(a):
    return np.asarray(Image.fromarray(a[..., :3]).convert("HSV")).astype(float) / 255.0


def effect_mask(f, base, near, front, close):
    d = np.abs(f.astype(int) - base.astype(int)).max(-1) > DIFF
    hf, hb = hsv(f), hsv(base)
    warm = (hf[..., 1] > 0.35) & ((hf[..., 0] < WARM[0]) | (hf[..., 0] > WARM[1]))
    brighter = hf[..., 2] - hb[..., 2] * (base[..., 3] > 0) > 0.15
    fire = (hf[..., 2] > 0.75) & (warm | (hf[..., 2] > 0.9)) & brighter   # и белое ядро вспышки
    # не огонь (дым, искры) — только вне силуэта и перед жерлом: позади него — обрывки чужого рисунка корпуса
    m = (f[..., 3] > 0) & d & near & ((fire & ((base[..., 3] == 0) | close)) | ((base[..., 3] == 0) & front))
    # дыры внутри пламени (тёмное ядро, блик) — закрыть своим же кадром
    img = Image.fromarray((m * 255).astype('uint8')).filter(ImageFilter.MaxFilter(7)).filter(ImageFilter.MinFilter(7))
    return (np.asarray(img) > 0) & (f[..., 3] > 0) & near


SMALL = 0.06   # пятна эффекта мельче этой доли крупнейшего — крошки (обрывки чужого рисунка у жерла)


def tidy(layer, flash):
    """Крошки стереть; у кадров вспышки тёмное внутри пламени (жерло кадра, блик) закрасить ядром пламени."""
    m = layer[..., 3] > 0
    if m.sum() < 8:
        return layer
    h, w = m.shape
    seen = np.zeros_like(m)
    blobs = []
    for y, x in np.argwhere(m):
        if seen[y, x]:
            continue
        stack, blob = [(y, x)], []
        seen[y, x] = True
        while stack:
            cy, cx = stack.pop()
            blob.append((cy, cx))
            for ny in (cy - 1, cy, cy + 1):
                for nx in (cx - 1, cx, cx + 1):
                    if 0 <= ny < h and 0 <= nx < w and m[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
        blobs.append(blob)
    big = max(len(b) for b in blobs)
    for b in blobs:
        if len(b) < SMALL * big:
            for cy, cx in b:
                layer[cy, cx] = 0
    if flash:
        m = layer[..., 3] > 0
        v = hsv(layer)[..., 2]
        fire = m & (v > 0.75)
        if fire.sum() > 20:
            dens = np.asarray(Image.fromarray((fire * 255).astype("uint8")).filter(ImageFilter.BoxBlur(4))) / 255.0
            dark = m & (v < 0.5) & (dens > 0.3)
            core = np.median(layer[fire & (v >= np.percentile(v[fire], 70))][:, :3], axis=0)
            layer[dark, :3] = core.astype(np.uint8)
    return layer


def grow(layer, k):
    """Слой эффекта крупнее в k раз от заднего (левого) края — вспышка растёт вперёд от жерла."""
    m = layer[..., 3] > 0
    if m.sum() < 8:
        return layer
    h, w = m.shape
    ys, xs = np.nonzero(m)
    x0, y0, x1, y1 = xs.min(), ys.min(), xs.max() + 1, ys.max() + 1
    cy = ys.mean()
    nw, nh = round((x1 - x0) * k), round((y1 - y0) * k)
    big = np.asarray(Image.fromarray(layer[y0:y1, x0:x1]).resize((nw, nh), Image.NEAREST))
    px = int(max(0, min(x0, w - nw)))   # не влезает вперёд — растёт назад, на ствол
    py = int(max(0, min(round(cy - (cy - y0) * k), h - nh)))
    out = np.zeros_like(layer)
    sx0, sy0 = max(px, 0), max(py, 0)
    sx1, sy1 = min(px + nw, w), min(py + nh, h)
    if sx1 > sx0 and sy1 > sy0:
        out[sy0:sy1, sx0:sx1] = big[sy0 - py:sy1 - py, sx0 - px:sx1 - px]
    return out


def run(rel):
    unit = BUILDINGS / rel
    text = (unit / "frames.tres").read_text(encoding="utf-8")
    shot = int(re.search(r"shot_frame = (\d+)", text).group(1))
    keep = KEEP / rel / "attack_pixel_orig"
    for level in (1, 2, 3):
        sfx = "" if level == 1 else f"_{level}"
        row = unit / f"attack{sfx}"
        if not row.exists():
            continue
        if not (keep / row.name).exists():
            shutil.copytree(row, keep / row.name, ignore=shutil.ignore_patterns("*.import"))
        base = np.array(Image.open(unit / f"idle{sfx}" / "0.png").convert("RGBA"))
        h, w = base.shape[:2]
        pts, _ = fx.level_points(text, level)
        yy, xx = np.mgrid[0:h, 0:w]
        near = np.zeros((h, w), bool)
        close = np.zeros((h, w), bool)
        for x, y in pts:
            near |= np.hypot(xx - (w / 2 + x), yy - (h + y)) <= NEAR * w
            close |= np.hypot(xx - (w / 2 + x), yy - (h + y)) <= CLOSE * w
        front = xx >= min(w / 2 + x for x, _ in pts) - 0.03 * w
        sizes = []
        for f in sorted((keep / row.name).glob("*.png"), key=lambda p: int(p.stem)):
            a = np.array(Image.open(f).convert("RGBA"))
            m = effect_mask(a, base, near, front, close)
            layer = np.zeros_like(a)
            layer[m] = a[m]
            i = int(f.stem) - shot
            layer = tidy(layer, i in (0, 1))
            if i in (0, 1):
                layer = grow(layer, FLASH[i])
            out = base.copy()
            on = layer[..., 3] > 0
            out[on] = layer[on]
            Image.fromarray(out).save(row / f.name)
            sizes.append(int(on.sum()))
        print(f"{rel}/{row.name}: эффект по кадрам, px {sizes}")


if __name__ == "__main__":
    for r in sys.argv[1:]:
        run(r)
