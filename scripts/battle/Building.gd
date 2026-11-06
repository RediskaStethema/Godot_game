class_name Building
extends Node2D

# Здание игрока на клетке королевства. Параметры — из CardData.building_stats,
# вид — блоки лунного тайлсета в полклетки (как у Citadel).
# Здания неуязвимы и стоят между раундами (BattleManager.player_buildings).
# Тикает BattleManager (FIXED_TICK) во время боя.
#   tower — турель: бьёт ближайшего врага в радиусе
#   artillery — орудие игрока: клик по полю в бою (BattleScene) → fire_at, залп по
#           площади только по врагам, перезарядка cooldown (готово в начале боя)
#   wall  — карта стены владений: клетку не занимает, стена по контуру королевства — KingdomWall
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
# Hellfire Mortar (орудие Хаоса, card.faction "chaos"): пылающий череп и бордовый взрыв пакета эффектов
const HELLFIRE_PROJECTILE: String = "hellfire_shell"
const HELLFIRE_IMPACT_VFX = ["explosion", "hellfire_blast"]
# Аура в бою (Vfx, цикл; радиус — stats): замедление стены / шипов, яд котла, дымка Slaanesh
const SKULL_RISE: float = 70.0          # px — череп алтаря встаёт над крышей
const SKULL_SPREAD: float = 9.0         # px — черепа кладутся в стопку со сдвигом
var _aura_ring: AuraRing = null
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
# Уровень здания видно на модели (решение пользователя 24.10.2026: были только ромбики; листов по уровням нет —
# ASSETS_NEEDED P2): здание крупнее (LEVEL_SCALES по уровню) и кольцо у основания в цвете расы — на 2-м одно,
# на 3-м двойное со свечением. Только вид. Есть свои кадры уровня (idle_2 / idle_3) — рост из листа (_level_scale)
const LEVEL_SCALES: Array[float] = [1.0, 1.06, 1.12]
const LEVEL_UP_GROW_TIME: float = 0.55   # эффект улучшения: рост из прежнего масштаба
const LEVEL_UP_FLASH: float = 0.85       # белая вспышка (как попадание по бойцу) и её угасание, сек
const LEVEL_UP_FLASH_TIME: float = 0.6
# Неживые ряды уровня (metadata/level_static, tools/building_levels_add.py: пакет 26.10.2026 — стойка из копий одного
# кадра, выстрел и пополнение без движения здания) оживляются кодом до настоящих кадров (решение пользователя
# 26.10.2026): стойка в бою дышит (рост и ширина в противофазе), выстрел — отдача прочь от цели и приседание,
# пополнение / щит — толчок. Только вид, время кадра (не тик боя)
const BREATH: float = 0.012              # доля роста
const BREATH_PERIOD: float = 2.6         # сек
const KICK_TIME: float = 0.28            # отдача выстрела гаснет
const KICK_PX: float = 5.0               # px мира прочь от цели
const KICK_SQUASH: float = 0.04
const PULSE_TIME: float = 0.5            # толчок пополнения / щита
const PULSE_SCALE: float = 0.04
const LEVEL_RING_RADIUS: float = 0.47      # доля клетки — по краю ромба основания
const LEVEL_RING_GAP: float = 7.0          # между кольцами 3-го уровня, px
const LEVEL_RING_ALPHA: float = 0.6
const LEVEL_RING_GLOW_ALPHA: float = 0.13
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
# Контур спрайта, px мира: шейдер бойцов, но толще их 0.9 и непрозрачный (Palette.BUILDING_OUTLINE) —
# здание вчетверо крупнее бойца, и тонкая линия пропадала на тёмном грунте Хаоса (решение пользователя 24.10.2026).
# Тема с "building_env" задаёт свой контур (мягче — здание в свет местности, apply_environment)
const OUTLINE_WORLD_PX: float = 2.2
const ENV_AO_HEIGHT: float = 0.22   # затемнение к основанию — доля высоты кадра над точкой основания
const ENV_AO_BELOW: float = 0.04    # и чуть ниже неё (подножие)
static var _env_materials: Dictionary = {}   # "раса/тип|px" → ShaderMaterial (вид здания в свет местности)
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
var _base_scale: float = 1.0   # масштаб спрайта 1-го уровня (ширина основания — SPRITE_WIDTH клетки)
var sprite: AnimatedSprite2D = null         # свой спрайт (если есть лист), иначе null — блоки
var _level_k: float = 1.0      # масштаб спрайта уровня (_apply_level_scale); на экране — с ростом и оживлением
var _grow: float = 1.0         # рост из прежнего масштаба при улучшении (play_level_up)
var _pip_key: String = ""      # ромбики уровня: для какого ряда / масштаба посчитана высота (_draw_level_pips)
var _pip_top: float = 0.0
var _kick: float = 0.0         # отдача неживого выстрела: 1 — только что, гаснет к 0
var _kick_wait: float = 0.0    # до кадра вспышки, сек
var _pulse: float = 0.0        # толчок неживого пополнения / щита

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
	if sprite:
		_apply_level_scale()
		if sprite.animation.begins_with("idle"):
			sprite.play(_level_anim("idle"))   # улучшили — вид нового уровня
	queue_redraw()

