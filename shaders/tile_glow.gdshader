shader_type canvas_item;
render_mode blend_add;
uniform vec4 edge_color : source_color;
uniform vec4 core_color : source_color;
uniform vec2 quad_size;
uniform vec2 quad_center;     // центр клетки в пикселях квада
uniform vec2 half_tile;
uniform float px;
uniform float fill;
uniform float time;
uniform float alpha = 1.0;
uniform float burst = 0.0;    // 1 — раскрытие купленной клетки
uniform float progress = 0.0; // 0..1 раскрытия (BURST_TIME)

float hash(float n) { return fract(sin(n * 12.9898) * 43758.5453); }
float hash2(vec2 v) { return fract(sin(dot(v, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 v) {
	vec2 i = floor(v);
	vec2 f = fract(v);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x),
		mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 p = UV * quad_size - quad_center;
	p = (floor(p / px) + 0.5) * px;   // пиксель-арт: свечение ступеньками, как плиты
	float k = length(vec2(1.0 / half_tile.x, 1.0 / half_tile.y));
	float d = abs(p.x) / half_tile.x + abs(p.y) / half_tile.y;   // 1 — кромка клетки
	float dist = (d - 1.0) / k;   // до кромки в пикселях, внутри — минус
	float s = fract(atan(p.y * half_tile.x / half_tile.y, p.x) / 6.2831853 + 1.0);   // периметр 0..1
	float stone = vnoise(p / 9.0 + vec2(0.0, time * 0.25));   // свет пятнами по камню, медленно плывёт
	// раскрытие купленной клетки: от центра идёт волна света, за ней загорается кромка, всё оседает
	float edge_on = 1.0;
	float wave = 0.0;
	float dust = 1.0;
	if (burst > 0.5) {
		float t = progress;
		float wr = 1.15 * (1.0 - pow(1.0 - min(t / 0.45, 1.0), 3.0));
		wave = exp(-abs(d - wr) * 10.0) * step(d, wr + 0.15) * (1.0 - smoothstep(0.3, 0.6, t)) * (0.6 + 0.6 * stone);
		wave += step(d, wr) * step(d, 1.0) * (1.0 - smoothstep(0.05, 0.7, t)) * 0.45 * stone;
		edge_on = smoothstep(0.2, 0.42, t) * (1.0 - smoothstep(0.6, 1.0, t));
		dust = 1.0 - smoothstep(0.7, 1.0, t);
	}
	// кромка тлеет неровно: яркость плывёт вдоль периметра, местами почти гаснет
	float ember = smoothstep(0.2, 0.85, vnoise(vec2(s * 22.0, time * 1.6))) * 0.75 + 0.25;
	float pulse = 0.88 + 0.12 * sin(time * 2.4);
	float line = step(-px, dist) * step(dist, 0.0) * ember * 0.75;
	float rim = exp(min(dist, 0.0) / 7.0) * step(dist, 0.0) * 0.4 * ember;   // свет копится у края
	float halo = exp(-max(dist, 0.0) / (px * 1.2)) * step(0.0, dist) * 0.22 * ember;
	float inner = exp(min(dist, 0.0) / 28.0) * step(dist, 0.0) * fill * (0.55 + 0.9 * stone);
	float tip = min(length(vec2(abs(p.x) - half_tile.x, p.y)), length(vec2(p.x, abs(p.y) - half_tile.y)));
	float corner = step(tip, px * 1.5) * step(abs(dist), px * 1.5) * 0.5;   // уголки клетки — чуть ярче
	// две искры бегут по кромке
	float spark = 0.0;
	for (int i = 0; i < 2; i++) {
		float ds = abs(fract(s - fract(time * 0.16 + float(i) * 0.5) + 0.5) - 0.5);
		spark += step(ds, 0.008) * step(abs(dist + px * 0.5), px);
	}
	// угольки поднимаются над клеткой и гаснут
	float mote = 0.0;
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		float life = fract(time * (0.3 + hash(fi) * 0.25) + hash(fi + 9.0));
		vec2 m = vec2((hash(fi + 3.0) - 0.5) * half_tile.x * 1.3, (hash(fi + 5.0) - 0.5) * half_tile.y * 0.7);
		m.y -= life * 30.0;
		m.x += sin(life * 6.2831 + fi) * 3.0;
		vec2 dm = abs(p - (floor(m / px) + 0.5) * px);
		mote += step(max(dm.x, dm.y), px * 0.5) * (1.0 - life) * 0.6;
	}
	float soft = floor((rim + inner + halo) * pulse * 7.0) / 7.0;   // мягкий свет — ступенями, как в пиксель-арте
	float glow = (line + corner) * pulse * edge_on + soft * max(edge_on, 0.35 * step(0.5, burst) * dust) + wave;
	float hot = clamp(spark + corner + wave * 0.6 + line * 0.2, 0.0, 1.0);
	float a = clamp(glow + spark * edge_on + mote * dust, 0.0, 1.0) * alpha;
	vec3 col = mix(edge_color.rgb, core_color.rgb, clamp(hot + mote, 0.0, 1.0));
	COLOR = vec4(col, a);
}
