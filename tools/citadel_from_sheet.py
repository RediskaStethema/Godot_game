"""Лист анимации цитадели (ряды idle / attack / hit / fall, подписи, красный ромб основания под
каждым кадром, прозрачный фон) → лист кадров для FactionTheme "citadel": одна сетка, у всех
кадров общая точка основания.

    python tools/citadel_from_sheet.py assets/citadel_marine.png assets/sprites/props/space_marines/citadel

Кадр — крупное пятно (альфа > BODY_ALPHA) в полосе ряда, его окно по x — до середины зазора
с соседями: дым и обломки рядом с кадром остаются его. Основание — центр красного ромба-метки;
ромб перекрашивается в камень площадки, подписи (ниже ромба) и шапки рядов стираются.
Кадры листа нарисованы чуть разного размера (основание гуляет до 20%) — каждый подгоняется
к первому кадру idle по силуэту (масштаб и сдвиг основания), руины — к предыдущему кадру.
Следы снарядов на кадрах выстрела срезаны у края крепости (снаряд рисует игра — Projectile),
вспышка у ствола остаётся. Стилизация (палитра поля Космодесанта): камень и сталь — холоднее
и приглушённее, огни (тёплые яркие пиксели) — как есть.
Пишет <выход>/sheet.png и печатает frame_size, anchor и ряды для FactionTheme.
"""
import colorsys
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
from tiles_from_sheet import components, dilate  # noqa: E402

BODY_ALPHA = 120
MIN_BODY = 4000        # пятно меньше — подпись или обломок
HEADER_MAX_H = 60      # шапка ряда («1. IDLE») — низкое широкое пятно у левого края
ALPHA_CUT = 30         # ореол фона листа
LABEL_GAP = 9          # подписи кадров — ниже ромба больше чем на столько px
TRAIL_MARGIN = 6       # след снаряда срезается дальше края основания крепости
TRAIL_RIGHT = 50       # и над крышей: правее основания на столько px (конец ствола — +44)
TRAIL_ABOVE = 125      # … и выше основания на столько px (огонь правого шпиля — −113)
SCRAP_MAX = 400        # px — мелкий кусок
SOLID_ALPHA = 90       # плотный пиксель (не ореол)
HALO = 5               # px ореола вокруг оставшихся кусков
SCRAP_NEAR = 12        # px от крепости — ближе: обломки и дым своего кадра
ROWS = ["idle", "attack", "hit", "fall"]
SKIP = {"idle": [0], "hit": [3]}   # 1-й кадр idle — без знамени (мигало бы в цикле); 4-й кадр
                                    # попадания — уже руины (начало падения)
PAD = 4
# Подгонка кадров к эталону по силуэту: масштабы, шаг, сдвиг основания ±px; полосы относительно
# основания (верх, низ): тело крепости без знамени и орудия; низ руин
REG_SCALES = (0.8, 1.5)
REG_STEP = 0.01
REG_SHIFT = 8
REG_BODY = (-120, 4)
FALL_STANDING = 3   # кадров обрушения, где крепость ещё цела (сверяются с эталоном), дальше — руины
REG_CANVAS = 320
REG_ORIGIN = (160, 260)
# Стилизация камня: насыщенность ×, яркость ×, сдвиг тона к стальному синему
STONE_SAT = 0.72
STONE_VAL = 0.9
STEEL_HUE = 0.6
STEEL_PULL = 0.25


def red_marker(img):
    r, g, b, a = [img[..., i].astype(int) for i in range(4)]
    return (r > 170) & (g < 45) & (b < 45) & (a > 100)


def find_frames(img):
    label, ids = components(dilate(img[..., 3] > BODY_ALPHA, 2))
    bodies, headers = [], []
    for n in ids:
        ys, xs = np.nonzero(label == n)
        if len(ys) < MIN_BODY:
            continue
        box = (ys.min(), xs.min(), ys.max() + 1, xs.max() + 1)
        (headers if box[2] - box[0] < HEADER_MAX_H else bodies).append(box)
    bodies.sort(key=lambda b: b[0])
    rows, cur = [], []
    for b in bodies:
        if cur and b[0] - cur[0][0] > 120:
            rows.append(cur)
            cur = []
        cur.append(b)
    rows.append(cur)
    return [sorted(r, key=lambda b: b[1]) for r in rows], headers


def stylize(px):
    """RGBA uint8 → камень холоднее и тусклее, тёплые яркие огни не трогает."""
    out = px.copy()
    rgb = px[..., :3].astype(float) / 255.0
    h, w = rgb.shape[:2]
    flat = rgb.reshape(-1, 3)
    res = np.empty_like(flat)
    for i, (r, g, b) in enumerate(flat):
        hh, s, v = colorsys.rgb_to_hsv(r, g, b)
        warm = (hh < 0.17 or hh > 0.95) and s > 0.45 and v > 0.55
        blue = 0.55 < hh < 0.72 and s > 0.4   # знамёна и витражи — цвет ордена, не камень
        if not warm and not blue:
            hh = hh + (STEEL_HUE - hh) * STEEL_PULL * (1.0 - s) if s < 0.5 else hh
            s *= STONE_SAT
            v *= STONE_VAL
        res[i] = colorsys.hsv_to_rgb(hh, s, v)
    out[..., :3] = (res.reshape(h, w, 3) * 255.0 + 0.5).clip(0, 255).astype(np.uint8)
    return out


