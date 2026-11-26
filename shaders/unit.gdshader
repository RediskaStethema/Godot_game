shader_type canvas_item;
uniform float armor = 0.0;
uniform float target_hue = 0.0;
uniform float sat_mult = 1.0;
uniform float val_mult = 1.0;
uniform float body_mix = 0.0;                       // тёмная нейтральная броня → тон ордена (Chapters "armor"."body")
uniform vec3 body_hsv = vec3(0.0, 0.0, 1.0);        // тон, + насыщенность, × яркость
uniform vec4 protect = vec4(0.0);                   // участок кадра в UV (x, y, ширина, высота), который цвет братства не трогает (лицо, мех)
uniform float body_cap = 1.0;                       // мягкий потолок яркости тела: светлые бойцы (особые отряды) не светлее тёмных
uniform float trim_mix = 0.0;                       // золотая отделка листа → цвет ордена ("armor"."trim")
uniform vec3 trim_hsv = vec3(0.12, 1.0, 1.0);       // тон, × насыщенность, × яркость
uniform float rim_px = 0.0;
uniform vec3 rim_color = vec3(1.0);
uniform float rim_strength = 0.5;
uniform float outline_px = 0.0;
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 0.85);
uniform float flash = 0.0;
// Здания в свет местности (Building.apply_environment; у бойцов — по умолчанию, без изменений): насыщенность,
// приглушение светов, затемнение к основанию (UV.y от ao_from до ao_to — к ao_strength)
uniform float env_sat = 1.0;
uniform float env_knee = 0.0;
uniform float ao_strength = 0.0;
uniform float ao_from = 1.0;
uniform float ao_to = 1.0;
// Смягчение пиксельности (цитадель, решение пользователя 07.11.2026 «менее пиксельной на 20%»): доля лёгкого
// размытия поверх резкой выборки по центру пикселя листа; работает при фильтре LINEAR у узла, 0 — как было
uniform float soften = 0.0;
// Бойцы в стиль поля (решение пользователя 08.11.2026: «юниты слишком выделяются на фоне»):
// pix — пикселизация: «пиксель арта» в pix текселей листа (сетка от угла кадра, цвет — средний по клетке через
// мип-уровень, край силуэта резкий), контур и объём — ровно в такой пиксель; 0 — как было (здания, цитадель);
// env_tint — оттенок местности (у зданий — self_modulate); vol_* — объём кодом, свет сверху (симметричный —
// отражённый враг освещён так же): верхние кромки светлее (vol_light, к цвету vol_color), нижние и боковые
// темнее (vol_shade), корпус светлее к плечам (vol_grad)
uniform float pix = 0.0;
uniform float sharpen = 0.0;   // резкость (18.11.2026, «модели мыльные»): нерезкая маска — сжатие листа до ~31 px размывало мелочь
// Стилизация 12.11.2026 (решение пользователя «бойцы — объём и свет», «здания и поле — единая палитра»):
// bands — светотень ступенями: яркость пикселя к середине своей ступени (bands ступеней), доля band_mix — как
// рисованный пиксель-арт в 2–3 тона; pal_mix — нейтральные (ненасыщенные) цвета к палитре расы pal_ramp по
// яркости (gradient map), насыщенные акценты — золото, синий ордена, огонь — как были. 0 — выключено
uniform float bands = 0.0;
uniform float band_mix = 0.0;
uniform sampler2D pal_ramp : source_color, filter_linear, repeat_disable;
uniform float pal_mix = 0.0;
uniform float pal_range = 1.0;
// Стилизация зданий 12.11.2026 (решение пользователя «пройдись по моделькам зданий»): style_sat — насыщенность
// краски (золото, жёлтый Imperial Fists, красный, синий ордена) к тону поля; свечение (почти белое по яркости и
// насыщенное: плазма, огонь, варп) — как было, glow_keep 1 — беречь его. 1 / 0 — выключено
uniform float style_sat = 1.0;
uniform float glow_keep = 0.0;
uniform vec3 env_tint = vec3(1.0);
uniform float vol_light = 0.0;
uniform float vol_shade = 0.0;
uniform float vol_grad = 0.0;
uniform vec3 vol_color = vec3(1.0);
// Направленный свет (WorldLight, решение пользователя 12.11.2026 «свет и тени»): to_light — к свету на экране;
// кромки силуэта со стороны света светлее (dir_light, к цвету dir_color), с теневой — темнее полосой dir_reach
// клеток (dir_shade). Отражённый спрайт (враг смотрит влево) — по знаку dFdx(UV.x): свет с той же стороны экрана
uniform vec2 to_light = vec2(0.0);
uniform float dir_light = 0.0;
uniform float dir_shade = 0.0;
uniform float dir_reach = 3.0;
uniform vec3 dir_color = vec3(1.0);
// Статусы на теле (решение пользователя 08.11.2026, EFFECTS_NEEDED 7.1–7.4 — кодом): 0/1 по статусу, вид по TIME:
// горение — мерцание огня, сильнее к верху; яд — зелёный налёт от ног, пульс; замедление — иней; усиление —
// контур в цвет st_emp_color и пульсирует
uniform float st_burn = 0.0;
uniform float st_poison = 0.0;
uniform float st_slow = 0.0;
uniform float st_emp = 0.0;
uniform vec3 st_burn_color = vec3(1.0, 0.5, 0.15);
uniform vec3 st_poison_color = vec3(0.55, 0.9, 0.3);
uniform vec3 st_slow_color = vec3(0.6, 0.8, 1.0);
uniform vec3 st_emp_color = vec3(1.0, 0.83, 0.4);
varying vec4 tint;
// Прозрачность листа в точке: lod ≥ 0 — с мип-уровня (пикселизация), иначе обычная выборка. Макрос, не функция:
// встроенный TEXTURE параметром в свою функцию Godot не передаёт («custom_samplers»)
#define ALPHA_AT(p) (lod >= 0.0 ? textureLod(TEXTURE, (p), lod).a : texture(TEXTURE, (p)).a)
vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}
vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}
void vertex() {
	tint = COLOR;   // modulate узла
}
void fragment() {
	vec4 c = COLOR;   // уже текстура × modulate — texture() ещё раз дал бы цвет в квадрат
	vec2 uv = UV;
	float lod = -1.0;
	if (sharpen > 0.0 && pix <= 0.0) {
		vec2 px = UV / TEXTURE_PIXEL_SIZE;
		float foot = max(length(dFdx(px)), length(dFdy(px)));
		float l0 = log2(max(foot, 1.0));
		vec4 soft = textureLod(TEXTURE, UV, l0 + 1.0) * tint;
		c.rgb = clamp(c.rgb + (c.rgb - soft.rgb) * sharpen * c.a, 0.0, 1.5);
	}
	vec2 cell = TEXTURE_PIXEL_SIZE * max(outline_px, 1.0);   // шаг объёма: без пикселизации — толщина контура
	if (pix > 0.0) {
		cell = TEXTURE_PIXEL_SIZE * pix;
		uv = (floor(UV / cell) + 0.5) * cell;
		lod = log2(pix);
		c = textureLod(TEXTURE, uv, lod);
		c.a = smoothstep(0.3, 0.6, c.a);
		c *= tint;
	}
	if (soften > 0.0) {   // ветка по параметру материала — производные определены
		// резкая выборка по центру пикселя листа + доля soften лёгкого размытия (4 плавные выборки в ±1 пиксель —
		// окно ≈ 3×3, с предумноженной альфой: без тёмной каймы по краю силуэта)
		vec2 texel = (floor(UV / TEXTURE_PIXEL_SIZE) + 0.5) * TEXTURE_PIXEL_SIZE;
		vec2 d = TEXTURE_PIXEL_SIZE;
		vec4 t0 = texture(TEXTURE, UV + d);
		vec4 t1 = texture(TEXTURE, UV - d);
		vec4 t2 = texture(TEXTURE, UV + vec2(d.x, -d.y));
		vec4 t3 = texture(TEXTURE, UV + vec2(-d.x, d.y));
		float ba = (t0.a + t1.a + t2.a + t3.a) * 0.25;
		vec3 brgb = (t0.rgb * t0.a + t1.rgb * t1.a + t2.rgb * t2.a + t3.rgb * t3.a) * 0.25 / max(ba, 1e-4);
		vec4 sharp = texture(TEXTURE, texel);
		c = mix(sharp, vec4(brgb, ba), soften) * tint;
	}
	if (armor > 0.5) {
		vec3 hsv = rgb2hsv(c.rgb);
		float blue = smoothstep(0.50, 0.55, hsv.x) * (1.0 - smoothstep(0.72, 0.77, hsv.x)) * smoothstep(0.2, 0.35, hsv.y);
		vec3 col = hsv2rgb(vec3(target_hue, clamp(hsv.y * sat_mult, 0.0, 1.0), clamp(hsv.z * val_mult, 0.0, 1.0)));
		c.rgb = mix(c.rgb, col, blue);
		// Листы Космодесанта после перерисовки — вороненая сталь с золотом: тело (нейтральные не слишком тёмные и не
		// белые пиксели; чёрный контур и блики остаются) и отделка (золото: тон 0.09–0.18, насыщенное) — цвета ордена
		// (17.11.2026: Terminator, Apothecary, Librarian, Chaplain, Chapter Master, Dreadnought, Land Speeder — серо-сиреневая броня
		// светлее 0.62 оставалась как нарисована, а не цвета братства: маска по яркости шире, до 0.95)
		float neutral = (1.0 - smoothstep(0.18, 0.40, hsv.y)) * smoothstep(0.07, 0.14, hsv.z) * (1.0 - smoothstep(0.80, 0.95, hsv.z));
		// Лица и волосы не красятся (решение пользователя 17.11.2026: «только одежду и доспехи»): тёплая кожа и волосы — тон
		// 0.02–0.11, насыщенность от 0.24, яркость 0.4–0.85 — в верхних 40% кадра (голова; в нижней части такие тона — плащи
		// и ткань, их красим) из маски исключены
		float skin = smoothstep(0.015, 0.03, hsv.x) * (1.0 - smoothstep(0.10, 0.12, hsv.x)) * smoothstep(0.20, 0.26, hsv.y)
			* smoothstep(0.35, 0.45, hsv.z) * (1.0 - smoothstep(0.82, 0.9, hsv.z)) * (1.0 - smoothstep(0.36, 0.44, UV.y));
		neutral *= 1.0 - skin;
		vec2 pin = step(protect.xy, UV) * step(UV, protect.xy + protect.zw);
		neutral *= 1.0 - pin.x * pin.y * step(0.0001, protect.z);
		float bv = hsv.z * body_hsv.z;
		bv = body_cap < 0.99 ? body_cap * tanh(bv / body_cap) : bv;
		vec3 bcol = hsv2rgb(vec3(body_hsv.x, clamp(hsv.y + body_hsv.y, 0.0, 1.0), clamp(bv, 0.0, 1.0)));
		c.rgb = mix(c.rgb, bcol, neutral * body_mix);
		float gold = smoothstep(0.08, 0.10, hsv.x) * (1.0 - smoothstep(0.17, 0.20, hsv.x)) * smoothstep(0.35, 0.5, hsv.y) * smoothstep(0.25, 0.4, hsv.z);
		vec3 tcol = hsv2rgb(vec3(trim_hsv.x, clamp(hsv.y * trim_hsv.y, 0.0, 1.0), clamp(hsv.z * trim_hsv.z, 0.0, 1.0)));
		c.rgb = mix(c.rgb, tcol, gold * trim_mix);
	}
	if (rim_px > 0.0) {
		vec2 d = pix > 0.0 ? cell : TEXTURE_PIXEL_SIZE * rim_px;
		float around = min(min(ALPHA_AT(uv + vec2(d.x, 0.0)), ALPHA_AT(uv - vec2(d.x, 0.0))),
			min(ALPHA_AT(uv + vec2(0.0, d.y)), ALPHA_AT(uv - vec2(0.0, d.y))));
		c.rgb = mix(c.rgb, rim_color, (1.0 - around) * step(0.5, c.a) * rim_strength);
	}
	if (env_sat != 1.0 || env_knee > 0.0 || ao_strength > 0.0) {
		float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
		c.rgb = mix(vec3(l), c.rgb, env_sat);
		// светлое приглушается, огонь и свечение (яркое и насыщенное) — нет
		float mx = max(c.r, max(c.g, c.b));
		float glow = smoothstep(0.45, 0.75, (mx - min(c.r, min(c.g, c.b))) / max(mx, 1e-4)) * smoothstep(0.35, 0.6, mx);
		c.rgb *= 1.0 - env_knee * smoothstep(0.25, 0.9, l) * (1.0 - glow);
		c.rgb *= 1.0 - ao_strength * smoothstep(ao_from, ao_to, UV.y);
	}
	c.rgb *= env_tint;
	if (vol_light > 0.0 || vol_shade > 0.0 || vol_grad > 0.0) {
		float solid = step(0.5, c.a);
		float up = ALPHA_AT(uv - vec2(0.0, cell.y));
		float dn = ALPHA_AT(uv + vec2(0.0, cell.y));
		float sides = 2.0 - ALPHA_AT(uv - vec2(cell.x, 0.0)) - ALPHA_AT(uv + vec2(cell.x, 0.0));
		float lit = (1.0 - step(0.5, up)) * solid;
		float shade = max(1.0 - step(0.5, dn), min(sides, 1.0) * 0.6) * solid * (1.0 - lit);
		c.rgb = mix(c.rgb, c.rgb * 1.45 + vol_color * 0.1, lit * vol_light);
		c.rgb *= 1.0 - shade * vol_shade;
		c.rgb *= 1.0 + vol_grad * (0.55 - UV.y);
	}
	if (dir_light > 0.0 || dir_shade > 0.0) {
		float solid = step(0.5, c.a);
		vec2 dl = normalize(to_light) * vec2(dFdx(UV.x) < 0.0 ? -1.0 : 1.0, 1.0) * cell;
		float lit = (1.0 - step(0.5, ALPHA_AT(uv + dl * 1.5))) * solid;
		float back = max(1.0 - step(0.5, ALPHA_AT(uv - dl * 1.5)),
			(1.0 - step(0.5, ALPHA_AT(uv - dl * dir_reach))) * 0.55) * solid * (1.0 - lit);
		c.rgb = mix(c.rgb, c.rgb * 1.3 + dir_color * 0.14, lit * dir_light);
		c.rgb *= 1.0 - back * dir_shade;
	}
	if (style_sat < 1.0) {
		float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
		float mx = max(c.r, max(c.g, c.b));
		float sat = (mx - min(c.r, min(c.g, c.b))) / max(mx, 1e-4);
		float emissive = smoothstep(0.82, 0.97, mx) * smoothstep(0.45, 0.7, sat) * glow_keep;
		c.rgb = mix(vec3(l), c.rgb, mix(style_sat, 1.0, emissive));
	}
	if (bands > 0.0) {
		float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
		float lq = (floor(l * bands) + 0.5) / bands;
		c.rgb *= mix(1.0, clamp(lq / max(l, 0.02), 0.6, 1.6), band_mix);
	}
	if (pal_mix > 0.0) {
		float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
		float mx = max(c.r, max(c.g, c.b));
		float sat = (mx - min(c.r, min(c.g, c.b))) / max(mx, 1e-4);
		vec3 p = texture(pal_ramp, vec2(clamp(l * pal_range, 0.0, 1.0), 0.5)).rgb;
		c.rgb = mix(c.rgb, p, pal_mix * (1.0 - smoothstep(0.2, 0.5, sat)));
	}
	if (st_burn + st_poison + st_slow + st_emp > 0.0) {
		float solid = step(0.5, c.a);
		if (st_burn > 0.0) {
			float fl = 0.5 + 0.5 * sin(TIME * 13.0 + UV.x * 38.0 + UV.y * 21.0) * sin(TIME * 8.3 - UV.y * 33.0);
			float heat = smoothstep(0.95, 0.25, UV.y);
			c.rgb = mix(c.rgb, st_burn_color * (0.75 + 0.6 * fl), solid * heat * (0.18 + 0.32 * fl));
		}
		if (st_poison > 0.0) {
			float pulse = 0.5 + 0.5 * sin(TIME * 3.2 + UV.x * 9.0);
			float low = smoothstep(0.35, 1.0, UV.y);
			float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
			c.rgb = mix(c.rgb, st_poison_color * (l * 1.3 + 0.12), solid * (0.25 + 0.3 * low) * (0.7 + 0.3 * pulse));
		}
		if (st_slow > 0.0) {
			float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
			c.rgb = mix(c.rgb, st_slow_color * (l * 1.2 + 0.18), solid * 0.42);
		}
		if (st_emp > 0.0) {
			c.rgb = mix(c.rgb, c.rgb * st_emp_color * 1.25, solid * 0.18);
		}
	}
	c.rgb = mix(c.rgb, vec3(1.0), flash);
	// Выборки — в ветке по параметру материала (одинаков для всех пикселей): в ветке по прозрачности пикселя
	// производные для мип-уровней не определены — на части видеокарт рябь по краю силуэта
	float near = 0.0;
	if (outline_px > 0.0) {
		// в пикселизации — ровно пиксель сетки, по сторонам и диагоналям (сплошной контур без зазубрин)
		vec2 d = pix > 0.0 ? cell : TEXTURE_PIXEL_SIZE * outline_px;
		vec2 e = pix > 0.0 ? cell : d * 0.7071;
		near = max(max(max(ALPHA_AT(uv + vec2(d.x, 0.0)), ALPHA_AT(uv - vec2(d.x, 0.0))),
			max(ALPHA_AT(uv + vec2(0.0, d.y)), ALPHA_AT(uv - vec2(0.0, d.y)))),
			max(max(ALPHA_AT(uv + e), ALPHA_AT(uv - e)),
			max(ALPHA_AT(uv + vec2(e.x, -e.y)), ALPHA_AT(uv + vec2(-e.x, e.y)))));
		if (pix > 0.0) {
			near = step(0.45, near);
		}
	}
	if (outline_px > 0.0 && c.a < 0.99) {
		vec4 oc = outline_color;
		if (st_emp > 0.0) {   // усиление — контур светится и дышит
			oc = vec4(st_emp_color * (0.75 + 0.35 * sin(TIME * 6.0)), 1.0);
		}
		float oa = oc.a * smoothstep(0.15, 0.6, near) * tint.a;
		// контур под фигурой: полупрозрачный край спрайта ложится на него
		float a = c.a + oa * (1.0 - c.a);
		c.rgb = a > 0.0 ? (c.rgb * c.a + oc.rgb * oa * (1.0 - c.a)) / a : c.rgb;
		c.a = a;
	}
	COLOR = c;
}
