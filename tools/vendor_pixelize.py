"""Продавцы магазина в пиксель-арт игры (решение пользователя 23.11.2026: «перерисуй продавцов, концепции оставь, сделай их больше
в стиле игры»): кадры `assets/ui/shop/vendor/<раса>/{idle,buy,no_money}` — рисованные мягкие, рядом с пиксельными картами и
бойцами выбиваются. Проход как у зданий и капсулы (`building_pixelize`): блок BLOCK px исходника → один пиксель арта (среднее с
весом альфы), цвет — ступенями по каналам (LEVELS, функция цвета, поэтому кадры не мигают; оттенки акцентов сохраняются), прозрачность — по порогу, кромка силуэта темнее
(как контур бойцов), обратно NEAREST ×BLOCK — холст и ноги прежние, frames.tres в силе. Концепт и анимации не меняются.
  python tools/vendor_pixelize.py [--to <папка>] [chaos|space_marines]    # --to: в другое место (превью), без — на место
Исходники — assets/source_sheets/vendor_pixel_orig_2026-11-23/<раса> (повтор — от них); --restore возвращает прежние кадры.
"""
import shutil
import sys
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
GAME = ROOT / "assets/ui/shop/vendor"
ORIG = ROOT / "assets/source_sheets/vendor_pixel_orig_2026-11-23"
ANIMS = ["idle", "buy", "no_money"]
BLOCK = 8            # px исходника на пиксель арта: продавец ≈ 190 px на экране из 760 → пиксель ≈ 2 px, как у рисунка на картах
LEVELS = 11          # ступеней на канал (общая палитра медианным сечением съедала тёплые акценты — фонарь, глаз в колбе)
ALPHA_MIN = 0.45
EDGE_DARK = 0.55     # кромка силуэта (внутренний пиксель у края) × столько
SAT_KEEP = 1.0


def frames_of(root: Path) -> list:
    out = []
    for a in ANIMS:
        out += sorted((root / a).glob("*.png"), key=lambda p: int(p.stem))
    return out


def down(img: Image.Image) -> np.ndarray:
    a = np.array(img.convert("RGBA")).astype(np.float64)
    h, w = a.shape[0] // BLOCK * BLOCK, a.shape[1] // BLOCK * BLOCK
    a = a[:h, :w]
    al = a[..., 3:4] / 255.0
    pm = (a[..., :3] * al).reshape(h // BLOCK, BLOCK, w // BLOCK, BLOCK, 3).sum(axis=(1, 3))
    asum = al.reshape(h // BLOCK, BLOCK, w // BLOCK, BLOCK, 1).sum(axis=(1, 3))
    rgb = np.where(asum > 1e-6, pm / np.maximum(asum, 1e-6), 0)
    return np.concatenate([rgb, asum / (BLOCK * BLOCK) * 255.0], axis=-1)


def run(race: str, dest: Path) -> None:
    src = ORIG / race
    if not src.exists():
        shutil.copytree(GAME / race, src)        # прежние кадры — исходник повтора
        print(race, "исходники сохранены в", src.relative_to(ROOT))
    files = frames_of(src)
    small = [down(Image.open(f)) for f in files]
    for f, s in zip(files, small):
        solid = s[..., 3] >= ALPHA_MIN * 255
        step = 255.0 / (LEVELS - 1)
        arr = np.round(np.clip(s[..., :3], 0, 255) / step) * step
                # кромка силуэта темнее
        inner = solid.copy()
        edge = solid & ~(np.roll(solid, 1, 0) & np.roll(solid, -1, 0) & np.roll(solid, 1, 1) & np.roll(solid, -1, 1))
        arr[edge] *= EDGE_DARK
        out = np.zeros(solid.shape + (4,), dtype=np.uint8)
        out[..., :3] = np.where(solid[..., None], np.clip(arr, 0, 255), 0).astype(np.uint8)
        out[..., 3] = np.where(solid, 255, 0)
        big = Image.fromarray(out).resize((out.shape[1] * BLOCK, out.shape[0] * BLOCK), Image.NEAREST)
        full = Image.new("RGBA", Image.open(f).size, (0, 0, 0, 0))
        full.paste(big, (0, 0))
        target = dest / race / f.parent.name / f.name
        target.parent.mkdir(parents=True, exist_ok=True)
        full.save(target)
    print(race, len(files), "кадров →", dest.relative_to(ROOT) if dest.is_relative_to(ROOT) else dest)


if __name__ == "__main__":
    args = sys.argv[1:]
    dest = GAME
    if "--restore" in args:
        for r in ("space_marines", "chaos"):
            if (ORIG / r).exists():
                for a in ANIMS:
                    shutil.rmtree(GAME / r / a, ignore_errors=True)
                    shutil.copytree(ORIG / r / a, GAME / r / a)
        print("восстановлено")
        sys.exit(0)
    if "--to" in args:
        i = args.index("--to")
        dest = Path(args[i + 1]).resolve()
        args = args[:i] + args[i + 2:]
    for r in (args or ["space_marines", "chaos"]):
        run(r, dest)
