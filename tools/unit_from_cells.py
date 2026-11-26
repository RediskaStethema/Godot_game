"""Модель юнита из готовых ячеек листа (папки кадров художника, сетка cols×N) → кадры на общем холсте + frames.tres.

Решение пользователя 12.11.2026 («подключи и стилизуй, структуризируй sanguinary_guard»): пакет художника — папки
sheet_01…sheet_07 по 13 / 10 / 8 кадров (полная ячейка листа 4×4 без обрезки, холсты листов разные), без названий
анимаций и без листа смерти. Исходники — assets/source_sheets/<юнит>_<дата>/ (с .gdignore), игра их не грузит.

Что делает:
  * чистит дымку: альфа ≤ HAZE → 0 (по листу — десятки тысяч почти прозрачных пикселей, Godot рисовал бы ореол);
  * сшивает вылеты сетки: модель, вылезшая из ячейки вниз, лежит обрезком вверху ячейки на ряд ниже (i + cols) —
    обрезок возвращается под свой кадр;
  * ставит кадры на общий холст: низ — на землю (Soldier ставит низ холста на точку бойца), корпус — по x в центр
    (полоса корпуса, как tools/unit_stabilize.py). Ряды `ground` — каждый кадр сам; остальные — ряд целиком
    (прыжок / приземление / смерть: фигура законно смещается внутри ряда), x — по кадру `:first` / `:last`;
  * чужой ряд (`@k`) — масштаб k к новой фигуре, `%` — цвет под стойку (среднее и разброс каналов): временная
    смерть из старого листа, пока художник не дорисует;
  * холст: высота = рост стойки / FILL (как у остальных юнитов — по высоте холста стойки Soldier считает рост),
    что выше (замах, крылья) — в metadata/figure_height.

  python tools/unit_from_cells.py <папка ячеек> <папка юнита> idle=sheet_01 walk=sheet_02 attack=sheet_04 \
      jump=sheet_05 landing=sheet_06:last death=old_death@1.29% [--ground idle,walk,attack] [--hit 6] [--cols 4]
затем godot --headless --path . --import
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gif_to_frames import IMPORT_PARAMS, FILL  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
HAZE = 20            # альфа дымки вокруг модели
ALPHA = 128          # «тело» для замеров
TORSO = (0.35, 0.75)
FOLDERS = {"walk": "run"}                       # имена папок, как Soldier.ANIMATION_FOLDERS
FPS = {"idle": 8, "walk": 14, "attack": 16, "death": 10, "jump": 10, "landing": 10}
LOOPING = {"idle", "walk"}


def load_cells(folder):
    files = sorted(folder.glob("*.png"), key=lambda p: int(p.stem))
    out = []
    for f in files:
        a = np.array(Image.open(f).convert("RGBA"))
        a[a[..., 3] <= HAZE] = 0
        out.append(a)
    return out


def touching_top(a):
    """Пиксели, связанные с верхним краем (обрезок кадра из ячейки выше)."""
    m = a[..., 3] > HAZE
    grow = np.zeros_like(m)
    grow[0] = m[0]
    while True:
        nxt = grow.copy()
        nxt[1:] |= grow[:-1]
        nxt[:-1] |= grow[1:]
        nxt[:, 1:] |= grow[:, :-1]
        nxt[:, :-1] |= grow[:, 1:]
        nxt &= m
        if (nxt == grow).all():
            return grow
        grow = nxt


def stitch(cells, cols):
    for i in range(len(cells) - cols):
        a, b = cells[i], cells[i + cols]
        if not (a[-2:, :, 3] > HAZE).any() or not (b[:2, :, 3] > HAZE).any():
            continue
        frag = touching_top(b)
        rows = np.nonzero(frag.any(axis=1))[0].max() + 1
        piece = np.where(frag[..., None], b, 0)[:rows]
        cells[i] = np.concatenate([a, piece.astype(a.dtype)], axis=0)
        cells[i + cols] = np.where(frag[..., None], 0, b).astype(b.dtype)
        print(f"  сшит вылет: кадр {i} +{rows} px снизу (из кадра {i + cols})")
    return cells


def body(a):
    ys, xs = np.nonzero(a[..., 3] > ALPHA)
    return xs.min(), ys.min(), xs.max(), ys.max()


def torso_x(a, h):
    m = a[..., 3] > ALPHA
    bot = np.nonzero(m)[0].max()
    band = m[max(0, int(bot - h * TORSO[1])):int(bot - h * TORSO[0])]
    return float(np.nonzero(band)[1].mean()) if band.any() else float(np.nonzero(m)[1].mean())


def match_color(frames, ref):
    """Каналы чужого ряда — к среднему и разбросу стойки (по непрозрачным пикселям)."""
    r = np.concatenate([f[f[..., 3] > ALPHA][:, :3] for f in ref]).astype(np.float32)
    s = np.concatenate([f[f[..., 3] > ALPHA][:, :3] for f in frames]).astype(np.float32)
    k = r.std(0) / np.maximum(s.std(0), 1.0)
    out = []
    for f in frames:
        g = f.astype(np.float32)
        g[..., :3] = (g[..., :3] - s.mean(0)) * k + r.mean(0)
        out.append(np.clip(g, 0, 255).astype(np.uint8))
    return out


def main(args):
    src, unit = Path(args[0]), Path(args[1])
    opt = lambda name, d: next((args[args.index(a) + 1] for a in args if a == name), d)
    ground = opt("--ground", "idle,walk,attack").split(",")
    cols = int(opt("--cols", "4"))
    hit = opt("--hit", None)
    spec = [a for a in args[2:] if "=" in a]
    rows = {}
    for s in spec:
        anim, rest = s.split("=", 1)
        recolor = rest.endswith("%")
        rest = rest.rstrip("%")
        rest, scale = (rest.split("@") + ["1"])[:2]
        folder, anchor = (rest.split(":") + ["first"])[:2]
        cells = stitch(load_cells(src / folder), cols)
        if float(scale) != 1.0:
            cells = [np.array(Image.fromarray(c).resize((round(c.shape[1] * float(scale)), round(c.shape[0] * float(scale))),
                                                         Image.LANCZOS)) for c in cells]
        rows[anim] = dict(cells=cells, anchor=anchor, recolor=recolor)
    if any(r["recolor"] for r in rows.values()):
        for r in rows.values():
            if r["recolor"]:
                r["cells"] = match_color(r["cells"], rows["idle"]["cells"])
    idle0 = rows["idle"]["cells"][0]
    ref_h = body(idle0)[3] - body(idle0)[1]

    # якорь каждого кадра: (x корпуса, y земли) в его ячейке
    for anim, r in rows.items():
        cells = r["cells"]
        if anim in ground:
            r["anchors"] = [(torso_x(c, ref_h), body(c)[3] + 1) for c in cells]
        else:
            key = cells[-1] if r["anchor"] == "last" else cells[0]
            x = torso_x(key, ref_h)
            y = max(body(c)[3] for c in cells) + 1
            r["anchors"] = [(x, y)] * len(cells)

    half_w = top = 0
    for r in rows.values():
        for c, (ax, ay) in zip(r["cells"], r["anchors"]):
            x0, y0, x1, _ = body(c)
            half_w = max(half_w, ax - x0, x1 - ax)
            top = max(top, ay - y0)
    figure_h = round(ref_h / FILL)
    canvas_h = max(figure_h, round(top) + 2)
    canvas_w = 2 * round(half_w + 4)
    print(f"холст {canvas_w}×{canvas_h}, рост стойки {ref_h}, рост для масштаба {figure_h}")

    res = "res://" + unit.resolve().relative_to(ROOT).as_posix()
    ext, anims = [], []
    for anim, r in rows.items():
        out_dir = unit / FOLDERS.get(anim, anim)
        out_dir.mkdir(parents=True, exist_ok=True)
        for old in out_dir.glob("*.png*"):
            old.unlink()
        refs = []
        for i, (c, (ax, ay)) in enumerate(zip(r["cells"], r["anchors"])):
            canvas = Image.new("RGBA", (canvas_w, canvas_h))
            canvas.alpha_composite(Image.fromarray(c), (round(canvas_w / 2 - ax), round(canvas_h - ay)))
            canvas.save(out_dir / f"{i}.png")
            (out_dir / f"{i}.png.import").write_text(IMPORT_PARAMS, encoding="utf-8")
            ext.append(f'[ext_resource type="Texture2D" path="{res}/{out_dir.name}/{i}.png" id="{anim}_{i}"]')
            refs.append(f'{{\n"duration": 1.0,\n"texture": ExtResource("{anim}_{i}")\n}}')
        anims.append(f'{{\n"frames": [{", ".join(refs)}],\n"loop": {"true" if anim in LOOPING else "false"},\n'
                     f'"name": &"{anim}",\n"speed": {float(FPS.get(anim, 10))}\n}}')
        print(f"  {anim}: {len(refs)} кадров → {out_dir.name}/")
    meta = f"metadata/hit_frame = {hit}\n" if hit is not None else ""
    if canvas_h != figure_h:
        meta += f"metadata/figure_height = {float(figure_h)}\n"
    (unit / "frames.tres").write_text(
        f'[gd_resource type="SpriteFrames" load_steps={len(ext) + 1} format=3]\n\n' + "\n".join(ext)
        + f'\n\n[resource]\n{meta}animations = [{", ".join(anims)}]\n', encoding="utf-8")


if __name__ == "__main__":
    main(sys.argv[1:])
