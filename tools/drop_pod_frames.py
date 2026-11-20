"""Десантная капсула (ТЗ ART_TZ_DROP_POD_2026-11-12.txt, пакет художника assets/source_sheets/drop_pod_2026-11-12)
→ кадры игры assets/effects/drop_pod/{fall,land,fade}/N.png на одном холсте 640×768 с точкой клетки (320, 600)
+ frames.tres (fall — цикл 16 к/с, land — 16 к/с, fade — 12 к/с).

Пакет первой версии не стыкуется (README художника: «проверить привязку в движке»):
  - fall — холст 320×768, корпус крупнее закрытой капсулы land/0 и другой привязки → масштаб по ширине корпуса,
    низ корпуса и середина — на корпус land/0 (шов при смене листа в момент удара не заметен);
  - fade/0 сдвинут против land/15 → весь fade сдвигается на лучшее совпадение альфы с land/15 (перебор ±SEARCH px).

Стилизация под игру (решение пользователя 12.11.2026: «выбивается из общего стиля, сделай более пиксельной»):
  - цветокор как у зданий Космодесанта (sm_grade через boss_frames.grade_group, все кадры одной группой:
    target 0.26, pull 0.6, синий ордена и золото — как есть);
  - пиксель-арт: кадр уменьшается в PIXEL раз (среднее), цвета — общая палитра PALETTE_SIZE на все кадры без
    дизеринга, прозрачность — ступенями ALPHA_STEP (дым — пиксельными клочьями, корпус — сплошной), кромка
    силуэта темнее (EDGE_DARK — контур тёмным тоном материала, как у бойцов), обратно ×PIXEL без сглаживания.

    PYTHONPATH=tools python tools/drop_pod_frames.py [пакет] [папка игры]

Пакет v2 (assets/source_sheets/drop_pod_v2_2026-11-12, по разделу 6 ТЗ) — уже пиксель-арт в ракурсе зданий:
--native — без цветокора и огрубления; в листе fall капсула сама опускается по холсту (а падение ведёт код —
DropPod), поэтому каждый кадр fall ставится днищем корпуса (нижняя строка шире BODY_ROW_MIN — без огня дюз) и
серединой на корпус land/0.

    PYTHONPATH=tools python tools/drop_pod_frames.py assets/source_sheets/drop_pod_v2_2026-11-12 assets/effects/drop_pod --native
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ARGS = [a for a in sys.argv[1:] if not a.startswith("--")]
NATIVE = "--native" in sys.argv
SRC = Path(ARGS[0] if len(ARGS) > 0 else "assets/source_sheets/drop_pod_v2_2026-11-12")
DST = Path(ARGS[1] if len(ARGS) > 1 else "assets/effects/drop_pod")
BODY_ROW_MIN = 100        # --native: строка корпуса — непрозрачных пикселей больше (огонь дюз уже)
CANVAS = (640, 768)
ANCHOR = (320, 600)
SEARCH = 40
BODY_ALPHA = 200
# Раскрытая капсула стоит на поле недолго (решение пользователя 12.11.2026: «инородно» — меньше времени на виду):
# land 20 к/с, кадры стоянки 11–14 пакета (повтор 15-го) убраны — LAND_DROP, fade 16 к/с; всего на земле ≈ 1.2 с
ANIMS = [("fall", 16.0, True), ("land", 20.0, False), ("fade", 16.0, False)]
LAND_DROP = [11, 12, 13, 14]
PIXEL = 4                 # пиксель арта = 4×4 пикселя холста (на поле ≈ 0.9 px мира — как кластеры бойцов и зданий)
PALETTE_SIZE = 40
ALPHA_STEP = 64           # прозрачность ступенями; ниже ALPHA_MIN — пусто
ALPHA_MIN = 40
SOLID_ALPHA = 192         # плотнее — корпус (кромка темнеет)
EDGE_DARK = 0.5
GRADE = {"target": 0.26, "pull": 1.0, "hue": 0.59, "blue_sat": 1.0, "metal_sat": 0.22, "white_hot": 0.8,
         "neutral_pull": 0.7}


def pixelize(images: list) -> list:
    small = [im.reduce(PIXEL) for im in images]
    # общая палитра — по непрозрачным пикселям всех кадров
    rgb = np.concatenate([np.array(im)[:, :, :3][np.array(im)[:, :, 3] > ALPHA_MIN] for im in small])
    strip = Image.fromarray(rgb.reshape(1, -1, 3).astype(np.uint8))
    pal = strip.quantize(PALETTE_SIZE, method=Image.Quantize.MEDIANCUT)
    out = []
    for im in small:
        a = np.array(im).astype(np.float32)
        alpha = a[:, :, 3]
        q = np.array(Image.fromarray(a[:, :, :3].astype(np.uint8)).quantize(palette=pal, dither=Image.Dither.NONE)
                     .convert("RGB")).astype(np.float32)
        alpha = np.where(alpha < ALPHA_MIN, 0, np.minimum(255, np.round(alpha / ALPHA_STEP) * ALPHA_STEP))
        solid = alpha >= SOLID_ALPHA
        alpha = np.where(solid, 255, alpha)
        # кромка корпуса: сплошной пиксель рядом с пустым / полупрозрачным — тёмным тоном своего цвета
        pad = np.pad(solid, 1)
        inner = pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:]
        edge = solid & ~inner
        q[edge] *= EDGE_DARK
        res = np.dstack([q, alpha]).clip(0, 255).astype(np.uint8)
        out.append(Image.fromarray(res).resize(images[0].size, Image.NEAREST))
    return out


def frames(anim: str) -> list:
    files = sorted((SRC / anim).glob("*.png"), key=lambda p: int(p.stem))
    return [Image.open(p).convert("RGBA") for p in files]


def body_box(im: Image.Image, rows: tuple) -> tuple:
    """Корпус: непрозрачные пиксели в полосе строк rows (без дыма сверху и огня снизу) — (x0, x1, низ)."""
    a = np.array(im)[:, :, 3] > BODY_ALPHA
    band = a[rows[0]:rows[1]]
    xs = np.nonzero(band.any(0))[0]
    ys = np.nonzero(a.sum(1) > 20)[0]
    return xs.min(), xs.max(), ys.max()


def best_shift(a: Image.Image, b: Image.Image) -> tuple:
    """Сдвиг b, при котором его альфа лучше всего ложится на альфу a."""
    aa = np.array(a)[:, :, 3] > 128
    bb = np.array(b)[:, :, 3] > 128
    best, score = (0, 0), -1
    for dy in range(-SEARCH, SEARCH + 1, 2):
        for dx in range(-SEARCH, SEARCH + 1, 2):
            s = (aa & np.roll(np.roll(bb, dy, 0), dx, 1)).sum()
            if s > score:
                best, score = (dx, dy), s
    return best


def place(im: Image.Image, scale: float, dx: float, dy: float) -> Image.Image:
    if scale != 1.0:
        im = im.resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS)
    out = Image.new("RGBA", CANVAS)
    out.paste(im, (round(dx), round(dy)), im)
    return out


def body_anchor(im: Image.Image) -> tuple:
    """Днище корпуса (нижняя строка шире BODY_ROW_MIN) и середина корпуса по этой полосе."""
    a = np.array(im)[:, :, 3] > BODY_ALPHA
    rows = np.nonzero(a.sum(1) > BODY_ROW_MIN)[0]
    bottom = rows.max()
    xs = np.nonzero(a[max(0, bottom - 40):bottom + 1].any(0))[0]
    return (xs.min() + xs.max()) / 2.0, bottom


def main() -> None:
    land = frames("land")
    fall = frames("fall")
    fade = frames("fade")
    if NATIVE:
        lcx, lb = body_anchor(land[0])
        placed = []
        for f in fall:
            fcx, fb = body_anchor(f)
            placed.append(place(f, 1.0, lcx - fcx, lb - fb))
        print(f"fall: по днищу корпуса land/0 ({lcx:.0f}, {lb})")
        sx, sy = best_shift(land[-1], fade[0])
        print(f"fade: сдвиг ({sx}, {sy})")
        out = {
            "fall": placed,
            "land": [f for i, f in enumerate(land) if i not in LAND_DROP],
            "fade": [place(f, 1.0, sx, sy) for f in fade],
        }
        write(out)
        return
    # fall → корпус land/0: ширина корпуса в полосе над днищем, низ корпуса
    lx0, lx1, lb = body_box(land[0], (450, 560))
    fx0, fx1, fb = body_box(fall[0], (330, 500))
    k = (lx1 - lx0) / (fx1 - fx0)
    dx = (lx0 + lx1) / 2 - (fx0 + fx1) / 2 * k
    dy = lb - fb * k
    print(f"fall: масштаб {k:.3f}, сдвиг ({dx:.0f}, {dy:.0f})")
    # fade → land/15
    sx, sy = best_shift(land[-1], fade[0])
    print(f"fade: сдвиг ({sx}, {sy})")
    out = {
        "fall": [place(f, k, dx, dy) for f in fall],
        "land": [f for i, f in enumerate(land) if i not in LAND_DROP],
        "fade": [place(f, 1.0, sx, sy) for f in fade],
    }
    import boss_frames   # цветокор группы кадров (sm_grade)
    order = [a for a, _, _ in ANIMS]
    flat = boss_frames.grade_group([im for a in order for im in out[a]], GRADE)
    flat = pixelize(flat)
    i = 0
    for a in order:
        out[a] = flat[i:i + len(out[a])]
        i += len(out[a])
    write(out)


def write(out: dict) -> None:
    lines = []
    ext = []
    for anim, fps, loop in ANIMS:
        (DST / anim).mkdir(parents=True, exist_ok=True)
        ids = []
        for i, im in enumerate(out[anim]):
            im.save(DST / anim / f"{i}.png")
            rid = f"{anim}_{i}"
            ext.append(f'[ext_resource type="Texture2D" path="res://{DST.as_posix()}/{anim}/{i}.png" id="{rid}"]')
            ids.append('{\n"duration": 1.0,\n"texture": ExtResource("%s")\n}' % rid)
        lines.append('{\n"frames": [%s],\n"loop": %s,\n"name": &"%s",\n"speed": %s\n}'
                     % (", ".join(ids), "true" if loop else "false", anim, fps))
    tres = (f'[gd_resource type="SpriteFrames" load_steps={len(ext) + 1} format=3]\n\n' + "\n".join(ext)
            + f"\n\n[resource]\nmetadata/anchor = Vector2{ANCHOR}\nanimations = [" + ", ".join(lines) + "]\n")
    (DST / "frames.tres").write_text(tres, encoding="utf-8", newline="\n")
    print("кадров:", {a: len(v) for a, v in out.items()})


if __name__ == "__main__":
    main()
