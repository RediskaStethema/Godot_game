class_name Soldier
extends Node2D

# -------------------------------------------------------
# СОСТОЯНИЯ
# -------------------------------------------------------
enum State { IDLE, MOVE, CHASE, ATTACK, CASTING, STUNNED, KNOCKBACK, RETREATING, DEAD }

# Затухание отбрасывания, пикселей/сек²
const KNOCKBACK_FRICTION: float = 600.0
# Ниже этой скорости отбрасывание считается законченным
const KNOCKBACK_STOP_SPEED: float = 5.0
# Высота бойца на экране (px) при sprite_scale = 1. Тайл — 128×64,
# спрайты разного исходного размера (marine 197 px, chaos 170 px) приводим к одной высоте.
# Решение пользователя: бойцы вдвое мельче прежних 62 px, зато их в отряде втрое больше
const TARGET_SPRITE_HEIGHT: float = 31.0
# Эффекты на бойце (Vfx) подобраны под рост 62 px
const EFFECT_SCALE: float = TARGET_SPRITE_HEIGHT / 62.0
# Полоска HP и уровень — у отряда (SquadBar); у бойца — тень, кольцо стороны и точки статусов
const STATUS_DOT_R: float = 1.5
const STATUS_DOT_GAP: float = 3.0
const SHADOW_RADIUS: float = 6.0       # × sprite_scale; эллипс сплюснут, как клетка изометрии
const SHADOW_FLATTEN: float = 0.5
const SHADOW_COLOR = Color(0, 0, 0, 0.35)
const SHADOW_SOFT = Color(0, 0, 0, 0.16)   # мягкий край тени: шире и прозрачнее
const SHADOW_SOFT_SCALE: float = 1.45
const RING_WIDTH: float = 2.0   # кольцо стороны под бойцом (решение пользователя 24.10.2026: было 1.5 / 0.6 — еле видно)
const RING_ALPHA: float = 0.85
# Всплывающие цифры (FloatingText) — только в схватке: удар не меньше FLOAT_MIN_DAMAGE
# (герои, техника, орудие; не каждый болт и не яд / огонь), лечение — порциями FLOAT_HEAL_STEP
const FLOAT_MIN_DAMAGE: float = 20.0
const FLOAT_HEAL_STEP: float = 10.0
const FLOAT_HIT_TO_ENEMY = Color(1.0, 0.86, 0.55)
const FLOAT_HIT_TO_PLAYER = UITheme.HIT_RED
const FLOAT_HEAL = UITheme.HEAL
# Боевой клич (Chaplain): кадр клича (анимация battle_cry листа, если есть), первый выстрел — после него
const BATTLE_CRY_TIME: float = 0.6
# Вспышка попадания: боец, получивший урон, на мгновение белеет (общий шейдер на всех)
const HIT_FLASH_TIME: float = 0.1
# Отдача от удара (решение пользователя 08.11.2026, только вид): спрайт на RECOIL_TIME с сжимается (RECOIL_SQUASH
# по высоте, половина — вширь) и отскакивает назад от лица на RECOIL_PX px мира, возвращается плавно
const RECOIL_TIME: float = 0.09
const RECOIL_SQUASH: float = 0.08
const RECOIL_PX: float = 1.5
const HEAVY_DUST_SCALE: float = 1.3   # sprite_scale, с которого боец пылит каждым шагом (Терминатор, техника)
const HIT_FLASH_STRENGTH: float = 0.85   # доля белого поверх цвета спрайта (с тинтом)
# Таймеры уменьшаются на 0.1 — из-за погрешности float 1.0 - 10*0.1 != 0
const TIMER_EPSILON: float = 0.001
# Темп бега — по скорости бойца, чтобы ноги не скользили: за цикл анимации бега боец проходит
# WALK_CYCLE_HEIGHTS своих ростов (два шага); множитель скорости анимации — в пределах WALK_SCALE_LIMITS.
# 23.10.2026 (решение пользователя — компромисс): было 2 роста и ×2 — в листах шаг ≈ 0.7–0.9 роста за цикл
# (размах ступней), ноги отставали от тела в 2.5 раза, бойцы «летели» (заметнее всего — Chapter Master).
# 1 рост и ×3: ноги вдвое быстрее, самые быстрые (Scout, Raptor) упираются в ×3 и чуть скользят
const WALK_CYCLE_HEIGHTS: float = 1.0
const WALK_SCALE_LIMITS = Vector2(0.5, 3.0)
# Шаг кодом (решение пользователя 23.10.2026, Screenshot 2026-10-23 172747.png: «бегут по воздуху в одной позе»):
# в листах бега ступни ходят на 2–4 px при росте бойца на поле ~40 px — шага не видно, строй скользит.
# На каждом шаге корпус проседает (scale.y от ног — ступни на земле): STEP_DIP роста, STEPS_PER_CYCLE шагов за цикл
const STEP_DIP: float = 0.06
const STEPS_PER_CYCLE: float = 2.0
# Бойцы отряда бьют вразнобой, а не залпом: первый удар после входа в ATTACK — со сдвигом
# до этой доли перезарядки (доля бойца — по номеру в отряде, золотое сечение: без случайности)
const ATTACK_STAGGER: float = 0.5
const GOLDEN_RATIO_FRAC: float = 0.618034
# Удар ближнего боя проходит на кадре hit_frame анимации атаки (метаданные frames.tres), если цель
# ещё рядом: дальность × это
const MELEE_HIT_REACH: float = 2.5   # ×дальность: при MELEE_RANGE 30 (21.10.2026) — 75 px, отходящий за замах не уходит
# Прыжок (UnitData.jump_range): скорость полёта не больше SoldierRegistry.GRID_SLACK за тик —
# поиск ближайшего по сетке остаётся точным; дуга (JUMP_HEIGHT × sprite_scale) — только вид
const JUMP_SPEED: float = 450.0
const JUMP_MIN_TIME: float = 0.3
const JUMP_HEIGHT: float = 30.0
const JUMP_TRAIL_RISE: float = 14.0   # px — шлейф ранца на высоте спины (боец роста 31)
# Отряд прыгает разом — приземления (удар по площади, оглушение) в один тик давали выброс тика
# (test_performance). Полёт бойца длиннее на attack_stagger × JUMP_STAGGER — отряд садится волной
const JUMP_STAGGER: float = 0.5
# Стрельба на ходу (UnitData.mobile_fire): скорость кружения — доля бега, дистанция — доля дальности
const MOBILE_FIRE_SPEED: float = 0.6
const MOBILE_FIRE_DISTANCE: float = 0.8

# -------------------------------------------------------
# ДАННЫЕ
# -------------------------------------------------------
var data: UnitData          # данные типа юнита (общие для всего отряда)
var team: int
# Runtime-статы: инициализируются из data, синергии меняют только их
var current_hp: float
var max_hp: float
var current_damage: float
var current_move_speed: float
# Щит Iron Halo на этот бой: снимается уроном раньше HP (runtime, из data.shield_ratio)
var shield: float = 0.0
var has_revived: bool = false   # Apothecarion поднимает бойца не больше раза за бой
var current_attack_range: float
var current_attack_speed: float
var current_heal_per_second: float
var target: Soldier = null  # цель — другой боец
var parent_squad: Squad     # отряд которому принадлежит боец

var current_state: State = State.IDLE
var previous_state: State = State.IDLE
var attack_timer: float = 0.0
var attack_stagger: float = 0.0   # доля сдвига первого удара [0, 1) — номер бойца в отряде
var cast_timer: float = 0.0
var _hit_timer: float = 0.0       # до удара ближнего боя на кадре hit_frame (0 — удара не ждём)
var _hit_target: Soldier = null
var stun_timer: float = 0.0
var retreat_timer: float = 0.0
var has_retreated: bool = false   # отступаем максимум один раз за бой
var knockback_velocity: Vector2 = Vector2.ZERO
# Статус-эффекты (StatusEffects): имя → {stacks, power, time, duration, dot_timer, spread_timer}
var status_effects: Dictionary = {}
var battle_cry_used: bool = false
# Прыжок (Assault): раз за бой; в полёте FSM стоит, контроль не действует
var jump_used: bool = false
# Приём босса (UnitData.special_kind): пока идёт (_special_left > 0) — FSM стоит, контроль не действует
var _special_cd: float = 0.0       # до готовности
var _special_left: float = 0.0     # до конца ряда special
var _special_release: float = 0.0  # до кадра срабатывания (0 — сработал)
var _special_wind: float = 0.0     # длина замаха до срабатывания (рывок / прыжок идут за неё)
var _special_from: Vector2 = Vector2.ZERO
var _special_to: Vector2 = Vector2.ZERO
var _special_target: Soldier = null
# Ось конуса — на начале замаха (решение пользователя 09.11.2026: метка рисовалась по цели в начале замаха, урон —
# по цели в момент удара, языки пламени — по взгляду спрайта; три разных направления): метка, урон и пламя — по ней
var _special_aim: Vector2 = Vector2.RIGHT
var _telegraph: BossFx = null      # метка зоны приёма на время замаха (только вид)
var _ground: BossFx = null         # тень и кольцо босса (только вид)
var enraged: bool = false          # ярость: босс впервые ≤ ENRAGE_AT HP — приём чаще
var _step_shake_at: int = -100000  # мс последней тряски от шага босса
var _leap_time: float = 0.0       # осталось лететь (0 — не в прыжке)
var _leap_duration: float = 0.0
var _leap_from: Vector2 = Vector2.ZERO
var _leap_to: Vector2 = Vector2.ZERO
var _leap_target: Soldier = null
var _leap_t: float = 1.0          # доля пути после последнего тика (дуга в _process); 1 — на земле
var _leap_prev: float = 1.0       # … и до него
var _jump_trail: Vfx = null       # шлейф ранца в полёте (только вид)
# Окапывание (Devastator): сколько стоит на месте; _moved — сдвинулся в этом тике
var _still_time: float = 0.0
var _entrench_vfx: Vfx = null       # бруствер окопавшегося (только вид)
var _moved: bool = false
var wall_segment: Node2D = null   # звено стены владений, в которое упёрся враг (KingdomWall.Segment) — ломает его
var _orbit_sign: float = 1.0      # стрельба на ходу: в какую сторону кружит (по номеру в отряде)
# Эффект при попадании от ордена (Salamanders) — если у юнита своего нет; ставит
# SynergyManager.apply_chapter_bonus в начале боя
var extra_on_hit_status: String = ""
var extra_on_hit_status_power: float = 0.0
var extra_on_hit_status_duration: float = 0.0
# Особые бонусы и минусы ордена / бога и их зданий (решение пользователя 18.10.2026) — на этот бой:
var damage_taken_mult: float = 1.0   # множитель получаемого урона (Slaanesh: ×1.1)
var lifesteal: float = 0.0           # доля урона ближнего боя, которая лечит бойца (Чаша крови)
# Благословения богов Хаоса и Котёл Нургла (решение пользователя 25.10.2026, ChaosGods) — на этот бой:
var bonus_poison_power: float = 0.0  # яд в атаках поверх своего эффекта, ур/с (ChaosGods.POISON_TIME)
var charm_chance: float = 0.0        # шанс поработить цель при попадании (Слаанеш)
var charmed: bool = false            # порабощён: бьётся за отряд, который поработил, после боя — не боец отряда
# Эффекты на бойце (Vfx) — только вид: статусы, оглушение / каст, лечение
var _status_vfx: Dictionary = {}   # статус → Vfx
var _state_vfx: Vfx
var _heal_vfx: Vfx
var _heal_unshown: float = 0.0   # вылечено, но ещё не показано цифрой

# Позиция в строю — смещение относительно центра отряда
var formation_offset: Vector2 = Vector2.ZERO
# Плавное движение (только вид): логика двигает бойца раз в тик, между тиками узел рисуется
# между позициями до и после последнего тика (BattleManager.get_tick_alpha). В начале тика
# позиция возвращается в логическую (SoldierRegistry.begin_tick) — бой считается как раньше
var _tick_from: Vector2 = Vector2.ZERO
var _tick_to: Vector2 = Vector2.ZERO
var _has_tick_from: bool = false
var _drawn_between: bool = false   # узел стоит в промежуточной точке, логическая — _tick_to

@onready var sprite: AnimatedSprite2D = $Sprite

signal died(soldier: Soldier)

# -------------------------------------------------------
# ИНИЦИАЛИЗАЦИЯ
# -------------------------------------------------------
# start_hp_ratio — доля HP: 1.0 свежий боец, меньше — раненый выживший
var convert_kind: String = ""   # боец бога Хаоса в чужом отряде (UnitData.saved_kinds), "" — свой

func setup(unit_data: UnitData, team_id: int, squad: Squad, offset: Vector2, start_hp_ratio: float = 1.0) -> void:
	data = unit_data
	team = team_id
	parent_squad = squad
	max_hp = data.get_max_hp()
	current_damage = data.get_damage()
	current_hp = max_hp * clampf(start_hp_ratio, 0.01, 1.0)
	current_move_speed = data.get_move_speed()
	shield = max_hp * data.shield_ratio
	current_attack_range = data.get_attack_range()
	current_attack_speed = data.get_attack_speed()
	current_heal_per_second = data.heal_per_second
	bonus_poison_power = ChaosGods.poison_power(data.get_god(), data.blessings)
	charm_chance = ChaosGods.charm_chance(data.get_god(), data.blessings)
	charmed = false
	formation_offset = offset
	attack_timer = 0.0
	attack_stagger = fmod(squad.soldiers.size() * GOLDEN_RATIO_FRAC, 1.0) if squad else 0.0
	_hit_timer = 0.0
	_hit_target = null
	current_state = State.IDLE
	previous_state = State.IDLE
	has_retreated = false
	status_effects.clear()
	_status_mask = 0
	battle_cry_used = false
	has_revived = false
	jump_used = false
	_special_cd = data.special_first
	enraged = false
	_special_left = 0.0
	_special_release = 0.0
	_special_target = null
	_leap_time = 0.0
	_leap_t = 1.0
	_leap_prev = 1.0
	_still_time = 0.0
	_orbit_sign = 1.0 if attack_stagger < 0.5 else -1.0

	_load_animations()
	_apply_chapter_colors()

	# Враги смотрят влево
	if team == GameConstants.TEAM_ENEMY:
		sprite.flip_h = true

