// Цветокоррекция поля боя (WorldGrade): насыщенность, экспозиция, гамма, тон теней и светов, свечение ярких,
// виньетка; последним — общая палитра (решение пользователя 12.11.2026, стилизация «весь экран — общая
// палитра»): каждый канал — post_levels ступеней, границы ступеней — дизерингом Байера в клетке post_dither_px
// пикселей экрана; post_levels 0 — без него. Параметры — WorldGrade.DEFAULT + тема расы "grade"
shader_type canvas_item;
#include "res://shaders/pixel_common.gdshaderinc"
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
// Свет со стороны источника (WorldLight, решение пользователя 12.11.2026 «общее освещение поля»): экран у key_pos
// (UV, может быть за краем) светлее и в тон key_color, к радиусу key_radius — как было; key 0 — выключено
uniform vec2 key_pos = vec2(0.0, 0.0);
uniform float key = 0.0;
uniform float key_radius = 1.2;
uniform vec3 key_color = vec3(1.0);
// Накал забега и облегчение (решение пользователя 18.11.2026): mood_amount 0..1 — к красно-угольному тону (чем глубже в
// забег, тем мрачнее и краснее), relief 0..1 — после победы поле на миг светлеет и теплеет
uniform vec3 mood_tint = vec3(1.1, 0.86, 0.82);
uniform float mood_amount = 0.0;
uniform float relief = 0.0;
// Зерно плёнки и хроматическая аберрация (то же решение): grain — сила зерна (тонкое, по пикселю экрана, 12 кадров/с),
// ca_edge — расхождение каналов у краёв экрана в доле UV, ca_pulse 0..1 — импульс от тяжёлых ударов (WorldGrade.pulse)
uniform float grain = 0.03;
uniform float film_time = 0.0;
uniform float ca_edge = 0.0007;
uniform float ca_pulse = 0.0;
uniform float post_levels = 0.0;
uniform float post_dither_px = 2.0;
vec3 bright(vec3 s) {
	return s * smoothstep(bloom_threshold, 1.0, max(s.r, max(s.g, s.b)));
}
void fragment() {
	vec2 to_c = SCREEN_UV - vec2(0.5);
	float ca = (ca_edge + ca_pulse * 0.007) * dot(to_c, to_c) * 4.0;
	vec2 ca_dir = normalize(to_c + vec2(0.0001)) * ca;
	vec3 c = vec3(texture(screen_tex, SCREEN_UV + ca_dir).r, texture(screen_tex, SCREEN_UV).g, texture(screen_tex, SCREEN_UV - ca_dir).b);
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
	c = mix(c, c * mood_tint, mood_amount * (1.0 - relief));
	c = c * (1.0 + 0.1 * relief);
	c = mix(vec3(dot(c, vec3(0.299, 0.587, 0.114))), c, 1.0 + 0.18 * relief);
	c = pow(clamp(c, 0.0, 1.0), vec3(gamma));
	if (key > 0.0) {
		float kd = length((UV - key_pos) * vec2(1.0, 0.75)) / key_radius;
		float kl = (1.0 - smoothstep(0.0, 1.0, kd)) * key;
		c = c * (1.0 + kl * key_color) + key_color * kl * 0.012;
	}
	c += glow * bloom;
	vec2 d = (UV - 0.5) * vec2(1.0, 0.8);
	float v = smoothstep(0.3, 0.75, length(d)) * vignette;
	c = mix(c, vignette_color, v);
	if (post_levels > 0.0) {
		c = posterize_dither(c, post_levels, bayer4(FRAGCOORD.xy / post_dither_px));
	}
	if (grain > 0.0) {
		float gl = dot(c, vec3(0.299, 0.587, 0.114));
		float n = fract(sin(dot(floor(FRAGCOORD.xy) + floor(film_time * 12.0) * 17.0, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
		c += n * grain * (0.35 + 0.65 * (1.0 - gl));   // в тенях зерно заметнее, в светах — нет
	}
	COLOR = vec4(c, 1.0);
}
