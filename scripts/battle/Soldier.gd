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
const GROUND_SINK: float = 7.5   # px мира: на сколько ступни ниже точки бойца — стоит в земле, а не над ней
# Эффекты на бойце (Vfx) подобраны под рост 62 px
const EFFECT_SCALE: float = TARGET_SPRITE_HEIGHT / 62.0
# Полоска HP и уровень — у отряда (SquadBar); у бойца — тень, кольцо стороны и точки статусов
const STATUS_DOT_R: float = 1.5
const STATUS_DOT_GAP: float = 3.0
# 17.11.2026 (решение пользователя: «юниты будто летают над текстурами, а не ходят»): тень была 6 × sprite_scale — у
# Tactical эллипс 8 px при теле ~14 px, весь прятался за ступнями; теперь шире тела, а центр сдвинут вниз (SHADOW_DROP)
const SHADOW_RADIUS: float = 8.5       # × sprite_scale; эллипс сплюснут, как клетка изометрии
const SHADOW_DROP: float = 2.2         # × sprite_scale: центр тени ниже точки ног — из-под сапог выглядывает полумесяц тени
const SHADOW_FLATTEN: float = 0.5
# Тень под ногами темнее (стилизация 12.11.2026, скилл game-art «читаемость — контраст по яркости»: свои бойцы
# Хаоса медианой яркости 33 на грунте 29 — сливались; осветлять бойцов нельзя — решение пользователя 08.11.2026
# «юниты слишком выделяются»): силуэт отделяет тёмная подложка, было 0.35 / 0.16
const SHADOW_COLOR = Color(0, 0, 0, 0.55)
const SHADOW_SOFT = Color(0, 0, 0, 0.26)   # мягкий край тени: шире и прозрачнее
const SHADOW_SOFT_SCALE: float = 1.45
const RING_WIDTH: float = 2.0   # кольцо стороны под бойцом (решение пользователя 24.10.2026: было 1.5 / 0.6 — еле видно)
const RING_ALPHA: float = 0.85
# Всплывающие цифры (FloatingText) — только в схватке: удар не меньше FLOAT_MIN_DAMAGE
# (герои, техника, орудие; не каждый болт и не яд / огонь), лечение — порциями FLOAT_HEAL_STEP
const FLOAT_MIN_DAMAGE: float = 20.0
# Число урона крупнее от силы удара (доля max HP бойца): тяжёлый удар читается без цифр
const FLOAT_HEAVY_RATIO: float = 0.3
const FLOAT_HEAVY_SIZE: float = 1.3
const FLOAT_MEDIUM_RATIO: float = 0.15
const FLOAT_MEDIUM_SIZE: float = 1.15
const EMBER_LIGHT_RADIUS: float = 34.0   # свет горящего бойца на земле, × sprite_scale
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
# 17.11.2026: цикл короче / потолок выше (0.62 роста и ×5) пробовали — замер скольжения стопы по снимкам бегущего бойца на
# однотонном фоне (опорная ступня по нижнему кластеру силуэта) оказался слишком шумным, чтобы подтвердить выигрыш, а бег ×4–5
# мельтешит; оставлено прежнее (решение 23.10.2026), заземление — тень с шагом (STEP_SHADOW_*) и пыль
const WALK_CYCLE_HEIGHTS: float = 0.8   # 18.11.2026 («скользят ногами»): шаг листа ≈ 0.7–0.9 роста за цикл — было 1.0, ноги отставали
# Бег с весом (решение пользователя 18.11.2026): боец разгоняется и тормозит плавно (_run_k), на бегу чуть клонится
# вперёд, шаг у каждого свой в пределах ±PACE_SPREAD/2 — строй не бежит стеной в одной фазе и скорости
const RUN_ACCEL: float = 0.28          # с до полного темпа
const RUN_DECEL: float = 0.22          # с до остановки
const RUN_LEAN: float = 0.05           # рад (≈ 3°) наклон корпуса вперёд на полном бегу
const PACE_SPREAD: float = 0.08        # разброс скорости между бойцами отряда (доля, по attack_stagger)
const FACE_TURN_DOT: float = 0.25      # разворот лицом только при |x| направления больше — на вертикальном ходу не мерцает
const WALK_SCALE_LIMITS = Vector2(0.5, 3.0)
# Шаг кодом (решение пользователя 23.10.2026, Screenshot 2026-10-23 172747.png: «бегут по воздуху в одной позе»):
# в листах бега ступни ходят на 2–4 px при росте бойца на поле ~40 px — шага не видно, строй скользит.
# На каждом шаге корпус проседает (scale.y от ног — ступни на земле): STEP_DIP роста, STEPS_PER_CYCLE шагов за цикл
# Позиция для выстрела (17.11.2026, решение пользователя: «юнит перемещается по полю для правильного положения для выстрела»,
# модельку не наклонять): лист только отражается по горизонтали, ствол всегда горизонтален, а цель на изометрии бывает прямо
# над или под стрелком — снаряд летел поперёк ствола. Стрелок, у которого цель круче AIM_TAN (≈ 35° от горизонтали), перед
# выстрелом сдвигается по горизонтали в точку, откуда цель в пределах угла (дальность не превышается), и стреляет оттуда;
# дольше AIM_SHIFT_MAX сек не ищет (цель убегает / путь закрыт) — стреляет как стоит
const AIM_TAN: float = 0.7
const AIM_SHIFT_MAX: float = 1.5
const STEP_DIP: float = 0.06
# Тень откликается на шаг (17.11.2026, «на бегу летают»): на ступне — темнее и шире (вес на земле), в середине шага (корпус
# выпрямился) — бледнее и уже; step_lift 0..1 считает _process по той же фазе, что и приседание корпуса
const STEP_SHADOW_FADE: float = 0.45
const STEP_SHADOW_SHRINK: float = 0.16
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
var _run_k: float = 0.0           # 0..1 разгон бега (вид)
var attack_stagger: float = 0.0   # доля сдвига первого удара [0, 1) — номер бойца в отряде
const VISION_EVERY: int = 2       # марш: поиск врага в поле зрения раз в столько тиков (Soldier._state_move)
var _vision_wait: int = -1        # тиков до следующего поиска; −1 — сдвиг ещё не задан (по attack_stagger)
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
# Благословения богов Хаоса и Котёл Дедушки Тысячи (решение пользователя 25.10.2026, ChaosGods) — на этот бой:
var bonus_poison_power: float = 0.0  # яд в атаках поверх своего эффекта, ур/с (ChaosGods.POISON_TIME)
var charm_chance: float = 0.0        # шанс поработить цель при попадании (Король Второго Акта)
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
const UNIT_SHARPEN: float = 1.5      # резкость бойцов (нерезкая маска в UNIT_SHADER)
const PIXEL_WORLD_PX: float = 0.0
const UNIT_AO_FROM: float = 0.72   # затемнение к ногам: доля высоты кадра, откуда начинается
# Отсвет костров и свечения поля (IsoGridRenderer.light_at) на теле: раз в LIGHT_EVERY с, self_modulate спрайта
const LIGHT_EVERY: float = 0.25
# Статусы на теле (UNIT_SHADER st_*): [статус, uniform, цвет]; бит маски — индекс
const STATUS_BODY = [[StatusEffects.BURNING, "st_burn", Palette.FORGE], [StatusEffects.POISONED, "st_poison", Palette.POISON],
	[StatusEffects.SLOWED, "st_slow", Palette.FROST], [StatusEffects.EMPOWERED, "st_emp", Palette.AMBER_LIGHT]]