# -------------------------------------------------------
# АНИМАЦИИ
# -------------------------------------------------------
# Анимация → подпапка спрайтов. Кадры: <sprite_path>/<папка>/0.png, 1.png, ...
# Если рядом есть <sprite_path>/frames.tres (tools/gif_to_frames.py из GIF) — берём его:
# там скорость каждой анимации и метаданные muzzle / shot_frame для снарядов.
const ANIMATION_FOLDERS = {"idle": "idle", "walk": "run", "attack": "attack", "death": "death"}
const ANIMATION_FPS: float = 8.0
# Набор кадров на папку спрайтов собирается один раз и общий для всех бойцов
# этого вида (раньше — заново на каждого бойца, с проверкой файлов на диске)
static var _frames_cache: Dictionary = {}   # sprite_path → SpriteFrames
# Один шейдер бойца (материалы общие по ключу "орден|подсветка|контур|вспышка"; _base_material — вне вспышки):
# - броня ордена (Chapters "armor"): синие насыщенные пиксели листа → тон ордена; только своим Космодесантникам;
# - подсветка края силуэта (тема "unit_rim" {color, strength}, решение пользователя 19.10.2026): пиксели у границы
#   фигуры — к тёплому свету, толщина RIM_SCREEN_PX; только бойцам расы игрока не в цветах ордена;
# - тёмный контур снаружи силуэта (решение пользователя 23.10.2026: бойцы отряда сливались в одно пятно) —
#   OUTLINE_WORLD_PX px мира у всех бойцов, цвет Palette.OUTLINE; передний боец отделён от заднего линией;
# - вспышка попадания (HIT_FLASH_STRENGTH белого) — поверх всего, кроме контура.
# Прозрачность узла (modulate) действует и на контур — она берётся из цвета вершины
const RIM_SCREEN_PX: float = 1.3
const OUTLINE_WORLD_PX: float = 0.9
# Бойцы в стиль поля (решение пользователя 08.11.2026): свет местности и объём — ключ темы "unit_env"
# {tint, sat, knee, ao, light, shade, grad, light_color}. Пикселизация (пиксель арта PIXEL_WORLD_PX px мира, шейдер
# pix) выключена — 0 (решение пользователя 08.11.2026, Screenshot 2026-11-08 092343: сетка в мире, при зуме камеры
# бойцы — размытые кляксы, не узнать); > 0 — включает
const PIXEL_WORLD_PX: float = 0.0
const UNIT_AO_FROM: float = 0.72   # затемнение к ногам: доля высоты кадра, откуда начинается
# Отсвет костров и свечения поля (IsoGridRenderer.light_at) на теле: раз в LIGHT_EVERY с, self_modulate спрайта
const LIGHT_EVERY: float = 0.25
# Статусы на теле (UNIT_SHADER st_*): [статус, uniform, цвет]; бит маски — индекс
const STATUS_BODY = [[StatusEffects.BURNING, "st_burn", Palette.FORGE], [StatusEffects.POISONED, "st_poison", Palette.POISON],
	[StatusEffects.SLOWED, "st_slow", Palette.FROST], [StatusEffects.EMPOWERED, "st_emp", Palette.AMBER_LIGHT]]
const UNIT_SHADER = """shader_type canvas_item;
uniform float armor = 0.0;
uniform float target_hue = 0.0;
uniform float sat_mult = 1.0;
uniform float val_mult = 1.0;
uniform float rim_px = 0.0;
uniform vec3 rim_color = vec3(1.0);
uniform float rim_strength = 0.5;
uniform float outline_px = 0.0;
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 0.85);
uniform float flash = 0.0;
// Здания в свет местности (Building.apply_environment; у бойцов — по умолчанию, без изменений): насыщенность,
// приглушение светов, затемнение к основанию (UV.y от ao_from до ao_to — к ao_strength)
uniform float env_sat = 1.0;
uniform float env_knee = 0.0;
uniform float ao_strength = 0.0;
uniform float ao_from = 1.0;
uniform float ao_to = 1.0;
// Смягчение пиксельности (цитадель, решение пользователя 07.11.2026 «менее пиксельной на 20%»): доля лёгкого
// размытия поверх резкой выборки по центру пикселя листа; работает при фильтре LINEAR у узла, 0 — как было
uniform float soften = 0.0;
// Бойцы в стиль поля (решение пользователя 08.11.2026: «юниты слишком выделяются на фоне»):
// pix — пикселизация: «пиксель арта» в pix текселей листа (сетка от угла кадра, цвет — средний по клетке через
// мип-уровень, край силуэта резкий), контур и объём — ровно в такой пиксель; 0 — как было (здания, цитадель);
// env_tint — оттенок местности (у зданий — self_modulate); vol_* — объём кодом, свет сверху (симметричный —
// отражённый враг освещён так же): верхние кромки светлее (vol_light, к цвету vol_color), нижние и боковые
// темнее (vol_shade), корпус светлее к плечам (vol_grad)
uniform float pix = 0.0;
uniform vec3 env_tint = vec3(1.0);
uniform float vol_light = 0.0;
uniform float vol_shade = 0.0;
uniform float vol_grad = 0.0;
uniform vec3 vol_color = vec3(1.0);
// Статусы на теле (решение пользователя 08.11.2026, EFFECTS_NEEDED 7.1–7.4 — кодом): 0/1 по статусу, вид по TIME:
// горение — мерцание огня, сильнее к верху; яд — зелёный налёт от ног, пульс; замедление — иней; усиление —
// контур в цвет st_emp_color и пульсирует
uniform float st_burn = 0.0;
uniform float st_poison = 0.0;
uniform float st_slow = 0.0;
uniform float st_emp = 0.0;
uniform vec3 st_burn_color = vec3(1.0, 0.5, 0.15);
uniform vec3 st_poison_color = vec3(0.55, 0.9, 0.3);
uniform vec3 st_slow_color = vec3(0.6, 0.8, 1.0);
uniform vec3 st_emp_color = vec3(1.0, 0.83, 0.4);
varying vec4 tint;
// Прозрачность листа в точке: lod ≥ 0 — с мип-уровня (пикселизация), иначе обычная выборка. Макрос, не функция:
// встроенный TEXTURE параметром в свою функцию Godot не передаёт («custom_samplers»)
#define ALPHA_AT(p) (lod >= 0.0 ? textureLod(TEXTURE, (p), lod).a : texture(TEXTURE, (p)).a)
vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}
vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}
void vertex() {
	tint = COLOR;   // modulate узла
}
void fragment() {
	vec4 c = COLOR;   // уже текстура × modulate — texture() ещё раз дал бы цвет в квадрат
	vec2 uv = UV;
	float lod = -1.0;
	vec2 cell = TEXTURE_PIXEL_SIZE * max(outline_px, 1.0);   // шаг объёма: без пикселизации — толщина контура
	if (pix > 0.0) {
		cell = TEXTURE_PIXEL_SIZE * pix;
		uv = (floor(UV / cell) + 0.5) * cell;
		lod = log2(pix);
		c = textureLod(TEXTURE, uv, lod);
		c.a = smoothstep(0.3, 0.6, c.a);
		c *= tint;
	}
	if (soften > 0.0) {   // ветка по параметру материала — производные определены
		// резкая выборка по центру пикселя листа + доля soften лёгкого размытия (4 плавные выборки в ±1 пиксель —
		// окно ≈ 3×3, с предумноженной альфой: без тёмной каймы по краю силуэта)
		vec2 texel = (floor(UV / TEXTURE_PIXEL_SIZE) + 0.5) * TEXTURE_PIXEL_SIZE;
		vec2 d = TEXTURE_PIXEL_SIZE;
		vec4 t0 = texture(TEXTURE, UV + d);
		vec4 t1 = texture(TEXTURE, UV - d);
		vec4 t2 = texture(TEXTURE, UV + vec2(d.x, -d.y));
		vec4 t3 = texture(TEXTURE, UV + vec2(-d.x, d.y));
		float ba = (t0.a + t1.a + t2.a + t3.a) * 0.25;
		vec3 brgb = (t0.rgb * t0.a + t1.rgb * t1.a + t2.rgb * t2.a + t3.rgb * t3.a) * 0.25 / max(ba, 1e-4);
		vec4 sharp = texture(TEXTURE, texel);
		c = mix(sharp, vec4(brgb, ba), soften) * tint;
	}
	if (armor > 0.5) {
		vec3 hsv = rgb2hsv(c.rgb);
		float blue = smoothstep(0.50, 0.55, hsv.x) * (1.0 - smoothstep(0.72, 0.77, hsv.x)) * smoothstep(0.2, 0.35, hsv.y);
		vec3 col = hsv2rgb(vec3(target_hue, clamp(hsv.y * sat_mult, 0.0, 1.0), clamp(hsv.z * val_mult, 0.0, 1.0)));
		c.rgb = mix(c.rgb, col, blue);
	}
	if (rim_px > 0.0) {
		vec2 d = pix > 0.0 ? cell : TEXTURE_PIXEL_SIZE * rim_px;
		float around = min(min(ALPHA_AT(uv + vec2(d.x, 0.0)), ALPHA_AT(uv - vec2(d.x, 0.0))),
			min(ALPHA_AT(uv + vec2(0.0, d.y)), ALPHA_AT(uv - vec2(0.0, d.y))));
		c.rgb = mix(c.rgb, rim_color, (1.0 - around) * step(0.5, c.a) * rim_strength);
	}
	if (env_sat != 1.0 || env_knee > 0.0 || ao_strength > 0.0) {
		float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
		c.rgb = mix(vec3(l), c.rgb, env_sat);
		// светлое приглушается, огонь и свечение (яркое и насыщенное) — нет
		float mx = max(c.r, max(c.g, c.b));
		float glow = smoothstep(0.45, 0.75, (mx - min(c.r, min(c.g, c.b))) / max(mx, 1e-4)) * smoothstep(0.35, 0.6, mx);
		c.rgb *= 1.0 - env_knee * smoothstep(0.25, 0.9, l) * (1.0 - glow);
		c.rgb *= 1.0 - ao_strength * smoothstep(ao_from, ao_to, UV.y);
	}
	c.rgb *= env_tint;
	if (vol_light > 0.0 || vol_shade > 0.0 || vol_grad > 0.0) {
		float solid = step(0.5, c.a);
		float up = ALPHA_AT(uv - vec2(0.0, cell.y));
		float dn = ALPHA_AT(uv + vec2(0.0, cell.y));
		float sides = 2.0 - ALPHA_AT(uv - vec2(cell.x, 0.0)) - ALPHA_AT(uv + vec2(cell.x, 0.0));
		float lit = (1.0 - step(0.5, up)) * solid;
		float shade = max(1.0 - step(0.5, dn), min(sides, 1.0) * 0.6) * solid * (1.0 - lit);
		c.rgb = mix(c.rgb, c.rgb * 1.45 + vol_color * 0.1, lit * vol_light);
		c.rgb *= 1.0 - shade * vol_shade;
		c.rgb *= 1.0 + vol_grad * (0.55 - UV.y);
	}
	if (st_burn + st_poison + st_slow + st_emp > 0.0) {
		float solid = step(0.5, c.a);
		if (st_burn > 0.0) {
			float fl = 0.5 + 0.5 * sin(TIME * 13.0 + UV.x * 38.0 + UV.y * 21.0) * sin(TIME * 8.3 - UV.y * 33.0);
			float heat = smoothstep(0.95, 0.25, UV.y);
			c.rgb = mix(c.rgb, st_burn_color * (0.75 + 0.6 * fl), solid * heat * (0.18 + 0.32 * fl));
		}
		if (st_poison > 0.0) {
			float pulse = 0.5 + 0.5 * sin(TIME * 3.2 + UV.x * 9.0);
			float low = smoothstep(0.35, 1.0, UV.y);
			float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
			c.rgb = mix(c.rgb, st_poison_color * (l * 1.3 + 0.12), solid * (0.25 + 0.3 * low) * (0.7 + 0.3 * pulse));
		}
		if (st_slow > 0.0) {
			float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
			c.rgb = mix(c.rgb, st_slow_color * (l * 1.2 + 0.18), solid * 0.42);
		}
		if (st_emp > 0.0) {
			c.rgb = mix(c.rgb, c.rgb * st_emp_color * 1.25, solid * 0.18);
		}
	}
	c.rgb = mix(c.rgb, vec3(1.0), flash);
	// Выборки — в ветке по параметру материала (одинаков для всех пикселей): в ветке по прозрачности пикселя
	// производные для мип-уровней не определены — на части видеокарт рябь по краю силуэта
	float near = 0.0;
	if (outline_px > 0.0) {
		// в пикселизации — ровно пиксель сетки, по сторонам и диагоналям (сплошной контур без зазубрин)
		vec2 d = pix > 0.0 ? cell : TEXTURE_PIXEL_SIZE * outline_px;
		vec2 e = pix > 0.0 ? cell : d * 0.7071;
		near = max(max(max(ALPHA_AT(uv + vec2(d.x, 0.0)), ALPHA_AT(uv - vec2(d.x, 0.0))),
			max(ALPHA_AT(uv + vec2(0.0, d.y)), ALPHA_AT(uv - vec2(0.0, d.y)))),
			max(max(ALPHA_AT(uv + e), ALPHA_AT(uv - e)),
			max(ALPHA_AT(uv + vec2(e.x, -e.y)), ALPHA_AT(uv + vec2(-e.x, e.y)))));
		if (pix > 0.0) {
			near = step(0.45, near);
		}
	}
	if (outline_px > 0.0 && c.a < 0.99) {
		vec4 oc = outline_color;
		if (st_emp > 0.0) {   // усиление — контур светится и дышит
			oc = vec4(st_emp_color * (0.75 + 0.35 * sin(TIME * 6.0)), 1.0);
		}
		float oa = oc.a * smoothstep(0.15, 0.6, near) * tint.a;
		// контур под фигурой: полупрозрачный край спрайта ложится на него
		float a = c.a + oa * (1.0 - c.a);
		c.rgb = a > 0.0 ? (c.rgb * c.a + oc.rgb * oa * (1.0 - c.a)) / a : c.rgb;
		c.a = a;
	}
	COLOR = c;
}"""
static var _unit_materials: Dictionary = {}   # ключ "орден|подсветка|контур|вспышка" → ShaderMaterial
static var _unit_shader: Shader = null        # один на все: в Compatibility шейдер компилируется при первом показе
var _rim_px: int = 0   # толщина подсветки края в пикселях текстуры (0 — без подсветки)
var _pix: int = 0      # пиксель арта бойца в пикселях текстуры (UNIT_SHADER pix)
var _status_mask: int = 0   # статусы на теле (STATUS_BODY) — часть ключа материала
var _light_left: float = 0.0
var _static_light: Color = Color(0, 0, 0, 0)   # отсвет костров (light_at)
var _flash_light: Color = Color(0, 0, 0, 0)    # вспышка рядом (add_flash_light)
var _flash_light_left: float = 0.0
var _flash_light_time: float = 1.0
var _outline_px: int = 0   # толщина контура в пикселях текстуры
var _rim: Dictionary = {}
var _base_material: Material = null
var _armor_chapter: String = ""   # орден, в цвет которого перекрашен боец ("" — нет)
var heal_beam: HealBeam = null   # луч лечения (лекарь), создаётся при первом пациенте
var _last_foot: int = -1   # шаг бега (пыль DustLayer)
var _steps: int = 0
var _recoil_left: float = 0.0   # сек до конца отдачи (_process, время дерева)
var _sprite_k: float = 1.0       # масштаб спрайта без шага и отдачи (_load_animations)
var _flash_left: float = 0.0   # сек до конца вспышки попадания (_process: время дерева, на паузе стоит)
var _walk_cycle_time: float = 0.0   # длина цикла бега листа, сек (0 — бега нет); темп бега — walk_anim_scale

