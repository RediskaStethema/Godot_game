class_name Projectile
extends AnimatedSprite2D

# Снаряд: летит от ствола к цели и наносит урон В МОМЕНТ ПОПАДАНИЯ.
# Полёт — боевая логика: тикает от BattleManager с FIXED_TICK (BattleManager.projectiles),
# а рисуется плавно — в _process между тиками досчитывается доля шага (get_tick_alpha).
# Стреляют бойцы (UnitData.projectile), турель (spark) и цитадель на штурме (bolt, взрыв).

# Вид снаряда → лист кадров assets/effects/<папка>/spritesheet.png (кадры в ряд, «летит вправо»).
# Лист сеткой (size): кадры from..from+frames, scale — свой масштаб, pivot — точка кадра в позиции
# снаряда (голова), angle — поворот листа к «летит вправо» (ракета нарисована носом вверх)
const EFFECTS = {
	"bolt":    {"sheet": "res://assets/effects/Bolt/spritesheet.png",    "frames": 4},
	"charged": {"sheet": "res://assets/effects/charged/spritesheet.png", "frames": 6},
	"spark":   {"sheet": "res://assets/effects/spark/spritesheet.png",   "frames": 5},
	# снаряд Thunderfire Cannon: огненный хвост, кадры горения после поджига (поджиг — Vfx "muzzle_flash")
	"rocket":  {"sheet": "res://assets/Spritesheets/Rocket Fire 2-Sheet.png", "size": Vector2i(150, 150),
		"from": 5, "frames": 15, "fps": 20.0, "scale": 1.3, "pivot": Vector2(66, 76), "angle": PI / 2.0},
	# огненная струя Havoc: лист 96×48, 10 кадров, голова пламени справа
	"flame":   {"sheet": "res://assets/Spritesheets/Flamethrower-Sheet.png", "size": Vector2i(96, 48),
		"frames": 10, "fps": 18.0, "scale": 0.4, "pivot": Vector2(84, 24)},
	# FXpack13 (решение пользователя 18.10.2026: пак — если подходит по стилю): листы tools/frames_to_strip.py,
	# палитра — tools/vfx_grade.py. Огненный снаряд с хвостом углей — орудие цитадели
	"fireball": {"sheet": "res://assets/effects/FXpack13/fireball_sheet.png", "size": Vector2i(64, 64),
		"frames": 60, "fps": 30.0, "scale": 0.6, "pivot": Vector2(48, 32)},
	# плазменный шар, перекрашен в варп — Шпиль варпа и Рубриковые десантники (Tzeentch)
	"warp_bolt": {"sheet": "res://assets/effects/FXpack13/warp_bolt_sheet.png", "size": Vector2i(64, 64),
		"frames": 60, "fps": 30.0, "scale": 0.45, "pivot": Vector2(50, 32)},
	# болт Хаоса (лист пользователя assets/source_sheets/chaos_bolt_sheet.png, 19.10.2026): красное ядро в
	# зелёных разрядах — свои цвета (own_colors: цвет вспышки стрелка не перекрашивает)
	"chaos_bolt": {"sheet": "res://assets/effects/chaos_bolt/spritesheet.png", "size": Vector2i(214, 156),
		"frames": 8, "fps": 14.0, "scale": 0.11, "pivot": Vector2(194, 78), "own_colors": true},
	# пакет эффектов по ТЗ EFFECTS_NEEDED.txt (21.10.2026): звуковая волна Noise Marines (Slaanesh),
	# пылающий череп Hellfire Mortar — свои цвета
	"sonic_wave": {"sheet": "res://assets/effects/sonic_wave/spritesheet.png", "size": Vector2i(64, 64),
		"frames": 8, "fps": 18.0, "scale": 0.45, "pivot": Vector2(44, 32), "own_colors": true},
	# лист tools/fx_fix.py: кадры 80 px, череп — у правого края в одной точке (в пакете срезан сеткой)
	"hellfire_shell": {"sheet": "res://assets/effects/hellfire_shell/spritesheet.png", "size": Vector2i(80, 64),
		"frames": 8, "fps": 16.0, "scale": 0.6, "pivot": Vector2(63, 34), "own_colors": true},
}
const FPS: float = 14.0             # кадры эффектов — по 70 мс
const SCALE: float = 0.4            # листы рисованы крупно: шар charged — с голову марина (рост 31 px)
const SPEED: float = 750.0          # px/сек
const MAX_LIFETIME: float = 2.0     # сек — страховка от вечного полёта
const ARC_LOOKAHEAD: float = 4.0    # px вперёд по полёту — направление носа на дуге
# Взрыв (Vfx "explosion") при масштабе 1 накрывает примерно такой радиус, px
const EXPLOSION_VFX_RADIUS: float = 30.0
# Красные заряды (Хаос): эффекты синие — меняем местами R и B, синий → оранжево-красный
# Во fragment COLOR — уже цвет текстуры × modulate (документация CanvasItem shader): умножать на texture()
# ещё раз — цвет в квадрат, темнее и зеленее
const WARM_SHADER = "shader_type canvas_item;\nvoid fragment() { COLOR = COLOR.bgra; }"