const UNIT_SHADER: Shader = preload("res://shaders/unit.gdshader")
static var _unit_materials: Dictionary = {}   # ключ "орден|подсветка|контур|вспышка" → ShaderMaterial
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
var step_lift: float = 0.0   # 0 — ступня на земле, 1 — середина шага (тень SoldierShadows бледнее и уже)
var _walk_cycle_time: float = 0.0   # длина цикла бега листа, сек (0 — бега нет); темп бега — walk_anim_scale

const ParallelLoad = preload("res://scripts/utils/ParallelLoad.gd")

# Кадры всех юнитов, что сейчас выйдут на поле, — разом, до расстановки (BattleScene)
static func preload_frames(sprite_paths: Array) -> void:
	var files := {}   # файл листа → папка юнита
	for sprite_path: String in sprite_paths:
		if not _frames_cache.has(sprite_path):
			files[sprite_path + "/frames.tres"] = sprite_path
	var loaded := ParallelLoad.load_all(files.keys())
	for path in loaded:
		_frames_cache[files[path]] = loaded[path]

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
	var flashing := _flash_light_left > 0.0
	if flashing:   # вспышка гаснет каждый кадр, и в кадр пересчёта отсвета (было: этот кадр пропускала)
		_flash_light_left -= delta
	if _light_left <= 0.0:
		_light_left = LIGHT_EVERY
		_update_light()
	elif flashing:
		_apply_light()
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			sprite.material = _base_material
	# Разгон и торможение бега, наклон корпуса (вид): без шага анимации сходит на нет за RUN_DECEL
	var running := sprite.animation == &"walk" and _leap_prev >= 1.0
	if running:
		_run_k = move_toward(_run_k, 1.0, delta / RUN_ACCEL)
	elif _run_k > 0.0:
		_run_k = move_toward(_run_k, 0.0, delta / RUN_DECEL)
	if _run_k > 0.0 or sprite.rotation != 0.0:
		sprite.rotation = (-1.0 if sprite.flip_h else 1.0) * RUN_LEAN * _run_k if _leap_prev >= 1.0 else 0.0
	if running:
		# Шаг: плавная волна — ниже всего на ступне, выпрямился к середине шага (резкая посадка дёргала);
		# и в бою, и на построении (BattleScene._deploy_army — бой ещё не идёт)
		var phase := (sprite.frame + sprite.frame_progress) / sprite.sprite_frames.get_frame_count(&"walk")
		sprite.scale.y = _sprite_k * (1.0 - STEP_DIP * (0.5 + 0.5 * _run_k) * 0.5 * (1.0 + cos(TAU * STEPS_PER_CYCLE * phase)))
		step_lift = 0.5 * (1.0 - cos(TAU * STEPS_PER_CYCLE * phase))
		var foot := int(phase * STEPS_PER_CYCLE)
		if foot != _last_foot:   # нога встала — пыль (тяжёлые — каждый шаг, пехота — реже)
			_last_foot = foot
			_steps += 1
			var heavy := "vehicle" in data.tags or data.sprite_scale >= HEAVY_DUST_SCALE
			if heavy or _steps % DustLayer.INFANTRY_EVERY == 0:
				DustLayer.puff(global_position, (6.0 if heavy else 3.5) * data.sprite_scale)
			if "vehicle" in data.tags and _steps % 2 == 0 and BattleManager.is_battle_running():   # след техники (18.11.2026)
				ScarLayer.blood(feet(), 3.5 * data.sprite_scale, Color(0.02, 0.015, 0.02, 0.35))
			if data.special_kind != "":   # шаг примарха: земля дрожит и трескается
				BossSpecial.step(self)
			elif heavy:   # шаги — звук (AudioManager: предел частоты на событие, сотни бойцов не захлёбывают)
				AudioManager.play("step_heavy")
			elif _steps % DustLayer.INFANTRY_EVERY == 0:
				AudioManager.play("step")
	if _recoil_left > 0.0:
		_tick_recoil(delta)
	if not _has_tick_from or current_state == State.DEAD:
		return
	if _drawn_between and _tick_from == _tick_to and _leap_prev >= 1.0:
		return   # стоит и уже учтён в этом тике — дальше нечего считать (и автолоад не спрашиваем)
	if not BattleManager.is_battle_running():
		return
	if not _drawn_between:
		_tick_to = global_position
		_drawn_between = true
	# Стоит на месте (в сшибке — большинство): узел уже в своей точке. Запись позиции будит пересчёт трансформаций
	# детей и сортировку по глубине у каждого бойца каждый кадр — оптимизация 14.11.2026
	if _tick_from == _tick_to and _leap_prev >= 1.0:
		return
	var alpha := BattleManager.get_tick_alpha()
	global_position = _tick_from.lerp(_tick_to, alpha)
	if _leap_prev < 1.0:   # дуга прыжка: спрайт над тенью
		sprite.position.y = -sin(PI * lerpf(_leap_prev, _leap_t, alpha)) * JUMP_HEIGHT * data.sprite_scale
		if _jump_trail:
			_jump_trail.position.y = sprite.position.y - JUMP_TRAIL_RISE * data.sprite_scale