static func _get_frames(sprite_path: String) -> SpriteFrames:
	if _frames_cache.has(sprite_path):
		return _frames_cache[sprite_path]
	if ResourceLoader.exists(sprite_path + "/frames.tres"):
		_frames_cache[sprite_path] = load(sprite_path + "/frames.tres")
		return _frames_cache[sprite_path]
	var frames = SpriteFrames.new()
	frames.remove_animation("default")
	for anim_name in ANIMATION_FOLDERS:
		var folder = sprite_path + "/" + ANIMATION_FOLDERS[anim_name] + "/"
		frames.add_animation(anim_name)
		frames.set_animation_loop(anim_name, anim_name != "attack" and anim_name != "death")
		frames.set_animation_speed(anim_name, ANIMATION_FPS)
		var i = 0
		while ResourceLoader.exists(folder + str(i) + ".png"):
			frames.add_frame(anim_name, load(folder + str(i) + ".png"))
			i += 1
	_frames_cache[sprite_path] = frames
	return frames

# Отдача от удара (только вид): сжатие и отскок назад от лица, плавный возврат; конец — масштаб и место как были
func _tick_recoil(delta: float) -> void:
	_recoil_left = maxf(_recoil_left - delta, 0.0)
	var r := _recoil_left / RECOIL_TIME
	r = r * r
	sprite.scale.x = _sprite_k * (1.0 + RECOIL_SQUASH * 0.5 * r)
	if sprite.animation != &"walk":
		sprite.scale.y = _sprite_k * (1.0 - RECOIL_SQUASH * r)
	sprite.position.x = (1.0 if sprite.flip_h else -1.0) * RECOIL_PX / maxf(scale.x, 0.01) * r

# Стоп-кадр мира на крупном ударе — у сцены боя (BattleScene.hitstop); без неё (тесты) — ничего
static func request_hitstop(node: Node) -> void:
	if not node.is_inside_tree():
		return
	var sc := node.get_tree().current_scene
	if sc and sc.has_method("hitstop"):
		sc.hitstop()

# Отсвет поля на теле (только вид): self_modulate = (1 + свет) × оттенок порабощённого
func _update_light() -> void:
	_static_light = IsoGridRenderer.light_at(global_position)
	_apply_light()

func _apply_light() -> void:
	var base: Color = CHARM_TINT if charmed else Color.WHITE
	var l := _static_light
	if _flash_light_left > 0.0:
		l += _flash_light * (_flash_light_left / _flash_light_time)
	sprite.self_modulate = Color(base.r * (1.0 + l.r), base.g * (1.0 + l.g), base.b * (1.0 + l.b), base.a)

# Вспышка света рядом (IsoGridRenderer.flash_light): сильнейшая из одновременных, гаснет за time
func add_flash_light(col: Color, time: float) -> void:
	if current_state == State.DEAD:   # павший не загорается (босс от своей же вспышки смерти белел целиком)
		return
	var now := _flash_light * (_flash_light_left / _flash_light_time) if _flash_light_left > 0.0 else Color(0, 0, 0, 0)
	if col.r + col.g + col.b < now.r + now.g + now.b:
		return
	_flash_light = col
	_flash_light_left = time
	_flash_light_time = time
	_apply_light()

func _ready() -> void:
	# отсвет — вразнобой по кадрам (не все бойцы в один кадр); без randf — он общий со случайностью боя
	_light_left = (get_instance_id() % 97) / 97.0 * LIGHT_EVERY
	sprite.animation_finished.connect(_on_animation_finished)
	sprite.animation_changed.connect(_on_animation_changed)

func _process(delta: float) -> void:
	_light_left -= delta
	if _light_left <= 0.0:
		_light_left = LIGHT_EVERY
		_update_light()
	elif _flash_light_left > 0.0:
		_flash_light_left -= delta
		_apply_light()
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			sprite.material = _base_material
	if sprite.animation == &"walk" and _leap_prev >= 1.0:
		# Шаг: плавная волна — ниже всего на ступне, выпрямился к середине шага (резкая посадка дёргала);
		# и в бою, и на построении (BattleScene._deploy_army — бой ещё не идёт)
		var phase := (sprite.frame + sprite.frame_progress) / sprite.sprite_frames.get_frame_count(&"walk")
		sprite.scale.y = _sprite_k * (1.0 - STEP_DIP * 0.5 * (1.0 + cos(TAU * STEPS_PER_CYCLE * phase)))
		var foot := int(phase * STEPS_PER_CYCLE)
		if foot != _last_foot:   # нога встала — пыль (тяжёлые — каждый шаг, пехота — реже)
			_last_foot = foot
			_steps += 1
			var heavy := "vehicle" in data.tags or data.sprite_scale >= HEAVY_DUST_SCALE
			if heavy or _steps % DustLayer.INFANTRY_EVERY == 0:
				DustLayer.puff(global_position, (6.0 if heavy else 3.5) * data.sprite_scale)
			if data.special_kind != "":   # шаг примарха: земля дрожит и трескается
				_boss_step()
	if _recoil_left > 0.0:
		_tick_recoil(delta)
	if not _has_tick_from or current_state == State.DEAD or not BattleManager.is_battle_running():
		return
	if not _drawn_between:
		_tick_to = global_position
		_drawn_between = true
	var alpha := BattleManager.get_tick_alpha()
	global_position = _tick_from.lerp(_tick_to, alpha)
	if _leap_prev < 1.0:   # дуга прыжка: спрайт над тенью
		sprite.position.y = -sin(PI * lerpf(_leap_prev, _leap_t, alpha)) * JUMP_HEIGHT * data.sprite_scale
		if _jump_trail:
			_jump_trail.position.y = sprite.position.y - JUMP_TRAIL_RISE * data.sprite_scale

func _boss_step() -> void:
	var now := Time.get_ticks_msec()
	if now - _step_shake_at < BOSS_STEP_GAP_MS:
		return
	_step_shake_at = now
	_shake_camera(BOSS_STEP_SHAKE)
	BossFx.cracks(global_position, TARGET_SPRITE_HEIGHT * data.sprite_scale * 0.35, BOSS_STEP_CRACK_LIFE, data.special_color)

# Начало тика боя: узел — обратно в логическую позицию, от неё отсчитывается следующий шаг
func restore_tick_position() -> void:
	if _drawn_between:
		global_position = _tick_to
		_drawn_between = false
	_tick_from = global_position
	_has_tick_from = true

# Темп своей скорости — только у бега; остальные анимации — как в листе
# Новая анимация — с обычной скоростью: ускорение атаки (_attack_anim_scale) не переходит на бег и стойку;
# темп бега ставит _move_towards / _strafe_around сразу после смены (walk_anim_scale)
func _on_animation_changed() -> void:
	sprite.speed_scale = 1.0
	sprite.scale.y = _sprite_k   # шаг (STEP_DIP) — только у бега

# Множитель скорости анимации бега при скорости speed (px/с): цикл листа — за WALK_CYCLE_HEIGHTS ростов
# (зовётся каждый тик у каждого идущего — длина цикла посчитана в _load_animations)
func walk_anim_scale(speed: float) -> float:
	if _walk_cycle_time <= 0.0:
		return 1.0
	var stride: float = WALK_CYCLE_HEIGHTS * TARGET_SPRITE_HEIGHT * data.sprite_scale
	return clampf(speed * _walk_cycle_time / stride, WALK_SCALE_LIMITS.x, WALK_SCALE_LIMITS.y)

# Выстрел / удар отыгран — стойка до следующего (последний кадр атаки — со вспышкой ствола)
func _on_animation_finished() -> void:
	if sprite.animation in ["attack", "battle_cry", "landing", "appear"] and current_state != State.DEAD:
		sprite.play("idle")

# Бой окончен (BattleManager): выжившие опускают оружие — стойка, а не стрельба.
# won — сторона бойца победила: поза победы (анимация victory листа, решение пользователя —
# Дредноут поднимает кулак), держится на последнем кадре
func stand_down(won: bool = false) -> void:
	_end_leap_view()
	_special_left = 0.0
	_clear_telegraph()
	if heal_beam:
		heal_beam.set_patient(null)
	transition_to(State.IDLE)
	if current_state != State.IDLE:
		return
	if won and sprite.sprite_frames.has_animation("victory"):
		sprite.play("victory")
	else:
		_play_animation("idle")

func _load_animations() -> void:
	var frames = _get_frames(data.sprite_path)
	sprite.sprite_frames = frames
	_walk_cycle_time = 0.0
	if frames.has_animation("walk") and frames.get_frame_count("walk") > 0:
		_walk_cycle_time = frames.get_frame_count("walk") / frames.get_animation_speed("walk")
	# Масштаб по высоте первого кадра idle — все юниты одного роста,
	# sprite_scale делает Терминатора крупнее, а скаута мельче
	var base_h = TARGET_SPRITE_HEIGHT
	if frames.get_frame_count("idle") > 0:
		base_h = frames.get_frame_texture("idle", 0).get_height()
	# Рост фигуры (боссы, tools/boss_frames.py): холст выше стойки — крылья появления, замах; меряем по фигуре
	var k = TARGET_SPRITE_HEIGHT / float(frames.get_meta("figure_height", base_h)) * data.sprite_scale
	sprite.scale = Vector2(k, k)
	_sprite_k = k
	# Ноги — в точке бойца (стоит на тайле, а не висит центром над ним)
	sprite.offset = Vector2(0, -base_h / 2.0)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.modulate = data.tint
	queue_redraw()
	sprite.play("idle")

# Построение перед боем (BattleScene._deploy_army, только вид: бой ещё не идёт, отряд двигает твин узла отряда):
# идёт со скоростью speed px/с в сторону direction; встал — стойка лицом к врагу
func deploy_walk(speed: float, direction: Vector2) -> void:
	_play_animation("walk")
	sprite.speed_scale = walk_anim_scale(speed)
	_face(direction)

func deploy_stand() -> void:
	_play_animation("idle")
	sprite.flip_h = team == GameConstants.TEAM_ENEMY

# Бег и стойка — с кадра по номеру бойца в отряде (attack_stagger): отряд шагал в ногу, все бойцы на одном
# кадре, и строй из 9–15 одинаковых фигурок читался как замерший спрайт (23.10.2026). Только вид
func _play_animation(anim_name: String) -> void:
	if sprite.animation != anim_name:
		sprite.play(anim_name)
		if anim_name == "walk" or anim_name == "idle":
			sprite.frame = int(attack_stagger * sprite.sprite_frames.get_frame_count(anim_name))

