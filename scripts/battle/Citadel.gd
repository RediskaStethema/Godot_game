class_name Citadel
extends Node2D

# Цитадель игрока на клетке IsoGrid.citadel_tile. Вид — по теме расы игрока
# (FactionTheme.current()["citadel"]): башня из блоков тайлсета или анимированный
# лист кадров (стоит / стреляет / ранена / рушится).
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
# Полоска HP — в стиле полосок отрядов (SquadBar, решение пользователя 24.10.2026: была голая черта): подложка,
# стальная кромка, заливка, потерянное — тёмно-красным, деления по четвертям, справа — число HP
const HP_BAR_SIZE = Vector2(90, 7)
const HP_BAR_GAP: float = 14.0
const HP_BAR_TICKS: int = 4
const HP_FONT_SIZE: int = 20      # крупный кегль, уменьшенный HP_FONT_SCALE — мелкий рассыпается
const HP_FONT_SCALE: float = 0.5
const SHIELD_BAR_HEIGHT: float = 4.0
# Контур спрайта — как у зданий (Building.OUTLINE_WORLD_PX, Palette.BUILDING_OUTLINE), решение пользователя 24.10.2026;
# в свет местности — как здания (тема "building_env": оттенок, насыщенность, приглушение светов, затемнение
# к основанию, мягкий контур), решение пользователя 25.10.2026: новые кадры ярче зданий и грунта
const SHIELD_COLOR = UITheme.SHIELD_BLUE
# Враг атакует цитадель, когда до её центра не больше его дальности + HIT_RADIUS
const HIT_RADIUS: float = 50.0
# Попадание по цитадели: белеет, как боец (Soldier.HIT_FLASH_SHADER), и плавно гаснет
const HIT_FLASH_STRENGTH: float = 0.8   # доля белого на пике
const HIT_FLASH_TIME: float = 0.18      # секунд до исходного цвета
const HIT_FLASH_SHADER = """shader_type canvas_item;
uniform float flash = 0.0;
void fragment() {
	vec4 c = COLOR;   // уже текстура × modulate — texture() ещё раз дал бы цвет в квадрат
	COLOR = vec4(mix(c.rgb, vec3(1.0), flash), c.a);
}"""

# --- Орудие цитадели ---
const DAMAGE: float = 30.0          # каждому врагу в радиусе взрыва
const ATTACK_SPEED: float = 1.0     # выстрелов в секунду
const ATTACK_RANGE: float = 320.0   # пиксели от центра цитадели
const SPLASH_RADIUS: float = 80.0   # радиус взрыва вокруг цели
const SHOT_SHOW_TIME: float = 0.2   # сколько секунд виден взрыв
const SHOT_PROJECTILE: String = "fireball"   # огненный снаряд FXpack13 (Projectile.EFFECTS), взрыв — при попадании
# Взрыв снаряда — дым и огонь, как у Thunderfire (Vfx, assets/Spritesheets). explosion_side пака Pixel
# не использовать — не подходит по стилю (решение пользователя 18.10.2026)
const SHOT_IMPACT_VFX = ["explosion", "fireball"]
const SHOT_COLOR = UITheme.AMBER_LIGHT

