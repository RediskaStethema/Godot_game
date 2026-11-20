// Отброшенная тень здания / цитадели (WorldLight.attach, решение пользователя 12.11.2026 «свет и тени»): силуэт
// кадра — сплошной тенью (полупрозрачные дым и свечение тени почти не дают), к концу тени светлее (fade по высоте
// точки над основанием base_y в px кадра, на fade_height — полное; 0 — без затухания), прозрачность ступенями
// с дизерингом Байера — как пиксельные эффекты.
// Прозрачность узла (OcclusionFader, проявление) — множителем: COLOR — текстура × modulate
shader_type canvas_item;
#include "res://shaders/pixel_common.gdshaderinc"
uniform vec3 shadow_color = vec3(0.0);
uniform float shadow_alpha = 0.5;
uniform float fade = 0.6;
uniform float base_y = 0.0;
uniform float fade_height = 0.0;
uniform float alpha_steps = 6.0;
uniform float dither_px = 2.0;
varying float height;
void vertex() {
	height = base_y - VERTEX.y;   // VERTEX — px кадра в координатах спрайта (с offset), до скоса тени
}
void fragment() {
	float ta = texture(TEXTURE, UV).a;
	float node_a = ta > 0.004 ? clamp(COLOR.a / ta, 0.0, 1.0) : 1.0;
	float h = fade_height > 0.0 ? clamp(height / fade_height, 0.0, 1.0) : 0.0;
	float a = smoothstep(0.25, 0.6, ta) * shadow_alpha * (1.0 - fade * h) * node_a;
	a = floor(a * alpha_steps + bayer4(FRAGCOORD.xy / dither_px)) / alpha_steps;
	COLOR = vec4(shadow_color, clamp(a, 0.0, 1.0));
}