# Масштаб спрайта по уровню и контур под него — толщина в px мира та же
func _apply_level_scale() -> void:
	var k := _base_scale * _level_scale()
	_level_k = k
	sprite.scale = Vector2(k, k)
	var env: Dictionary = FactionTheme.current().get("building_env", {})
	if env.is_empty():
		sprite.material = Soldier.outline_material(k, OUTLINE_WORLD_PX, Palette.BUILDING_OUTLINE)   # контур как у бойцов
		return
	sprite.self_modulate = env.get("tint", Color.WHITE)
	sprite.material = _environment_material(env, k)

# Рост уровня: есть свои кадры уровня — metadata/level_scale листа (кадры уровня в масштабе, при котором здание
# на LEVEL_GROWTH выше прежнего уровня — tools/building_levels_add.py; решение пользователя 26.10.2026: улучшенное
# здание чуть выше прежнего, пусть и шире), нет — LEVEL_SCALES
func _level_scale() -> float:
	if _level_anim("idle") != "idle":
		return float(sprite.sprite_frames.get_meta("level_scale", {}).get(card.building_level, 1.0))
	return LEVEL_SCALES[clampi(card.building_level, 1, LEVEL_SCALES.size()) - 1]

# Эффект улучшения (решение пользователя 26.10.2026): здание вспыхивает белым — под вспышкой уже кадры нового
# уровня — и с пружинкой вырастает из прежнего масштаба (from_scale — sprite.scale до refresh_stats); свет,
# кольца и шевроны — BuildingLevelUp. Только вид
func play_level_up(from_scale: Vector2) -> void:
	BuildingLevelUp.play(self, card.building_level, _visual_height(), card.faction)
	if sprite == null:
		return
	var shared := sprite.material
	var flash := shared.duplicate() as ShaderMaterial if shared is ShaderMaterial else null
	if flash:
		sprite.material = flash
	_grow = from_scale.y / maxf(_level_k, 0.001)
	_apply_motion(0.0)
	var tw := create_tween().set_parallel()
	tw.tween_property(self, "_grow", 1.0, LEVEL_UP_GROW_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if flash:
		tw.tween_method(func(v: float): flash.set_shader_parameter("flash", v), LEVEL_UP_FLASH, 0.0, LEVEL_UP_FLASH_TIME)
		tw.chain().tween_callback(func():
			if sprite.material == flash:   # контур и свет местности — снова общий материал
				sprite.material = shared)

# Непрозрачная часть кадра стойки уровня (px кадра) — раз на ряд (get_image дорогой)
var _used_anim: String = ""
var _used_rect := Rect2()
func _idle_used_rect() -> Rect2:
	var anim := _level_anim("idle")
	if anim != _used_anim:
		_used_anim = anim
		var tex: Texture2D = sprite.sprite_frames.get_frame_texture(anim, 0)
		var img := tex.get_image()
		_used_rect = Rect2(img.get_used_rect()) if img else Rect2(Vector2.ZERO, tex.get_size())
		if _used_rect.size == Vector2.ZERO:
			_used_rect = Rect2(Vector2.ZERO, tex.get_size())
	return _used_rect

# Рост здания над основанием, px мира (кадр стойки уровня; блоки — по прямоугольнику блоков)
func _visual_height() -> float:
	if sprite == null:
		return global_position.y - get_occlusion_rect().position.y
	var top := _idle_used_rect().position.y
	return (-sprite.offset.y - top) * _level_k

# Здание в свет местности (тема "building_env"): шейдер бойцов — мягкий контур, насыщенность, приглушение
# светов, затемнение к основанию (по точке основания листа). Материал общий для зданий одного листа и масштаба
func _environment_material(env: Dictionary, k: float) -> ShaderMaterial:
	var px := maxi(1, roundi(env.get("outline_px", OUTLINE_WORLD_PX) / maxf(k, 0.01)))
	var key := "%s/%s|%d" % [card.faction, building_type, px]
	if not _env_materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = Soldier.unit_shader()
		m.set_shader_parameter("outline_px", float(px))
		m.set_shader_parameter("outline_color", Color(Palette.BUILDING_OUTLINE, env.get("outline_alpha", 1.0)))
		m.set_shader_parameter("env_sat", env.get("sat", 1.0))
		m.set_shader_parameter("env_knee", env.get("knee", 0.0))
		var tex: Texture2D = sprite.sprite_frames.get_frame_texture("idle", 0)
		var base: Vector2 = sprite.sprite_frames.get_meta("base_point", tex.get_size())
		var bv := base.y / tex.get_height()
		m.set_shader_parameter("ao_strength", env.get("ao", 0.0))
		m.set_shader_parameter("ao_from", bv - ENV_AO_HEIGHT)
		m.set_shader_parameter("ao_to", bv + ENV_AO_BELOW)
		_env_materials[key] = m
	return _env_materials[key]

# Кольцо уровня у основания (под спрайтом — он рисуется поверх, кольцо видно спереди и по бокам)
func _draw_level_ring() -> void:
	if card.building_level < 2:
		return
	var col: Color = Palette.LEVEL_RING_CHAOS if card.faction == "chaos" else Palette.GOLD
	var r := IsoGrid.TILE_WIDTH * LEVEL_RING_RADIUS
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))   # изометрия: круг на земле — эллипс 2:1
	if card.building_level >= 3:
		draw_circle(Vector2.ZERO, r, Color(col, LEVEL_RING_GLOW_ALPHA))
		draw_arc(Vector2.ZERO, r + LEVEL_RING_GAP, 0.0, TAU, 64, Color(col, LEVEL_RING_ALPHA * 0.6), 2.0, true)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, Color(col, LEVEL_RING_ALPHA), 2.5, true)
	draw_set_transform(Vector2.ZERO)

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
	_base_scale = minf(IsoGrid.TILE_WIDTH * SPRITE_WIDTH / maxf(frames.get_meta("body_width"), 1.0),
			IsoGrid.TILE_WIDTH * SPRITE_MAX_HEIGHT / size.y)
	_apply_level_scale()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.animation_finished.connect(func():
		_set_flip(false)   # выстрел влево отразил спрайт — стойка снова как нарисована
		sprite.play(_level_anim("idle")))
	sprite.animation_changed.connect(_update_offset)   # у рядов уровня свой сдвиг (level_shift)
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
	sprite.flip_h = on
	_update_offset()

