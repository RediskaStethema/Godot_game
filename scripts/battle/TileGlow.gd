class_name TileGlow
extends Sprite2D

# Свечение клетки поля (решение пользователя 22.10.2026: листы пакета tile_target / tile_bought — обрезанные,
# схематичные): ромб рисует шейдер ровно по клетке IsoGrid (140×70) при любом зуме, в пикселях клетки поля.
# Кромка тлеет неровно (огоньки по периметру мерцают каждый своим тактом), по ней бегут искры, к центру —
# мягкий отсвет, над клеткой поднимаются угольки. Только вид.
#   target(parent, verdict, точка) — ромб под перетаскиваемой картой (цикл; снимает владелец dismiss())
#   burst(parent, точка, вид, раса) — клетка куплена / здание встало / здание улучшено / доход генератора
#     (решение пользователя 22.10.2026: листы пакета build / building_level_up / generator_pulse — неоновые столбы
#     и «вата» крупных пикселей): от центра идёт волна света, загорается кромка, оседает; у Хаоса — бордо в огонь
#   target(parent, "strike", точка) — метка Orbital Strike на клетке до боя (вместо высокого луча orbital_mark)

# Вид: кромка, ядро (блики, искры), сила отсвета внутри; playable / compatible / invalid — BattleScene._drop_verdict
const LOOKS = {
	"playable":   {"edge": Palette.GOLD, "core": Palette.AMBER_LIGHT, "fill": 0.22},
	"compatible": {"edge": Palette.GOLD_BRIGHT, "core": Palette.GOLD_PALE, "fill": 0.34},
	"invalid":    {"edge": Palette.RED_BRIGHT, "core": Palette.HIT_RED, "fill": 0.36},
	"bought":     {"edge": Palette.GOLD, "core": Palette.AMBER_LIGHT, "fill": 0.3},
	"build":      {"edge": Palette.GOLD, "core": Palette.AMBER_LIGHT, "fill": 0.22},
	"level":      {"edge": Palette.GOLD_BRIGHT, "core": Palette.GOLD_PALE, "fill": 0.36},
	"income":     {"edge": Palette.GOLD, "core": Palette.AMBER_LIGHT, "fill": 0.12},
	"strike":     {"edge": Palette.RED_BRIGHT, "core": Palette.HIT_RED, "fill": 0.3},
}
# Хаос — те же виды в бордо и огне (метка удара — своя: красная у обеих рас)
const CHAOS_LOOK = {"edge": Palette.RED_BRIGHT, "core": Palette.FIRE}
const PIXEL: float = IsoGrid.TILE_WIDTH / 60.0   # пиксель свечения — половина пикселя плиты (32 px арта на 140)
const MARGIN: float = 14.0      # запас квада вокруг ромба — ореол кромки
const RISE: float = 36.0        # запас сверху — угольки поднимаются над клеткой
const FADE_IN: float = 0.15
const FADE_OUT: float = 0.15
const BURST_TIME: float = 1.1

const SHADER = """shader_type canvas_item;
render_mode blend_add;
uniform vec4 edge_color : source_color;
uniform vec4 core_color : source_color;
uniform vec2 quad_size;
uniform vec2 quad_center;     // центр клетки в пикселях квада
uniform vec2 half_tile;
uniform float px;
uniform float fill;
uniform float time;
uniform float alpha = 1.0;
uniform float burst = 0.0;    // 1 — раскрытие купленной клетки
uniform float progress = 0.0; // 0..1 раскрытия (BURST_TIME)

float hash(float n) { return fract(sin(n * 12.9898) * 43758.5453); }
float hash2(vec2 v) { return fract(sin(dot(v, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 v) {
	vec2 i = floor(v);
	vec2 f = fract(v);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x),
		mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 p = UV * quad_size - quad_center;
	p = (floor(p / px) + 0.5) * px;   // пиксель-арт: свечение ступеньками, как плиты
	float k = length(vec2(1.0 / half_tile.x, 1.0 / half_tile.y));
	float d = abs(p.x) / half_tile.x + abs(p.y) / half_tile.y;   // 1 — кромка клетки
	float dist = (d - 1.0) / k;   // до кромки в пикселях, внутри — минус
	float s = fract(atan(p.y * half_tile.x / half_tile.y, p.x) / 6.2831853 + 1.0);   // периметр 0..1
	float stone = vnoise(p / 9.0 + vec2(0.0, time * 0.25));   // свет пятнами по камню, медленно плывёт
	// раскрытие купленной клетки: от центра идёт волна света, за ней загорается кромка, всё оседает
	float edge_on = 1.0;
	float wave = 0.0;
	float dust = 1.0;
	if (burst > 0.5) {
		float t = progress;
		float wr = 1.15 * (1.0 - pow(1.0 - min(t / 0.45, 1.0), 3.0));
		wave = exp(-abs(d - wr) * 10.0) * step(d, wr + 0.15) * (1.0 - smoothstep(0.3, 0.6, t)) * (0.6 + 0.6 * stone);
		wave += step(d, wr) * step(d, 1.0) * (1.0 - smoothstep(0.05, 0.7, t)) * 0.45 * stone;
		edge_on = smoothstep(0.2, 0.42, t) * (1.0 - smoothstep(0.6, 1.0, t));
		dust = 1.0 - smoothstep(0.7, 1.0, t);
	}
	// кромка тлеет неровно: яркость плывёт вдоль периметра, местами почти гаснет
	float ember = smoothstep(0.2, 0.85, vnoise(vec2(s * 22.0, time * 1.6))) * 0.75 + 0.25;
	float pulse = 0.88 + 0.12 * sin(time * 2.4);
	float line = step(-px, dist) * step(dist, 0.0) * ember * 0.75;
	float rim = exp(min(dist, 0.0) / 7.0) * step(dist, 0.0) * 0.4 * ember;   // свет копится у края
	float halo = exp(-max(dist, 0.0) / (px * 1.2)) * step(0.0, dist) * 0.22 * ember;
	float inner = exp(min(dist, 0.0) / 28.0) * step(dist, 0.0) * fill * (0.55 + 0.9 * stone);
	float tip = min(length(vec2(abs(p.x) - half_tile.x, p.y)), length(vec2(p.x, abs(p.y) - half_tile.y)));
	float corner = step(tip, px * 1.5) * step(abs(dist), px * 1.5) * 0.5;   // уголки клетки — чуть ярче
	// две искры бегут по кромке
	float spark = 0.0;
	for (int i = 0; i < 2; i++) {
		float ds = abs(fract(s - fract(time * 0.16 + float(i) * 0.5) + 0.5) - 0.5);
		spark += step(ds, 0.008) * step(abs(dist + px * 0.5), px);
	}
	// угольки поднимаются над клеткой и гаснут
	float mote = 0.0;
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		float life = fract(time * (0.3 + hash(fi) * 0.25) + hash(fi + 9.0));
		vec2 m = vec2((hash(fi + 3.0) - 0.5) * half_tile.x * 1.3, (hash(fi + 5.0) - 0.5) * half_tile.y * 0.7);
		m.y -= life * 30.0;
		m.x += sin(life * 6.2831 + fi) * 3.0;
		vec2 dm = abs(p - (floor(m / px) + 0.5) * px);
		mote += step(max(dm.x, dm.y), px * 0.5) * (1.0 - life) * 0.6;
	}
	float soft = floor((rim + inner + halo) * pulse * 7.0) / 7.0;   // мягкий свет — ступенями, как в пиксель-арте
	float glow = (line + corner) * pulse * edge_on + soft * max(edge_on, 0.35 * step(0.5, burst) * dust) + wave;
	float hot = clamp(spark + corner + wave * 0.6 + line * 0.2, 0.0, 1.0);
	float a = clamp(glow + spark * edge_on + mote * dust, 0.0, 1.0) * alpha;
	vec3 col = mix(edge_color.rgb, core_color.rgb, clamp(hot + mote, 0.0, 1.0));
	COLOR = vec4(col, a);
}"""

