class_name Building
extends Node2D

# Здание игрока на клетке королевства. Параметры — из CardData.building_stats,
# вид — блоки лунного тайлсета в полклетки (как у Citadel).
# Здания неуязвимы и стоят между раундами (BattleManager.player_buildings).
# Тикает BattleManager (FIXED_TICK) во время боя.
#   tower — турель: бьёт ближайшего врага в радиусе
#   artillery — орудие игрока: клик по полю в бою (BattleScene) → fire_at, залп по
#           площади только по врагам, перезарядка cooldown (готово в начале боя)
#   wall  — стена: щит цитадели на каждый бой + замедляет врагов рядом
#           (статус slowed без стаков, держится WALL_SLOW_LINGER после выхода из радиуса)

const BLOCK_SCALE: float = 0.5
# Блоки по building_type: [Tiles/Slice N, i, j, ярус]; (i, j) — подклетка 2×2,
# 0.5 — центр клетки. Порядок — от дальних к ближним, снизу вверх.
const BLOCKS = {
	"tower": [[30, 0.5, 0.5, 1], [30, 0.5, 0.5, 2], [31, 0.5, 0.5, 3]],
	"wall":  [[12, 0, 1, 1], [12, 1, 0, 1]],   # низкая стена поперёк клетки
	"artillery": [[30, 0.5, 0.5, 1], [31, 0.5, 0.5, 2]],   # приземистая башня с длинным стволом
}
const ARTILLERY_LEVELS: int = 2
const ARTILLERY_BARREL_LENGTH: float = 40.0
const ARTILLERY_PROJECTILE: String = "rocket"
const ARTILLERY_ARC: float = 90.0          # px — высота дуги полёта ракеты (только вид)
const ARTILLERY_IMPACT_VFX = ["explosion", "fireball", "impact"]   # по порядку: огонь поверх дыма
const RECOIL_DISTANCE: float = 12.0        # px — откат ствола при залпе
const RECOIL_TIME: float = 0.35
const EXPLOSION_SHAKE: float = 6.0         # px — тряска камеры от взрыва залпа
const EXPLOSION_COLOR = Color(1.0, 0.6, 0.2, 0.45)
const EXPLOSION_SHOW_TIME: float = 0.3   # сек видна вспышка взрыва (таймер дерева — только вид)
const TOWER_LEVELS: int = 3
const BARREL_LENGTH: float = 26.0
const BARREL_COLOR = Color("1b1f24")
const SHOT_PROJECTILE: String = "spark"   # снаряд турели (Projectile.EFFECTS), урон — при попадании
const WALL_SLOW_LINGER: float = 0.5        # сек замедления после выхода из ауры стены
const SLOW_AURA_COLOR = Color(0.45, 0.65, 0.95, 0.05)
const SLOW_AURA_LINE = Color(0.45, 0.65, 0.95, 0.30)
# Уровень здания — ромбики над ним (1-й уровень без отметки)
const LEVEL_PIP_SIZE: float = 5.0
const LEVEL_PIP_GAP: float = 14.0
const LEVEL_PIP_COLOR = Color(1.0, 0.82, 0.35)

var card: CardData
var tile: Vector2i
var building_type: String
var stats: Dictionary

var attack_timer: float = 0.0
var aim: Vector2 = Vector2(1, 0.5)        # куда смотрит ствол (к врагу по умолчанию)
var cooldown_left: float = 0.0            # орудие: сек до готовности (0 — готово)
var _explosion_point: Vector2             # орудие: где показать вспышку взрыва
var _explosion_id: int = 0
var _recoil: float = 0.0                  # орудие: 1 — ствол откачен, гаснет к 0 (только вид)

func setup(building_card: CardData, grid_tile: Vector2i) -> void:
	card = building_card
	tile = grid_tile
	building_type = card.building_type
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	refresh_stats()

