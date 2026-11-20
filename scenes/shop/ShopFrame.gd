class_name ShopFrame
extends PanelContainer

# Рамка панели магазина (решение пользователя 12.11.2026, образец download.png): ржавая латунная кромка с
# заклёпками по углам, внутри — полупрозрачная тьма (Palette.SHOP_VEIL): сквозь магазин видно поле боя.
# Кодом, пока нет арта (UI_NEEDED.txt); ржавчина — пятна по кромке от своего seed (не RunManager.rng).

const BORDER: int = 3
const CUT: int = 6               # срез угла
const RIVET_R: float = 3.0
const RIVET_INSET: float = 7.0
const RUST_SPOTS: int = 28       # пятен на 1000 px периметра
const FADE_STEPS: int = 5        # шапка без рамки: подложка — полосы со ступенями прозрачности (не плавный градиент: пиксель-арт)
const FADE_EXTRA: float = 26.0   # подложка спускается ниже шапки на столько px

var veil: Color = Palette.SHOP_VEIL
var rivets: bool = true
var framed: bool = true          # false — шапка без рамки и фона (17.11.2026): только содержимое поверх поля
var _seed: int = 0

static func style(bg: Color, margin: float = 10.0) -> StyleBoxFlat:
	var s := UITheme.panel_style(bg, Palette.SHOP_FRAME, BORDER, CUT, margin)
	s.anti_aliasing = false   # пиксельная кромка, как в образце
	return s

# Шапка экрана — одна на магазин, бой и событие (решение пользователя 12.11.2026, «единая шапка»): тьма
# SHOP_BAR_VEIL, верх и бока — за краем экрана, видна латунная кромка снизу. Добавляет в parent, высота HUD_HEIGHT
static func hud_bar(parent: Control, with_frame: bool = false) -> ShopFrame:   # без рамки у всех шапок (магазин, бой, выбор карты, событие — 17.11.2026)
	var hud := ShopFrame.new(Palette.SHOP_BAR_VEIL, 6.0, false)
	hud.name = "HudBar"
	if not with_frame:   # решение пользователя 17.11.2026: бой и выбор карты — без верхней рамки, видны только значки и числа
		hud.framed = false
		var empty := StyleBoxEmpty.new()
		empty.set_content_margin_all(6.0)
		hud.add_theme_stylebox_override("panel", empty)
	parent.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hud.offset_left = -BORDER
	hud.offset_right = BORDER
	hud.offset_top = -BORDER
	hud.offset_bottom = UITheme.HUD_HEIGHT
	return hud

func _init(bg: Color = Palette.SHOP_VEIL, margin: float = 10.0, with_rivets: bool = true) -> void:
	veil = bg
	rivets = with_rivets
	_seed = randi()
	add_theme_stylebox_override("panel", style(bg, margin))
	mouse_filter = Control.MOUSE_FILTER_PASS
	resized.connect(queue_redraw)

func _draw() -> void:
	if not framed:
		_draw_fade()
		return
	# Тёмная внутренняя кромка — объём рамки
	draw_rect(Rect2(Vector2(BORDER, BORDER), size - Vector2(BORDER, BORDER) * 2.0), Palette.SHOP_FRAME_DARK, false, 1.0)
	# Ржавчина и блики по кромке
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	var per := (size.x + size.y) * 2.0
	for i in int(per / 1000.0 * RUST_SPOTS):
		var t := rng.randf() * per
		var p := _perimeter_point(t)
		var c: Color = Palette.SHOP_RUST if rng.randf() < 0.7 else Palette.SHOP_FRAME_LIGHT
		draw_rect(Rect2(p - Vector2(1, 1), Vector2(rng.randi_range(2, 4), rng.randi_range(2, 3))), c)
	if rivets:
		for corner in [Vector2(RIVET_INSET, RIVET_INSET), Vector2(size.x - RIVET_INSET, RIVET_INSET),
				Vector2(RIVET_INSET, size.y - RIVET_INSET), Vector2(size.x - RIVET_INSET, size.y - RIVET_INSET)]:
			draw_circle(corner, RIVET_R + 1.0, Palette.SHOP_FRAME_DARK)
			draw_circle(corner, RIVET_R, Palette.SHOP_FRAME)
			draw_circle(corner - Vector2(1, 1), 1.0, Palette.SHOP_FRAME_LIGHT)

# Подложка шапки без рамки (решение пользователя 17.11.2026: рамку убрали, а значки и лента волн на светлой стене поля
# читались слабо — отношение яркости 1.08): ступени тёмного от верха кадра, к низу прозрачнее
func _draw_fade() -> void:
	var total := size.y + FADE_EXTRA
	var band := total / float(FADE_STEPS)
	for i in FADE_STEPS:
		var c := Palette.HUD_FADE
		c.a *= 1.0 - float(i) / float(FADE_STEPS)
		draw_rect(Rect2(-BORDER, i * band, size.x + BORDER * 2.0, band + 1.0), c)

# Точка на кромке по длине обхода t (по часовой от левого верхнего угла)
func _perimeter_point(t: float) -> Vector2:
	var b := BORDER / 2.0
	if t < size.x:
		return Vector2(t, b)
	t -= size.x
	if t < size.y:
		return Vector2(size.x - b, t)
	t -= size.y
	if t < size.x:
		return Vector2(size.x - t, size.y - b)
	t -= size.x
	return Vector2(b, size.y - t)
