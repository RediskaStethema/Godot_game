"""Уход от канона 40K в картинках интерфейса и цитадели (решение пользователя 17.11.2026: «нарисовать кодом заглушки»;
правила замен — AGENT_PROMPT_asset_cleanup.md: двуглавый орёл / аквила → масляная лампа с двумя огнями, буква-знак ордена →
знак без букв). Заглушки пиксель-артом кодом, потом их может заменить художник:
  - assets/ui/difficulty/1,2,3,4,6.png — значки сложности: наплечник с шевроном (1), аквилы (2, 3, 6), шлем (4) → свечка, лампа
    с 1 / 2 / 3 огнями, лампа в нимбе, лампа в лавровом венке (5 — меч в венке, 7 — череп с искрами остаются);
  - assets/ui/frame_eagle.png — аквила над рамкой окон → лампа с двумя огнями на латунных завитках;
  - баннер «ПОБЕДА» (assets/ui/banners/victory.png) НЕ тронут: крылатый череп в кольце — часть орнамента всей рамки (перья на всю
    ширину); заменить может только художник (UI_NEEDED.txt);
  - assets/sprites/props/space_marines/citadel/sheet.png — цитадель Космодесанта: аквила над дверью и значок над ней → лампа,
    буква «U» на флагах (флаг на башне, три знамени на стенах) → маленькая лампа; ряды стойки / выстрела / попадания (обрушение
    не трогается).
Исходники — assets/source_sheets/canon_cleanup_orig_2026-11-17/ (повторный прогон — от них); `--restore` возвращает.

  PYTHONIOENCODING=utf-8 python tools/canon_cleanup.py [--restore]
затем godot --headless --path . --import
"""
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
UI = ROOT / "assets/ui"
CITADEL = ROOT / "assets/sprites/props/space_marines/citadel/sheet.png"
BACKUP = ROOT / "assets/source_sheets/canon_cleanup_orig_2026-11-17"

OUT = (26, 15, 8)          # тёмный контур
BRASS_D = (112, 68, 26)
BRASS = (178, 124, 44)
BRASS_L = (234, 184, 86)
FLAME_O = (236, 112, 28)
FLAME_Y = (252, 196, 70)
FLAME_W = (255, 244, 190)
WAX = (214, 200, 168)
WAX_D = (150, 136, 112)
BANNER_MAX_Y = 171          # знамёна и флаг цитадели выше этой строки кадра; ниже — основание из камня


# ---------------------------------------------------------------- рисование
def outline(im: Image.Image, color=OUT) -> Image.Image:
    """тёмный контур в 1 px вокруг силуэта"""
    a = im.split()[3]
    grown = a.filter(ImageFilter.MaxFilter(3))
    base = Image.new("RGBA", im.size, color + (0,))
    base.putalpha(grown)
    base.alpha_composite(im)
    return base


