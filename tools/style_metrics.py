"""Цифры к стилизации «до / после» (скилл game-stylization): яркость, насыщенность, засветы, разница снимков.
Работает по PNG-снимкам (tests/capture_style.gd) и по любым картинкам, Godot не нужен.

  python tools/style_metrics.py a.png [b.png …]                 — метрики каждого снимка
  python tools/style_metrics.py a.png --region x,y,w,h          — только прямоугольник (px картинки)
  python tools/style_metrics.py --diff до.png после.png         — что изменилось: средняя разница, доля изменённых
                                                                  пикселей, рамка изменений, сдвиг яркости / насыщенности
  python tools/style_metrics.py --contrast a.png --fg x,y,w,h --bg x,y,w,h   — контраст объекта и фона (по яркости)

Яркость — относительная (Rec.709, линейно по sRGB-значению 0..1), как «яркость» в заметках проекта
(грунт Хаоса ≈ 21/255 = 0.08; бойцы Хаоса ≈ 30/255). «Засвет» — доля пикселей ярче 0.8 (у кадров юнитов потолок 7%,
tests/test_unit_frames.gd). Прозрачные пиксели (альфа < 16) не считаются: для PNG с альфой меряется только рисунок.
"""
import argparse
import sys

import numpy as np
from PIL import Image

CHANGED = 12          # разница канала (из 255) — пиксель считается изменившимся
BRIGHT = 0.8


def load(path, region=None):
    img = Image.open(path).convert("RGBA")
    if region:
        x, y, w, h = region
        img = img.crop((x, y, x + w, y + h))
    return np.asarray(img).astype(np.float32)


def parse_region(s):
    if not s:
        return None
    x, y, w, h = (int(v) for v in s.split(","))
    return x, y, w, h


def lum_sat(a):
    rgb = a[..., :3] / 255.0
    mask = a[..., 3] >= 16
    lum = 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]
    mx, mn = rgb.max(-1), rgb.min(-1)
    sat = np.where(mx > 1e-6, (mx - mn) / np.maximum(mx, 1e-6), 0.0)
    return lum, sat, mask


def metrics(a):
    lum, sat, mask = lum_sat(a)
    if mask.sum() == 0:
        return None
    l, s = lum[mask], sat[mask]
    return {"px": int(mask.sum()), "lum_mean": float(l.mean()), "lum_p5": float(np.percentile(l, 5)),
            "lum_p50": float(np.percentile(l, 50)), "lum_p95": float(np.percentile(l, 95)),
            "contrast": float(np.percentile(l, 95) - np.percentile(l, 5)), "sat_mean": float(s.mean()),
            "bright_share": float((l > BRIGHT).mean())}


def show(name, m):
    if m is None:
        print("%s: пусто (всё прозрачное)" % name)
        return
    print("%s: яркость сред. %.3f (%.0f/255)  p5 %.3f  p50 %.3f  p95 %.3f  размах p95−p5 %.3f | насыщенность %.3f | засвет >%.1f: %.1f%%"
          % (name, m["lum_mean"], m["lum_mean"] * 255, m["lum_p5"], m["lum_p50"], m["lum_p95"], m["contrast"],
             m["sat_mean"], BRIGHT, m["bright_share"] * 100))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("images", nargs="*")
    ap.add_argument("--region")
    ap.add_argument("--diff", nargs=2, metavar=("ДО", "ПОСЛЕ"))
    ap.add_argument("--contrast")
    ap.add_argument("--fg")
    ap.add_argument("--bg")
    a = ap.parse_args()
    if a.diff:
        x = load(a.diff[0], parse_region(a.region))
        y = load(a.diff[1], parse_region(a.region))
        if x.shape != y.shape:
            sys.exit("снимки разного размера: %s и %s — снимай с тем же окном" % (x.shape[:2], y.shape[:2]))
        d = np.abs(x[..., :3] - y[..., :3]).max(-1)
        ch = d >= CHANGED
        print("разница: средняя %.2f/255, изменилось %.1f%% пикселей (порог %d)" % (d.mean(), ch.mean() * 100, CHANGED))
        if ch.any():
            ys, xs = np.nonzero(ch)
            print("рамка изменений: x %d..%d, y %d..%d" % (xs.min(), xs.max(), ys.min(), ys.max()))
        mx, my = metrics(x), metrics(y)
        show("до   ", mx)
        show("после", my)
        if mx and my:
            print("сдвиг: яркость %+.3f (%+.0f/255), насыщенность %+.3f, засвет %+.1f п.п., размах %+.3f" % (
                my["lum_mean"] - mx["lum_mean"], (my["lum_mean"] - mx["lum_mean"]) * 255,
                my["sat_mean"] - mx["sat_mean"], (my["bright_share"] - mx["bright_share"]) * 100,
                my["contrast"] - mx["contrast"]))
        return
    if a.contrast:
        if not (a.fg and a.bg):
            sys.exit("--contrast требует --fg и --bg")
        img = a.contrast
        f = metrics(load(img, parse_region(a.fg)))
        b = metrics(load(img, parse_region(a.bg)))
        show("объект", f)
        show("фон   ", b)
        if f and b:
            lf, lb = f["lum_p50"], b["lum_p50"]
            print("контраст объект / фон по медиане яркости: %.3f vs %.3f — разница %+.3f, отношение %.2f" % (
                lf, lb, lf - lb, (lf + 0.05) / (lb + 0.05)))
        return
    if not a.images:
        ap.error("нужен снимок, --diff или --contrast")
    for p in a.images:
        show(p, metrics(load(p, parse_region(a.region))))


if __name__ == "__main__":
    main()
