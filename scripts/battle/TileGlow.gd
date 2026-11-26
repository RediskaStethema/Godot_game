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

const SHADER: Shader = preload("res://shaders/tile_glow.gdshader")

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
	if _white == null:
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
	m.shader = SHADER
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
