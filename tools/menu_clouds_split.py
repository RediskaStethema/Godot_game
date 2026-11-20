"""Нарезка облаков главного меню на отдельные облака (решение пользователя 19.11.2026: при взлёте облака должны
улетать целиком, а не разрезанной пополам текстурой).

Облака — один лист 1774×887 (assets/ui/menu/anim/menu_storm_clouds.png). Отдельные облака — связные пятна; сплошная
масса внизу режется по тёмным швам между слоями (маркеры — светлые области, остальное достаётся ближайшему маркеру).
Каждое облако — свой PNG по рамке (assets/ui/menu/anim/clouds_parts/cloud_NN.png) + clouds_parts.json с положением,
центром и размером. Запуск: python tools/menu_clouds_split.py [--preview папка]
"""
import json, os, sys
from collections import deque
import numpy as np
from PIL import Image

SRC = "assets/ui/menu/anim/menu_storm_clouds.png"
OUT = "assets/ui/menu/anim/clouds_parts"
ALPHA_MIN = 40        # непрозрачнее — облако
DARK_PCT = int(os.environ.get("DP", 62))         # самые тёмные процент пикселей облака — швы
MARKER_MIN = int(os.environ.get("MK", 600))      # меньше — не облако, а крошка шва (отдаётся ближайшему)
FEATHER = 16          # px мягкого шва между облаками одной массы
MERGE_MIN = int(os.environ.get("MM", 12000))      # облако мельче — вливается в соседа по самому длинному общему краю


def label(mask, conn4=True):
    h, w = mask.shape
    lab = np.zeros((h, w), np.int32)
    n = 0
    for y in range(h):
        for x in range(w):
            if mask[y, x] and lab[y, x] == 0:
                n += 1
                lab[y, x] = n
                q = deque([(y, x)])
                while q:
                    cy, cx = q.popleft()
                    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        ny, nx = cy + dy, cx + dx
                        if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and lab[ny, nx] == 0:
                            lab[ny, nx] = n
                            q.append((ny, nx))
    return lab, n


