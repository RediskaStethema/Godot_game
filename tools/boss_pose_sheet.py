"""Листы поз финального босса для перерисовки в Layer (решение пользователя 23.11.2026: «перерисуй боссов и их фреймы в Layer
в соответствии с новым лором», мастер-кадры утверждены — варианты A). Из кадров ряда `assets/units/bosses/<id>/<ряд>/N.png`
(холст 183×164) делает лист сеткой cols×2: кадр ×2 без сглаживания в ячейке 366×328, как в игре (опора на холст сохраняется).
Ряды: idle 12 → 6×2, run 12 → 6×2, attack 12 → 6×2, special 16 → 4×4, death 16 → 4×4, appear 16 → 4×4.
  python tools/boss_pose_sheet.py <id босса>      # → assets/source_sheets/boss_redraw_v1_2026-11-23/<id>/pose_<ряд>.png
Дальше: image.edit в Layer (исходник — лист, reference — мастер и style_game), затем tools/boss_slice.py.
"""
import sys
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ROWS = {"idle": (6, 2), "run": (6, 2), "attack": (6, 2), "special": (4, 4), "death": (4, 4), "appear": (4, 4)}   # (столбцов, рядов); 16 кадров — 4×4: сетка 8×2 слишком вытянута (4.5:1, Layer сжимает до 3:1)
CELL = (400, 332)   # кадр ×2 у Сангвиния 392 px — ячейка с запасом

boss = sys.argv[1]
src = ROOT / "assets/units/bosses" / boss
out = ROOT / "assets/source_sheets/boss_redraw_v1_2026-11-23" / boss
out.mkdir(parents=True, exist_ok=True)
for row, (cols, nrows) in ROWS.items():
    files = sorted((src / row).glob("*.png"), key=lambda p: int(p.stem))
    n = len(files)
    if n == 0:
        print(row, "— нет кадров, пропуск")
        continue
    sheet = Image.new("RGBA", (cols * CELL[0], nrows * CELL[1]), (0, 0, 0, 0))
    for i, f in enumerate(files):
        im = Image.open(f).convert("RGBA")
        big = im.resize((im.width * 2, im.height * 2), Image.NEAREST)
        sheet.alpha_composite(big, ((i % cols) * CELL[0], (i // cols) * CELL[1]))
    p = out / f"pose_{row}.png"
    sheet.save(p)
    print(row, n, "кадров →", sheet.size, p.stat().st_size)