var attack_timer: float = 0.0
var shot_timer: float = 0.0
# HP-бар — отдельный дочерний узел: OcclusionFader гасит цитадель через
# self_modulate, а дочерние узлы его не наследуют — бар остаётся ярким
var _hp_bar: Node2D
var shot_target: Vector2 = Vector2.ZERO   # в глобальных координатах
# Лист кадров темы (null — башня из блоков). Гасится вместе с цитаделью
# (OcclusionFader меняет self_modulate — переносим его на спрайт)
var _sprite: AnimatedSprite2D = null
var _sheet: Dictionary = {}
# Выстрел ждёт кадра вспышки листа ("shot_frame"): {"point", "target", "time"}; пусто — нет
var _pending_shot: Dictionary = {}
# Вспышка попадания: один материал на крепость (блоки — сам узел, лист — спрайт; HP-бар без него)
var _flash_material: ShaderMaterial
# Спрайт листа — шейдер бойцов (контур + вспышка; Soldier.unit_shader), свой материал: вспышка — только этой крепости
var _sprite_material: ShaderMaterial = null
var _env: Dictionary = {}   # тема "building_env" (пусто — без света местности)
var _siege_shown: bool = false   # тревога штурма показана (цитадель — новая на каждый бой)
var _flash_left: float = 0.0   # сек до конца вспышки попадания (гаснет в _process, не Tween на удар)

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	material = _get_flash_material()
	apply_theme(FactionTheme.current().get("citadel", {}))
	_hp_bar = Node2D.new()
	_hp_bar.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR   # число — не пиксельным фильтром мира
	_hp_bar.draw.connect(_draw_hp_bar)
	add_child(_hp_bar)
	BattleManager.citadel_hp_changed.connect(_on_hp_changed)

func _exit_tree() -> void:
	if BattleManager.citadel == self:
		BattleManager.citadel = null

# Вид цитадели из темы: пусто — блоки, "sheet" — анимированный лист кадров
func apply_theme(citadel_theme: Dictionary) -> void:
	if _sprite:
		_sprite.queue_free()
		_sprite = null
	_sheet = citadel_theme
	if not _sheet.has("sheet"):
		queue_redraw()
		return
	var tex = FactionTheme.load_texture(_sheet["sheet"])
	if tex == null:
		push_warning("Citadel: нет листа кадров %s — башня из блоков" % _sheet["sheet"])
		_sheet = {}
		queue_redraw()
		return
	var frame: Vector2i = _sheet["frame_size"]
	var frames = SpriteFrames.new()
	frames.remove_animation("default")
	for anim in _sheet["rows"]:
		var row: Array = _sheet["rows"][anim]
		frames.add_animation(anim)
		frames.set_animation_speed(anim, float(row[2]) if row.size() > 2 else _sheet.get("fps", 8.0))
		frames.set_animation_loop(anim, anim == "idle")
		for i in range(int(row[1])):
			var at = AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(i * frame.x, int(row[0]) * frame.y, frame.x, frame.y)
			frames.add_frame(anim, at)
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = frames
	_sprite.centered = false
	var k: float = _sheet.get("scale", 1.0)
	_sprite.scale = Vector2(k, k)
	_sprite.position = -Vector2(_sheet.get("anchor", Vector2(frame.x / 2.0, frame.y))) * k
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.modulate = _sheet.get("tint", Color.WHITE)   # вспышка попадания — modulate узла, не спрайта
	_sprite_material = ShaderMaterial.new()
	_sprite_material.shader = Soldier.unit_shader()
	_env = FactionTheme.current().get("building_env", {})
	var outline_px: float = _env.get("outline_px", Building.OUTLINE_WORLD_PX)
	_sprite_material.set_shader_parameter("outline_px", float(maxi(1, roundi(outline_px / maxf(k, 0.01)))))
	_sprite_material.set_shader_parameter("outline_color", Color(Palette.BUILDING_OUTLINE, _env.get("outline_alpha", 1.0)))
	_sprite_material.set_shader_parameter("env_sat", _env.get("sat", 1.0))
	_sprite_material.set_shader_parameter("env_knee", _env.get("knee", 0.0))
	_sprite_material.set_shader_parameter("ao_strength", _env.get("ao", 0.0))
	_sprite.material = _sprite_material
	_sprite.animation_finished.connect(_on_sprite_animation_finished)
	_sprite.animation_changed.connect(_update_env_ao)
	add_child(_sprite)
	move_child(_sprite, 0)   # под HP-баром
	_sprite.play("idle" if BattleManager.citadel_hp > 0.0 else "fall")
	_update_env_ao()
	queue_redraw()

