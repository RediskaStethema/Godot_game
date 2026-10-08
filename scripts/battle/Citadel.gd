class_name Citadel
extends Node2D

# Цитадель игрока — башня из блоков лунного тайлсета на клетке IsoGrid.citadel_tile.
# Позиция узла = центр клетки (верх пола), башня растёт вверх.
# HP хранится в BattleManager.citadel_hp (живёт весь забег).
# Во время штурма (армия игрока пала) цитадель — боевая сторона: бьёт из
# орудия по площади ближайшего врага в радиусе, враги бьют её своими атаками.
# Тикает BattleManager (FIXED_TICK), только при siege_started.

# Крепость из блоков в полклетки: клетка делится на 2×2 подклетки (i, j).
# Спереди — стены в один ярус, на задней подклетке (0, 0) — донжон.
# Блок: [Tiles/Slice N, i, j, ярус (1 — стоит на полу)]
const BLOCK_SCALE: float = 0.5
const WALL = 12
const KEEP = 13
const KEEP_LEVELS: int = 3
const BLOCKS = [
	[KEEP, 0, 0, 1], [KEEP, 0, 0, 2], [KEEP, 0, 0, 3],
	[WALL, 0, 1, 1], [WALL, 1, 0, 1], [WALL, 1, 1, 1],
]
const HP_BAR_SIZE = Vector2(90, 7)
const HP_BAR_GAP: float = 14.0
const SHIELD_BAR_HEIGHT: float = 4.0
const SHIELD_COLOR = Color(0.45, 0.7, 1.0)
# Враг атакует цитадель, когда до её центра не больше его дальности + HIT_RADIUS
const HIT_RADIUS: float = 50.0
const FLASH_COLOR = Color(1.0, 0.45, 0.4)

# --- Орудие цитадели ---
const DAMAGE: float = 30.0          # каждому врагу в радиусе взрыва
const ATTACK_SPEED: float = 1.0     # выстрелов в секунду
const ATTACK_RANGE: float = 320.0   # пиксели от центра цитадели
const SPLASH_RADIUS: float = 80.0   # радиус взрыва вокруг цели
const SHOT_SHOW_TIME: float = 0.2   # сколько секунд виден след выстрела
const SHOT_COLOR = Color(1.0, 0.85, 0.45)

var attack_timer: float = 0.0
var shot_timer: float = 0.0
var shot_target: Vector2 = Vector2.ZERO   # в глобальных координатах

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	BattleManager.citadel_hp_changed.connect(_on_hp_changed)

func _exit_tree() -> void:
	if BattleManager.citadel == self:
		BattleManager.citadel = null

func _draw() -> void:
	# BLOCKS уже упорядочены от дальних подклеток к ближним, внутри — снизу вверх
	for b in BLOCKS:
		TerrainTiles.draw_block(self, TerrainTiles.tile(b[0]), _block_top(b[1], b[2], b[3]), Color.WHITE, BLOCK_SCALE)
	_draw_hp_bar()
	if shot_timer > Soldier.TIMER_EPSILON:
		var a = shot_timer / SHOT_SHOW_TIME
		var to = to_local(shot_target)
		draw_line(_muzzle(), to, Color(SHOT_COLOR, a), 3.0, true)
		draw_circle(to, SPLASH_RADIUS * 0.5, Color(SHOT_COLOR, 0.35 * a))
		draw_arc(to, SPLASH_RADIUS, 0.0, TAU, 32, Color(SHOT_COLOR, 0.6 * a), 2.0, true)

# Откуда вылетает выстрел — верх донжона
func _muzzle() -> Vector2:
	return Vector2(0, _top_y() + 6.0)

# Центр верхней грани блока подклетки (i, j) на ярусе level
func _block_top(i: int, j: int, level: int) -> Vector2:
	var sub = Vector2(IsoGrid.TILE_WIDTH, IsoGrid.TILE_HEIGHT) * BLOCK_SCALE / 2.0
	return Vector2((i - j) * sub.x, (i + j - 1) * sub.y) - Vector2(0, TerrainTiles.LEVEL_HEIGHT * BLOCK_SCALE * level)

# Верхняя точка донжона
func _top_y() -> float:
	return _block_top(0, 0, KEEP_LEVELS).y - IsoGrid.TILE_HEIGHT * BLOCK_SCALE / 2.0

func _draw_hp_bar() -> void:
	var rect = Rect2(Vector2(-HP_BAR_SIZE.x / 2.0, _top_y() - HP_BAR_GAP - HP_BAR_SIZE.y), HP_BAR_SIZE)
	draw_rect(rect.grow(1.5), Color(0, 0, 0, 0.8))
	var ratio = clampf(float(BattleManager.citadel_hp) / BattleManager.CITADEL_MAX_HP, 0.0, 1.0)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * ratio, rect.size.y)), UITheme.GOLD)
	# Щит от стен — синяя полоска над HP (доля от максимального HP)
	if BattleManager.citadel_shield > 0.0:
		var srect = Rect2(rect.position - Vector2(0, SHIELD_BAR_HEIGHT + 3.0), Vector2(rect.size.x, SHIELD_BAR_HEIGHT))
		draw_rect(srect.grow(1.0), Color(0, 0, 0, 0.8))
		var sratio = clampf(BattleManager.citadel_shield / BattleManager.CITADEL_MAX_HP, 0.0, 1.0)
		draw_rect(Rect2(srect.position, Vector2(srect.size.x * sratio, srect.size.y)), SHIELD_COLOR)

# -------------------------------------------------------
# БОЙ (штурм)
# -------------------------------------------------------
func tick(delta: float) -> void:
	if shot_timer > Soldier.TIMER_EPSILON:
		shot_timer -= delta
		queue_redraw()
	attack_timer -= delta
	if attack_timer > Soldier.TIMER_EPSILON:
		return
	var target = _find_target()
	if target == null:
		return
	attack_timer = 1.0 / ATTACK_SPEED
	_fire_at(target.global_position)

# Ближайший враг в радиусе орудия
func _find_target() -> Soldier:
	var best: Soldier = null
	var best_dist: float = ATTACK_RANGE
	for e in SoldierRegistry.get_alive_soldiers_of_team(GameConstants.TEAM_ENEMY):
		var d = global_position.distance_to(e.global_position)
		if d <= best_dist:
			best_dist = d
			best = e
	return best

# Взрыв: урон всем врагам в SPLASH_RADIUS от точки попадания
func _fire_at(point: Vector2) -> void:
	for e in SoldierRegistry.get_alive_soldiers_of_team(GameConstants.TEAM_ENEMY):
		if e.global_position.distance_to(point) <= SPLASH_RADIUS:
			e.take_damage(DAMAGE)
	shot_target = point
	shot_timer = SHOT_SHOW_TIME
	queue_redraw()

# Враг атаковал цитадель
func take_hit(amount: float) -> void:
	BattleManager.damage_citadel(amount)
	modulate = FLASH_COLOR
	create_tween().tween_property(self, "modulate", Color.WHITE, 0.25)

func _on_hp_changed(_hp: float) -> void:
	queue_redraw()
