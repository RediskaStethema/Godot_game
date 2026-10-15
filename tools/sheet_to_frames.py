"""Лист анимаций PNG (ряды idle / бег / стрельба / смерть, необязательно — боевой клич) → кадры PNG + frames.tres для Soldier.gd.

    python tools/sheet_to_frames.py assets/assetlist.png assets/sprites/space_marine_v2

Лист: прозрачный фон, анимации — ряды сверху вниз в порядке ROW_ANIMS, кадры в ряду — слева
направо с промежутками. Подписи (заголовки рядов, номера кадров) — низкие полосы, пропускаются
сами (ряд кадров — полоса выше MIN_ROW_HEIGHT). Кадры режутся по силуэту: вспышка выстрела
не считается телом (она тянется к соседнему кадру), брызги крови уже MIN_FRAME_WIDTH
приклеиваются к кадру слева.

Выравнивание: y — нижняя точка ряда (общая линия земли), x — центр шлема (верхняя четверть
силуэта): так боец не скачет из кадра в кадр. В смерти шлем уходит вниз — там x по центру
тела со сдвигом первого кадра. Масштаб 1:1 (пиксель-арт), холст общий, ноги — по центру низа,
как у tools/gif_to_frames.py. muzzle / shot_frame — по первой вспышке в ряду стрельбы.
"""
import sys
from pathlib import Path

from PIL import Image

from gif_to_frames import IMPORT_PARAMS, FILL

ROW_ANIMS = ["idle", "walk", "attack", "death"]
# Необязательный пятый ряд — боевой клич (Chaplain): кадр показывается, пока он кричит (Soldier.BATTLE_CRY_TIME)
EXTRA_ROWS = ["battle_cry"]
FOLDERS = {"idle": "idle", "walk": "run", "attack": "attack", "death": "death", "battle_cry": "battle_cry"}
LOOPING = {"idle", "walk"}
FPS = {"idle": 8.0, "walk": 14.0, "attack": 16.0, "death": 10.0, "battle_cry": 1.5}
ALPHA_MIN = 128
MIN_ROW_HEIGHT = 80
MIN_FRAME_WIDTH = 20
HEAD_PART = 0.25
LABEL_PART = 0.2     # отдельный кусок выше этой доли высоты кадра — подпись ряда
STRAY_SIZE = 40      # меньше — крошка соседнего кадра
SPLIT_WINDOW = 0.3   # где искать границу слипшихся кадров: ± доля шага
NARROW_PART = 0.35   # кусок уже этой доли шага кадров — не кадр, а хвост кадра слева


def is_flash(p):
    r, g, b, a = p
    return a > ALPHA_MIN and r > 200 and g > 100 and b < 150 and r - b > 80


def is_body(p):
    return p[3] > ALPHA_MIN and not is_flash(p)


def runs(values):
    """[(начало, конец)) подряд идущих ненулевых значений."""
    out, start = [], None
    for i, v in enumerate(values):
        if v and start is None:
            start = i
        elif not v and start is not None:
            out.append((start, i))
            start = None
    if start is not None:
        out.append((start, len(values)))
    return out


def find_rows(img):
    px = img.load()
    w, h = img.size
    bands = runs([any(px[x, y][3] > ALPHA_MIN for x in range(0, w, 2)) for y in range(h)])
    return [b for b in bands if b[1] - b[0] >= MIN_ROW_HEIGHT]


def find_cells(img, y0, y1, pitch=0.0, split=True):
    """Ячейки кадров ряда: от начала тела до начала следующего (вспышка уходит вправо).
    Кадры, слипшиеся силуэтами (ствол касается соседа), делятся по шагу кадров pitch:
    кусок шириной в n шагов режется на n по самым «тонким» столбцам у ожидаемых границ.
    split = False — не делить (смерть: лежащий боец шире шага кадров)."""
    px = img.load()
    w = img.width
    counts = [sum(1 for y in range(y0, y1) if is_body(px[x, y])) for x in range(w)]
    segs = runs(counts)
    merged = []
    for s in segs:
        # Узкий кусок (брызги крови, меч лежащего бойца) — часть кадра слева
        if merged and s[1] - s[0] < max(MIN_FRAME_WIDTH, pitch * NARROW_PART):
            merged[-1] = (merged[-1][0], s[1])
        else:
            merged.append(s)
    starts = []
    for s0, s1 in merged:
        starts.append(s0)
        n = round((s1 - s0) / pitch) if pitch > 0 and split else 1
        step = (s1 - s0) / max(n, 1)
        for k in range(1, n):
            mid = round(s0 + step * k)
            win = range(max(s0 + 1, mid - round(step * SPLIT_WINDOW)), min(s1 - 1, mid + round(step * SPLIT_WINDOW)))
            starts.append(min(win, key=lambda x: counts[x]))
    starts.append(w)
    return [(starts[i], starts[i + 1]) for i in range(len(starts) - 1)]


