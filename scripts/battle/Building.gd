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
#   generator   — Plasma Generatorium: +Req после каждого боя (EconomyManager.collect_building_income)
#   apothecarion — Apothecarion: павший боец отряда на клетке его зоны (крест) может встать (revive_at)

const BLOCK_SCALE: float = 0.5
# Блоки по building_type: [Tiles/Slice N, i, j, ярус]; (i, j) — подклетка 2×2,
# 0.5 — центр клетки. Порядок — от дальних к ближним, снизу вверх.
const BLOCKS = {
	"tower": [[30, 0.5, 0.5, 1], [30, 0.5, 0.5, 2], [31, 0.5, 0.5, 3]],
	"wall":  [[12, 0, 1, 1], [12, 1, 0, 1]],   # низкая стена поперёк клетки
	"artillery": [[30, 0.5, 0.5, 1], [31, 0.5, 0.5, 2]],   # приземистая башня с длинным стволом
	"barracks": [[30, 0, 1, 1], [30, 1, 0, 1], [31, 0.5, 0.5, 2]],   # широкое низкое здание с надстройкой
	"generator": [[1, 0.5, 0.5, 1], [3, 0.5, 0.5, 2]],   # кубы с решётками — реактор
	"apothecarion": [[8, 0.5, 0.5, 1], [5, 0.5, 0.5, 2]],  # гладкий блок с плитой
}
# Оттенок блоков по типу (свои спрайты — потом): генератор холодный, госпиталь светлый
const BLOCK_TINT = {
	"generator": Color(0.75, 0.9, 1.25),
	"apothecarion": Color(1.15, 1.25, 1.1),
}
const ARTILLERY_LEVELS: int = 2
const ARTILLERY_BARREL_LENGTH: float = 40.0
const ARTILLERY_PROJECTILE: String = "rocket"
const ARTILLERY_ARC: float = 90.0          # px — высота дуги полёта ракеты (только вид)
const ARTILLERY_IMPACT_VFX = ["explosion", "fireball", "impact"]   # огонь поверх дыма
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
# Свой спрайт здания (готов к ассетам): <SPRITES_DIR>/<building_type>/frames.tres — лист кадров
# (tools/sheet_to_frames.py, ноги — основание здания по центру низа кадра). Анимации: idle (цикл),
# attack — выстрел (турель, орудие; muzzle / shot_frame по оранжевой вспышке), refill — Казармы
# вернули бойцов; варианты по уровню — idle_2 / attack_3 / …, нет варианта — базовая. Нет листа —
# здание из блоков тайлсета, как раньше. Ширина непрозрачной части idle — SPRITE_WIDTH клетки
const SPRITES_DIR: String = "res://assets/sprites/buildings/"
const SPRITE_WIDTH: float = 0.8
static var _frames_cache: Dictionary = {}   # building_type → SpriteFrames или null (листа нет)

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
var sprite: AnimatedSprite2D = null         # свой спрайт (если есть лист), иначе null — блоки

func setup(building_card: CardData, grid_tile: Vector2i) -> void:
	card = building_card
	tile = grid_tile
	building_type = card.building_type
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_load_sprite()
	refresh_stats()

# Статы по уровню карты (после улучшения — пересчитать)
func refresh_stats() -> void:
	stats = Chapters.apply_building_stats(card.get_building_stats(), RunManager.player_chapter)
	if sprite and sprite.animation.begins_with("idle"):
		sprite.play(_level_anim("idle"))   # улучшили — вид нового уровня
	queue_redraw()

# -------------------------------------------------------
# СВОЙ СПРАЙТ (если есть лист кадров)
# -------------------------------------------------------
static func get_frames(type: String) -> SpriteFrames:
	if not _frames_cache.has(type):
		var path := SPRITES_DIR + type + "/frames.tres"
		_frames_cache[type] = load(path) if ResourceLoader.exists(path) else null
	return _frames_cache[type]

