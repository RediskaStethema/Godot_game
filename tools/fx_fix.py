"""Пакет эффектов художника (assets/source_sheets/effects_pack, ТЗ — EFFECTS_NEEDED.txt) → листы для Vfx.

Листы пакета пришли с ошибками сборки (21.10.2026):
  - эффект съезжает вниз от кадра к кадру, а вылезшее за низ кадра «заворачивается» к верхнему краю
    (кольцо на земле висит над столбом света) — режим bottom возвращает завёрнутый кусок вниз;
  - у части листов сетка не та, что в ТЗ (ромб клетки — кадр 80, ауры — 216 и 16 кадров), и кадр гуляет
    по x / y — режим center: кусок с края — обратно, затем содержимое кадра — в центр;
  - кадры шире своей ячейки и налезают на соседей (клич Chaplain, тревога штурма) — режим segments:
    кадр — каждый кусок между пустыми столбцами, по центру нового, более широкого кадра.
Брак, который режимы не снимают (аудит 22.10.2026, решение пользователя: чинить брак, вид не трогать):
  - в кадр попали обрывки соседнего ряда атласа пакета (звёзды у ауры Slaanesh, обломки у черепа алтаря,
    штрихи над снарядом Hellfire) — clean: кусок у края кадра, не связанный с самим эффектом, стирается;
  - художник рисовал за ячейкой, и кусок потерян (дым Nurgle, взрыв техники, кольцо Warp Ward) —
    прямой срез по краю кадра смягчается: альфа плавно гаснет к краю (FEATHER, у всех листов —
    только у тех краёв, которых касается эффект);
  - одна широкая картинка разрезана на два кадра (удар варпа: 8+9, 10+11) — merge склеивает их,
    остальные кадры встают по центру кадра двойной ширины;
  - снаряд летит вправо, а кадры сдвинуты сеткой (череп Hellfire срезан в каждом) — segments с
    align right: голова снаряда в одной точке кадра.
Результат — кадры в ряд, assets/effects/<путь пакета>; исходники не трогает.

  python tools/fx_fix.py            — все листы таблицы
  python tools/fx_fix.py level_up   — только листы, в пути которых есть эта строка
"""
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "source_sheets", "effects_pack", "assets")
DST = os.path.join(ROOT, "assets")
ALPHA_MIN = 8        # пиксель с альфой ниже — пустой (ореол свечения листа)

