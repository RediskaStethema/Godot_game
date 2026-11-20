// Эффекты и снаряды пиксель-артом (решение пользователя 12.11.2026): цвет — ступенями fx_levels на канал,
// прозрачность — ступенями fx_alpha_steps, граница ступени — дизерингом Байера в клетке fx_dither_px пикселей
// экрана (полупрозрачный дым и свет — пиксельным узором, а не «мылом»). fx_on 0 — как было
#include "res://shaders/pixel_common.gdshaderinc"
uniform float fx_on = 1.0;
uniform float fx_levels = 7.0;
uniform float fx_alpha_steps = 4.0;
uniform float fx_dither_px = 2.0;
vec4 fx_pixel(vec4 c, vec2 frag) {
	if (fx_on < 0.5) {
		return c;
	}
	// Слабый вклад (дым, свет, большие заливки) — мелкие ступени и дизеринг в 1 px: при 7 ступенях и клетке 2 px
	// слабая заливка на весь экран рассыпалась в крупную сетку точек (решение пользователя 19.11.2026)
	float faint = 1.0 - smoothstep(0.1, 0.3, max(c.r, max(c.g, c.b)) * c.a);
	float dpx = mix(fx_dither_px, 1.0, faint);
	float d = bayer4(frag / dpx);
	c.rgb = posterize_dither(c.rgb, mix(fx_levels, 32.0, faint), d);
	c.a = clamp(floor(c.a * mix(fx_alpha_steps, 24.0, faint) + d) / mix(fx_alpha_steps, 24.0, faint), 0.0, 1.0);
	return c;
}
