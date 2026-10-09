class_name PauseMenu
extends CanvasLayer

# Пауза по Esc (ui_cancel) в магазине и бою: игра останавливается
# (get_tree().paused — бой, таймеры, анимации), поверх — меню.
# Прогресс уже в автосохранении, поэтому «В главное меню» и «Выход» без вопросов.

const LAYER: int = 10   # поверх UI сцены

var enabled: bool = true   # выключается на экране конца забега
var _menu: ModalOverlay = null
var _settings: SettingsPanel = null

func _init() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if _settings:
		_settings.close()
	elif _menu:
		resume()
	elif enabled:
		open()

func is_open() -> bool:
	return _menu != null

func open() -> void:
	get_tree().paused = true
	_menu = ModalOverlay.new()
	add_child(_menu)
	_menu.build_frame(360.0)
	_menu.add_title("ПАУЗА")
	_menu.add_button("ПРОДОЛЖИТЬ", resume, "PrimaryButton")
	_menu.add_button("Настройки", _open_settings)
	_menu.add_button("В главное меню", _to_main_menu)
	_menu.add_button("Выход из игры", _quit)

func resume() -> void:
	if _menu:
		_menu.close()
		_menu = null
	get_tree().paused = false

func _open_settings() -> void:
	_settings = SettingsPanel.new()
	add_child(_settings)
	_settings.setup()
	_settings.tree_exited.connect(func(): _settings = null)

func _to_main_menu() -> void:
	resume()
	RunManager.goto_main_menu()

func _quit() -> void:
	get_tree().quit()
