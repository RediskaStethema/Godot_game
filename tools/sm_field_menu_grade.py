"""Поле Космодесанта под цветокор главного меню (решение пользователя 16.11.2026: «перекрасить текстуры поля боя
космодесанта под цветокор главного меню»; выбор: бордо-фиолет как облака меню, всё поле целиком).

Было: холодная синяя сталь — тон 0.59, насыщенность 0.49, яркость 0.145. Меню: облака бордо-фиолетовые (тон 0.91,
насыщенность 0.39, яркость 0.16), камень тёплый угольный. Грунт, воронки, руины, стена, знамёна-плиты и кадры реки —
синие пиксели переводятся в тон облаков меню `TARGET_HUE` с насыщенностью ×`SAT_K`: поворот тона только у пикселей
в полосе синего (`BLUE_HUE` ± `BLUE_WIDTH`, мягкий край `BLUE_SOFT`) — тёплые (огни, золото, ржавчина, знамёна) не
трогаются, иначе стали бы зелёными. Река (бирюзовая, 0.53) поворачивается тем же сдвигом в пурпур.
Готика (props/space_marines) — не перекрашивается: её тон — `FactionTheme.GOTHIC_TINT` (теперь бордо-нейтральный).

Исходники — assets/source_sheets/sm_field_orig_2026-11-16 (повторный прогон — от них; вернуть прежний вид — `--restore`):
    python tools/sm_field_menu_grade.py [--restore]      затем  godot --headless --import
"""
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
TILES = ROOT / "assets/sprites/tiles/space_marines"
BACKUP = ROOT / "assets/source_sheets/sm_field_orig_2026-11-16"

BLUE_HUE = 0.594      # тон грунта до перекраски
BLUE_WIDTH = 0.14     # полоса, где пиксель считается «синим»
BLUE_SOFT = 0.06      # мягкий край полосы
TARGET_HUE = 0.91     # тон облаков меню
SAT_K = 0.62          # насыщенность грунта 0.49 → ≈ 0.30 (облака меню 0.39, камень 0.14)
VAL_K = 1.06          # яркость грунта 0.145 → ≈ 0.154 (облака меню 0.16)


def rgb_to_hsv(rgb: np.ndarray) -> np.ndarray:
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx, mn = rgb.max(-1), rgb.min(-1)
    d = mx - mn
    h = np.zeros_like(mx)
    nz = d > 1e-6
    rc = np.where(nz & (mx == r), ((g - b) / np.where(nz, d, 1)) % 6, 0)
    gc = np.where(nz & (mx == g) & (mx != r), (b - r) / np.where(nz, d, 1) + 2, 0)
    bc = np.where(nz & (mx == b) & (mx != r) & (mx != g), (r - g) / np.where(nz, d, 1) + 4, 0)
    h = (rc + gc + bc) / 6.0 % 1.0
    s = np.where(mx > 1e-6, d / np.where(mx > 1e-6, mx, 1), 0)
    return np.stack([h, s, mx], -1)


def hsv_to_rgb(hsv: np.ndarray) -> np.ndarray:
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    i = np.floor(h * 6).astype(int) % 6
    f = h * 6 - np.floor(h * 6)
    p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    r = np.choose(i, [v, q, p, p, t, v])
    g = np.choose(i, [t, v, v, q, p, p])
    b = np.choose(i, [p, p, t, v, v, q])
    return np.stack([r, g, b], -1)


def blue_weight(h: np.ndarray, s: np.ndarray) -> np.ndarray:
    dist = np.abs(((h - BLUE_HUE) + 0.5) % 1.0 - 0.5)
    w = 1.0 - np.clip((dist - BLUE_WIDTH) / BLUE_SOFT, 0.0, 1.0)
    return w * np.clip(s / 0.12, 0.0, 1.0)   # почти серые пиксели тон не несут — не красим скачком


def grade(src: Path, dst: Path) -> None:
    im = Image.open(src).convert("RGBA")
    a = np.asarray(im).astype(np.float32)
    hsv = rgb_to_hsv(a[..., :3] / 255.0)
    w = blue_weight(hsv[..., 0], hsv[..., 1])
    dh = TARGET_HUE - BLUE_HUE
    hsv[..., 0] = (hsv[..., 0] + dh * w) % 1.0
    hsv[..., 1] = np.clip(hsv[..., 1] * (1.0 + (SAT_K - 1.0) * w), 0.0, 1.0)
    hsv[..., 2] = np.clip(hsv[..., 2] * (1.0 + (VAL_K - 1.0) * w), 0.0, 1.0)
    out = np.dstack([hsv_to_rgb(hsv) * 255.0, a[..., 3]])
    Image.fromarray(np.clip(out + 0.5, 0, 255).astype(np.uint8)).save(dst)


def main() -> None:
    files = sorted(TILES.glob("*.png"))
    if "--restore" in sys.argv:
        for f in files:
            if (BACKUP / f.name).exists():
                shutil.copy2(BACKUP / f.name, f)
        print("исходные плиты возвращены")
        return
    BACKUP.mkdir(parents=True, exist_ok=True)
    for f in files:
        src = BACKUP / f.name
        if not src.exists():
            shutil.copy2(f, src)
        grade(src, f)
    print(f"{len(files)} плит перекрашено (тон {BLUE_HUE} -> {TARGET_HUE}, насыщенность ×{SAT_K}, яркость ×{VAL_K})")


if __name__ == "__main__":
    main()
