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
	"embers": {"amount": 110, "lifetime": 7.0, "color": Color(1.0, 0.45, 0.15, 0.85), "scale": Vector2(1.0, 2.0),
		"velocity": Vector2(8.0, 22.0), "direction": Vector2(0.3, -1.0), "gravity": Vector2(3.0, -6.0), "additive": true},
}
const Z_INDEX: int = 40   # над бойцами и постройками, под полосками отрядов и цифрами

func setup(bounds: Rect2, kind: String) -> void:
	if not KINDS.has(kind):
		return
	var k: Dictionary = KINDS[kind]
	z_index = Z_INDEX
	position = bounds.get_center()
	var p := CPUParticles2D.new()
	p.amount = k["amount"]
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
	visible = GameSettings.atmosphere
	GameSettings.changed.connect(_on_settings_changed)

func _on_settings_changed() -> void:
	visible = GameSettings.atmosphere
