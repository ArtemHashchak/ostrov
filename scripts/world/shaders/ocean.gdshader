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
	float shoal = clamp(depth_m / 3.0, 0.15, 1.0);
	float amp = shoal * vfade;
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

// Прибой: тонкие кружевные линии пены идут к берегу с фазой набегающей волны,
// рвутся шумом вдоль берега, за линией — редкое «кружево», у самой кромки — заплеск.
// Направление к берегу — градиент запечённой карты глубин (только у берега, d < 2.8 м).
float shore_foam(vec2 p, float d) {
	float e = 2.0;
	vec2 g = vec2(sample_depth(p + vec2(e, 0.0)) - sample_depth(p - vec2(e, 0.0)),
			sample_depth(p + vec2(0.0, e)) - sample_depth(p - vec2(0.0, e)));
	vec2 off = normalize(g + vec2(0.0001, 0.0));     // от берега в море
	vec2 tng = vec2(-off.y, off.x);
	float along = dot(p, tng);
	float across = dot(p, off);
	// шум вдоль берега: растянутые полосы (разрывы линии)
	float n1 = texture(foam_tex, vec2(along * 0.045, across * 0.35) + vec2(u_time * 0.004, 0.0)).r;
	float n2 = texture(foam_tex, vec2(along * 0.11 + 3.7, across * 0.9) - vec2(0.0, u_time * 0.02)).r;
	float lace_tex = n1 * 0.55 + n2 * 0.6;
	float slow = sin(along * 0.035 + u_time * 0.05) * 0.12;   // разная фаза по берегу
	float f = 0.0;
	for (int k = 0; k < 3; k++) {
		float s = fract(u_time / 7.5 + float(k) / 3.0 + slow);
		float front = mix(1.25 + storm * 1.2, -0.05 - storm * 0.35, s * s * (3.0 - 2.0 * s));   // набег; в шторм — дальше на берег
		float w = 0.025 + 0.035 * clamp(front, 0.0, 1.2);
		float line = exp(-pow((d - front) / w, 2.0));
		// линия рождается у отмели, ярче всего у самого берега, гаснет в конце набега
		float amp = smoothstep(1.3, 0.55, front) * (1.0 - smoothstep(0.8, 1.0, s)) * 0.85;
		float broken = smoothstep(0.5, 0.85, lace_tex + line * 0.2);
		f += line * amp * broken;
		// след за линией: редкое кружево, тает
		float behind = smoothstep(front + 0.05, front + 0.6, d) * (1.0 - smoothstep(front + 0.6, front + 1.4, d));
		f += behind * smoothstep(0.78, 0.95, lace_tex) * amp * (1.0 - s) * 0.5;
	}
	// заплеск у кромки
	float swash = 0.06 + 0.1 * (0.5 + 0.5 * sin(u_time * 0.84 + along * 0.06));
	f += exp(-pow((d - swash) / 0.045, 2.0)) * smoothstep(0.3, 0.7, n2 + 0.25) * 0.8;
	return clamp(f, 0.0, 1.0) * (1.0 - smoothstep(0.9 + storm * 1.2, 1.5 + storm * 1.5, d));
}

void fragment() {
	vec2 p = wpos.xz;
	float d = sample_depth(p);
	float fft_foam = 0.0;
	// крупная форма от аналитических волн — попиксельно (гладко, без «ступенек» сетки)
	float amp_px = clamp(d / 3.0, 0.15, 1.0) * vfade;
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
	col = mix(col, vec3(0.05, 0.13, 0.15) * (0.6 + 0.4 * (1.0 - smoothstep(0.0, 6.0, d))), storm * 0.6);
	// пена у берега и над отмелями
	float f1 = texture(foam_tex, p * 0.22 + vec2(u_time * 0.03, 0.0)).r;
	float f2 = texture(foam_tex, p * 0.13 - vec2(0.0, u_time * 0.025)).r;
	float foam = (d < 1.5 + storm * 1.5 && d > -0.4 - storm * 0.4) ? shore_foam(p, d) : 0.0;
	// барашки: гребни, где поверхность сжата (якобиан Герстнера), сильнее с ветром
	float cap = smoothstep(0.45, 0.85, jac + crest * 0.25) * smoothstep(0.35, 0.8, f1 * 0.55 + f2 * 0.55) * smoothstep(0.0, 0.5, crest);
	foam = max(foam, cap * (0.15 + 0.85 * max(storm, wind_k * 0.6)) * 0.9);
	// полосы пены вдоль ветра в шторм (сорванная с гребней пена)
	if (storm > 0.05) {
		vec2 wpp = vec2(-wind_dir.y, wind_dir.x);
		vec2 suv = vec2(dot(p, wind_dir) * 0.012 - u_time * 0.02, dot(p, wpp) * 0.16);
		float st = texture(foam_tex, suv).r * texture(foam_tex, suv * vec2(2.3, 0.7) + 0.37).r;
		// только на передних склонах гребней, мягко — длинные рваные полосы, а не «мазки»
		float on_crest = smoothstep(-0.1, 0.6, crest);
		float lace = texture(foam_tex, p * 0.31 + vec2(u_time * 0.04, 0.0)).r;
		foam = max(foam, smoothstep(0.3, 0.75, st) * smoothstep(0.35, 0.7, lace) * on_crest * storm * 0.4 * smoothstep(1.5, 5.0, d));
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
	ROUGHNESS = mix(0.05, 0.6, foam);
	METALLIC = 0.0;
	SPECULAR = 0.55;
	// прозрачность: на мелководье видно дно
	float a = mix(0.38, 0.97, smoothstep(0.0, 6.0, d));
	ALPHA = clamp(max(a, foam * 0.95), 0.0, 1.0) * mix(1.0, 0.0, 1.0 - smoothstep(-0.3, 0.02, d));
	}
}
