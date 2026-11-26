shader_type canvas_item;
render_mode blend_add;
uniform float foil = 0.0;            // 1 — Epic: переливы
uniform float sweep = -1.0;          // доля прохода полосы блика (< 0 — нет)
uniform vec2 mouse = vec2(0.5);      // курсор в долях карты
uniform float hover = 0.0;
uniform vec3 light_color = vec3(1.0, 0.86, 0.62);
// Силуэт карты: альфа рамки + окно арта (в долях лица) — прозрачные поля рамки (у Common) не светятся
uniform bool use_mask = false;
uniform sampler2D mask_tex : filter_linear;
uniform vec4 window = vec4(0.0, 0.0, 1.0, 1.0);   // x, y, конец x, конец y
void fragment() {
	vec3 col = vec3(0.0);
	if (sweep >= 0.0) {
		float d = UV.x + UV.y * 0.5 - (sweep * 1.9 - 0.2);
		col += light_color * smoothstep(0.09, 0.0, abs(d)) * 0.32;
	}
	if (foil > 0.5) {
		float h = fract(UV.x * 0.8 + UV.y * 0.6 + mouse.x * 0.5 + TIME * 0.05);
		vec3 rainbow = 0.5 + 0.5 * cos(6.2831 * (h + vec3(0.0, 0.33, 0.67)));
		col += rainbow * 0.09 * hover;
	}
	col += light_color * hover * 0.14 * smoothstep(0.65, 0.0, distance(UV, mouse));
	if (use_mask) {
		float inside = step(window.x, UV.x) * step(UV.x, window.z) * step(window.y, UV.y) * step(UV.y, window.w);
		col *= max(texture(mask_tex, UV).a, inside);
	}
	COLOR = vec4(col, 1.0);
}
