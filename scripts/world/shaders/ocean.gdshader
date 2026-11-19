shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_always, specular_schlick_ggx;
// Океан архипелага: волны — до 8 волн Герстнера (та же формула в Ocean.wave_height),
// цвет и прозрачность по глубине (запечённая карта глубин), пена у берега и над
// отмелями, рябь из карт нормалей, блики/френель от солнца и неба.
// Высокое/ультра (use_fft): запечённая зацикленная FFT-зыбь (Texture2DArray кадров:
// R,G — наклоны, B — высота, A — пена по якобиану) — вершины у камеры, нормали
// на двух масштабах, барашки. Только чтение текстуры, без симуляции.
// Вид снизу (из-под воды): тёмная гладь с «окном Снеллиуса» над головой.

uniform float u_time = 0.0;          // время для текстур (с переносом раз в 2 ч)
uniform float water_level = 0.0;    // текущий уровень (прилив + нагон)
uniform float water_mean = 0.0;     // средний уровень, от которого запечена карта
uniform float wave_scale = 1.0;     // 1 — норма, 3 — шторм (уже учтён в амплитудах)
uniform float storm = 0.0;          // 0..1
uniform float rain_amount = 0.0;    // 0..1 — рябь от капель
uniform vec2 wind_dir = vec2(1.0, 0.0);
uniform float wind_k = 0.1;         // 0..1 сила ветра
// волны Герстнера: w_a = (dir.x, dir.z, амплитуда, k), w_b = (фаза, Q, двигает_вершины, 0)
uniform vec4 w_a[8];
uniform vec4 w_b[8];
uniform vec2 cam_xz = vec2(0.0);
uniform vec2 w_origin = vec2(0.0);   // опора фаз (рядом с камерой)
uniform float fade_start = 260.0;
uniform float fade_end = 600.0;
uniform vec2 fft_rot = vec2(1.0, 0.0);
uniform float amp_sum = 1.0;        // сумма амплитуд волн (для обрушения у берега)
uniform vec2 swell_dir = vec2(1.0, 0.0);

uniform sampler2D depth_map : filter_linear, repeat_disable;
uniform vec2 map_origin = vec2(0.0);
uniform vec2 map_size = vec2(1.0);
uniform sampler2D normal_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_tex : filter_linear_mipmap, repeat_enable;
uniform bool use_fft = false;
uniform bool detail_normals = true;
uniform sampler2DArray fft_tex : filter_linear_mipmap, repeat_enable;
uniform float fft_frames = 32.0;
uniform float fft_period = 8.0;
uniform float fft_tile = 24.0;
uniform float fft_slope = 0.3;

uniform vec3 shallow_color : source_color = vec3(0.30, 0.80, 0.78);
uniform vec3 mid_color : source_color = vec3(0.07, 0.42, 0.50);
uniform vec3 deep_color : source_color = vec3(0.02, 0.13, 0.22);
uniform vec3 night_tint : source_color = vec3(1.0);

varying vec3 wpos;
varying float depth_m;
varying float vfade;
varying float crest;
varying float jac;

const float G = 9.81;

float sample_depth(vec2 p) {
	vec2 uv = (p - map_origin) / map_size;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) return 30.0;
	vec4 s = texture(depth_map, uv);
	// R — грубая глубина 0..30 м, G — точная у берега −1..+3 м
	float coarse = s.r * 30.0;
	float fine = s.g * 4.0 - 1.0;
	float d = coarse > 2.8 ? coarse : fine;
	return d + (water_level - water_mean);
}

// Шоалинг (как Ocean.shoal): к берегу волна растёт до ×2, в зоне обрушения
// (d < 1.8 м) падает до 35 %; над пляжем (d < 0) — 35 % (гребни набегают на песок).
float shoal(float d) {
	float grow = clamp(pow(12.0 / max(d, 0.8), 0.35), 1.0, 2.0);
	float t = clamp(d / 1.8, 0.0, 1.0);
	return mix(0.35, grow, t * t * (3.0 - 2.0 * t));
}

// кадр зыби: (кадр0, кадр1, вес)
vec3 fft_frame(float t) {
	float ft = fract(t / fft_period) * fft_frames;
	float f0 = floor(ft);
	return vec3(f0, mod(f0 + 1.0, fft_frames), ft - f0);
}