# Статы по уровню карты (после улучшения — пересчитать)
func refresh_stats() -> void:
	stats = Chapters.apply_building_stats(card.get_building_stats(), RunManager.player_chapter)
	queue_redraw()

# -------------------------------------------------------
# ВИД
# -------------------------------------------------------
func _draw() -> void:
	if building_type == "wall" and stats.get("slow_radius", 0.0) > 0.0:
		draw_circle(Vector2.ZERO, stats["slow_radius"], SLOW_AURA_COLOR)
		draw_arc(Vector2.ZERO, stats["slow_radius"], 0.0, TAU, 48, SLOW_AURA_LINE, 1.5, true)
	for b in BLOCKS.get(building_type, []):
		TerrainTiles.draw_block(self, TerrainTiles.tile(b[0]), _block_top(b[1], b[2], b[3]), Color.WHITE, BLOCK_SCALE)
	if building_type == "tower":
		var muzzle = _block_top(0.5, 0.5, TOWER_LEVELS)
		draw_line(muzzle, muzzle + aim.normalized() * BARREL_LENGTH, BARREL_COLOR, 6.0)
	if building_type == "artillery":
		var dir = aim.normalized()
		var base = _block_top(0.5, 0.5, ARTILLERY_LEVELS) - dir * RECOIL_DISTANCE * _recoil
		draw_line(base, base + dir * ARTILLERY_BARREL_LENGTH, BARREL_COLOR, 8.0)
		if _explosion_id > 0:
			draw_circle(to_local(_explosion_point), stats.get("splash_radius", 0.0), EXPLOSION_COLOR)
	_draw_level_pips()

func _draw_level_pips() -> void:
	if card.building_level <= 1:
		return
	var top = get_occlusion_rect().position.y - global_position.y - LEVEL_PIP_SIZE * 2.0
	var x0 = -LEVEL_PIP_GAP * (card.building_level - 1) / 2.0
	for i in range(card.building_level):
		var c = Vector2(x0 + i * LEVEL_PIP_GAP, top)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -LEVEL_PIP_SIZE), c + Vector2(LEVEL_PIP_SIZE, 0),
			c + Vector2(0, LEVEL_PIP_SIZE), c + Vector2(-LEVEL_PIP_SIZE, 0)]), LEVEL_PIP_COLOR)

# Центр верхней грани блока подклетки (i, j) на ярусе level
func _block_top(i: float, j: float, level: int) -> Vector2:
	var sub = Vector2(IsoGrid.TILE_WIDTH, IsoGrid.TILE_HEIGHT) * BLOCK_SCALE / 2.0
	return Vector2((i - j) * sub.x, (i + j - 1) * sub.y) - Vector2(0, TerrainTiles.LEVEL_HEIGHT * BLOCK_SCALE * level)

# Область экрана (мировые координаты), которую закрывают блоки здания —
# OcclusionFader делает здание полупрозрачным, если за ним стоит боец
func get_occlusion_rect() -> Rect2:
	var rect = Rect2()
	for b in BLOCKS.get(building_type, []):
		var r = TerrainTiles.block_rect(_block_top(b[1], b[2], b[3]), BLOCK_SCALE)
		rect = r if rect.size == Vector2.ZERO else rect.merge(r)
	return Rect2(rect.position + global_position, rect.size)

# -------------------------------------------------------
# БОЙ
# -------------------------------------------------------
func tick(delta: float) -> void:
	if building_type == "artillery":
		cooldown_left = maxf(cooldown_left - delta, 0.0)
		return
	if building_type == "wall":
		_tick_slow_aura()
		return
	if building_type != "tower":
		return
	attack_timer -= delta
	if attack_timer > Soldier.TIMER_EPSILON:
		return
	var target = _find_target(stats.get("attack_range", 0.0))
	if target == null:
		return
	attack_timer = 1.0 / stats.get("attack_speed", 1.0)
	var aim_offset = Vector2(0, -Soldier.TARGET_SPRITE_HEIGHT / 2.0)
	aim = target.global_position + aim_offset - global_position
	queue_redraw()
	var barrel_end = to_global(_block_top(0.5, 0.5, TOWER_LEVELS) + aim.normalized() * BARREL_LENGTH)
	var shot = Projectile.launch(get_parent(), SHOT_PROJECTILE, barrel_end, target, aim_offset)
	shot.damage = stats.get("damage", 0.0)