func _load_sprite() -> void:
	var frames := get_frames(building_type)
	if frames == null or not frames.has_animation("idle") or frames.get_frame_count("idle") == 0:
		return
	sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	sprite.centered = false
	var tex: Texture2D = frames.get_frame_texture("idle", 0)
	var size := tex.get_size()
	sprite.offset = Vector2(-size.x / 2.0, -size.y)   # основание — центр низа кадра, в точке здания
	if not frames.has_meta("body_width"):   # непрозрачная ширина idle — один раз на лист
		var img := tex.get_image()
		var used: int = img.get_used_rect().size.x if img else 0
		frames.set_meta("body_width", float(used) if used > 0 else size.x)
	var k: float = IsoGrid.TILE_WIDTH * SPRITE_WIDTH / maxf(frames.get_meta("body_width"), 1.0)
	sprite.scale = Vector2(k, k)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.animation_finished.connect(func():
		sprite.flip_h = false   # выстрел влево отразил спрайт — стойка снова как нарисована
		sprite.play(_level_anim("idle")))
	add_child(sprite)
	sprite.play(_level_anim("idle"))

# Анимация с учётом уровня: idle_3, нет такой — idle
func _level_anim(base: String) -> String:
	var leveled := "%s_%d" % [base, card.building_level]
	return leveled if sprite.sprite_frames.has_animation(leveled) else base

# Разовая анимация листа (выстрел, пополнение), потом снова idle. false — у листа такой нет
func play_once(base: String) -> bool:
	if sprite == null:
		return false
	var anim := _level_anim(base)
	if not sprite.sprite_frames.has_animation(anim):
		return false
	sprite.flip_h = base == "attack" and aim.x < 0.0
	sprite.stop()
	sprite.play(anim)
	return true

# Точка ствола спрайта (мир): метаданные muzzle кадров, отражение — когда целится влево
func _sprite_muzzle() -> Vector2:
	var h: float = sprite.sprite_frames.get_frame_texture("idle", 0).get_size().y
	var m: Vector2 = sprite.sprite_frames.get_meta("muzzle", Vector2(0, -h * 0.6))
	if aim.x < 0.0:
		m.x = -m.x
	return to_global(m * sprite.scale)

# Задержка снаряда до кадра выстрела листа (metadata shot_frame) — как у бойцов
func _shot_delay() -> float:
	var frames := sprite.sprite_frames
	if not frames.has_meta("shot_frame"):
		return 0.0
	return frames.get_meta("shot_frame") / frames.get_animation_speed(sprite.animation)

# Прозрачность OcclusionFader (self_modulate) — и на спрайт: дочерний узел self_modulate не наследует
func _process(_delta: float) -> void:
	if sprite:
		sprite.modulate.a = self_modulate.a

# -------------------------------------------------------
# ВИД
# -------------------------------------------------------
func _draw() -> void:
	if building_type == "wall" and stats.get("slow_radius", 0.0) > 0.0:
		draw_circle(Vector2.ZERO, stats["slow_radius"], SLOW_AURA_COLOR)
		draw_arc(Vector2.ZERO, stats["slow_radius"], 0.0, TAU, 48, SLOW_AURA_LINE, 1.5, true)
	if sprite:   # свой спрайт — блоков и нарисованных стволов нет
		if building_type == "artillery" and _explosion_id > 0:
			draw_circle(to_local(_explosion_point), stats.get("splash_radius", 0.0), EXPLOSION_COLOR)
		_draw_level_pips()
		return
	var tint: Color = BLOCK_TINT.get(building_type, Color.WHITE)
	for b in BLOCKS.get(building_type, []):
		TerrainTiles.draw_block(self, TerrainTiles.tile(b[0]), _block_top(b[1], b[2], b[3]), tint, BLOCK_SCALE)
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

# -------------------------------------------------------
# ПОДСКАЗКА И ЗОНА ДЕЙСТВИЯ (наведение на здание, перетаскивание карты — BattleScene)
# -------------------------------------------------------
# Зона действия на клетках — только у зданий, которые действуют на своих (правило пользователя 17.10.2026):
# соседние клетки крестом, линией по горизонтали (вдоль ряда, ±x) или по вертикали (±y). Здания против
# врагов (стена — круг замедления, турель, орудие) и генератор (доход) зоны на клетках не имеют.
# Клетки — без проверки, открыта ли клетка (рисуются только открытые)
const AREA_CROSS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const AREA_HORIZONTAL: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0)]
const AREA_VERTICAL: Array[Vector2i] = [Vector2i(0, 1), Vector2i(0, -1)]
const EFFECT_AREAS = {
	"barracks": AREA_CROSS,       # пополняет отряды на соседних клетках
	"apothecarion": AREA_CROSS,   # павший боец отряда на соседней клетке может встать
}