vec4 fft_at_auto(vec2 p, vec3 fr) {
	// повернуть плитку так, чтобы её «ветер» совпал с текущим
	vec2 q = vec2(fft_rot.x * p.x + fft_rot.y * p.y, -fft_rot.y * p.x + fft_rot.x * p.y);
	vec2 uv = q / fft_tile;
	return mix(texture(fft_tex, vec3(uv, fr.x)), texture(fft_tex, vec3(uv, fr.y)), fr.z);
}

void vertex() {
	vec3 base = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = base.xz;
	float dist = length(p - cam_xz);
	vfade = 1.0 - smoothstep(fade_start, fade_end, dist);
	depth_m = sample_depth(p);
	float amp = shoal(depth_m) * vfade;
	float h = 0.0;
	vec2 disp = vec2(0.0);
	vec2 grad = vec2(0.0);
	float j = 0.0;
	float atot = 0.001;
	for (int i = 0; i < 8; i++) {
		vec4 a = w_a[i];
		vec4 b = w_b[i];
		if (b.z < 0.5 || a.z <= 0.0) continue;
		float ph = a.w * dot(a.xy, p - w_origin) - b.x;
		float s = sin(ph);
		float c = cos(ph);
		h += a.z * s;
		disp += a.xy * (b.y * a.z * c);
		grad += a.xy * (a.z * a.w * c);
		j += b.y * a.w * a.z * s;   // сжатие поверхности у гребня (якобиан Герстнера)
		atot += a.z;
	}
	crest = h / atot;
	jac = j * amp;
	VERTEX.xz += disp * amp;
	VERTEX.y = water_level + h * amp - MODEL_MATRIX[3].y;
	wpos = vec3(base.x + disp.x * amp, water_level + h * amp, base.z + disp.y * amp);
	NORMAL = normalize(vec3(-grad.x * amp, 1.0, -grad.y * amp));
}

// Нормаль от ВСЕХ волн (включая короткие, что не двигают вершины) — в каждом пикселе.
vec2 wave_grad_px(vec2 p, float amp) {
	vec2 g = vec2(0.0);
	for (int i = 0; i < 8; i++) {
		vec4 a = w_a[i];
		if (a.z <= 0.0) continue;
		float ph = a.w * dot(a.xy, p - w_origin) - w_b[i].x;
		g += a.xy * (a.z * a.w * cos(ph));
	}
	return g * amp;
}

// Высота аналитических волн в точке (без смещения Герстнера) — для пены за гребнем.
float wave_h_px(vec2 p) {
	float h = 0.0;
	for (int i = 0; i < 8; i++) {
		vec4 a = w_a[i];
		if (a.z <= 0.0 || w_b[i].z < 0.5) continue;
		h += a.z * sin(a.w * dot(a.xy, p - w_origin) - w_b[i].x);
	}
	return h;
}

// Все волны (и короткие, что не двигают вершины): x — сжатие у гребня (якобиан,
// 0..1 от максимума), y — нормированная высота.
vec2 crest_px(vec2 p) {
	float j = 0.0;
	float qs = 0.0001;
	float h = 0.0;
	float at = 0.0001;
	for (int i = 0; i < 8; i++) {
		vec4 a = w_a[i];
		if (a.z <= 0.0) continue;
		float q = max(w_b[i].y, 0.35);
		float s = sin(a.w * dot(a.xy, p - w_origin) - w_b[i].x);
		j += q * a.w * a.z * s;
		qs += q * a.w * a.z;
		h += a.z * s;
		at += a.z;
	}
	return vec2(j / qs, h / at);
}

// Рябь от капель: кольца в ячейках 0.7 м (одна выборка на пиксель, без текстур).
vec2 rain_rings(vec2 p, float t) {
	vec2 cell = floor(p / 0.7);
	vec2 f = fract(p / 0.7) - 0.5;
	float hsh = fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
	vec2 c = vec2(fract(hsh * 13.7) - 0.5, fract(hsh * 7.3) - 0.5) * 0.5;
	float ph = fract(t * 1.3 + hsh);
	vec2 d = f - c;
	float r = length(d);
	float ring = ph * 0.42;
	float w = sin((r - ring) * 60.0) * exp(-pow((r - ring) / 0.05, 2.0)) * (1.0 - ph);
	return (r > 0.0001 ? d / r : vec2(0.0)) * w;
}