func _update_offset() -> void:
	var size := sprite.sprite_frames.get_frame_texture("idle", 0).get_size()
	var base: Vector2 = sprite.sprite_frames.get_meta("base_point", Vector2(size.x / 2.0, size.y))
	var shift := _level_shift(sprite.animation)
	sprite.offset = Vector2(-(size.x - base.x) - shift.x if sprite.flip_h else -base.x + shift.x, -base.y + shift.y)

# Кадры уровня (ряды idle_2, attack_3, …) художник нарисовал со сдвигом здания по холсту: metadata/level_shift
# {уровень: Vector2} — на сколько px холста их подвинуть, чтобы постамент совпал с 1-м уровнем
# (tools/building_levels_add.py). Сдвиг — по анимации: ряда уровня нет — играет ряд 1-го, без сдвига
func _level_shift(anim: StringName) -> Vector2:
	var parts := String(anim).rsplit("_", true, 1)
	if parts.size() < 2 or not parts[1].is_valid_int():
		return Vector2.ZERO
	return sprite.sprite_frames.get_meta("level_shift", {}).get(parts[1].to_int(), Vector2.ZERO)

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
	if _is_static(anim):   # неживой ряд уровня — оживить кодом
		if base == "attack":
			_kick = 1.0
			_kick_wait = _shot_delay()
		else:
			_pulse = 1.0
	return true