static func get_effect_tiles(type: String, at: Vector2i) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for d in EFFECT_AREAS.get(type, []):
		tiles.append(at + d)
	return tiles

# Подсказка: название и уровень, что делает (с текущими цифрами), можно ли улучшить
func describe() -> String:
	var lines: Array[String] = ["%s · ур. %d/%d" % [card.title, card.building_level, CardData.MAX_BUILDING_LEVEL]]
	match building_type:
		"tower":
			lines.append("Стреляет в ближайшего врага на всём поле: %d урона, %.1f выстр./с" % [
				stats.get("damage", 0.0), stats.get("attack_speed", 0.0)])
		"wall":
			lines.append("Щит цитадели +%d в каждом бою. Замедляет врагов на %d%% в круге %d px" % [
				stats.get("shield", 0.0), roundi((1.0 - stats.get("slow_mult", 1.0)) * 100.0), stats.get("slow_radius", 0.0)])
		"artillery":
			lines.append("В бою — клик по полю: залп %d урона в радиусе %d px, перезарядка %.1f с" % [
				stats.get("damage", 0.0), stats.get("splash_radius", 0.0), stats.get("cooldown", 0.0)])
		"barracks":
			lines.append("После каждой победы возвращают %d павших бойцов отрядам на соседних клетках (подсвечены). Не лечат" \
				% floori(stats.get("refill", 0.0)))
		"apothecarion":
			lines.append("Павший боец отряда на соседней клетке (подсвечены) встаёт с %d%% HP: шанс %d%%, раз за бой" \
				% [roundi(stats.get("revive_hp", 0.0) * 100.0), roundi(stats.get("revive_chance", 0.0) * 100.0)])
		_:
			lines.append(card.description)
	lines.append("Такая же карта — уровень +1" if card.can_level_up_building() else "Максимальный уровень")
	return "\n".join(lines)


# Область экрана (мировые координаты), которую закрывают блоки здания —
# OcclusionFader делает здание полупрозрачным, если за ним стоит боец
func get_occlusion_rect() -> Rect2:
	if sprite:
		var size: Vector2 = sprite.sprite_frames.get_frame_texture("idle", 0).get_size() * sprite.scale
		return Rect2(global_position + Vector2(-size.x / 2.0, -size.y), size)
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
	var target = _find_target(stats.get("attack_range", INF))   # без дальности — всё поле
	if target == null:
		return
	attack_timer = 1.0 / stats.get("attack_speed", 1.0)
	var aim_offset = Vector2(0, -Soldier.TARGET_SPRITE_HEIGHT / 2.0)
	aim = target.global_position + aim_offset - global_position
	queue_redraw()
	var barrel_end = to_global(_block_top(0.5, 0.5, TOWER_LEVELS) + aim.normalized() * BARREL_LENGTH)
	var delay := 0.0
	if sprite:   # свой спрайт: снаряд из его ствола (на кадре вспышки, если есть ряд attack)
		barrel_end = _sprite_muzzle()
		if play_once("attack"):
			delay = _shot_delay()
	var shot = Projectile.launch(get_parent(), SHOT_PROJECTILE, barrel_end, target, aim_offset, delay)
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
	var delay := 0.0
	if sprite:
		muzzle = _sprite_muzzle()
		if play_once("attack"):
			delay = _shot_delay()
	var shot = Projectile.launch(get_parent(), ARTILLERY_PROJECTILE, muzzle, null, point, delay)
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
	if not is_inside_tree() or sprite:   # у спрайта отдача — в его анимации
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

# Шанс поднять павшего бойца игрока в точке: самый сильный Apothecarion рядом.
# Возвращает {"chance", "hp"} (доля HP после подъёма); нет — chance 0
static func revive_at(tile: Vector2i) -> Dictionary:
	var best = {"chance": 0.0, "hp": 0.0}
	for b in BattleManager.buildings:
		if not is_instance_valid(b):
			continue
		var c = b.stats.get("revive_chance", 0.0)
		if c > best["chance"] and tile in get_effect_tiles(b.building_type, b.tile):
			best = {"chance": c, "hp": b.stats.get("revive_hp", 0.3)}
	return best
