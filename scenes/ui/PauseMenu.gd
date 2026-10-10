class_name PauseMenu
extends CanvasLayer

# Пауза по Esc (ui_cancel) в магазине и бою: игра останавливается
# (get_tree().paused — бой, таймеры, анимации), поверх — меню.
# Прогресс уже в автосохранении, поэтому «В главное меню» и «Выход» без вопросов —
# кроме выхода посреди схватки: выйти (бой начнётся заново) или сдаться.

const LAYER: int = 10   # поверх UI сцены

var enabled: bool = true   # выключается на экране конца забега
var _menu: ModalOverlay = null
var _settings: SettingsPanel = null
var _leave_dialog: ModalOverlay = null

func _init() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if _settings:
		_settings.close()
	elif _leave_dialog:
		_leave_dialog.close()
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
	_menu.add_button("В главное меню", _leave.bind(_to_main_menu))
	_menu.add_button("Выход из игры", _leave.bind(_quit))

func resume() -> void:
	if _leave_dialog:
		_leave_dialog.close()
	if _menu:
		_menu.close()
		_menu = null
	get_tree().paused = false

func _open_settings() -> void:
	_settings = SettingsPanel.new()
	add_child(_settings)
	_settings.setup()
	_settings.tree_exited.connect(func(): _settings = null)

# Уход из сцены; посреди схватки — сначала выбор «выйти / сдаться»
func _leave(exit: Callable) -> void:
	if not BattleManager.is_battle_running():
		exit.call()
		return
	_leave_dialog = ModalOverlay.new()
	add_child(_leave_dialog)
	_leave_dialog.build_frame(440.0)
	_leave_dialog.add_title("Идёт бой", "HeaderLabel")
	_leave_dialog.add_title("Выйти — при «Продолжить» бой начнётся заново.\nСдаться — забег окончен, сохранение удаляется.", "DimLabel")
	_leave_dialog.add_button("Выйти", exit, "PrimaryButton")
	_leave_dialog.add_button("Сдаться", _surrender_and.bind(exit))
	_leave_dialog.add_button("Отмена", _leave_dialog.close)
	_leave_dialog.tree_exited.connect(func(): _leave_dialog = null)

func _surrender_and(exit: Callable) -> void:
	BattleManager.surrender()
	exit.call()

func _to_main_menu() -> void:
	resume()
	RunManager.goto_main_menu()

func _quit() -> void:
	get_tree().quit()