func _is_static(anim: StringName) -> bool:
	return sprite.sprite_frames.get_meta("level_static", []).has(String(anim))

# Масштаб и сдвиг спрайта на экране: уровень × рост улучшения × оживление неживых рядов (дыхание, отдача, толчок)
func _apply_motion(delta: float) -> void:
	var sx := 1.0
	var sy := 1.0
	var pos := Vector2.ZERO
	if BattleManager.is_battle_running() and sprite.animation.begins_with("idle") and _is_static(sprite.animation):
		var b := sin(Time.get_ticks_msec() / 1000.0 * TAU / BREATH_PERIOD + float(hash(tile) % 628) / 100.0)
		sy += BREATH * b
		sx -= BREATH * 0.5 * b
	if _kick_wait > 0.0:
		_kick_wait -= delta
	elif _kick > 0.0:
		_kick = maxf(0.0, _kick - delta / KICK_TIME)
		var e := _kick * _kick
		pos = -aim.normalized() * KICK_PX * e
		sy *= 1.0 - KICK_SQUASH * e
		sx *= 1.0 + KICK_SQUASH * 0.75 * e
	if _pulse > 0.0:
		_pulse = maxf(0.0, _pulse - delta / PULSE_TIME)
		var e := sin(PI * (1.0 - _pulse))
		sx *= 1.0 + PULSE_SCALE * e
		sy *= 1.0 + PULSE_SCALE * e
	sprite.scale = Vector2(sx, sy) * _level_k * _grow
	sprite.position = pos

# Точка ствола спрайта (мир): метаданные muzzle кадров, отражение — когда целится влево
func _sprite_muzzle() -> Vector2:
	var size := sprite.sprite_frames.get_frame_texture("idle", 0).get_size()
	var m: Vector2 = sprite.sprite_frames.get_meta("muzzle", Vector2(0, -size.y * 0.6))
	# у ряда уровня свои стволы (пакет 05.11.2026): metadata/level_muzzle {уровень: Vector2} — та же мера, что
	# muzzle, на холсте ряда уровня (tools/building_levels_muzzle.py); нет — вспышка там же, где у 1-го уровня
	var attack := _level_anim("attack")
	if attack != "attack":
		m = sprite.sprite_frames.get_meta("level_muzzle", {}).get(card.building_level, m)
	return _muzzle_to_world(m)

# Все стволы для залпа (решение пользователя 06.11.2026 «залп из всех стволов»): metadata/level_barrels
# {уровень: [Vector2, …]} — по стволу на каждую вспышку кадра выстрела (tools/building_levels_muzzle.py),
# та же мера, что muzzle; нет записи уровня — один ствол _sprite_muzzle
func _sprite_barrels() -> Array:
	var points: Array = sprite.sprite_frames.get_meta("level_barrels", {}).get(card.building_level, [])
	if points.is_empty():
		return [_sprite_muzzle()]
	return points.map(func(m): return _muzzle_to_world(m))

# Точка листа (мера muzzle: px холста от центра низа кадра) → мир, с отражением и сдвигом ряда уровня
func _muzzle_to_world(m: Vector2) -> Vector2:
	var size := sprite.sprite_frames.get_frame_texture("idle", 0).get_size()
	var base: Vector2 = sprite.sprite_frames.get_meta("base_point", Vector2(size.x / 2.0, size.y))
	var p := Vector2(size.x / 2.0 + m.x, size.y + m.y) - base   # muzzle — от центра низа кадра (sheet_to_frames)
	p += _level_shift(_level_anim("attack"))   # ствол едет вместе с рядом уровня
	if aim.x < 0.0:   # выстрел влево — спрайт отразится (play_once), основание на месте
		p.x = -p.x
	return to_global(p * _level_k)

