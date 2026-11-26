"""Нарезка листов боссов, перерисованных в Layer (решение пользователя 24.11.2026: «нарежь и замени боссов»), в «пакет» для
`tools/boss_frames.py` (<босс>/<ряд>/NN.png, прозрачный фон, ячейки в масштабе старых кадров).

Листы — `assets/source_sheets/boss_redraw_v1_2026-11-23/<id>/gen/<ряд>.png` (ответ image.edit, фон НЕПРОЗРАЧНЫЙ — тёмный
размытый градиент; remove_background у Layer (birefnet-v2) на листе из 12 фигур вернул пустую альфу, поэтому фон режется кодом):
  - градиент соседних пикселей (максимум разности по каналам со всеми четырьмя соседями) < `FLAT`: «гладко» — фон;
  - заливка (torch, max_pool) от периметра каждой ячейки по гладким пикселям; тёмный контур фигуры 1 px — преграда;
  - всё, что не залито, — фигура; крошки (открытие 3×3 + 4 px) убираются.
Сетка — по числу столбцов / рядов (Layer перекладывает лист в другой аспект: ячейки равные, делить по числу).
Масштаб — один на босса: стойка (медиана высоты кадров idle) → прежний `figure_height` × 2 (boss_frames сожмёт ×0.5).
Какой из вариантов листа взят — `CHOICE` (последние перегенерации по времени файла).
  python tools/boss_slice.py [id босса …]   # → assets/source_sheets/boss_redraw_v1_2026-11-23/pack/<id>/…
  python tools/boss_frames.py assets/source_sheets/boss_redraw_v1_2026-11-23/pack   # → assets/units/bosses (+ цветокор)
Прежние кадры — assets/source_sheets/_backup_before_boss_redraw_2026-11-24/bosses.
"""
import re
import sys
from pathlib import Path

import numpy as np
import torch
import torch.nn.functional as F
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets/source_sheets/boss_redraw_v1_2026-11-23"
OUT = SRC / "pack"
BOSSES = ROOT / "assets/units/bosses"
ROWS = {"idle": (6, 2), "run": (6, 2), "attack": (6, 2), "special": (4, 4), "death": (4, 4), "appear": (4, 4)}
CHOICE = {("daemon_angron", "attack"): "attack2", ("daemon_angron", "special"): "special2", ("daemon_angron", "appear"): "appear2",
          ("daemon_fulgrim", "attack"): "attack_A", ("primarch_vulkan", "run"): "run_v3A"}
FLAT = {}          # порог по боссу (по умолчанию DEFAULT_FLAT)
DEFAULT_FLAT = 4.0
SKIP = {"primarch_vulkan": ["appear"]}
PACK_DIR = {"run": "walk"}
# Ряды, нарисованные лицом влево: в игре спрайт «смотрит вправо» (врагов Soldier отражает к армии игрока) — отразить при нарезке.
# Вулкан (24.11.2026, «в начале повернут не в сторону армии игрока»): idle / attack / special / death влево, бег вправо
# Русс (24.11.2026, то же замечание): idle / death / appear влево, бег / атака / special вправо
FLIP = {"primarch_vulkan": ["idle", "attack", "special", "death"], "primarch_russ": ["idle", "death", "appear"]}


def shifted(a, dx, dy):
    h, w = a.shape[2:]
    return F.pad(a, (1, 1, 1, 1), mode="replicate")[:, :, 1 + dy:1 + dy + h, 1 + dx:1 + dx + w]


DEVICE = "cuda" if torch.cuda.is_available() else "cpu"   # заливка на видеокарте — ~10× быстрее, чем на процессоре


def cut_background(rgb, cols, rows, flat):
    """rgb: H×W×3 uint8 → маска фигуры H×W (bool)."""
    a = torch.from_numpy(rgb).float().permute(2, 0, 1)[None].to(DEVICE)
    h, w = a.shape[2:]
    g = torch.zeros(1, 1, h, w, device=DEVICE)
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        g = torch.maximum(g, (a - shifted(a, dx, dy)).abs().amax(1, keepdim=True))
    smooth = (g < flat).float()
    cw, ch = w // cols, h // rows
    bg = torch.zeros(1, 1, h, w, device=DEVICE)
    for r in range(rows):
        for c in range(cols):
            x0, y0 = c * cw, r * ch
            bg[:, :, y0, x0:x0 + cw] = 1
            bg[:, :, y0 + ch - 1, x0:x0 + cw] = 1
            bg[:, :, y0:y0 + ch, x0] = 1
            bg[:, :, y0:y0 + ch, x0 + cw - 1] = 1
    bg = bg * smooth
    prev = -1.0
    for i in range(4000):
        bg = F.max_pool2d(bg, 3, 1, 1) * smooth
        if i % 20 == 0:
            s = bg.sum().item()
            if s == prev:
                break
            prev = s
    fg = 1 - bg
    # крошки: открытие 3×3, оставляем всё в 4 px от открытого
    opened = -F.max_pool2d(-fg, 3, 1, 1)
    opened = F.max_pool2d(opened, 3, 1, 1)
    near = F.max_pool2d(opened, 9, 1, 4)
    return ((fg * near)[0, 0].cpu().numpy() > 0.5), (opened[0, 0].cpu().numpy() > 0.5)