# Затемнение к основанию — в UV листа целиком (кадр — AtlasTexture): полоса у anchor в ряду текущей анимации
func _update_env_ao() -> void:
	if _sprite == null or not _sheet["rows"].has(_sprite.animation):
		return
	var fh: float = Vector2i(_sheet["frame_size"]).y
	var sheet_h: float = FactionTheme.load_texture(_sheet["sheet"]).get_height()
	var base: float = int(_sheet["rows"][_sprite.animation][0]) * fh + Vector2(_sheet.get("anchor", Vector2(0, fh))).y
	_sprite_material.set_shader_parameter("ao_from", (base - Building.ENV_AO_HEIGHT * fh) / sheet_h)
	_sprite_material.set_shader_parameter("ao_to", (base + Building.ENV_AO_BELOW * fh) / sheet_h)

func has_sprite() -> bool:
	return _sprite != null

# Состояние листа кадров: рухнувшая остаётся рухнувшей; выстрел не перебивает
# анимацию попадания; нет такой анимации в листе — ничего
func play_state(anim: String) -> void:
	if _sprite == null or not _sprite.sprite_frames.has_animation(anim):
		return
	if _sprite.animation == "fall":
		return
	if anim == "attack" and _sprite.animation == "hit" and _sprite.is_playing():
		return
	_sprite.play(anim)

func get_sprite_animation() -> String:
	return _sprite.animation if _sprite else ""

func _on_sprite_animation_finished() -> void:
	if _sprite.animation in ["attack", "hit"]:
		_sprite.play("idle")

func _process(delta: float) -> void:
	if _sprite:
		_sprite.self_modulate = self_modulate * _env.get("tint", Color.WHITE)
	if _flash_left > 0.0:
		_flash_left = maxf(_flash_left - delta, 0.0)
		_set_flash(HIT_FLASH_STRENGTH * _flash_left / HIT_FLASH_TIME)

func _draw() -> void:
	Building.draw_ground_shadow(self, Vector2.ZERO, IsoGrid.TILE_WIDTH * SHADOW_WIDTH)
	# BLOCKS уже упорядочены от дальних подклеток к ближним, внутри — снизу вверх
	if _sprite == null:
		for b in BLOCKS:
			TerrainTiles.draw_block(self, TerrainTiles.tile(b[0]), _block_top(b[1], b[2], b[3]), Color.WHITE, BLOCK_SCALE)
	if shot_timer > Soldier.TIMER_EPSILON:
		var a = shot_timer / SHOT_SHOW_TIME
		var to = to_local(shot_target)
		draw_circle(to, SPLASH_RADIUS * 0.5, Color(SHOT_COLOR, 0.35 * a))
		draw_arc(to, SPLASH_RADIUS, 0.0, TAU, 32, Color(SHOT_COLOR, 0.6 * a), 2.0, true)

const SHADOW_WIDTH: float = 1.7   # тень на грунте — доля клетки (крепость шире клетки)

# Откуда вылетает выстрел — ствол листа ("muzzle", px кадра) или верх донжона
func _muzzle() -> Vector2:
	if _sprite and _sheet.has("muzzle"):
		return _sprite.position + Vector2(_sheet["muzzle"]) * _sprite.scale
	return Vector2(0, _top_y() + 6.0)

# Центр верхней грани блока подклетки (i, j) на ярусе level
func _block_top(i: int, j: int, level: int) -> Vector2:
	var sub = Vector2(IsoGrid.TILE_WIDTH, IsoGrid.TILE_HEIGHT) * BLOCK_SCALE / 2.0
	return Vector2((i - j) * sub.x, (i + j - 1) * sub.y) - Vector2(0, TerrainTiles.LEVEL_HEIGHT * BLOCK_SCALE * level)

# Верхняя точка донжона (у листа кадров — верх кадра)
func _top_y() -> float:
	if _sprite:
		return _sprite.position.y
	return _block_top(0, 0, KEEP_LEVELS).y - IsoGrid.TILE_HEIGHT * BLOCK_SCALE / 2.0

