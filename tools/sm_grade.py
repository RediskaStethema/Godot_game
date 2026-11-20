"""Цветокор ассетов Космодесанта под палитру поля (грунт terrain.png: тёмная сине-сталь, тон 0.59,
яркость 0.145; готика с GOTHIC_TINT — 0.10–0.12). Пишет PNG поверх (или в другую папку), форма и
прозрачность не меняются.

    python tools/sm_grade.py [--tint r,g,b] [--out <папка>] [--target V] [--pull K] [--hue H] [--blue-sat K] <файл> …

Все файлы — одна группа (кадры одного листа, множители общие — кадры не мигают яркостью).
--tint — оттенок, которым игра ещё умножит ассет (тема: "tint"), цель яркости — с ним.
--target / --pull — средняя яркость группы и доля пути к ней (1 — ровно на цель; бойцы — 0.5: разброс
между листами вдвое меньше, а чёрный Chaplain остаётся чёрным, белый Apothecary — белым);
--hue — тон, к которому тянутся камень и металл (Хаос — тёплый); --blue-sat 1 — синий не трогать
(броня бойцов: шейдер ордена Soldier.ARMOR_SHADER ищет синие насыщенные пиксели); --metal-sat —
насыщенность, к которой тянется металл (бойцы — 0.12: ниже порога шейдера 0.2, иначе болтер
Blood Angels покраснел бы вместе с бронёй); --sat — общий множитель насыщенности (кроме огней): здания
глуше, как цитадель и готика поля; --white-hot V — порог «раскалённого» белого (здания с белым камнем —
1.01: белое — не огонь, темнеет вместе со всем); --gold-sat — насыщенность золота (повторный прогон — 1: не серить
золото ещё раз).
Бойцы: `python tools/sm_grade.py --target 0.36 --pull 0.5 --blue-sat 1 --metal-sat 0.12 <папка>/*/*.png`
- камень и металл (почти серые) — к стальному тону грунта, чуть насыщеннее, тусклее до TARGET_VAL;
- огни (тёплые, яркие, насыщенные: пламя, лампады, вспышки) — гаснут слабее (GLOW_KEEP) — светятся
  на тёмном поле, как костры темы;
- золото (тёплое, не яркое) — глуше (GOLD_SAT), синий ордена (знамёна, витражи) — глуше (BLUE_SAT).
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

TARGET_VAL = 0.17      # средняя яркость с оттенком игры: чуть выше грунта (0.145) — главный объект читается
STEEL_HUE = 0.59       # тон грунта
NEUTRAL_SAT = 0.25     # насыщенность ниже — камень, металл
WHITE_HOT = 0.8        # светлее — раскалённое ядро вспышки: огонь, тон не трогаем
NEUTRAL_PULL = 0.7     # доля, на которую их тон тянется к стали
NEUTRAL_SAT_TO = 0.22  # их насыщенность — к этой (сталь с синевой, как грунт)
NEUTRAL_SAT_PULL = 0.5
# Серые с тоном дальше этого от стали (тёплый дым и пыль, ~0.1) — тон и насыщенность не трогаются: путь тона к стали
# идёт через зелёный — дым обрушения цитадели (10.11.2026) выходил мятным, а зелёный в игре — яд Nurgle.
# Бесцветные (s < GRAY_SAT: тон не определён) — сразу тоном стали
NEUTRAL_HUE_FAR = 0.25
GRAY_SAT = 0.04
GLOW = (0.85, 0.5)     # огонь: яркость > 0.85, насыщенность > 0.5, тёплый тон (золото шпилей тусклее — не огонь)
WARM = (0.17, 0.95)    # тёплый — тон ниже первого или выше второго
GLOW_KEEP = 0.5        # огни гаснут на корень из множителя яркости в этой степени (0 — как есть)
GOLD_SAT = 0.8
BLUE = (0.55, 0.72)
BLUE_SAT = 0.75
DENSE = 200


def hsv_of(img):
    return np.array(Image.fromarray(np.array(img)[:, :, :3]).convert("HSV")).astype(float) / 255.0


def tinted_val(img, tint):
    a = np.array(img).astype(float)
    rgb = (a[..., :3] * np.array(tint)).clip(0, 255).astype(np.uint8)
    return np.array(Image.fromarray(rgb).convert("HSV"))[..., 2].astype(float) / 255.0


def masks(h, s, v, white_hot=WHITE_HOT):
    warm = (h < WARM[0]) | (h > WARM[1])
    glow = (warm & (v > GLOW[0]) & (s > GLOW[1])) | (v > white_hot)   # пламя и белое ядро вспышки
    gold = warm & ~glow & (s > NEUTRAL_SAT)
    blue = (h > BLUE[0]) & (h < BLUE[1]) & (s > 0.4)
    neutral = (s < NEUTRAL_SAT) & ~glow
    return glow, gold, blue, neutral


def grade(img, gain, hue=STEEL_HUE, blue_sat=BLUE_SAT, metal_sat=NEUTRAL_SAT_TO, sat=1.0, white_hot=WHITE_HOT,
          gold_sat=GOLD_SAT):
    alpha = np.array(img)[:, :, 3]
    h, s, v = [c.copy() for c in np.moveaxis(hsv_of(img), -1, 0)]
    glow, gold, blue, neutral = masks(h, s, v, white_hot)
    d = ((hue - h + 0.5) % 1.0) - 0.5
    gray = neutral & (s < GRAY_SAT)
    neutral = neutral & ~gray & (np.abs(d) <= NEUTRAL_HUE_FAR) | gray
    h = np.where(gray, hue, np.where(neutral, (h + d * NEUTRAL_PULL) % 1.0, h))
    s = np.where(neutral, s + (metal_sat - s) * NEUTRAL_SAT_PULL, s)
    s = np.where(gold, s * gold_sat, s)
    s = np.where(blue, s * blue_sat, s)
    s = np.where(glow, s, s * sat)
    v = np.where(glow, v * gain ** GLOW_KEEP, v * gain)
    out = Image.merge("HSV", [Image.fromarray((c.clip(0, 1) * 255 + 0.5).astype(np.uint8)) for c in (h, s, v)])
    out = out.convert("RGBA")
    out.putalpha(Image.fromarray(alpha))
    return out


def main(args):
    tint = (1.0, 1.0, 1.0)
    out = None
    target, pull, hue, blue_sat, metal_sat, sat, white_hot = TARGET_VAL, 1.0, STEEL_HUE, BLUE_SAT, NEUTRAL_SAT_TO, 1.0, WHITE_HOT
    gold_sat = GOLD_SAT
    files = []
    it = iter(args)
    for a in it:
        if a == "--tint":
            tint = tuple(float(x) for x in next(it).split(","))
        elif a == "--out":
            out = Path(next(it))
        elif a == "--target":
            target = float(next(it))
        elif a == "--pull":
            pull = float(next(it))
        elif a == "--hue":
            hue = float(next(it))
        elif a == "--blue-sat":
            blue_sat = float(next(it))
        elif a == "--metal-sat":
            metal_sat = float(next(it))
        elif a == "--sat":
            sat = float(next(it))
        elif a == "--gold-sat":
            gold_sat = float(next(it))
        elif a == "--white-hot":
            white_hot = float(next(it))
        else:
            files.append(a)
    images = [Image.open(f).convert("RGBA") for f in files]
    # множитель яркости: средняя по плотным пикселям группы (с оттенком игры), огни — отдельно
    vals, glows = [], []
    for img in images:
        dense = np.array(img)[:, :, 3] > DENSE
        h, s, v = np.moveaxis(hsv_of(img), -1, 0)
        vals.append(tinted_val(img, tint)[dense])
        glows.append(masks(h, s, v, white_hot)[0][dense])
    v_all, g_all = np.concatenate(vals), np.concatenate(glows)
    goal = v_all.mean() * (target / v_all.mean()) ** pull
    # подбор: огни гаснут слабее — множитель ищется так, чтобы итоговая средняя легла на цель
    lo, hi = 0.05, 2.0
    for _ in range(40):
        gain = (lo + hi) / 2
        mean = np.where(g_all, (v_all * gain ** GLOW_KEEP).clip(0, 1), (v_all * gain).clip(0, 1)).mean()
        lo, hi = (gain, hi) if mean < goal else (lo, gain)
    print(f"средняя яркость {v_all.mean():.3f} -> {goal:.3f}, множитель x{gain:.2f}, огни x{gain ** GLOW_KEEP:.2f}")
    for f, img in zip(files, images):
        dst = (out / Path(f).name) if out else Path(f)
        dst.parent.mkdir(parents=True, exist_ok=True)
        grade(img, gain, hue, blue_sat, metal_sat, sat, white_hot, gold_sat).save(dst)
        print(f"  {dst}")


if __name__ == "__main__":
    main(sys.argv[1:])