# -------------------------------------------------------
# ГЛАВНЫЙ ТИК
# -------------------------------------------------------
func tick(delta: float) -> void:
	# Проверки — до вызова: тик идёт у сотен бойцов, вызов функции в GDScript не бесплатен
	if not status_effects.is_empty():
		_tick_status_effects(delta)
	if current_state == State.DEAD:
		return
	_leap_prev = _leap_t
	if _leap_prev >= 1.0 and sprite.position.y != 0.0:
		sprite.position.y = 0.0   # дуга прыжка дорисована
	if _leap_time > 0.0:
		_tick_leap(delta)
		return
	if _special_left > 0.0:
		_tick_special(delta)
		return
	if data.special_kind != "":
		_special_cd -= delta
		if _special_cd <= TIMER_EPSILON and (current_state == State.ATTACK or current_state == State.CHASE) 				and _try_special():
			return
	if current_heal_per_second > 0.0:
		_tick_support(delta)
	if _hit_timer > 0.0:
		_tick_melee_hit(delta)
	if data.jump_range > 0.0 and not jump_used and (current_state == State.MOVE or current_state == State.CHASE):
		if _try_jump():
			return
	_moved = false
	match current_state:
		State.IDLE:       _state_idle()
		State.MOVE:       _state_move(delta)
		State.CHASE:      _state_chase(delta)
		State.ATTACK:     _state_attack(delta)
		State.CASTING:    _state_casting(delta)
		State.STUNNED:    _state_stunned(delta)
		State.KNOCKBACK:  _state_knockback(delta)
		State.RETREATING: _state_retreating(delta)
		State.DEAD:       pass
	if data.entrench_time > 0.0:
		_tick_entrench(delta)

# -------------------------------------------------------
# СПОСОБНОСТИ ОТРЯДОВ (данными в UnitData; решение пользователя 17.10.2026)
# -------------------------------------------------------
# Прыжок (Assault): враг-стрелок ближе jump_range, но не вплотную — прыжок к нему (раз за бой)
func _try_jump() -> bool:
	var prey := SoldierRegistry.find_nearest(1 - team, global_position, data.jump_range, true)
	if prey == null or global_position.distance_to(prey.global_position) <= current_attack_range * 2.0:
		return false
	jump_used = true
	_leap_target = prey
	_leap_from = global_position
	# Приземление — перед целью со стороны прыжка, бойцы отряда — своим строем, не в одну точку
	var back := (global_position - prey.global_position).normalized()
	_leap_to = prey.global_position + back * current_attack_range * 0.5 + formation_offset * 0.5
	_leap_duration = maxf(_leap_from.distance_to(_leap_to) / JUMP_SPEED, JUMP_MIN_TIME) * (1.0 + attack_stagger * JUMP_STAGGER)
	_leap_time = _leap_duration
	_leap_t = 0.0
	_leap_prev = 0.0
	_face(prey.global_position - global_position)
	_play_animation("jump" if sprite.sprite_frames.has_animation("jump") else "idle")   # полёт на ранце (Assault)
	# Шлейф ранца — хвостом назад по полёту, на высоте спины (дугу спрайта повторяет _process)
	_jump_trail = Vfx.attach(self, "jump_trail", data.sprite_scale * EFFECT_SCALE)
	if _jump_trail:
		_jump_trail.rotation = (_leap_to - _leap_from).angle()
		_jump_trail.position.y = -JUMP_TRAIL_RISE * data.sprite_scale
	return true

func _clear_jump_trail() -> void:
	Vfx.dismiss(_jump_trail)
	_jump_trail = null

func _tick_leap(delta: float) -> void:
	_leap_time -= delta
	if _leap_time <= TIMER_EPSILON:
		_leap_time = 0.0
	_leap_t = 1.0 - _leap_time / _leap_duration
	global_position = _leap_from.lerp(_leap_to, _leap_t)
	if _leap_time <= 0.0:
		_land_jump()

func is_leaping() -> bool:
	return _leap_time > 0.0

# Приземление: удар по всем врагам в jump_radius (урон удара × jump_damage_mult) и оглушение; дальше —
# бой с тем, на кого прыгал
func _land_jump() -> void:
	var dmg := _roll_damage() * data.jump_damage_mult
	var r2 := data.jump_radius * data.jump_radius
	for e in SoldierRegistry.get_alive_soldiers_of_team(1 - team).duplicate():
		if global_position.distance_squared_to(e.global_position) > r2:
			continue
		BattleManager.credit_damage(parent_squad, clampf(dmg - e.shield, 0.0, e.current_hp))
		e.take_damage(dmg)
		if data.jump_stun > 0.0:
			e.apply_stun(data.jump_stun)
	_clear_jump_trail()
	Vfx.spawn(_world_parent(), "jump_land", global_position, data.sprite_scale * EFFECT_SCALE)
	AudioManager.play("jump_land")
	DustLayer.puff(global_position, 8.0 * data.sprite_scale, 3, 6.0)
	request_hitstop(self)
	target = _leap_target if is_instance_valid(_leap_target) and _leap_target.current_state != State.DEAD \
		else _find_target()
	_leap_target = null
	if target and global_position.distance_to(target.global_position) <= current_attack_range:
		transition_to(State.ATTACK)
	elif target:
		transition_to(State.CHASE)
	# Приземление листа (Assault: пыль из-под ног) — до первого удара, потом стойка
	if current_state == State.ATTACK and sprite.sprite_frames.has_animation("landing"):
		sprite.play("landing")
	elif current_state != State.ATTACK:   # переход в то же состояние анимацию не меняет — снимаем jump
		_play_animation("walk" if current_state in [State.MOVE, State.CHASE] else "idle")

# Прыжок прерван итогом боя или гибелью — спрайт обратно на землю
func _end_leap_view() -> void:
	_leap_time = 0.0
	_leap_t = 1.0
	_leap_prev = 1.0
	_leap_target = null
	sprite.position.y = 0.0
	_clear_jump_trail()

# -------------------------------------------------------
# ПРИЁМ ФИНАЛЬНОГО БОССА (UnitData.special_*; решение пользователя 09.11.2026 — свой приём у каждого примарха)
# Ряд special листа: замах до metadata/special_frame, на нём — действие, затем доигрывается; всё это время FSM стоит,
# оглушение и отброс не действуют. Рывок и прыжок — ход за время замаха (≤ GRID_SLACK за тик при special_range ≤ 300)
# -------------------------------------------------------
const SPECIAL_CONE_HALF: float = deg_to_rad(55.0)   # конус: половина угла
# Языки пламени огненного конуса: (доля полуугла от оси, доля радиуса)
const CONE_FLAMES = [Vector2(-0.6, 0.35), Vector2(0.0, 0.35), Vector2(0.6, 0.35), Vector2(-0.35, 0.7), Vector2(0.35, 0.7)]
const SPECIAL_FALLBACK_TIME: float = 1.0           # ряда special нет — приём длится столько, срабатывает в середине
const SPECIAL_SHAKE: float = 6.0
const BOSS_CRACK_LIFE: float = 2.5     # трещины от приёма гаснут за столько
const BOSS_STEP_CRACK_LIFE: float = 1.2
const BOSS_STEP_SHAKE: float = 1.5     # шаг босса — лёгкая тряска камеры
const BOSS_STEP_GAP_MS: int = 250      # … не чаще
const BOSS_NUMBER_SIZE: float = 1.5    # цифры урона от удара босса крупнее
const ENRAGE_AT: float = 0.5           # ярость с этой доли HP
const ENRAGE_COOLDOWN_MULT: float = 0.67   # перезарядка приёма в ярости (в 1.5 раза чаще)
const ENRAGE_FIRST: float = 1.0        # после рёва приём не позже чем через столько
const SCAR_RADIUS: float = 4.5          # px мира — пятно крови павшего (× sprite_scale; ScarLayer)
const BOSS_CORPSE_HOLD: float = 1.5    # тело примарха лежит на последнем кадре смерти
const BOSS_CORPSE_FADE: float = 2.0    # … потом темнеет и тает
const BOSS_CORPSE_TINT := Color(0.35, 0.36, 0.42, 0.0)   # к тону грунта, прозрачно

func _try_special() -> bool:
	var reach := data.special_range if data.special_range > 0.0 else data.special_radius
	var t: Soldier = target if _has_valid_target() else _find_target()
	if data.special_kind == "leap":   # прыжок — на стрелков, если они в досягаемости (как Assault)
		var prey := SoldierRegistry.find_nearest(1 - team, global_position, reach, true)
		if prey:
			t = prey
	if t == null or global_position.distance_to(t.global_position) > reach:
		return false
	_special_target = t
	_special_from = global_position
	_special_to = global_position
	var dir := (t.global_position - global_position).normalized()
	_special_aim = dir if dir != Vector2.ZERO else (Vector2.LEFT if sprite.flip_h else Vector2.RIGHT)
	match data.special_kind:
		"leap":   # приземлиться перед целью
			_special_to = t.global_position - dir * current_attack_range * 0.5
		"dash":   # насквозь: за цель на свою дальность
			_special_to = t.global_position + dir * current_attack_range
	_face(t.global_position - global_position)
	var frames := sprite.sprite_frames
	var length := SPECIAL_FALLBACK_TIME
	_special_wind = SPECIAL_FALLBACK_TIME * 0.5
	if frames.has_animation("special") and frames.get_frame_count("special") > 0:
		var fps: float = frames.get_animation_speed("special")
		length = frames.get_frame_count("special") / fps
		_special_wind = minf(frames.get_meta("special_frame", frames.get_frame_count("special") / 2) / fps, length)
	_special_left = length
	_special_release = maxf(_special_wind, GameConstants.FIXED_TICK)
	_special_cd = data.special_cooldown * (ENRAGE_COOLDOWN_MULT if enraged else 1.0)
	_clear_telegraph()
	_telegraph = BossFx.telegraph(self, data.special_kind, _special_from,
		_special_to if _special_to != _special_from else _special_from + _special_aim * data.special_radius,
		data.special_radius, _special_release, t)
	_hit_timer = 0.0   # замах обычного удара снят
	_hit_target = null
	sprite.stop()
	sprite.play("special" if frames.has_animation("special") else "attack")
	return true

func _tick_special(delta: float) -> void:
	_special_left -= delta
	if _special_release > 0.0:
		_special_release -= delta
		if _special_to != _special_from:
			var t := clampf(1.0 - _special_release / maxf(_special_wind, GameConstants.FIXED_TICK), 0.0, 1.0)
			global_position = _special_from.lerp(_special_to, t)
			_moved = true
		if _special_release <= TIMER_EPSILON:
			_special_release = 0.0
			global_position = _special_to
			_clear_telegraph()
			_release_special()
	if _special_left <= TIMER_EPSILON:
		_special_left = 0.0
		_special_target = null
		# FSM стояла в ATTACK / CHASE: цель могла пасть или отойти — дальше обычным ходом состояний
		if not _has_valid_target():
			target = _find_target()
		if target and global_position.distance_to(target.global_position) <= current_attack_range:
			if current_state != State.ATTACK:
				transition_to(State.ATTACK)
			else:
				sprite.play("idle")
		elif target:
			if current_state != State.CHASE:
				transition_to(State.CHASE)
			else:
				_play_animation("walk")
		else:
			transition_to(State.MOVE)
			_play_animation("walk")

func is_using_special() -> bool:
	return _special_left > 0.0

# Кадр срабатывания: урон по виду приёма, статус, оглушение; вид — свет, тряска, стоп-кадр
func _release_special() -> void:
	var dmg := _roll_damage() * data.special_mult
	var victims: Array = []
	var foes: Array = SoldierRegistry.get_alive_soldiers_of_team(1 - team)
	var r2 := data.special_radius * data.special_radius
	var aim := _special_aim
	match data.special_kind:
		"leap", "nova", "shield":
			for e in foes:
				if global_position.distance_squared_to(e.global_position) <= r2:
					victims.append(e)
		"cone":
			for e in foes:
				var to: Vector2 = e.global_position - global_position
				if to.length_squared() <= r2 and (to.length_squared() < 1.0 or absf(aim.angle_to(to)) <= SPECIAL_CONE_HALF):
					victims.append(e)
		"dash":
			for e in foes:
				if Geometry2D.get_closest_point_to_segment(e.global_position, _special_from, _special_to) \
						.distance_squared_to(e.global_position) <= r2:
					victims.append(e)
		"bolt":
			_special_bolt(dmg)
	for e in victims.duplicate():
		_special_hit(e, dmg)
	if data.special_shield > 0.0:
		shield += max_hp * data.special_shield
		Vfx.attach(self, "shield", data.sprite_scale * EFFECT_SCALE)
	_special_view()

func _special_hit(e: Soldier, dmg: float) -> void:
	if not is_instance_valid(e) or e.current_state == State.DEAD:
		return
	var amount: float = dmg * e.data.unit_weight
	BattleManager.credit_damage(parent_squad, clampf(amount - e.shield, 0.0, e.current_hp))
	e.take_damage(amount, true, true)
	if data.special_stun > 0.0:
		e.apply_stun(data.special_stun)
	if data.special_status != "":
		e.apply_status(data.special_status, data.special_status_power, data.special_status_duration)

# Магнус: сгусток варпа в цель, взрыв по площади со статусом
func _special_bolt(dmg: float) -> void:
	if not is_instance_valid(_special_target) or parent_squad == null:
		return
	var shot := Projectile.launch(parent_squad.get_parent(), data.special_projectile, _muzzle_point(), _special_target,
		Vector2(0.0, -TARGET_SPRITE_HEIGHT * 0.45 * _special_target.data.sprite_scale))
	shot.source = parent_squad
	shot.damage = dmg
	shot.splash_radius = data.special_radius
	shot.splash_team = 1 - team
	shot.heavy = true
	shot.light_color = data.special_color
	var status := data.special_status
	var power := data.special_status_power
	var duration := data.special_status_duration
	var radius := data.special_radius
	var foe_team := 1 - team
	var col := data.special_color
	shot.on_impact = func(point: Vector2) -> void:
		BossFx.shockwave(point, radius, col)
		BossFx.cracks(point, radius * 0.8, BOSS_CRACK_LIFE, col)
		if status == "":
			return
		for e in SoldierRegistry.get_alive_soldiers_of_team(foe_team).duplicate():
			if e.global_position.distance_to(point) <= radius:
				e.apply_status(status, power, duration)

