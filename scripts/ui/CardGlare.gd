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
const SHADER = """shader_type canvas_item;
render_mode blend_add;
uniform float foil = 0.0;            // 1 — Epic: переливы
uniform float sweep = -1.0;          // доля прохода полосы блика (< 0 — нет)
uniform vec2 mouse = vec2(0.5);      // курсор в долях карты
uniform float hover = 0.0;
uniform vec3 light_color = vec3(1.0, 0.86, 0.62);
// Силуэт карты: альфа рамки + окно арта (в долях лица) — прозрачные поля рамки (у Common) не светятся
uniform bool use_mask = false;
uniform sampler2D mask_tex : filter_linear;
uniform vec4 window = vec4(0.0, 0.0, 1.0, 1.0);   // x, y, конец x, конец y
void fragment() {
	vec3 col = vec3(0.0);
	if (sweep >= 0.0) {
		float d = UV.x + UV.y * 0.5 - (sweep * 1.9 - 0.2);
		col += light_color * smoothstep(0.09, 0.0, abs(d)) * 0.32;
	}
	if (foil > 0.5) {
		float h = fract(UV.x * 0.8 + UV.y * 0.6 + mouse.x * 0.5 + TIME * 0.05);
		vec3 rainbow = 0.5 + 0.5 * cos(6.2831 * (h + vec3(0.0, 0.33, 0.67)));
		col += rainbow * 0.09 * hover;
	}
	col += light_color * hover * 0.14 * smoothstep(0.65, 0.0, distance(UV, mouse));
	if (use_mask) {
		float inside = step(window.x, UV.x) * step(UV.x, window.z) * step(window.y, UV.y) * step(UV.y, window.w);
		col *= max(texture(mask_tex, UV).a, inside);
	}
	COLOR = vec4(col, 1.0);
}"""

