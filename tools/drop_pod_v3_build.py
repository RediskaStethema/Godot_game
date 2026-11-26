"""Десантная капсула v3 (Layer AI, 23.11.2026, решение пользователя: «перерисовать капсулы под новую вселенную»):
клёпаный железный снаряд-капсула (Ж. Верн «С Земли на Луну» + купол-«петарда» из «Гамлета», лампа с двумя огнями вместо
аквилы, четыре створки вместо пяти дверей — уход от силуэта канона).

Лист поз 4×4 (по строкам, 16 кадров) `assets/source_sheets/drop_pod_layer_2026-11-23/land_<вариант>.png` → кадры на холсте
игры 640×768 с точкой клетки (320, 600):
  - ячейка листа — по числу колонок / рядов (модель вернула лист на 16 px больше заготовки 448×576: ячейки 452×580);
  - зелёный ключ фона просочился в пар: пиксели с перевесом зелёного приводятся к нейтральному (g = max(r, b));
  - альфа корпуса 250+ → 255; пар остаётся полупрозрачным;
  - масштаб K: закрытая капсула ≈ 250 px холста (раздел 6.5 ТЗ); основание капсулы — точка (320, 600), центр по x — 320.

    python tools/drop_pod_v3_build.py [land|fall|fade] [A|B] [папка для кадров]
    python tools/drop_pod_v3_build.py --all A       # все три листа + цветокор + пиксель-проход → черновой пакет (игру не трогает)

fall — лист 3×2 (шесть кадров цикла, клетки 640×1096; модель вернула лист в 1920×2192): корпус в клетке — основание y 758,
центр x 321, высота 360 px; дым у верхней кромки клетки обрезан листом — альфа затухает на верхних FEATHER_TOP px.

fade — лист 5×2 (десять кадров, клетки 573×736; лист вернулся в 2864×1472 при заготовке 2260×1160, ×1.267); фон листа НЕ
прозрачный — зелёный ключ снимается мягко (альфа по перевесу зелёного, остаток нейтрализуется); исходная клетка — кадр 15 land.

Дальше (после fall и fade): цветокор и пиксель-проход — `drop_pod_frames.py` (`GRADE`, `pixelize`), затем `--import`.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

VARIANT = next((a for a in sys.argv[1:] if a in ("A", "B")), "A")
MODE = next((a for a in sys.argv[1:] if a in ("land", "fall", "fade")), "land")
ARGS = [a for a in sys.argv[1:] if not a.startswith("--") and a not in ("A", "B", "land", "fall", "fade")]
SRC = Path("assets/source_sheets/drop_pod_layer_2026-11-23")
DST = Path(ARGS[0] if ARGS else f"assets/source_sheets/drop_pod_v3_2026-11-23/{MODE}")
# land: лист 4×4, ячейка 452×580; fall: лист 3×2, ячейка 640×1096
COLS, ROWS = {"land": (4, 4), "fall": (3, 2), "fade": (5, 2)}[MODE]
FEATHER_TOP = 0 if MODE == "land" else 140
CANVAS = (640, 768)
ANCHOR = (320, 600)
BASE_IN_CELL = {"land": (226.0, 473.0), "fall": (321.0, 758.0), "fade": (286.0, 599.0)}[MODE]   # центр основания капсулы в ячейке
CLOSED_HEIGHT = 250.0           # высота закрытой капсулы в кадре игры (ТЗ 6.5)
# высота ВСЕЙ капсулы (купол и лампа) в клетке: land — заготовка 360 px × 1.009; fall — лист вернулся ×1.43 (1920×2192 вместо
# 1344×1536): 360 × 1.43 = 518 (цилиндр корпуса 360 — без купола; ошибка первой версии скрипта давала fall в 1.4 раза крупнее land)
CAPSULE_HEIGHT_IN_SHEET = {"land": 363.0, "fall": 518.0, "fade": 460.0}[MODE]   # fade: 363 × 1.267
GREEN_OVER = 8
KEY_START, KEY_FULL = 25, 140   # fade: перевес зелёного, с которого пиксель начинает таять / становится фоном


def key_green(a: np.ndarray) -> np.ndarray:
    """Плоский зелёный фон листа (fade): альфа падает с перевесом зелёного (d = g − max(r, b)); d ≥ KEY_FULL — фон."""
    d = a[..., 1].astype(int) - np.maximum(a[..., 0], a[..., 2]).astype(int)
    alpha = np.clip(1.0 - (d - KEY_START) / float(KEY_FULL - KEY_START), 0.0, 1.0)
    a = a.copy()
    a[..., 3] = (a[..., 3] * alpha).astype(np.uint8)
    return a


def defringe(a: np.ndarray) -> np.ndarray:
    """Зелёный перевес → нейтральный (g = max(r, b)): ключ фона просочился в пар."""
    r, g, b = a[..., 0].astype(int), a[..., 1].astype(int), a[..., 2].astype(int)
    over = (g - np.maximum(r, b)) > GREEN_OVER
    a = a.copy()
    a[..., 1] = np.where(over, np.maximum(r, b), a[..., 1])
    return a


def cut(sheet: Image.Image) -> list:
    cw, ch = sheet.width / COLS, sheet.height / ROWS
    k = CLOSED_HEIGHT / CAPSULE_HEIGHT_IN_SHEET
    out = []
    for i in range(COLS * ROWS):
        c, r = i % COLS, i // COLS
        cell = sheet.crop((round(c * cw), round(r * ch), round((c + 1) * cw), round((r + 1) * ch)))
        a = np.asarray(cell.convert("RGBA")).copy()
        if MODE == "fade":
            a = key_green(a)
        a = defringe(a)
        a[..., 3] = np.where(a[..., 3] >= 250, 255, a[..., 3])
        if FEATHER_TOP:   # дым упёрся в верх ячейки — гаснет полосой
            ramp = np.clip(np.arange(a.shape[0]) / FEATHER_TOP, 0.0, 1.0)[:, None]
            a[..., 3] = (a[..., 3] * ramp).astype(np.uint8)
        a[..., :3] = np.where(a[..., 3:4] == 0, 0, a[..., :3])
        im = Image.fromarray(a, "RGBA")
        im = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
        frame = Image.new("RGBA", CANVAS)
        frame.alpha_composite(im, (round(ANCHOR[0] - BASE_IN_CELL[0] * k), round(ANCHOR[1] - BASE_IN_CELL[1] * k)))
        out.append(frame)
    return out


def main() -> None:
    sheet = Image.open(SRC / f"{MODE}_{VARIANT}.png")
    frames = cut(sheet)
    DST.mkdir(parents=True, exist_ok=True)
    for i, f in enumerate(frames):
        f.save(DST / f"{i}.png")
    print(f"{MODE} {VARIANT}: {len(frames)} кадров → {DST}")


if __name__ == "__main__":
    main()