# Портрет для справки (SquadInspector): кадр стойки листа темы; блоки без листа — null
func get_portrait() -> Texture2D:
	if _sprite and _sprite.sprite_frames.has_animation("idle"):
		return _sprite.sprite_frames.get_frame_texture("idle", 0)
	return null

# Область экрана (мировые координаты), которую закрывают блоки цитадели
func get_occlusion_rect() -> Rect2:
	if _sprite:
		var fs = Vector2(_sheet["frame_size"]) * _sprite.scale
		return Rect2(_sprite.position + global_position, fs)
	var rect = Rect2()
	for b in BLOCKS:
		var r = TerrainTiles.block_rect(_block_top(b[1], b[2], b[3]), BLOCK_SCALE)
		rect = r if rect.size == Vector2.ZERO else rect.merge(r)
	return Rect2(rect.position + global_position, rect.size)

# Рисуется в дочернем узле _hp_bar (координаты те же — узел в начале цитадели)
func _draw_hp_bar() -> void:
	var rect = Rect2(Vector2(-HP_BAR_SIZE.x / 2.0, _top_y() - HP_BAR_GAP - HP_BAR_SIZE.y), HP_BAR_SIZE)
	_hp_bar.draw_rect(rect.grow(2.0), Palette.OUTLINE)
	_hp_bar.draw_rect(rect.grow(1.0), Palette.GOLD_DIM, false, 1.0)
	var ratio = clampf(float(BattleManager.citadel_hp) / BattleManager.CITADEL_MAX_HP, 0.0, 1.0)
	_hp_bar.draw_rect(rect, Palette.RED.darkened(0.55))   # потерянное
	_hp_bar.draw_rect(Rect2(rect.position, Vector2(rect.size.x * ratio, rect.size.y)), UITheme.GOLD)
	_hp_bar.draw_rect(Rect2(rect.position, Vector2(rect.size.x * ratio, 1.0)), Palette.GOLD_BRIGHT)   # блик сверху
	for i in range(1, HP_BAR_TICKS):
		var x: float = rect.position.x + rect.size.x * i / HP_BAR_TICKS
		_hp_bar.draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), Palette.OUTLINE, 1.0)
	var text := str(ceili(BattleManager.citadel_hp))
	var font := UITheme.world_font()
	var fs := UITheme.world_px(HP_FONT_SIZE)
	var h := font.get_ascent(fs) * HP_FONT_SCALE
	_hp_bar.draw_set_transform(Vector2(rect.end.x + 5.0, rect.get_center().y + h * 0.35), 0.0, Vector2(HP_FONT_SCALE, HP_FONT_SCALE))
	_hp_bar.draw_string_outline(font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Palette.OUTLINE)
	_hp_bar.draw_string(font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.GOLD_BRIGHT)
	_hp_bar.draw_set_transform(Vector2.ZERO)
	# Щит от стен — синяя полоска над HP (доля от максимального HP)
	if BattleManager.citadel_shield > 0.0:
		var srect = Rect2(rect.position - Vector2(0, SHIELD_BAR_HEIGHT + 3.0), Vector2(rect.size.x, SHIELD_BAR_HEIGHT))
		_hp_bar.draw_rect(srect.grow(1.0), Color(0, 0, 0, 0.8))
		var sratio = clampf(BattleManager.citadel_shield / BattleManager.CITADEL_MAX_HP, 0.0, 1.0)
		_hp_bar.draw_rect(Rect2(srect.position, Vector2(srect.size.x * sratio, srect.size.y)), SHIELD_COLOR)