# Снаряд в цвет вспышки стрелка (UnitData-лист: metadata/muzzle_color, tools/muzzle_color.py; решение
# пользователя 17.10.2026): яркость листа снаряда — в оттенок tint, почти белая сердцевина — белой
const TINT_SHADER = """shader_type canvas_item;
uniform vec3 tint;
void fragment() {
	vec4 c = COLOR;
	float l = max(c.r, max(c.g, c.b));
	float core = smoothstep(0.55, 0.95, min(c.r, min(c.g, c.b)));
	COLOR = vec4(mix(tint * l, vec3(1.0, 1.0, 0.92), core), c.a);
}"""

static var _frames_cache: Dictionary = {}   # вид → SpriteFrames
static var _warm_material: ShaderMaterial
static var _tint_shader: Shader
static var _tint_materials: Dictionary = {}   # цвет → ShaderMaterial (общие — по стрелкам одного листа)

# --- Что делает попадание (заполняет стрелок) ---
var damage: float = 0.0
var _kind: String = ""        # вид снаряда — звук выстрела «shot_<вид>»
var source: Squad = null   # чей выстрел — урон в итоги боя (BattleManager.credit_damage); здания — null
var stun: float = 0.0               # сек оглушения цели (Librarian)
var knockback: float = 0.0          # сила отбрасывания от точки выстрела
var status: String = ""             # статус-эффект цели (StatusEffects), +1 стак
var status_power: float = 0.0
var status_duration: float = 0.0
var splash_radius: float = 0.0      # > 0 — урон всем бойцам splash_team в радиусе точки попадания
var splash_team: int = GameConstants.TEAM_ENEMY
var on_impact: Callable             # (точка) — вспышка взрыва у стрелка (цитадель)
var impact_vfx: Array = ["explosion"]   # эффекты взрыва (Vfx), масштаб — по splash_radius
var arc_height: float = 0.0         # > 0 — рисуется по дуге (артиллерия), попадание то же
var origin_fn: Callable             # () -> Vector2: ствол стрелка сейчас — снаряд с задержкой вылетает из него

var finished: bool = false

var _target: Node2D                 # Soldier / Citadel; null — летим в точку
var _aim_offset: Vector2
var _aim_point: Vector2
var _origin: Vector2
var _pos: Vector2                   # логическая позиция (меняется только в tick)
var _delay: float
var _life: float = 0.0
var _angle_offset: float = 0.0
var _released: bool = false         # вылетел из ствола (кадр вспышки дошёл)
var _standing: bool = false         # тик вылета: стоит у ствола, летит со следующего (только вид — в _process)
var _show_after: float = 0.0        # с какой доли тика вылета (сек) снаряд виден — вспышка в листе стрелка