def drop_scraps(frame, detached=False):
    """Куски соседних кадров (дым, обломки, след снаряда, щепки шпилей) — прочь: всё, что задевает
    край окна, и мелкие куски дальше SCRAP_NEAR px от крепости; detached — все отдельные куски
    (кадр выстрела: обломков нет, отдельно от крепости — только следы снарядов)."""
    # куски — по плотным пикселям: полупрозрачный ореол листа связал бы всё в одно пятно
    label, ids = components(dilate(frame[..., 3] > SOLID_ALPHA, 2))
    sizes = {n: int((label == n).sum()) for n in ids}
    main = max(sizes, key=sizes.get)
    keep = np.zeros(label.shape, bool)
    ys, xs = np.nonzero(label == main)
    mx0, mx1, my0 = xs.min() - SCRAP_NEAR, xs.max() + SCRAP_NEAR, ys.min() - SCRAP_NEAR
    w = frame.shape[1]
    for n in ids:
        if n == main:
            continue
        ys, xs = np.nonzero(label == n)
        far = xs.max() < mx0 or xs.min() > mx1 or ys.max() < my0
        if detached or xs.min() <= 1 or xs.max() >= w - 2 or (far and sizes[n] < SCRAP_MAX)                 or (sizes[n] < SCRAP_MAX // 4 and (xs.min() < mx0 + SCRAP_NEAR or xs.max() > mx1 - SCRAP_NEAR)):
            continue
        keep |= label == n
    keep |= label == main
    frame[~dilate(keep, HALO)] = 0   # ореол — только у оставшихся кусков
    return frame


def silhouette(frame, anchor, scale, region):
    """Плотный силуэт кадра в масштабе scale на холсте REG_CANVAS с основанием в REG_ORIGIN;
    region (верх, низ) — полоса относительно основания, px эталона."""
    im = Image.fromarray(frame[..., 3])
    if abs(scale - 1.0) > 1e-3:
        im = im.resize((max(1, round(im.width * scale)), max(1, round(im.height * scale))), Image.BILINEAR)
    a = np.array(im) > 200
    canvas = np.zeros((REG_CANVAS, REG_CANVAS), bool)
    ox = REG_ORIGIN[0] - int(round(anchor[0] * scale))
    oy = REG_ORIGIN[1] - int(round(anchor[1] * scale))
    y0, x0 = max(oy, 0), max(ox, 0)
    y1, x1 = min(oy + a.shape[0], REG_CANVAS), min(ox + a.shape[1], REG_CANVAS)
    canvas[y0:y1, x0:x1] = a[y0 - oy:y1 - oy, x0 - ox:x1 - ox]
    canvas[:REG_ORIGIN[1] + region[0]] = False
    canvas[REG_ORIGIN[1] + region[1]:] = False
    return canvas


def register(frame, anchor, ref, region):
    """Масштаб и сдвиг основания, при которых силуэт кадра лучше всего ложится на эталон ref
    (наибольшее пересечение / объединение): художник рисовал кадры чуть разного размера."""
    best = (-1.0, 1.0, 0, 0)
    for scale in np.arange(REG_SCALES[0], REG_SCALES[1] + 1e-6, REG_STEP):
        sil = silhouette(frame, anchor, scale, (region[0] - REG_SHIFT, region[1] + REG_SHIFT))
        for dy in range(-REG_SHIFT, REG_SHIFT + 1):
            for dx in range(-REG_SHIFT, REG_SHIFT + 1):
                moved = np.roll(np.roll(sil, dy, axis=0), dx, axis=1)
                band = slice(REG_ORIGIN[1] + region[0], REG_ORIGIN[1] + region[1])
                inter = (moved[band] & ref[band]).sum()
                union = (moved[band] | ref[band]).sum()
                iou = inter / union if union else 0.0
                if iou > best[0]:
                    best = (iou, scale, dx, dy)
    return best


def main(sheet, out_dir):
    img = np.array(Image.open(sheet).convert("RGBA"))
    rows, headers = find_frames(img)
    for y0, x0, y1, x1 in headers:
        img[y0:y1, x0:x1, 3] = 0
    marker = red_marker(img)
    img[img[..., 3] < ALPHA_CUT] = 0
    # Окна кадров и основания; подписи под ромбами стираются заранее — иначе попадут в кадр ряда ниже
    windows = []
    for bodies in rows:
        row = []
        for k, (by0, bx0, by1, bx1) in enumerate(bodies):
            left = 0 if k == 0 else (bodies[k - 1][3] + bx0) // 2
            right = img.shape[1] if k == len(bodies) - 1 else (bx1 + bodies[k + 1][1]) // 2
            ys, xs = np.nonzero(marker[by0:by1 + 30, left:right])
            ay, ax = int(round(ys.mean())) + by0, int(round(xs.mean())) + left
            img[ay + LABEL_GAP:ay + 40, left:right] = 0
            row.append((by0, bx0, by1, bx1, left, right, ax, ay))
        windows.append(row)
    cut = []   # [(ряд, кадр RGBA, якорь (x, y) в кадре)]
    ref = None
    standing = None   # масштаб и сдвиг последнего кадра обрушения, где крепость ещё стоит
    for name, bodies in zip(ROWS, windows):
        for k, (by0, bx0, by1, bx1, left, right, ax, ay) in enumerate(bodies):
            top = max(by0 - 40, 0)
            frame = img[top:ay + LABEL_GAP, left:right].copy()
            # ромб → камень площадки: цвет — средний у его краёв
            m = marker[top:ay + LABEL_GAP, left:right]
            ring = dilate(m, 5) & ~dilate(m, 3) & (frame[..., 3] > 200)
            frame[dilate(m, 3) & (frame[..., 3] > 0), :3] = np.median(frame[ring][:, :3], axis=0).astype(np.uint8)
            anchor = (ax - left, ay - top)
            frame = drop_scraps(frame)
            if name == "attack":
                # край крепости — по ширине основания (пятно кадра тянется вдоль следа)
                band = frame[anchor[1] - 40:anchor[1] - 20, :, 3] > 200
                xs = np.nonzero(band.any(axis=0))[0]
                frame[:, xs.max() + TRAIL_MARGIN:] = 0
                # след над крышей — правее и выше конца ствола
                frame[:anchor[1] - TRAIL_ABOVE, anchor[0] + TRAIL_RIGHT:] = 0
                frame = drop_scraps(frame, detached=True)
            if k in SKIP.get(name, []):
                continue
            # Каждый кадр — к размеру и месту эталона (первый кадр idle); у руин силуэта крепости
            # нет (ромб-метка листа постоянного размера — по нему тоже нельзя) — масштаб и сдвиг
            # последнего стоящего кадра обрушения: груда оседает без скачка размера
            if ref is None:
                ref = silhouette(frame, anchor, 1.0, REG_BODY)
                iou, scale, dx, dy = 1.0, 1.0, 0, 0
            elif name == "fall" and k >= FALL_STANDING:
                iou, scale, dx, dy = standing
            else:
                iou, scale, dx, dy = register(frame, anchor, ref, REG_BODY)
                if name == "fall":
                    standing = (iou, scale, dx, dy)
            if abs(scale - 1.0) > 1e-3:
                im = Image.fromarray(frame)
                im = im.resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS)
                frame = np.array(im)
            anchor = (anchor[0] * scale - dx, anchor[1] * scale - dy)
            print(f"  {name} {k + 1}: масштаб {scale:.2f}, сдвиг ({dx}, {dy}), совпадение {iou:.2f}")
            ys, xs = np.nonzero(frame[..., 3])
            frame = frame[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
            anchor = (anchor[0] - xs.min(), anchor[1] - ys.min())
            cut.append((name, stylize(frame), anchor))
        print(f"{name}: {len(bodies) - len(SKIP.get(name, []))} кадров")
    # Общая сетка: якорь в одной точке каждой клетки
    left = max(a[0] for _, _, a in cut)
    up = max(a[1] for _, _, a in cut)
    right = max(f.shape[1] - a[0] for _, f, a in cut)
    down = max(f.shape[0] - a[1] for _, f, a in cut)
    fw, fh = int(np.ceil(left + right)) + 2 * PAD, int(np.ceil(up + down)) + 2 * PAD
    counts = {n: sum(1 for c in cut if c[0] == n) for n in ROWS}
    sheet_img = Image.new("RGBA", (fw * max(counts.values()), fh * len(ROWS)), (0, 0, 0, 0))
    col = {n: 0 for n in ROWS}
    for name, frame, (ax, ay) in cut:
        r = ROWS.index(name)
        x = col[name] * fw + PAD + int(round(left - ax))
        y = r * fh + PAD + int(round(up - ay))
        sheet_img.alpha_composite(Image.fromarray(frame), (x, y))
        col[name] += 1
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    sheet_img.save(out / "sheet.png")
    print(f'"frame_size": Vector2i({fw}, {fh}), "anchor": Vector2({PAD + left:.0f}, {PAD + up:.0f}),')
    print('"rows": {' + ", ".join(f'"{n}": [{i}, {counts[n]}]' for i, n in enumerate(ROWS)) + "}")


if __name__ == "__main__":
    main(*sys.argv[1:3])