# Задержка снаряда до кадра выстрела листа (metadata shot_frame) — как у бойцов
func _shot_delay() -> float:
	var frames := sprite.sprite_frames
	if not frames.has_meta("shot_frame"):
		return 0.0
	return frames.get_meta("shot_frame") / frames.get_animation_speed(sprite.animation)

# Прозрачность OcclusionFader (self_modulate) — и на спрайт: дочерний узел self_modulate не наследует.
# Вне схватки стойка — один кадр (hold_idle_outside_battle)
func _process(delta: float) -> void:
	if sprite:
		sprite.modulate.a = self_modulate.a
		hold_idle_outside_battle(sprite)
		_apply_motion(delta)
	if _aura_ring != null and not BattleManager.is_battle_running():
		if is_instance_valid(_aura_ring):
			_aura_ring.dismiss()
		_aura_ring = null
		queue_redraw()

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
	_draw_level_ring()
	if _aura_ring == null and stats.get("slow_radius", 0.0) > 0.0:   # в бою — кольцо ауры (_show_aura)
		draw_circle(Vector2.ZERO, stats["slow_radius"], SLOW_AURA_COLOR)
		draw_arc(Vector2.ZERO, stats["slow_radius"], 0.0, TAU, 48, SLOW_AURA_LINE, 1.5, true)
	if _aura_ring == null and stats.get("poison_radius", 0.0) > 0.0:
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
	var top: float
	if sprite:
		# над моделью, не над холстом кадра (06.11.2026: у кадров уровня над зданием пустой холст — ромбики
		# висели в воздухе или ложились на соседние здания); высота — по силуэту кадра стойки уровня, раз на ряд
		var key := "%s|%.4f" % [_level_anim("idle"), _level_k]
		if key != _pip_key:
			_pip_key = key
			_pip_top = -_visual_height()
		top = _pip_top - LEVEL_PIP_SIZE * 2.0
	else:
		top = get_occlusion_rect().position.y - global_position.y - LEVEL_PIP_SIZE * 2.0
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
	"plague_cauldron": AREA_CROSS,   # атаки соседних отрядов отравляют
}

static func get_effect_tiles(type: String, at: Vector2i) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for d in EFFECT_AREAS.get(type, []):
		tiles.append(at + d)
	return tiles

# Подсказка: название и уровень, что делает (с текущими цифрами), можно ли улучшить
func describe() -> String:
	return "\n".join(["%s · ур. %d/%d" % [card.title, card.building_level, CardData.MAX_BUILDING_LEVEL],
		effect_text(), upgrade_text()])

func upgrade_text() -> String:
	return "Такая же карта — уровень +1" if card.can_level_up_building() else "Максимальный уровень"

