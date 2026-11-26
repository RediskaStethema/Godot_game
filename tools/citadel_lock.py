"""Лист цитадели (FactionTheme "citadel": ряды idle / attack / hit / fall по N кадров одной сеткой) — без «кипения»
и прыжков (решение пользователя 10.11.2026: «цитадель Космодесанта прыгает и оторвана от текстур»).

    python tools/citadel_lock.py lock <лист.png> <выход.png> <кадр w> <кадр h> [--live sm|chaos]
    python tools/citadel_lock.py body <лист.png> <выход.png> <кадр w> <кадр h> --live chaos
    python tools/citadel_lock.py tone <лист.png> <выход.png> [--black B] [--gamma G] [--sat K] [--dark-hue H --dark-pull K]

lock:
- стойка (ряд 0): художник перерисовал крепость в каждом кадре (шпили, кладка, контур другие, сдвиг 1–2 px) —
  тело во всех кадрах — из кадра 0, из своего кадра берётся только полотнище флага (насыщенный синий над
  крышей + закрытие — подкова внутри), выровненное по телу;
- остальные ряды (обрушение — сдвигом 1-го кадра целиком, WHOLE_ROWS): каждый кадр сдвигается на целые px так, чтобы основание (нижние BASE_SHARE силуэта) легло на
  основание 1-го кадра стойки (было: выстрел ±1 px через кадр, попадание до 2 px).
tone: тени — как у грунта и готики поля (у пакета нижние 10% яркости 0.067 против 0.012–0.016 — крепость
  плоская, «в дымке»): яркость v → ((v − black) / (1 − black))^gamma, насыщенность ×sat (огни и золото — тоже);
  прозрачность не меняется. Запускать после tools/sm_grade.py.
Порядок для Космодесанта (10.11.2026): citadel_frames_fit.py (эталон idle) → lock → sm_grade.py → tone.
"""
import sys

import numpy as np
from PIL import Image

# Что в стойке живое (берётся из своего кадра), по расе (--live): тон, насыщенность и яркость выше порогов, область
# (выше строки top, правее left), закрытие close (подкова в полотнище), расширение grow (ореол огня), тело для
# выравнивания — ниже body_from
LIVE = {
    # Космодесант: полотнище флага над крышей (синий, правее древка)
    "sm": {"hue": (0.53, 0.72), "sat": 0.35, "val": 0.0, "top": 75, "left": 108, "close": 3, "grow": 0, "body_from": 90},
    # Хаос (пакет 10.11.2026): фиолетовые огни варпа на жаровнях и в окнах — по всей крепости
    "chaos": {"hue": (0.70, 0.95), "sat": 0.3, "val": 0.3, "top": 10000, "left": 0, "close": 2, "grow": 1, "body_from": 0,
              # body: ряд → что ещё своё, кроме огней: "box" (x0, y0, x1, y1) на кадрах "frames" (все — None),
              # "outside" — всё вне силуэта стойки (дым, искры над крепостью)
              "rows": {1: {"box": (140, 140, 195, 236), "frames": [0, 1, 2]},   # выстрел: ворота горят на зарядке
                       2: {"box": (150, 0, 272, 140), "frames": None, "outside": True}}},   # попадание: удар сверху справа
}
LIVE_CFG = LIVE["sm"]
BASE_SHARE = 0.35      # основание для выравнивания остальных рядов — нижняя доля силуэта
SHIFT = 4              # поиск сдвига, ± px
ALPHA = 128
LIVE_NEAR = 6          # body: огонь ряда берётся не дальше стольких px от огней стойки
WHOLE_ROWS = {3}       # обрушение: основание расползается — сдвиг 1-го кадра на весь ряд (движение внутри ряда — как есть)


def dilate(m, r):
    out = m.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            out |= np.roll(np.roll(m, dy, 0), dx, 1)
    return out


def erode(m, r):
    return ~dilate(~m, r)


def best_shift(mask, ref):
    best = (-1.0, 0, 0)
    for dy in range(-SHIFT, SHIFT + 1):
        for dx in range(-SHIFT, SHIFT + 1):
            sh = np.roll(np.roll(mask, dy, 0), dx, 1)
            iou = (sh & ref).sum() / max((sh | ref).sum(), 1)
            if iou > best[0]:
                best = (iou, dx, dy)
    return best[1], best[2]