# Начало тика боя: узел — обратно в логическую позицию, от неё отсчитывается следующий шаг
func restore_tick_position() -> void:
	if _drawn_between:
		if _tick_from != _tick_to:   # стоял — узел и так в логической точке
			global_position = _tick_to
		_drawn_between = false
	_tick_from = global_position
	_has_tick_from = true

# Темп своей скорости — только у бега; остальные анимации — как в листе
# Новая анимация — с обычной скоростью: ускорение атаки (_attack_anim_scale) не переходит на бег и стойку;
# темп бега ставит _move_towards / UnitAbilities.strafe_around сразу после смены (walk_anim_scale)
func _on_animation_changed() -> void:
	sprite.speed_scale = 1.0
	sprite.scale.y = _sprite_k   # шаг (STEP_DIP) — только у бега
	step_lift = 0.0

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
	UnitAbilities.end_leap_view(self)
	_special_left = 0.0
	BossSpecial.clear_telegraph(self)
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
	# Модель чуть «втоплена» в землю (решение пользователя 18.11.2026): спрайт ниже точки ног на GROUND_SINK px мира
	sprite.offset = Vector2(0, -base_h / 2.0 + GROUND_SINK / maxf(k, 0.001))
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
		UnitAbilities.tick_leap(self, delta)
		return
	if _special_left > 0.0:
		BossSpecial.tick(self, delta)
		return
	if data.special_kind != "":
		_special_cd -= delta
		if _special_cd <= TIMER_EPSILON and (current_state == State.ATTACK or current_state == State.CHASE) 				and BossSpecial.try_start(self):
			return
	if current_heal_per_second > 0.0:
		_tick_support(delta)
	if _hit_timer > 0.0:
		_tick_melee_hit(delta)
	if data.jump_range > 0.0 and not jump_used and (current_state == State.MOVE or current_state == State.CHASE):
		if UnitAbilities.try_jump(self):
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
		UnitAbilities.tick_entrench(self, delta)

