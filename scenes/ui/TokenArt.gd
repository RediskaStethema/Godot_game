class_name TokenArt
extends RefCounted

# Пиксель-арт жетона выбора (TokenCarousel; решение пользователя 13.11.2026: «стилизуй эти жетоны»): картинка
# ART × ART пикселей арта собирается попиксельно и выводится крупным пикселем без сглаживания (кэш по виду).
#   обод — потемневшая латунь объёмом тора: свет сверху слева, ступени Palette.TOKEN_RIM с дизерингом Байера,
#          блик, потёртости пятнами, насечки, заклёпки-полусферы;
#   поле — вогнутая чаша цвета accent (свет на нижнюю правую стенку, к краю темнее, «чеканка» шумом);
#   закрытый — серый.
# Эмблема — не здесь: TokenCarousel рисует её поверх исходной текстурой с мип-уровнями (решение пользователя
# 13.11.2026, `Screenshot 2026-11-13 211546.png`: «ордена и расы почётче» — ужатая до ~40 пикселей арта, при окне
# ×2.5 расплывалась); FIELD_R — радиус поля в пикселях арта, по нему размер эмблемы

const RADIUS: float = 34.0     # радиус медальона в пикселях арта
const ART: int = 74            # сторона картинки
const RIM_IN: float = 0.74     # внутренний край обода — доля радиуса
const RIVETS: int = 10
const NOTCHES: int = 36
const FIELD_STEPS: int = 5
const FIELD_R: float = RIM_IN * RADIUS - 1.0   # радиус поля
const BAYER = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
const LIGHT = Vector3(-0.55, -0.65, 0.53)

static var _cache: Dictionary = {}

# fire — «огненно-чёрное» поле (Вакулинцы, решение пользователя 17.11.2026): почти чёрное, accent — раскалённое только в свету
static func build(accent: Color, locked: bool, fire: bool = false) -> Texture2D:
	var key := "%s|%s|%s" % [accent.to_html(), locked, fire]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(ART, ART, false, Image.FORMAT_RGBA8)
	var c := Vector2(ART, ART) / 2.0 - Vector2(0.5, 0.5)
	var light := LIGHT.normalized()
	var rim_mid := (1.0 + RIM_IN) / 2.0 * RADIUS
	var rim_half := (1.0 - RIM_IN) / 2.0 * RADIUS
	var field_r := FIELD_R
	for y in ART:
		for x in ART:
			var d := Vector2(x, y) - c
			var r := d.length()
			if r > RADIUS + 0.5:
				continue
			var dir := d / maxf(r, 0.001)
			var bay: float = (BAYER[(y % 4) * 4 + (x % 4)] + 0.5) / 16.0
			var col: Color
			if r > RADIUS - 0.7:
				col = Palette.TOKEN_OUTLINE
			elif r > field_r + 1.0:
				# обод: профиль тора — нормаль по t ∈ [−1, 1] поперёк кольца
				var t := clampf((r - rim_mid) / rim_half, -1.0, 1.0)
				var nz := sqrt(maxf(0.0, 1.0 - t * t))
				var n := Vector3(dir.x * t, dir.y * t, nz).normalized()
				var lit := clampf(n.dot(light), 0.0, 1.0)
				var v := 0.1 + lit * 0.62 + pow(lit, 14.0) * 0.8 - _wear(x, y) * 0.22
				var a := fposmod(atan2(d.y, d.x), TAU)
				if absf(fposmod(a * NOTCHES / TAU, 1.0) - 0.5) < 0.09 and absf(t) < 0.55:
					v -= 0.25   # насечка
				col = _ramp(Palette.TOKEN_RIM, v, bay)
			elif r > field_r:
				col = Palette.TOKEN_OUTLINE   # шов между ободом и полем
			else:
				var q := r / field_r
				var n2 := Vector3(-dir.x * q * 0.7, -dir.y * q * 0.7, 1.0).normalized()
				var lit2 := clampf(n2.dot(light), 0.0, 1.0)
				var fv := 0.2 + lit2 * 0.55 - q * q * 0.3 + (_noise(x, y) - 0.5) * 0.1
				col = _fire_field(accent, fv, bay) if fire else _field(accent, fv, bay)
			img.set_pixel(x, y, _grey(col) if locked else col)
	for i in RIVETS:   # заклёпки — полусферы на ободе
		var a := TAU * (i + 0.5) / RIVETS
		var p := c + Vector2(cos(a), sin(a)) * rim_mid
		for oy in range(-2, 3):
			for ox in range(-2, 3):
				var rr := Vector2(ox, oy).length()
				if rr > 2.2:
					continue
				var col2: Color = Palette.TOKEN_RIM[0]
				if rr <= 1.5:
					var nn := Vector3(ox / 2.0, oy / 2.0, 0.8).normalized()
					col2 = _ramp(Palette.TOKEN_RIM, 0.2 + clampf(nn.dot(light), 0.0, 1.0) * 0.9, 0.5)
				img.set_pixel(roundi(p.x) + ox, roundi(p.y) + oy, _grey(col2) if locked else col2)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

static func _grey(col: Color) -> Color:
	var g := col.get_luminance() * 0.85
	return Color(g, g, g * 1.06, col.a)

static func _ramp(ramp: Array, v: float, bay: float) -> Color:
	var f := clampf(v, 0.0, 0.999) * (ramp.size() - 1)
	var i := int(f)
	return ramp[mini(i + (1 if fmod(f, 1.0) > bay else 0), ramp.size() - 1)]

static func _field(accent: Color, v: float, bay: float) -> Color:
	var f := clampf(v, 0.0, 0.999) * (FIELD_STEPS - 1)
	var step := float(int(f) + (1 if fmod(f, 1.0) > bay else 0)) / (FIELD_STEPS - 1)
	return accent.darkened(0.82).lerp(accent.lerp(Color(1, 0.95, 0.85), 0.12), step * 0.85)

static func _fire_field(accent: Color, v: float, bay: float) -> Color:
	var f := clampf((v - 0.25) / 0.5, 0.0, 1.0)   # только свет жетона горит, остальное — чёрное
	var step := float(int(f * 4.0) + (1 if fmod(f * 4.0, 1.0) > bay else 0)) / 4.0
	return Color(0.035, 0.03, 0.03).lerp(accent, pow(step, 1.8) * 0.8)

static func _noise(x: int, y: int) -> float:
	var h := (x * 374761393 + y * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h % 1000) / 1000.0

# Потёртости: крупные пятна — шум по клеткам 3×3 с соседями
static func _wear(x: int, y: int) -> float:
	var s := 0.0
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			s += _noise((x + ox * 2) / 3, (y + oy * 2) / 3)
	return clampf((s / 9.0 - 0.55) * 4.0, 0.0, 1.0)