# путь в пакете → (ширина кадра, режим, доп.): drop — сколько первых кадров выкинуть (затухание из пустоты
# у циклов), frames — сколько оставить, pick — только эти кадры (остальные склеены из двух кусков),
# out — ширина кадра на выходе (segments), align — right: кусок к правому краю (снаряд — голова в одной точке),
# merge — пары кадров [i, j] → один кадр двойной ширины, clean — стереть обрывки у края кадра, не связанные
# с эффектом (радиус «связности» в px), ring — кольцо ауры в центр по его середине (center), feather — ширина затухания у среза (по умолчанию FEATHER, 0 — нет)
FEATHER = 6          # px: альфа гаснет к краю кадра, которого касается эффект (срез — не прямой линией)
CLEAN_RADIUS = 3     # px: куски ближе этого — один эффект (искры у столба — не обрывок)
SEGMENT_MARGIN = 2   # px от правого края кадра до куска (align right)
EDGE_NEAR = 4        # px: эффект ближе к краю кадра — край считается срезом (feather)
SHEETS = {
	"effects/upgrades/upgrade_blessed_armour.png": (128, "copy", {}),
	"effects/upgrades/upgrade_daemonic_armour.png": (128, "copy", {}),
	"effects/upgrades/upgrade_battle_fury.png": (128, "copy", {}),
	"effects/upgrades/upgrade_blood_rage.png": (128, "copy", {}),
	"effects/upgrades/upgrade_iron_halo.png": (128, "copy", {}),
	"effects/upgrades/upgrade_warp_ward.png": (128, "copy", {}),
	"effects/upgrades/upgrade_combat_stimms.png": (128, "copy", {"clean": CLEAN_RADIUS}),
	"effects/upgrades/upgrade_combat_drugs.png": (128, "copy", {}),
	"effects/upgrades/upgrade_chapter_banner.png": (128, "bottom", {"pick": [0, 1, 2, 3, 6, 7]}),
	"effects/upgrades/upgrade_icon_of_chaos.png": (128, "bottom", {"pick": [0, 1, 2, 3, 5, 6]}),
	"effects/banner_aura/spritesheet.png": (192, "center", {"drop": 4}),
	"effects/banner_aura/banner_aura_chaos.png": (192, "center", {"drop": 4}),
	"effects/orbital_strike/spritesheet.png": (256, "copy", {}),
	"effects/warp_strike/spritesheet.png": (256, "copy", {"merge": [[8, 9], [10, 11]]}),
	"effects/buildings/aura_plague.png": (216, "center", {"drop": 4, "clean": CLEAN_RADIUS, "ring": True,
		"feather": 18}),
	"effects/buildings/aura_pleasure.png": (216, "center", {"drop": 4, "clean": CLEAN_RADIUS, "ring": True,
		"feather": 18}),
	"effects/buildings/skull_add.png": (64, "bottom", {"clean": CLEAN_RADIUS}),
	"effects/buildings/forge_repair.png": (256, "copy", {}),
	"effects/chaplain_warcry/spritesheet.png": (384, "segments", {"out": 512, "frames": 9}),
	"effects/jump_trail/spritesheet.png": (64, "copy", {}),
	"effects/jump_land/spritesheet.png": (128, "bottom", {}),
	"effects/entrench/spritesheet.png": (64, "copy", {}),
	"effects/retreat_dust/spritesheet.png": (32, "copy", {}),
	"effects/vehicle_explode/spritesheet.png": (128, "bottom", {}),
	"effects/squad_lost/spritesheet.png": (64, "bottom", {}),
	"effects/ricochet/spritesheet.png": (32, "copy", {}),
	"effects/sonic_wave/spritesheet.png": (64, "copy", {}),
	"effects/hellfire_shell/spritesheet.png": (64, "segments", {"out": 80, "align": "right", "frames": 8,
		"clean": CLEAN_RADIUS}),
	"effects/hellfire_blast/spritesheet.png": (192, "bottom", {}),
	"effects/siege_alarm/spritesheet.png": (256, "segments", {"out": 352}),
	"effects/card_burn/spritesheet.png": (180, "copy", {}),
	"ui/fx/card_sell.png": (180, "bottom", {}),
	"ui/fx/no_money.png": (64, "copy", {}),
}


def filled(a):
	return a > ALPHA_MIN


def unwrap_bottom(fr):
	"""Кусок у верхнего края, отделённый пустой строкой от тела кадра, — завёрнутый низ: вернуть вниз."""
	rows = filled(fr[..., 3]).any(axis=1)
	h = len(rows)
	if not rows[0]:
		return fr
	k = int(np.argmin(rows)) if not rows.all() else h   # первая пустая строка — высота куска сверху
	if k >= h * 0.6 or not rows[k:].any():
		k = thin_cut(fr)
		if k == 0:
			return fr   # тело кадра от самого верха (луч с неба) — не завёрнуто
	return np.roll(fr, -k, axis=0)


def thin_cut(fr):
	"""Завёрнутый кусок касается тела кончиком (ромб клетки — верхушки столба): разрез по самой тонкой строке
	верхней части, если кусок над ней широкий (половина ромба), а строка — кончик в несколько пикселей.
	Узкий луч с неба так не режется. 0 — разреза нет."""
	m = filled(fr[..., 3])
	h, w = m.shape
	width = m.sum(axis=1)
	top = int(h * 0.45)
	k = 4 + int(np.argmin(width[4:top]))
	if width[k] > w * 0.05 or width[:k].max() < w * 0.25:
		return 0
	return k


def unwrap_cyclic(fr, axis):
	"""Содержимое — одним куском по оси: самая длинная пустая полоса (по кругу) уходит на край кадра."""
	occ = filled(fr[..., 3]).any(axis=1 - axis)
	n = len(occ)
	if not occ.any() or occ.all():
		return fr
	best_len, best_start, run, start = 0, 0, 0, 0
	for i in range(2 * n):
		if not occ[i % n]:
			if run == 0:
				start = i
			run += 1
			if run > best_len and run <= n:
				best_len, best_start = run, start
		else:
			run = 0
	# полоса best_start … best_start + best_len − 1 → в начало кадра
	return np.roll(fr, -(best_start % n), axis=axis)


