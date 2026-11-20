extends Node

# Звук (решение пользователя 16.10.2026: система готова к ассетам — файлы кладутся в папку и играют).
# Событие → файл AUDIO_DIR/<событие>.ogg|.wav|.mp3 или варианты <событие>_1, _2, … (случайный);
# файла нет — событие молча пропускается. Звуки — пакет пользователя 09.11.2026 (исходник
# assets/sounds_for_gWHKINGS → копии по событиям в assets/audio: выстрелы, мечи, смерть, боль, шаги, карты, меню,
# музыка menu / shop / battle; у части событий файлов пока нет — молчат).
# Частые звуки (выстрелы сотен бойцов) ограничены: не чаще max_per_sec в секунду на событие и не больше
# MAX_VOICES одновременно. Шины SFX и Music создаются, если их нет; общая громкость — Master (GameSettings).
# Музыка: play_music(трек) — цикл, смена трека — плавно за MUSIC_FADE.

const AUDIO_DIR: String = "res://assets/audio/"
const MUSIC_DIR: String = "res://assets/audio/music/"
const EXTENSIONS = ["ogg", "wav", "mp3"]
const MAX_VARIANTS: int = 8
const MAX_VOICES: int = 24
const MUSIC_FADE: float = 1.2
# Трек не найден — играет запасной (своей музыки боя с боссом нет — боевая, 09.11.2026)
const MUSIC_FALLBACK = {"boss": "battle"}
# Вариант звука и высота — своя случайность: общий randf — случайность боя (урон, цели); звук на каждый
# выстрел сдвигал бы её (ревью 09.11.2026)
var _rng := RandomNumberGenerator.new()
const SFX_BUS: String = "SFX"
const MUSIC_BUS: String = "Music"
const UI_BUS: String = "UI"   # звуки интерфейса — своя громкость в настройках (EVENTS: "ui": true)
const HISTORY_SIZE: int = 64

