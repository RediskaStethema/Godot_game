class_name WorldGrade
extends CanvasLayer

# Цветокоррекция поля боя (решение пользователя 18.10.2026 — гримдарк по концепту меню): полноэкранный
# проход поверх мира и под интерфейсом — приглушённая насыщенность, тени в холодный тон, света в тёплый,
# мягкий контраст и виньетка. Параметры — по расе игрока (FactionTheme "grade"), без ключа — DEFAULT.
# Только вид; выключается настройкой GameSettings.atmosphere.
#   layer = 1 и место в дереве перед UI (BattleScene._build_ui): UI того же слоя рисуется позже — не тонируется

# Поле и так тёмное: коррекция не топит его, а поднимает средние тона (gamma < 1), тонирует тени
# сложением (холодный воздух), гасит лишнюю насыщенность ярких бойцов и греет света
const DEFAULT = {
	"saturation": 0.78,                        # 1 — как есть
	"exposure": 1.1,
	"gamma": 0.88,                             # < 1 — светлее средние тона
	"shadow_tone": Color(0.006, 0.014, 0.032), # прибавка в тенях — сине-сталь
	"highlights": Color(1.06, 1.0, 0.88),      # множитель в светах — янтарь
	"vignette": 0.5,                           # сила затемнения краёв
	"vignette_color": Color(0.01, 0.015, 0.03),
	# Свечение ярких (решение пользователя 08.11.2026, bloom одним проходом): яркие пиксели (огонь, плазма, варп,
	# вспышки — ярче bloom_threshold по сильнейшему каналу) светят ореолом радиусом bloom_radius px экрана
	"bloom": 0.6,
	"bloom_threshold": 0.6,
	"bloom_radius": 4.0,
}

const SHADER = """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float saturation = 0.78;
uniform float exposure = 1.1;
uniform float gamma = 0.88;
uniform vec3 shadow_tone = vec3(0.006, 0.014, 0.032);
uniform vec3 highlights = vec3(1.06, 1.0, 0.88);
uniform float vignette = 0.5;
uniform vec3 vignette_color = vec3(0.01, 0.015, 0.03);
uniform sampler2D screen_lin : hint_screen_texture, filter_linear;
uniform float bloom = 0.6;
uniform float bloom_threshold = 0.6;
uniform float bloom_radius = 4.0;
vec3 bright(vec3 s) {
	return s * smoothstep(bloom_threshold, 1.0, max(s.r, max(s.g, s.b)));
}
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	// ореол: 12 выборок по двум кольцам, ближнее весомее
	vec3 glow = vec3(0.0);
	if (bloom > 0.0) {
		for (int i = 0; i < 6; i++) {
			float a = float(i) * 1.0472;
			vec2 dir = vec2(cos(a), sin(a)) * SCREEN_PIXEL_SIZE * bloom_radius;
			glow += bright(texture(screen_lin, SCREEN_UV + dir * 0.5).rgb) * 0.6;
			glow += bright(texture(screen_lin, SCREEN_UV + vec2(-dir.y, dir.x) * 1.15).rgb) * 0.4;
		}
		glow /= 6.0;
	}
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation) * exposure;
	float t = smoothstep(0.0, 0.45, l);
	c = c + shadow_tone * (1.0 - t);
	c *= mix(vec3(1.0), highlights, t);
	c = pow(clamp(c, 0.0, 1.0), vec3(gamma));
	c += glow * bloom;
	vec2 d = (UV - 0.5) * vec2(1.0, 0.8);
	float v = smoothstep(0.3, 0.75, length(d)) * vignette;
	COLOR = vec4(mix(c, vignette_color, v), 1.0);
}"""

static var _shader: Shader

var _rect: ColorRect

func _ready() -> void:
	layer = 1
	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	var grade: Dictionary = DEFAULT.merged(FactionTheme.current().get("grade", {}), true)
	for key in grade:
		var value = grade[key]
		m.set_shader_parameter(key, Vector3(value.r, value.g, value.b) if value is Color else value)
	_rect.material = m
	add_child(_rect)
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = GameSettings.atmosphere
	GameSettings.changed.connect(_on_settings_changed)   # метод, не лямбда: связь снимется вместе с узлом

func _on_settings_changed() -> void:
	visible = GameSettings.atmosphere