def recenter(fr):
	m = filled(fr[..., 3])
	if not m.any():
		return fr
	ys = np.where(m.any(axis=1))[0]
	xs = np.where(m.any(axis=0))[0]
	h, w = m.shape
	dy = int(round((h - 1) / 2 - (ys[0] + ys[-1]) / 2))
	dx = int(round((w - 1) / 2 - (xs[0] + xs[-1]) / 2))
	return np.roll(np.roll(fr, dy, axis=0), dx, axis=1)


def recenter_ring(fr):
	"""Кольцо ауры — в центр кадра по его крайним левым и правым пикселям: они лежат на середине эллипса.
	Столб дыма над кольцом (Nurgle) центр по рамке сдвигал вниз, и низ кольца упирался в край кадра."""
	m = filled(fr[..., 3])
	if not m.any():
		return fr
	h, w = m.shape
	xs = np.where(m.any(axis=0))[0]
	side = np.zeros_like(m)
	side[:, xs[0]:xs[0] + 4] = True
	side[:, xs[-1] - 3:xs[-1] + 1] = True
	ys = np.nonzero(m & side)[0]
	dy = int(round((h - 1) / 2 - ys.mean()))
	dx = int(round((w - 1) / 2 - (xs[0] + xs[-1]) / 2))
	return shift(fr, dy, dx)


def shift(fr, dy, dx):
	"""Сдвиг без заворота: ушедшее за край кадра пропадает, а не появляется с другой стороны."""
	out = np.zeros_like(fr)
	h, w = fr.shape[:2]
	out[max(dy, 0):h + min(dy, 0), max(dx, 0):w + min(dx, 0)] = fr[max(-dy, 0):h + min(-dy, 0), max(-dx, 0):w + min(-dx, 0)]
	return out


def segments(im, out_w, count, align="center"):
	"""Куски между пустыми столбцами; мелкие обрывки (< 12 px) — к ближайшему куску."""
	occ = filled(im[..., 3]).any(axis=0)
	segs, s = [], None
	for x, v in enumerate(occ):
		if v and s is None:
			s = x
		if not v and s is not None:
			segs.append([s, x])
			s = None
	if s is not None:
		segs.append([s, len(occ)])
	big = [g for g in segs if g[1] - g[0] >= 12]
	for g in segs:
		if g[1] - g[0] < 12 and big:
			near = min(big, key=lambda b: min(abs(b[0] - g[1]), abs(g[0] - b[1])))
			near[0], near[1] = min(near[0], g[0]), max(near[1], g[1])
	big = big[:count] if count else big
	h = im.shape[0]
	frames = []
	for a, b in big:
		fr = np.zeros((h, out_w, 4), dtype=im.dtype)
		piece = im[:, a:b][:, :out_w]
		x0 = (out_w - piece.shape[1]) // 2 if align == "center" else out_w - SEGMENT_MARGIN - piece.shape[1]
		fr[:, x0:x0 + piece.shape[1]] = piece
		frames.append(fr)
	return frames


def components(m):
	"""Метки связных кусков маски (8 соседей) — без scipy: обход в ширину по непрозрачным пикселям."""
	h, w = m.shape
	lab = np.zeros((h, w), dtype=np.int32)
	n = 0
	for y0, x0 in zip(*np.nonzero(m)):
		if lab[y0, x0]:
			continue
		n += 1
		lab[y0, x0] = n
		stack = [(y0, x0)]
		while stack:
			y, x = stack.pop()
			for dy in (-1, 0, 1):
				for dx in (-1, 0, 1):
					yy, xx = y + dy, x + dx
					if 0 <= yy < h and 0 <= xx < w and m[yy, xx] and not lab[yy, xx]:
						lab[yy, xx] = n
						stack.append((yy, xx))
	return lab, n


def clean(fr, radius):
	"""Обрывки у края кадра, не связанные с самим эффектом (самым крупным куском), — стереть. Связность —
	по маске, расширенной на radius: искры и обломки рядом с эффектом — его часть."""
	m = filled(fr[..., 3])
	if not m.any():
		return fr
	grown = np.array(Image.fromarray(m.astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(radius * 2 + 1))) > 0
	lab, n = components(grown)
	if n < 2:
		return fr
	sizes = np.bincount(lab[m], minlength=n + 1)
	main = int(np.argmax(sizes))
	border = np.zeros_like(m)
	border[0, :] = border[-1, :] = border[:, 0] = border[:, -1] = True
	out = fr.copy()
	for k in set(np.unique(lab[border & grown])) - {0, main}:
		out[lab == k] = 0
	return out


