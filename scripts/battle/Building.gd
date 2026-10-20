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
	# Особые здания орденов и богов (решение пользователя 18.10.2026) — пока блоки
	"codex_bastion": [[12, 0, 1, 1], [12, 1, 0, 1], [31, 0.5, 0.5, 2]],
	"blood_chalice": [[8, 0.5, 0.5, 1], [5, 0.5, 0.5, 2]],
	"fists_bastion": [[12, 0, 1, 1], [12, 1, 0, 1], [30, 0.5, 0.5, 2], [31, 0.5, 0.5, 3]],
	"wolf_totem": [[30, 0.5, 0.5, 1], [31, 0.5, 0.5, 2]],
	"vulkan_forge": [[1, 0.5, 0.5, 1], [3, 0.5, 0.5, 2]],
	"skull_altar": [[30, 0.5, 0.5, 1], [8, 0.5, 0.5, 2]],
	"plague_cauldron": [[1, 0.5, 0.5, 1], [5, 0.5, 0.5, 2]],
	"warp_spire": [[30, 0.5, 0.5, 1], [30, 0.5, 0.5, 2], [3, 0.5, 0.5, 3]],
	"pleasure_shrine": [[8, 0.5, 0.5, 1], [5, 0.5, 0.5, 2]],
}
# Оттенок блоков по типу (свои спрайты — потом): генератор холодный, госпиталь светлый
const BLOCK_TINT = {
	"generator": Color(0.75, 0.9, 1.25),
	"apothecarion": Color(1.15, 1.25, 1.1),
	"blood_chalice": Color(1.3, 0.75, 0.75),
	"vulkan_forge": Color(1.25, 0.9, 0.65),
	"skull_altar": Color(1.25, 0.8, 0.65),
	"plague_cauldron": Color(0.85, 1.15, 0.65),
	"warp_spire": Color(0.75, 0.9, 1.3),
	"pleasure_shrine": Color(1.2, 0.85, 1.2),
}
# Здания-стрелки: вид снаряда (Projectile.EFFECTS). Урон, скорострельность и оглушение — из stats
const SHOOTERS = {"tower": "spark", "fists_bastion": "spark", "warp_spire": "warp_bolt"}
const POISON_AURA_COLOR = Color(0.55, 0.9, 0.3, 0.05)
const POISON_AURA_LINE = Color(0.55, 0.9, 0.3, 0.3)
const POISON_LINGER: float = 1.0   # сек яда после выхода из облака котла
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
const SLOW_AURA_COLOR = Color(UITheme.SLOW_BLUE, 0.05)
const SLOW_AURA_LINE = Color(UITheme.SLOW_BLUE, 0.30)
# Уровень здания — ромбики над ним (1-й уровень без отметки)
const LEVEL_PIP_SIZE: float = 5.0
const LEVEL_PIP_GAP: float = 14.0
const LEVEL_PIP_COLOR = UITheme.AMBER_LIGHT
# Свой спрайт здания (готов к ассетам): <SPRITES_DIR>/<building_type>/frames.tres — лист кадров
# (tools/sheet_to_frames.py, ноги — основание здания по центру низа кадра). Анимации: idle (цикл),
# attack — выстрел (турель, орудие; muzzle / shot_frame по оранжевой вспышке), refill — Казармы
# вернули бойцов; варианты по уровню — idle_2 / attack_3 / …, нет варианта — базовая. Нет листа —
# здание из блоков тайлсета, как раньше. Ширина непрозрачной части idle — SPRITE_WIDTH клетки, высота —
# не выше SPRITE_MAX_HEIGHT клетки (узкие и высокие: тотем, шпиль). Здания Хаоса (карты CHAOS_RESKINS
# с тем же building_type) — <SPRITES_DIR>/chaos/<building_type>, нет там листа — общий
const SPRITES_DIR: String = "res://assets/sprites/buildings/"
const SPRITE_WIDTH: float = 0.8
const SPRITE_MAX_HEIGHT: float = 1.25
# Основание на листе — самая широкая строка силуэта в нижней BASE_ZONE кадра; в центре клетки — центр
# ромба основания: выше нижнего пикселя на четверть его ширины (изометрия 2:1). Раньше в центре клетки
# стоял нижний пиксель кадра — передний угол основания, и здание съезжало на клетку назад
const BASE_ZONE: float = 0.4
const BASE_ALPHA: float = 0.5
static var _frames_cache: Dictionary = {}   # "раса/building_type" → SpriteFrames или null (листа нет)

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
static func get_frames(type: String, faction: String = "") -> SpriteFrames:
	var key := faction + "/" + type
	if not _frames_cache.has(key):
		var path := SPRITES_DIR + (faction + "/" if faction == "chaos" else "") + type + "/frames.tres"
		if ResourceLoader.exists(path):
			_frames_cache[key] = load(path)
		else:
			_frames_cache[key] = get_frames(type) if faction != "" else null
	return _frames_cache[key]

