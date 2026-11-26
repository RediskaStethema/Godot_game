"""Пиксель-арт кадров зданий (решение пользователя 12.11.2026: «займись стилизацией зданий» → пиксель-арт кадров,
все здания обеих рас, все уровни) — тот же проход, что у десантной капсулы (tools/drop_pod_frames.py):
  - кадр уменьшается в PIXEL раз (среднее), PIXEL — свой у здания: пиксель арта ≈ WORLD_PX px мира на поле
    (масштаб здания — как Building._load_sprite: ширина непрозрачного idle/0 → TILE_WIDTH × SPRITE_WIDTH, рост ≤
    TILE_WIDTH × SPRITE_MAX_HEIGHT), т.е. крупный пиксель одного размера у всех зданий и у капсулы;
  - цвета — общая палитра PALETTE_SIZE на все кадры здания (все ряды и уровни — одна группа: кадры не мигают)
    без дизеринга; прозрачность — ступенями ALPHA_STEP; кромка сплошного силуэта темнее (EDGE_DARK);
  - обратно ×PIXEL без сглаживания; холст прежний (по нему muzzle / level_shift / level_scale в frames.tres),
    ширина непрозрачной части idle/0 почти та же (по ней Building считает масштаб) — расхождение печатается.
Исходники — STASH/<путь здания>/ (первый прогон копирует их туда, повторный берёт оттуда — результат тот же).

  PYTHONIOENCODING=utf-8 python tools/building_pixelize.py [--dry] [папка здания …]   (без папок — все)
затем godot --headless --path . --import
"""
import shutil
import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
BUILDINGS = ROOT / "assets/sprites/buildings"
STASH = ROOT / "assets/source_sheets/building_pixel_orig"
TILE_WIDTH = 140            # IsoGrid.TILE_WIDTH
SPRITE_WIDTH = 0.68         # Building.SPRITE_WIDTH
SPRITE_MAX_HEIGHT = 1.0625  # Building.SPRITE_MAX_HEIGHT
WORLD_PX = 1.3              # пиксель арта на поле, px мира (выбор пользователя 12.11.2026 из 0.9 / 1.3 / 1.8: детали читаются, пиксель виден вблизи)
PIXEL_RANGE = (2, 10)
PALETTE_SIZE = 48
# цветное (s > HUE_S, v > HUE_V) — своя палитра у каждого заметного тона (HUE_BINS по кругу, доля > HUE_MIN_SHARE):
# в общей медиане редкие огни гасли (лампа турели), розовый варп казарм Хаоса уходил в красный огонь жаровен
HUE_BINS = 12
HOT_V, HOT_S, HOT_SHARE = 0.75, 0.45, 0.15   # огонь в клетке пикселя (доля клетки) — её цвет из огня
HUE_S, HUE_V = 0.35, 0.25
HUE_MIN_SHARE = 0.003
HUE_COLORS = 8
ALPHA_STEP = 64
ALPHA_MIN = 40
SOLID_ALPHA = 192
EDGE_DARK = 0.6


def building_dirs(args):
    if args:
        return [Path(a).resolve() for a in args]
    return sorted(p.parent for p in BUILDINGS.rglob("frames.tres"))


def frame_files(src):
    return sorted(src.glob("*/*.png"))


def pixel_of(idle0: Image.Image) -> int:
    a = np.array(idle0)[:, :, 3]
    xs = np.nonzero(a.any(axis=0))[0]
    width = xs.max() - xs.min() + 1 if len(xs) else idle0.width
    scale = min(TILE_WIDTH * SPRITE_WIDTH / width, TILE_WIDTH * SPRITE_MAX_HEIGHT / idle0.height)
    return int(np.clip(round(WORLD_PX / scale), *PIXEL_RANGE)), scale


def used_width(im: Image.Image) -> int:
    xs = np.nonzero(np.array(im)[:, :, 3].any(axis=0))[0]
    return int(xs.max() - xs.min() + 1) if len(xs) else 0


def palette_of(rgb, n):
    im = Image.fromarray(rgb.reshape(1, -1, 3).astype(np.uint8)).quantize(n, method=Image.Quantize.MEDIANCUT)
    return np.array(im.getpalette()[:n * 3], dtype=np.float32).reshape(-1, 3)


def nearest(rgb, pal):
    flat = rgb.reshape(-1, 3)
    idx = np.empty(len(flat), dtype=np.int32)
    for i in range(0, len(flat), 65536):
        d = ((flat[i:i + 65536, None, :] - pal[None]) ** 2).sum(-1)
        idx[i:i + 65536] = d.argmin(1)
    return pal[idx].reshape(rgb.shape)


