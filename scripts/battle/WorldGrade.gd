class_name WorldGrade
extends CanvasLayer

# Цветокоррекция поля боя (решение пользователя 18.10.2026 — гримдарк по концепту меню): полноэкранный
# проход поверх мира и под интерфейсом — приглушённая насыщенность, тени в холодный тон, света в тёплый,
# мягкий контраст и виньетка. Параметры — по расе игрока (FactionTheme "grade"), без ключа — DEFAULT.
# Только вид; выключается настройкой GameSettings.atmosphere.
#   layer = 1 и место в дереве перед UI (BattleScene._build_ui): UI того же слоя рисуется позже — не тонируется

# Поле и так тёмное: коррекция не топит его, а поднимает средние тона (gamma < 1), тонирует тени
# сложением (холодный воздух), гасит лишнюю насыщенность ярких бойцов и греет света
const DEFAULT = {
	"saturation": 0.78,                        # 1 — как есть
	"exposure": 1.1,
	"gamma": 0.88,                             # < 1 — светлее средние тона
	"shadow_tone": Color(0.006, 0.014, 0.032), # прибавка в тенях — сине-сталь
	"highlights": Color(1.06, 1.0, 0.88),      # множитель в светах — янтарь
	"vignette": 0.6,                           # сила затемнения краёв (12.11.2026: 0.5 → 0.6, взгляд к центру боя)
	"vignette_color": Color(0.01, 0.015, 0.03),
	# Свечение ярких (решение пользователя 08.11.2026, bloom одним проходом): яркие пиксели (огонь, плазма, варп,
	# вспышки — ярче bloom_threshold по сильнейшему каналу) светят ореолом радиусом bloom_radius px экрана
	"bloom": 0.6,
	"bloom_threshold": 0.6,
	"bloom_radius": 4.0,
	# Свет со стороны источника (WorldLight, 12.11.2026): экран вверху слева светлее, в тон света (key_color — из
	# WorldLight "color", если тема не задала свой), к key_radius (доли экрана) — как было
	"key": 0.22,
	"key_pos": Vector2(0.05, -0.1),
	"key_radius": 1.15,
	# Общая палитра (решение пользователя 12.11.2026): ступеней на канал после всей коррекции, границы — дизерингом
	# Байера в клетке post_dither_px пикселей экрана; 0 — выключено
	"post_levels": 0.0,   # 16.11.2026 (решение пользователя: «шейдеры слишком видны» — сетка дизеринга Байера на всём поле): выключено, было 20
	"post_dither_px": 2.0,
}

# Шейдер — файл shaders/world_grade.gdshader (12.11.2026: вынесен из строки, общий код дизеринга — include)
const SHADER := preload("res://shaders/world_grade.gdshader")


# Накал забега (решение пользователя 17.11.2026: «частицы и цветокор по расам и волнам»): 0 на волне 1 → 1 на волне 15,
# бой с боссом — ещё +MOOD_BOSS. Раса задаёт тон (FactionTheme "grade" / "atmosphere"), накал — насколько он сгущён:
# цвет глуше и темнее, виньетка плотнее, в воздухе больше частиц (Atmosphere.setup). Только вид.
const MOOD_BOSS: float = 0.35
const MOOD_SATURATION: float = 0.10   # на накал 1: насыщенность −, экспозиция −, виньетка +
const MOOD_EXPOSURE: float = 0.05
const MOOD_VIGNETTE: float = 0.14

static func mood() -> float:
	var wave: int = RunManager.get_battle_wave()
	var t := clampf(float(wave - 1) / float(RunMapData.TOTAL_WAVES - 1), 0.0, 1.0)
	if RunManager.get_battle_type() in [RunMapNode.MINIBOSS, RunMapNode.BOSS]:
		t += MOOD_BOSS
	return t

var _rect: ColorRect
static var _active: WorldGrade = null
var _mat: ShaderMaterial = null
var _pulse: float = 0.0           # импульс аберрации, спадает за PULSE_TIME
var _film_time: float = 0.0
var _relief: float = 0.0
const PULSE_TIME: float = 0.35
const PULSE_GAP_MS: int = 120     # не чаще — осада не мигает без конца
var _last_pulse_ms: int = -1000

# Импульс хроматической аберрации (0..1): тяжёлые удары — приём босса, падение босса, прорыв стены, цитадель
static func pulse(strength: float) -> void:
	if _active == null or not is_instance_valid(_active) or not GameSettings.atmosphere:
		return
	var now := Time.get_ticks_msec()
	if now - _active._last_pulse_ms < PULSE_GAP_MS:
		return
	_active._last_pulse_ms = now
	_active._pulse = maxf(_active._pulse, clampf(strength, 0.0, 1.0))

# Облегчение после победы: поле светлеет и теплеет на миг (по реальному времени)
static func relieve() -> void:
	if _active == null or not is_instance_valid(_active) or not GameSettings.atmosphere:
		return
	var tw := _active.create_tween().set_ignore_time_scale(true)
	tw.tween_property(_active, "_relief", 1.0, 1.2).set_trans(Tween.TRANS_SINE)

func _process(delta: float) -> void:
	if _mat == null:
		return
	_film_time += delta
	_pulse = move_toward(_pulse, 0.0, delta / PULSE_TIME)
	_mat.set_shader_parameter("film_time", _film_time)
	_mat.set_shader_parameter("ca_pulse", _pulse * _pulse)
	_mat.set_shader_parameter("relief", _relief)

func _exit_tree() -> void:
	if _active == self:
		_active = null

func _ready() -> void:
	layer = 1
	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = SHADER
	var grade: Dictionary = DEFAULT.merged(FactionTheme.grade(), true)
	var mood := mood()
	grade["saturation"] = float(grade["saturation"]) - MOOD_SATURATION * mood
	grade["exposure"] = float(grade["exposure"]) - MOOD_EXPOSURE * mood
	grade["vignette"] = float(grade["vignette"]) + MOOD_VIGNETTE * mood
	if not grade.has("key_color"):
		grade["key_color"] = WorldLight.param("color")
	for key in grade:
		var value = grade[key]
		m.set_shader_parameter(key, Vector3(value.r, value.g, value.b) if value is Color else value)
	_rect.material = m
	_mat = m
	_active = self
	m.set_shader_parameter("mood_amount", clampf(mood * 0.7, 0.0, 1.0))
	add_child(_rect)
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = GameSettings.atmosphere
	GameSettings.changed.connect(_on_settings_changed)   # метод, не лямбда: связь снимется вместе с узлом

func _on_settings_changed() -> void:
	visible = GameSettings.atmosphere
