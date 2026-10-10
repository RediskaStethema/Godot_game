class_name Building
extends Node2D

# Здание игрока на клетке королевства. Параметры — из CardData.building_stats,
# вид — блоки лунного тайлсета в полклетки (как у Citadel).
# Здания неуязвимы и стоят между раундами (BattleManager.player_buildings).
# Тикает BattleManager (FIXED_TICK) во время боя.
#   tower — турель: бьёт ближайшего врага в радиусе
#   wall  — стена: щит цитадели на каждый бой + замедляет врагов рядом

const BLOCK_SCALE: float = 0.5
# Блоки по building_type: [Tiles/Slice N, i, j, ярус]; (i, j) — подклетка 2×2,
# 0.5 — центр клетки. Порядок — от дальних к ближним, снизу вверх.
const BLOCKS = {
	"tower": [[30, 0.5, 0.5, 1], [30, 0.5, 0.5, 2], [31, 0.5, 0.5, 3]],
	"wall":  [[12, 0, 1, 1], [12, 1, 0, 1]],   # низкая стена поперёк клетки
}
const TOWER_LEVELS: int = 3
const BARREL_LENGTH: float = 26.0
const BARREL_COLOR = Color("1b1f24")
const SHOT_SHOW_TIME: float = 0.15
const SHOT_COLOR = Color(1.0, 0.8, 0.4)
const SLOW_AURA_COLOR = Color(0.45, 0.65, 0.95, 0.05)
const SLOW_AURA_LINE = Color(0.45, 0.65, 0.95, 0.30)

var card: CardData
var tile: Vector2i
var building_type: String
var stats: Dictionary

var attack_timer: float = 0.0
var shot_timer: float = 0.0
var shot_target: Vector2 = Vector2.ZERO   # глобальные координаты
var aim: Vector2 = Vector2(1, 0.5)        # куда смотрит ствол (к врагу по умолчанию)

func setup(building_card: CardData, grid_tile: Vector2i) -> void:
	card = building_card
	tile = grid_tile
	building_type = card.building_type
	stats = card.building_stats
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

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
		if shot_timer > Soldier.TIMER_EPSILON:
			var a = shot_timer / SHOT_SHOW_TIME
			draw_line(muzzle + aim.normalized() * BARREL_LENGTH, to_local(shot_target), Color(SHOT_COLOR, a), 2.0, true)

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
	if building_type != "tower":
		return
	if shot_timer > Soldier.TIMER_EPSILON:
		shot_timer -= delta
		queue_redraw()
	attack_timer -= delta
	if attack_timer > Soldier.TIMER_EPSILON:
		return
	var target = _find_target(stats.get("attack_range", 0.0))
	if target == null:
		return
	attack_timer = 1.0 / stats.get("attack_speed", 1.0)
	target.take_damage(stats.get("damage", 0.0))
	shot_target = target.global_position + Vector2(0, -Soldier.TARGET_SPRITE_HEIGHT / 2.0)
	aim = shot_target - global_position
	shot_timer = SHOT_SHOW_TIME
	queue_redraw()

func _find_target(attack_range: float) -> Soldier:
	var best: Soldier = null
	var best_dist: float = attack_range
	for e in SoldierRegistry.get_alive_soldiers_of_team(GameConstants.TEAM_ENEMY):
		var d = global_position.distance_to(e.global_position)
		if d <= best_dist:
			best_dist = d
			best = e
	return best

# Щит цитадели, который даёт здание на каждый бой
func get_citadel_shield() -> float:
	return stats.get("shield", 0.0)

# Множитель скорости врага в точке: самая сильная аура замедления стен рядом
static func slow_mult_at(point: Vector2) -> float:
	var mult: float = 1.0
	for b in BattleManager.buildings:
		if not is_instance_valid(b):
			continue
		var r = b.stats.get("slow_radius", 0.0)
		if r > 0.0 and point.distance_to(b.global_position) <= r:
			mult = minf(mult, b.stats.get("slow_mult", 1.0))
	return mult