func _find_target(attack_range: float) -> Soldier:
	var best: Soldier = null
	var best_dist: float = attack_range
	for e in SoldierRegistry.get_alive_soldiers_of_team(GameConstants.TEAM_ENEMY):
		var d = global_position.distance_to(e.global_position)
		if d <= best_dist:
			best_dist = d
			best = e
	return best

# -------------------------------------------------------
# ОРУДИЕ ИГРОКА (artillery)
# -------------------------------------------------------
func is_artillery_ready() -> bool:
	return building_type == "artillery" and cooldown_left <= Soldier.TIMER_EPSILON

# Залп в точку поля (мировые координаты): снаряд из ствола, взрыв по площади
# при попадании — только враги. false — не орудие или перезаряжается.
func fire_at(point: Vector2) -> bool:
	if not is_artillery_ready():
		return false
	cooldown_left = stats.get("cooldown", 1.0)
	aim = point - global_position
	queue_redraw()
	var base = _block_top(0.5, 0.5, ARTILLERY_LEVELS)
	var muzzle = to_global(base + aim.normalized() * ARTILLERY_BARREL_LENGTH)
	var shot = Projectile.launch(get_parent(), ARTILLERY_PROJECTILE, muzzle, null, point)
	shot.damage = stats.get("damage", 0.0)
	shot.splash_radius = stats.get("splash_radius", 0.0)
	shot.splash_team = GameConstants.TEAM_ENEMY
	shot.on_impact = _show_explosion
	shot.impact_vfx = ARTILLERY_IMPACT_VFX
	shot.arc_height = ARTILLERY_ARC
	_play_fire_animation(muzzle)
	return true

# Только вид: вспышка и дым из ствола, ствол откатывается и возвращается
func _play_fire_animation(muzzle: Vector2) -> void:
	Vfx.spawn(get_parent(), "muzzle_flash", muzzle)
	Vfx.spawn(get_parent(), "muzzle_smoke", muzzle)
	if not is_inside_tree():
		return
	create_tween().tween_method(_set_recoil, 1.0, 0.0, RECOIL_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _set_recoil(value: float) -> void:
	_recoil = value
	queue_redraw()

# Только вид: вспышка на месте взрыва гаснет по таймеру дерева
func _show_explosion(point: Vector2) -> void:
	if not is_inside_tree():
		return
	_explosion_point = point
	_explosion_id += 1
	var camera = get_viewport().get_camera_2d()
	if camera and camera.has_method("shake"):
		camera.shake(EXPLOSION_SHAKE)
	var id := _explosion_id
	queue_redraw()
	get_tree().create_timer(EXPLOSION_SHOW_TIME, false).timeout.connect(func():
		if is_instance_valid(self) and _explosion_id == id:
			_explosion_id = 0
			queue_redraw())

# Щит цитадели, который даёт здание на каждый бой
func get_citadel_shield() -> float:
	return stats.get("shield", 0.0)

# Аура стены: врагам в радиусе — slowed силой 1 − slow_mult (×0.6 → 0.4), без стаков
func _tick_slow_aura() -> void:
	var r = stats.get("slow_radius", 0.0)
	if r <= 0.0:
		return
	var power = 1.0 - stats.get("slow_mult", 1.0)
	for e in SoldierRegistry.get_alive_soldiers_of_team(GameConstants.TEAM_ENEMY):
		if global_position.distance_to(e.global_position) <= r:
			e.apply_status(StatusEffects.SLOWED, power, WALL_SLOW_LINGER, false)
