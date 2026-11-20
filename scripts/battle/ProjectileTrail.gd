class_name ProjectileTrail
extends Node2D

# След снарядов (решение пользователя 08.11.2026, только вид): болты, лучи, искры — короткий светящийся трассер
# в цвет вспышки стрелка (ADD, сужается к хвосту); ракета и огненный шар — дымный след из клубов, оседают и тают
# (и после разрыва). Один слой на поле (BattleScene._build_field, ProjectileTrail.layer): раз в кадр после снарядов
# (process_priority 1) обходит BattleManager.projectiles и рисует всё одним узлом — узел на снаряд стоил ~17 FPS
# в худшем бою (126 снарядов). Вид по снаряду — Projectile.TRAILS; трассер — этот узел (ADD), дым — дочерний

const TRACER_LIFE: float = 0.09     # сек: длина трассера во времени
const TRACER_WIDTH: float = 2.2
const SMOKE_EVERY: float = 0.03
const SMOKE_LIFE: float = 0.5
const SMOKE_R: float = 3.0
const SMOKE_GROW: float = 2.4
const MAX_SMOKE: int = 160
const SHADOW_R: float = 7.0         # радиус тени снаряда по дуге у земли (px мира), овал 2:1
const SHADOW_ALPHA: float = 0.32

static var layer: ProjectileTrail = null

var _tracers: Dictionary = {}   # id снаряда → {"color", "pts": [[точка, возраст]]}
var _smoke: Array = []          # [точка, возраст]
var _emit: Dictionary = {}      # id снаряда → сек до следующего клуба
var _smoke_node: Node2D
var _shadow_node: Node2D
var _shadows: Array = []        # [точка на земле, 0..1 высота дуги] — на этот кадр

func _ready() -> void:
	layer = self
	process_priority = 1
	z_index = 9   # под снарядами (10), над бойцами
	material = Vfx.add_material()   # пиксельный ADD
	_shadow_node = Node2D.new()
	_shadow_node.z_index = -9   # абсолютный z 0 — на земле вместе с бойцами, не над снарядами (слой трассера z 9)
	_shadow_node.use_parent_material = false
	_shadow_node.material = Vfx.soft_mix_material()
	_shadow_node.draw.connect(_draw_shadows)
	add_child(_shadow_node)
	_smoke_node = Node2D.new()
	_smoke_node.use_parent_material = false
	_smoke_node.material = Vfx.mix_material()   # обычное смешение — дым темнит; пиксельный
	_smoke_node.draw.connect(_draw_smoke)
	add_child(_smoke_node)

func _exit_tree() -> void:
	if layer == self:
		layer = null

# Есть ли трассер у снаряда (тесты)
func has_trail(p: Node2D) -> bool:
	return _tracers.has(p.get_instance_id()) or _emit.has(p.get_instance_id())

func _process(delta: float) -> void:
	var live := {}
	_shadows.clear()
	for p in BattleManager.projectiles:
		if not is_instance_valid(p) or p.finished:
			continue
		if p.arc_height > 0.0 and p.visible and p._lift > 0.0:   # снаряд по дуге — овал на земле под ним
			var lift: float = p._lift
			var high := clampf(lift / (p.arc_height * 1.0), 0.0, 1.0)   # 1 — в верхней точке дуги
			_shadows.append([to_local(p.global_position + Vector2(0.0, lift)), high])
		var kind: String = Projectile.TRAILS.get(p._kind, "")
		if kind == "":
			continue
		var id: int = p.get_instance_id()
		live[id] = true
		if not p.visible:
			continue
		var at := to_local(p.global_position)
		if kind == "tracer":
			if not _tracers.has(id):
				_tracers[id] = {"color": p.light_color, "pts": []}
			_tracers[id]["pts"].append([at, 0.0])
		else:
			_emit[id] = _emit.get(id, 0.0) - delta
			if _emit[id] <= 0.0 and _smoke.size() < MAX_SMOKE:
				_emit[id] = SMOKE_EVERY
				_smoke.append([at, 0.0])
	# возраст и уборка: трассер гаснет вместе со снарядом, дым — сам
	for id in _tracers.keys():
		if not live.has(id):
			_tracers.erase(id)
			continue
		var pts: Array = _tracers[id]["pts"]
		for pt in pts:
			pt[1] += delta
		_tracers[id]["pts"] = pts.filter(func(pt): return pt[1] < TRACER_LIFE)
	for id in _emit.keys():
		if not live.has(id):
			_emit.erase(id)
	for pt in _smoke:
		pt[1] += delta
	_smoke = _smoke.filter(func(pt): return pt[1] < SMOKE_LIFE)
	queue_redraw()
	_smoke_node.queue_redraw()
	_shadow_node.queue_redraw()

func _draw() -> void:
	for id in _tracers:
		var tr: Dictionary = _tracers[id]
		var pts: Array = tr["pts"]
		var n := pts.size()
		for i in range(1, n):
			var k := float(i) / (n - 1)   # 0 — хвост, 1 — голова
			draw_line(pts[i - 1][0], pts[i][0], Color(tr["color"], 0.9 * k), maxf(TRACER_WIDTH * k, 0.5), true)

# Тень снаряда по дуге: мягкий овал 2:1 на земле; выше снаряд — тень меньше и бледнее (мягкий материал, без грубой сетки)
func _draw_shadows() -> void:
	for sh in _shadows:
		var high: float = sh[1]
		var r := lerpf(SHADOW_R, SHADOW_R * 0.55, high)
		var a := lerpf(SHADOW_ALPHA, SHADOW_ALPHA * 0.45, high)
		_shadow_node.draw_set_transform(sh[0], 0.0, Vector2(1.0, 0.5))
		_shadow_node.draw_circle(Vector2.ZERO, r, Color(0.0, 0.0, 0.0, a))
		_shadow_node.draw_circle(Vector2.ZERO, r * 0.6, Color(0.0, 0.0, 0.0, a * 0.7))
	_shadow_node.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_smoke() -> void:
	for pt in _smoke:
		var t: float = pt[1] / SMOKE_LIFE
		var r := SMOKE_R * lerpf(1.0, SMOKE_GROW, t)
		_smoke_node.draw_circle(pt[0] + Vector2(0.0, -3.0 * t), r, Color(Palette.DUST_PALE, 0.32 * (1.0 - t)))