func _load_sprite() -> void:
	var frames := get_frames(building_type, card.faction)
	if frames == null or not frames.has_animation("idle") or frames.get_frame_count("idle") == 0:
		return
	sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	sprite.centered = false
	var tex: Texture2D = frames.get_frame_texture("idle", 0)
	var size := tex.get_size()
	if not frames.has_meta("body_width"):   # непрозрачная ширина и основание idle — один раз на лист
		var img := tex.get_image()
		var used: int = img.get_used_rect().size.x if img else 0
		frames.set_meta("body_width", float(used) if used > 0 else size.x)
		frames.set_meta("base_point", find_base(img) if img else Vector2(size.x / 2.0, size.y))
	_set_flip(false)
	var k: float = minf(IsoGrid.TILE_WIDTH * SPRITE_WIDTH / maxf(frames.get_meta("body_width"), 1.0),
			IsoGrid.TILE_WIDTH * SPRITE_MAX_HEIGHT / size.y)
	sprite.scale = Vector2(k, k)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.animation_finished.connect(func():
		_set_flip(false)   # выстрел влево отразил спрайт — стойка снова как нарисована
		sprite.play(_level_anim("idle")))
	add_child(sprite)
	sprite.play(_level_anim("idle"))

# Центр ромба основания в кадре (px): самая широкая строка силуэта внизу кадра, выше нижнего пикселя
# на четверть её ширины. Пустой кадр — центр низа
static func find_base(img: Image) -> Vector2:
	var used := img.get_used_rect()
	if used.size.x == 0:
		return Vector2(img.get_width() / 2.0, img.get_height())
	var bottom := used.end.y
	var best_w := 0
	var best_cx := used.get_center().x
	for y in range(bottom - 1, maxi(used.position.y, bottom - int(used.size.y * BASE_ZONE)) - 1, -1):
		var left := -1
		var right := -1
		for x in range(used.position.x, used.end.x):
			if img.get_pixel(x, y).a > BASE_ALPHA:
				if left < 0:
					left = x
				right = x
		if left >= 0 and right - left + 1 > best_w:
			best_w = right - left + 1
			best_cx = (left + right + 1) / 2.0
	return Vector2(best_cx, bottom - best_w / 4.0)

# Отражение спрайта (выстрел влево) — основание остаётся в точке здания
func _set_flip(on: bool) -> void:
	var size := sprite.sprite_frames.get_frame_texture("idle", 0).get_size()
	var base: Vector2 = sprite.sprite_frames.get_meta("base_point", Vector2(size.x / 2.0, size.y))
	sprite.flip_h = on
	sprite.offset = Vector2(-(size.x - base.x) if on else -base.x, -base.y)

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
	_set_flip(base == "attack" and aim.x < 0.0)
	sprite.stop()
	sprite.play(anim)
	return true

# Точка ствола спрайта (мир): метаданные muzzle кадров, отражение — когда целится влево
func _sprite_muzzle() -> Vector2:
	var size := sprite.sprite_frames.get_frame_texture("idle", 0).get_size()
	var m: Vector2 = sprite.sprite_frames.get_meta("muzzle", Vector2(0, -size.y * 0.6))
	var base: Vector2 = sprite.sprite_frames.get_meta("base_point", Vector2(size.x / 2.0, size.y))
	var p := Vector2(size.x / 2.0 + m.x, size.y + m.y) - base   # muzzle — от центра низа кадра (sheet_to_frames)
	if aim.x < 0.0:   # выстрел влево — спрайт отразится (play_once), основание на месте
		p.x = -p.x
	return to_global(p * sprite.scale)

# Задержка снаряда до кадра выстрела листа (metadata shot_frame) — как у бойцов
func _shot_delay() -> float:
	var frames := sprite.sprite_frames
	if not frames.has_meta("shot_frame"):
		return 0.0
	return frames.get_meta("shot_frame") / frames.get_animation_speed(sprite.animation)

# Прозрачность OcclusionFader (self_modulate) — и на спрайт: дочерний узел self_modulate не наследует.
# Вне схватки стойка — один кадр (hold_idle_outside_battle)
func _process(_delta: float) -> void:
	if sprite:
		sprite.modulate.a = self_modulate.a
		hold_idle_outside_battle(sprite)

