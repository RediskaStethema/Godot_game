"""Грунт и декор за стеной поля: сборка из листов Layer (23.11.2026, решение пользователя: «так очень неплохо» + анимация).

Читает `assets/source_sheets/surround_v1_2026-11-23/{ground_*.png, cut/<раса>/NN.png}` (cut — `tools/surround_slice.py`),
пишет в `assets/sprites/surround/<раса>/`:
  ground.png          — грунт: ÷GROUND_DIV, шов сшит (сдвиг на полразмера + мягкое смешивание), яркость к GROUND_LUM
  prop_NN.png         — предмет: ÷PROP_DIV, ореол снят порогом альфы, палитра PALETTE цветов, яркость к PROP_LUM
  prop_NN_anim.png    — лента кадров (по ряду в строке) для предметов с анимацией кодом:
                        Хаос 00 — кровь по жилам дерева и капли; Хаос 04 — один глаз черепа тлеет;
                        Космодесант 00 — свет в дупле; Космодесант 05 — куст качается
  (контактные листы — source_sheets/surround_v1_2026-11-23/preview)
Layer-кадры для анимации не берутся (модель перерисовывает предмет в каждом кадре — «кипение»): анимация строится из утверждённого
спрайта. Повтор безопасен: всё пишется заново от исходников.
  python tools/surround_build.py [chaos|space_marines]
"""
import math
import sys
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets/source_sheets/surround_v1_2026-11-23"
OUT = ROOT / "assets/sprites/surround"
PREV = SRC / "preview"          # контактные листы для проверки (в source_sheets — Godot не импортирует)
RACES = {"chaos": "chaos", "space_marines": "marines"}   # id расы → суффикс листов Layer
PROP_DIV = 6
GROUND_DIV = 5
PALETTE = 24
PROP_LUM = {"chaos": 0.13, "space_marines": 0.17}      # средняя яркость предмета (23.11.2026: 0.095 / 0.135 → 0.13 / 0.17 — на грунте, подогнанном под внутренний, деревья не читались)
# Грунт за стеной подгоняется к ВНУТРЕННЕМУ (решение пользователя 23.11.2026: «грунт за стеной отличается по цвету и насыщенности
# от внутреннего, у обеих рас»): средний цвет плиты грунта темы × FLOOR_TINT × floor_brightness, пропущенный через floor_calm
# (внутри пол рисуется с ним, снаружи — нет); разброс узора — как у спокойного грунта (CALM_CONTRAST).
INNER = {   # раса: (плита грунта темы, floor_brightness, опора floor_calm)
    "chaos": ("assets/sprites/tiles/chaos/red_terrain.png", 1.1, 0.045),
    "space_marines": ("assets/sprites/tiles/space_marines/terrain.png", 1.0, 0.07),
}
FLOOR_TINT = (0.72, 0.70, 0.68)   # IsoGridRenderer.FLOOR_TINT
CALM_CONTRAST = 0.6               # IsoGridRenderer.FLOOR_CALM
PATTERN_KEEP = 0.65               # доля разброса узора, что оставляем (картинка Layer контрастнее плиты)
ANIM_FPS = {"chaos": {0: 7, 4: 8}, "space_marines": {0: 7, 5: 7}}
ANIM_FRAMES = {"chaos": {0: 12, 4: 8}, "space_marines": {0: 8, 5: 8}}


def lum(a: np.ndarray) -> np.ndarray:
    return 0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]