# -------------------------------------------------------
# СПОСОБНОСТИ ОТРЯДОВ (данными в UnitData; решение пользователя 17.10.2026): действия — UnitAbilities.gd,
# приёмы боссов — BossSpecial.gd; здесь константы, состояние и запросы
# -------------------------------------------------------

func is_leaping() -> bool:
	return _leap_time > 0.0

# -------------------------------------------------------
# ПРИЁМ ФИНАЛЬНОГО БОССА (UnitData.special_*; решение пользователя 09.11.2026 — свой приём у каждого примарха)
# Ряд special листа: замах до metadata/special_frame, на нём — действие, затем доигрывается; всё это время FSM стоит,
# оглушение и отброс не действуют. Рывок и прыжок — ход за время замаха (≤ GRID_SLACK за тик при special_range ≤ 300).
# Сами действия приёма — BossSpecial.gd
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
const CORPSE_HOLD: float = 2.5          # тело бойца лежит на последнем кадре смерти
const CORPSE_FADE: float = 1.5          # … потом темнеет в тон земли и тает
const CORPSE_TINT := Color(0.3, 0.3, 0.34, 0.0)
const MAX_CORPSES: int = 80             # больше — прежнее поведение (пропадают сразу), иначе дорого по отрисовке
static var _corpses: int = 0
const BOSS_CORPSE_HOLD: float = 1.5    # тело примарха лежит на последнем кадре смерти
const BOSS_CORPSE_FADE: float = 2.0    # … потом темнеет и тает
const BOSS_CORPSE_TINT := Color(0.35, 0.36, 0.42, 0.0)   # к тону грунта, прозрачно

func is_using_special() -> bool:
	return _special_left > 0.0

# Босс показан (враги открываются по «В БОЙ»): тень и кольцо под ним (раньше выдали бы его на расстановке)
func reveal_boss() -> void:
	if data.special_kind != "" and not is_instance_valid(_ground):
		_ground = BossFx.ground(self)

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

func is_entrenched() -> bool:
	return data.entrench_time > 0.0 and _still_time >= data.entrench_time - TIMER_EPSILON

# Прибавка урона окапывания: растёт от 0 до entrench_bonus за entrench_time
func get_entrench_bonus() -> float:
	if data.entrench_time <= 0.0:
		return 0.0
	return data.entrench_bonus * clampf(_still_time / data.entrench_time, 0.0, 1.0)

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

	# Враг в поле зрения — поиск по сетке реестра; отряд уже проверил, что врагов рядом нет, — не ищем.
	# Обзор — раз в VISION_EVERY тиков вразнобой по номеру в отряде (профиль 09.11.2026: на первом тике боя все
	# ~300 бойцов искали разом — выброс тика 25 мс); реакция позже не больше чем на (VISION_EVERY − 1) тик
	if _vision_wait < 0:
		_vision_wait = int(attack_stagger * VISION_EVERY) + 1   # половина отряда смотрит в этот тик, половина — в следующий
	_vision_wait -= 1
	if _vision_wait <= 0 and not (parent_squad and parent_squad.enemy_out_of_sight):
		_vision_wait = VISION_EVERY
		var seen := SoldierRegistry.find_nearest(1 - team, global_position, data.vision_range)
		if seen:
			# Ближайший в поле зрения — он же ближайший на всём поле: для цели «ближайший» второй поиск по сетке
			# (без радиуса — шире) не нужен (09.11.2026: на первом тике боя ~280 переходов MOVE → CHASE разом)
			target = seen if data.priority == GameConstants.PRIORITY_NEAREST else _find_target()
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
# Порядок проверок — по цене (зовётся каждым врагом каждый тик): чаще всего у игрока есть бойцы — дальше не идём
func _is_sieging() -> bool:
	return team == GameConstants.TEAM_ENEMY \
		and SoldierRegistry.get_alive_soldiers_of_team(1 - team).is_empty() \
		and BattleManager.citadel_hp > 0.0 and BattleManager.has_citadel()

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
		if _aim_shift(delta):
			return   # встаёт на линию выстрела; перезарядка уже готова — ударит, как встанет
		attack_timer = 1.0 / (current_attack_speed * get_attack_speed_mult())
		if data.cast_time > 0.0:
			transition_to(State.CASTING)   # замах/каст перед ударом
		else:
			_do_attack()
	if data.mobile_fire and current_state == State.ATTACK and _has_valid_target():
		UnitAbilities.strafe_around(self, target.global_position, delta)