# Что делает здание — с текущими цифрами (подсказка describe и справка SquadInspector)
func effect_text() -> String:
	var lines: Array[String] = []
	match building_type:
		"tower":
			lines.append("Стреляет в ближайшего врага на всём поле: %d урона, %.1f выстр./с" % [
				stats.get("damage", 0.0), stats.get("attack_speed", 0.0)])
		"wall":   # стена владений клетку не занимает (KingdomWall) — описание карты
			lines.append("Стена вокруг владений: звено %d HP, щит цитадели +%d в каждом бою" % [
				stats.get("wall_hp", 0.0), stats.get("shield", 0.0)])
		"artillery":
			lines.append("В бою — клик по полю: залп %d урона в радиусе %d px, перезарядка %.1f с" % [
				stats.get("damage", 0.0), stats.get("splash_radius", 0.0), stats.get("cooldown", 0.0)])
		"barracks":
			if card.faction == "chaos":   # Святилище культа: не лечит, отряд бога рядом — павшие встают его бойцами
				lines.append(("После каждой победы возвращают %d павших бойцов отрядам на соседних клетках (подсвечены). "
					+ "Отряд бога Хаоса рядом — павшие других соседей встают его бойцами (сила — по редкости отряда)") \
					% floori(stats.get("refill", 0.0)))
			else:
				lines.append("После каждой победы лечат отряды на соседних клетках (подсвечены) на %d%% HP и возвращают %d павших" \
					% [roundi(stats.get("heal", 0.0) * 100.0), floori(stats.get("refill", 0.0))])
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
			lines.append("Каждый убитый враг: +%.1f%% урона всей армии, отрядам Кхорна ещё +%.1f%%, до конца боя (до +%d%%)" % [
				stats.get("per_kill", 0.0) * 100.0, stats.get("khorne_per_kill", 0.0) * 100.0,
				roundi(stats.get("max_bonus", 0.0) * 100.0)])
		"plague_cauldron":
			lines.append("Травит врагов в круге %d px: яд %.1f ур/с. Атаки отрядов на соседних клетках (подсвечены) отравляют: %.1f ур/с" % [
				stats.get("poison_radius", 0.0), stats.get("poison", 0.0), stats.get("neighbour_poison", 0.0)])
		"warp_spire":
			lines.append("Молния варпа по ближайшему врагу: %d урона, оглушение %.1f с, %.1f выстр./с" % [
				stats.get("damage", 0.0), stats.get("stun", 0.0), stats.get("attack_speed", 0.0)])
		"pleasure_shrine":
			lines.append("Замедляет врагов на %d%% в круге %d px" % [
				roundi((1.0 - stats.get("slow_mult", 1.0)) * 100.0), stats.get("slow_radius", 0.0)])
		_:
			lines.append(card.description)
	if not special_active():
		lines.append("Не ваш %s — особый эффект не действует" % ("бог" if card.faction == "chaos" else "орден"))
	return "\n".join(lines)


# Область экрана (мировые координаты), которую закрывают блоки здания —
# OcclusionFader делает здание полупрозрачным, если за ним стоит боец
func get_occlusion_rect() -> Rect2:
	if sprite:
		# по силуэту кадра стойки уровня, не по холсту (06.11.2026: холст уровня ×1.6 с пустыми полями — рамка
		# накрывала бойцов на соседних клетках, и здание гасло на расстановке без причины)
		var used := _idle_used_rect()
		if sprite.flip_h:
			var w := sprite.sprite_frames.get_frame_texture(_level_anim("idle"), 0).get_width()
			used.position.x = w - used.end.x
		return Rect2(global_position + sprite.position + (sprite.offset + used.position) * sprite.scale,
			used.size * sprite.scale)
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
	var barrels := [to_global(_block_top(0.5, 0.5, TOWER_LEVELS) + aim.normalized() * BARREL_LENGTH)]
	var delay := 0.0
	if sprite:   # свой спрайт: снаряд из каждого его ствола (на кадре вспышки, если есть ряд attack)
		barrels = _sprite_barrels()
		if play_once("attack"):
			delay = _shot_delay()
	for barrel_end in barrels:   # залп: урон поровну, сумма — как у одного выстрела; оглушение — у каждого
		var shot = Projectile.launch(get_parent(), SHOOTERS[building_type], barrel_end, target, aim_offset, delay)
		shot.damage = stats.get("damage", 0.0) / barrels.size()
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
	var barrels := [to_global(base + aim.normalized() * ARTILLERY_BARREL_LENGTH)]
	var delay := 0.0
	if sprite:
		barrels = _sprite_barrels()
		if play_once("attack"):
			delay = _shot_delay()
	var hellfire: bool = card.faction == "chaos"
	for i in barrels.size():   # залп: ракета из каждого ствола в ту же точку, урон поровну (сумма прежняя)
		var shot = Projectile.launch(get_parent(), HELLFIRE_PROJECTILE if hellfire else ARTILLERY_PROJECTILE,
			barrels[i], null, point, delay)
		shot.damage = stats.get("damage", 0.0) / barrels.size()
		shot.splash_radius = stats.get("splash_radius", 0.0)
		shot.splash_team = GameConstants.TEAM_ENEMY
		if i == 0:   # взрыв (огонь, дым, обломки), круг и тряска камеры — раз за залп: ракеты ложатся в одну точку
			shot.on_impact = _show_explosion
			shot.impact_vfx = HELLFIRE_IMPACT_VFX if hellfire else ARTILLERY_IMPACT_VFX
		shot.arc_height = ARTILLERY_ARC
		if delay > Soldier.TIMER_EPSILON and is_inside_tree():   # вспышка — на кадре выстрела листа, когда ствол поднят
			get_tree().create_timer(delay, false).timeout.connect(_play_fire_animation.bind(barrels[i]))
		else:
			_play_fire_animation(barrels[i])
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
var _altar_khorne_bonus: float = 0.0   # отрядам Кхорна — сверх прибавки армии (решение пользователя 25.10.2026)

