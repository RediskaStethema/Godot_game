"""Единый стиль интерфейса под новое главное меню (решение пользователя 16.11.2026, этап «единый стиль» плана визуала): окна, шапки,
плашки, подсказки, кнопки и полосы прокрутки — из холодной тёмно-синей стали в тёплый тёмный камень с медной кромкой, как каменные
кнопки меню (`tools/menu_v2_assets.py`, эталон `exec-cd0d7c5f….png`).

  python tools/ui_restyle.py [--restore]      затем  godot --headless --import

Холодные пиксели (тон 0.48–0.75, насыщенность > 0.06) перекрашиваются: тёмные заливки — в тёплый бордо-камень, светлые кромки — в
медь; тёплые (латунь, янтарь, золото) и нейтральные не трогаются. Исходники сохраняются один раз в
assets/source_sheets/_backup_before_redesign_2026-11-15/ui/ui_restyle (повторный прогон идёт от них; --restore возвращает).
Цвета кодом (Palette.gd / UITheme.gd) правятся отдельно — см. журнал.
"""
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
UI = ROOT / "assets/ui"
BACKUP = ROOT / "assets/source_sheets/_backup_before_redesign_2026-11-15/ui/ui_restyle"
FILES = (["frame", "panel", "hud_bar", "plate_small", "tooltip", "scroll_track", "scroll_grabber", "scroll_grabber_hover",
          "button_normal", "button_hover", "button_pressed", "button_disabled",
          "button_small_normal", "button_small_hover", "button_small_pressed", "button_small_disabled",
          "panels/hud", "panels/panel", "panels/card_select", "info/info_frame", "info/portrait_frame"])
COLD = (0.48, 0.75)
SAT_MIN = 0.06
FILL_V = 0.24          # темнее — заливка (бордо-камень), светлее — кромка (медь)
FILL = {"hue": 0.985, "sat_k": 0.8, "sat_add": 0.06, "val_k": 1.04}
RIM = {"hue": 0.07, "sat_k": 0.7, "sat_add": 0.1, "val_k": 1.0}


def restyle(im: Image.Image) -> Image.Image:
    a = np.asarray(im.convert("RGBA")).copy()
    hsv = np.asarray(im.convert("RGB").convert("HSV")).astype(np.float32) / 255.0
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    cold = (h > COLD[0]) & (h < COLD[1]) & (s > SAT_MIN)
    w = np.clip((s - SAT_MIN) / 0.2, 0, 1) * cold
    fill = v < FILL_V
    out_h, out_s, out_v = h.copy(), s.copy(), v.copy()
    for mask, p in ((fill, FILL), (~fill, RIM)):
        m = cold & mask
        out_h = np.where(m, h * (1 - w) + p["hue"] * w, out_h)
        out_s = np.where(m, np.clip(s * p["sat_k"] + p["sat_add"] * w, 0, 1), out_s)
        out_v = np.where(m, np.clip(v * p["val_k"], 0, 1), out_v)
    rgb = np.asarray(Image.fromarray((np.stack([out_h, out_s, out_v], -1) * 255 + 0.5).astype(np.uint8), "HSV").convert("RGB"))
    a[..., :3] = rgb
    return Image.fromarray(a)


def main(argv: list) -> None:
    for name in FILES:
        src = UI / (name + ".png")
        bak = BACKUP / (name + ".png")
        if not src.exists():
            print("нет файла:", name)
            continue
        if not bak.exists():
            bak.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(src, bak)
        if "--restore" in argv:
            shutil.copyfile(bak, src)
            continue
        restyle(Image.open(bak)).save(src)
    print("готово" if "--restore" not in argv else "возвращено", "— затем: godot --headless --import")


if __name__ == "__main__":
    main(sys.argv[1:])