// Прибой, привязанный к НАСТОЯЩИМ волнам: в зоне обрушения (мельче ~2.6 м,
// в шторм — дальше от берега) гребень ломается — белая рваная полоса вдоль гребня,
// за ней (со стороны моря) тающий шлейф пены; у кромки воды — тонкая пена заплеска.
// Только там, где вода есть (dl > 0) — на сухой песок пена не рисуется.
float breaking_foam(vec2 p, float d, float dl) {
	if (dl <= 0.0) return 0.0;
	// координаты рядом с камерой (w_origin) — без потери точности на больших X/Z;
	// шум вытянут ВДОЛЬ гребня (перпендикуляр направлению зыби): пена рвётся
	// нитями и кружевом, а не круглыми «пятнами»
	vec2 pr = p - w_origin;
	vec2 sd = normalize(swell_dir + vec2(0.0001));
	vec2 tg = vec2(-sd.y, sd.x);
	float along = dot(pr, tg);
	float across = dot(pr, sd);
	float n1 = texture(foam_tex, vec2(along * 0.06, across * 0.55) + vec2(u_time * 0.006, -u_time * 0.02)).r;
	float n2 = texture(foam_tex, vec2(along * 0.17, across * 1.4) + vec2(3.7, u_time * 0.035)).r;
	float n3 = texture(foam_tex, vec2(along * 0.45, across * 2.6) + vec2(1.3, -u_time * 0.05)).r;
	float lace = n1 * 0.5 + n2 * 0.35 + n3 * 0.3;
	// энергия обрушения: местная высота волны к глубине (H/d > ~0.8 — гребень ломается).
	// В штиль ломаются только у самой кромки, в шторм — далеко от берега.
	float a_loc = amp_sum * shoal(d);
	float energy = clamp(a_loc / 0.7, 0.25, 1.0);
	float brk_zone = smoothstep(0.55, 1.0, 2.0 * a_loc / max(d, 0.15))
			* (1.0 - smoothstep(0.9 + storm * 3.0, 1.6 + storm * 4.5, d));
	vec2 c0 = crest_px(p);
	// тонкая линия по самому гребню (сжатие + верх волны)
	float line = smoothstep(0.62, 0.9, c0.x) * smoothstep(0.25, 0.7, c0.y);
	line *= smoothstep(0.42, 0.7, lace);
	// шлейф: гребень прошёл здесь только что — редкое тающее кружево (нити)
	vec2 c1 = crest_px(p - sd * 1.4);
	vec2 c2 = crest_px(p - sd * 3.2);
	float tr = max(smoothstep(0.55, 0.85, c1.x) * 0.55, smoothstep(0.55, 0.85, c2.x) * 0.3);
	tr *= smoothstep(0.62, 0.82, n2 * 0.6 + n3 * 0.55);
	float f = max(line, tr) * brk_zone * energy;
	// тонкая кромка заплеска — ровно по краю воды (dl → 0), бегает вместе с волной
	float edge = smoothstep(0.0, 0.015, dl) * (1.0 - smoothstep(0.03, 0.09, dl));
	f = max(f, edge * smoothstep(0.45, 0.75, lace) * 0.55);
	return clamp(f, 0.0, 1.0);
}