def shifted(frame, dx, dy):
    out = np.zeros_like(frame)
    h, w = frame.shape[:2]
    ys = slice(max(dy, 0), h + min(dy, 0))
    yd = slice(max(-dy, 0), h + min(-dy, 0))
    xs = slice(max(dx, 0), w + min(dx, 0))
    xd = slice(max(-dx, 0), w + min(-dx, 0))
    out[ys, xs] = frame[yd, xd]
    return out


def flag_mask(frame):
    """Живая часть стойки (LIVE_CFG): флаг Космодесанта, огни варпа Хаоса."""
    cfg = LIVE_CFG
    hsv = np.array(Image.fromarray(frame[..., :3]).convert("HSV")).astype(float) / 255.0
    m = (frame[..., 3] > ALPHA) & (hsv[..., 1] > cfg["sat"]) & (hsv[..., 2] > cfg["val"])         & (hsv[..., 0] > cfg["hue"][0]) & (hsv[..., 0] < cfg["hue"][1])
    m[cfg["top"]:] = False
    m[:, :cfg["left"]] = False
    if cfg["close"]:
        m = erode(dilate(m, cfg["close"]), cfg["close"])
    if cfg["grow"]:
        m = dilate(m, cfg["grow"])
    m &= frame[..., 3] > 0
    m[cfg["top"]:] = False
    m[:, :cfg["left"]] = False
    return m


def base_mask(frame):
    a = frame[..., 3] > ALPHA
    ys = np.nonzero(a.any(1))[0]
    if len(ys) == 0:
        return a
    top, bottom = ys.min(), ys.max()
    a[: bottom - int((bottom - top) * BASE_SHARE)] = False
    return a


def lock(src, dst, fw, fh):
    sheet = np.array(Image.open(src).convert("RGBA"))
    rows, cols = sheet.shape[0] // fh, sheet.shape[1] // fw
    cell = lambda r, c: sheet[r * fh:(r + 1) * fh, c * fw:(c + 1) * fw]
    ref = cell(0, 0).copy()
    body_ref = ref[..., 3] > ALPHA
    body_ref[:LIVE_CFG["body_from"]] = False
    ref_flag = flag_mask(ref)
    base_ref = base_mask(ref)
    out = np.zeros_like(sheet)
    for c in range(cols):
        f = cell(0, c)
        if f[..., 3].max() == 0:
            continue
        body = f[..., 3] > ALPHA
        body[:LIVE_CFG["body_from"]] = False
        dx, dy = best_shift(body, body_ref)
        f = shifted(f, dx, dy)
        fm = flag_mask(f)
        res = ref.copy()
        # флаг кадра 0 снять: под ним — то, что в своём кадре не флаг (шпиль), иначе пусто
        hole = ref_flag & ~fm
        res[hole] = f[hole]
        res[fm] = f[fm]
        out[0:fh, c * fw:(c + 1) * fw] = res
        print("idle %2d: сдвиг (%d, %d), флаг %d px" % (c, dx, dy, fm.sum()))
    for r in range(1, rows):
        row_shift = best_shift(base_mask(cell(r, 0)), base_ref) if r in WHOLE_ROWS else None
        for c in range(cols):
            f = cell(r, c)
            if f[..., 3].max() == 0:
                continue
            dx, dy = row_shift if row_shift else best_shift(base_mask(f), base_ref)
            out[r * fh:(r + 1) * fh, c * fw:(c + 1) * fw] = shifted(f, dx, dy)
            if dx or dy:
                print("ряд %d кадр %2d: сдвиг (%d, %d)" % (r, c, dx, dy))
    Image.fromarray(out).save(dst)