# volume — дБ, max_per_sec — предел частоты (0 — без предела), pitch — разброс высоты ±
const EVENTS = {
	# Выстрелы (Projectile: по виду снаряда, когда снаряд вылетел)
	"shot_bolt":    {"volume": -12.0, "max_per_sec": 14, "pitch": 0.08},
	"shot_charged": {"volume": -8.0,  "max_per_sec": 8,  "pitch": 0.06},
	"shot_spark":   {"volume": -10.0, "max_per_sec": 8,  "pitch": 0.08},
	"shot_flame":   {"volume": -10.0, "max_per_sec": 6,  "pitch": 0.05},
	"shot_rocket":  {"volume": -4.0,  "max_per_sec": 4,  "pitch": 0.03},
	"explosion":    {"volume": -4.0,  "max_per_sec": 6,  "pitch": 0.05},
	# Попадания и гибель
	"hit":          {"volume": -18.0, "max_per_sec": 4,  "pitch": 0.12},   # крик боли — реже выстрелов, иначе хор
	"melee_hit":    {"volume": -10.0, "max_per_sec": 12, "pitch": 0.1},
	"death":        {"volume": -12.0, "max_per_sec": 8,  "pitch": 0.1},
	"death_vehicle": {"volume": -6.0, "max_per_sec": 4,  "pitch": 0.05},
	"citadel_hit":  {"volume": -8.0,  "max_per_sec": 4,  "pitch": 0.05},
	"citadel_shot": {"volume": -6.0,  "max_per_sec": 4,  "pitch": 0.04},
	# Статусы и способности
	"burning":      {"volume": -14.0, "max_per_sec": 4,  "pitch": 0.1},
	"poison":       {"volume": -14.0, "max_per_sec": 4,  "pitch": 0.1},
	"battle_cry":   {"volume": -6.0,  "max_per_sec": 2,  "pitch": 0.03},
	"jump_land":    {"volume": -8.0,  "max_per_sec": 6,  "pitch": 0.08},   # приземление Assault
	# Шаги (Soldier._process, нога встала): пехота — каждым INFANTRY_EVERY-м шагом, техника — каждым, примарх — с тряской
	"step":         {"volume": -22.0, "max_per_sec": 6,  "pitch": 0.15},
	"step_heavy":   {"volume": -14.0, "max_per_sec": 4,  "pitch": 0.08},
	"boss_step":    {"volume": -8.0,  "max_per_sec": 4,  "pitch": 0.05},
	"launch":       {"volume": -6.0,  "max_per_sec": 1,  "pitch": 0.0},    # взлёт из меню в забег (MenuLaunch)
	"landing":      {"volume": -6.0,  "max_per_sec": 1,  "pitch": 0.0},    # посадка на первое поле (BattleLanding)
	"deep_strike":  {"volume": -4.0,  "max_per_sec": 2,  "pitch": 0.03},   # телепорт Терминаторов
	"pod_fall":     {"volume": -6.0,  "max_per_sec": 3,  "pitch": 0.05},   # десантная капсула падает (DropPod)
	"pod_impact":   {"volume": -4.0,  "max_per_sec": 3,  "pitch": 0.06},   # капсула ударила о землю
	"pod_open":     {"volume": -8.0,  "max_per_sec": 3,  "pitch": 0.05},   # двери упали, пар
	"revive":       {"volume": -8.0,  "max_per_sec": 3,  "pitch": 0.05},
	"orbital_strike": {"volume": -2.0, "max_per_sec": 2, "pitch": 0.0},
	"boss_special": {"volume": -2.0,  "max_per_sec": 2,  "pitch": 0.03},   # приём финального босса (Soldier._special_view)
	"boss_appear":  {"volume": -2.0,  "max_per_sec": 1,  "pitch": 0.0},    # босс выходит на поле (Soldier.play_appear)
	# Интерфейс
	"ui_click":     {"volume": -10.0, "max_per_sec": 20, "pitch": 0.0, "ui": true},
	"buy":          {"volume": -6.0,  "max_per_sec": 8,  "pitch": 0.0, "ui": true},
	"sell":         {"volume": -6.0,  "max_per_sec": 8,  "pitch": 0.0, "ui": true},
	"no_money":     {"volume": -6.0,  "max_per_sec": 4,  "pitch": 0.0, "ui": true},
	"reroll":       {"volume": -6.0,  "max_per_sec": 6,  "pitch": 0.0, "ui": true},
	"place":        {"volume": -8.0,  "max_per_sec": 8,  "pitch": 0.05},
	"tile_bought":  {"volume": -6.0,  "max_per_sec": 4,  "pitch": 0.0},
	"building_level_up": {"volume": -6.0, "max_per_sec": 4, "pitch": 0.0},
	"wall_hit":     {"volume": -10.0, "max_per_sec": 6,  "pitch": 0.08},   # удар по стене владений (KingdomWall)
	"wall_break":   {"volume": -4.0,  "max_per_sec": 3,  "pitch": 0.05},   # звено стены разбито
	"pause":        {"volume": -8.0,  "max_per_sec": 4,  "pitch": 0.0, "ui": true},
	# Итоги и переходы
	"battle_start": {"volume": -4.0,  "max_per_sec": 1,  "pitch": 0.0},
	"victory":      {"volume": -2.0,  "max_per_sec": 1,  "pitch": 0.0},
	"defeat":       {"volume": -2.0,  "max_per_sec": 1,  "pitch": 0.0},
	"run_won":      {"volume": 0.0,   "max_per_sec": 1,  "pitch": 0.0},
	"run_lost":     {"volume": 0.0,   "max_per_sec": 1,  "pitch": 0.0},
	"expansion":    {"volume": -4.0,  "max_per_sec": 1,  "pitch": 0.0},
}

var record_history: bool = false  # тесты / отладка: писать события в history (в игре — нет, лишние строки на выстрел)
var history: Array[String] = []   # последние запрошенные события: «имя» или «имя (нет файла)»
var _streams: Dictionary = {}     # событие → Array[AudioStream] (пусто — файла нет)
var _last_play: Dictionary = {}   # событие → [время окна, сыграно в окне]
var _voices: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer = null
var _music_track: String = ""
var _music_tween: Tween = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # интерфейс и музыка звучат и на паузе
	_ensure_bus(SFX_BUS)
	_ensure_bus(UI_BUS)
	_ensure_bus(MUSIC_BUS)
	for i in MAX_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = SFX_BUS
		add_child(p)
		_voices.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = MUSIC_BUS
	add_child(_music)
	# Щелчок — у ЛЮБОЙ кнопки, что появляется в дереве (09.11.2026, «у некоторых кнопок нет звука»: раньше — только
	# у собранных UITheme.make_button; кнопки из .tscn и Button.new() молчали). Кнопка со своим звуком (купить,
	# продать, обновить) — meta NO_CLICK
	get_tree().node_added.connect(_on_node_added)

const NO_CLICK := "no_click"