# Вне схватки (расстановка, итог) стойка здания — один кадр idle, в бою — анимация (решение пользователя
# 20.10.2026: покачивание стоек на расстановке мелькало; бойцы анимируются всегда). Уровни — idle_2 / idle_3
static func hold_idle_outside_battle(s: AnimatedSprite2D) -> void:
	if not String(s.animation).begins_with("idle"):
		return
	var still := not BattleManager.is_battle_running()
	if still and (s.is_playing() or s.frame != 0):
		s.stop()   # stop — кадр 0, анимация та же
	elif not still and not s.is_playing():
		s.play()

# -------------------------------------------------------
# ВИД
# -------------------------------------------------------
func _draw() -> void:
	draw_ground_shadow(self, Vector2.ZERO, IsoGrid.TILE_WIDTH * GROUND_SHADOW_WIDTH)
	if stats.get("slow_radius", 0.0) > 0.0:
		draw_circle(Vector2.ZERO, stats["slow_radius"], SLOW_AURA_COLOR)
		draw_arc(Vector2.ZERO, stats["slow_radius"], 0.0, TAU, 48, SLOW_AURA_LINE, 1.5, true)
	if stats.get("poison_radius", 0.0) > 0.0:
		draw_circle(Vector2.ZERO, stats["poison_radius"], POISON_AURA_COLOR)
		draw_arc(Vector2.ZERO, stats["poison_radius"], 0.0, TAU, 48, POISON_AURA_LINE, 1.5, true)
	if sprite:   # свой спрайт — блоков и нарисованных стволов нет
		if building_type == "artillery" and _explosion_id > 0:
			draw_circle(to_local(_explosion_point), stats.get("splash_radius", 0.0), EXPLOSION_COLOR)
		_draw_level_pips()
		return
	# Блоки тайлсета светло-серые — в тон камня расы (FactionTheme "building_tint", решение пользователя 18.10.2026)
	var tint: Color = BLOCK_TINT.get(building_type, Color.WHITE) * FactionTheme.current().get("building_tint", Color.WHITE)
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

# Мягкая тень постройки на грунте (стилизация 20.10.2026: здание «стояло» на поле без опоры) — сплюснутое
# пятно, гаснет к краю; рисуется до спрайта (ребёнок рисуется поверх). Цитадель — тот же помощник
const GROUND_SHADOW_WIDTH: float = 1.15   # доля клетки: шире основания — край тени виден из-под стен
const GROUND_SHADOW_ALPHA: float = 0.9   # в центре
const GROUND_SHADOW_STEPS: int = 4       # слоёв: каждый уже и добавляет долю темноты — мягкий край
static func draw_ground_shadow(ci: CanvasItem, center: Vector2, width: float) -> void:
	var flat := float(IsoGrid.TILE_HEIGHT) / IsoGrid.TILE_WIDTH
	ci.draw_set_transform(center, 0.0, Vector2(1.0, flat))
	for i in GROUND_SHADOW_STEPS:
		var r := width / 2.0 * (1.0 - float(i) / GROUND_SHADOW_STEPS)
		ci.draw_circle(Vector2.ZERO, r, Color(0, 0, 0, GROUND_SHADOW_ALPHA / GROUND_SHADOW_STEPS))
	ci.draw_set_transform(Vector2.ZERO)

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
	"codex_bastion": AREA_CROSS,  # щит соседним отрядам в начале боя
	"blood_chalice": AREA_CROSS,  # вампиризм соседним отрядам
	"wolf_totem": AREA_CROSS,     # клич соседним отрядам в начале боя
	"vulkan_forge": AREA_CROSS,   # +урон соседним отрядам
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
		"codex_bastion":
			lines.append("Отряды на соседних клетках (подсвечены) начинают бой со щитом %d%% HP" \
				% roundi(stats.get("shield_ratio", 0.0) * 100.0))
		"blood_chalice":
			lines.append("Отряды на соседних клетках (подсвечены) лечатся на %d%% урона ближнего боя" \
				% roundi(stats.get("lifesteal", 0.0) * 100.0))
		"fists_bastion":
			lines.append("Щит цитадели +%d в каждом бою. Стреляет в ближайшего врага: %d урона, %.1f выстр./с" % [
				stats.get("shield", 0.0), stats.get("damage", 0.0), stats.get("attack_speed", 0.0)])
		"wolf_totem":
			lines.append("В начале боя отряды на соседних клетках (подсвечены) +%d%% урона на %.0f с" % [
				roundi(stats.get("empower", 0.0) * 100.0), stats.get("duration", 0.0)])
		"vulkan_forge":
			lines.append("Отряды на соседних клетках (подсвечены) +%d%% урона. После боя чинит цитадель на %d HP" % [
				roundi(stats.get("damage_bonus", 0.0) * 100.0), stats.get("repair", 0.0)])
		"skull_altar":
			lines.append("Каждый убитый враг: +%.1f%% урона всей армии до конца боя (до +%d%%)" % [
				stats.get("per_kill", 0.0) * 100.0, roundi(stats.get("max_bonus", 0.0) * 100.0)])
		"plague_cauldron":
			lines.append("Травит врагов в круге %d px: яд %.1f ур/с" % [stats.get("poison_radius", 0.0), stats.get("poison", 0.0)])
		"warp_spire":
			lines.append("Молния варпа по ближайшему врагу: %d урона, оглушение %.1f с, %.1f выстр./с" % [
				stats.get("damage", 0.0), stats.get("stun", 0.0), stats.get("attack_speed", 0.0)])
		"pleasure_shrine":
			lines.append("Замедляет врагов на %d%% в круге %d px" % [
				roundi((1.0 - stats.get("slow_mult", 1.0)) * 100.0), stats.get("slow_radius", 0.0)])
		_:
			lines.append(card.description)
	lines.append("Такая же карта — уровень +1" if card.can_level_up_building() else "Максимальный уровень")
	return "\n".join(lines)