EDGE_GAP = 4         # зазор (px), отделяющий кусок от тела
EDGE_NEAR = 0.1      # «у границы ячейки» — в этой доле размера от верха / боков (обрывок начинается не вплотную к линии сетки)
EDGE_MIN = 0.12      # и весит не меньше этой доли тела: мелкие частицы (лепестки, дым, искры) — не обрывки


def _segments(has):
    idx = np.where(has)[0]
    if len(idx) == 0:
        return []
    segs, start = [], idx[0]
    for a, b in zip(idx[:-1], idx[1:]):
        if b - a > EDGE_GAP:
            segs.append((start, a + 1))
            start = b
    segs.append((start, idx[-1] + 1))
    return segs


def drop_edge_bleed(im):
    """Обрывки фигур соседних ячеек: не главный кусок, отделённый зазором и касающийся верха или боков ячейки — стереть.
    Низ не трогаем: оружие и тело лежащего на земле касаются нижней границы законно (молот Вулкана, алебарда Сангвиния)."""
    arr = np.array(im)
    for axis in (0, 1):   # 0 — куски по высоте (сверху / снизу), 1 — по ширине (слева / справа)
        m = arr[..., 3] > 40
        has = m.any(1 - axis)
        segs = _segments(has)
        if len(segs) < 2:
            continue
        weight = [m[a:b].sum() if axis == 0 else m[:, a:b].sum() for a, b in segs]
        main = int(np.argmax(weight))
        size = arr.shape[axis]
        for i, (a, b) in enumerate(segs):
            near = EDGE_NEAR * size
            touches = (a <= near) if axis == 0 else (a <= near or b >= size - near)
            if i != main and touches and weight[i] >= EDGE_MIN * weight[main]:
                if axis == 0:
                    arr[a:b, :, 3] = 0
                else:
                    arr[:, a:b, 3] = 0
    return Image.fromarray(arr)


PAD_X, PAD_Y = 0.3, 0.5   # поля вокруг ячейки: boss_frames масштабирует и сдвигает кадры на холсте ячейки — без полей верх / низ срезались


def pad_cell(im):
    px, py = round(im.width * PAD_X), round(im.height * PAD_Y)
    out = Image.new("RGBA", (im.width + 2 * px, im.height + 2 * py), (0, 0, 0, 0))
    out.paste(im, (px, py))
    return out


def old_figure_height(boss):
    m = re.search(r"metadata/figure_height = ([\d.]+)", (BOSSES / boss / "frames.tres").read_text(encoding="utf-8"))
    return float(m.group(1))


def sheet_path(boss, row):
    return SRC / boss / "gen" / (CHOICE.get((boss, row), row) + ".png")


def slice_boss(boss):
    print(boss)
    flat = FLAT.get(boss, DEFAULT_FLAT)
    cells = {}   # ряд → [(RGBA ячейки, bbox открытой маски)]
    for row, (cols, nrows) in ROWS.items():
        if row in SKIP.get(boss, []):
            continue
        p = sheet_path(boss, row)
        im = Image.open(p).convert("RGB")
        rgb = np.array(im)
        fg, opened = cut_background(rgb, cols, nrows, flat)
        h, w = fg.shape
        cw, ch = w // cols, h // nrows
        rgba = np.dstack([rgb, (fg * 255).astype(np.uint8)])
        out = []
        for i in range(cols * nrows):
            x0, y0 = (i % cols) * cw, (i // cols) * ch
            cell = Image.fromarray(rgba[y0:y0 + ch, x0:x0 + cw])
            box = Image.fromarray((opened[y0:y0 + ch, x0:x0 + cw] * 255).astype(np.uint8)).getbbox()
            out.append((cell, box))
        cells[row] = out
        print(f"  {row:8s} {p.name:12s} {w}x{h} ячейка {cw}x{ch} фигура {fg.mean():.2f}")
    idle_h = float(np.median([b[3] - b[1] for _, b in cells["idle"] if b]))
    k = old_figure_height(boss) * 2.0 / idle_h
    print(f"  стойка {idle_h:.0f} px, масштаб x{k:.3f}")
    for row, frames in cells.items():
        d = OUT / boss / PACK_DIR.get(row, row)   # boss_frames читает ряд бега из папки walk
        d.mkdir(parents=True, exist_ok=True)
        for old in d.glob("*.png"):
            old.unlink()
        for i, (cell, _) in enumerate(frames):
            big = cell.convert("RGBa").resize((round(cell.width * k), round(cell.height * k)), Image.LANCZOS).convert("RGBA")
            big = pad_cell(drop_edge_bleed(big))
            if row in FLIP.get(boss, []):
                big = big.transpose(Image.FLIP_LEFT_RIGHT)
            big.save(d / f"{i:02d}.png")


def main(argv):
    torch.set_grad_enabled(False)
    for boss in argv or sorted(p.name for p in BOSSES.iterdir() if p.is_dir()):
        slice_boss(boss)


if __name__ == "__main__":
    main(sys.argv[1:])