# Вид приёма (кроме снаряда — у него свой взрыв): удар о землю, свет цвета приёма, тряска камеры, стоп-кадр
func _special_view() -> void:
	if data.special_kind == "bolt":
		AudioManager.play("boss_special")
		IsoGridRenderer.flash_light(_muzzle_point(), Color(data.special_color, 0.9), 70.0, 0.25)
		return
	var parent := _world_parent()
	var k := data.special_radius / 60.0
	match data.special_kind:
		"leap":
			Vfx.spawn(parent, "jump_land", global_position, k)
			DustLayer.puff(global_position, 10.0 * data.sprite_scale, 4, 8.0)
		"dash":
			Vfx.spawn(parent, "retreat_dust", _special_from, data.sprite_scale * EFFECT_SCALE)
			Vfx.spawn(parent, "ground_slam", global_position, k)
			# Борозда и пыль по всему пути рывка (EFFECTS_NEEDED 4.12, кодом 09.11.2026; было — пыль только на старте)
			BossFx.furrow(_special_from, _special_to, data.special_color)
			var path := _special_to - _special_from
			for i in 4:
				DustLayer.puff(_special_from + path * (i + 0.5) / 4.0, 7.0 * data.sprite_scale, 2, 6.0)
		"cone":
			if data.special_status == StatusEffects.POISONED:
				# Чумное облако по зоне конуса (4.12, кодом 09.11.2026): клубы висят и тают — видно, куда пришёлся удар
				BossFx.cloud(global_position, _special_aim, SPECIAL_CONE_HALF, data.special_radius, data.special_color)
			else:
				# Огонь — языки по всему конусу: три у тела и два дальше (было три у тела — дальняя часть зоны пустая)
				for i in CONE_FLAMES.size():
					var f: Vector2 = CONE_FLAMES[i]
					var a: float = _special_aim.angle() + f.x * SPECIAL_CONE_HALF
					Vfx.spawn(parent, "flame_burst", global_position + Vector2.from_angle(a) * data.special_radius * f.y,
						k * (0.8 if f.y < 0.5 else 0.65), a)
		_:
			Vfx.spawn(parent, "ground_slam", global_position, k)
			Vfx.spawn(parent, "explosion", global_position, k * 0.8)
	BossFx.shockwave(global_position, data.special_radius, data.special_color)
	BossFx.cracks(global_position, data.special_radius * 0.8, BOSS_CRACK_LIFE, data.special_color)
	ScarLayer.scorch(global_position, data.special_radius * 0.35)   # шрам поля от удара приёма
	AudioManager.play("boss_special")
	IsoGridRenderer.flash_light(global_position, Color(data.special_color, 0.95), data.special_radius * 1.6, 0.4)
	_shake_camera(SPECIAL_SHAKE)
	request_hitstop(self)

func _clear_telegraph() -> void:
	if is_instance_valid(_telegraph):
		_telegraph.release()
	_telegraph = null

# Босс показан (враги открываются по «В БОЙ»): тень и кольцо под ним (раньше выдали бы его на расстановке)
func reveal_boss() -> void:
	if data.special_kind != "" and not is_instance_valid(_ground):
		_ground = BossFx.ground(self)

# Ярость (решение пользователя 09.11.2026): босс впервые ≤ ENRAGE_AT HP — рёв: приём скоро, дальше в
# 1 / ENRAGE_COOLDOWN_MULT раза чаще; вид — вспышка, ударная волна, тряска, кольцо пульсирует, тело тлеет
func _enrage() -> void:
	enraged = true
	_special_cd = minf(_special_cd, ENRAGE_FIRST)
	if is_instance_valid(_ground):
		_ground.enraged = true
	_sync_status_vfx()
	_flash_hit()
	BossFx.shockwave(global_position, data.special_radius * 1.2, data.special_color)
	IsoGridRenderer.flash_light(global_position, Color(data.special_color, 0.9), data.special_radius * 2.0, 0.5)
	AudioManager.play("boss_appear")
	_shake_camera(SPECIAL_SHAKE)
	var scene := get_tree().current_scene if is_inside_tree() else null
	if scene and scene.has_method("boss_enraged"):
		scene.boss_enraged(self)

func _shake_camera(strength: float) -> void:
	var camera := get_viewport().get_camera_2d() if is_inside_tree() else null
	if camera and camera.has_method("shake"):
		camera.shake(strength)

# Появление босса на поле (ряд appear, по «В БОЙ» на построении — бой ещё не идёт, только вид); false — ряда нет
func play_appear() -> bool:
	if not sprite.sprite_frames.has_animation("appear"):
		return false
	sprite.stop()
	sprite.play("appear")
	AudioManager.play("boss_appear")
	return true

# Окапывание (Devastator): стоял весь тик — копит, сдвинулся (бег, кружение, отброс) — с нуля
func _tick_entrench(delta: float) -> void:
	var was := is_entrenched()
	if _moved or current_state == State.KNOCKBACK:
		_still_time = 0.0
	else:
		_still_time = minf(_still_time + delta, data.entrench_time)
	if is_entrenched() != was:
		_show_entrench(is_entrenched())

# Бруствер (лист entrench, пакет художника; было — дуга кодом в _draw): вырастает у ног и стоит, сдвинулся — тает
func _show_entrench(on: bool) -> void:
	Vfx.dismiss(_entrench_vfx)
	_entrench_vfx = Vfx.attach(self, "entrench", data.sprite_scale * EFFECT_SCALE) if on else null

func is_entrenched() -> bool:
	return data.entrench_time > 0.0 and _still_time >= data.entrench_time - TIMER_EPSILON

# Прибавка урона окапывания: растёт от 0 до entrench_bonus за entrench_time
func get_entrench_bonus() -> float:
	if data.entrench_time <= 0.0:
		return 0.0
	return data.entrench_bonus * clampf(_still_time / data.entrench_time, 0.0, 1.0)

# Стрельба на ходу (Land Speeder): кружит вокруг цели, держась на MOBILE_FIRE_DISTANCE дальности
func _strafe_around(center: Vector2, delta: float) -> void:
	var to_me := global_position - center
	var dist := to_me.length()
	if dist < 0.01:
		return
	var radial := to_me / dist
	var tangent := Vector2(-radial.y, radial.x) * _orbit_sign
	var want := current_attack_range * MOBILE_FIRE_DISTANCE
	var dir := (tangent + radial * clampf((want - dist) / want * 3.0, -1.0, 1.0)).normalized()
	var speed := current_move_speed * get_move_speed_mult() * MOBILE_FIRE_SPEED
	global_position += dir * speed * delta
	_moved = true
	if sprite.animation != "attack":   # выстрел доигрывается, между выстрелами — ход
		_play_animation("walk")
		sprite.speed_scale = walk_anim_scale(speed)
	_face(center - global_position)

# Телепорт (Deep Strike, Squad): сразу в точку — без плавного перелёта через поле
func teleport_to(point: Vector2) -> void:
	global_position = point
	_tick_from = point
	_tick_to = point
	_drawn_between = false

# -------------------------------------------------------
# СОСТОЯНИЯ
# -------------------------------------------------------
func _state_idle() -> void:
	# В IDLE просто ждём команды от Squad
	pass

# Идём в сторону вражеской армии, пока кто-то не попадёт в поле зрения
func _state_move(delta: float) -> void:
	var enemies = SoldierRegistry.get_alive_soldiers_of_team(1 - team)
	if enemies.is_empty():
		if _is_sieging():
			_march_on_citadel(delta)
		else:
			_play_animation("idle")
		return

	# Враг в поле зрения — поиск по сетке реестра; отряд уже проверил, что врагов рядом нет, — не ищем
	if not (parent_squad and parent_squad.enemy_out_of_sight) 			and SoldierRegistry.find_nearest(1 - team, global_position, data.vision_range):
		target = _find_target()
		transition_to(State.CHASE)
		return

	var center = SoldierRegistry.get_team_center(1 - team)
	# Марш строем (как в 9 Kings): цель каждого бойца — центр врага + его
	# смещение в строю, поэтому весь отряд идёт параллельно, не сбиваясь в кучу.
	# Строй рассыпается только в CHASE, когда враг в поле зрения.
	_move_towards(center + formation_offset, delta)

# -------------------------------------------------------
# ШТУРМ ЦИТАДЕЛИ — армия игрока пала, враги бьются с цитаделью
# -------------------------------------------------------
func _is_sieging() -> bool:
	return team == GameConstants.TEAM_ENEMY and BattleManager.has_citadel() \
		and BattleManager.citadel_hp > 0.0 \
		and SoldierRegistry.get_alive_soldiers_of_team(1 - team).is_empty()

func _citadel_in_range() -> bool:
	return global_position.distance_to(BattleManager.citadel.global_position) \
		<= current_attack_range + Citadel.HIT_RADIUS

func _march_on_citadel(delta: float) -> void:
	if _citadel_in_range():
		transition_to(State.ATTACK)
	else:
		_move_towards(BattleManager.citadel.global_position, delta)

# ATTACK по цитадели: тот же таймер и урон, что по бойцам
func _attack_citadel(delta: float) -> void:
	var citadel = BattleManager.citadel
	if not _citadel_in_range():
		transition_to(State.MOVE)
		return
	_face(citadel.global_position - global_position)
	attack_timer -= delta
	if attack_timer <= TIMER_EPSILON:
		attack_timer = 1.0 / (current_attack_speed * get_attack_speed_mult())
		_play_attack_animation()
		var shot := _shoot_projectile(citadel, Vector2(0.0, -40.0))
		if shot:
			shot.damage = _roll_damage()   # урон — при попадании
		else:
			citadel.take_hit(_roll_damage())

# -------------------------------------------------------
# СТЕНА ВЛАДЕНИЙ — враг упёрся в целое звено (_move_towards) и ломает его тем же ударом / выстрелом
# -------------------------------------------------------
const WALL_AIM := Vector2(0.0, -10.0)   # выстрел — в середину высоты стены

# Зовёт _move_towards, когда шаг к точке внутри стены упёрся в звено: ломать или обходить — решает только он,
# по точке, куда боец идёт (цель вышла за стену — следующий шаг уже обход, а не удар)
func _attack_wall(delta: float) -> void:
	var seg = wall_segment
	if not is_instance_valid(seg) or seg.hp <= 0.0:
		wall_segment = null   # пролом — дальше обычным ходом
		return
	_face(seg.global_position - global_position)
	attack_timer -= delta
	if attack_timer <= TIMER_EPSILON:
		attack_timer = 1.0 / (current_attack_speed * get_attack_speed_mult())
		_play_attack_animation()
		var shot := _shoot_projectile(seg, WALL_AIM)
		if shot:
			shot.damage = _roll_damage()   # урон — при попадании
		else:
			seg.take_hit(_roll_damage())

# Преследуем конкретную цель до дальности атаки
func _state_chase(delta: float) -> void:
	if not _has_valid_target():
		target = _find_target()
		if not target:
			transition_to(State.MOVE)
			return

	if global_position.distance_to(target.global_position) <= current_attack_range:
		transition_to(State.ATTACK)
	else:
		_move_towards(target.global_position, delta)

func _state_attack(delta: float) -> void:
	if _is_sieging():
		_attack_citadel(delta)
		return
	if not _has_valid_target():
		target = _find_target()
		if not target:
			transition_to(State.MOVE)
			return

	if global_position.distance_to(target.global_position) > current_attack_range:
		transition_to(State.CHASE)
		return

	_face(target.global_position - global_position)
	attack_timer -= delta
	if attack_timer <= TIMER_EPSILON:
		attack_timer = 1.0 / (current_attack_speed * get_attack_speed_mult())
		if data.cast_time > 0.0:
			transition_to(State.CASTING)   # замах/каст перед ударом
		else:
			_do_attack()
	if data.mobile_fire and current_state == State.ATTACK and _has_valid_target():
		_strafe_around(target.global_position, delta)

# Каст: удар срабатывает через cast_time. Цель умерла — каст сорван.
func _state_casting(delta: float) -> void:
	if not _has_valid_target():
		transition_to(State.CHASE)
		return
	cast_timer -= delta
	if cast_timer <= TIMER_EPSILON:
		# Сначала в ATTACK, потом удар: вход в ATTACK ставит стойку и перебил бы анимацию атаки.
		# Каст — часть перезарядки (отсчитана перед кастом): цикл «каст + удар» = 1 / attack_speed;
		# вход в ATTACK её не сбрасывает
		var cooldown := attack_timer
		transition_to(State.ATTACK)
		attack_timer = maxf(cooldown - data.cast_time, 0.0)
		if global_position.distance_to(target.global_position) <= current_attack_range:
			_do_attack()

func _state_stunned(delta: float) -> void:
	stun_timer -= delta
	if stun_timer <= TIMER_EPSILON:
		stun_timer = 0.0
		_resume_after_control()

func _state_knockback(delta: float) -> void:
	global_position += knockback_velocity * delta
	knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, KNOCKBACK_FRICTION * delta)
	if knockback_velocity.length() <= KNOCKBACK_STOP_SPEED:
		knockback_velocity = Vector2.ZERO
		transition_to(State.CHASE)

