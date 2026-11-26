class_name Atmosphere
extends Node2D

# Атмосфера поля боя (решение пользователя 18.10.2026, гримдарк): частицы в воздухе над всем полем —
# пепел у Космодесанта, угли у Хаоса (FactionTheme "atmosphere"). Только вид: свои часы частиц,
# на бой не влияют. Выключается настройкой GameSettings.atmosphere.

const KINDS = {
	# пепел: медленно оседает и сносится ветром
	"ash": {"amount": 140, "lifetime": 10.0, "color": Color(0.72, 0.76, 0.84, 0.45), "scale": Vector2(1.0, 2.2),
		"velocity": Vector2(6.0, 16.0), "direction": Vector2(0.4, 1.0), "gravity": Vector2(5.0, 4.0), "additive": false},
	# угли: тлеющие искры поднимаются и гаснут
	# Хаос: искры варпа (палитра «бордо + варп», 23.10.2026; были оранжевые угли)
	"embers": {"amount": 110, "lifetime": 7.0, "color": Color(1.0, 0.3, 0.62, 0.8), "scale": Vector2(1.0, 2.0),
		"velocity": Vector2(8.0, 22.0), "direction": Vector2(0.3, -1.0), "gravity": Vector2(3.0, -6.0), "additive": true},
	# Второй слой (17.11.2026, «атмосфера»): редкие крупные частицы поверх основных — глубина вместо плоской завесы
	# хлопья: крупные, тусклые, медленнее пепла (Космодесант)
	"ash_flake": {"amount": 26, "lifetime": 14.0, "color": Color(0.6, 0.55, 0.62, 0.22), "scale": Vector2(2.4, 4.0),
		"velocity": Vector2(3.0, 8.0), "direction": Vector2(0.5, 1.0), "gravity": Vector2(2.0, 2.0), "additive": false},
	# искры варпа: редкие, яркие, плывут вверх (Хаос)
	"warp_mote": {"amount": 16, "lifetime": 9.0, "color": Color(0.85, 0.3, 1.0, 0.55), "scale": Vector2(2.0, 3.5),
		"velocity": Vector2(5.0, 12.0), "direction": Vector2(-0.2, -1.0), "gravity": Vector2(-2.0, -3.0), "additive": true},
}
# Основной слой → второй (если задан)
const EXTRA = {"ash": "ash_flake", "embers": "warp_mote"}
const Z_INDEX: int = 40   # над бойцами и постройками, под полосками отрядов и цифрами

# Частиц на накал 1 (WorldGrade.mood): к финалу воздух гуще, к боссу — ещё плотнее
const MOOD_AMOUNT: float = 0.7

func setup(bounds: Rect2, kind: String, mood: float = 0.0) -> void:
	if not KINDS.has(kind):
		return
	z_index = Z_INDEX
	position = bounds.get_center()
	_add_layer(bounds, kind, mood)
	if EXTRA.has(kind):
		_add_layer(bounds, EXTRA[kind], mood)
	visible = GameSettings.atmosphere
	GameSettings.changed.connect(_on_settings_changed)

func _add_layer(bounds: Rect2, kind: String, mood: float) -> void:
	var k: Dictionary = KINDS[kind]
	var p := CPUParticles2D.new()
	p.amount = int(k["amount"] * (1.0 + MOOD_AMOUNT * mood))
	p.lifetime = k["lifetime"]
	p.preprocess = k["lifetime"]   # поле уже в частицах на входе в бой
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = bounds.size / 2.0
	p.direction = k["direction"]
	p.spread = 25.0
	p.initial_velocity_min = k["velocity"].x
	p.initial_velocity_max = k["velocity"].y
	p.gravity = k["gravity"]
	p.scale_amount_min = k["scale"].x
	p.scale_amount_max = k["scale"].y
	var ramp := Gradient.new()   # появляется и гаснет плавно
	var c: Color = k["color"]
	ramp.set_color(0, Color(c, 0.0))
	ramp.set_color(1, Color(c, 0.0))
	ramp.add_point(0.2, c)
	ramp.add_point(0.75, c)
	p.color_ramp = ramp
	if k["additive"]:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		p.material = m
	add_child(p)

func _on_settings_changed() -> void:
	visible = GameSettings.atmosphere