def main():
    img = Image.open(SRC).convert("RGBA")
    a = np.array(img)
    alpha = a[..., 3]
    mask = alpha > ALPHA_MIN
    # 1. отдельные облака — связные пятна
    comp, n = label(mask)
    sizes = np.bincount(comp.ravel())
    big = [i for i in range(1, n + 1) if sizes[i] > 60000]
    final = np.zeros_like(comp)
    nxt = 0
    for i in range(1, n + 1):
        if sizes[i] < 80:
            continue
        m = comp == i
        if i not in big:
            nxt += 1
            final[m] = nxt
            continue
        # 2. масса — по швам
        lum = a[..., :3].astype(np.float32) @ np.array([0.299, 0.587, 0.114], np.float32)
        th = np.percentile(lum[m], DARK_PCT)
        seed = m & (lum > th)
        # размыкаем узкие перемычки — эрозия 3 пикс
        er = seed.copy()
        for _ in range(int(os.environ.get("ER", 2))):
            e = er.copy()
            e[1:] &= er[:-1]; e[:-1] &= er[1:]; e[:, 1:] &= er[:, :-1]; e[:, :-1] &= er[:, 1:]
            er = e
        lab, k = label(er)
        sz = np.bincount(lab.ravel())
        keep = [j for j in range(1, k + 1) if sz[j] >= MARKER_MIN]
        mark = np.zeros_like(lab)
        for idx, j in enumerate(keep, 1):
            mark[lab == j] = idx
        # ближайший маркер — расходящимся фронтом внутри массы
        h, w = mark.shape
        out = mark.copy()
        q = deque(zip(*np.nonzero(mark)))
        while q:
            cy, cx = q.popleft()
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = cy + dy, cx + dx
                if 0 <= ny < h and 0 <= nx < w and m[ny, nx] and out[ny, nx] == 0:
                    out[ny, nx] = out[cy, cx]
                    q.append((ny, nx))
        # 3. мелкие части вливаем в соседа с самым длинным общим краем
        while True:
            ids, cnt = np.unique(out[out > 0], return_counts=True)
            small = [(c, i) for i, c in zip(ids, cnt) if c < MERGE_MIN]
            if not small or len(ids) == 1:
                break
            c, sid = min(small)
            sm = out == sid
            edge = {}
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                sh = np.roll(np.roll(sm, dy, 0), dx, 1)
                nb = out[sh & ~sm]
                for v in nb[nb > 0]:
                    edge[v] = edge.get(v, 0) + 1
            if not edge:
                out[sm] = 0
                continue
            out[sm] = max(edge, key=edge.get)
        for v in np.unique(out[out > 0]):
            nxt += 1
            final[out == v] = nxt
    # 4. сохранение: у каждого облака швы между соседями мягкие и с заходом на соседа (FEATHER px) — при расхождении
    # открывается пушистый край, а не срез; у пары облаков на шве прозрачность в сумме даёт 1
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        os.remove(os.path.join(OUT, f))
    parts = []
    ids = [v for v in range(1, nxt + 1) if (final == v).sum() >= 200]
    for v in ids:
        m = final == v
        other = (final > 0) & ~m
        # швы: точки облака, касающиеся другого облака (4-соседство), и точки соседей, касающиеся облака
        def touch(a, b):
            t = np.zeros_like(a)
            t[1:] |= a[1:] & b[:-1]; t[:-1] |= a[:-1] & b[1:]
            t[:, 1:] |= a[:, 1:] & b[:, :-1]; t[:, :-1] |= a[:, :-1] & b[:, 1:]
            return t
        seam_in = touch(m, other)
        seam_out = touch(other, m)
        f = np.where(m, 1.0, 0.0).astype(np.float32)
        if seam_in.any():
            # внутрь: от 0.5 на шве до 1 на FEATHER px от шва
            dist = np.full(m.shape, 99, np.int32)
            dist[seam_in] = 0
            fr = seam_in.copy()
            for d in range(1, FEATHER + 1):
                n = np.zeros_like(fr)
                n[1:] |= fr[:-1]; n[:-1] |= fr[1:]; n[:, 1:] |= fr[:, :-1]; n[:, :-1] |= fr[:, 1:]
                n &= m & (dist == 99)
                dist[n] = d
                fr = n
            t = np.clip(dist / float(FEATHER), 0, 1)
            f = np.where(m, 0.5 + 0.5 * (t * t * (3 - 2 * t)), 0.0).astype(np.float32)
            # наружу: захват соседа от 0.5 на шве до 0 на FEATHER px
            mass = mask & (final > 0)
            dout = np.full(m.shape, 99, np.int32)
            dout[seam_out] = 0
            fr = seam_out.copy()
            for d in range(1, FEATHER + 1):
                n = np.zeros_like(fr)
                n[1:] |= fr[:-1]; n[:-1] |= fr[1:]; n[:, 1:] |= fr[:, :-1]; n[:, :-1] |= fr[:, 1:]
                n &= mass & ~m & (dout == 99)
                dout[n] = d
                fr = n
            to = np.clip(dout / float(FEATHER), 0, 1)
            ext = mass & ~m & (dout < 99)
            f = np.where(ext, 0.5 * (1.0 - (to * to * (3 - 2 * to))), f)
        cover = m | (f > 0)
        ys, xs = np.nonzero(cover)
        x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
        piece = a[y0:y1, x0:x1].copy()
        piece[..., 3] = (piece[..., 3].astype(np.float32) * f[y0:y1, x0:x1]).astype(np.uint8)
        name = "cloud_%02d.png" % len(parts)
        Image.fromarray(piece).save(os.path.join(OUT, name))
        mx, my = np.nonzero(m)[1], np.nonzero(m)[0]
        parts.append({"file": name, "x": int(x0), "y": int(y0), "w": int(x1 - x0), "h": int(y1 - y0),
                      "cx": float(mx.mean()), "cy": float(my.mean()), "area": int(m.sum())})
    with open(os.path.join(OUT, "clouds_parts.json"), "w", encoding="utf-8") as f:
        json.dump(parts, f, indent=1)
    print(len(parts), "облаков")
    if "--preview" in sys.argv:
        pv = sys.argv[sys.argv.index("--preview") + 1]
        os.makedirs(pv, exist_ok=True)
        rng = np.random.default_rng(3)
        col = rng.integers(60, 255, (nxt + 1, 3))
        col[0] = 0
        Image.fromarray(col[final].astype(np.uint8)).save(os.path.join(pv, "labels.png"))


main()
