class_name Projectile
extends AnimatedSprite2D

# Снаряд: летит от ствола к цели и наносит урон В МОМЕНТ ПОПАДАНИЯ.
# Полёт — боевая логика: тикает от BattleManager с FIXED_TICK (BattleManager.projectiles),
# а рисуется плавно — в _process между тиками досчитывается доля шага (get_tick_alpha).
# Стреляют бойцы (UnitData.projectile), турель (spark) и цитадель на штурме (bolt, взрыв).

# Вид снаряда → лист кадров assets/effects/<папка>/spritesheet.png
const EFFECTS = {
	"bolt":    {"sheet": "res://assets/effects/Bolt/spritesheet.png",    "frames": 4},
	"charged": {"sheet": "res://assets/effects/charged/spritesheet.png", "frames": 6},
	"spark":   {"sheet": "res://assets/effects/spark/spritesheet.png",   "frames": 5},
}
const FPS: float = 14.0             # кадры эффектов — по 70 мс
const SCALE: float = 0.6            # листы рисованы крупно: шар charged — с голову марина
const SPEED: float = 750.0          # px/сек
const MAX_LIFETIME: float = 2.0     # сек — страховка от вечного полёта
# Красные заряды (Хаос): эффекты синие — меняем местами R и B, синий → оранжево-красный
const WARM_SHADER = "shader_type canvas_item;\nvoid fragment() { COLOR = texture(TEXTURE, UV).bgra * COLOR; }"

static var _frames_cache: Dictionary = {}   # вид → SpriteFrames
static var _warm_material: ShaderMaterial

# --- Что делает попадание (заполняет стрелок) ---
var damage: float = 0.0
var stun: float = 0.0               # сек оглушения цели (Librarian)
var knockback: float = 0.0          # сила отбрасывания от точки выстрела
var status: String = ""             # статус-эффект цели (StatusEffects), +1 стак
var status_power: float = 0.0
var status_duration: float = 0.0
var splash_radius: float = 0.0      # > 0 — урон всем бойцам splash_team в радиусе точки попадания
var splash_team: int = GameConstants.TEAM_ENEMY
var on_impact: Callable             # (точка) — вспышка взрыва у стрелка (цитадель)

var finished: bool = false

var _target: Node2D                 # Soldier / Citadel; null — летим в точку
var _aim_offset: Vector2
var _aim_point: Vector2
var _origin: Vector2
var _pos: Vector2                   # логическая позиция (меняется только в tick)
var _delay: float
var _life: float = 0.0

# Выстрел из точки from в цель (Soldier / Citadel): aim — куда в цели (смещение от её ног).
# target == null — летим в точку aim (глобальные координаты).
# delay — сек до вылета (вспышка в анимации атаки).
# Урон и эффекты задаются полями возвращённого снаряда.
static func launch(parent: Node, kind: String, from: Vector2, target: Node2D, aim: Vector2,
		delay: float = 0.0, warm: bool = false) -> Projectile:
	var p := Projectile.new()
	if EFFECTS.has(kind):
		p.sprite_frames = _get_frames(kind)
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # пиксель-арт
	p.z_index = 10   # поверх бойцов и построек
	p.scale = Vector2(SCALE, SCALE)
	p._target = target if is_instance_valid(target) else null
	p._aim_offset = aim if p._target else Vector2.ZERO
	p._aim_point = (p._target.global_position + aim) if p._target else aim
	p._origin = from
	p._pos = from
	p._delay = delay
	if warm:
		p.material = _get_warm_material()
	parent.add_child(p)
	p.global_position = from
	p.visible = delay <= Soldier.TIMER_EPSILON
	p._face(p._aim_point - from)
	if p.sprite_frames:
		p.play("fly")
	BattleManager.projectiles.append(p)
	return p

static func _get_frames(kind: String) -> SpriteFrames:
	if _frames_cache.has(kind):
		return _frames_cache[kind]
	var e: Dictionary = EFFECTS[kind]
	var sheet: Texture2D = load(e["sheet"])
	var count: int = e["frames"]
	var w: float = sheet.get_width() / float(count)
	var frames := SpriteFrames.new()
	frames.rename_animation("default", "fly")
	frames.set_animation_speed("fly", FPS)
	for i in count:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(i * w, 0, w, sheet.get_height())
		frames.add_frame("fly", atlas)
	_frames_cache[kind] = frames
	return frames

static func _get_warm_material() -> ShaderMaterial:
	if _warm_material == null:
		var shader := Shader.new()
		shader.code = WARM_SHADER
		_warm_material = ShaderMaterial.new()
		_warm_material.shader = shader
	return _warm_material

# -------------------------------------------------------
# ЛОГИКА (FIXED_TICK от BattleManager)
# -------------------------------------------------------
func tick(delta: float) -> void:
	if finished:
		return
	_life += delta
	_track_target()
	if _delay > Soldier.TIMER_EPSILON:
		_delay -= delta
		return
	visible = true
	var step := SPEED * delta
	if _pos.distance_to(_aim_point) <= step or _life > MAX_LIFETIME:
		_pos = _aim_point
		_impact()
		return
	_pos = _pos.move_toward(_aim_point, step)

# Самонаведение: живая цель тянет снаряд за собой. Цель погибла — летим в последнюю точку,
# урона там не будет (если только это не взрыв).
func _track_target() -> void:
	if _target == null:
		return
	if not is_instance_valid(_target) or (_target is Soldier and _target.current_state == Soldier.State.DEAD):
		_target = null
		return
	_aim_point = _target.global_position + _aim_offset

func _impact() -> void:
	finished = true
	var point := _aim_point - _aim_offset
	if splash_radius > 0.0:
		for e in SoldierRegistry.get_alive_soldiers_of_team(splash_team).duplicate():
			if e.global_position.distance_to(point) <= splash_radius:
				e.take_damage(damage * e.data.unit_weight)   # пехоту в толпе накрывает втрое больше
		if on_impact.is_valid():
			on_impact.call(point)
	elif _target is Soldier:
		var s: Soldier = _target
		s.take_damage(damage)
		if stun > 0.0:
			s.apply_stun(stun)
		if knockback > 0.0:
			s.apply_knockback(s.global_position - _origin, knockback)
		if status != "":
			s.apply_status(status, status_power, status_duration)
	elif _target is Citadel:
		_target.take_hit(damage)
	queue_free()

# -------------------------------------------------------
# ОТРИСОВКА — плавно между тиками
# -------------------------------------------------------
func _process(_delta: float) -> void:
	if finished or not visible:
		return
	var ahead := SPEED * GameConstants.FIXED_TICK * BattleManager.get_tick_alpha()
	var shown := _pos.move_toward(_aim_point, ahead)
	_face(_aim_point - shown)
	global_position = shown

# Листы нарисованы «летит вправо» — поворачиваем по направлению полёта
func _face(direction: Vector2) -> void:
	if direction.length_squared() > 0.01:
		rotation = direction.angle()