def flame(d: ImageDraw.ImageDraw, x: int, y: int, h: int = 14, w: int = 6):
    """язычок пламени: основание в (x, y), вершина на h выше"""
    pts = [(x, y - h), (x + w // 2 + 1, y - h // 2), (x + w // 2, y - 1), (x, y), (x - w // 2, y - 1), (x - w // 2 - 1, y - h // 2)]
    d.polygon(pts, fill=FLAME_O)
    inner = [(x, y - h + 4), (x + w // 3 + 1, y - h // 2), (x + w // 4, y - 1), (x, y), (x - w // 4, y - 1), (x - w // 3 - 1, y - h // 2)]
    d.polygon(inner, fill=FLAME_Y)
    d.polygon([(x, y - h // 2), (x + 1, y - 2), (x - 1, y - 2)], fill=FLAME_W)


def lamp(size=64, flames=2, halo=False) -> Image.Image:
    """масляная лампа (латунная чаша с носиком и ручкой), flames огней над чашей"""
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx = size // 2
    top = int(size * 0.60)
    if halo:
        d.ellipse((4, 4, size - 5, size - 5), outline=BRASS, width=2)
        d.ellipse((7, 7, size - 8, size - 8), outline=BRASS_D, width=1)
    # огни
    xs = {1: [cx], 2: [cx - 8, cx + 8], 3: [cx - 12, cx, cx + 12]}[flames]
    for i, x in enumerate(xs):
        flame(d, x, top - 2, h=16 if (flames == 3 and i == 1) or flames < 3 else 13)
    # чаша
    d.polygon([(cx - 20, top), (cx + 20, top), (cx + 17, top + 9), (cx + 9, top + 14), (cx - 9, top + 14), (cx - 17, top + 9)], fill=BRASS)
    d.polygon([(cx - 17, top + 9), (cx + 17, top + 9), (cx + 9, top + 14), (cx - 9, top + 14)], fill=BRASS_D)
    d.line((cx - 20, top, cx + 20, top), fill=BRASS_L, width=1)
    d.line((cx - 15, top + 3, cx + 12, top + 3), fill=BRASS_L, width=1)
    # носик справа, ручка слева
    d.polygon([(cx + 20, top), (cx + 28, top - 4), (cx + 26, top + 3), (cx + 19, top + 6)], fill=BRASS)
    d.arc((cx - 31, top - 2, cx - 17, top + 12), 90, 270, fill=BRASS, width=2)
    # ножка и основание
    d.rectangle((cx - 3, top + 14, cx + 3, top + 18), fill=BRASS_D)
    d.polygon([(cx - 12, top + 22), (cx + 12, top + 22), (cx + 8, top + 18), (cx - 8, top + 18)], fill=BRASS)
    return outline(im)


def candle(size=64) -> Image.Image:
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx = size // 2
    d.rectangle((cx - 7, 34, cx + 7, 52), fill=WAX)
    d.rectangle((cx + 3, 34, cx + 7, 52), fill=WAX_D)
    d.polygon([(cx - 7, 34), (cx + 7, 34), (cx + 5, 31), (cx - 5, 31)], fill=WAX)
    d.line((cx, 31, cx, 28), fill=OUT, width=1)
    flame(d, cx, 28, h=14, w=6)
    d.polygon([(cx - 14, 56), (cx + 14, 56), (cx + 10, 52), (cx - 10, 52)], fill=BRASS)
    d.polygon([(cx - 14, 56), (cx + 14, 56), (cx + 12, 58), (cx - 12, 58)], fill=BRASS_D)
    return outline(im)


def up(im: Image.Image, k: int) -> Image.Image:
    return im.resize((im.width * k, im.height * k), Image.NEAREST)


def difficulty_icons():
    out = {}
    out[1] = up(candle(), 2)
    out[2] = up(lamp(flames=1), 2)
    out[4] = up(lamp(flames=2, halo=True), 2)
    # 3 — лампа с двумя огнями; 6 — три огня в лавровом венке из значка 5
    out[3] = up(lamp(flames=2), 2)
    wreath = Image.open(BACKUP / "difficulty" / "5.png").convert("RGBA")
    clean = wreath.copy()
    px = np.array(clean)
    px[8:100, 52:78, 3] = 0          # меч в центре венка
    px[100:128, 58:70, 3] = 0        # острие меча между лентами
    clean = Image.fromarray(px)
    base = clean.copy()
    l3 = up(lamp(size=64, flames=3), 2)
    base.alpha_composite(l3.resize((88, 88), Image.NEAREST), (20, 14))
    out[6] = base
    return out


def frame_eagle() -> Image.Image:
    """152 × 88: лампа с двумя огнями на латунных завитках (вместо аквилы над рамкой окна)"""
    w, h = 152, 88
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx = w // 2
    # завитки: две симметричные дуги от основания лампы к краям
    for sx in (-1, 1):
        d.arc((cx + sx * 8 - (40 if sx < 0 else 0), 46, cx + sx * 8 + (40 if sx > 0 else 0), 78), 200 if sx > 0 else 270, 340 if sx > 0 else 350, fill=BRASS, width=3)
        d.line((cx + sx * 24, 68, cx + sx * 66, 66), fill=BRASS, width=3)
        d.line((cx + sx * 24, 66, cx + sx * 66, 64), fill=BRASS_L, width=1)
        d.ellipse((cx + sx * 66 - 3, 62, cx + sx * 66 + 3, 70), fill=BRASS_L)
    im = outline(im)
    lp = lamp(size=64, flames=2).resize((96, 96), Image.NEAREST)   # 1.5×
    im.alpha_composite(lp, (cx - 48, -14))
    return im


def tiny_lamp(flames=1) -> Image.Image:
    """маленькая лампа 9 × 10 px для знамён цитадели"""
    im = Image.new("RGBA", (9, 10), (0, 0, 0, 0))
    px = im.load()
    for x, y in [(4, 0), (3, 1), (4, 1), (4, 2), (3, 2), (5, 2), (4, 3)]:
        px[x, y] = FLAME_Y if y > 0 else FLAME_O
    px[4, 2] = FLAME_W
    for x in range(1, 8):
        px[x, 4] = BRASS_L
    for x in range(1, 8):
        px[x, 5] = BRASS
    for x in range(2, 7):
        px[x, 6] = BRASS_D
    for x in range(3, 6):
        px[x, 7] = BRASS_D
    px[0, 4] = BRASS
    px[8, 3] = BRASS
    for x in range(2, 7):
        px[x, 8] = BRASS
    return im


# ---------------------------------------------------------------- файлы
def stash(path: Path, rel: str):
    dst = BACKUP / rel
    if not dst.exists():
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, dst)
    return dst


def components(mask: np.ndarray):
    h, w = mask.shape
    seen = np.zeros_like(mask, bool)
    out = []
    for y0, x0 in zip(*np.nonzero(mask)):
        if seen[y0, x0]:
            continue
        st = [(y0, x0)]
        seen[y0, x0] = True
        pts = []
        while st:
            y, x = st.pop()
            pts.append((y, x))
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < h and 0 <= xx < w and mask[yy, xx] and not seen[yy, xx]:
                        seen[yy, xx] = True
                        st.append((yy, xx))
        out.append(pts)
    return out


def hsv_of(a: np.ndarray):
    rgb = a[..., :3] / 255.0
    mx, mn = rgb.max(-1), rgb.min(-1)
    sat = np.where(mx > 1e-6, (mx - mn) / np.maximum(mx, 1e-6), 0.0)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    hue = np.zeros_like(mx)
    d = np.maximum(mx - mn, 1e-6)
    hue = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) / 6.0
    return hue, sat, mx


def replace_patch(frame: np.ndarray, region, new: Image.Image, center, fill_color=None):
    """стереть золото в region (x0, y0, x1, y1) заливкой цветом окружения и положить new (центр — center)"""
    x0, y0, x1, y1 = region
    sub = frame[y0:y1, x0:x1]
    hue, sat, val = hsv_of(sub.astype(np.float32))
    gold = (sub[..., 3] > 40) & (hue > 0.06) & (hue < 0.16) & (sat > 0.4)
    gold = np.array(Image.fromarray((gold * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3))) > 0   # с кромкой
    if fill_color is None:
        ring = (sub[..., 3] > 40) & ~gold
        fill_color = np.median(sub[ring][:, :3], axis=0) if ring.sum() else np.array([30, 36, 48])
    sub[gold, :3] = fill_color
    sub[gold, 3] = 255
    tmp = Image.fromarray(frame)
    tmp.alpha_composite(new, (int(center[0] - new.width / 2), int(center[1] - new.height / 2)))
    return np.array(tmp)


def process_citadel():
    src = stash(CITADEL, "citadel/sheet.png")
    im = Image.open(src).convert("RGBA")
    fw, fh = 211, 219
    cols, rows = im.width // fw, im.height // fh
    arr = np.array(im)
    changed = 0
    for r in range(min(3, rows)):             # idle, attack, hit; обрушение (последний ряд) не трогаем
        for c in range(cols):
            f = arr[r * fh:(r + 1) * fh, c * fw:(c + 1) * fw].copy()
            if f[..., 3].max() < 40:
                continue
            # значок под зубцами и аквила над дверью — золото в этих рамках → одна лампа с двумя огнями
            f = replace_patch(f, (66, 92, 130, 140), lamp(size=40, flames=2).resize((26, 26), Image.NEAREST), (98, 120))
            # «U» на флагах: светлые малонасыщенные пятна внутри тёмно-синего полотна (кромка пятна сглажена — пороги мягкие;
            # от каменной кладки отличает кольцо вокруг: тёмное и синее)
            hue, sat, val = hsv_of(f.astype(np.float32))
            pale = (f[..., 3] > 200) & (sat < 0.42) & (val > 0.42)
            for pts in components(pale):
                ys = [p[0] for p in pts]
                xs = [p[1] for p in pts]
                bw, bh = max(xs) - min(xs) + 1, max(ys) - min(ys) + 1
                if not (4 <= bw <= 18 and 5 <= bh <= 18 and len(pts) >= 12) or max(ys) >= BANNER_MAX_Y:
                    continue   # ниже BANNER_MAX_Y — камни у основания, не знамёна
                x0, x1, y0, y1 = max(min(xs) - 3, 0), min(max(xs) + 4, fw), max(min(ys) - 3, 0), min(max(ys) + 4, fh)
                zone = (~pale[y0:y1, x0:x1]) & (f[y0:y1, x0:x1, 3] > 200)
                if zone.sum() < 20:
                    continue
                ring_val = val[y0:y1, x0:x1][zone]
                ring_sat = sat[y0:y1, x0:x1][zone]
                if ring_val.mean() > 0.4 or ring_sat.mean() < 0.3:
                    continue   # не полотно (камень / золото)
                cloth = np.median(f[y0:y1, x0:x1][zone][:, :3], axis=0)
                for (py, px) in pts:
                    f[py, px, :3] = cloth
                # соседние светлые пиксели кромки буквы (тоньше порога) — тоже полотном
                cx, cy = (min(xs) + max(xs)) // 2, (min(ys) + max(ys)) // 2
                edge = (f[cy - 8:cy + 8, cx - 8:cx + 8, 3] > 200) & (val[cy - 8:cy + 8, cx - 8:cx + 8] > 0.3) & (sat[cy - 8:cy + 8, cx - 8:cx + 8] < 0.5)
                patch = f[cy - 8:cy + 8, cx - 8:cx + 8]
                patch[edge, :3] = cloth
                tmp = Image.fromarray(f)
                tmp.alpha_composite(tiny_lamp(), (cx - 4, cy - 5))
                f = np.array(tmp)
            arr[r * fh:(r + 1) * fh, c * fw:(c + 1) * fw] = f
            changed += 1
    Image.fromarray(arr).save(CITADEL)
    print("цитадель: обработано кадров", changed)


def main():
    if "--restore" in sys.argv:
        for rel, dst in [("difficulty/%d.png" % i, UI / "difficulty" / ("%d.png" % i)) for i in (1, 2, 3, 4, 5, 6, 7)] + \
                [("frame_eagle.png", UI / "frame_eagle.png"), ("banners/victory.png", UI / "banners/victory.png"),
                 ("citadel/sheet.png", CITADEL)]:   # victory.png — на случай прежних прогонов
            s = BACKUP / rel
            if s.exists():
                shutil.copy2(s, dst)
        print("исходные файлы возвращены")
        return
    for i in (5,):
        stash(UI / "difficulty" / ("%d.png" % i), "difficulty/%d.png" % i)
    for i in (1, 2, 3, 4, 6):
        stash(UI / "difficulty" / ("%d.png" % i), "difficulty/%d.png" % i)
    stash(UI / "frame_eagle.png", "frame_eagle.png")
    for i, im in difficulty_icons().items():
        im.save(UI / "difficulty" / ("%d.png" % i))
    frame_eagle().save(UI / "frame_eagle.png")
    print("значки сложности и аквила окон заменены")
    process_citadel()


if __name__ == "__main__":
    main()