# Выстрел из точки from в цель (Soldier / Citadel): aim — куда в цели (смещение от её ног).
# tint (альфа > 0) — снаряд в цвет вспышки стрелка; иначе warm — синий → красный (Хаос), иначе как на листе.
# target == null — летим в точку aim (глобальные координаты).
# delay — сек до вылета (вспышка в анимации атаки).
# Урон и эффекты задаются полями возвращённого снаряда.
static func launch(parent: Node, kind: String, from: Vector2, target: Node2D, aim: Vector2,
		delay: float = 0.0, warm: bool = false, tint: Color = Color(0, 0, 0, 0)) -> Projectile:
	var p := Projectile.new()
	var e: Dictionary = EFFECTS.get(kind, {})
	if not e.is_empty():
		p.sprite_frames = _get_frames(kind)
		if e.has("pivot"):
			p.offset = Vector2(e["size"]) / 2.0 - e["pivot"]
	p._angle_offset = e.get("angle", 0.0)
	p.texture_filter = Vfx.filter   # как у эффектов
	p.z_index = 10   # поверх бойцов и построек
	var s: float = e.get("scale", SCALE)
	p.scale = Vector2(s, s)
	p._target = target if is_instance_valid(target) else null
	p._aim_offset = aim if p._target else Vector2.ZERO
	p._aim_point = (p._target.global_position + aim) if p._target else aim
	p._origin = from
	p._pos = from
	p._delay = delay
	if e.get("own_colors", false):   # лист в своих цветах — без перекраски
		pass
	elif tint.a > 0.0:   # цвет вспышки стрелка — важнее тёплой перекраски
		p.material = _get_tint_material(tint)
	elif warm:
		p.material = _get_warm_material()
	parent.add_child(p)
	p.global_position = from
	p.visible = delay <= Soldier.TIMER_EPSILON   # без задержки — виден у ствола сразу, звук — при вылете
	p._kind = kind
	p._face(p._aim_point - from)
	if p.sprite_frames:
		FrameBlend.attach(p)   # кадры перетекают (только вид)
		p.play("fly")
	BattleManager.projectiles.append(p)
	return p

# Все листы — заранее (BattleScene._ready): иначе первый выстрел каждого вида читает лист посреди боя
static func warm_cache() -> void:
	for kind in EFFECTS:
		_get_frames(kind)

static func _get_frames(kind: String) -> SpriteFrames:
	if _frames_cache.has(kind):
		return _frames_cache[kind]
	var e: Dictionary = EFFECTS[kind]
	var sheet: Texture2D = load(Vfx.graded_path(e["sheet"]))   # ракета и огнемёт — в палитре игры
	var count: int = e["frames"]
	var frames := SpriteFrames.new()
	frames.rename_animation("default", "fly")
	frames.set_animation_speed("fly", e.get("fps", FPS))
	var size := Vector2(sheet.get_width() / float(count), sheet.get_height())
	if e.has("size"):
		size = Vector2(e["size"])
	var cols := int(sheet.get_width() / size.x)
	var first: int = e.get("from", 0)
	for i in range(first, first + count):
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2((i % cols) * size.x, (i / cols) * size.y, size.x, size.y)
		frames.add_frame("fly", atlas)
	_frames_cache[kind] = frames
	return frames

static func _get_tint_material(tint: Color) -> ShaderMaterial:
	if not _tint_materials.has(tint):
		if _tint_shader == null:
			_tint_shader = Shader.new()
			_tint_shader.code = TINT_SHADER
		var m := ShaderMaterial.new()
		m.shader = _tint_shader
		m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
		_tint_materials[tint] = m
	return _tint_materials[tint]

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
		_show_after = _delay   # остаток задержки внутри этого тика — вспышка в листе стрелка (только вид)
		_delay -= delta
		if _delay > Soldier.TIMER_EPSILON:
			return
	if not _released:
		_release()
		return
	_standing = false
	var step := SPEED * delta
	if _pos.distance_to(_aim_point) <= step or _life > MAX_LIFETIME:
		_pos = _aim_point
		_impact()
		return
	_pos = _pos.move_toward(_aim_point, step)

