extends SceneTree
# Окна и надписи интерфейса не вылезают за края (решение пользователя 24.11.2026: «проверь шрифты и надписи в UI/UX, они вылазят за края»).
# Каждое окно (настройки, подтверждение, Арсенал, сложность, выбор расы / братства / бога, стартовая карта, смена бога, итог забега
# победа / поражение, подкрепление) ставится в SubViewport 1152×648 (в -s скрипте окно — 64×64, раскладка на нём неверна) и
# обходится: Label / RichTextLabel / Button за экраном, надпись шире своей панели, текст шире своей кнопки / метки — вылет.
#   godot --headless --path . -s tests/test_ui_overflow.gd
const SCREEN := Rect2(0, 0, 1152, 648)
var found := 0
var vp: SubViewport

func _initialize() -> void:
	root.get_node("SaveManager").enabled = false
	root.get_node("GameSettings").battle_speed = 1.0
	_main()

func _box_of(n: Node) -> Control:
	var p := n.get_parent()
	while p != null:
		if p is PanelContainer or p is Panel or p is Button:
			return p
		p = p.get_parent()
	return null

func _text_w(c: Control, txt: String) -> float:
	var font: Font = c.get_theme_font("font")
	var fs: int = c.get_theme_font_size("font_size")
	return font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x

func _report(win: String, c: Control, what: String) -> void:
	found += 1
	var txt: String = str(c.get("text")) if c.get("text") != null else ""
	print("FAIL вылет [%s] %s «%s» — %s  rect=%s" % [win, c.get_class(), txt.substr(0, 46).replace("\n", "/"), what, c.get_global_rect()])

func _scan(win: String, node: Node) -> void:
	for ch in node.get_children():
		_scan(win, ch)
	if not (node is Control) or not node.is_visible_in_tree():
		return
	var c: Control = node
	var r := c.get_global_rect()
	if r.size.x < 2 or r.size.y < 2:
		return
	if c is Label or c is RichTextLabel or c is Button:
		var txt: String = str(c.get("text"))
		if txt.strip_edges() == "":
			return
		if r.position.x < SCREEN.position.x - 1 or r.end.x > SCREEN.end.x + 1 or r.position.y < -1 or r.end.y > SCREEN.end.y + 1:
			_report(win, c, "за экраном")
		var box := _box_of(c)
		if box != null and not c is Button:
			var br := box.get_global_rect()
			if r.position.x < br.position.x - 1 or r.end.x > br.end.x + 1:
				_report(win, c, "шире своей панели (%s)" % br)
		if c is Button and (c as Button).icon == null:
			var w := _text_w(c, txt)
			if w > r.size.x - 8:
				_report(win, c, "текст %.0f px в кнопке %.0f px" % [w, r.size.x])
		if c is Label and (c as Label).autowrap_mode == TextServer.AUTOWRAP_OFF and not (c as Label).clip_text:
			var w2 := _text_w(c, txt.split("\n")[0]) if "\n" in txt else _text_w(c, txt)
			if w2 > r.size.x + 1:
				_report(win, c, "текст %.0f px в метке %.0f px" % [w2, r.size.x])

func _open(win: String, path: String, args: Array) -> void:
	var d = load(path).new()
	vp.add_child(d)
	if d.has_method("setup"):
		d.callv("setup", args)
	elif d.has_method("open"):
		d.open()
	await process_frame
	await process_frame
	await process_frame
	var before := found
	_scan(win, d)
	print("%s %s" % ["PASS" if found == before else "FAIL", win])
	d.queue_free()
	await process_frame

func _main() -> void:
	vp = SubViewport.new()
	vp.size = Vector2i(1152, 648)
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	await process_frame
	var rm = root.get_node("RunManager")
	rm.new_run(3)
	await _open("Настройки", "res://scenes/ui/SettingsPanel.gd", [])
	await _open("Подтверждение", "res://scenes/ui/ConfirmDialog.gd", ["Начать новый забег? Текущее сохранение будет потеряно, прогресс Арсенала сохранится.", "Начать", "Отмена"])
	await _open("Арсенал", "res://scenes/ui/ArsenalDialog.gd", [])
	await _open("Сложность", "res://scenes/ui/DifficultySelectDialog.gd", [])
	await _open("Расы", "res://scenes/ui/RaceSelectDialog.gd", [])
	await _open("Братства", "res://scenes/ui/ChapterSelectDialog.gd", ["space_marines", true])
	await _open("Боги", "res://scenes/ui/ChapterSelectDialog.gd", ["chaos", true])
	await _open("Стартовая карта", "res://scenes/ui/StartCardDialog.gd", ["space_marines"])
	await _open("Выбор бога", "res://scenes/ui/GodPickDialog.gd", ["Чумные десантники", "nurgle"])
	await _open("Итог: победа", "res://scenes/battle/ui/RunEndScreen.gd", [true, "Главный босс повержен: цитадель устояла 15 волн подряд", "Волн: 15 · Потери: 128 бойцов · Лучший отряд: Лазники Криспина — 12480 урона\nСлава: +46 (итого 212)\nОткрыта сложность 4"])
	await _open("Итог: поражение", "res://scenes/battle/ui/RunEndScreen.gd", [false, "Цитадель пала на волне 14", "Волн: 13 · Потери: 94 бойца\nСлава: +12"])
	await _open("Подкрепление", "res://scenes/shop/CatchUpPicker.gd", [])
	_check("окна и надписи не выходят за экран, свою панель и кнопку (%d вылетов)" % found, found == 0)
	quit()

func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])
