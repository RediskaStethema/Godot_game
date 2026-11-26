"""Стойка боссов без «кипения» (решение пользователя 24.11.2026, скилл game-stylization: «анимации боссов» → «только стойка idle»).

Листы Layer перерисовывают фигуру целиком в каждом кадре стойки: между соседними кадрами меняется 15–39% пикселей при ровном
корпусе — стойка шевелится, а не дышит (как было у бойцов и продавца). Тело всех кадров берётся из эталонного кадра (кадр 0),
из своего кадра — только крупное движение (огонь, плащ, дым, перья, лампа): разница с эталоном > `DIFF`, размытая на `BLUR`
выше `THRESH` и расширенная на `GROW`, край мягкий (`SOFT`). Сверху — дыхание: корпус выше пояса (`BELT` доли роста от стоп)
поднимается на `BREATH` доли роста и опускается за цикл, строка пояса повторяется на разрыв.
  python tools/boss_idle_lock.py [--out папка] [--dry] [id босса …]
Исходные кадры стойки — `assets/source_sheets/boss_idle_orig_2026-11-24/<id>/` (повторный прогон — от них; первый прогон копирует).
Откат: скопировать их обратно в `assets/units/bosses/<id>/idle` и `godot --headless --path . --import`.
"""
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
BOSSES = ROOT / "assets/units/bosses"
ORIG = ROOT / "assets/source_sheets/boss_idle_orig_2026-11-24"
DIFF = 70        # разница канала (0–255), с которой пиксель «двигался»
BLUR = 3         # размытие маски движения, px
THRESH = 0.35    # порог размытой маски
GROW = 3         # расширение области движения, px
SOFT = 2         # мягкий край области, px
BELT = 0.46      # пояс — доля роста от стоп; выше — дышит
BREATH = 0.012   # подъём корпуса: доля роста
# Все девять боссов — только кадр 0 и дыхание, без наложения своих кадров (решение пользователя 24.11.2026: «убери кипение боссов»).
# Сначала так сделаны Дорн и Жиллиман (живого нет); у остальных семи режим «своё только в местах крупного движения» не годился: кадры
# листа различаются на 4 px и по форме, область «движения» занимала 40% холста и давала призраков по краю
STATIC = {"primarch_dorn", "primarch_guilliman", "daemon_angron", "daemon_fulgrim", "daemon_magnus", "daemon_mortarion",
	"primarch_russ", "primarch_sanguinius", "primarch_vulkan"}


def files_of(d):
    return sorted(d.glob("*.png"), key=lambda p: int(p.stem))


def bbox_rows(a):
    ys = np.where((a[..., 3] > 40).any(1))[0]
    return int(ys.min()), int(ys.max())


def motion_mask(ref, cur):
    d = np.abs(ref[..., :3].astype(int) - cur[..., :3].astype(int)).max(2)
    d = np.maximum(d, np.abs(ref[..., 3].astype(int) - cur[..., 3].astype(int)))
    m = Image.fromarray(((d > DIFF) * 255).astype(np.uint8))
    m = m.filter(ImageFilter.GaussianBlur(BLUR))
    m = m.point(lambda v: 255 if v / 255.0 > THRESH else 0)
    m = m.filter(ImageFilter.MaxFilter(GROW * 2 + 1))
    m = m.filter(ImageFilter.GaussianBlur(SOFT))
    return np.array(m).astype(float) / 255.0


def breathe(ref, k, n):
    """Корпус выше пояса — на dy px вверх (синус по циклу), пояс растягивается на разрыв."""
    top, bot = bbox_rows(ref)
    h = bot - top
    belt = int(bot - BELT * h)
    dy = int(round(BREATH * h * (1 - np.cos(2 * np.pi * k / n)) / 2 * 2))   # 0..BREATH·h·... (целые px)
    if dy <= 0:
        return ref
    out = np.zeros_like(ref)
    out[:belt] = 0
    out[belt - dy:belt] = ref[belt - dy:belt]       # заполнитель; верх сдвинут ниже
    out[:belt - dy] = ref[dy:belt]                  # корпус выше пояса — вверх на dy
    out[belt - dy:belt] = ref[belt]                 # строка пояса повторяется на разрыв
    out[belt:] = ref[belt:]
    return out


def lock(frames, static=False):
    n = len(frames)
    ref = frames[0]
    out = []
    for k, cur in enumerate(frames):
        base = breathe(ref, k, n).astype(float)
        if static:
            out.append(base.astype(np.uint8))
            continue
        m = motion_mask(ref, cur)[..., None]
        cur_f = cur.astype(float)
        mix = base * (1 - m) + cur_f * m
        mix[..., 3] = np.maximum(mix[..., 3], 0)
        out.append(np.clip(mix, 0, 255).astype(np.uint8))
    return out


def kipenie(frames):
    d = []
    for x, y in zip(frames, frames[1:] + frames[:1]):
        mx = (x[..., 3] > 100) | (y[..., 3] > 100)
        d.append((np.abs(x[..., :3].astype(int) - y[..., :3].astype(int)).max(2) > 40)[mx].mean())
    return float(np.mean(d))


def main(argv):
    out_root = None
    dry = "--dry" in argv
    argv = [a for a in argv if a != "--dry"]
    if "--out" in argv:
        i = argv.index("--out")
        out_root = Path(argv[i + 1])
        argv = argv[:i] + argv[i + 2:]
    for boss in argv or sorted(p.name for p in BOSSES.iterdir() if p.is_dir()):
        src = ORIG / boss
        if not src.exists():
            src.mkdir(parents=True)
            for f in files_of(BOSSES / boss / "idle"):
                shutil.copy2(f, src / f.name)
        frames = [np.array(Image.open(f).convert("RGBA")) for f in files_of(src)]
        done = lock(frames, boss in STATIC)
        print(f"{boss}: кипение {kipenie(frames):.2f} -> {kipenie(done):.2f} ({len(frames)} кадров)")
        if dry:
            continue
        dst = (out_root / boss) if out_root else (BOSSES / boss / "idle")
        dst.mkdir(parents=True, exist_ok=True)
        for i, a in enumerate(done):
            Image.fromarray(a).save(dst / f"{i}.png")


if __name__ == "__main__":
    main(sys.argv[1:])
