"""Срезы по краю кадра у листов эффектов → мягкое затухание (решение пользователя 16.11.2026: «часть эффектов всё ещё
выглядит слишком обрезанно»). Аудит (по Vfx.EFFECTS и Projectile.EFFECTS): эффект упирался в низ кадра (дым ствола, огненный
шар, взрыв, плевок, яд, телепорт) или в правый край (болт) — на экране ровная линия среза. Здесь альфа у такого края
гаснет по полосе FEATHER_PX (только вдоль сторон, где эффект действительно касается края, 2-px полоса с альфой > 60).
Холст и положение эффекта не меняются. Раскладки листов — tools/fx_edge_layouts.json (путь файла, который грузит игра —
graded или исходный, размер кадра, from, frames). Исходники — assets/source_sheets/fx_edge_orig_2026-11-16 (повторный
прогон — от них). После vfx_grade.py (он пишет graded заново) прогнать снова:  python tools/fx_edge_feather.py
"""
import json
import shutil
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
BACKUP = ROOT / "assets/source_sheets/fx_edge_orig_2026-11-16"
FEATHER_FRAC = 0.12     # полоса затухания — доля меньшей стороны кадра
FEATHER_MIN = 4
TOUCH_ALPHA = 60
TOUCH_PX = 4            # меньше пикселей на кромке — эффект не упирается в край


def feather_frame(f: np.ndarray, band: int) -> np.ndarray:
    h, w = f.shape[:2]
    a = f[..., 3].astype(np.float32)
    edge = {"L": f[:, :2, 3], "R": f[:, -2:, 3], "T": f[:2, :, 3], "B": f[-2:, :, 3]}
    touch = {k: int((v > TOUCH_ALPHA).sum()) >= TOUCH_PX for k, v in edge.items()}
    ramp = np.arange(band, dtype=np.float32) / band           # 0 у края → 1 внутри
    ramp = ramp * ramp * (3.0 - 2.0 * ramp)                    # плавный ход
    k = np.ones((h, w), np.float32)
    if touch["L"]:
        k[:, :band] = np.minimum(k[:, :band], ramp[None, :])
    if touch["R"]:
        k[:, w - band:] = np.minimum(k[:, w - band:], ramp[::-1][None, :])
    if touch["T"]:
        k[:band, :] = np.minimum(k[:band, :], ramp[:, None])
    if touch["B"]:
        k[h - band:, :] = np.minimum(k[h - band:, :], ramp[::-1][:, None])
    f = f.copy()
    f[..., 3] = np.clip(a * k, 0, 255).round().astype(np.uint8)
    return f


def main() -> None:
    layouts = json.loads((ROOT / "tools/fx_edge_layouts.json").read_text(encoding="utf-8"))
    done = set()
    for e in layouts:
        rel = e["path"].replace("res://", "")
        if rel in done:
            continue
        done.add(rel)
        dst = ROOT / rel
        src = BACKUP / rel
        if not src.exists():
            src.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(dst, src)
        im = np.array(Image.open(src).convert("RGBA"))
        w, h = e["w"], e["h"]
        if w < 0:
            w, h = im.shape[1] // e["frames"], im.shape[0]
        band = max(FEATHER_MIN, int(round(min(w, h) * FEATHER_FRAC)))
        cols = max(1, im.shape[1] // w)
        out = im.copy()
        for i in range(e["from"], e["from"] + e["frames"]):
            x0, y0 = (i % cols) * w, (i // cols) * h
            if y0 + h > im.shape[0] or x0 + w > im.shape[1]:
                continue
            out[y0:y0 + h, x0:x0 + w] = feather_frame(im[y0:y0 + h, x0:x0 + w], band)
        Image.fromarray(out).save(dst)
        print(f"{e['kind']}: {rel} (полоса {band} px)")


if __name__ == "__main__":
    main()
