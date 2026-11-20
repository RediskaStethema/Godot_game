class_name HealBeam
extends Node2D

# Луч лечения (решение пользователя 08.11.2026, EFFECTS_NEEDED 5.5 — кодом, только вид): лекарь (Apothecary) лечит
# раненого — от груди лекаря к груди пациента зелёный луч: мягкий ореол, яркая сердцевина с лёгкой волной, к пациенту
# бегут искры. Появляется и гаснет за FADE с; лечит себя / некого — гаснет. Дочерний узел лекаря, ADD, цвета —
# Palette.HEAL / HEAL_DEEP. Ставит Soldier._tick_support → set_patient

const FADE: float = 0.2
const CHEST: float = 0.45            # доля роста бойца — грудь
const GLOW_WIDTH: float = 4.0
const CORE_WIDTH: float = 1.2
const SPARKS: int = 3
const SPARK_SPEED: float = 1.4       # проходов искры по лучу в секунду
const WAVE: float = 1.2              # px: волна сердцевины


var healer: Soldier
var patient: Soldier = null
var _alpha: float = 0.0
var _time: float = 0.0

static func for_healer(h: Soldier) -> HealBeam:
	var b := HealBeam.new()
	b.healer = h
	b.material = Vfx.add_material()   # пиксельный ADD
	b.z_index = 5
	h.add_child(b)
	return b

func set_patient(p: Soldier) -> void:
	patient = p

func _active() -> bool:
	return is_instance_valid(patient) and patient != healer and patient.current_state != Soldier.State.DEAD \
		and is_instance_valid(healer) and healer.current_state != Soldier.State.DEAD

func _process(delta: float) -> void:
	var on := _active()
	if not on and _alpha <= 0.0:
		return
	_alpha = move_toward(_alpha, 1.0 if on else 0.0, delta / FADE)
	_time += delta
	queue_redraw()

func _chest(s: Soldier) -> Vector2:
	return to_local(s.global_position + Vector2(0.0, -Soldier.TARGET_SPRITE_HEIGHT * CHEST * s.data.sprite_scale + Soldier.GROUND_SINK))

func _draw() -> void:
	if _alpha <= 0.0 or not is_instance_valid(patient) or not is_instance_valid(healer):
		return
	var a := to_local(healer.heal_point())   # нартециум в руке (metadata/heal_origin листа), нет — грудь
	var b := _chest(patient)
	var dir := b - a
	if dir.length() < 2.0:
		return
	var n := dir.orthogonal().normalized()
	var pulse := 0.8 + 0.2 * sin(_time * 9.0)
	draw_line(a, b, Color(Palette.HEAL_DEEP, 0.35 * _alpha * pulse), GLOW_WIDTH, true)
	# сердцевина — ломаная с волной
	var pts := PackedVector2Array()
	var steps := 8
	for i in steps + 1:
		var t := float(i) / steps
		var w := sin(t * PI) * sin(t * 12.0 - _time * 14.0) * WAVE
		pts.append(a + dir * t + n * w)
	draw_polyline(pts, Color(Palette.HEAL, 0.85 * _alpha), CORE_WIDTH, true)
	for i in SPARKS:
		var t := fmod(_time * SPARK_SPEED + float(i) / SPARKS, 1.0)
		draw_circle(a + dir * t, 1.4, Color(Palette.HEAL, _alpha * sin(t * PI)))
	draw_circle(b, 2.5 * pulse, Color(Palette.HEAL, 0.4 * _alpha))