func _on_node_added(node: Node) -> void:
	# button_down — в миг нажатия (09.11.2026, «звук отстаёт от действия»): pressed приходит на отпускании и
	# после обработчика самой кнопки (окно, смена сцены), щелчок звучал с задержкой
	if node is BaseButton:
		var cb := _on_button_pressed.bind(node)
		if not node.button_down.is_connected(cb):   # кнопку переподвесили — node_added второй раз
			node.button_down.connect(cb)

func _on_button_pressed(button: BaseButton) -> void:
	if is_instance_valid(button) and not button.get_meta(NO_CLICK, false):
		play("ui_click")

func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, bus_name)
	AudioServer.set_bus_send(i, "Master")

# Сыграть событие. true — звук пошёл; false — файла нет, предел частоты или все голоса заняты
func play(event: String) -> bool:
	var streams := _get_streams(event)
	if streams.is_empty():
		if record_history:
			_log(event + " (нет файла)")
		return false
	var cfg: Dictionary = EVENTS.get(event, {})
	if not _rate_ok(event, cfg.get("max_per_sec", 0)):
		return false
	var voice := _free_voice()
	if voice == null:
		return false
	voice.stream = streams[_rng.randi() % streams.size()]
	voice.bus = UI_BUS if cfg.get("ui", false) else SFX_BUS
	voice.volume_db = cfg.get("volume", 0.0)
	var jitter: float = cfg.get("pitch", 0.0)
	voice.pitch_scale = 1.0 + _rng.randf_range(-jitter, jitter)
	voice.play()
	if record_history:
		_log(event)
	return true

# Музыка: трек MUSIC_DIR/<трек>.ogg|… по кругу; тот же — ничего; "" или нет файла — тишина (плавно)
func play_music(track: String) -> void:
	if track == _music_track:
		return
	_music_track = track
	var stream: AudioStream = _find_music(track)
	if stream == null and MUSIC_FALLBACK.has(track):
		stream = _find_music(MUSIC_FALLBACK[track])
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()   # быстрая смена сцены — прошлый переход не спорит с новым
	var tw := create_tween().set_ignore_time_scale(true)   # по реальному времени, ×2 боя ни при чём
	_music_tween = tw
	if _music.playing:
		tw.tween_property(_music, "volume_db", -40.0, MUSIC_FADE / 2.0)
	tw.tween_callback(func():
		_music.stop()
		if stream:
			if stream is AudioStreamWAV:
				stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
				stream.loop_end = int(stream.get_length() * stream.mix_rate)
			elif "loop" in stream:
				stream.loop = true
			_music.stream = stream
			_music.volume_db = -40.0
			_music.play())
	if stream:
		tw.tween_property(_music, "volume_db", 0.0, MUSIC_FADE / 2.0)

func _find_music(track: String) -> AudioStream:
	if track == "":
		return null
	for ext in EXTENSIONS:
		var path := "%s%s.%s" % [MUSIC_DIR, track, ext]
		if ResourceLoader.exists(path):
			return load(path)
	return null

func current_music() -> String:
	return _music_track

# Звук для теста / подмены без файлов: событие → свой поток (пустой массив — снова искать файл)
func set_streams(event: String, streams: Array) -> void:
	_streams[event] = streams

# Файлы всех событий — заранее (BattleScene._ready): поиск файла — до 27 проверок диска, первое
# событие каждого вида посреди схватки давало выброс тика (test_performance)
func warm_cache() -> void:
	for event in EVENTS:
		_get_streams(event)

func _get_streams(event: String) -> Array:
	if not _streams.has(event):
		var found: Array = []
		var names: Array[String] = [event]
		for i in range(1, MAX_VARIANTS + 1):
			names.append("%s_%d" % [event, i])
		for n in names:
			for ext in EXTENSIONS:
				var path := "%s%s.%s" % [AUDIO_DIR, n, ext]
				if ResourceLoader.exists(path):
					found.append(load(path))
					break
		_streams[event] = found
	return _streams[event]

func _rate_ok(event: String, per_sec: int) -> bool:
	if per_sec <= 0:
		return true
	var now := Time.get_ticks_msec() / 1000.0
	var w: Array = _last_play.get(event, [now, 0])
	if now - w[0] >= 1.0:
		w = [now, 0]
	if w[1] >= per_sec:
		_last_play[event] = w
		return false
	w[1] += 1
	_last_play[event] = w
	return true

func _free_voice() -> AudioStreamPlayer:
	for v in _voices:
		if not v.playing:
			return v
	return null

func _log(entry: String) -> void:
	history.append(entry)
	if history.size() > HISTORY_SIZE:
		history.pop_front()