static var _shader: Shader
static var _white: Texture2D

var verdict := ""   # вид ромба (LOOKS)
var _time := 0.0
var _age := 0.0
var _burst := false
var _dismiss_left := -1.0

static func target(parent: Node, verdict: String, at: Vector2) -> TileGlow:
	return _make(parent, verdict, at, false)

static func burst(parent: Node, at: Vector2, look: String = "bought", faction: String = "") -> TileGlow:
	return _make(parent, look, at, true, faction)

static func _make(parent: Node, look: String, at: Vector2, is_burst: bool, faction: String = "") -> TileGlow:
	if parent == null or not LOOKS.has(look):
		return null
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white = ImageTexture.create_from_image(img)
	var g := TileGlow.new()
	g.verdict = look
	g._burst = is_burst
	var half := Vector2(IsoGrid.TILE_WIDTH, IsoGrid.TILE_HEIGHT) / 2.0
	var size := Vector2(half.x + MARGIN, half.y + MARGIN) * 2.0 + Vector2(0.0, RISE)
	g.texture = _white
	g.centered = false
	g.scale = size   # квад 1×1 → размер в мире; UV шейдера — 0..1 по кваду
	g.position = Vector2.ZERO
	g.offset = Vector2(-(half.x + MARGIN) / size.x, -(half.y + MARGIN + RISE) / size.y)
	var m := ShaderMaterial.new()
	m.shader = _shader
	var l: Dictionary = LOOKS[look].duplicate()
	if faction == "chaos" and look != "strike":
		l.merge(CHAOS_LOOK, true)
	m.set_shader_parameter("edge_color", l["edge"])
	m.set_shader_parameter("core_color", l["core"])
	m.set_shader_parameter("fill", l["fill"])
	m.set_shader_parameter("quad_size", size)
	m.set_shader_parameter("quad_center", Vector2(half.x + MARGIN, half.y + MARGIN + RISE))
	m.set_shader_parameter("half_tile", half)
	m.set_shader_parameter("px", PIXEL)
	m.set_shader_parameter("burst", 1.0 if is_burst else 0.0)
	g.material = m
	g.z_index = 0   # на земле — под бойцами и постройками
	parent.add_child(g)
	g.global_position = at
	g._update(0.0)
	return g


# Снять плавно: гаснет за FADE_OUT и освобождается сам
func dismiss() -> void:
	if _dismiss_left < 0.0:
		_dismiss_left = FADE_OUT

func _process(delta: float) -> void:
	_update(delta)

func _update(delta: float) -> void:
	_time += delta
	_age += delta
	var a := clampf(_age / FADE_IN, 0.0, 1.0)
	if _burst:
		a = 1.0
		if _age >= BURST_TIME:
			queue_free()
			return
		material.set_shader_parameter("progress", _age / BURST_TIME)
	if _dismiss_left >= 0.0:
		_dismiss_left -= delta
		if _dismiss_left <= 0.0:
			queue_free()
			return
		a *= _dismiss_left / FADE_OUT
	material.set_shader_parameter("time", _time)
	material.set_shader_parameter("alpha", a)
