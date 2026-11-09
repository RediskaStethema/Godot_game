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

static var layer: ProjectileTrail = null

var _tracers: Dictionary = {}   # id снаряда → {"color", "pts": [[точка, возраст]]}
var _smoke: Array = []          # [точка, возраст]
var _emit: Dictionary = {}      # id снаряда → сек до следующего клуба
var _smoke_node: Node2D

func _ready() -> void:
	layer = self
	process_priority = 1
	z_index = 9   # под снарядами (10), над бойцами
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = add
	_smoke_node = Node2D.new()
	_smoke_node.use_parent_material = false
	_smoke_node.material = CanvasItemMaterial.new()   # обычное смешение — дым темнит
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
	for p in BattleManager.projectiles:
		if not is_instance_valid(p) or p.finished:
			continue
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

func _draw() -> void:
	for id in _tracers:
		var tr: Dictionary = _tracers[id]
		var pts: Array = tr["pts"]
		var n := pts.size()
		for i in range(1, n):
			var k := float(i) / (n - 1)   # 0 — хвост, 1 — голова
			draw_line(pts[i - 1][0], pts[i][0], Color(tr["color"], 0.9 * k), maxf(TRACER_WIDTH * k, 0.5), true)

func _draw_smoke() -> void:
	for pt in _smoke:
		var t: float = pt[1] / SMOKE_LIFE
		var r := SMOKE_R * lerpf(1.0, SMOKE_GROW, t)
		_smoke_node.draw_circle(pt[0] + Vector2(0.0, -3.0 * t), r, Color(Palette.DUST_PALE, 0.32 * (1.0 - t)))