# Стрелок встаёт так, чтобы цель была в пределах угла ствола (AIM_TAN); true — ещё идёт на позицию (стрелять рано)
var _aim_shift_time: float = 0.0
func _aim_shift(delta: float) -> bool:
	if data.projectile == "" or data.mobile_fire or data.special_kind != "" or not _has_valid_target():
		return false
	var d: Vector2 = target.global_position - global_position
	if absf(d.x) * AIM_TAN >= absf(d.y):
		_aim_shift_time = 0.0
		return false   # цель в пределах угла ствола
	if _aim_shift_time >= AIM_SHIFT_MAX:
		_aim_shift_time = 0.0
		return false   # не вышло за отведённое время — стреляет как стоит
	var needed: float = absf(d.y) / AIM_TAN
	if sqrt(needed * needed + d.y * d.y) > current_attack_range * 0.97:
		return false   # из этой дальности ровно не встать
	var side: float = signf(d.x) if absf(d.x) > 0.5 else (-1.0 if sprite.flip_h else 1.0)
	var spot := Vector2(target.global_position.x - side * needed * 1.05, global_position.y)
	_aim_shift_time += delta
	var before := global_position
	_move_towards(spot, delta)
	_face(target.global_position - global_position)   # лицом к цели, а не по ходу сдвига
	if global_position.is_equal_approx(before):
		_aim_shift_time = AIM_SHIFT_MAX   # путь закрыт (стена) — не стоять
		return false
	return true

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
	_show_heal_animation(patient != null, patient)
	# луч к раненому (себя лечит — без луча); только вид
	if patient and patient != self and heal_beam == null:
		heal_beam = HealBeam.for_healer(self)
	if heal_beam:
		heal_beam.set_patient(patient)

# Лечение листа (Apothecary: ряд heal, если есть) — пока лечит и стоит (стойка между ударами);
# бег и удар его перебивают, кончил лечить — снова стойка. Только вид
func _show_heal_animation(healing: bool, patient: Soldier = null) -> void:
	if not sprite.sprite_frames.has_animation("heal"):
		return
	if healing and sprite.animation in ["idle", "heal"]:
		_play_animation("heal")
		# Лицом к раненому (решение пользователя 11.11.2026: луч — из нартециума, а не из груди; прибор в руке
		# со стороны взгляда — иначе луч шёл бы назад сквозь тело)
		if is_instance_valid(patient) and patient != self:
			_face(patient.global_position - global_position)
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
	# Бруствер окопавшегося — Vfx "entrench" (UnitAbilities.show_entrench)
	# Статус-эффекты — точки над головой, по точке на стак
	var stacks := 0
	for effect in status_effects:
		stacks += status_effects[effect]["stacks"]
	var dot_x := -stacks * (STATUS_DOT_R * 2.0 + 1.0) / 2.0
	var dot_y := -TARGET_SPRITE_HEIGHT * data.sprite_scale - STATUS_DOT_GAP + GROUND_SINK
	for effect in status_effects:
		for i in status_effects[effect]["stacks"]:
			draw_circle(Vector2(dot_x + STATUS_DOT_R, dot_y), STATUS_DOT_R, StatusEffects.COLORS.get(effect, Color.WHITE))
			dot_x += STATUS_DOT_R * 2.0 + 1.0

# -------------------------------------------------------
# ДВИЖЕНИЕ
# -------------------------------------------------------
func _move_towards(point: Vector2, delta: float) -> void:
	var direction = (point - global_position).normalized()
	var speed = current_move_speed * get_move_speed_mult() * (1.0 + (attack_stagger - 0.5) * PACE_SPREAD)   # замедление (ауры зданий игрока); свой шаг у каждого
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
	if absf(direction.x) > FACE_TURN_DOT:
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
	Vfx.spawn(_world_parent(), "ground_slam", feet(), data.sprite_scale * EFFECT_SCALE)
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
	var shot := _shoot_projectile(target, Vector2(0.0, -TARGET_SPRITE_HEIGHT * 0.45 * target.data.sprite_scale + GROUND_SINK))
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
	var body := victim.global_position + Vector2(0.0, -TARGET_SPRITE_HEIGHT * 0.45 * victim.data.sprite_scale + GROUND_SINK)
	Vfx.spawn_blood(_world_parent(), body, victim.data, false, EFFECT_SCALE)
	Vfx.spawn(_world_parent(), "slash", body, EFFECT_SCALE, (victim.global_position - global_position).angle())
	_hit_debris(victim, body)
	if boss or data.on_hit_knockback > 0.0 or "vehicle" in data.tags:   # тяжёлый удар — волна по земле и пыль (18.11.2026)
		BossFx.shockwave(victim.feet(), 26.0 * data.sprite_scale, Palette.DUST_PALE)
		DustLayer.puff(victim.feet(), 7.0 * data.sprite_scale, 3, 8.0)
	_apply_on_hit_effects()
	if is_instance_valid(prev_target):
		target = prev_target

