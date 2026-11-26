class_name VoidFx
extends Node2D

# Пустота за краем помоста (решение пользователя 18.11.2026): вокруг пола — далёкие тлеющие огни и медленный дым, чтобы
# за стеной не было ровной черноты и поле читалось поднятым над чем-то. Один узел позади пола, один _draw; ADD-пятна
# мерцают каждое своим ритмом, дым — крупные тусклые пятна, дрейфуют. Только вид; выключается GameSettings.atmosphere.

const SPECKS: int = 34
const SMOKES: int = 9
const OUT_MIN: float = 3.0          # клеток от края пола
const OUT_MAX: float = 10.0
const SPECK_ALPHA: float = 0.5
const SMOKE_ALPHA: float = 0.1
const SPECK_COLOR = Color(1.0, 0.55, 0.22)
const SMOKE_COLOR = Color(0.35, 0.28, 0.33)

static var _tex: GradientTexture2D

var _specks: Array = []    # [точка, радиус, фаза, скорость]
var _smokes: Array = []    # [точка, радиус, фаза]
var _t: float = 0.0

func setup(grid: IsoGrid, pad: int, seed_value: int) -> void:
	show_behind_parent = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	material = Vfx.soft_add_material()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var u0 := -pad - 0.5
	var v0 := -pad - 0.5
	var u1 := grid.get_layout_cols() + pad - 0.5
	var v1 := grid.get_layout_rows() + pad - 0.5
	for i in SPECKS + SMOKES:
		var p := _outside(rng, u0, v0, u1, v1)
		var s := grid.lattice_to_screen(p.x, p.y)
		if i < SPECKS:
			_specks.append([s, rng.randf_range(10.0, 26.0), rng.randf() * TAU, rng.randf_range(0.6, 1.6)])
		else:
			_smokes.append([s, rng.randf_range(90.0, 180.0), rng.randf() * TAU])
	_ensure_tex()

# Точка решётки за краем пола: кольцо шириной OUT_MIN..OUT_MAX клеток
static func _outside(rng: RandomNumberGenerator, u0: float, v0: float, u1: float, v1: float) -> Vector2:
	var d := rng.randf_range(OUT_MIN, OUT_MAX)
	var side := rng.randi() % 4
	var u := rng.randf_range(u0 - d, u1 + d)
	var v := rng.randf_range(v0 - d, v1 + d)
	match side:
		0: u = u0 - d
		1: u = u1 + d
		2: v = v0 - d
		_: v = v1 + d
	return Vector2(u, v)

static func _ensure_tex() -> void:
	if _tex != null:
		return
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	_tex = GradientTexture2D.new()
	_tex.gradient = g
	_tex.fill = GradientTexture2D.FILL_RADIAL
	_tex.fill_from = Vector2(0.5, 0.5)
	_tex.fill_to = Vector2(1.0, 0.5)
	_tex.width = 64
	_tex.height = 64

func _process(delta: float) -> void:
	if not GameSettings.atmosphere:
		visible = false
		return
	visible = true
	_t += delta
	queue_redraw()

func _draw() -> void:
	if _tex == null:
		return
	for s in _smokes:
		var k: float = 0.7 + 0.3 * sin(_t * 0.15 + s[2])
		var r: float = s[1]
		var at: Vector2 = s[0] + Vector2(sin(_t * 0.05 + s[2]) * 20.0, 0.0)
		draw_texture_rect(_tex, Rect2(at - Vector2(r, r * 0.5), Vector2(r, r * 0.5) * 2.0), false, Color(SMOKE_COLOR, SMOKE_ALPHA * k))
	for s in _specks:
		var flick: float = 0.55 + 0.45 * sin(_t * s[3] * 3.0 + s[2]) * sin(_t * s[3] * 1.3 + s[2] * 2.0)
		var r: float = s[1]
		draw_texture_rect(_tex, Rect2(s[0] - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(SPECK_COLOR, SPECK_ALPHA * clampf(flick, 0.1, 1.0)))