# Область экрана (мировые координаты), которую закрывают блоки здания —
# OcclusionFader делает здание полупрозрачным, если за ним стоит боец
func get_occlusion_rect() -> Rect2:
	if sprite:
		var size: Vector2 = sprite.sprite_frames.get_frame_texture("idle", 0).get_size() * sprite.scale
		return Rect2(global_position + sprite.offset * sprite.scale, size)
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
	if stats.get("slow_radius", 0.0) > 0.0:
		_tick_slow_aura()
	if stats.get("poison_radius", 0.0) > 0.0:
		_tick_poison_aura()
	if building_type == "skull_altar":
		_tick_skull_altar()
	if not SHOOTERS.has(building_type):
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
	var shot = Projectile.launch(get_parent(), SHOOTERS[building_type], barrel_end, target, aim_offset, delay)
	shot.damage = stats.get("damage", 0.0)
	shot.stun = stats.get("stun", 0.0)

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

# Котёл Нургла: врагам в радиусе — яд без стаков, держится POISON_LINGER после выхода
func _tick_poison_aura() -> void:
	var r: float = stats["poison_radius"]
	for e in SoldierRegistry.get_alive_soldiers_of_team(GameConstants.TEAM_ENEMY):
		if global_position.distance_to(e.global_position) <= r:
			e.apply_status(StatusEffects.POISONED, stats.get("poison", 0.0), POISON_LINGER, false)

# Алтарь черепов: убитые с начала боя враги → +урон всей армии (runtime current_damage; прибавка
# пересчитывается отношением, когда растёт счёт)
var _enemies_at_start: int = 0
var _altar_bonus: float = 0.0

func _tick_skull_altar() -> void:
	var kills := maxi(_enemies_at_start - SoldierRegistry.get_alive_soldiers_of_team(GameConstants.TEAM_ENEMY).size(), 0)
	var bonus := minf(kills * stats.get("per_kill", 0.0), stats.get("max_bonus", 0.0))
	if bonus <= _altar_bonus:
		return
	var k := (1.0 + bonus) / (1.0 + _altar_bonus)
	_altar_bonus = bonus
	for s in SoldierRegistry.get_alive_soldiers_of_team(GameConstants.TEAM_PLAYER):
		s.current_damage *= k

# Начало боя (BattleScene._on_start_pressed, после бонусов ордена): эффекты зданий на отряды соседних
# клеток (щит, вампиризм, клич, +урон) и отсчёт алтаря
static func apply_battle_start() -> void:
	var squads := SquadRegistry.get_alive_squads_of_team(GameConstants.TEAM_PLAYER)
	var enemies := SoldierRegistry.get_alive_soldiers_of_team(GameConstants.TEAM_ENEMY).size()
	for b in BattleManager.buildings:
		if not is_instance_valid(b):
			continue
		b._enemies_at_start = enemies
		b._altar_bonus = 0.0
		if b.stats.get("shield", 0.0) > 0.0:
			b.play_once("shield")   # стена подняла щит цитадели (ряд листа, если есть)
		var area := get_effect_tiles(b.building_type, b.tile)
		for sq in squads:
			if sq.tile in area:
				for s in sq.soldiers:
					b._apply_start_effect(s)

func _apply_start_effect(s: Soldier) -> void:
	match building_type:
		"codex_bastion":
			s.shield += s.max_hp * stats.get("shield_ratio", 0.0)
		"blood_chalice":
			s.lifesteal = maxf(s.lifesteal, stats.get("lifesteal", 0.0))
		"wolf_totem":
			s.apply_status(StatusEffects.EMPOWERED, stats.get("empower", 0.0), stats.get("duration", 0.0), false)
		"vulkan_forge":
			s.current_damage *= 1.0 + stats.get("damage_bonus", 0.0)

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
