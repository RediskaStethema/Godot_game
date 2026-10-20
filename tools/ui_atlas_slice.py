"""Атласы интерфейса assets/ui/assets (пакет пользователя 20.10.2026, atlas_manifest.json) → отдельные PNG.

Ячейки сетки манифеста неровные, иконки касаются друг друга (цепи эмблем): граница ячейки — самая
прозрачная строка / столбец около линии сетки (столбцы — отдельно в каждом ряду), в ячейке остаются
крупные пятна силуэта (обрывки соседей у края — прочь), кадр — по ним. Ореол (альфа < HALO_ALPHA) срезан. Картинка уменьшается
до MAX_SIDE по большей стороне (LANCZOS) — в игре иконки мельче, а атлас в 1–2 тыс. px.

    python tools/ui_atlas_slice.py [assets/ui/assets] [assets/ui]

Выход: <out>/<папка>/<имя>.png, имена — NAMES ниже (пустые ячейки пропускаются).
"""
import json
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

HALO_ALPHA = 40      # мягкий ореол листа — прочь
MASK_ALPHA = 60      # пятна силуэта ищутся по этой альфе
DOWN = 4             # пятна ищутся на уменьшенной маске (быстрее, крошки рядом сливаются)
SEARCH = 0.2         # граница ячейки ищется в ± этой доли ячейки от линии сетки
KEEP_SHARE = 0.08    # в ячейке остаются пятна не меньше этой доли самого крупного (обрывки соседей — прочь)
PAD = 4

# атлас → (папка, имена ячеек по порядку манифеста, наибольшая сторона px)
NAMES = {
    "ui/cards/upgrade_event_atlas.png": ("cards", [
        "blessed_armour", "battle_fury", "iron_halo", "combat_stimms", "chapter_banner",
        "emergency_reinforcements", "orbital_strike", "daemonic_armour", "blood_rage", "warp_ward",
        "combat_drugs", "icon_of_chaos", "cult_uprising", "warp_strike", None, None], 256),
    "ui/icons/faction_emblems_atlas.png": ("emblems", [
        "ultramarines", "imperial_fists", "blood_angels", "space_wolves", "salamanders",
        "khorne", "nurgle", "tzeentch", "slaanesh"], 192),
    "ui/icons/synergy_row_atlas.png": ("synergy", [
        "marine_3", "marine_6", "chaos_3", "chaos_6", "elite_2", "front_row", "rear_row", None], 96),
    "ui/icons/hud_atlas.png": ("hud", [
        "requisition", "citadel_hp", "shield", "wave", "cannon_ready", "cannon_cooldown"], 96),
    "ui/icons/run_ribbon_atlas.png": ("ribbon", [
        "wave", "miniboss", "boss", "event", "current"], 96),
    "ui/cards/battle_result_banners_atlas.png": ("banners", ["victory", "defeat"], 1024),
    "ui/frames/card_rarity_frames_atlas.png": ("rarity", ["common", "rare", "epic"], 448),
    "ui/icons/race_selection_atlas.png": ("races", ["space_marines", "chaos", "necrons"], 256),
    "ui/screens/expansion_blueprint.png": ("screens", ["expansion_blueprint"], 384),
}


def label(mask):
    """Связные пятна (8 соседей): массив номеров, 0 — фон."""
    h, w = mask.shape
    lab = np.zeros((h, w), np.int32)
    n = 0
    for y0, x0 in zip(*np.nonzero(mask)):
        if lab[y0, x0]:
            continue
        n += 1
        lab[y0, x0] = n
        q = deque([(y0, x0)])
        while q:
            y, x = q.popleft()
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < h and 0 <= xx < w and mask[yy, xx] and not lab[yy, xx]:
                        lab[yy, xx] = n
                        q.append((yy, xx))
    return lab, n


def best_cut(counts, center, reach):
    """Номер строки / столбца около center (± reach) с наименьшим числом непрозрачных пикселей."""
    lo, hi = max(int(center - reach), 1), min(int(center + reach), len(counts) - 1)
    return lo + int(np.argmin(counts[lo:hi])) if hi > lo else int(center)


def cuts(counts, parts):
    """Границы частей: линии сетки, сдвинутые в самые прозрачные места (± SEARCH доли части)."""
    step = len(counts) / parts
    return [0] + [best_cut(counts, step * i, step * SEARCH) for i in range(1, parts)] + [len(counts)]


def slice_atlas(path, grid, names, max_side):
    img = np.array(Image.open(path).convert("RGBA"))
    img[img[:, :, 3] < HALO_ALPHA] = 0
    solid = img[:, :, 3] >= MASK_ALPHA
    cols, rows = grid
    ys = cuts(solid.sum(axis=1), rows)
    out = {}
    for cell, name in enumerate(names):
        if name is None:
            continue
        r, c = divmod(cell, cols)
        band = solid[ys[r]:ys[r + 1]]
        xs = cuts(band.sum(axis=0), cols)
        y0, y1, x0, x1 = ys[r], ys[r + 1], xs[c], xs[c + 1]
        crop = img[y0:y1, x0:x1].copy()
        # обрывки соседей у краёв ячейки — прочь: пятна меньше KEEP_SHARE самого крупного
        m = solid[y0:y1, x0:x1]
        h, w = m.shape
        small = m[: h // DOWN * DOWN, : w // DOWN * DOWN]
        small = small.reshape(h // DOWN, DOWN, w // DOWN, DOWN).any(axis=(1, 3))
        lab, n = label(small)
        if n == 0:
            print(f"  {name}: пусто")
            continue
        areas = np.bincount(lab.ravel())[1:]
        keep_ids = [i + 1 for i, a in enumerate(areas) if a >= areas.max() * KEEP_SHARE]
        keep = np.kron(np.isin(lab, keep_ids), np.ones((DOWN, DOWN), bool))
        keep = np.pad(keep, ((0, h - keep.shape[0]), (0, w - keep.shape[1])), constant_values=False)
        crop[~keep] = 0
        yy, xx = np.nonzero(crop[:, :, 3])
        crop = crop[max(yy.min() - PAD, 0):yy.max() + PAD + 1, max(xx.min() - PAD, 0):xx.max() + PAD + 1]
        im = Image.fromarray(crop)
        k = max_side / max(im.size)
        if k < 1:
            im = im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)
        out[name] = im
    return out


def main():
    src = Path(sys.argv[1] if len(sys.argv) > 1 else "assets/ui/assets")
    dst = Path(sys.argv[2] if len(sys.argv) > 2 else "assets/ui")
    manifest = json.loads((src / "atlas_manifest.json").read_text(encoding="utf-8"))
    for atlas in manifest["atlases"]:
        f = atlas["file"]
        if f not in NAMES:
            print(f"{f}: нет в NAMES — пропуск")
            continue
        folder, names, side = NAMES[f]
        print(f)
        for name, im in slice_atlas(src / f, atlas["grid"], names, side).items():
            p = dst / folder / f"{name}.png"
            p.parent.mkdir(parents=True, exist_ok=True)
            im.save(p)
            print(f"  {p} {im.size}")


if __name__ == "__main__":
    main()
