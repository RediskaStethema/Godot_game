"""Огни кораблей главного меню (решение пользователя 16.11.2026: «когда наводится на раздел меню — 50% окон в кораблях
горят ярче»). Огни ship_N_glow_00..03 в пакете NewAssets/07_ui пустые (альфа 0), поэтому огни — из самих спрайтов:
тёплые яркие пиксели (окна, лампы) → слои для ADD поверх корабля:
  ship_N_glow.png          — все огни маленького корабля (N = 1..3) с мягким ореолом, дышит в игре всегда (слабо);
  ship_N_glow_half.png     — каждое второе окно корабля (по порядку слева направо), ореол крупнее; в игре проявляется,
                             пока курсор на кнопке меню (MenuSceneArt.set_menu_hover);
  menu_capital_ship_glow_half.png — то же для флагмана (его огни нарисованы в спрайте — постоянного слоя нет);
  menu_castle_battlement_glow.png — все окна башни (свет в них при курсоре на кнопке меню).
Окно = связное пятно тёплых пикселей (соседство 8 + зазор 1 px). Прежние ship_N_glow_00..03 удаляются.

  python tools/menu_ships_glow.py        затем  godot --headless --import
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ANIM = Path(__file__).resolve().parent.parent / "assets/ui/menu/anim"
# Ореол узкий и слабый (решение пользователя 16.11.2026: «загораться должен свет в окнах, но не сами корабли» — широкий
# ореол 2.4–4 px при 0.55–0.7 заливал светом корпус и корабль вспыхивал целиком)
HALO = {"ship": 1.2, "capital": 1.6, "castle": 1.8}      # радиус размытия ореола, px спрайта
HALO_ALPHA = {"ship": 0.3, "capital": 0.35, "castle": 0.4}
WARM = (255, 150, 60)
CASTLE_GAIN = 1.0   # прозрачность слоя окон башни (цвет стекла берётся из спрайта, ADD удваивает его яркость)


def lit_mask(im: Image.Image) -> np.ndarray:
    hsv = np.asarray(im.convert("RGB").convert("HSV")).astype(float) / 255.0
    a = np.asarray(im)[..., 3]
    return (a > 200) & (hsv[..., 2] > 0.6) & (hsv[..., 1] > 0.4) & ((hsv[..., 0] < 0.13) | (hsv[..., 0] > 0.95))


def blobs(mask: np.ndarray) -> list:
    """Связные пятна маски (соседство 8, зазор 1 px) — списки точек (y, x)."""
    h, w = mask.shape
    grown = np.asarray(Image.fromarray((mask * 255).astype("uint8")).filter(ImageFilter.MaxFilter(3))) > 0
    seen = np.zeros_like(grown)
    out = []
    for y, x in np.argwhere(grown):
        if seen[y, x]:
            continue
        stack, pts = [(y, x)], []
        seen[y, x] = True
        while stack:
            cy, cx = stack.pop()
            if mask[cy, cx]:
                pts.append((cy, cx))
            for ny in (cy - 1, cy, cy + 1):
                for nx in (cx - 1, cx, cx + 1):
                    if 0 <= ny < h and 0 <= nx < w and grown[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
        if pts:
            out.append(pts)
    return out


# Что считается окном (решение пользователя 16.11.2026: «светиться должны окна, а не сами корабли» — в маску попадала и
# медная кромка арок флагмана, и кайма знамён башни): компактное пятно — не длиннее MAX_SIDE px спрайта, не тоньше
# MIN_SIDE и плотно заполняет свою рамку; длинные тонкие линии — не окна
WINDOW = {"ship": (1, 8, 0.4), "capital": (1, 10, 0.4), "castle": (5, 50, 0.35)}   # (мин., макс. сторона рамки, заполнение)


def is_window(pts: list, kind: str) -> bool:
    lo, hi, fill = WINDOW[kind]
    ys = [p[0] for p in pts]
    xs = [p[1] for p in pts]
    h, w = max(ys) - min(ys) + 1, max(xs) - min(xs) + 1
    return min(w, h) >= lo and max(w, h) <= hi and len(pts) / float(w * h) >= fill


def glass_mask(im: Image.Image, seeds: list) -> np.ndarray:
    """Окно башни целиком (решение пользователя 16.11.2026: «сделай окна башни полностью светящимися» — раньше горели
    только самые яркие пиксели): всё оранжевое стекло связных с ярким ядром пятен; каймы знамён и блики на камне,
    у которых ядра нет, не берутся."""
    hsv = np.asarray(im.convert("RGB").convert("HSV")).astype(float) / 255.0
    a = np.asarray(im)[..., 3]
    orange = (a > 200) & (hsv[..., 1] > 0.35) & (hsv[..., 2] > 0.2) & (hsv[..., 0] > 0.03) & (hsv[..., 0] < 0.13)
    seed = np.zeros_like(orange)
    for pts in seeds:
        for y, x in pts:
            seed[y, x] = True
    out = np.zeros_like(orange)
    for pts in blobs(orange):
        if any(seed[y, x] for y, x in pts):
            for y, x in pts:
                out[y, x] = True
    return out


def layer(im: Image.Image, mask: np.ndarray, kind: str, strength: float = 1.0) -> Image.Image:
    a = np.asarray(im).astype(np.float32)
    halo = np.asarray(Image.fromarray((mask * 255).astype("uint8")).filter(ImageFilter.GaussianBlur(HALO[kind]))).astype(np.float32) / 255.0
    out = np.zeros(a.shape, np.float32)
    out[..., :3] = np.where(mask[..., None], a[..., :3], np.array(WARM, np.float32))
    out[..., 3] = np.clip(np.where(mask, 255.0, halo * 255.0 * HALO_ALPHA[kind]) * strength, 0, 255)
    return Image.fromarray(out.round().astype(np.uint8))


def build(sprite: str, out_base: str | None, out_half: str, kind: str, all_windows: bool = False) -> None:
    im = Image.open(ANIM / (sprite + ".png")).convert("RGBA")
    mask = lit_mask(im)
    all_blobs = blobs(mask)
    bl = [b for b in all_blobs if is_window(b, kind)]
    mask = np.zeros_like(mask)
    for pts in bl:
        for y, x in pts:
            mask[y, x] = True
    bl = sorted(bl, key=lambda pts: (sum(p[1] for p in pts) / len(pts), sum(p[0] for p in pts) / len(pts)))
    if kind == "castle":
        mask = glass_mask(im, bl)
    half = np.zeros_like(mask)
    if all_windows:
        half = mask.copy()   # башня — все окна целиком
    else:
        for i, pts in enumerate(bl):
            if i % 2 == 0:
                for y, x in pts:
                    half[y, x] = True
    if out_base:
        layer(im, mask, kind, 0.8).save(ANIM / (out_base + ".png"))
    layer(im, half, kind, CASTLE_GAIN if kind == "castle" else 1.0).save(ANIM / (out_half + ".png"))
    print(f"{sprite}: пятен {len(all_blobs)}, окон {len(bl)}, в слое наведения {len(bl) if all_windows else (len(bl) + 1) // 2}")


def main() -> None:
    for i in (1, 2, 3):
        build(f"ship_{i}", f"ship_{i}_glow", f"ship_{i}_glow_half", "ship")
        for k in range(4):
            (ANIM / f"ship_{i}_glow_{k:02d}.png").unlink(missing_ok=True)
            (ANIM / f"ship_{i}_glow_{k:02d}.png.import").unlink(missing_ok=True)
    build("menu_capital_ship", None, "menu_capital_ship_glow_half", "capital")
    build("menu_castle_battlement", None, "menu_castle_battlement_glow", "castle", all_windows=True)   # башня — все окна


if __name__ == "__main__":
    main()
