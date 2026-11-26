// Внешний грунт за стеной поля (решение пользователя 23.11.2026, FieldSurround): земля до краёв экрана вместо пустоты.
// Спокойный пятнистый грунт одного цвета с плитами поля: пятна шире, чем выше (изометрия), цвет — ступенями,
// пиксель крупный (px), редкие тёмные крапинки. Яркость — прямо target_lum (сжим floor_calm на цвет, близкий к его опоре, ничего не менял и грунт тонул в черноте).
shader_type canvas_item;

uniform vec4 base_color : source_color = vec4(0.12, 0.08, 0.08, 1.0);
uniform float target_lum = 0.09;   // средняя яркость грунта (после пятен), оттенок — от base_color
uniform float px = 3.0;
uniform float steps = 4.0;
uniform float spread = 0.32;   // размах яркости пятен вокруг основного цвета

varying vec2 wpos;

void vertex() {
	wpos = VERTEX;
}

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 p = floor(wpos / px) * px;
	vec2 q = vec2(p.x, p.y * 2.0);   // пятна вытянуты по горизонтали, как на изометрическом полу
	float n = 0.55 * vnoise(q / 140.0) + 0.3 * vnoise(q / 55.0) + 0.15 * vnoise(q / 18.0);
	n = floor(n * steps) / steps;
	vec3 c = base_color.rgb * (1.0 + (n - 0.5) * 2.0 * spread);
	if (h21(floor(wpos / (px * 2.0))) > 0.988) {
		c *= 0.7;   // крапинка
	}
	float base_l = max(dot(base_color.rgb, vec3(0.299, 0.587, 0.114)), 0.004);
	c *= target_lum / base_l;
	COLOR = vec4(c, 1.0);
}
