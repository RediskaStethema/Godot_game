extends Node

# Настройки игрока (не забега): скорость боя, полноэкранный режим, громкость.
# Хранятся в user://settings.cfg, применяются при запуске и при каждом изменении.
# Новая настройка: поле + строка в _save / _load + применение в apply().

const CONFIG_PATH: String = "user://settings.cfg"
const BATTLE_SPEEDS: Array[float] = [1.0, 2.0]

signal changed

# Тесты подменяют путь, чтобы не трогать настройки игрока
var config_path: String = CONFIG_PATH
var battle_speed: float = 1.0      # множитель скорости боя (Engine.time_scale в бою)
var fullscreen: bool = false
var master_volume: float = 1.0     # 0..1, шина Master

func _ready() -> void:
	_load()
	apply()

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

func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_commit()

func apply() -> void:
	var mode = DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.get_name() != "headless" and DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
	var bus = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(bus, master_volume <= 0.0)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(master_volume, 0.0001)))

func _commit() -> void:
	apply()
	_save()
	emit_signal("changed")

func _save() -> void:
	var cfg = ConfigFile.new()
	cfg.set_value("battle", "speed", battle_speed)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.save(config_path)

func _load() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(config_path) != OK:
		return
	battle_speed = float(cfg.get_value("battle", "speed", 1.0))
	if not BATTLE_SPEEDS.has(battle_speed):
		battle_speed = 1.0
	fullscreen = bool(cfg.get_value("video", "fullscreen", false))
	master_volume = clampf(float(cfg.get_value("audio", "master_volume", 1.0)), 0.0, 1.0)
