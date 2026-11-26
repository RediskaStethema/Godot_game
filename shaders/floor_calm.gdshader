// Спокойный грунт (стилизация 12.11.2026, скилл game-art: «не перегружать фон деталями», «читаемость — контраст
// по яркости»): узор пола сжат по яркости к опорной pivot — доля contrast от прежнего перепада, оттенок и
// насыщенность прежние. Бойцы и здания на ровном фоне читаются силуэтом, сами не ярче (решение пользователя
// 08.11.2026: «юниты слишком выделяются»). contrast 1 — как было. Параметры — IsoGridRenderer.FLOOR_CALM + тема "floor_calm"
shader_type canvas_item;
uniform float contrast = 1.0;
uniform float pivot = 0.18;
void fragment() {
	vec4 c = COLOR;
	float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	float lc = pivot + (l - pivot) * contrast;
	c.rgb *= lc / max(l, 0.004);
	COLOR = c;
}