# Кадр вспышки дошёл (без задержки — тик выстрела): снаряд у ствола (стрелок мог сдвинуться — Land Speeder
# кружит) и на этом тике стоит, летит со следующего: снаряд тикает в тот же тик, что выпущен, и раньше первый
# кадр рисовался на шаг полёта (75 px) впереди ствола — «из воздуха» (решение пользователя 21.10.2026)
func _release() -> void:
	_released = true
	_standing = true
	if origin_fn.is_valid():
		_origin = origin_fn.call()
		_pos = _origin
		global_position = _pos
	_face(_aim_point - _pos)
	visible = true
	AudioManager.play("shot_" + _kind)

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
		AudioManager.play("explosion")
		for e in SoldierRegistry.get_alive_soldiers_of_team(splash_team).duplicate():
			if e.global_position.distance_to(point) <= splash_radius:
				var amount: float = damage * e.data.unit_weight   # пехоту в толпе накрывает втрое больше
				BattleManager.credit_damage(source, clampf(amount - e.shield, 0.0, e.current_hp))
				e.take_damage(amount)
		if on_impact.is_valid():
			on_impact.call(point)
		for kind in impact_vfx:
			Vfx.spawn(get_parent(), kind, point, splash_radius / EXPLOSION_VFX_RADIUS)
	elif not is_instance_valid(_target):
		pass   # цель удалена в полёте (погибла и исчезла) — урона нет. _track_target её не обнулит:
			# удалённый объект в Godot 4 равен null, а «is» на нём падает
	elif _target is Soldier:
		var s: Soldier = _target
		AudioManager.play("hit")
		BattleManager.credit_damage(source, clampf(damage - s.shield, 0.0, s.current_hp))
		s.take_damage(damage)
		# Попадание в бойца — брызги крови пака NEw pack blood цвета жертвы (решение пользователя 18.10.2026;
		# техника — масло и искра); по камню цитадели — искры
		Vfx.spawn_blood(get_parent(), _aim_point, s.data, true, Soldier.EFFECT_SCALE)
		if stun > 0.0:
			s.apply_stun(stun)
			Vfx.spawn(get_parent(), "lightning", _aim_point, Soldier.EFFECT_SCALE)
		if knockback > 0.0:
			s.apply_knockback(s.global_position - _origin, knockback)
		if status != "":
			s.apply_status(status, status_power, status_duration)
			if status == StatusEffects.BURNING:
				Vfx.spawn(get_parent(), "flame_burst", _aim_point, Soldier.EFFECT_SCALE, rotation)
	elif _target.has_method("take_hit"):   # цитадель, звено стены владений (KingdomWall.Segment)
		_target.take_hit(damage)
		Vfx.spawn(get_parent(), "hit_spark", _aim_point, 1.0, rotation)
	queue_free()

# -------------------------------------------------------
# ОТРИСОВКА — плавно между тиками
# -------------------------------------------------------
func _process(_delta: float) -> void:
	if finished:
		return
	if not _released:   # ждёт кадра вспышки (видимость — по задержке в launch)
		global_position = _pos
		return
	# Тик вылета: снаряд стоит у ствола и появляется с кадром вспышки стрелка (задержка короче тика — турель
	# 1/16 с), а не летит вперёд по доле тика: искра уходила со ствола раньше вспышки, и выстрел в листе
	# загорался позади неё (23.10.2026)
	if _standing:
		visible = BattleManager.get_tick_alpha() * GameConstants.FIXED_TICK >= _show_after - Soldier.TIMER_EPSILON
		global_position = _pos
		return
	if not visible:
		return
	var ahead := SPEED * GameConstants.FIXED_TICK * BattleManager.get_tick_alpha()
	var shown := _pos.move_toward(_aim_point, ahead)
	if arc_height > 0.0:
		var next := _arc(shown.move_toward(_aim_point, ARC_LOOKAHEAD))
		shown = _arc(shown)
		_face(next - shown)
	else:
		_face(_aim_point - shown)
	global_position = shown

# Точка прямого полёта → на дуге: подъём по параболе, наибольший в середине пути
func _arc(point: Vector2) -> Vector2:
	var total := _origin.distance_to(_aim_point)
	if total < 1.0:
		return point
	var t := clampf(1.0 - point.distance_to(_aim_point) / total, 0.0, 1.0)
	return point - Vector2(0.0, arc_height * 4.0 * t * (1.0 - t))

# Листы нарисованы «летит вправо» — поворачиваем по направлению полёта
func _face(direction: Vector2) -> void:
	if direction.length_squared() > 0.01:
		rotation = direction.angle() + _angle_offset