def pixelize(images: list, px: int) -> list:
    w, h = images[0].size
    pw, ph = -(-w // px) * px, -(-h // px) * px
    small = []
    for im in images:
        pad = Image.new("RGBA", (pw, ph))
        pad.paste(im, (0, 0))
        # среднее по клетке с весом альфы: цвет прозрачных пикселей (часто чёрный) не темнит кромку
        a = np.array(pad).astype(np.float32).reshape(ph // px, px, pw // px, px, 4)
        al = a[..., 3:4]
        rgb = (a[..., :3] * al).sum(axis=(1, 3)) / np.maximum(al.sum(axis=(1, 3)), 1e-6)
        # огонь в клетке (лампа, искра, жерло) — цвет клетки из огня: среднее с бронёй гасило мелкие огни
        mx, mn = a[..., :3].max(-1), a[..., :3].min(-1)
        hot = ((mx > HOT_V * 255) & ((mx - mn) / np.maximum(mx, 1) > HOT_S) & (a[..., 3] > 128)).astype(np.float32)
        n_hot = hot.sum(axis=(1, 3))
        hot_rgb = (a[..., :3] * hot[..., None]).sum(axis=(1, 3)) / np.maximum(n_hot, 1)[..., None]
        use = (n_hot >= HOT_SHARE * px * px)[..., None]
        rgb = np.where(use, hot_rgb, rgb)
        small.append(np.dstack([rgb, al.mean(axis=(1, 3))]))
    rgb = np.concatenate([s[:, :, :3][s[:, :, 3] > ALPHA_MIN] for s in small]).clip(0, 255)
    hsv = np.array(Image.fromarray(rgb.reshape(1, -1, 3).astype(np.uint8)).convert("HSV")).reshape(-1, 3) / 255.0
    color = (hsv[:, 1] > HUE_S) & (hsv[:, 2] > HUE_V)
    pal = [palette_of(rgb[~color], PALETTE_SIZE)] if (~color).sum() > PALETTE_SIZE else []
    bins = (hsv[:, 0] * HUE_BINS + 0.5).astype(int) % HUE_BINS
    for b in range(HUE_BINS):
        sel = color & (bins == b)
        if sel.sum() > max(HUE_COLORS, HUE_MIN_SHARE * len(rgb)):
            pal.append(palette_of(rgb[sel], HUE_COLORS))
    pal = np.concatenate(pal) if pal else palette_of(rgb, PALETTE_SIZE)
    out = []
    for s in small:
        q = nearest(s[:, :, :3].clip(0, 255), pal)
        alpha = s[:, :, 3]
        alpha = np.where(alpha < ALPHA_MIN, 0, np.minimum(255, np.round(alpha / ALPHA_STEP) * ALPHA_STEP))
        solid = alpha >= SOLID_ALPHA
        alpha = np.where(solid, 255, alpha)
        pad = np.pad(solid, 1)
        inner = pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:]
        q[solid & ~inner] *= EDGE_DARK
        res = Image.fromarray(np.dstack([q, alpha]).clip(0, 255).astype(np.uint8))
        out.append(res.resize((pw, ph), Image.NEAREST).crop((0, 0, w, h)))
    return out


def save(im, path, tries=20):
    """Открытый редактор Godot на миг держит кадр, пока перечитывает его, — повторить."""
    for i in range(tries):
        try:
            im.save(path)
            return
        except PermissionError:
            if i == tries - 1:
                raise
            time.sleep(0.25)


def main(args):
    global WORLD_PX
    dry = "--dry" in args
    if "--world-px" in args:   # свой размер пикселя на запуск (Хаос 21.11.2026: 0.9 вместо 1.3)
        i = args.index("--world-px")
        WORLD_PX = float(args[i + 1])
        args = args[:i] + args[i + 2:]
    for unit in building_dirs([a for a in args if not a.startswith("--")]):
        rel = unit.relative_to(BUILDINGS)
        stash = STASH / rel
        if not stash.exists() and not dry:
            shutil.copytree(unit, stash, ignore=shutil.ignore_patterns("*.import", "*.tres"))
        src = stash if stash.exists() else unit
        files = frame_files(src)
        if not files:
            continue
        idle0 = src / "idle" / "0.png"
        px, scale = pixel_of(Image.open(idle0 if idle0.exists() else files[0]).convert("RGBA"))
        # группы — кадры одного размера (у стены ряд щита может быть другого холста)
        groups = {}
        for f in files:
            im = Image.open(f).convert("RGBA")
            groups.setdefault(im.size, []).append((f, im))
        for size, items in groups.items():
            res = pixelize([im for _, im in items], px)
            for (f, im), r in zip(items, res):
                if not dry:
                    save(r, unit / f.relative_to(src))
        w0 = used_width(Image.open(idle0 if idle0.exists() else files[0]).convert("RGBA"))
        w1 = used_width(Image.open(unit / (idle0 if idle0.exists() else files[0]).relative_to(src)).convert("RGBA"))
        print(f"{rel.as_posix()}: пиксель {px} (масштаб {scale:.3f}), кадров {len(files)}, ширина idle/0 {w0} → {w1}")


if __name__ == "__main__":
    main(sys.argv[1:])
