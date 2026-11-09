"""Планета живой сцены меню — целиком, без среза по левому краю холста (решение пользователя 06.11.2026: «теперь
планета как бы обрезана» — после фона-космоса меню вертикальный срез планеты у левого края сцены стал виден).

Художник обрезал планету рамкой холста 712×1172 (диск уходит за левый край на ~280 px). Скрипт:
  1. уточняет окружность диска по яркой кромке атмосферы (наибольшая яркость вдоль радиусов, МНК);
  2. layer_planet_wide.png / layer_clouds_wide.png — холст шире на EXT px слева: недостающая часть диска —
     тот же слой, повёрнутый вокруг центра диска на ROTATE (кусок сверху; радиус сохраняется — кромка
     атмосферы и затемнение к краю продолжаются сами; зеркало давало заметную «ёлочку» облаков), у бывшего
     среза — перетекание на BLEND px; облака — только внутри диска;
  3. layer_space_edge.png — космос сцены с прозрачным левым краем (SPACE_FADE px): через него проступают фон и
     звёзды меню — у сцены больше нет вертикальной границы.
MenuSceneArt берёт *_wide / *_edge, если они есть (планета и облака — со сдвигом −EXT), иначе прежние слои.
Шов (решение пользователя 08.11.2026, «всё ещё есть шов»): прямая граница с перетеканием на BLEND px смешивала две
разные картинки облаков — вертикальная смазанная полоса. Теперь угол поворота подбирается (ROTATE_TRY — наименьшая
разница с исходным слоем в полосе BAND px у бывшего среза), а граница — шов наименьшей разницы через эту полосу
(динамикой по строкам, как при склейке текстур: петляет там, где обе картинки почти совпадают), растушёвка FEATHER px.
Шов один на планету и облака (разница — по картинке «планета + облака»).
Исходники не меняет. Повторный прогон — с тем же результатом.

  python tools/menu_planet_extend.py
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
ANIM = ROOT / "assets/ui/menu/anim"
EXT = 320            # px холста — запас слева (диск уходит за край на ~280)
SPACE_FADE = 260     # px — прозрачный край космоса сцены
ROTATE = 50.0        # градусов — недостающий кусок диска берётся сверху диска, повёрнутым вокруг центра
BLEND = 60           # px — (прежний способ, не используется) перетекание у бывшего среза
ROTATE_TRY = range(30, 72, 2)   # градусы — перебор угла поворота
BAND = 170           # px исходного холста от бывшего среза — полоса, где идёт шов
EDGE_KEEP = 30       # px — шов не прижимается к краям полосы (у самого среза пиксели исходного полупрозрачные)
FEATHER = 5.0        # px — растушёвка шва
RIM_FEATHER = 60.0   # px — у кромки атмосферы растушёвка шире (кромка рисунка — не идеальный круг, шов давал ступеньку)
RIM_ZONE = 40.0      # px внутрь от кромки, где растушёвка растёт до RIM_FEATHER
CLOUD_FEATHER = 25.0 # px — у облаков шов мягче (у края диска облака плотнее, чем в куске, откуда берётся копия)
DENSITY_ROWS = 61    # строк — окно, по которому плотность облаков копии подтягивается к исходной у шва
BG = np.array([10, 14, 22], np.float32)   # фон под планетой при сравнении
GUESS = (513.0, 1278.0, 797.0)   # центр и радиус по верхней кромке (первая оценка)


def lum(img):
    return img[..., :3].astype(np.float32) @ np.array([0.3, 0.59, 0.11], np.float32)


def fit_circle(planet):
    cx, cy, r = GUESS
    l = lum(planet)
    h, w = l.shape
    pts = []
    for ang in np.radians(np.arange(-175.0, -5.0, 1.5)):
        best = None
        for d in range(-40, 41):
            x = int(round(cx + (r + d) * np.cos(ang)))
            y = int(round(cy + (r + d) * np.sin(ang)))
            if not (2 <= x < w and 0 <= y < h) or planet[y, x, 3] < 120:
                continue
            if best is None or l[y, x] > best[0]:
                best = (l[y, x], x, y)
        if best and best[0] > 200:
            pts.append(best[1:])
    pts = np.array(pts, np.float64)
    a = np.c_[pts[:, 0], pts[:, 1], np.ones(len(pts))]
    b = -(pts[:, 0] ** 2 + pts[:, 1] ** 2)
    d, e, f = np.linalg.lstsq(a, b, rcond=None)[0]
    cx, cy = -d / 2, -e / 2
    return cx, cy, float(np.sqrt(cx * cx + cy * cy - f)), len(pts)


def extend(layer, cx, cy, r, clouds=False):
    """Холст шире на EXT слева: недостающее — тот же слой, повёрнутый вокруг центра диска на ROTATE (кусок
    сверху диска; радиус сохраняется — кромка, свечение и затемнение к краю продолжаются сами), у бывшего
    среза — перетекание на BLEND px в исходный слой."""
    h, w = layer.shape[:2]
    W = w + EXT
    ys, xs = np.mgrid[0:h, 0:W]
    x = xs - EXT                                   # координата исходного холста
    a = np.radians(ROTATE)
    dx, dy = x - cx, ys - cy
    sx = np.round(cx + dx * np.cos(a) - dy * np.sin(a)).astype(int)
    sy = np.round(cy + dx * np.sin(a) + dy * np.cos(a)).astype(int)
    ok = (sx >= 0) & (sx < w) & (sy >= 0) & (sy < h)
    rot = np.zeros((h, W, 4), np.float32)
    rot[ok] = layer[sy[ok], sx[ok]]
    orig = np.zeros((h, W, 4), np.float32)
    orig[:, EXT:] = layer
    wgt = np.clip(x / BLEND, 0.0, 1.0)[..., None]   # 0 — левее среза (поворот), 1 — исходный слой
    out = rot * (1.0 - wgt) + orig * wgt
    if clouds:   # облака — только внутри диска
        dist = np.sqrt(dx ** 2 + dy ** 2) - r
        out[..., 3] *= np.clip((-dist - 2.0) / 6.0, 0.0, 1.0)
    return np.clip(out, 0, 255).astype(np.uint8)


def rotated(layer, cx, cy, ang, r=None, radial=0.0):
    """Слой на широком холсте, повёрнутый вокруг центра диска на ang градусов (облака — только внутри диска);
    radial — px: берётся точка дальше от центра на столько (кромка копии совпадает с кромкой исходного у шва)."""
    h, w = layer.shape[:2]
    W = w + EXT
    ys, xs = np.mgrid[0:h, 0:W]
    x = xs - EXT
    a = np.radians(ang)
    dx, dy = x - cx, ys - cy
    if radial:
        rho = np.maximum(np.sqrt(dx ** 2 + dy ** 2), 1.0)
        k = (rho + radial) / rho
        dx, dy = dx * k, dy * k
    sx = np.round(cx + dx * np.cos(a) - dy * np.sin(a)).astype(int)
    sy = np.round(cy + dx * np.sin(a) + dy * np.cos(a)).astype(int)
    ok = (sx >= 0) & (sx < w) & (sy >= 0) & (sy < h)
    out = np.zeros((h, W, 4), np.float32)
    out[ok] = layer[sy[ok], sx[ok]]
    if r is not None:
        dist = np.sqrt(dx ** 2 + dy ** 2) - r
        out[..., 3] *= np.clip((-dist - 2.0) / 6.0, 0.0, 1.0)
    return out


def padded(layer):
    h, w = layer.shape[:2]
    out = np.zeros((h, w + EXT, 4), np.float32)
    out[:, EXT:] = layer
    return out


def composite(planet, clouds):
    pa = planet[..., 3:4] / 255.0
    c = planet[..., :3] * pa + BG * (1.0 - pa)
    ca = clouds[..., 3:4] / 255.0
    return c * (1.0 - ca) + clouds[..., :3] * ca


def mix(a, b, wgt):
    """a·(1−wgt) + b·wgt с премультиплицированной альфой: прозрачные пиксели (чёрные) не темнят смесь."""
    aa, ab = a[..., 3:4] / 255.0, b[..., 3:4] / 255.0
    alpha = aa * (1.0 - wgt) + ab * wgt
    rgb = (a[..., :3] * aa * (1.0 - wgt) + b[..., :3] * ab * wgt) / np.maximum(alpha, 1e-4)
    return np.concatenate([rgb, alpha * 255.0], axis=-1)


def min_seam(diff):
    """Шов сверху вниз через полосу diff (строки × столбцы) с наименьшей суммой, шаг ±1 столбец."""
    h, w = diff.shape
    m = diff.copy()
    for y in range(1, h):
        prev = m[y - 1]
        left = np.r_[np.inf, prev[:-1]]
        right = np.r_[prev[1:], np.inf]
        m[y] += np.minimum(np.minimum(left, prev), right)
    seam = np.zeros(h, int)
    seam[-1] = int(np.argmin(m[-1]))
    for y in range(h - 2, -1, -1):
        x = seam[y + 1]
        lo, hi = max(0, x - 1), min(w, x + 2)
        seam[y] = lo + int(np.argmin(m[y, lo:hi]))
    return seam


def extend_seamed(planet, clouds, cx, cy, r):
    po, co = padded(planet), padded(clouds)
    comp_o = composite(po, co)
    band = slice(EXT, EXT + BAND)
    rows = po[:, band, 3].max(axis=1) > 200          # строки, где в полосе есть диск
    h, W = po.shape[:2]
    xx = np.arange(W)[None, :] - EXT
    yy = np.arange(h)[:, None]
    need = (xx < 0) & (np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) < r - 3)   # достраиваемая часть диска (левее среза)
    best = None
    for ang in ROTATE_TRY:
        pr, cr = rotated(planet, cx, cy, ang), rotated(clouds, cx, cy, ang, r)
        if (pr[..., 3][need] > 200).mean() < 0.9995:   # копия должна закрыть весь недостающий кусок
            continue
        d = np.abs(composite(pr, cr)[:, band] - comp_o[:, band]).sum(axis=2)
        valid = (pr[:, band, 3] > 200) & (po[:, band, 3] > 200)
        if valid[rows].mean() < 0.9:
            continue
        err = d[rows][valid[rows]].mean()
        if best is None or err < best[0]:
            best = (err, ang, pr, cr, d)
    err, ang, pr, cr, d = best
    print(f"угол поворота {ang}° — средняя разница в полосе {err:.1f}")
    # кромка: радиальная поправка копии — наименьшая разница у кромки в полосе шва
    dist0 = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) - r
    rim = (dist0 > -RIM_ZONE) & (dist0 < 12) & (xx >= 0) & (xx < BAND)
    best_rad = None
    for rad in np.arange(-8.0, 8.5, 1.0):
        prr, crr = rotated(planet, cx, cy, ang, None, rad), rotated(clouds, cx, cy, ang, r, rad)
        ok = rim & (prr[..., 3] > 0)
        if ok.sum() < 50:
            continue
        e = np.abs(composite(prr, crr) - comp_o)[ok].mean()
        if best_rad is None or e < best_rad[0]:
            best_rad = (e, rad, prr, crr)
    if best_rad:
        print(f"радиальная поправка кромки {best_rad[1]:+.0f} px (разница у кромки {best_rad[0]:.1f})")
        pr, cr = best_rad[2], best_rad[3]
        d = np.abs(composite(pr, cr)[:, band] - comp_o[:, band]).sum(axis=2)
    # уголок свечения внизу, срезанный краем повёрнутого холста, — из копии с другим углом, с мягким краем
    # ожидаемая прозрачность по расстоянию от кромки — по исходному слою (медиана по кольцам 1 px)
    di = np.round(dist0).astype(int)
    prof = {}
    src_ok = po[..., 3] > 0
    for k in range(-20, 25):
        sel = (di == k) & (xx >= 60)
        if sel.any():
            prof[k] = float(np.median(po[..., 3][sel]))
    expect = np.vectorize(lambda k: prof.get(k, 255.0 if k < -20 else 0.0))(np.clip(di, -21, 25)).astype(np.float32)
    hole = (xx < 0) & (dist0 < 20) & (pr[..., 3] < expect * 0.7 - 5)
    hole = np.asarray(Image.fromarray((hole * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(5))) > 0
    if hole.any():
        for alt in range(ang + 6, ang + 40, 4):
            pa, ca = rotated(planet, cx, cy, alt), rotated(clouds, cx, cy, alt, r)
            if (pa[..., 3][hole] >= expect[hole] * 0.7 - 5).mean() > 0.99:
                soft = np.asarray(Image.fromarray((hole * 255).astype(np.uint8)).filter(
                    ImageFilter.GaussianBlur(4)), np.float32)[..., None] / 255.0
                soft = np.maximum(soft, hole[..., None].astype(np.float32))
                pr = mix(pr, pa, soft)
                cr = mix(cr, ca, soft)
                print(f"уголок внизу ({int(hole.sum())} px) — из копии {alt}°")
                break
    print(f"не закрыто пикселей левее среза: {int((need & (pr[..., 3] < 200)).sum())}")
    cost = d.copy()
    cost[~rows] = 0.0                                # вне диска шов идёт как угодно
    # левее шва — копия: где её нет (ушла за край холста), а исходный диск есть, шву нельзя
    gap = (pr[:, band, 3] < 200) & (po[:, band, 3] > 200)
    gap_left = np.maximum.accumulate(gap[:, ::-1], axis=1)[:, ::-1]   # дыра правее — шов должен быть левее неё
    cost[gap_left] += 1e5
    cost[:, :EDGE_KEEP] += 1e4                       # не к краям полосы
    cost[:, -EDGE_KEEP:] += 1e4
    seam = min_seam(cost)
    h, W = po.shape[:2]
    x = np.arange(W)[None, :] - EXT                  # координата исходного холста
    dist = np.sqrt((x - cx) ** 2 + (np.arange(h)[:, None] - cy) ** 2) - r
    feather = FEATHER + (RIM_FEATHER - FEATHER) * np.clip((dist + RIM_ZONE) / RIM_ZONE, 0.0, 1.0)
    wgt = np.clip((x - seam[:, None]) / feather + 0.5, 0.0, 1.0)[..., None]   # 0 — повёрнутый, 1 — исходный
    wgt = np.where(po[..., 3:4] > 0, wgt, 0.0)       # где исходного нет — только копия
    planet_out = mix(pr, po, wgt)
    # облака: плотность копии — к исходной у шва (средняя прозрачность в полосе справа от шва / в копии там же),
    # множитель по строкам, сглажен окном DENSITY_ROWS; сам шов облаков мягче
    ratio = np.ones(h, np.float32)
    for y in range(h):
        x0 = EXT + seam[y]
        a_o = co[y, x0:x0 + 60, 3]
        a_r = cr[y, max(EXT + seam[y] - 60, 0):x0, 3]
        if a_o.size and a_r.size and a_r.mean() > 4.0:
            ratio[y] = np.clip(a_o.mean() / a_r.mean(), 0.6, 2.2)
    kern = np.ones(DENSITY_ROWS, np.float32) / DENSITY_ROWS
    ratio = np.convolve(np.pad(ratio, DENSITY_ROWS // 2, mode="edge"), kern, mode="valid")[:h]
    cr = cr.copy()
    cr[..., 3] = np.clip(cr[..., 3] * ratio[:, None], 0.0, 255.0)
    feather_c = np.maximum(feather, CLOUD_FEATHER)
    wgt_c = np.clip((x - seam[:, None]) / feather_c + 0.5, 0.0, 1.0)[..., None]
    wgt_c = np.where(po[..., 3:4] > 0, wgt_c, 0.0)
    clouds_out = mix(cr, co, wgt_c)
    clouds_out[..., 3] *= np.clip((-dist - 2.0) / 6.0, 0.0, 1.0)
    return (np.clip(planet_out, 0, 255).astype(np.uint8), np.clip(clouds_out, 0, 255).astype(np.uint8))


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    planet = np.asarray(Image.open(ANIM / "layer_planet.png").convert("RGBA"))
    cx, cy, r, n = fit_circle(planet)
    print(f"диск: центр ({cx:.1f}, {cy:.1f}), радиус {r:.1f} — по {n} точкам кромки; левый край x = {cx - r:.0f}")
    if cx - r < -EXT + 4:
        print("  диск шире запаса EXT — увеличить EXT")
    clouds = np.asarray(Image.open(ANIM / "layer_clouds.png").convert("RGBA"))
    planet_wide, clouds_wide = extend_seamed(planet.astype(np.float32), clouds.astype(np.float32), cx, cy, r)
    Image.fromarray(planet_wide).save(ANIM / "layer_planet_wide.png")
    Image.fromarray(clouds_wide).save(ANIM / "layer_clouds_wide.png")
    space = np.asarray(Image.open(ANIM / "layer_space.png").convert("RGBA")).astype(np.float32)
    ramp = np.clip(np.arange(space.shape[1], dtype=np.float32) / SPACE_FADE, 0.0, 1.0)
    ramp = ramp * ramp * (3.0 - 2.0 * ramp)   # smoothstep
    space[..., 3] *= ramp[None, :]
    Image.fromarray(space.astype(np.uint8)).save(ANIM / "layer_space_edge.png")
    print("layer_planet_wide.png, layer_clouds_wide.png, layer_space_edge.png")


if __name__ == "__main__":
    main()