# Удар вплотную (решение пользователя 18.11.2026): пыль из-под ног жертвы, по броне техники — искры
func _hit_debris(victim: Soldier, body: Vector2) -> void:
	DustLayer.puff(victim.feet(), 5.0 * victim.data.sprite_scale, 1, 4.0)
	if "vehicle" in victim.data.tags:
		Vfx.spawn(_world_parent(), "hit_spark", body, EFFECT_SCALE)

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
	return global_position + muzzle * _sprite_k + Vector2(0.0, GROUND_SINK)   # спрайт втоплен — ствол ниже на столько же

# На сколько спрайт втоплен — эффекты на теле (Vfx.attach) смещаются так же
func body_sink() -> float:
	return GROUND_SINK

# Точка ног с учётом втапливания — эффекты у земли
func feet() -> Vector2:
	return global_position + Vector2(0.0, GROUND_SINK)

# Откуда луч лечения (HealBeam): metadata/heal_origin листа — прибор в руке (Apothecary — нартециум; решение
# пользователя 11.11.2026), от центра низа кадра, как ствол; нет — грудь (HealBeam.CHEST роста)
func heal_point() -> Vector2:
	var frames := sprite.sprite_frames
	if frames == null or not frames.has_meta("heal_origin"):
		return global_position + Vector2(0.0, -TARGET_SPRITE_HEIGHT * HealBeam.CHEST * data.sprite_scale + GROUND_SINK)
	var origin: Vector2 = frames.get_meta("heal_origin")
	if sprite.flip_h:
		origin.x = -origin.x
	return global_position + origin * _sprite_k + Vector2(0.0, GROUND_SINK)

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
				target.global_position + Vector2(0.0, -TARGET_SPRITE_HEIGHT * 0.45 * target.data.sprite_scale + GROUND_SINK),
				EFFECT_SCALE, (target.global_position - global_position).angle())
	if data.on_hit_knockback > 0.0:
		target.apply_knockback(target.global_position - global_position, data.on_hit_knockback)
	apply_blessing_hit(target, bonus_poison_power, charm_chance, parent_squad)

# Яд благословения / Котла и порабощение Король Второго Акта при попадании (удар — здесь, снаряд — Projectile._impact)
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

# Порабощён (благословение Короля Второго Акта): уходит из своего отряда в отряд, который его поработил, и бьётся за него до
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
		if shield <= 0.0:   # щит кончился — лопается (решение пользователя 09.11.2026, только вид)
			BuildingFx.shield_break(self, data.sprite_scale)
	current_hp -= amount
	if flash:
		_flash_hit()
		if amount >= FLOAT_MIN_DAMAGE and BattleManager.is_battle_running():
			var ratio := amount / maxf(max_hp, 1.0)
			var size := 1.0
			if ratio >= FLOAT_HEAVY_RATIO:
				size = FLOAT_HEAVY_SIZE
			elif ratio >= FLOAT_MEDIUM_RATIO:
				size = FLOAT_MEDIUM_SIZE
			_float_text("%d" % roundi(amount),
				FLOAT_HIT_TO_PLAYER if team == GameConstants.TEAM_PLAYER else FLOAT_HIT_TO_ENEMY,
				BOSS_NUMBER_SIZE if big else size)
	if current_hp <= 0.0:
		if _try_revive():
			return
		_die()
		return
	if not enraged and data.special_kind != "" and current_hp <= max_hp * ENRAGE_AT:
		BossSpecial.enrage(self)
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
	return UNIT_SHADER   # один на все: в Compatibility шейдер компилируется при первом показе

