class_name CardGlare
extends ColorRect

# Наклон и блик игральной карты (решение пользователя 08.11.2026, только вид): под курсором карта чуть
# поворачивается к нему (до MAX_TILT градусов), по ней скользит пятно света за курсором; у Rare и Epic — полоса
# блика проходит при наведении; у Epic — ещё переливающаяся «фольга». Блик — только под курсором (решение
# пользователя 08.11.2026: сам по себе раз в 4 с не нужен). Оверлей ADD поверх лица карты, мышь не ловит.
# CardGlare.attach(лицо карты, редкость, подсветка всегда) — ShopSlot (всегда), BenchCard (только под курсором)

const MAX_TILT: float = 3.0          # градусов
const TILT_RATE: float = 12.0        # скорость, с которой карта догоняет наклон
const SWEEP_TIME: float = 0.8        # проход полосы блика
const SHADER: Shader = preload("res://shaders/card_glare.gdshader")


# Подсветка редкости (решение пользователя 08.11.2026): Rare — сине-стальная, Epic — варп-фиолетовая, гримдарк:
# не ровный неон, а тлеющая кромка — свет пятнами вдоль края медленно ползёт и мерцает (как угли / свечение
# варпа), ореол за краем рваный, как дымка, редкие искры-угольки. Карты предложения магазина — всегда, неярко
# (GLOW_IDLE), под курсором ярче (GLOW_HOVER); карты в руке (расстановка, рука магазина) — только под курсором
# (решение пользователя: «постоянно — только в магазине», было слишком ярко). Отдельный узел поверх лица (ADD),
# мышь не ловит; в контейнере (карта руки магазина) контейнер растягивает его по карте — тогда только кромка и
# свет внутрь (pad 0). Наведение — от CardGlare (hover), без него узел сам смотрит, над картой ли курсор
#
# Свет — от самой карты, а не от прямоугольника картинки (решение пользователя 26.11.2026, Screenshot 2026-11-26
# 080737.png: «подсветка карт слишком не естественная и исходит из спрайта, а не из текстуры карты»; у рамок
# прозрачные поля — светилась невидимая коробка). У лица карты: ореол идёт от силуэта рамки (карта расстояний
# _silhouette, у малой карты — ещё крупная плашка названия), цвет редкости ложится на светлый металл самой рамки
# (пергамент плашек не красится). Без рамки (окно подкрепления) — прежняя скруглённая кромка
const GLOW_PAD: float = 10.0
const SHAPE_MARGIN: int = 40         # px арта: поле карты расстояний вокруг холста карты (дальше свет не идёт)
const SHAPE_STEP: int = 2            # px арта в одной точке карты расстояний
const SHAPE_ALPHA: float = 0.35      # плотнее — пиксель рамки входит в силуэт
# Отсвет на металле: на золоте эпической фиолетовый уводит в розовый — слабее
const METAL_GAIN = {"rare": 0.24, "epic": 0.1}
const GLOW_IDLE: float = 0.75        # сила постоянной подсветки (магазин)
const GLOW_HOVER: float = 1.35       # под курсором
const GLOW_EPIC: float = 1.15        # Epic — чуть сильнее
const GLOW_COLORS = {"rare": Palette.RARE_GLOW, "epic": Palette.EPIC_GLOW}
const GLOW_SHADER: Shader = preload("res://shaders/card_edge_glow.gdshader")
static var _silhouettes: Dictionary = {}   # редкость → ImageTexture расстояний от силуэта
var _glow: RarityGlow = null         # подсветка редкости этой карты (Rare / Epic)

# Узел подсветки: сила = (always ? GLOW_IDLE : 0) + (GLOW_HOVER − то же) × наведение; driven — наведение задаёт
# CardGlare, иначе узел сам смотрит, над родителем ли курсор
class RarityGlow extends ColorRect:
	var always: bool = false
	var driven: bool = false
	var hover: float = 0.0
	var mult: float = 1.0
	func _process(delta: float) -> void:
		var card := get_parent() as Control
		if card == null or not card.is_visible_in_tree():
			return
		if not driven:
			var over := card.get_global_rect().has_point(card.get_global_mouse_position())
			hover = move_toward(hover, 1.0 if over else 0.0, delta * 6.0)
		var base: float = CardGlare.GLOW_IDLE if always else 0.0
		var level: float = (base + (CardGlare.GLOW_HOVER - base) * hover) * mult
		self_modulate.a = 1.0 if level > 0.001 else 0.0   # не видна — не рисуется
		(material as ShaderMaterial).set_shader_parameter("level", level)

# Подсветка редкости на карте parent (null — у Common); always — и без наведения; pad — ореол за краем
# (0 — только внутрь)
static func add_rarity_glow(parent: Control, rarity: String, always: bool, pad: float = GLOW_PAD) -> RarityGlow:
	if not GLOW_COLORS.has(rarity):
		return null
	var glow := add_edge_glow(parent, GLOW_COLORS[rarity],
		Palette.STAR_AMBER if rarity == "rare" else Palette.WARP_EMBER, always, pad, GLOW_EPIC if rarity == "epic" else 1.0)
	_shape_to_card(glow, parent, rarity)
	return glow