# Отходим от ближайшего врага retreat_duration секунд, затем снова в бой.
# HP не регенерирует — без таймера боец бегал бы вечно и бой не кончился бы.
func _state_retreating(delta: float) -> void:
	retreat_timer -= delta
	var enemies = SoldierRegistry.get_alive_soldiers_of_team(1 - team)
	if retreat_timer <= TIMER_EPSILON or enemies.is_empty():
		transition_to(State.CHASE)
		return
	var threat = SoldierRegistry.find_nearest(1 - team, global_position)
	var away = global_position - threat.global_position
	_move_towards(global_position + away, delta)

# -------------------------------------------------------
# ПОДДЕРЖКА — лечение (Apothecary). Работает параллельно с FSM.
# -------------------------------------------------------
func _tick_support(delta: float) -> void:
	if current_state in [State.IDLE, State.STUNNED, State.DEAD]:
		if heal_beam:
			heal_beam.set_patient(null)   # луч гаснет
		return
	# Лечим самого раненого (по доле HP) союзника в радиусе, включая себя
	var patient: Soldier = null
	var lowest_ratio: float = 1.0
	var r2 = data.heal_radius * data.heal_radius
	for ally in SoldierRegistry.get_alive_soldiers_of_team(team):
		if global_position.distance_squared_to(ally.global_position) > r2:
			continue
		var ratio = ally.current_hp / ally.max_hp
		if ratio < lowest_ratio:
			lowest_ratio = ratio
			patient = ally
	if patient:
		patient.heal(current_heal_per_second * delta)
	_show_heal_animation(patient != null)
	# луч к раненому (себя лечит — без луча); только вид
	if patient and patient != self and heal_beam == null:
		heal_beam = HealBeam.for_healer(self)
	if heal_beam:
		heal_beam.set_patient(patient)

# Лечение листа (Apothecary: ряд heal, если есть) — пока лечит и стоит (стойка между ударами);
# бег и удар его перебивают, кончил лечить — снова стойка. Только вид
func _show_heal_animation(healing: bool) -> void:
	if not sprite.sprite_frames.has_animation("heal"):
		return
	if healing and sprite.animation in ["idle", "heal"]:
		_play_animation("heal")
	elif not healing and sprite.animation == "heal":
		_play_animation("idle")

# Пересчитать базовые статы после изменения множителей отряда (карта-улучшение
# во время расстановки). Доля HP сохраняется.
func refresh_stats_from_data() -> void:
	var ratio = current_hp / max_hp if max_hp > 0.0 else 1.0
	max_hp = data.get_max_hp()
	current_hp = max_hp * ratio
	current_damage = data.get_damage()
	current_attack_speed = data.get_attack_speed()
	current_move_speed = data.get_move_speed()
	current_attack_range = data.get_attack_range()
	shield = max_hp * data.shield_ratio
	bonus_poison_power = ChaosGods.poison_power(data.get_god(), data.blessings)
	charm_chance = ChaosGods.charm_chance(data.get_god(), data.blessings)

func heal(amount: float) -> void:
	if current_state == State.DEAD:
		return
	if status_effects.has(StatusEffects.POISONED):
		amount *= StatusEffects.POISON_HEAL_MULT
	if amount > 0.0 and current_hp < max_hp and not is_instance_valid(_heal_vfx):
		_heal_vfx = Vfx.attach(self, "heal", data.sprite_scale * EFFECT_SCALE)
	var before := current_hp
	current_hp = min(current_hp + amount, max_hp)
	if BattleManager.is_battle_running():
		_heal_unshown += current_hp - before
		if _heal_unshown >= FLOAT_HEAL_STEP:
			_float_text("+%d" % roundi(_heal_unshown), FLOAT_HEAL)
			_heal_unshown = 0.0

# -------------------------------------------------------
# ВИД: тень, кольцо стороны, статусы
# -------------------------------------------------------
# HP здесь не рисуется (полоска — у отряда, SquadBar): урон и лечение перерисовки не просят.
# Рисуется под спрайтом (дочерним): тень и кольцо стороны у ног — свои янтарные, враги красные
# (решение пользователя: стороны различимы не только оттенком спрайта). Статусы — точки над головой
func _draw() -> void:
	if data == null or current_state == State.DEAD or max_hp <= 0.0:
		return
	# Тень и кольцо стороны — общий слой SoldierShadows (один вызов на всех; здесь пакет рвался на каждом бойце).
	# Бруствер окопавшегося — Vfx "entrench" (_show_entrench)
	# Статус-эффекты — точки над головой, по точке на стак
	var stacks := 0
	for effect in status_effects:
		stacks += status_effects[effect]["stacks"]
	var dot_x := -stacks * (STATUS_DOT_R * 2.0 + 1.0) / 2.0
	var dot_y := -TARGET_SPRITE_HEIGHT * data.sprite_scale - STATUS_DOT_GAP
	for effect in status_effects:
		for i in status_effects[effect]["stacks"]:
			draw_circle(Vector2(dot_x + STATUS_DOT_R, dot_y), STATUS_DOT_R, StatusEffects.COLORS.get(effect, Color.WHITE))
			dot_x += STATUS_DOT_R * 2.0 + 1.0

# -------------------------------------------------------
# ДВИЖЕНИЕ
# -------------------------------------------------------
func _move_towards(point: Vector2, delta: float) -> void:
	var direction = (point - global_position).normalized()
	var speed = current_move_speed * get_move_speed_mult()   # замедление (ауры зданий игрока)
	var step: Vector2 = direction * speed * delta
	# Стена владений (решение пользователя 22.10.2026): враг снаружи не входит через целое звено — встаёт и ломает.
	# Точка снаружи, а путь срезает угол владений — обходит вдоль звена (иначе стоял бы: ломать незачем, идти некуда)
	if team == GameConstants.TEAM_ENEMY and BattleManager.has_kingdom_wall():
		var wall = BattleManager.kingdom_wall
		var seg = wall.blocking_segment(global_position, global_position + step)
		if seg and wall.is_inside(point):
			wall_segment = seg
			_face(direction)
			_attack_wall(delta)
			return
		wall_segment = null
		if seg:
			var along: Vector2 = (seg.b - seg.a).normalized()
			step = along * (1.0 if step.dot(along) >= 0.0 else -1.0) * step.length()
			if wall.blocking_segment(global_position, global_position + step):
				return
			direction = step.normalized()
	global_position += step
	_moved = true
	_face(direction)
	_play_animation("walk")
	sprite.speed_scale = walk_anim_scale(speed)

func _face(direction: Vector2) -> void:
	if absf(direction.x) > 0.01:
		sprite.flip_h = direction.x < 0.0

func _has_valid_target() -> bool:
	return is_instance_valid(target) and target.current_state != State.DEAD

# После стана возвращаемся туда, где были; из «контроля» — сразу в погоню
func _resume_after_control() -> void:
	match previous_state:
		State.IDLE, State.MOVE, State.CHASE, State.ATTACK, State.RETREATING:
			transition_to(previous_state)
		_:
			transition_to(State.CHASE)

# -------------------------------------------------------
# КОНТРОЛЬ (стан, отбрасывание) — вызывают способности/здания
# -------------------------------------------------------
func apply_stun(duration: float) -> void:
	if current_state == State.DEAD or _leap_time > 0.0 or _special_left > 0.0:   # в прыжке и приёме контроль не действует
		return
	# Повторный стан не перезаписывает previous_state, только продлевает таймер
	stun_timer = max(stun_timer, duration)
	transition_to(State.STUNNED)

func apply_knockback(direction: Vector2, force: float) -> void:
	if current_state == State.DEAD or current_state == State.STUNNED or _leap_time > 0.0 or _special_left > 0.0 			or data.knockback_immune:
		return
	knockback_velocity = direction.normalized() * force
	transition_to(State.KNOCKBACK)
	Vfx.spawn(_world_parent(), "ground_slam", global_position, data.sprite_scale * EFFECT_SCALE)
	request_hitstop(self)

# -------------------------------------------------------
# АТАКА И УРОН
# -------------------------------------------------------
# Стрелок (UnitData.projectile) выпускает снаряд — урон и эффекты при попадании
# (Projectile._impact); ближний бой бьёт сразу.
func _do_attack() -> void:
	if not is_instance_valid(target):
		return
	_play_attack_animation()
	var shot := _shoot_projectile(target, Vector2(0.0, -TARGET_SPRITE_HEIGHT * 0.45 * target.data.sprite_scale))
	if shot:
		shot.damage = _roll_damage()
		shot.stun = data.on_hit_stun
		shot.knockback = data.on_hit_knockback
		var st = _on_hit_status()
		shot.status = st[0]
		shot.status_power = st[1]
		shot.status_duration = st[2]
		shot.poison_power = bonus_poison_power
		shot.charm_chance = charm_chance
		return
	var frames := sprite.sprite_frames
	if frames and frames.has_meta("hit_frame"):
		# Удар — когда кулак / меч дойдёт до цели (кадр hit_frame), а не в начале замаха.
		# Прошлый замах ещё не дошёл (атака быстрее анимации) — он засчитывается сейчас, не теряется
		if _hit_timer > 0.0:
			_resolve_melee_hit()
		_hit_target = target
		_hit_timer = maxf(frames.get_meta("hit_frame") / frames.get_animation_speed("attack") / _attack_anim_scale(),
			GameConstants.FIXED_TICK)
		return
	_land_melee_hit(target)

# Анимация атаки длиннее перерыва между ударами (быстрая атака, баффы, Librarian — после каста
# остаётся мало) — играется быстрее, чтобы следующий удар не обрывал замах; кадр выстрела / удара
# сдвигается вместе с ней (_attack_anim_scale). Медленнее листа — не бывает
const ATTACK_ANIM_FILL: float = 0.9   # анимация укладывается в эту долю перерыва
const ATTACK_ANIM_MAX_SCALE: float = 3.0   # не быстрее: Librarian 3-го уровня — цикл короче каста, замах был бы мельканием
func _play_attack_animation() -> void:
	sprite.stop()
	sprite.play("attack")   # animation_changed сбрасывает speed_scale — ставим после
	sprite.speed_scale = _attack_anim_scale()

func _attack_anim_scale() -> float:
	var frames := sprite.sprite_frames
	if frames == null or not frames.has_animation("attack") or frames.get_frame_count("attack") == 0:
		return 1.0
	var length: float = frames.get_frame_count("attack") / frames.get_animation_speed("attack")
	var gap: float = 1.0 / maxf(current_attack_speed * get_attack_speed_mult(), 0.01) - data.cast_time
	return clampf(length / maxf(gap * ATTACK_ANIM_FILL, GameConstants.FIXED_TICK), 1.0, ATTACK_ANIM_MAX_SCALE)

func _tick_melee_hit(delta: float) -> void:
	if _hit_timer <= 0.0:   # тесты зовут и после удара
		return
	_hit_timer -= delta
	if _hit_timer <= TIMER_EPSILON:
		_resolve_melee_hit()

# Замах дошёл: урон, если цель жива и рядом (дальность × MELEE_HIT_REACH), иначе мимо
func _resolve_melee_hit() -> void:
	_hit_timer = 0.0
	var victim := _hit_target
	_hit_target = null
	if is_instance_valid(victim) and victim.current_state != State.DEAD \
			and global_position.distance_to(victim.global_position) <= current_attack_range * MELEE_HIT_REACH:
		_land_melee_hit(victim)

func _land_melee_hit(victim: Soldier) -> void:
	var prev_target := target
	target = victim   # эффекты попадания (_apply_on_hit_effects) — по тому, кого ударили
	var dmg := _roll_damage()
	AudioManager.play("melee_hit")
	BattleManager.credit_damage(parent_squad, clampf(dmg - victim.shield, 0.0, victim.current_hp))
	var boss := data.special_kind != ""
	victim.take_damage(dmg, true, boss)
	if boss:
		request_hitstop(self)   # удар примарха — стоп-кадр (предел частоты — BattleScene.HITSTOP_GAP_MS)
	if lifesteal > 0.0:
		heal(dmg * lifesteal)
		BuildingFx.lifesteal(self, data.sprite_scale)   # кровавые нити к груди (Чаша крови)
	var body := victim.global_position + Vector2(0.0, -TARGET_SPRITE_HEIGHT * 0.45 * victim.data.sprite_scale)
	Vfx.spawn_blood(_world_parent(), body, victim.data, false, EFFECT_SCALE)
	Vfx.spawn(_world_parent(), "slash", body, EFFECT_SCALE, (victim.global_position - global_position).angle())
	_apply_on_hit_effects()
	if is_instance_valid(prev_target):
		target = prev_target

# Снаряд из ствола (метаданные muzzle кадров) на кадре вспышки (shot_frame);
# null — юнит без снаряда (ближний бой)
func _shoot_projectile(to: Node2D, aim_offset: Vector2) -> Projectile:
	if data.projectile == "" or parent_squad == null:
		return null
	var frames := sprite.sprite_frames
	var delay := 0.0
	if frames.has_meta("shot_frame"):   # анимация атаки ускорена под частые выстрелы — кадр вспышки раньше
		delay = frames.get_meta("shot_frame") / frames.get_animation_speed("attack") / _attack_anim_scale()
	var shot := Projectile.launch(parent_squad.get_parent(), data.projectile, _muzzle_point(),
			to, aim_offset, delay, data.projectile_warm, frames.get_meta("muzzle_color", Color(0, 0, 0, 0)))
	shot.source = parent_squad
	shot.origin_fn = _muzzle_point   # к кадру вспышки стрелок мог сдвинуться — вылет из ствола там, где он сейчас
	return shot

