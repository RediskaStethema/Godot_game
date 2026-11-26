"""Капсула v3: цветокор и пиксель-проход по кадрам fall / land / fade (после drop_pod_v3_build.py), 23.11.2026.

Берёт `assets/source_sheets/drop_pod_v3_2026-11-23/{fall,land,fade}/N.png` (холст 640×768, точка клетки (320, 600)), как
`drop_pod_frames.py`: кадры стоянки land 11–14 убираются (`LAND_DROP`), все кадры одной группой — цветокор (`GRADE`, как у
зданий Космодесанта), пиксель-проход (`pixelize`, пиксель = PIXEL × PIXEL px холста). Пишет в `<папка>/p<PIXEL>/{fall,land,fade}`
+ ленту `strip_p<PIXEL>.png` для просмотра. В игру не ставит (`--install` — копирует в `assets/effects/drop_pod` + `frames.tres`,
прежние кадры сохраняются в `assets/source_sheets/_backup_before_drop_pod_v3_2026-11-23`).

    PYTHONIOENCODING=utf-8 PYTHONPATH=tools python tools/drop_pod_v3_finish.py [PIXEL=4] [--nograde] [--bright=1.6] [--blue=1.5] [--install]
"""
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image

argv = sys.argv[1:]
PIXEL_ARG = next((int(a) for a in argv if a.isdigit()), 4)
INSTALL = "--install" in argv
BRIGHT = next((float(a.split("=")[1]) for a in argv if a.startswith("--bright=")), 1.0)   # подъём тёмных тонов (колено: света почти не трогает)
BLUE = next((float(a.split("=")[1]) for a in argv if a.startswith("--blue=")), 1.0)       # насыщенность и яркость синего створок
NO_GRADE = "--nograde" in argv   # цветокор зданий (GRADE) убивал синий створок и обесцвечивал уже тёмный рендер v3
sys.argv = [sys.argv[0]]   # drop_pod_frames разбирает argv при импорте

import boss_frames   # noqa: E402
import drop_pod_frames as dpf   # noqa: E402

SRC = Path("assets/source_sheets/drop_pod_v3_2026-11-23")
dpf.PIXEL = PIXEL_ARG


def lift(im: Image.Image) -> Image.Image:
    """В игре шейдер зданий (палитра бордо, оттенок, AO) гасит нейтральную сталь и тусклую латунь до цвета грунта, а у капсулы v3
    синий только на створках (3–8% пикселей; у прежней капсулы корпус был синий — 50%+): тёмные тона поднимаются
    v' = v·(1 + (BRIGHT − 1)·(1 − v)), синий (тон 0.55–0.70, s > 0.25) — насыщеннее (BLUE) и светлее."""
    a = np.asarray(im.convert("RGBA")).copy()
    hsv = np.asarray(Image.fromarray(a[..., :3]).convert("HSV")).astype(np.float32)
    h, sat, v = hsv[..., 0] / 255.0, hsv[..., 1] / 255.0, hsv[..., 2] / 255.0
    v2 = v * (1.0 + (BRIGHT - 1.0) * (1.0 - v))
    blue = (h > 0.55) & (h < 0.70) & (sat > 0.25)
    sat = np.where(blue, np.minimum(1.0, sat * BLUE), sat)
    v2 = np.where(blue, np.minimum(1.0, v2 * (1.0 + (BLUE - 1.0) * 0.5)), v2)
    hsv2 = np.dstack([h * 255.0, sat * 255.0, np.minimum(1.0, v2) * 255.0]).clip(0, 255).astype(np.uint8)
    rgb = np.asarray(Image.fromarray(hsv2, "HSV").convert("RGB"))
    a[..., :3] = rgb
    return Image.fromarray(a, "RGBA")


def load(anim: str) -> list:
    files = sorted((SRC / anim).glob("*.png"), key=lambda p: int(p.stem))
    return [Image.open(p).convert("RGBA") for p in files]


def main() -> None:
    out = {"fall": load("fall"), "land": [f for i, f in enumerate(load("land")) if i not in dpf.LAND_DROP], "fade": load("fade")}
    order = [a for a, _, _ in dpf.ANIMS]
    flat = [im for a in order for im in out[a]]
    if not NO_GRADE:
        flat = boss_frames.grade_group(flat, dpf.GRADE)
    if BRIGHT != 1.0 or BLUE != 1.0:
        flat = [lift(im) for im in flat]
    flat = dpf.pixelize(flat)
    i = 0
    for a in order:
        out[a] = flat[i:i + len(out[a])]
        i += len(out[a])
    dst = SRC / f"p{PIXEL_ARG}{'n' if NO_GRADE else ''}{'L' if (BRIGHT != 1.0 or BLUE != 1.0) else ''}"
    for a in order:
        (dst / a).mkdir(parents=True, exist_ok=True)
        for k, im in enumerate(out[a]):
            im.save(dst / a / f"{k}.png")
    print("кадров:", {a: len(v) for a, v in out.items()}, "→", dst)
    # лента для просмотра
    box = (60, 120, 580, 700)
    w, h = box[2] - box[0], box[3] - box[1]
    seq = out["fall"] + out["land"] + out["fade"]
    cols = 11
    rows = (len(seq) + cols - 1) // cols
    sheet = Image.new("RGBA", (w * cols, h * rows), (40, 28, 34, 255))
    for k, im in enumerate(seq):
        sheet.alpha_composite(im.crop(box), ((k % cols) * w, (k // cols) * h))
    sheet.convert("RGB").save(SRC / f"strip_{dst.name}.png")
    if INSTALL:
        game = Path("assets/effects/drop_pod")
        backup = Path("assets/source_sheets/_backup_before_drop_pod_v3_2026-11-23")
        if not backup.exists():
            shutil.copytree(game, backup)
            print("копия прежних кадров →", backup)
        for a in order:
            shutil.rmtree(game / a, ignore_errors=True)
        dpf.DST = game
        dpf.write(out)


if __name__ == "__main__":
    main()