def frame_pitch(img, y0, y1):
    """Шаг кадров листа — медиана расстояний между началами кадров первого ряда (idle)."""
    cells = find_cells(img, y0, y1)
    gaps = sorted(c1 - c0 for c0, c1 in cells[:-1])
    return gaps[len(gaps) // 2] if gaps else 0.0


def body_box(frame):
    px = frame.load()
    pts = [(x, y) for y in range(frame.height) for x in range(frame.width) if is_body(px[x, y])]
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return min(xs), min(ys), max(xs) + 1, max(ys) + 1, pts


def parts_of(frame, alpha_min=0):
    """Связные куски пикселей кадра с альфой > alpha_min, самый большой (фигура) — первым."""
    px = frame.load()
    w, h = frame.size
    seen = set()
    parts = []
    for sy in range(h):
        for sx in range(w):
            if (sx, sy) in seen or px[sx, sy][3] <= alpha_min:
                continue
            part, stack = [], [(sx, sy)]
            seen.add((sx, sy))
            while stack:
                x, y = stack.pop()
                part.append((x, y))
                for nx in (x - 1, x, x + 1):
                    for ny in (y - 1, y, y + 1):
                        if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in seen and px[nx, ny][3] > alpha_min:
                            seen.add((nx, ny))
                            stack.append((nx, ny))
            parts.append(part)
    parts.sort(key=len, reverse=True)
    return parts


def clear_halo(frame):
    """Полупрозрачный ореол, оставшийся без плотных пикселей рядом (стёртые куски), — в ноль."""
    px = frame.load()
    w, h = frame.size
    for y in range(h):
        for x in range(w):
            if 0 < px[x, y][3] <= ALPHA_MIN and not any(
                    px[nx, ny][3] > ALPHA_MIN
                    for nx in range(max(0, x - 2), min(w, x + 3)) for ny in range(max(0, y - 2), min(h, y + 3))):
                px[x, y] = (0, 0, 0, 0)


def clear_label(frame, by_color=False):
    """Подписи листа стираются: отдельные от фигуры куски целиком выше её макушки или в верхней
    LABEL_PART кадра (поднятый крозиус достаёт до строки подписи) — заголовок ряда, и целиком ниже
    её ног — номера кадров. Куски — по плотным пикселям: ореол листа склеивает буквы с фигурой.
    by_color — подпись касается фигуры (ряд из одного кадра): в строке подписи стираются её цвета —
    белые буквы и тёмно-синяя обводка (у оружия и брони в этой строке — тёплые цвета)."""
    px = frame.load()
    if by_color:
        _clear_label_colors(frame)
    parts = parts_of(frame, ALPHA_MIN)
    top = min(y for _, y in parts[0])
    feet = max(y for _, y in parts[0])
    for part in parts[1:]:
        ys = [y for _, y in part]
        if max(ys) <= top + 2 or max(ys) < frame.height * LABEL_PART or min(ys) >= feet - 2:
            for x, y in part:
                px[x, y] = (0, 0, 0, 0)
    clear_halo(frame)
    return frame


def _clear_label_colors(frame):
    px = frame.load()
    w, h = frame.size
    band = int(h * LABEL_PART)
    whites = [y for y in range(band) for x in range(w)
              if px[x, y][3] > ALPHA_MIN and min(px[x, y][:3]) > 200]
    if not whites:
        return
    for y in range(max(whites) + 4):   # буквы + обводка под ними
        for x in range(w):
            r, g, b, a = px[x, y]
            if a > 0 and b >= r - 10:
                px[x, y] = (0, 0, 0, 0)


def clear_strays(frame):
    """Кончик ствола / вспышки кадра слева, залетевший в ячейку, и мелкие крошки соседей
    стираются: куски, не касающиеся фигуры, левее шлема или меньше STRAY_SIZE пикселей.
    Только для стоя / бега / стрельбы — в смерти мелкие куски — брызги крови.
    Куски — по плотным пикселям: полупрозрачный ореол листа склеивает их с фигурой;
    ореол, оставшийся без плотных пикселей рядом, стирается следом."""
    px = frame.load()
    w, h = frame.size
    hx = head_x(frame)
    parts = parts_of(frame, ALPHA_MIN)
    for part in parts[1:]:
        if min(x for x, _ in part) < hx or len(part) < STRAY_SIZE:
            for x, y in part:
                px[x, y] = (0, 0, 0, 0)
    clear_halo(frame)
    return frame


def clear_stray_flash(frame):
    """Тёплый хвост вспышки кадра слева, касающийся брони, стирается."""
    clear_strays(frame)
    px = frame.load()
    w, h = frame.size
    hx = head_x(frame)
    # Хвост, касающийся брони: в каждой строке слева — тёплые пиксели до первого контура
    for y in range(h):
        for x in range(int(hx)):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            if r > 120 and r - b > 70:
                px[x, y] = (0, 0, 0, 0)
            else:
                break
    return frame


def muzzle_flash(frame):
    """Пиксели вспышки правее тела (окантовка брони того же цвета — внутри силуэта)."""
    x1 = body_box(frame)[2]
    px = frame.load()
    return [(x, y) for y in range(frame.height) for x in range(x1 - 2, frame.width) if is_flash(px[x, y])]


def head_x(frame):
    x0, y0, x1, y1, pts = body_box(frame)
    limit = y0 + (y1 - y0) * HEAD_PART
    xs = [x for x, y in pts if y < limit]
    return sum(xs) / len(xs)


def main(sheet, folder, hit_frame=None, attack_fps=None, extra_anim=None, rows_order=None, drop=None):
    if rows_order:   # ряды листа в другом порядке (Дредноут: удар — второй ряд, шаг — третий)
        ROW_ANIMS[:] = rows_order
    if extra_anim:   # пятый ряд под своим именем (Дредноут: victory — поза победы)
        EXTRA_ROWS[0] = extra_anim
        FOLDERS[extra_anim] = extra_anim
        FPS[extra_anim] = FPS["battle_cry"]
    img = Image.open(sheet).convert("RGBA")
    # Полупрозрачный ореол фона (альфа 1–5 на листе) — в ноль
    img.putalpha(img.getchannel("A").point(lambda a: 0 if a < 16 else a))
    folder = Path(folder)
    res_folder = "res://" + folder.as_posix().strip("/")
    rows = find_rows(img)
    anims = ROW_ANIMS + EXTRA_ROWS[:max(len(rows) - len(ROW_ANIMS), 0)]
    if len(rows) != len(anims):
        sys.exit(f"рядов кадров {len(rows)}, ожидалось {len(ROW_ANIMS)}–{len(ROW_ANIMS) + len(EXTRA_ROWS)}: {rows}")

    # Кадры и якоря (x — в координатах кадра, y — линия земли ряда)
    src = {}
    pitch = frame_pitch(img, *rows[0])
    for anim, (y0, y1) in zip(anims, rows):
        if anim in EXTRA_ROWS:   # один кадр на весь ряд — подпись ряда сотрёт clear_label
            frames = [img.crop((0, y0, img.width, y1))]
        else:
            frames = [img.crop((c0, y0, c1, y1)) for c0, c1 in find_cells(img, y0, y1, pitch, anim != "death")]
        frames = [clear_label(f, anim in EXTRA_ROWS) for f in frames]
        if anim == "attack":
            frames = [clear_stray_flash(f) for f in frames]
        elif anim != "death":
            frames = [clear_strays(f) for f in frames]
        ground = max(body_box(f)[3] for f in frames)
        if anim == "death":
            bx = body_box(frames[0])
            shift = head_x(frames[0]) - (bx[0] + bx[2]) / 2
            anchors = [((b[0] + b[2]) / 2 + shift, ground) for b in map(body_box, frames)]
        else:
            anchors = [(head_x(f), ground) for f in frames]
        if drop and anim in drop:   # кадры, выпадающие из цикла (кривой лист), — убрать
            keep = [i for i in range(len(frames)) if i not in drop[anim]]
            frames = [frames[i] for i in keep]
            anchors = [anchors[i] for i in keep]
        src[anim] = (frames, anchors)

    half_w = top = 0
    for frames, anchors in src.values():
        for f, (ax, ay) in zip(frames, anchors):
            box = f.getbbox()
            half_w = max(half_w, ax - box[0], box[2] - ax)
            top = max(top, ay - box[1])
    idle_box = body_box(src["idle"][0][0])
    canvas_h = round(max(top, (idle_box[3] - idle_box[1]) / FILL))
    canvas_w = 2 * round(half_w + 4)

    ext, tres_anims, meta = [], [], ""
    for anim, (frames, anchors) in src.items():
        out_dir = folder / FOLDERS[anim]
        out_dir.mkdir(parents=True, exist_ok=True)
        for old in out_dir.iterdir():
            if old.name.endswith(".png") or old.name.endswith(".png.import"):
                old.unlink()
        refs = []
        for i, (f, (ax, ay)) in enumerate(zip(frames, anchors)):
            canvas = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
            canvas.alpha_composite(f, (round(canvas_w / 2 - ax), round(canvas_h - ay)))
            canvas.save(out_dir / f"{i}.png")
            (out_dir / f"{i}.png.import").write_text(IMPORT_PARAMS, encoding="utf-8")
            ext.append(f'[ext_resource type="Texture2D" path="{res_folder}/{FOLDERS[anim]}/{i}.png" id="{anim}_{i}"]')
            refs.append(f'{{\n"duration": 1.0,\n"texture": ExtResource("{anim}_{i}")\n}}')
            if anim == "attack" and not meta:
                flash = muzzle_flash(f)
                if len(flash) > 10:
                    mx = min(x for x, _ in flash)
                    my = sum(y for x, y in flash if x < mx + 3) / len([1 for x, _ in flash if x < mx + 3])
                    meta = (f"metadata/muzzle = Vector2({mx - ax:.1f}, {my - ay:.1f})\n"
                            f"metadata/shot_frame = {i}\n")
        tres_anims.append(
            f'{{\n"frames": [{", ".join(refs)}],\n"loop": {"true" if anim in LOOPING else "false"},\n'
            f'"name": &"{anim}",\n"speed": {attack_fps if anim == "attack" and attack_fps else FPS[anim]}\n}}')
        print(anim, len(frames), "кадров")

    if hit_frame is not None:
        meta += f"metadata/hit_frame = {hit_frame}\n"
    tres = (f'[gd_resource type="SpriteFrames" load_steps={len(ext) + 1} format=3]\n\n'
            + "\n".join(ext)
            + f'\n\n[resource]\n{meta}animations = [{", ".join(tres_anims)}]\n')
    (folder / "frames.tres").write_text(tres, encoding="utf-8")
    print(f"холст {canvas_w}x{canvas_h}; {meta.strip()}")


if __name__ == "__main__":
    # Ближний бой: --hit-frame N — кадр атаки, на котором удар доходит до цели (Soldier бьёт на нём),
    # --attack-fps F — своя скорость атаки (тяжёлый замах Дредноута),
    # --extra-anim NAME — имя анимации пятого ряда вместо battle_cry (Дредноут: victory),
    # --rows a,b,c,d — порядок первых четырёх рядов листа (по умолчанию idle,walk,attack,death),
    # --drop anim:i,j[;anim:k] — убрать кадры анимации (номера после нарезки), выпадающие из цикла
    args = sys.argv[1:]
    opts = {}
    for key in ("--hit-frame", "--attack-fps", "--extra-anim", "--rows", "--drop"):
        if key in args:
            i = args.index(key)
            opts[key] = args[i + 1]
            del args[i:i + 2]
    main(args[0], args[1],
         int(opts["--hit-frame"]) if "--hit-frame" in opts else None,
         float(opts["--attack-fps"]) if "--attack-fps" in opts else None,
         opts.get("--extra-anim"),
         opts["--rows"].split(",") if "--rows" in opts else None,
         {a: {int(i) for i in idx.split(",")} for a, idx in (p.split(":") for p in opts["--drop"].split(";"))}
         if "--drop" in opts else None)