# Ствол в мире (metadata/muzzle листа — от центра низа кадра; нет — у груди)
func _muzzle_point() -> Vector2:
	var frames := sprite.sprite_frames
	var base_h := TARGET_SPRITE_HEIGHT / _sprite_k   # рост фигуры в кадре (scale.y проседает на шаге)
	var muzzle: Vector2 = frames.get_meta("muzzle", Vector2(base_h * 0.3, -base_h * 0.5))
	if sprite.flip_h:
		muzzle.x = -muzzle.x
	return global_position + muzzle * _sprite_k

# Урон одного удара: аура союзников + разброс damage_variance
func _roll_damage() -> float:
	var damage = current_damage * (1.0 + get_aura_damage_bonus()) * get_damage_mult() * (1.0 + get_entrench_bonus())
	var variance = damage * data.damage_variance
	return randf_range(damage - variance, damage + variance)

# Эффекты попадания из данных юнита (Librarian — стан, Dreadnought — отбрасывание)
func _apply_on_hit_effects() -> void:
	if not _has_valid_target():
		return
	if data.on_hit_stun > 0.0:
		target.apply_stun(data.on_hit_stun)
	var st = _on_hit_status()
	if st[0] != "":
		target.apply_status(st[0], st[1], st[2])
		if st[0] == StatusEffects.BURNING:   # поджог (Salamanders) — язык пламени по удару
			Vfx.spawn(_world_parent(), "flame_burst",
				target.global_position + Vector2(0.0, -TARGET_SPRITE_HEIGHT * 0.45 * target.data.sprite_scale),
				EFFECT_SCALE, (target.global_position - global_position).angle())
	if data.on_hit_knockback > 0.0:
		target.apply_knockback(target.global_position - global_position, data.on_hit_knockback)
	apply_blessing_hit(target, bonus_poison_power, charm_chance, parent_squad)

# Яд благословения / Котла и порабощение Слаанеш при попадании (удар — здесь, снаряд — Projectile._impact)
static func apply_blessing_hit(victim: Soldier, poison: float, charm: float, by: Squad) -> void:
	if not is_instance_valid(victim) or victim.current_state == State.DEAD:
		return
	if poison > 0.0:
		victim.apply_status(StatusEffects.POISONED, poison, ChaosGods.POISON_TIME)
	if charm > 0.0 and randf() < charm and victim.can_be_charmed(by):   # случайность боя, как разброс урона
		victim.charm(by)

# Порабощать нельзя элиту, командиров и боссов; уже порабощённого и бойца своей стороны
func can_be_charmed(by: Squad) -> bool:
	return is_instance_valid(by) and by.is_alive() and team != by.team and not charmed 		and not ("elite" in data.tags or "commander" in data.tags)

# Порабощён (благословение Слаанеш): уходит из своего отряда в отряд, который его поработил, и бьётся за него до
# конца боя; после выигранного боя порабощённые возвращают павших этого отряда или лечат его
# (BattleManager.apply_thralls). Бойцом отряда не становится — sync_army_from_squads его пропускает
const CHARM_TINT = Color(1.0, 0.72, 0.92)
func charm(by: Squad) -> void:
	BuildingFx.charm(self, by)   # розовая цепь от поработившего отряда (EFFECTS_NEEDED 4.11, кодом 09.11.2026)
	if parent_squad:
		parent_squad.release_soldier(self)
	charmed = true
	team = by.team
	target = null
	_hit_target = null
	_hit_timer = 0.0
	parent_squad = by
	reparent(by)
	by.adopt_soldier(self)
	sprite.flip_h = team == GameConstants.TEAM_ENEMY
	_update_light()
	SoldierRegistry.mark_dirty()
	SoldierRegistry.invalidate_grid()
	BattleManager.add_thrall(by.data)
	_float_text("Порабощён!", Palette.SLAANESH)
	if current_state not in [State.STUNNED, State.KNOCKBACK]:
		transition_to(State.MOVE)

# Эффект попадания: свой у юнита (Plague Marine, Havoc), иначе от ордена
func _on_hit_status() -> Array:
	if data.on_hit_status != "":
		return [data.on_hit_status, data.on_hit_status_power, data.on_hit_status_duration]
	return [extra_on_hit_status, extra_on_hit_status_power, extra_on_hit_status_duration]

# Бонус урона от аур союзников рядом (Chaplain). Считается в момент удара —
# runtime-поля не меняются, поэтому аура пропадает, как только отошли из радиуса.
func get_aura_damage_bonus() -> float:
	# Носители аур — кэш реестра: Chaplain (aura_damage_bonus, по тегу) и знамя Chapter Banner
	# (banner_aura_bonus, всем в BANNER_RADIUS). Не суммируются — берётся сильнейшая
	var best: float = 0.0
	for ally in SoldierRegistry.get_aura_sources(team):
		var a: UnitData = ally.data
		var d2 := global_position.distance_squared_to(ally.global_position)
		if a.aura_damage_bonus > best and (a.aura_tag == "" or a.aura_tag in data.tags) and d2 <= a.aura_radius * a.aura_radius:
			best = a.aura_damage_bonus
		if a.banner_aura_bonus > best and d2 <= UnitData.BANNER_RADIUS * UnitData.BANNER_RADIUS:
			best = a.banner_aura_bonus
	return best

# flash = false — урон яда/огня: без вспышки каждые полсекунды
# big — удар босса: цифра крупнее (BOSS_NUMBER_SIZE)
func take_damage(amount: float, flash: bool = true, big: bool = false) -> void:
	if current_state == State.DEAD:
		return
	amount *= damage_taken_mult
	if shield > 0.0:
		var absorbed = minf(shield, amount)
		shield -= absorbed
		amount -= absorbed
	current_hp -= amount
	if flash:
		_flash_hit()
		if amount >= FLOAT_MIN_DAMAGE and BattleManager.is_battle_running():
			_float_text("%d" % roundi(amount),
				FLOAT_HIT_TO_PLAYER if team == GameConstants.TEAM_PLAYER else FLOAT_HIT_TO_ENEMY,
				BOSS_NUMBER_SIZE if big else 1.0)
	if current_hp <= 0.0:
		if _try_revive():
			return
		_die()
		return
	if not enraged and data.special_kind != "" and current_hp <= max_hp * ENRAGE_AT:
		_enrage()
	if not has_retreated and current_hp / max_hp < data.get_retreat_threshold() and _leap_time <= 0.0 \
			and current_state not in [State.IDLE, State.STUNNED, State.KNOCKBACK]:
		has_retreated = true
		retreat_timer = data.retreat_duration
		transition_to(State.RETREATING)

# Материал бойца: броня ордена (только своим Космодесантникам; у врагов и Ultramarines без "armor" — как нарисовано),
# подсветка края (тема "unit_rim"), контур — у всех
func _apply_chapter_colors() -> void:
	_armor_chapter = ""
	if team == GameConstants.TEAM_PLAYER and data.faction == Chapters.FACTION and data.chapter_armor:
		if Chapters.get_chapter(RunManager.player_chapter).has("armor"):
			_armor_chapter = RunManager.player_chapter
	_rim_px = 0
	_rim = FactionTheme.current().get("unit_rim", {})
	if _armor_chapter == "" and not _rim.is_empty() and data.faction == RunManager.player_faction:
		_rim_px = maxi(1, roundi(RIM_SCREEN_PX / maxf(sprite.scale.x, 0.01)))
	_outline_px = maxi(1, roundi(OUTLINE_WORLD_PX / maxf(sprite.scale.x, 0.01)))
	_pix = maxi(1, roundi(PIXEL_WORLD_PX / maxf(sprite.scale.x, 0.01))) if PIXEL_WORLD_PX > 0.0 else 0
	_base_material = _unit_material(false)
	_unit_material(true)   # вспышка — заранее, не на первом попадании в бою
	sprite.material = _base_material

# Общий шейдер бойца (UNIT_SHADER) — и для своих материалов вне кэша (цитадель: своя вспышка попадания)
static func unit_shader() -> Shader:
	if _unit_shader == null:
		_unit_shader = Shader.new()
		_unit_shader.code = UNIT_SHADER
	return _unit_shader

# Только тёмный контур, как у бойцов (решение пользователя 24.10.2026: здания — с той же обводкой):
# world_px px мира при масштабе спрайта sprite_scale, цвет color; материал общий из того же кэша
static func outline_material(sprite_scale: float, world_px: float = OUTLINE_WORLD_PX,
		color: Color = Palette.OUTLINE) -> ShaderMaterial:
	var px := maxi(1, roundi(world_px / maxf(sprite_scale, 0.01)))
	var key := "|0|%d|false|%s" % [px, color.to_html()]
	if not _unit_materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = unit_shader()
		m.set_shader_parameter("outline_px", float(px))
		m.set_shader_parameter("outline_color", color)
		_unit_materials[key] = m
	return _unit_materials[key]

func _unit_material(flashing: bool) -> ShaderMaterial:
	var key := "%s|%d|%d|%s|%d|%s|%d" % [_armor_chapter, _rim_px, _outline_px, flashing, _pix, RunManager.player_faction,
		_status_mask]
	if not _unit_materials.has(key):
		if _unit_shader == null:
			_unit_shader = Shader.new()
			_unit_shader.code = UNIT_SHADER
		var m := ShaderMaterial.new()
		m.shader = _unit_shader
		if _armor_chapter != "":
			var armor: Dictionary = Chapters.get_chapter(_armor_chapter).get("armor", {})
			m.set_shader_parameter("armor", 1.0)
			m.set_shader_parameter("target_hue", armor.get("hue", 0.6))
			m.set_shader_parameter("sat_mult", armor.get("sat", 1.0))
			m.set_shader_parameter("val_mult", armor.get("val", 1.0))
		if _rim_px > 0:
			var col: Color = _rim.get("color", Color.WHITE)
			m.set_shader_parameter("rim_px", float(_rim_px))
			m.set_shader_parameter("rim_color", Vector3(col.r, col.g, col.b))
			m.set_shader_parameter("rim_strength", _rim.get("strength", 0.5))
		m.set_shader_parameter("outline_px", float(_outline_px))
		m.set_shader_parameter("outline_color", Palette.OUTLINE)
		m.set_shader_parameter("flash", HIT_FLASH_STRENGTH if flashing else 0.0)
		m.set_shader_parameter("pix", float(_pix))
		for i in STATUS_BODY.size():
			var st: Array = STATUS_BODY[i]
			if _status_mask & (1 << i):
				var col: Color = st[2]
				m.set_shader_parameter(st[1], 1.0)
				m.set_shader_parameter(st[1] + "_color", Vector3(col.r, col.g, col.b))
		var env: Dictionary = FactionTheme.current().get("unit_env", {})
		if not env.is_empty():
			var t: Color = env.get("tint", Color.WHITE)
			var lc: Color = env.get("light_color", Color.WHITE)
			m.set_shader_parameter("env_tint", Vector3(t.r, t.g, t.b))
			m.set_shader_parameter("env_sat", env.get("sat", 1.0))
			m.set_shader_parameter("env_knee", env.get("knee", 0.0))
			m.set_shader_parameter("ao_strength", env.get("ao", 0.0))
			m.set_shader_parameter("ao_from", UNIT_AO_FROM)
			m.set_shader_parameter("ao_to", 1.0)
			m.set_shader_parameter("vol_light", env.get("light", 0.0))
			m.set_shader_parameter("vol_shade", env.get("shade", 0.0))
			m.set_shader_parameter("vol_grad", env.get("grad", 0.0))
			m.set_shader_parameter("vol_color", Vector3(lc.r, lc.g, lc.b))
		_unit_materials[key] = m
	return _unit_materials[key]

# Только визуал: гаснет по времени дерева в _process (на паузе стоит, ×2 ускоряет), а не по тику боя —
# иначе вспышка последнего тика осталась бы гореть после конца боя. Повторный урон продлевает.
# Раньше — таймер дерева с лямбдой на каждое попадание: сотни объектов за тик в сшибке
func _flash_hit() -> void:
	if not is_inside_tree():
		return
	sprite.material = _unit_material(true)
	_flash_left = HIT_FLASH_TIME
	if _leap_time <= 0.0:   # в прыжке дуга спрайта — своя
		_recoil_left = RECOIL_TIME

# Apothecarion рядом: шанс встать с долей HP (один раз за бой, только игрок)
func _try_revive() -> bool:
	if team != GameConstants.TEAM_PLAYER or has_revived:
		return false
	if not is_instance_valid(parent_squad):
		return false
	var r = Building.revive_at(parent_squad.tile)   # клетка отряда — в зоне Apothecarion (крест)
	if r["chance"] <= 0.0 or randf() >= r["chance"]:
		return false
	has_revived = true
	current_hp = max_hp * r["hp"]
	if BattleManager.is_battle_running():
		_float_text("Встал!", FLOAT_HEAL)   # иначе подъём на поле незаметен
		LevelUpGlow.play(self, 0, 0.0, "heal")   # свет лечения на бойце (лист пакета revive — неоновый столб)
		AudioManager.play("revive")
	return true

