class_name WorldLight
extends RefCounted

# Один источник света на всё поле (решение пользователя 12.11.2026: «поработай со светом и тенями» — отброшенные
# тени, направленная светотень, общее освещение поля). Свет — сзади слева (луна / зарево за полем, на экране
# вверху слева): тени падают вперёд-вправо по земле (вниз-вправо на экране, по оси изометрии 2:1) — под тех, кто
# стоит впереди: y-сортировка рисует их позже, и тень ложится под них, а не поверх бойцов за зданием;
# на моделях светлее кромки сверху слева, темнее — справа снизу (шейдер бойцов, Soldier.apply_style).
# Параметры — DEFAULT + ключ темы расы "light". Только вид.

const DEFAULT := {
	"shadow_dir": Vector2(0.894, 0.447),   # куда падает тень по земле (экран, длина 1)
	"to_light": Vector2(-0.7, -0.7),       # к свету на моделях (экран)
	"cast_length": 1.1,                    # длина тени здания / цитадели — доля роста над основанием
	"cast_alpha": 0.75,                    # плотность у основания
	"cast_fade": 0.45,                     # к концу тени светлее на эту долю
	"unit_cast_length": 0.9,               # тень бойца — доля роста на экране (TARGET_SPRITE_HEIGHT × sprite_scale)
	"unit_cast_width": 8.0,                # px мира × sprite_scale
	"unit_cast_alpha": 0.85,
	"color": Color(0.72, 0.82, 1.0),       # цвет света на кромках (холодный лунный)
}
const SHADER := preload("res://shaders/cast_shadow.gdshader")

static func param(key: String):
	return FactionTheme.current().get("light", {}).get(key, DEFAULT[key])

# Тень — копия спрайта, сплющенная и скошенная по земле от основания (base — точка основания в координатах
# спрайта): точка на высоте h над основанием ложится на землю в h × cast_length вдоль shadow_dir
static func cast_transform(base: Vector2) -> Transform2D:
	var s: Vector2 = param("shadow_dir") * float(param("cast_length"))
	var basis := Transform2D(Vector2(1, 0), Vector2(-s.x, -s.y), Vector2.ZERO)
	return Transform2D(0.0, base) * basis * Transform2D(0.0, -base)

# Отброшенная тень анимированного спрайта: ребёнок за ним (show_behind_parent), кадр и отражение — как у него.
# fade_height — рост фигуры над основанием, px кадра (к нему тень гаснет на cast_fade); 0 — без затухания
static func attach(sprite: AnimatedSprite2D, base: Vector2, fade_height: float) -> CastShadow:
	var sh := CastShadow.new()
	sh.name = "CastShadow"
	sh.show_behind_parent = true
	sh.sprite_frames = sprite.sprite_frames
	sh.centered = sprite.centered
	sh.texture_filter = sprite.texture_filter
	sh.transform = cast_transform(base)
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("shadow_alpha", float(param("cast_alpha")))
	m.set_shader_parameter("fade", float(param("cast_fade")))
	m.set_shader_parameter("base_y", base.y)
	m.set_shader_parameter("fade_height", fade_height)
	sh.material = m
	sprite.add_child(sh)
	sh.sync()
	return sh

class CastShadow extends AnimatedSprite2D:
	func _process(_delta: float) -> void:
		sync()

	func sync() -> void:
		var p := get_parent() as AnimatedSprite2D
		if p == null:
			return
		if sprite_frames != p.sprite_frames:
			sprite_frames = p.sprite_frames
		if animation != p.animation:
			animation = p.animation
		frame = p.frame
		flip_h = p.flip_h
		offset = p.offset