def box_down(img: Image.Image, div: int) -> Image.Image:
    """÷div усреднением по блоку с весом альфы (края не темнеют)."""
    a = np.array(img.convert("RGBA")).astype(np.float64)
    h, w = a.shape[0] // div * div, a.shape[1] // div * div
    a = a[:h, :w]
    al = a[..., 3:4] / 255.0
    pm = a[..., :3] * al
    pm = pm.reshape(h // div, div, w // div, div, 3).mean(axis=(1, 3))
    alm = al.reshape(h // div, div, w // div, div, 1).mean(axis=(1, 3))
    rgb = np.where(alm > 0.01, pm / np.maximum(alm, 1e-6), 0)
    out = np.concatenate([rgb, alm * 255.0], axis=-1)
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")


def scale_lum(a: np.ndarray, target: float, mask: np.ndarray) -> np.ndarray:
    """Яркость всех цветных пикселей множителем так, чтобы средняя по маске стала target."""
    f = a[..., :3].astype(np.float64) / 255.0
    cur = lum(f)[mask].mean()
    k = target / max(cur, 1e-4)
    f = np.clip(f * k, 0, 1)
    out = a.copy()
    out[..., :3] = (f * 255.0 + 0.5).astype(np.uint8)
    return out


def make_prop(path: Path, race: str) -> np.ndarray:
    img = box_down(Image.open(path), PROP_DIV)
    a = np.array(img)
    solid = a[..., 3] >= 128
    a[..., 3] = np.where(solid, 255, 0)
    rgb = Image.fromarray(a[..., :3], "RGB")
    q = rgb.quantize(colors=PALETTE, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    qa = np.array(q)
    # палитра считалась по всему кадру (в т.ч. по чёрному фону) — для предмета берём только его пиксели
    a[..., :3] = np.where(solid[..., None], qa, 0)
    ys, xs = np.where(solid)
    a = a[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    solid = a[..., 3] > 0
    return a


# -------------------------------------------------- анимации (кодом, на сетке пикселя арта)

def pad(a: np.ndarray, left: int, right: int, top: int, bottom: int) -> np.ndarray:
    return np.pad(a, ((top, bottom), (left, right), (0, 0)))


def strip(frames: list) -> np.ndarray:
    return np.concatenate(frames, axis=1)


def blend(dst: np.ndarray, x: int, y: int, col, alpha: float) -> None:
    if 0 <= y < dst.shape[0] and 0 <= x < dst.shape[1] and alpha > 0:
        c = dst[y, x]
        t = min(1.0, alpha)
        if c[3] == 0:
            dst[y, x] = [col[0], col[1], col[2], int(255 * t)]
        else:
            dst[y, x, :3] = (c[:3] * (1 - t) + np.array(col) * t).astype(np.uint8)


def anim_blood_tree(base: np.ndarray, n: int) -> list:
    """Хаос, большое дерево: по красным жилам бежит волна яркости вниз, с концов жил срываются капли."""
    h, w = base.shape[:2]
    r, g, b = base[..., 0].astype(int), base[..., 1].astype(int), base[..., 2].astype(int)
    vein = (base[..., 3] > 0) & (r > 110) & (r > g * 2.2) & (r > b * 1.8)
    ys, xs = np.where(vein)
    # концы жил: нет жилы ниже в пределах 3 px; берём три самых разнесённых по x, не выше трети роста
    ends = [(y, x) for y, x in zip(ys, xs) if y > h * 0.3 and not vein[y + 1:y + 4, max(0, x - 1):x + 2].any()]
    ends.sort(key=lambda p: p[1])
    picks = []
    for y, x in ends:
        if all(abs(x - px) > w * 0.12 for _, px in picks):
            picks.append((y, x))
        if len(picks) == 3:
            break
    frames = []
    period = 13.0
    fall = 11
    for i in range(n):
        f = pad(base, 0, 0, 0, fall + 2)
        for y, x in zip(ys, xs):
            ph = math.sin(2 * math.pi * (y / period - i / n))
            k = 0.62 + 0.55 * (0.5 + 0.5 * ph)
            f[y, x, :3] = np.clip(base[y, x, :3].astype(np.float64) * k + (np.array([60, 0, 0]) * max(0.0, ph - 0.4)), 0, 255).astype(np.uint8)
        for d, (y0, x0) in enumerate(picks):
            t = (i / n + d / 3.0) % 1.0      # у каждой капли свой сдвиг по циклу
            if t < 0.15:
                continue                    # набухает на кончике жилы — только яркий пиксель
            dy = int((t - 0.15) / 0.85 * fall) + 1
            a_ = 1.0 - max(0.0, (t - 0.7) / 0.3)
            for ddx in (0, 1):
                blend(f, x0 + ddx, y0 + dy, (225, 25, 45), a_)
                blend(f, x0 + ddx, y0 + dy - 1, (170, 12, 32), a_ * 0.8)
            blend(f, x0, y0 + dy - 2, (120, 8, 24), a_ * 0.6)
        frames.append(f)
    return frames


EYE_SEED = (11, 37)    # (строка, столбец) в спрайте Хаоса 04 (÷6): центр левой глазницы, обращённой к зрителю


def find_eye(base: np.ndarray) -> list:
    """Тёмные пиксели глазницы, связные с EYE_SEED (8-связность, яркость < 0.05)."""
    h, w = base.shape[:2]
    l = lum(base[..., :3].astype(np.float64) / 255.0)
    ok = (base[..., 3] > 0) & (l < 0.05)
    y0, x0 = EYE_SEED
    if not ok[y0, x0]:
        # ближайший тёмный пиксель в окне 3 px
        c = [(abs(y - y0) + abs(x - x0), y, x) for y in range(max(0, y0 - 3), y0 + 4) for x in range(max(0, x0 - 3), x0 + 4) if ok[y, x]]
        if not c:
            return []
        _, y0, x0 = min(c)
    seen = {(y0, x0)}
    stack = [(y0, x0)]
    while stack:
        cy, cx = stack.pop()
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                ny, nx = cy + dy, cx + dx
                if 0 <= ny < h and 0 <= nx < w and ok[ny, nx] and (ny, nx) not in seen:
                    seen.add((ny, nx))
                    stack.append((ny, nx))
    return list(seen) if len(seen) < 80 else []     # слишком большое — залило тень вокруг, а не глазницу


def anim_skull_eye(base: np.ndarray, n: int) -> list:
    """Хаос, череп: левая глазница (обращённая к зрителю) тлеет красным и дышит; вторая — тёмная."""
    eye = find_eye(base)
    if not eye:
        print("  ! глазница черепа не найдена")
        return [base.copy() for _ in range(n)]
    print("  глазница:", len(eye), "px, центр", np.mean([q[0] for q in eye]).round(1), np.mean([q[1] for q in eye]).round(1))
    pulse = [0.45, 0.55, 0.7, 0.9, 1.0, 0.85, 0.65, 0.5]
    frames = []
    for i in range(n):
        f = base.copy()
        k = pulse[i % len(pulse)]
        for y, x in eye:
            core = np.array([255, 70, 45]) * k + np.array([60, 0, 0]) * (1 - k)
            f[y, x, :3] = np.clip(core, 0, 255).astype(np.uint8)
        # ореол на кости: ближайшие светлые пиксели краснеют
        ex = set(eye)
        for y, x in eye:
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    p = (y + dy, x + dx)
                    if p in ex or not (0 <= p[0] < f.shape[0] and 0 <= p[1] < f.shape[1]) or f[p[0], p[1], 3] == 0:
                        continue
                    f[p[0], p[1], :3] = np.clip(f[p[0], p[1], :3].astype(np.float64) * (1 - 0.35 * k) + np.array([200, 30, 30]) * 0.35 * k, 0, 255).astype(np.uint8)
        frames.append(f)
    return frames


def find_hollow(base: np.ndarray) -> list:
    """Дупло: самое тёмное связное пятно в нижней половине ствола (по центру спрайта)."""
    h, w = base.shape[:2]
    l = lum(base[..., :3].astype(np.float64) / 255.0)
    solid = base[..., 3] > 0
    win = np.zeros_like(solid)
    win[int(h * 0.55):int(h * 0.88), int(w * 0.32):int(w * 0.66)] = True
    dark = solid & win & (l < 0.055)
    seen = np.zeros_like(dark)
    best: list = []
    for y, x in zip(*np.where(dark)):
        if seen[y, x]:
            continue
        stack = [(y, x)]
        seen[y, x] = True
        pts = []
        while stack:
            cy, cx = stack.pop()
            pts.append((cy, cx))
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = cy + dy, cx + dx
                    if 0 <= ny < h and 0 <= nx < w and dark[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
        if len(pts) > len(best):
            best = pts
    return best


def anim_hollow(base: np.ndarray, n: int) -> list:
    """Космодесант, большое дерево: в дупле тёплый свет — неровно мерцает, как далёкая лампа."""
    hollow = find_hollow(base)
    if len(hollow) < 8:
        print("  ! дупло не найдено")
        return [base.copy() for _ in range(n)]
    print("  дупло:", len(hollow), "px, центр", np.mean([q[0] for q in hollow]).round(1), np.mean([q[1] for q in hollow]).round(1))
    flick = [0.55, 0.8, 0.65, 1.0, 0.7, 0.9, 0.6, 0.85]
    cy_, cx_ = np.mean([p[0] for p in hollow]), np.mean([p[1] for p in hollow])
    rad = max(math.hypot(p[0] - cy_, (p[1] - cx_) * 0.8) for p in hollow) + 0.5
    frames = []
    for i in range(n):
        f = base.copy()
        k = flick[i % len(flick)]
        for y, x in hollow:
            d = math.hypot(y - cy_, (x - cx_) * 0.8) / rad               # 0 — центр, 1 — край
            glow = max(0.0, 1.0 - d ** 0.9)
            col = np.array([235, 140, 45]) * (0.1 + 0.6 * k) * glow + np.array([40, 18, 8]) * (1 - glow)
            f[y, x, :3] = np.clip(col, 0, 255).astype(np.uint8)
        hs = set(hollow)
        for y, x in hollow:                                        # отсвет на коре у края
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    p = (y + dy, x + dx)
                    if p in hs or not (0 <= p[0] < f.shape[0] and 0 <= p[1] < f.shape[1]) or f[p[0], p[1], 3] == 0:
                        continue
                    f[p[0], p[1], :3] = np.clip(f[p[0], p[1], :3].astype(np.float64) * (1 - 0.4 * k) + np.array([230, 140, 50]) * 0.4 * k, 0, 255).astype(np.uint8)
        frames.append(f)
    return frames


def anim_sway(base: np.ndarray, n: int, amp: float = 3.0) -> list:
    """Космодесант, куст: верх качается, низ стоит (сдвиг строк ~ высота^1.6, шаг — целый пиксель арта)."""
    h, w = base.shape[:2]
    p = int(math.ceil(amp)) + 1
    padded = pad(base, p, p, 0, 0)
    ys = np.where(padded[..., 3].any(axis=1))[0]
    top, bot = ys.min(), ys.max()
    frames = []
    for i in range(n):
        f = np.zeros_like(padded)
        s = math.sin(2 * math.pi * i / n)
        for y in range(padded.shape[0]):
            hh = max(0.0, (bot - y) / max(1, bot - top))
            dx = int(round(amp * (hh ** 1.6) * s))
            f[y] = np.roll(padded[y], dx, axis=0)
        frames.append(f)
    return frames


ANIMS = {
    "chaos": {0: anim_blood_tree, 4: anim_skull_eye},
    "space_marines": {0: anim_hollow, 5: anim_sway},
}


# -------------------------------------------------- грунт

def make_ground(race: str, suffix: str) -> Image.Image:
    img = Image.open(SRC / f"ground_{suffix}.png").convert("RGB")
    a = np.array(box_down(img.convert("RGBA"), GROUND_DIV))[..., :3].astype(np.float64)
    n = min(a.shape[:2])
    a = a[:n, :n]
    # шов: сдвинутая на полразмера копия, в центре исходника вес 1, у краёв 0 (гладкая «палатка»)
    j = np.roll(a, (n // 2, n // 2), axis=(0, 1))
    t = 1.0 - np.abs(np.linspace(-1, 1, n))
    t = t * t * (3 - 2 * t)
    w2 = (t[:, None] * t[None, :])[..., None]
    s = a * w2 + j * (1 - w2)
    q = Image.fromarray(np.clip(s, 0, 255).astype(np.uint8), "RGB").quantize(
        colors=48, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGBA")
    arr = np.array(q).astype(np.float64) / 255.0
    tile, lift, pivot = INNER[race]
    t = np.array(Image.open(ROOT / tile).convert("RGBA")).astype(np.float64) / 255.0
    avg = t[..., :3][t[..., 3] > 0.9].mean(axis=0)
    c = avg * np.array(FLOOR_TINT) * lift                 # как внутри до шейдера пола
    l = float(lum(c))
    c = c * (pivot + (l - pivot) * CALM_CONTRAST) / max(l, 1e-4)   # floor_calm
    target = c / lift                                      # снаружи множитель lift даёт узел FieldSurround (modulate)
    rgb = arr[..., :3]
    mean = rgb.reshape(-1, 3).mean(axis=0)
    rgb = rgb * (target / np.maximum(mean, 1e-4))          # средний цвет — в цвет внутреннего грунта
    rgb = target + (rgb - target) * PATTERN_KEEP           # узор спокойнее
    print("  грунт", race, "цель", np.round(target * 255).astype(int), "яркость", round(float(lum(target)), 3), "(внутри после шейдера", np.round(c * 255).astype(int), ")")
    arr = np.concatenate([np.clip(rgb, 0, 1), np.ones(rgb.shape[:2] + (1,))], axis=-1)
    arr = (arr * 255.0 + 0.5).astype(np.uint8)
    return Image.fromarray(arr, "RGBA")


def contact(items: list, path: Path) -> None:
    cell = max(max(i.shape[0], i.shape[1]) for i in items) + 8
    k = 3
    sheet = Image.new("RGBA", (cell * len(items) * k // 1, cell * k), (36, 28, 30, 255))
    x = 0
    for it in items:
        im = Image.fromarray(it, "RGBA").resize((it.shape[1] * k, it.shape[0] * k), Image.NEAREST)
        sheet.alpha_composite(im, (x, cell * k - im.height - 4))
        x += cell * k
    sheet.convert("RGB").save(path)


def build(race: str) -> None:
    suffix = RACES[race]
    out = OUT / race
    out.mkdir(parents=True, exist_ok=True)
    PREV.mkdir(parents=True, exist_ok=True)
    for old in out.glob("*.png"):
        old.unlink()
    make_ground(race, suffix).save(out / "ground.png")
    raw = [make_prop(f, race) for f in sorted((SRC / "cut" / suffix).glob("*.png"))]
    # один множитель на все предметы расы: средняя яркость по всем пикселям предметов — PROP_LUM
    allpx = np.concatenate([r[..., :3][r[..., 3] > 0].astype(np.float64) / 255.0 for r in raw])
    kk = PROP_LUM[race] / max(lum(allpx).mean(), 1e-4)
    print(race, "множитель яркости предметов", round(kk, 3))
    props = []
    for k, a in enumerate(raw):
        a = a.copy()
        a[..., :3] = np.clip(a[..., :3].astype(np.float64) * kk, 0, 255).astype(np.uint8)
        Image.fromarray(a, "RGBA").save(out / f"prop_{k:02d}.png")
        props.append(a)
        print(race, k, a.shape[1], "x", a.shape[0])
        fn = ANIMS[race].get(k)
        if fn:
            n = ANIM_FRAMES[race][k]
            frames = fn(a, n)
            wmax = max(fr.shape[1] for fr in frames)
            hmax = max(fr.shape[0] for fr in frames)
            norm = []
            for fr in frames:       # общий холст кадра: основание внизу по центру
                c = np.zeros((hmax, wmax, 4), dtype=np.uint8)
                ox = (wmax - fr.shape[1]) // 2
                c[hmax - fr.shape[0]:hmax, ox:ox + fr.shape[1]] = fr
                norm.append(c)
            Image.fromarray(strip(norm), "RGBA").save(out / f"prop_{k:02d}_anim.png")
            print(f"   анимация: {n} кадров {wmax}x{hmax}, {ANIM_FPS[race][k]} к/с")
            contact(norm, PREV / f"{race}_anim_{k:02d}.png")
    contact(props, PREV / f"{race}_contact.png")


if __name__ == "__main__":
    for r in (sys.argv[1:] or list(RACES)):
        build(r)