func _die() -> void:
	if current_state == State.DEAD:
		return
	_end_leap_view()
	_special_left = 0.0
	_clear_telegraph()
	transition_to(State.DEAD)
	if data.special_kind != "" and _flash_left > 0.0:   # вспышка смертельного удара в замедлении ×0.25 белила
		_flash_left = 0.0                              # примарха 0.4 с — текстура видна сразу
		sprite.material = _base_material
	if data.special_kind != "" and is_inside_tree():   # примарх пал — кинематографичный миг (BattleScene.boss_fall)
		var scene := get_tree().current_scene
		if scene and scene.has_method("boss_fall"):
			scene.boss_fall(self)
	AudioManager.play("death_vehicle" if "vehicle" in data.tags else "death")
	if BattleManager.is_battle_running():   # шрам поля: техника — подпалина, остальные — пятно крови
		if "vehicle" in data.tags:
			ScarLayer.scorch(global_position, SCAR_RADIUS * 2.5 * data.sprite_scale)
		else:
			ScarLayer.blood(global_position, SCAR_RADIUS * data.sprite_scale,
				Vfx.BLOOD_COLORS.get(data.get_blood(), Vfx.BLOOD_COLORS["red"]))
	if "vehicle" in data.tags:   # техника взрывается: огонь, обломки, чёрный дым
		Vfx.spawn(_world_parent(), "vehicle_explode", global_position, data.sprite_scale * EFFECT_SCALE)
		IsoGridRenderer.flash_light(global_position, Color(Palette.FIRE, 1.0), 90.0 * data.sprite_scale, 0.45)
		request_hitstop(self)
	status_effects.clear()
	_sync_status_vfx()
	queue_redraw()   # убрать тень, кольцо и точки статусов
	emit_signal("died", self)

# -------------------------------------------------------
# СТАТУС-ЭФФЕКТЫ (StatusEffects) — поверх FSM, тикают с боем
# -------------------------------------------------------
# stackable: удар добавляет стак (до MAX_STACKS); аура (false) держит 1 стак.
# Время обновляется, сила — наибольшая из наложенных.
func apply_status(effect: String, power: float, duration: float, stackable: bool = true) -> void:
	if current_state == State.DEAD or effect == "" or duration <= 0.0:
		return
	var e: Dictionary = status_effects.get(effect, {})
	if e.is_empty():
		if effect == StatusEffects.BURNING or effect == StatusEffects.POISONED:
			AudioManager.play("burning" if effect == StatusEffects.BURNING else "poison")
		e = {"stacks": 1, "power": power, "time": duration, "duration": duration,
			"dot_timer": StatusEffects.DOT_TICK, "spread_timer": StatusEffects.BURN_SPREAD_EVERY}
		status_effects[effect] = e
	else:
		if stackable:
			e["stacks"] = mini(e["stacks"] + 1, StatusEffects.MAX_STACKS)
		e["power"] = maxf(e["power"], power)
		e["time"] = maxf(e["time"], duration)
		e["duration"] = maxf(e["duration"], duration)
	_sync_status_vfx()
	queue_redraw()

func get_status_stacks(effect: String) -> int:
	return status_effects[effect]["stacks"] if status_effects.has(effect) else 0

# Сила эффекта с учётом стаков (0 — эффекта нет)
func _status_amount(effect: String) -> float:
	if not status_effects.has(effect):
		return 0.0
	var e: Dictionary = status_effects[effect]
	return e["power"] * e["stacks"]

func get_damage_mult() -> float:
	return 1.0 + _status_amount(StatusEffects.EMPOWERED)

func get_move_speed_mult() -> float:
	return maxf(1.0 - _status_amount(StatusEffects.SLOWED), StatusEffects.MIN_SPEED_MULT)

func get_attack_speed_mult() -> float:
	return maxf(1.0 - _status_amount(StatusEffects.SLOWED) * StatusEffects.SLOW_ATTACK_SHARE,
		StatusEffects.MIN_SPEED_MULT)

func _tick_status_effects(delta: float) -> void:
	if status_effects.is_empty() or current_state == State.DEAD:
		return
	var expired: Array[String] = []
	for effect in status_effects.keys():
		var e: Dictionary = status_effects[effect]
		if StatusEffects.is_dot(effect):
			e["dot_timer"] -= delta
			if e["dot_timer"] <= TIMER_EPSILON:
				e["dot_timer"] += StatusEffects.DOT_TICK
				# Доля бойца (UnitData.unit_weight): мелкий боец пехоты горит / травится втрое слабее
				take_damage(e["power"] * e["stacks"] * StatusEffects.DOT_TICK * data.unit_weight, false)
				if current_state == State.DEAD:
					return
		if effect == StatusEffects.BURNING:
			e["spread_timer"] -= delta
			if e["spread_timer"] <= TIMER_EPSILON:
				e["spread_timer"] += StatusEffects.BURN_SPREAD_EVERY
				_spread_burning(e)
		e["time"] -= delta
		if e["time"] <= TIMER_EPSILON:
			expired.append(effect)
	for effect in expired:
		status_effects.erase(effect)
	if not expired.is_empty():
		_sync_status_vfx()
		queue_redraw()

# Эффект на бойце на каждый действующий статус (StatusEffects.VFX): появился — надеть, прошёл — снять
func _sync_status_vfx() -> void:
	var mask := 0
	for i in STATUS_BODY.size():
		if status_effects.has(STATUS_BODY[i][0]) or (enraged and STATUS_BODY[i][0] == StatusEffects.EMPOWERED):
			mask |= 1 << i   # ярость босса — тело тлеет, как под усилением
	if mask != _status_mask and _base_material != null:
		_status_mask = mask
		_base_material = _unit_material(false)
		sprite.material = _unit_material(true) if _flash_left > 0.0 else _base_material
	for effect in _status_vfx.keys():
		if not status_effects.has(effect):
			Vfx.dismiss(_status_vfx[effect])   # тает, а не пропадает
			_status_vfx.erase(effect)
	for effect in status_effects:
		if not _status_vfx.has(effect) and StatusEffects.VFX.has(effect):
			_status_vfx[effect] = Vfx.attach(self, StatusEffects.VFX[effect], data.sprite_scale * EFFECT_SCALE)

func _float_text(label: String, tint: Color, size: float = 1.0) -> void:
	FloatingText.spawn(_world_parent(), global_position + Vector2(0.0, -TARGET_SPRITE_HEIGHT * data.sprite_scale - 6.0),
		label, tint, size)

# Куда класть разовые эффекты в мире — туда же, куда снаряды (узел отрядов)
func _world_parent() -> Node:
	return parent_squad.get_parent() if parent_squad else null

# Огонь перекидывается на ближайшего негорящего соседа своей команды (1 стак)
# с остатком своего времени: цепочка гаснет, соседи не поджигают друг друга вечно
func _spread_burning(e: Dictionary) -> void:
	if e["time"] <= StatusEffects.BURN_SPREAD_EVERY + TIMER_EPSILON:
		return
	var best: Soldier = null
	var best_d2: float = StatusEffects.BURN_SPREAD_RADIUS * StatusEffects.BURN_SPREAD_RADIUS
	for ally in SoldierRegistry.get_alive_soldiers_of_team(team):
		if ally == self or ally.status_effects.has(StatusEffects.BURNING):
			continue
		var d2 = global_position.distance_squared_to(ally.global_position)
		if d2 <= best_d2:
			best_d2 = d2
			best = ally
	if best:
		best.apply_status(StatusEffects.BURNING, e["power"], e["time"], false)

# Боевой клич (Chaplain): один раз за бой, при первом сближении с врагом
func _try_battle_cry() -> bool:
	if battle_cry_used or data.battle_cry_status == "":
		return false
	battle_cry_used = true
	AudioManager.play("battle_cry")
	Vfx.spawn(_world_parent(), "chaplain_warcry", global_position, data.battle_cry_radius)   # кольцо по радиусу клича
	var r2 = data.battle_cry_radius * data.battle_cry_radius
	for ally in SoldierRegistry.get_alive_soldiers_of_team(team):
		if global_position.distance_squared_to(ally.global_position) <= r2:
			# Без стаков: клич пары Chaplain (UnitFactory.PAIR_UNITS) — как клич одного
			ally.apply_status(data.battle_cry_status, data.battle_cry_power, data.battle_cry_duration, false)
	return true

# -------------------------------------------------------
# ПОИСК ЦЕЛИ
# -------------------------------------------------------
# Боец спрашивает свой отряд о врагах —
# отряд знает о всех вражеских бойцах
func _find_target() -> Soldier:
	var enemies = SoldierRegistry.get_alive_soldiers_of_team(1 - team)
	if enemies.is_empty():
		return null

	match data.priority:
		GameConstants.PRIORITY_NEAREST:
			return SoldierRegistry.find_nearest(1 - team, global_position)
		GameConstants.PRIORITY_LOWEST_HP:
			return _get_lowest_hp(enemies)
		GameConstants.PRIORITY_HIGHEST_THREAT:
			return _get_highest_threat(enemies)
		GameConstants.PRIORITY_FARTHEST:
			return _get_farthest(enemies)
		GameConstants.PRIORITY_RANDOM:
			return enemies[randi() % enemies.size()]
		GameConstants.PRIORITY_RANGED_FIRST:
			return _get_nearest_ranged()
		_:
			return SoldierRegistry.find_nearest(1 - team, global_position)

# Ближайший стрелок; стрелков нет — просто ближайший
func _get_nearest_ranged() -> Soldier:
	var closest = SoldierRegistry.find_nearest(1 - team, global_position, INF, true)
	return closest if closest else SoldierRegistry.find_nearest(1 - team, global_position)

func _get_farthest(units: Array) -> Soldier:
	var farthest: Soldier = null
	var max_dist: float = -INF
	for u in units:
		var d = global_position.distance_squared_to(u.global_position)
		if d > max_dist:
			max_dist = d
			farthest = u
	return farthest

func _get_lowest_hp(units: Array) -> Soldier:
	var result: Soldier = null
	var min_hp: float = INF
	for u in units:
		if u.current_hp < min_hp:
			min_hp = u.current_hp
			result = u
	return result

func _get_highest_threat(units: Array) -> Soldier:
	var result: Soldier = null
	var max_dmg: float = -INF
	for u in units:
		if u.current_damage > max_dmg:
			max_dmg = u.current_damage
			result = u
	return result

# -------------------------------------------------------
# ПЕРЕХОД МЕЖДУ СОСТОЯНИЯМИ
# -------------------------------------------------------
func transition_to(new_state: State) -> void:
	# Повторный вход в то же состояние и выход из DEAD запрещены
	if current_state == new_state or current_state == State.DEAD:
		return
	previous_state = current_state
	current_state = new_state
	_on_state_enter(new_state)

func _on_state_enter(state: State) -> void:
	# Оглушение и каст видны, пока боец в этом состоянии
	Vfx.dismiss(_state_vfx)
	_state_vfx = null
	if state in [State.STUNNED, State.KNOCKBACK, State.DEAD]:
		_hit_timer = 0.0   # замах сорван
		_hit_target = null
	if state == State.STUNNED:
		_state_vfx = Vfx.attach(self, "stun", data.sprite_scale * EFFECT_SCALE)
	elif state == State.CASTING and not sprite.sprite_frames.has_animation("cast"):
		_state_vfx = Vfx.attach(self, "cast", data.sprite_scale * EFFECT_SCALE)   # своего каста на листе нет
	match state:
		State.IDLE, State.STUNNED, State.KNOCKBACK:
			_play_animation("idle")
		State.MOVE, State.CHASE, State.RETREATING:
			_play_animation("walk")
			if state == State.RETREATING:   # пыль из-под ног — боец бросился назад
				Vfx.spawn(_world_parent(), "retreat_dust", global_position, data.sprite_scale * EFFECT_SCALE)
		State.ATTACK:
			# Первый удар — со сдвигом бойца (отряд бьёт вразнобой); до него — стойка
			attack_timer = attack_stagger * ATTACK_STAGGER / maxf(current_attack_speed * get_attack_speed_mult(), 0.01)
			sprite.stop()
			if _try_battle_cry() and sprite.sprite_frames.has_animation("battle_cry"):
				attack_timer = BATTLE_CRY_TIME   # сначала клич, выстрел — после
				sprite.play("battle_cry")
			else:
				sprite.play("idle")
		State.CASTING:
			cast_timer = data.cast_time
			# Каст листа (Librarian: ряд cast) — замах посохом, держится на последнем кадре
			_play_animation("cast" if sprite.sprite_frames.has_animation("cast") else "idle")
		State.DEAD:
			sprite.stop()
			sprite.play("death")
			_show_entrench(false)
			var pool: Vfx = null
			if data.special_kind != "" and _world_parent():
				# Примарх (решение пользователя 09.11.2026): лужа ребёнком прямо за спрайтом — в Compatibility босс
				# рисовался белым раздутым силуэтом, пока она играла; лужа — в мире, на пиксель выше ног (y-sort: за телом)
				pool = Vfx.spawn(_world_parent(), "splatter", global_position - Vector2(0.0, 1.0),
					data.sprite_scale * EFFECT_SCALE)
				if pool:
					pool.z_index = z_index
			else:
				pool = Vfx.attach(self, "splatter", data.sprite_scale * EFFECT_SCALE)
			if pool:
				pool.material = Vfx.blood_material(data.get_blood())   # лужа — цвета крови павшего
			sprite.animation_finished.connect(_on_death_finished)

func _on_death_finished() -> void:
	if current_state != State.DEAD:
		return
	if data.special_kind != "":
		_fade_boss_corpse()
		return
	var timer = get_tree().create_timer(0.3, false)   # на паузе не тикает
	timer.timeout.connect(queue_free)

# Тело примарха (решение пользователя 09.11.2026: «умирают инородно» — через 0.3 с после последнего кадра
# пропадало рывком): последний кадр лежит BOSS_CORPSE_HOLD, потом темнеет в тон земли и тает за BOSS_CORPSE_FADE
func _fade_boss_corpse() -> void:
	var tw := create_tween()
	tw.tween_interval(BOSS_CORPSE_HOLD)
	tw.tween_property(sprite, "modulate", BOSS_CORPSE_TINT, BOSS_CORPSE_FADE).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(queue_free)
