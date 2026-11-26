shader_type canvas_item;
render_mode blend_add;
uniform vec3 glow_color = vec3(0.35, 0.72, 1.0);
uniform vec2 rect_size = vec2(100.0);
uniform float pad = 10.0;
uniform vec3 ember_color = vec3(1.0, 0.8, 0.5);   // искры-угольки на кромке
uniform float level = 0.0;          // сила: постоянная + наведение (считает узел)
// Карта с рамкой: свет от силуэта и по металлу рамки (координаты — px арта карты)
uniform bool use_shape = false;
uniform sampler2D dist_tex : filter_linear, repeat_disable;     // расстояние от силуэта наружу / shape_margin
uniform sampler2D frame_tex : filter_linear_mipmap, repeat_disable;
uniform vec2 art_size = vec2(360.0, 504.0);
uniform float shape_margin = 40.0;
uniform float metal_gain = 0.24;    // сила отсвета на металле рамки (METAL_GAIN)
uniform vec4 plate = vec4(0.0);     // крупная плашка малой карты (x, y, конец x, конец y) — тоже силуэт
uniform vec4 calm_a = vec4(0.0);    // пергамент плашек — свет на него не ложится
uniform vec4 calm_b = vec4(0.0);
float in_rect(vec2 p, vec4 r) { return step(r.x, p.x) * step(p.x, r.z) * step(r.y, p.y) * step(p.y, r.w); }
float hash(float n) { return fract(sin(n) * 43758.5453); }
float noise(float x) {               // плавный шум по одной оси
	float i = floor(x);
	float f = fract(x);
	return mix(hash(i), hash(i + 1.0), f * f * (3.0 - 2.0 * f));
}
void fragment() {
	vec2 p = UV * rect_size - rect_size * 0.5;
	vec2 hs = rect_size * 0.5 - vec2(pad);
	float r = 4.0;
	vec2 q = abs(p) - hs + vec2(r);
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;   // < 0 — внутри карты
	// координата вдоль периметра (px): пятна света ползут по кромке
	float per = (atan(p.y, p.x) + 3.14159) * (hs.x + hs.y) * 0.64;
	float t = TIME * 0.6;
	float smolder = noise(per * 0.045 + t) * 0.65 + noise(per * 0.13 - t * 1.7) * 0.35;
	smolder = smoothstep(0.25, 0.9, smolder);                    // тлеет пятнами, местами почти гаснет
	float flick = 0.8 + 0.2 * noise(TIME * 7.0 + per * 0.02);   // неровное мерцание
	if (use_shape) {
		float k = max((rect_size.x - pad * 2.0) / art_size.x, 0.001);   // px экрана на px арта
		vec2 a = (UV * rect_size - vec2(pad)) / k;
		float far = texture(dist_tex, (a + vec2(shape_margin)) / (art_size + vec2(shape_margin * 2.0))).r * shape_margin;
		if (plate.z > plate.x) {
			vec2 out_of = max(max(plate.xy - a, a - plate.zw), vec2(0.0));
			far = min(far, length(out_of));
		}
		float s = far * k;                                          // px экрана от кромки рамки
		float breath = 0.82 + 0.18 * smolder;                       // медленное дыхание, без пятен и провалов
		// ореол: плотный у самой кромки, быстро гаснет; внутри силуэта его нет
		float halo = exp(-s / 3.2) * smoothstep(0.0, 0.7, s) * (1.0 - smoothstep(shape_margin * 0.55, shape_margin, far));
		if (pad > 0.0) {
			halo *= 1.0 - smoothstep(pad * 0.6, pad, s);
		}
		// отсвет на самой рамке: чем светлее металл / камень, тем сильнее берёт цвет
		float metal = 0.0;
		if (a.x >= 0.0 && a.y >= 0.0 && a.x <= art_size.x && a.y <= art_size.y) {
			vec4 f = texture(frame_tex, a / art_size);
			float lum = dot(f.rgb, vec3(0.299, 0.587, 0.114));
			// самое светлое (ленты пергамента, блики) берёт цвет слабее — не выбеливается
			metal = f.a * smoothstep(0.08, 0.55, lum) * (1.0 - smoothstep(0.5, 0.75, lum))
				* (1.0 - max(in_rect(a, calm_a), in_rect(a, calm_b)));
		}
		vec3 lit = glow_color * (halo * 0.55 + metal * metal_gain) * breath;
		float ember = step(0.99, hash(floor(per * 0.25) + floor(TIME * 3.0) * 17.0));
		lit += ember_color * ember * smoothstep(2.0, 0.6, s) * smoothstep(0.0, 0.6, s) * smolder * 0.35;
		COLOR = vec4(lit * level, 1.0);
	} else {
	// ореол за краем — рваный, как дымка
	float haze = noise(per * 0.07 + d * 0.3 - TIME * 0.9);
	float outer = d > 0.0 ? exp(-d / max(pad * 0.35, 1.0)) * (0.25 + 0.45 * haze) : 0.0;
	float inner = d <= 0.0 ? exp(d / 7.0) * 0.18 : 0.0;
	float rim = smoothstep(1.8, 0.0, abs(d + 1.0)) * 0.5;
	vec3 col = glow_color * (outer + inner + rim) * (0.5 + 0.7 * smolder) * flick;
	// редкие угольки на самой кромке
	float spark = step(0.985, hash(floor(per * 0.25) + floor(TIME * 3.0) * 17.0)) * rim * smolder;
	col += ember_color * spark * 0.6;
	COLOR = vec4(col * level, 1.0);
	}
}