def feather(fr, px, cap=True):
	"""Срез по краю кадра — не прямой линией: у краёв, которых касается эффект, альфа плавно гаснет к краю."""
	m = filled(fr[..., 3])
	h, w = m.shape
	if cap:   # заданную в таблице ширину не урезаем
		px = min(px, max(1, min(h, w) // 8))   # мелкий лист (пыль 32×16) — уже, иначе эффект гаснет весь
	if px <= 0:
		return fr
	ys = np.arange(h, dtype=float)[:, None]
	xs = np.arange(w, dtype=float)[None, :]
	k = np.ones((h, w))
	ramp = lambda d: np.clip((d + 0.5) / px, 0.0, 1.0) ** 1.5
	near = EDGE_NEAR   # срез бывает и на пару пикселей внутри (сдвиг кольца ауры отрезал верх)
	if m[:near].any():
		k = k * ramp(ys)
	if m[-near:].any():
		k = k * ramp(h - 1 - ys)
	if m[:, :near].any():
		k = k * ramp(xs)
	if m[:, -near:].any():
		k = k * ramp(w - 1 - xs)
	out = fr.copy()
	out[..., 3] = (fr[..., 3] * k).round().astype(fr.dtype)
	return out


def merge(frames, pairs):
	"""Пары кадров — одна широкая картинка; все кадры — в кадр наибольшей ширины, по центру."""
	firsts = {a: b for a, b in pairs}
	seconds = {b for _, b in pairs}
	joined = [np.concatenate([f, frames[firsts[i]]], axis=1) if i in firsts else f
		for i, f in enumerate(frames) if i not in seconds]
	out_w = max(f.shape[1] for f in joined)
	res = []
	for f in joined:
		fr = np.zeros((f.shape[0], out_w, 4), dtype=f.dtype)
		x0 = (out_w - f.shape[1]) // 2
		fr[:, x0:x0 + f.shape[1]] = f
		res.append(fr)
	return res


def process(rel, w, mode, opt):
	im = np.array(Image.open(os.path.join(SRC, rel)).convert("RGBA"))
	if mode == "segments":
		frames = segments(im, opt["out"], opt.get("frames"), opt.get("align", "center"))
	else:
		frames = [im[:, i * w:(i + 1) * w] for i in range(im.shape[1] // w)]
		if mode == "bottom":
			frames = [unwrap_bottom(f) for f in frames]
		elif mode == "center":
			# обрывки соседнего ряда — до центрирования: иначе они сдвигают центр
			frames = [unwrap_cyclic(unwrap_cyclic(f, 0), 1) for f in frames]
			if opt.get("clean"):
				frames = [clean(f, opt["clean"]) for f in frames]
			if opt.get("ring"):   # срез ячейки художника — смягчить до сдвига: после он окажется внутри кадра
				frames = [feather(f, opt.get("feather", FEATHER), "feather" not in opt) for f in frames]
			frames = [recenter_ring(f) if opt.get("ring") else recenter(f) for f in frames]
	if "merge" in opt:
		frames = merge(frames, opt["merge"])
	if "pick" in opt:
		frames = [frames[i] for i in opt["pick"]]
	frames = frames[opt.get("drop", 0):]
	if opt.get("frames") and mode != "segments":
		frames = frames[:opt["frames"]]
	if opt.get("clean") and mode != "center":
		frames = [clean(f, opt["clean"]) for f in frames]
	frames = [feather(f, opt.get("feather", FEATHER), "feather" not in opt) for f in frames]
	out = os.path.join(DST, rel)
	os.makedirs(os.path.dirname(out), exist_ok=True)
	Image.fromarray(np.concatenate(frames, axis=1)).save(out)
	print("%-52s %s  кадр %dx%d x %d" % (rel, mode, frames[0].shape[1], frames[0].shape[0], len(frames)))


if __name__ == "__main__":
	only = sys.argv[1] if len(sys.argv) > 1 else ""
	for rel, (w, mode, opt) in SHEETS.items():
		if only in rel:
			process(rel, w, mode, opt)