void fragment() {
	vec2 p = wpos.xz;
	float d = sample_depth(p);
	float fft_foam = 0.0;
	// крупная форма от аналитических волн — попиксельно (гладко, без «ступенек» сетки)
	float amp_px = shoal(d) * vfade;
	// глубина воды в ЭТОЙ точке с учётом волны: > 0 — здесь вода (в т.ч. набежавший
	// на пляж заплеск), < 0 — сухо. Пена и прозрачность — только по ней.
	float dl = d + (wpos.y - water_level);
	vec2 wg = wave_grad_px(p, amp_px);
	vec3 n_waves = normalize(vec3(-wg.x, 1.0, -wg.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_waves, 0.0)).xyz);
	if (rain_amount > 0.02 && length(p - cam_xz) < 45.0) {
		vec2 rr = rain_rings(p, u_time) * rain_amount * 0.35;
		n_waves = normalize(n_waves + vec3(rr.x, 0.0, rr.y));
		NORMAL = normalize((VIEW_MATRIX * vec4(n_waves, 0.0)).xyz);
	}
	if (use_fft) {
		// зыбь на двух масштабах (второй повёрнут и сдвинут по времени — без повторов)
		vec3 fr = fft_frame(u_time);
		vec4 s1 = fft_at_auto(p, fr);
		vec2 p2 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p * 2.7 + vec2(7.3, 2.1);
		vec4 s2 = fft_at_auto(p2, fft_frame(u_time * 1.37 + 3.0));
		float calm = mix(0.4, 1.0, wind_k);
		vec2 sl = ((s1.rg * 2.0 - 1.0) * 1.0 + (s2.rg * 2.0 - 1.0) * 0.6) * calm * fft_slope * 1.6;
		vec3 nw = normalize(vec3(-sl.x, 1.0, -sl.y));
		// поверх нормали вершин (крупные волны)
		vec3 base_w = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		vec3 nn = normalize(vec3(base_w.x + nw.x, base_w.y, base_w.z + nw.z));
		NORMAL = normalize((VIEW_MATRIX * vec4(nn, 0.0)).xyz);
		// мелкая рябь поверх (одна выборка) — блёстки вблизи
		NORMAL_MAP = texture(normal_b, p * 0.16 - vec2(u_time * 0.02, -u_time * 0.007)).rgb;
		NORMAL_MAP_DEPTH = 0.4;
		fft_foam = smoothstep(0.45, 0.9, s1.a) * (0.15 + 0.85 * storm);
	} else if (detail_normals) {
		vec2 uv1 = p * 0.045 + vec2(u_time * 0.012, u_time * 0.008);
		vec2 uv2 = p * 0.11 - vec2(u_time * 0.018, -u_time * 0.006);
		vec3 n1 = texture(normal_a, uv1).rgb;
		vec3 n2 = texture(normal_b, uv2).rgb;
		NORMAL_MAP = normalize(mix(n1, n2, 0.5));
		NORMAL_MAP_DEPTH = mix(0.35, 1.0, wind_k);
	} else {
		NORMAL_MAP = texture(normal_a, p * 0.06 + vec2(u_time * 0.012, u_time * 0.008)).rgb;
		NORMAL_MAP_DEPTH = 0.5;
	}

	vec3 col = mix(shallow_color, mid_color, smoothstep(0.3, 4.5, d));
	col = mix(col, deep_color, smoothstep(4.5, 16.0, d));
	// шторм: вода темнее и серее (взмученная, под тучами)
	col = mix(col, vec3(0.05, 0.15, 0.17) * (0.7 + 0.3 * (1.0 - smoothstep(0.0, 6.0, d))), storm * 0.45);
	// форма волн читается цветом: гребни светятся бирюзой на просвет, впадины темнее
	float wave_vis = 0.35 + 0.65 * storm;
	vec3 n_w = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v_w = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float thin = smoothstep(0.1, 0.9, crest) * (0.4 + 0.6 * clamp(1.0 - dot(n_w, v_w), 0.0, 1.0));
	col = mix(col, vec3(0.08, 0.42, 0.40), thin * 0.55 * wave_vis * smoothstep(1.0, 5.0, d));
	col *= mix(1.0, 0.62, smoothstep(0.0, -0.8, crest) * wave_vis);
	// склон к свету чуть светлее (крупная форма волны видна даже под тучами)
	col *= 1.0 + 0.25 * storm * clamp(n_w.y - 0.85, -0.3, 0.15) * 4.0;
	// пена у берега и над отмелями
	float foam = (d < 2.6 + storm * 3.5 && d > -1.2) ? breaking_foam(p, d, dl) : 0.0;
	// барашки: гребни, где поверхность сжата (якобиан Герстнера), сильнее с ветром
	// барашки: на крутых гребнях, рвутся по ветру (вытянутая текстура), сильнее на подветренном склоне
	vec2 wpp = vec2(-wind_dir.y, wind_dir.x);
	float along_w = dot(p, wind_dir);
	float across_w = dot(p, wpp);
	float lace1 = texture(foam_tex, vec2(along_w * 0.035 - u_time * 0.03, across_w * 0.11)).r;
	float lace2 = texture(foam_tex, vec2(along_w * 0.09 - u_time * 0.05, across_w * 0.27) + 0.41).r;
	float lace = lace1 * 0.6 + lace2 * 0.55;
	// барашки — ломающиеся гребни: тонкие линии вдоль гребня с рваными краями
	// и тающим шлейфом пены по ветру; вблизи — мелкие и частые (короткие волны),
	// при сильном шторме сливаются в пятна
	float cap = 0.0;
	float cap_k = max(storm, wind_k * 0.6);
	if (cap_k > 0.05 && length(p - cam_xz) < 220.0) {
		float thr = mix(0.72, 0.42, cap_k);                 // чем сильнее ветер, тем больше гребней ломается
		float wdt = mix(0.05, 0.16, smoothstep(0.75, 1.0, storm));   // ширина линии; в сильный шторм — пятна
		vec2 c0 = crest_px(p);
		float line = smoothstep(thr, thr + wdt, c0.x) * smoothstep(-0.1, 0.4, c0.y);
		// рваный край: шум вытянут ВДОЛЬ гребня (поперёк ветра), мелкий — вдоль ветра
		float rag = texture(foam_tex, vec2(along_w * 0.42 - u_time * 0.05, across_w * 0.06)).r * 0.6
				+ texture(foam_tex, vec2(along_w * 0.9, across_w * 0.15) + 0.33).r * 0.5;
		line *= smoothstep(0.35, 0.7, rag + line * 0.15);
		// шлейф по ветру: гребень был здесь чуть раньше (сэмплы против ветра), тает
		vec2 c1 = crest_px(p - wind_dir * 1.6);
		vec2 c2 = crest_px(p - wind_dir * 3.4);
		float tr = max(smoothstep(thr, thr + wdt * 1.5, c1.x) * 0.6, smoothstep(thr, thr + wdt * 2.0, c2.x) * 0.35);
		tr *= smoothstep(0.55, 0.85, rag * 0.7 + lace * 0.5);
		cap = max(line, tr) * (1.0 - smoothstep(150.0, 220.0, length(p - cam_xz)));
	}
	foam = max(foam, cap * (0.25 + 0.75 * cap_k) * 0.95);
	// полосы пены вдоль ветра в шторм: тянутся за гребнем (след сорванной пены живёт
	// 10–25 м с подветренной стороны), тонкое кружево, а не «мазки»
	if (storm > 0.05) {
		float h_up = wave_h_px(p - wind_dir * 9.0);     // гребень, что прошёл здесь недавно
		float trail = smoothstep(0.2, 1.4, h_up);
		float st = texture(foam_tex, vec2(along_w * 0.008 - u_time * 0.012, across_w * 0.35)).r;
		float st2 = texture(foam_tex, vec2(along_w * 0.02 - u_time * 0.02, across_w * 0.9) + 0.27).r;
		// крупные пятна (низкая частота, повёрнуты) — полосы рвутся, не идут ровной штриховкой
		vec2 pr = mat2(vec2(0.83, 0.56), vec2(-0.56, 0.83)) * p;
		float patchm = smoothstep(0.45, 0.75, texture(foam_tex, pr * 0.0065 + vec2(u_time * 0.002, 0.0)).r);
		float streak = smoothstep(0.72, 0.95, st * 0.65 + st2 * 0.45) * patchm;
		float web = smoothstep(0.66, 0.92, lace2 + st2 * 0.3) * trail;
		foam = max(foam, (streak * 0.4 + web * 0.4) * storm * smoothstep(1.5, 5.0, d));
	}
	foam = max(foam, fft_foam * smoothstep(1.5, 4.0, d) * 0.55);
	col = mix(col, vec3(0.93, 0.96, 0.97), foam);
	if (!FRONT_FACING) {
		// снизу: тёмная толща, над головой — светлое «окно Снеллиуса»
		float cosv = abs(dot(normalize(VIEW), NORMAL));
		float win = smoothstep(0.62, 0.86, cosv);
		ALBEDO = mix(vec3(0.015, 0.09, 0.11), vec3(0.55, 0.80, 0.86), win) * night_tint;
		EMISSION = vec3(0.30, 0.48, 0.50) * win * night_tint;
		ROUGHNESS = 0.2;
		SPECULAR = 0.2;
		ALPHA = mix(0.96, 0.55, win);
	} else {
	ALBEDO = col * night_tint;
	ROUGHNESS = mix(mix(0.05, 0.14, storm), 0.6, foam);
	METALLIC = 0.0;
	SPECULAR = 0.55;
	// прозрачность: на мелководье видно дно
	float a = mix(0.38, 0.97, smoothstep(0.0, 6.0, d));
	// край воды — там, где кончается ВОЛНА (заплеск бегает по пляжу), а не средний уровень
	ALPHA = clamp(max(a, foam * 0.95), 0.0, 1.0) * smoothstep(-0.01, 0.07, dl);
	}
}
