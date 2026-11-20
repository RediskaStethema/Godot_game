extends Control

# Космос за главным меню (решение пользователя 06.11.2026: «в главном меню сияют звёзды, меню — на фоне космоса»):
# звёзды мерцают каждая в своём ритме (пиксельные квадраты 1–3 px, крупные — с лучиками), изредка пролетает
# метеор. Справа звёзды гаснут к сцене с башней (mask_node: от её левого края на fade_width) — у сцены свой
# космос со своими звёздами. Только вид, своё время; раскладка — от SEED (одна и та же при каждом входе).

const SEED: int = 4017
const DENSITY: float = 0.00024          # звёзд на px² экрана (08.11.2026, образец exampel.png: реже — было 0.00042)
const TWINKLE_SPEED = Vector2(0.25, 1.4)   # Гц — разброс скорости мерцания
const TWINKLE_DEPTH: float = 0.55       # насколько гаснет в минимуме (доля яркости)
const BIG_SHARE: float = 0.06           # доля крупных звёзд с лучиками
const MID_SHARE: float = 0.22           # доля звёзд 2 px
const GLINT_LEN = Vector2(4.0, 9.0)     # px — длина лучиков крупной звезды
const METEOR_EVERY = Vector2(6.0, 14.0) # с — пауза между метеорами
const METEOR_TIME: float = 0.9          # с — пролёт
const METEOR_LEN: float = 90.0          # px — хвост
const METEOR_SPEED: float = 520.0       # px/с

var mask_node: Control = null           # сцена справа: звёзды гаснут к её левому краю
var fade_width: float = 220.0

var _stars: Array = []                  # [pos (доли), size, base, speed, phase, color]
var _time: float = 0.0
var _rng := RandomNumberGenerator.new()
var _meteor_wait: float = 3.0
var _meteor_t: float = -1.0
var _meteor_from := Vector2.ZERO
var _meteor_dir := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	material = Vfx.mix_material()   # мерцание и хвост метеора — ступенями с дизерингом (стилизация 12.11.2026)
	_rng.seed = SEED
	resized.connect(_build)
	_build()

func _build() -> void:
	_stars.clear()
	var r := RandomNumberGenerator.new()
	r.seed = SEED
	var count := int(maxf(size.x * size.y, 1152.0 * 648.0) * DENSITY)
	var colors := [Palette.STAR_WHITE, Palette.STAR_WHITE, Palette.STAR_BLUE, Palette.STAR_AMBER]
	for i in count:
		var roll := r.randf()
		var px := 3.0 if roll < BIG_SHARE else (2.0 if roll < BIG_SHARE + MID_SHARE else 1.0)
		_stars.append([Vector2(r.randf(), r.randf()), px, r.randf_range(0.35, 1.0) if px < 3.0 else 1.0,
			r.randf_range(TWINKLE_SPEED.x, TWINKLE_SPEED.y), r.randf() * TAU, colors[r.randi() % colors.size()],
			r.randf_range(GLINT_LEN.x, GLINT_LEN.y)])

func _process(delta: float) -> void:
	_time += delta
	if _meteor_t >= 0.0:
		_meteor_t += delta
		if _meteor_t > METEOR_TIME:
			_meteor_t = -1.0
	else:
		_meteor_wait -= delta
		if _meteor_wait <= 0.0:
			_meteor_wait = _rng.randf_range(METEOR_EVERY.x, METEOR_EVERY.y)
			_meteor_t = 0.0
			_meteor_from = Vector2(_rng.randf_range(0.05, 0.6) * _limit_x(), _rng.randf_range(0.03, 0.4) * size.y)
			_meteor_dir = Vector2(1.0, _rng.randf_range(0.25, 0.6)).normalized()
	queue_redraw()

# Правая граница звёзд — левый край сцены с башней (+ полоса затухания)
func _limit_x() -> float:
	if is_instance_valid(mask_node):
		return mask_node.global_position.x - global_position.x + fade_width
	return size.x

func _fade_at(x: float) -> float:
	if not is_instance_valid(mask_node):
		return 1.0
	var left := mask_node.global_position.x - global_position.x
	return clampf(1.0 - (x - left) / fade_width, 0.0, 1.0)

func _draw() -> void:
	var limit := _limit_x()
	for s in _stars:
		var p: Vector2 = (s[0] as Vector2) * size
		if p.x > limit:
			continue
		var tw := 1.0 - TWINKLE_DEPTH * (0.5 + 0.5 * sin(_time * TAU * s[3] + s[4]))
		var a: float = s[2] * tw * _fade_at(p.x)
		if a <= 0.02:
			continue
		var c := Color(s[5], a)
		var px: float = s[1]
		var at := p.floor()
		draw_rect(Rect2(at - Vector2(px, px) * 0.5, Vector2(px, px)), c)
		if px >= 3.0:   # лучики крупной звезды — длиннее на пике мерцания
			var l: float = s[6] * tw
			var g := Color(s[5], a * 0.45)
			draw_line(at + Vector2(-l, 0), at + Vector2(l, 0), g, 1.0)
			draw_line(at + Vector2(0, -l), at + Vector2(0, l), g, 1.0)
	if _meteor_t >= 0.0:
		var k := _meteor_t / METEOR_TIME
		var head := _meteor_from + _meteor_dir * METEOR_SPEED * _meteor_t
		var fade := sin(k * PI) * _fade_at(head.x)
		var steps := 12
		for i in steps:   # хвост — отрезки с убывающей яркостью
			var a0 := float(i) / steps
			var a1 := float(i + 1) / steps
			draw_line(head - _meteor_dir * METEOR_LEN * a0, head - _meteor_dir * METEOR_LEN * a1,
				Color(Palette.STAR_WHITE, fade * (1.0 - a0) * 0.8), 1.5 if i < 3 else 1.0)
