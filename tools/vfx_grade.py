"""Листы эффектов из разных паков → одна палитра (стилизация, решение пользователя 18.10.2026: гримдарк).

Каждый пиксель перекрашивается по своей яркости в градиент палитры (RAMPS): тёмное — в тёмный тон
градиента (чёрный контур пака Pixel становится тёмной сталью / бордо), светлое — в светлый. Яркость
нормируется по плотным пикселям листа (перцентили), так что используется весь градиент. Альфа не меняется.
Оригиналы не трогаются: результат — assets/graded/<путь от assets/>, игра берёт его, если он есть
(Vfx._sheet_path, Projectile — тот же путь).

    python tools/vfx_grade.py            — перекрасить все листы из GRADES
    python tools/vfx_grade.py <часть пути> — только листы, в пути которых есть эта строка
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent / "assets"
OUT = ROOT / "graded"

# Градиенты палитры: (позиция 0..1, RGB). Цвета — Palette.gd: сталь, янтарь, бордо, кислотный яд
RAMPS = {
    "fire":   [(0.0, (38, 10, 8)), (0.3, (140, 30, 12)), (0.55, (232, 94, 22)), (0.8, (250, 168, 58)), (1.0, (255, 226, 150))],
    "warp":   [(0.0, (10, 16, 30)), (0.35, (38, 78, 138)), (0.7, (118, 186, 232)), (1.0, (232, 248, 255))],
    # варп-болт: белое ядро листа не выжигается в белый — верх градиента голубой
    "warp_bolt": [(0.0, (8, 14, 40)), (0.35, (30, 70, 170)), (0.7, (70, 150, 240)), (1.0, (175, 222, 255))],
    "smoke":  [(0.0, (12, 14, 20)), (0.5, (58, 64, 76)), (1.0, (148, 152, 162))],
    "dust":   [(0.0, (20, 16, 14)), (0.5, (88, 76, 62)), (1.0, (182, 168, 148))],
    "steel":  [(0.0, (15, 18, 25)), (0.5, (118, 128, 144)), (1.0, (238, 238, 232))],
    "poison": [(0.0, (14, 20, 8)), (0.5, (88, 128, 30)), (1.0, (208, 238, 118))],
    "heal":   [(0.0, (10, 22, 14)), (0.5, (68, 148, 88)), (1.0, (208, 248, 212))],
    "amber":  [(0.0, (30, 16, 6)), (0.5, (198, 128, 40)), (1.0, (255, 234, 168))],
    # болт Хаоса: красное ядро, разряды — не зелёные (зелёный в игре — яд Nurgle), а адский огонь в бордо
    "chaos_bolt": [(0.0, (30, 6, 10)), (0.35, (128, 18, 24)), (0.65, (222, 68, 30)), (0.85, (250, 150, 70)),
                   (1.0, (255, 222, 172))],
}

PIXEL = "effects/Pixel/PNG_native/"
# Лист (путь от assets/) → градиент. Кровь (шейдер Vfx.BLOOD_SHADER) и снаряды bolt / charged / spark
# (цвет вспышки стрелка, Projectile.TINT_SHADER) красятся в игре — здесь их нет
GRADES = {
    "Spritesheets/Spark1-Sheet.png": "fire",
    "Spritesheets/Smoke-Sheet.png": "smoke",
    "Spritesheets/Smoke2-Sheet.png": "smoke",
    "Spritesheets/Fire+Sparks-Sheet.png": "fire",
    "Spritesheets/Rocket Fire 2-Sheet.png": "fire",
    "Spritesheets/Flamethrower-Sheet.png": "fire",
    PIXEL + "combat/hit_side.png": "fire",
    PIXEL + "combat/slash.png": "steel",
    PIXEL + "combat/ground_slam_side.png": "dust",
    PIXEL + "magic/lightning_side.png": "warp",
    PIXEL + "magic/magic_burst.png": "warp",
    PIXEL + "magic/heal_side.png": "heal",
    PIXEL + "magic/shield.png": "warp",
    PIXEL + "pickup_ui/level_up.png": "amber",
    PIXEL + "movement/poof_side.png": "dust",
    PIXEL + "status/burn.png": "fire",
    PIXEL + "status/poison.png": "poison",
    PIXEL + "status/buff.png": "amber",
    PIXEL + "status/debuff.png": "warp",
    PIXEL + "status/stun.png": "amber",
    # FXpack13 (листы — tools/frames_to_strip.py): огненный снаряд цитадели, варп-болт (Шпиль, Рубрики)
    "effects/FXpack13/fireball_sheet.png": "fire",
    "effects/FXpack13/warp_bolt_sheet.png": "warp_bolt",
    "effects/chaos_bolt/spritesheet.png": "chaos_bolt",
}
LOW, HIGH = 2.0, 99.5   # перцентили яркости плотных пикселей → начало и конец градиента
DENSE_ALPHA = 40

# Пакет художника (assets/effects после tools/fx_fix.py; решение пользователя 22.10.2026 «стилизуй эффекты»):
# листы многоцветные (знаки улучшений, черепа, золото) — градиент их бы сплющил, поэтому мягкий цветокор
# SOFT: неон глуше (насыщенность сжимается к SOFT_SAT_CAP), розовый и фиолетовый — к малиновому бордо
# палитры (MAGENTA_PULL), электрический синий — к стали (BLUE_SAT), средние тона темнее (SOFT_GAMMA),
# белое ядро и блики (яркость выше SOFT_KEEP) — как были: свечение читается на тёмном поле
SOFT = "soft"
SOFT_SAT = 0.92         # насыщенность × (всё)
SOFT_SAT_CAP = 0.85     # выше — сжимается: s → cap + (s − cap) × 0.35
BLUE_SAT = 0.88         # синий (тон 0.53–0.70) — ещё глуше, к стали
MAGENTA_PULL = 0.7      # доля сдвига тона розового / фиолетового (0.72–0.97) к малиновому MAGENTA_TARGET
MAGENTA_TARGET = 0.985
MAGENTA_VAL = 0.85      # розовый темнее — бордо, а не неон
SOFT_GAMMA = 1.25       # яркость средних тонов: v^gamma
SOFT_KEEP = 0.9         # яркость выше — без затемнения (ядро, блики)
SOFT_SHEETS = [
    "upgrades/upgrade_blessed_armour.png", "upgrades/upgrade_daemonic_armour.png",
    "upgrades/upgrade_battle_fury.png", "upgrades/upgrade_blood_rage.png",
    "upgrades/upgrade_iron_halo.png", "upgrades/upgrade_warp_ward.png",
    "upgrades/upgrade_combat_stimms.png", "upgrades/upgrade_combat_drugs.png",
    "upgrades/upgrade_chapter_banner.png", "upgrades/upgrade_icon_of_chaos.png",
    "banner_aura/spritesheet.png", "banner_aura/banner_aura_chaos.png",

    "orbital_strike/spritesheet.png", "warp_strike/spritesheet.png",

    "buildings/aura_plague.png", "buildings/aura_pleasure.png",
    "buildings/forge_repair.png", "buildings/skull_add.png",

    "chaplain_warcry/spritesheet.png", "jump_trail/spritesheet.png", "jump_land/spritesheet.png",
    "retreat_dust/spritesheet.png", "vehicle_explode/spritesheet.png", "squad_lost/spritesheet.png",
    "ricochet/spritesheet.png", "hellfire_blast/spritesheet.png", "hellfire_shell/spritesheet.png",

    "siege_alarm/spritesheet.png", "sonic_wave/spritesheet.png", "entrench/spritesheet.png",
    "card_burn/spritesheet.png",
]
for _rel in SOFT_SHEETS:
    GRADES["effects/" + _rel] = SOFT
# Неон, который SOFT не гасит (23.10.2026, «стилизуй эффекты под сеттинг»): розово-фиолетовые варп-листы —
# насыщенность ещё × DEEP_SAT, средние тона темнее (DEEP_GAMMA), розовый — целиком в бордо
DEEP = "deep"
DEEP_SAT = 0.7
DEEP_GAMMA = 1.45
for _rel in ["upgrades/upgrade_warp_ward.png", "upgrades/upgrade_combat_drugs.png", "warp_strike/spritesheet.png"]:
    GRADES["effects/" + _rel] = DEEP


# Пак Pixel — «живописный» вид (решение пользователя 23.10.2026 «стилизуй эффекты под сеттинг»: искра, росчерк,
# пыль, молния, значки статусов — плоский мультяшный пиксель-арт 32 px, растянутый квадратами, а бойцы и пакет
# художника — рисованные). Каждый кадр PAINT_FRAME: ×PAINT_UP со сглаживанием → край альфы снова чёткий, но
# скруглённый (ступеньки пикселей ушли), зерно мазка (PAINT_GRAIN), объём — край темнее середины (PAINT_EDGE_DARK),
# мягкий ореол (PAINT_HALO), затем — градиент палитры, как раньше. Лист выходит в PAINT_UP раз больше исходного:
# Vfx берёт масштаб из отношения ширины листов (Vfx._get_frames) — размеры и точки в Vfx.EFFECTS прежние
PAINT_PREFIX = PIXEL
PAINT_FRAME = 32
PAINT_UP = 4
PAINT_GRAIN = 0.22        # ± доля яркости: зерно мазка
PAINT_EDGE_DARK = 0.35    # край силуэта темнее на эту долю — объём, а не плоская заливка
PAINT_HALO = 0.35         # непрозрачность мягкого ореола вокруг силуэта


def paint(img: Image.Image, seed: int) -> Image.Image:
    src = img.convert("RGBA")
    f, up = PAINT_FRAME, PAINT_UP
    cols, rows = src.width // f, src.height // f
    out = Image.new("RGBA", (cols * f * up, rows * f * up), (0, 0, 0, 0))
    rng = np.random.default_rng(seed)
    for r in range(rows):
        for c in range(cols):
            cell = src.crop((c * f, r * f, c * f + f, r * f + f))
            if cell.getbbox() is None:
                continue
            # поле с запасом под ореол, без утечки в соседний кадр
            big = cell.convert("RGBa").resize((f * up, f * up), Image.BICUBIC).convert("RGBA")
            a = np.array(big).astype(float) / 255.0
            alpha = a[..., 3]
            # край снова чёткий, но скруглённый: альфа через плавный порог
            alpha = np.clip((alpha - 0.3) / 0.4, 0.0, 1.0)
            alpha = alpha * alpha * (3.0 - 2.0 * alpha)
            # объём: глубже в силуэте — светлее
            inner = np.array(Image.fromarray((alpha * 255).astype(np.uint8)).filter(
                ImageFilter.GaussianBlur(up * 1.2))).astype(float) / 255.0
            shade = 1.0 - PAINT_EDGE_DARK * (1.0 - inner)
            # зерно мазка: крупное + мелкое
            n1 = np.array(Image.fromarray((rng.random((f, f)) * 255).astype(np.uint8)).resize(
                (f * up, f * up), Image.BICUBIC)).astype(float) / 255.0
            n2 = rng.random((f * up, f * up))
            grain = 1.0 + PAINT_GRAIN * ((n1 - 0.5) * 1.2 + (n2 - 0.5) * 0.6)
            rgb = np.clip(a[..., :3] * (shade * grain)[..., None], 0.0, 1.0)
            # ореол: размытый силуэт под фигурой, цвета соседних пикселей
            halo_src = Image.fromarray((np.dstack([rgb, alpha]) * 255).astype(np.uint8)).convert("RGBa")
            halo = np.array(halo_src.filter(ImageFilter.GaussianBlur(up * 2.0)).convert("RGBA")).astype(float) / 255.0
            ha = halo[..., 3] * PAINT_HALO
            oa = alpha + ha * (1.0 - alpha)
            orgb = np.where(oa[..., None] > 0, (rgb * alpha[..., None] + halo[..., :3] * (ha * (1.0 - alpha))[..., None])
                            / np.maximum(oa, 1e-6)[..., None], 0.0)
            tile = Image.fromarray((np.dstack([orgb, oa]) * 255).round().astype(np.uint8))
            out.paste(tile, (c * f * up, r * f * up))
    return out


def enable_mipmaps(png: Path) -> None:
    """Лист ×PAINT_UP уменьшается в игре в 3–5 раз — без мип-уровней рябит. .import появится после первого
    `godot --headless --import`: тогда прогнать скрипт ещё раз (и импорт)."""
    imp = png.with_name(png.name + ".import")
    if imp.exists():
        text = imp.read_text(encoding="utf8")
        imp.write_text(text.replace("mipmaps/generate=false", "mipmaps/generate=true"), encoding="utf8")


def ramp_lut(stops):
    """Таблица 256 цветов градиента."""
    xs = np.array([p for p, _ in stops])
    cols = np.array([c for _, c in stops], dtype=float)
    t = np.linspace(0.0, 1.0, 256)
    return np.stack([np.interp(t, xs, cols[:, i]) for i in range(3)], axis=1)


def grade(img: Image.Image, ramp: str) -> Image.Image:
    a = np.array(img.convert("RGBA")).astype(float)
    lum = a[..., 0] * 0.299 + a[..., 1] * 0.587 + a[..., 2] * 0.114
    dense = a[..., 3] > DENSE_ALPHA
    if not dense.any():
        return img
    lo, hi = np.percentile(lum[dense], [LOW, HIGH])
    t = np.clip((lum - lo) / max(hi - lo, 1.0), 0.0, 1.0)
    rgb = ramp_lut(RAMPS[ramp])[(t * 255).astype(int)]
    out = np.concatenate([rgb, a[..., 3:4]], axis=2)
    return Image.fromarray(out.round().astype(np.uint8))


def soft_grade(img: Image.Image, deep: bool = False) -> Image.Image:
    """Мягкий цветокор многоцветного листа (SOFT): тон и форма те же, неон глуше, розовый — к бордо.
    deep (DEEP) — сильнее: насыщенность ниже, средние тона темнее, розовый целиком в бордо."""
    rgba = img.convert("RGBA")
    a = np.array(rgba).astype(float) / 255.0
    hsv = np.array(rgba.convert("RGB").convert("HSV")).astype(float) / 255.0
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    s = s * SOFT_SAT * (DEEP_SAT if deep else 1.0)
    s = np.where(s > SOFT_SAT_CAP, SOFT_SAT_CAP + (s - SOFT_SAT_CAP) * 0.35, s)
    s = np.where((h > 0.53) & (h < 0.70), s * BLUE_SAT, s)
    magenta = (h > 0.72) & (h < 0.97)
    h = np.where(magenta, h + (MAGENTA_TARGET - h) * (1.0 if deep else MAGENTA_PULL), h)
    v = np.where(v < SOFT_KEEP, np.power(v, DEEP_GAMMA if deep else SOFT_GAMMA), v)
    v = np.where(magenta & (v < SOFT_KEEP), v * MAGENTA_VAL, v)
    hsv = (np.stack([h, np.clip(s, 0, 1), v], axis=2) * 255).round().astype(np.uint8)
    rgb = np.array(Image.frombytes("HSV", img.size, hsv.tobytes()).convert("RGB"))
    return Image.fromarray(np.concatenate([rgb, (a[..., 3:4] * 255).round().astype(np.uint8)], axis=2))


def main(args):
    only = args[0] if args else ""
    for rel, ramp in GRADES.items():
        if only and only not in rel:
            continue
        src = ROOT / rel
        if not src.exists():
            print("нет файла:", rel)
            continue
        dst = OUT / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        img = Image.open(src)
        if rel.startswith(PAINT_PREFIX):
            img = paint(img, sum(map(ord, rel)))
        (soft_grade(img, ramp == DEEP) if ramp in (SOFT, DEEP) else grade(img, ramp)).save(dst)
        if rel.startswith(PAINT_PREFIX):
            enable_mipmaps(dst)
        print(f"{rel} -> graded ({ramp})")


if __name__ == "__main__":
    main(sys.argv[1:])
