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
const GLOW_PAD: float = 10.0
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
}"""
static var _glow_shader: Shader
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
	return add_edge_glow(parent, GLOW_COLORS[rarity], Palette.STAR_AMBER if rarity == "rare" else Palette.WARP_EMBER,
		always, pad, GLOW_EPIC if rarity == "epic" else 1.0)

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