# Стилизация шейдером (решение пользователя 12.11.2026): светотень ступенями (bands) у бойцов и зданий, у зданий,
# цитадели и капсулы — ещё палитра расы (pal_ramp). Значения — STYLE_DEFAULT + ключ темы "style"; kind — "unit"
# (бойцы, продавец) или "building" (здания, цитадель, капсула)
const STYLE_DEFAULT := {
	# 16.11.2026 (решение пользователя: «шейдеры слишком видны»): светотень ступенями, палитра расы и направленный свет слабее
	# (было: unit_band_mix 0.4, building_band_mix 0.3, building_pal_mix 0.35, unit_dir 0.5 / 0.3, building_dir 0.45 / 0.35)
	"unit_bands": 5.0, "unit_band_mix": 0.2,
	"building_bands": 5.0, "building_band_mix": 0.16, "building_pal_mix": 0.18, "pal_range": 1.6,
	"building_sat": 0.9, "building_glow_keep": 1.0,   # краска зданий чуть глуше, свечение — нет (12.11.2026)
	# Здания отделяются от грунта (решение пользователя 12.11.2026, `Screenshot 2026-11-12 143816.png`: «слишком
	# сливаются с текстурами»): свет сверху по верхним кромкам силуэта (vol_light, тёплый vol_color) и ярче в целом
	"building_light": 0.55, "building_light_color": Color(1.0, 0.86, 0.66), "building_gain": 1.12,
	# Направленный свет (WorldLight, 12.11.2026): кромки к свету светлее, теневая сторона темнее
	"unit_dir_light": 0.3, "unit_dir_shade": 0.18, "building_dir_light": 0.3, "building_dir_shade": 0.22,
	"palette": [Color("07090e"), Color("141b26"), Color("2a3442"), Color("4b5566"), Color("7d8696"), Color("c9b48a")],
}
static var _ramps: Dictionary = {}   # раса → GradientTexture1D палитры
static func apply_style(m: ShaderMaterial, kind: String) -> void:
	var st: Dictionary = STYLE_DEFAULT.merged(FactionTheme.current().get("style", {}), true)
	m.set_shader_parameter("bands", float(st.get(kind + "_bands", 0.0)))
	m.set_shader_parameter("band_mix", float(st.get(kind + "_band_mix", 0.0)))
	m.set_shader_parameter("style_sat", float(st.get(kind + "_sat", 1.0)))
	m.set_shader_parameter("glow_keep", float(st.get(kind + "_glow_keep", 0.0)))
	if st.has(kind + "_light"):
		var lc: Color = st.get(kind + "_light_color", Color.WHITE)
		m.set_shader_parameter("vol_light", float(st[kind + "_light"]))
		m.set_shader_parameter("vol_color", Vector3(lc.r, lc.g, lc.b))
	if st.has(kind + "_gain"):
		var g := float(st[kind + "_gain"])
		m.set_shader_parameter("env_tint", Vector3(g, g, g))
	var tl: Vector2 = WorldLight.param("to_light")
	var lc2: Color = WorldLight.param("color")
	m.set_shader_parameter("to_light", tl)
	m.set_shader_parameter("dir_light", float(st.get(kind + "_dir_light", 0.0)))
	m.set_shader_parameter("dir_shade", float(st.get(kind + "_dir_shade", 0.0)))
	m.set_shader_parameter("dir_color", Vector3(lc2.r, lc2.g, lc2.b))
	var pal_mix: float = st.get(kind + "_pal_mix", 0.0)
	m.set_shader_parameter("pal_mix", pal_mix)
	if pal_mix <= 0.0:
		return
	var race: String = RunManager.player_faction
	if not _ramps.has(race):
		var g := Gradient.new()
		var cols: Array = st["palette"]
		g.offsets = PackedFloat32Array(range(cols.size()).map(func(i): return float(i) / (cols.size() - 1)))
		g.colors = PackedColorArray(cols)
		var t := GradientTexture1D.new()
		t.gradient = g
		t.width = 64
		_ramps[race] = t
	m.set_shader_parameter("pal_ramp", _ramps[race])
	m.set_shader_parameter("pal_range", float(st["pal_range"]))

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
	var key := "%s|%d|%d|%s|%d|%s|%d|%s" % [_armor_chapter, _rim_px, _outline_px, flashing, _pix, RunManager.player_faction,
		_status_mask, data.armor_protect if _armor_chapter != "" else ""]
	if not _unit_materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = UNIT_SHADER
		if _armor_chapter != "":
			var armor: Dictionary = Chapters.get_chapter(_armor_chapter).get("armor", {})
			m.set_shader_parameter("armor", 1.0)
			if data.armor_protect.has_area() and sprite.sprite_frames.has_animation("idle"):
				var canvas: Vector2 = sprite.sprite_frames.get_frame_texture("idle", 0).get_size()
				var r: Rect2 = data.armor_protect
				m.set_shader_parameter("protect", Vector4(r.position.x / canvas.x, r.position.y / canvas.y, r.size.x / canvas.x, r.size.y / canvas.y))
			m.set_shader_parameter("target_hue", armor.get("hue", 0.6))
			m.set_shader_parameter("sat_mult", armor.get("sat", 1.0))
			m.set_shader_parameter("val_mult", armor.get("val", 1.0))
			if armor.has("body"):
				var body: Dictionary = armor["body"]
				m.set_shader_parameter("body_mix", 1.0)
				m.set_shader_parameter("body_hsv", Vector3(body.get("hue", 0.0), body.get("sat", 0.0), body.get("val", 1.0)))
				m.set_shader_parameter("body_cap", float(body.get("cap", 1.0)))
			if armor.has("trim"):
				var trim: Dictionary = armor["trim"]
				m.set_shader_parameter("trim_mix", 1.0)
				m.set_shader_parameter("trim_hsv", Vector3(trim.get("hue", 0.12), trim.get("sat", 1.0), trim.get("val", 1.0)))
		if _rim_px > 0:
			var col: Color = _rim.get("color", Color.WHITE)
			m.set_shader_parameter("rim_px", float(_rim_px))
			m.set_shader_parameter("rim_color", Vector3(col.r, col.g, col.b))
			m.set_shader_parameter("rim_strength", _rim.get("strength", 0.5))
		m.set_shader_parameter("outline_px", float(_outline_px))
		m.set_shader_parameter("outline_color", Palette.OUTLINE)
		m.set_shader_parameter("flash", HIT_FLASH_STRENGTH if flashing else 0.0)
		m.set_shader_parameter("pix", float(_pix))
		m.set_shader_parameter("sharpen", UNIT_SHARPEN)
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
		apply_style(m, "unit")
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
	UnitAbilities.end_leap_view(self)
	_special_left = 0.0
	BossSpecial.clear_telegraph(self)
	transition_to(State.DEAD)
	if data.special_kind != "" and _flash_left > 0.0:   # вспышка смертельного удара в замедлении ×0.25 белила
		_flash_left = 0.0                              # примарха 0.4 с — текстура видна сразу
		sprite.material = _base_material
	if data.special_kind != "" and is_inside_tree():   # примарх пал — кинематографичный миг (BattleScene.boss_fall)
		var scene := get_tree().current_scene
		if scene and scene.has_method("boss_fall"):
			scene.boss_fall(self)
	AudioManager.play("death_vehicle" if "vehicle" in data.tags else "death")
	if team == GameConstants.TEAM_ENEMY and "elite" in data.tags and BattleManager.is_battle_running() \
			and is_inside_tree():   # элита пала — монеты к счётчику (BattleScene.elite_killed)
		var scene := get_tree().current_scene
		if scene and scene.has_method("elite_killed"):
			scene.elite_killed(global_position)
	if BattleManager.is_battle_running():   # шрам поля: техника — подпалина, остальные — пятно крови
		if "vehicle" in data.tags:
			ScarLayer.scorch(global_position, SCAR_RADIUS * 2.5 * data.sprite_scale)
		else:
			ScarLayer.blood(global_position, SCAR_RADIUS * data.sprite_scale,
				Vfx.BLOOD_COLORS.get(data.get_blood(), Vfx.BLOOD_COLORS["red"]))
	if "vehicle" in data.tags:   # техника взрывается: огонь, обломки, чёрный дым
		Vfx.spawn(_world_parent(), "vehicle_explode", feet(), data.sprite_scale * EFFECT_SCALE)
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
		elif effect == StatusEffects.SLOWED:
			AudioManager.play("slow")
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
				if effect == StatusEffects.BURNING:   # горящий боец тускло подсвечивает землю (только вид)
					IsoGridRenderer.ember_light(global_position, Color(Palette.FIRE, 0.4),
						EMBER_LIGHT_RADIUS * data.sprite_scale, StatusEffects.DOT_TICK * 1.2)
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
		if status_effects.has(STATUS_BODY[i][0]) or (enraged and current_state != State.DEAD 				and STATUS_BODY[i][0] == StatusEffects.EMPOWERED):
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
	FloatingText.spawn(_world_parent(), global_position + Vector2(0.0, -TARGET_SPRITE_HEIGHT * data.sprite_scale - 6.0 + GROUND_SINK),
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
				Vfx.spawn(_world_parent(), "retreat_dust", feet(), data.sprite_scale * EFFECT_SCALE)
		State.ATTACK:
			# Первый удар — со сдвигом бойца (отряд бьёт вразнобой); до него — стойка
			attack_timer = attack_stagger * ATTACK_STAGGER / maxf(current_attack_speed * get_attack_speed_mult(), 0.01)
			sprite.stop()
			if UnitAbilities.try_battle_cry(self) and sprite.sprite_frames.has_animation("battle_cry"):
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
			UnitAbilities.show_entrench(self, false)
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
	if _corpses >= MAX_CORPSES:
		var timer = get_tree().create_timer(0.3, false)   # на паузе не тикает
		timer.timeout.connect(queue_free)
		return
	# Тело лежит и тает (решение пользователя 18.11.2026): после схватки поле читается как побоище; пачка тел ограничена
	_corpses += 1
	tree_exiting.connect(func(): _corpses = maxi(_corpses - 1, 0))
	var tw := create_tween()
	tw.tween_interval(CORPSE_HOLD)
	tw.tween_property(sprite, "modulate", CORPSE_TINT, CORPSE_FADE).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(queue_free)

# Тело примарха (решение пользователя 09.11.2026: «умирают инородно» — через 0.3 с после последнего кадра
# пропадало рывком): последний кадр лежит BOSS_CORPSE_HOLD, потом темнеет в тон земли и тает за BOSS_CORPSE_FADE
func _fade_boss_corpse() -> void:
	var tw := create_tween()
	tw.tween_interval(BOSS_CORPSE_HOLD)
	tw.tween_property(sprite, "modulate", BOSS_CORPSE_TINT, BOSS_CORPSE_FADE).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(queue_free)