def body(src, dst, fw, fh):
    """Ряды из LIVE_CFG["rows"] (выстрел, попадание): тело — из кадра 0 стойки (художник перерисовал крепость в каждом
    кадре и иначе, чем в стойке: переход стойка → выстрел → стойка скакал), своё — огни (flag_mask) и правило ряда.
    Нарисованный снаряд в тело не попадает (его выпускает игра: Citadel, shot_frame / muzzle темы). Запускать после lock."""
    sheet = np.array(Image.open(src).convert("RGBA"))
    cols = sheet.shape[1] // fw
    ref = sheet[0:fh, 0:fw].copy()
    ref_live = flag_mask(ref)
    near = dilate(ref[..., 3] > 0, 2)
    for r, rule in LIVE_CFG["rows"].items():
        for c in range(cols):
            f = sheet[r * fh:(r + 1) * fh, c * fw:(c + 1) * fw]
            if f[..., 3].max() == 0:
                continue
            live = flag_mask(f) & dilate(ref_live, LIVE_NEAR)   # огни — у жаровен стойки (след снаряда — не огонь)
            extra = np.zeros_like(live)
            if rule.get("frames") is None or c in rule["frames"]:
                x0, y0, x1, y1 = rule["box"]
                extra[y0:y1, x0:x1] = True
                extra &= f[..., 3] > 0
            if rule.get("outside"):
                extra |= (f[..., 3] > 0) & ~near
            res = ref.copy()
            hole = ref_live & ~live
            res[hole] = f[hole]
            if rule.get("frames") is None or c in rule["frames"]:   # в области ряда — кадр целиком (и прозрачное)
                x0, y0, x1, y1 = rule["box"]
                res[y0:y1, x0:x1] = f[y0:y1, x0:x1]
            take = live | extra
            res[take] = f[take]
            sheet[r * fh:(r + 1) * fh, c * fw:(c + 1) * fw] = res
    Image.fromarray(sheet).save(dst)


# --dark-hue H --dark-pull K: тёмные (v < DARK_V) пурпурные (тон в DARK_RANGE) — к тону H на долю K (крепость Хаоса
# 10.11.2026: все тени пурпурно-чёрные, у поля и прежней крепости — бордо); огни варпа светлее — не трогаются
DARK_V = 0.32
DARK_RANGE = (0.78, 0.95)


def tone(src, dst, black=0.05, gamma=1.0, sat=1.0, dark_hue=-1.0, dark_pull=0.0):
    img = Image.open(src).convert("RGBA")
    alpha = np.array(img)[..., 3]
    hsv = np.array(img.convert("RGB").convert("HSV")).astype(float) / 255.0
    h = hsv[..., 0]
    if dark_hue >= 0.0 and dark_pull > 0.0:
        m = (hsv[..., 2] < DARK_V) & (h > DARK_RANGE[0]) & (h < DARK_RANGE[1])
        d = ((dark_hue - h + 0.5) % 1.0) - 0.5
        h = np.where(m, (h + d * dark_pull) % 1.0, h)
    v = np.clip((hsv[..., 2] - black) / (1.0 - black), 0.0, 1.0) ** gamma
    s = np.clip(hsv[..., 1] * sat, 0.0, 1.0)
    out = np.stack([h, s, v], -1)
    res = Image.merge("HSV", [Image.fromarray((out[..., i] * 255 + 0.5).astype(np.uint8)) for i in range(3)]).convert("RGBA")
    res.putalpha(Image.fromarray(alpha))
    res.save(dst)
    dense = alpha > 200
    print("яркость: средняя %.3f, нижние 10%% %.3f" % (v[dense].mean(), np.percentile(v[dense], 10)))


if __name__ == "__main__":
    cmd, args = sys.argv[1], sys.argv[2:]
    if "--live" in args:   # чья стойка: sm (по умолчанию) / chaos
        i = args.index("--live")
        LIVE_CFG = LIVE[args[i + 1]]
        args = args[:i] + args[i + 2:]
    if cmd == "lock":
        lock(args[0], args[1], int(args[2]), int(args[3]))
    elif cmd == "body":
        body(args[0], args[1], int(args[2]), int(args[3]))
    else:
        opts = {"black": 0.05, "gamma": 1.0, "sat": 1.0, "dark-hue": -1.0, "dark-pull": 0.0}
        rest = []
        it = iter(args)
        for a in it:
            if a.startswith("--"):
                opts[a[2:]] = float(next(it))
            else:
                rest.append(a)
        tone(rest[0], rest[1], black=opts["black"], gamma=opts["gamma"], sat=opts["sat"], dark_hue=opts["dark-hue"],
             dark_pull=opts["dark-pull"])
