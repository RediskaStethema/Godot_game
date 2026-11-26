extends Node

# Настройки игрока (не забега): скорость боя, полноэкранный режим, громкость (общая, сражение, интерфейс, музыка).
# Хранятся в user://settings.cfg, применяются при запуске и при каждом изменении.
# Новая настройка: поле + строка в _save / _load + применение в apply().

const CONFIG_PATH: String = "user://settings.cfg"
const BATTLE_SPEEDS: Array[float] = [1.0, 2.0, 3.0]   # ×3 — решение пользователя 16.10.2026

signal changed

# Тесты подменяют путь, чтобы не трогать настройки игрока
var config_path: String = CONFIG_PATH
var battle_speed: float = 1.0      # множитель скорости боя (Engine.time_scale в бою)
var fullscreen: bool = false
var master_volume: float = 1.0     # 0..1, шина Master
# Громкость по видам звука (решение пользователя 09.11.2026): сражение / интерфейс / музыка — свои шины под Master
var battle_volume: float = 1.0     # шина SFX — бой и поле
var ui_volume: float = 1.0         # шина UI — кнопки, магазин, пауза
var music_volume: float = 1.0      # шина Music
const VOLUME_BUSES = {"master_volume": "Master", "battle_volume": "SFX", "ui_volume": "UI", "music_volume": "Music"}
var atmosphere: bool = true        # цветокоррекция, частицы и свет на поле боя (WorldGrade, Atmosphere)
var names_language: String = "ru"  # язык названий карт, отрядов, зданий (Names.of; решение пользователя 17.11.2026): "ru" / "en"

# Обучение Козла (решение пользователя 23.11.2026): включено, пока не пройдено или пока игрок не выключил;
# tutorial_seen — id уже показанных шагов (Tutorial.STEPS), включение заново их стирает
var tutorial_enabled: bool = true
var tutorial_seen: Array[String] = []
var tutorial_stage: int = 0   # сценарий волн 1–2 (Tutorial.Stage): сохраняется, чтобы «Продолжить» не начинал заново

func set_tutorial_stage(stage: int) -> void:
	tutorial_stage = stage
	_save()

func _ready() -> void:
	_load()
	apply()

func set_tutorial_enabled(value: bool) -> void:
	tutorial_enabled = value
	if value:
		tutorial_seen.clear()   # включили снова — обучение с начала
		tutorial_stage = 0
	_commit()

func mark_tutorial_seen(step_id: String) -> void:
	if not tutorial_seen.has(step_id):
		tutorial_seen.append(step_id)
		_save()

# Следующая скорость боя по кругу (кнопка в шапке боя)
func cycle_battle_speed() -> void:
	var i = BATTLE_SPEEDS.find(battle_speed)
	set_battle_speed(BATTLE_SPEEDS[(i + 1) % BATTLE_SPEEDS.size()])

func set_battle_speed(value: float) -> void:
	battle_speed = value
	_commit()

func set_fullscreen(value: bool) -> void:
	fullscreen = value
	_commit()

func set_names_language(value: String) -> void:
	names_language = value if Names.LANGUAGES.has(value) else "ru"
	_commit()

func set_atmosphere(value: bool) -> void:
	atmosphere = value
	_commit()

func set_master_volume(value: float) -> void:
	set_volume("master_volume", value)

# Громкость одного вида: ключ из VOLUME_BUSES, значение 0..1
func set_volume(key: String, value: float) -> void:
	if not VOLUME_BUSES.has(key):
		return
	set(key, clampf(value, 0.0, 1.0))
	_commit()

# Шина по имени; нет — создаётся (автолоад настроек грузится раньше AudioManager)
static func ensure_bus(bus_name: String) -> int:
	var i := AudioServer.get_bus_index(bus_name)
	if i >= 0:
		return i
	AudioServer.add_bus()
	i = AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, bus_name)
	AudioServer.set_bus_send(i, "Master")
	return i

func apply() -> void:
	var mode = DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.get_name() != "headless" and DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
	for key in VOLUME_BUSES:
		var vol: float = get(key)
		var bus := ensure_bus(VOLUME_BUSES[key])
		AudioServer.set_bus_mute(bus, vol <= 0.0)
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(vol, 0.0001)))

func _commit() -> void:
	apply()
	_save()
	emit_signal("changed")

func _save() -> void:
	var cfg = ConfigFile.new()
	cfg.set_value("battle", "speed", battle_speed)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "atmosphere", atmosphere)
	cfg.set_value("interface", "names_language", names_language)
	cfg.set_value("tutorial", "enabled", tutorial_enabled)
	cfg.set_value("tutorial", "seen", tutorial_seen)
	cfg.set_value("tutorial", "stage", tutorial_stage)
	for key in VOLUME_BUSES:
		cfg.set_value("audio", key, get(key))
	cfg.save(config_path)

func _load() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(config_path) != OK:
		return
	battle_speed = float(cfg.get_value("battle", "speed", 1.0))
	if not BATTLE_SPEEDS.has(battle_speed):
		battle_speed = 1.0
	fullscreen = bool(cfg.get_value("video", "fullscreen", false))
	atmosphere = bool(cfg.get_value("video", "atmosphere", true))
	names_language = str(cfg.get_value("interface", "names_language", names_language))
	if not Names.LANGUAGES.has(names_language):
		names_language = "ru"
	tutorial_enabled = bool(cfg.get_value("tutorial", "enabled", true))
	tutorial_stage = int(cfg.get_value("tutorial", "stage", 0))
	tutorial_seen.clear()
	for s in cfg.get_value("tutorial", "seen", []):
		tutorial_seen.append(str(s))
	for key in VOLUME_BUSES:
		set(key, clampf(float(cfg.get_value("audio", key, 1.0)), 0.0, 1.0))