func _tick_skull_altar() -> void:
	var kills := maxi(_enemies_at_start - SoldierRegistry.get_alive_soldiers_of_team(GameConstants.TEAM_ENEMY).size(), 0)
	var khorne := minf(kills * stats.get("khorne_per_kill", 0.0), stats.get("max_bonus", 0.0)) if special_active() else 0.0
	if khorne > _altar_khorne_bonus:
		var kk := (1.0 + khorne) / (1.0 + _altar_khorne_bonus)
		_altar_khorne_bonus = khorne
		for s in SoldierRegistry.get_alive_soldiers_of_team(GameConstants.TEAM_PLAYER):
			if not s.charmed and s.data.get_god() == "khorne":
				s.current_damage *= kk
	var bonus := minf(kills * stats.get("per_kill", 0.0), stats.get("max_bonus", 0.0))
	if bonus <= _altar_bonus:
		return
	var k := (1.0 + bonus) / (1.0 + _altar_bonus)
	_altar_bonus = bonus
	# Вид: череп встаёт в стопку над алтарём (на прибавку — один, стопка растёт до предела бонуса)
	var n := roundi(bonus / maxf(stats.get("per_kill", 0.01), 0.001))
	Vfx.spawn(get_parent(), "skull_add", global_position + Vector2(((n % 5) - 2) * SKULL_SPREAD, -SKULL_RISE))
	for s in SoldierRegistry.get_alive_soldiers_of_team(GameConstants.TEAM_PLAYER):
		s.current_damage *= k

# Особый эффект здания ордена / бога (на соседние отряды, прибавка отрядам Кхорна у Алтаря) — только когда игрок играет
# за этого бога / орден (решение пользователя 25.10.2026); общие здания — всегда. Основное действие (аура, выстрел) — всегда
func special_active() -> bool:
	var owner := Chapters.building_owner(card.id)
	return owner == "" or owner == RunManager.player_chapter

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
		b._altar_khorne_bonus = 0.0
		b._show_aura()
		if b.stats.get("shield", 0.0) > 0.0:
			b.play_once("shield")   # стена подняла щит цитадели (ряд листа, если есть)
		if not b.special_active():
			continue   # здание чужого бога / ордена — эффект на соседей не действует
		var area := get_effect_tiles(b.building_type, b.tile)
		for sq in squads:
			if sq.tile in area:
				for s in sq.soldiers:
					b._apply_start_effect(s)

# Аура здания в бою — кольцо на земле вместо круга расстановки (AuraRing; только вид; снимает _process после боя)
func _show_aura() -> void:
	var kind := ""
	var r: float = 0.0
	if stats.get("poison_radius", 0.0) > 0.0:
		kind = "plague"
		r = stats["poison_radius"]
	elif stats.get("slow_radius", 0.0) > 0.0:
		kind = "pleasure"   # замедляет только Святилище Slaanesh: стена владений — преграда (KingdomWall)
		r = stats["slow_radius"]
	if kind == "" or _aura_ring != null:
		return
	_aura_ring = AuraRing.at(global_position, r, kind)
	queue_redraw()

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
		"plague_cauldron":
			s.bonus_poison_power += stats.get("neighbour_poison", 0.0)

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