# Лицо карты с рамкой (UITheme.make_card_face): свет по силуэту и металлу рамки вместо прямоугольника
static func _shape_to_card(glow: RarityGlow, face: Control, rarity: String) -> void:
	var frame := face.get_node_or_null("Frame") as TextureRect
	if frame == null or frame.texture == null:
		return
	var art: Vector2 = UITheme.CARD_ART_SIZE
	var layout: Dictionary = UITheme.CARD_FRAME_LAYOUT.get(rarity, UITheme.CARD_FRAME_LAYOUT["common"])
	var m := glow.material as ShaderMaterial
	m.set_shader_parameter("use_shape", true)
	m.set_shader_parameter("dist_tex", _silhouette(rarity, frame.texture, layout))
	m.set_shader_parameter("frame_tex", frame.texture)
	m.set_shader_parameter("art_size", art)
	m.set_shader_parameter("shape_margin", float(SHAPE_MARGIN))
	m.set_shader_parameter("metal_gain", METAL_GAIN.get(rarity, 0.2))
	var calm: Rect2 = layout["plate"]
	var holder := face.get_node_or_null("TitlePlate") as Control
	if holder:   # малая карта: крупная плашка выходит за рамку — свет обходит и её
		var k: float = face.custom_minimum_size.x / art.x
		var width: float = maxf(UITheme.CARD_SMALL_PLATE_WIDTH / UITheme.CARD_SMALL_PLATE_SCALE, calm.size.x)
		calm = Rect2(holder.position / k, Vector2(width, calm.size.y) * holder.scale / k)
		m.set_shader_parameter("plate", _bounds(calm))
	m.set_shader_parameter("calm_a", _bounds(calm))
	if layout.has("footer"):
		m.set_shader_parameter("calm_b", _bounds(layout["footer"]))

static func _bounds(r: Rect2) -> Vector4:
	return Vector4(r.position.x, r.position.y, r.end.x, r.end.y)

# Карта расстояний (раз на редкость): силуэт = рамка + окно иллюстрации + всё, что внутри них замкнуто; значение —
# расстояние наружу в долях SHAPE_MARGIN
static func _silhouette(rarity: String, frame: Texture2D, layout: Dictionary) -> ImageTexture:
	if _silhouettes.has(rarity):
		return _silhouettes[rarity]
	var img := frame.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var art := Vector2i(UITheme.CARD_ART_SIZE)
	img.resize(art.x / SHAPE_STEP, art.y / SHAPE_STEP, Image.INTERPOLATE_BILINEAR)
	var pad := SHAPE_MARGIN / SHAPE_STEP
	var w := img.get_width() + pad * 2
	var h := img.get_height() + pad * 2
	var window: Rect2 = (layout["window"] as Rect2).grow(UITheme.CARD_ART_BLEED)
	var solid := PackedByteArray()
	solid.resize(w * h)
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > SHAPE_ALPHA or window.has_point(Vector2(x, y) * SHAPE_STEP):
				solid[(y + pad) * w + x + pad] = 1
	# Снаружи — то, куда можно дойти от края по прозрачному; замкнутые дыры (гнёзда медальонов) — часть карты
	var outside := PackedByteArray()
	outside.resize(w * h)
	var stack: Array[int] = [0]
	outside[0] = 1
	while not stack.is_empty():
		var i: int = stack.pop_back()
		var x := i % w
		for j in [i - 1 if x > 0 else -1, i + 1 if x < w - 1 else -1, i - w, i + w]:
			if j >= 0 and j < w * h and outside[j] == 0 and solid[j] == 0:
				outside[j] = 1
				stack.append(j)
	# Расстояние двумя проходами (шаг по прямой 1, по диагонали 1.41)
	var dist := PackedFloat32Array()
	dist.resize(w * h)
	for i in w * h:
		dist[i] = 1e6 if outside[i] == 1 else 0.0
	for pass_dir in [1, -1]:
		for n in w * h:
			var i: int = n if pass_dir == 1 else w * h - 1 - n
			if dist[i] == 0.0:
				continue
			var x := i % w
			var y := i / w
			var px: int = x - pass_dir
			var py: int = y - pass_dir
			var d := dist[i]
			if px >= 0 and px < w:
				d = minf(d, dist[y * w + px] + 1.0)
			if py >= 0 and py < h:
				d = minf(d, dist[py * w + x] + 1.0)
				if x > 0:
					d = minf(d, dist[py * w + x - 1] + 1.414)
				if x < w - 1:
					d = minf(d, dist[py * w + x + 1] + 1.414)
			dist[i] = d
	var bytes := PackedByteArray()
	bytes.resize(w * h)
	for i in w * h:
		bytes[i] = int(clampf(dist[i] * SHAPE_STEP / SHAPE_MARGIN, 0.0, 1.0) * 255.0)
	var tex := ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_R8, bytes))
	_silhouettes[rarity] = tex
	return tex