# -------------------------------------------------------
# БОЙ (штурм)
# -------------------------------------------------------
func tick(delta: float) -> void:
	if BattleManager.siege_started and not _siege_shown:   # армия пала — тревога: кольцо от цитадели
		_siege_shown = true
		Vfx.spawn(get_parent(), "siege_alarm", global_position)
	if shot_timer > Soldier.TIMER_EPSILON:
		shot_timer -= delta
		queue_redraw()
	if not _pending_shot.is_empty():
		_pending_shot["time"] -= delta
		if _pending_shot["time"] <= Soldier.TIMER_EPSILON:
			var target = _pending_shot["target"]
			if not is_instance_valid(target) or target.current_state == Soldier.State.DEAD:
				target = null
			_launch_shot(_pending_shot["point"] if target == null else target.global_position, target)
			_pending_shot = {}
	attack_timer -= delta
	if attack_timer > Soldier.TIMER_EPSILON:
		return
	var target = _find_target()
	if target == null:
		return
	attack_timer = 1.0 / ATTACK_SPEED
	_fire_at(target.global_position, target)

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

# Выстрел снарядом: взрыв (урон всем врагам в SPLASH_RADIUS) — где он попадёт.
# target — за кем снаряд наводится (null — в точку point)
# С листом кадров снаряд вылетает на кадре вспышки ствола ("shot_frame" ряда attack)
func _fire_at(point: Vector2, target: Soldier = null) -> void:
	play_state("attack")
	var delay = _shot_delay()
	if delay > Soldier.TIMER_EPSILON:
		_pending_shot = {"point": point, "target": target, "time": delay}
		return
	_launch_shot(point, target)

# Сколько секунд от начала анимации выстрела до кадра вспышки (0 — сразу)
func _shot_delay() -> float:
	if _sprite == null or not _sheet.has("shot_frame") or _sprite.animation != "attack":
		return 0.0
	return float(_sheet["shot_frame"]) / _sprite.sprite_frames.get_animation_speed("attack")

func _launch_shot(point: Vector2, target: Soldier) -> void:
	var shot = Projectile.launch(get_parent(), SHOT_PROJECTILE, to_global(_muzzle()), target,
			Vector2.ZERO if target else point)
	shot.damage = DAMAGE
	shot.splash_radius = SPLASH_RADIUS
	shot.splash_team = GameConstants.TEAM_ENEMY
	shot.on_impact = _show_explosion
	shot.impact_vfx = SHOT_IMPACT_VFX

func _show_explosion(point: Vector2) -> void:
	shot_target = point
	shot_timer = SHOT_SHOW_TIME
	queue_redraw()

# Враг атаковал цитадель
func take_hit(amount: float) -> void:
	AudioManager.play("citadel_hit")
	var shielded := BattleManager.citadel_shield > 0.0
	BattleManager.damage_citadel(amount)
	if shielded and BattleManager.citadel_shield <= 0.0:   # щит стен кончился — стена гаснет красным, искры у цитадели
		if BattleManager.has_kingdom_wall():
			BattleManager.kingdom_wall.flash_shield(true)
		Vfx.spawn(get_parent(), "hit_spark", global_position + Vector2(0.0, -40.0), 2.0)
	play_state("fall" if BattleManager.citadel_hp <= 0.0 else "hit")
	_flash_hit()

func _get_flash_material() -> ShaderMaterial:
	if _flash_material == null:
		var shader = Shader.new()
		shader.code = HIT_FLASH_SHADER
		_flash_material = ShaderMaterial.new()
		_flash_material.shader = shader
	return _flash_material

# Белая вспышка попадания: новый удар начинает её заново; гаснет счётчиком в _process — на штурме по
# цитадели бьют десятки врагов, Tween на каждый удар был бы лишним объектом (как у Soldier)
func _flash_hit() -> void:
	_set_flash(HIT_FLASH_STRENGTH)
	_flash_left = HIT_FLASH_TIME

func _set_flash(v: float) -> void:
	_get_flash_material().set_shader_parameter("flash", v)
	if _sprite_material:
		_sprite_material.set_shader_parameter("flash", v)

func get_hit_flash() -> float:
	return _get_flash_material().get_shader_parameter("flash")

func _on_hp_changed(_hp: float) -> void:
	_hp_bar.queue_redraw()