static var _shader: Shader

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
const GLOW_SHADER = """shader_type canvas_item;
render_mode blend_add;
uniform vec3 glow_color = vec3(0.35, 0.72, 1.0);
uniform vec2 rect_size = vec2(100.0);
uniform float pad = 10.0;
uniform vec3 ember_color = vec3(1.0, 0.8, 0.5);   // искры-угольки на кромке
uniform float level = 0.0;          // сила: постоянная + наведение (считает узел)
// Карта с рамкой: свет от силуэта и по металлу рамки (координаты — px арта карты)
uniform bool use_shape = false;
uniform sampler2D dist_tex : filter_linear, repeat_disable;     // расстояние от силуэта наружу / shape_margin
uniform sampler2D frame_tex : filter_linear_mipmap, repeat_disable;
uniform vec2 art_size = vec2(360.0, 504.0);
uniform float shape_margin = 40.0;
uniform float metal_gain = 0.24;    // сила отсвета на металле рамки (METAL_GAIN)
uniform vec4 plate = vec4(0.0);     // крупная плашка малой карты (x, y, конец x, конец y) — тоже силуэт
uniform vec4 calm_a = vec4(0.0);    // пергамент плашек — свет на него не ложится
uniform vec4 calm_b = vec4(0.0);
float in_rect(vec2 p, vec4 r) { return step(r.x, p.x) * step(p.x, r.z) * step(r.y, p.y) * step(p.y, r.w); }
float hash(float n) { return fract(sin(n) * 43758.5453); }
float noise(float x) {               // плавный шум по одной оси
	float i = floor(x);
	float f = fract(x);
	return mix(hash(i), hash(i + 1.0), f * f * (3.0 - 2.0 * f));
}
void fragment() {
	vec2 p = UV * rect_size - rect_size * 0.5;
	vec2 hs = rect_size * 0.5 - vec2(pad);
	float r = 4.0;
	vec2 q = abs(p) - hs + vec2(r);
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;   // < 0 — внутри карты
	// координата вдоль периметра (px): пятна света ползут по кромке
	float per = (atan(p.y, p.x) + 3.14159) * (hs.x + hs.y) * 0.64;
	float t = TIME * 0.6;
	float smolder = noise(per * 0.045 + t) * 0.65 + noise(per * 0.13 - t * 1.7) * 0.35;
	smolder = smoothstep(0.25, 0.9, smolder);                    // тлеет пятнами, местами почти гаснет
	float flick = 0.8 + 0.2 * noise(TIME * 7.0 + per * 0.02);   // неровное мерцание
	if (use_shape) {
		float k = max((rect_size.x - pad * 2.0) / art_size.x, 0.001);   // px экрана на px арта
		vec2 a = (UV * rect_size - vec2(pad)) / k;
		float far = texture(dist_tex, (a + vec2(shape_margin)) / (art_size + vec2(shape_margin * 2.0))).r * shape_margin;
		if (plate.z > plate.x) {
			vec2 out_of = max(max(plate.xy - a, a - plate.zw), vec2(0.0));
			far = min(far, length(out_of));
		}
		float s = far * k;                                          // px экрана от кромки рамки
		float breath = 0.82 + 0.18 * smolder;                       // медленное дыхание, без пятен и провалов
		// ореол: плотный у самой кромки, быстро гаснет; внутри силуэта его нет
		float halo = exp(-s / 3.2) * smoothstep(0.0, 0.7, s) * (1.0 - smoothstep(shape_margin * 0.55, shape_margin, far));
		if (pad > 0.0) {
			halo *= 1.0 - smoothstep(pad * 0.6, pad, s);
		}
		// отсвет на самой рамке: чем светлее металл / камень, тем сильнее берёт цвет
		float metal = 0.0;
		if (a.x >= 0.0 && a.y >= 0.0 && a.x <= art_size.x && a.y <= art_size.y) {
			vec4 f = texture(frame_tex, a / art_size);
			float lum = dot(f.rgb, vec3(0.299, 0.587, 0.114));
			// самое светлое (ленты пергамента, блики) берёт цвет слабее — не выбеливается
			metal = f.a * smoothstep(0.08, 0.55, lum) * (1.0 - smoothstep(0.5, 0.75, lum))
				* (1.0 - max(in_rect(a, calm_a), in_rect(a, calm_b)));
		}
		vec3 lit = glow_color * (halo * 0.55 + metal * metal_gain) * breath;
		float ember = step(0.99, hash(floor(per * 0.25) + floor(TIME * 3.0) * 17.0));
		lit += ember_color * ember * smoothstep(2.0, 0.6, s) * smoothstep(0.0, 0.6, s) * smolder * 0.35;
		COLOR = vec4(lit * level, 1.0);
	} else {
	// ореол за краем — рваный, как дымка
	float haze = noise(per * 0.07 + d * 0.3 - TIME * 0.9);
	float outer = d > 0.0 ? exp(-d / max(pad * 0.35, 1.0)) * (0.25 + 0.45 * haze) : 0.0;
	float inner = d <= 0.0 ? exp(d / 7.0) * 0.18 : 0.0;
	float rim = smoothstep(1.8, 0.0, abs(d + 1.0)) * 0.5;
	vec3 col = glow_color * (outer + inner + rim) * (0.5 + 0.7 * smolder) * flick;
	// редкие угольки на самой кромке
	float spark = step(0.985, hash(floor(per * 0.25) + floor(TIME * 3.0) * 17.0)) * rim * smolder;
	col += ember_color * spark * 0.6;
	COLOR = vec4(col * level, 1.0);
	}
}"""
static var _glow_shader: Shader
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
	if _glow_shader == null:
		_glow_shader = Shader.new()
		_glow_shader.code = GLOW_SHADER
	var glow := RarityGlow.new()
	glow.name = "RarityGlow"
	glow.always = always
	glow.mult = mult
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = _glow_shader
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
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	g._mat = ShaderMaterial.new()
	g._mat.shader = _shader
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