# Тлеющая кромка того же вида на любом Control (EFFECTS_NEEDED 9.5 — окно подкрепления, 09.11.2026): цвет кромки,
# цвет угольков; always / pad — как у подсветки редкости, mult — сила
static func add_edge_glow(parent: Control, col: Color, ember: Color, always: bool, pad: float = GLOW_PAD,
		mult: float = 1.0) -> RarityGlow:
	var glow := RarityGlow.new()
	glow.name = "RarityGlow"
	glow.always = always
	glow.mult = mult
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = GLOW_SHADER
	m.set_shader_parameter("glow_color", Vector3(col.r, col.g, col.b))
	m.set_shader_parameter("ember_color", Vector3(ember.r, ember.g, ember.b))
	m.set_shader_parameter("pad", pad)
	m.set_shader_parameter("level", GLOW_IDLE * glow.mult if always else 0.0)
	glow.material = m
	parent.add_child(glow)
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not parent is Container:
		glow.offset_left = -pad
		glow.offset_top = -pad
		glow.offset_right = pad
		glow.offset_bottom = pad
	else:
		m.set_shader_parameter("pad", 0.0)
	var sync := func(): m.set_shader_parameter("rect_size", glow.size)
	glow.resized.connect(sync)
	sync.call()
	return glow

var target: Control                  # что наклоняется (лицо карты)
var enabled: bool = true             # тащат карту — не наклоняем
var _mat: ShaderMaterial
var _hover: float = 0.0
var _hovered: bool = false
var _sweep: float = -1.0
var _sweeps: bool = false            # Rare и Epic — полоса при наведении

static func attach(face: Control, rarity: String, glow_always: bool = false) -> CardGlare:
	var g := CardGlare.new()
	g.target = face
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g._mat = ShaderMaterial.new()
	g._mat.shader = SHADER
	g._mat.set_shader_parameter("foil", 1.0 if rarity == "epic" else 0.0)
	var lc: Color = Palette.STAR_AMBER
	g._mat.set_shader_parameter("light_color", Vector3(lc.r, lc.g, lc.b))
	# Блик — только по силуэту рамки (решение пользователя 10.11.2026: у Common подсветка выдавала прямоугольник
	# ассета — прозрачные поля рамки светились ADD)
	var frame := face.get_node_or_null("Frame") as TextureRect
	if frame and frame.texture:
		var layout: Dictionary = UITheme.CARD_FRAME_LAYOUT.get(rarity, UITheme.CARD_FRAME_LAYOUT["common"])
		var win: Rect2 = layout["window"]
		g._mat.set_shader_parameter("use_mask", true)
		g._mat.set_shader_parameter("mask_tex", frame.texture)
		g._mat.set_shader_parameter("window", Vector4(win.position.x / UITheme.CARD_ART_SIZE.x,
			win.position.y / UITheme.CARD_ART_SIZE.y, win.end.x / UITheme.CARD_ART_SIZE.x,
			win.end.y / UITheme.CARD_ART_SIZE.y))
	g.material = g._mat
	g._sweeps = rarity == "rare" or rarity == "epic"
	face.add_child(g)
	g.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	g._glow = add_rarity_glow(face, rarity, glow_always)
	if g._glow:
		g._glow.driven = true
	return g

func _process(delta: float) -> void:
	if target == null or not target.is_visible_in_tree():
		return
	var local := target.get_local_mouse_position()
	var over := enabled and Rect2(Vector2.ZERO, target.size).has_point(local)
	if over and not _hovered and _sweeps:
		_sweep = 0.0   # навели — полоса проходит
	_hovered = over
	_hover = move_toward(_hover, 1.0 if over else 0.0, delta * 6.0)
	var m := Vector2(0.5, 0.5)
	if target.size.x > 0.0 and target.size.y > 0.0:
		m = (local / target.size).clamp(Vector2.ZERO, Vector2.ONE)
	_mat.set_shader_parameter("mouse", m)
	_mat.set_shader_parameter("hover", _hover)
	if _glow:
		_glow.hover = _hover
	# наклон к курсору
	target.pivot_offset = target.size / 2.0
	var want := deg_to_rad((m.x - 0.5) * 2.0 * MAX_TILT) * _hover
	target.rotation = lerpf(target.rotation, want, minf(delta * TILT_RATE, 1.0))
	# полоса блика
	if _sweep >= 0.0:
		_sweep += delta / SWEEP_TIME
		if _sweep > 1.0:
			_sweep = -1.0
	_mat.set_shader_parameter("sweep", _sweep)
