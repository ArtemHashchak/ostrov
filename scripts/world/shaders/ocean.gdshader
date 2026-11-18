shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_always, specular_schlick_ggx;
// Океан архипелага: волны — сумма 4 синусоид (та же формула в Ocean.wave_height),
// цвет и прозрачность по глубине (запечённая карта глубин), пена у берега и над
// отмелями, рябь из карт нормалей, блики/френель от солнца и неба.
// Высокое/ультра (use_fft): запечённая зацикленная FFT-зыбь (Texture2DArray кадров:
// R,G — наклоны, B — высота, A — пена по якобиану) — вершины у камеры, нормали
// на двух масштабах, барашки. Только чтение текстуры, без симуляции.
// Вид снизу (из-под воды): тёмная гладь с «окном Снеллиуса» над головой.

uniform float u_time = 0.0;
uniform float water_level = 0.0;    // текущий уровень (прилив)
uniform float water_mean = 0.0;     // средний уровень, от которого запечена карта
uniform float wave_scale = 1.0;     // 1 — штиль/норма, 3 — шторм
uniform vec4 wave_a = vec4(1.0, 0.3, 0.18, 22.0);   // dir.xy, амплитуда, длина
uniform vec4 wave_b = vec4(0.6, 1.0, 0.12, 13.0);
uniform vec4 wave_c = vec4(-0.4, 0.9, 0.07, 7.5);
uniform vec4 wave_d = vec4(0.9, -0.5, 0.05, 4.5);
uniform vec2 cam_xz = vec2(0.0);
uniform float fade_start = 260.0;
uniform float fade_end = 600.0;

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
uniform float fft_amp = 0.32;
uniform float fft_slope = 0.3;
uniform vec2 fft_fade = vec2(70.0, 150.0);

uniform vec3 shallow_color : source_color = vec3(0.30, 0.80, 0.78);
uniform vec3 mid_color : source_color = vec3(0.07, 0.42, 0.50);
uniform vec3 deep_color : source_color = vec3(0.02, 0.13, 0.22);
uniform vec3 night_tint : source_color = vec3(1.0);

varying vec3 wpos;
varying float depth_m;
varying float vfade;
varying float crest;
varying float fft_near;

const float G = 9.81;

float wave_one(vec4 w, vec2 p, float t, out vec2 grad) {
	vec2 d = normalize(w.xy);
	float k = 6.2831853 / w.w;
	float om = sqrt(G * k);
	float ph = k * dot(d, p) - om * t;
	grad = d * (w.z * k * cos(ph));
	return w.z * sin(ph);
}

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

vec4 fft_at(vec2 p, vec3 fr, float lod) {
	vec2 uv = p / fft_tile;
	vec4 a = textureLod(fft_tex, vec3(uv, fr.x), lod);
	vec4 b = textureLod(fft_tex, vec3(uv, fr.y), lod);
	return mix(a, b, fr.z);
}

vec4 fft_at_auto(vec2 p, vec3 fr) {
	vec2 uv = p / fft_tile;
	return mix(texture(fft_tex, vec3(uv, fr.x)), texture(fft_tex, vec3(uv, fr.y)), fr.z);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = wpos.xz;
	float dist = length(p - cam_xz);
	vfade = 1.0 - smoothstep(fade_start, fade_end, dist);
	depth_m = sample_depth(p);
	float shoal = clamp(depth_m / 3.0, 0.15, 1.0);
	vec2 g1, g2, g3, g4;
	float h = wave_one(wave_a, p, u_time, g1) + wave_one(wave_b, p, u_time, g2)
		+ wave_one(wave_c, p, u_time, g3) + wave_one(wave_d, p, u_time, g4);
	float amp = wave_scale * shoal * vfade;
	crest = h / 0.42;
	vec2 grad = (g1 + g2 + g3 + g4) * amp;
	fft_near = 0.0;
	if (use_fft) {
		float ff = 1.0 - smoothstep(fft_fade.x, fft_fade.y, dist);
		fft_near = ff;
		if (ff > 0.0) {
			vec4 s = fft_at(p, fft_frame(u_time), 0.0);
			h += (s.b * 2.0 - 1.0) * fft_amp * ff;
			grad += (s.rg * 2.0 - 1.0) * fft_slope * ff * amp;
		}
	}
	VERTEX.y = water_level + h * amp - (MODEL_MATRIX[3].y);
	wpos.y = water_level + h * amp;
	NORMAL = normalize(vec3(-grad.x, 1.0, -grad.y));
}

void fragment() {
	vec2 p = wpos.xz;
	float d = sample_depth(p);
	float fft_foam = 0.0;
	if (use_fft) {
		// зыбь на двух масштабах (второй повёрнут и сдвинут по времени — без повторов)
		vec3 fr = fft_frame(u_time);
		vec4 s1 = fft_at_auto(p, fr);
		vec2 p2 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p * 2.7 + vec2(7.3, 2.1);
		vec4 s2 = fft_at_auto(p2, fft_frame(u_time * 1.37 + 3.0));
		float calm = mix(0.55, 1.0, clamp(wave_scale - 0.6, 0.0, 1.0));
		vec2 sl = ((s1.rg * 2.0 - 1.0) * 1.0 + (s2.rg * 2.0 - 1.0) * 0.6) * calm * fft_slope * 1.6;
		vec3 nw = normalize(vec3(-sl.x, 1.0, -sl.y));
		// поверх нормали вершин (крупные волны)
		vec3 base_w = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		vec3 nn = normalize(vec3(base_w.x + nw.x, base_w.y, base_w.z + nw.z));
		NORMAL = normalize((VIEW_MATRIX * vec4(nn, 0.0)).xyz);
		// мелкая рябь поверх (одна выборка) — блёстки вблизи
		NORMAL_MAP = texture(normal_b, p * 0.16 - vec2(u_time * 0.02, -u_time * 0.007)).rgb;
		NORMAL_MAP_DEPTH = 0.4;
		fft_foam = smoothstep(0.45, 0.9, s1.a) * (0.25 + 0.75 * clamp((wave_scale - 0.8) / 1.2, 0.0, 1.0));
	} else if (detail_normals) {
		vec2 uv1 = p * 0.045 + vec2(u_time * 0.012, u_time * 0.008);
		vec2 uv2 = p * 0.11 - vec2(u_time * 0.018, -u_time * 0.006);
		vec3 n1 = texture(normal_a, uv1).rgb;
		vec3 n2 = texture(normal_b, uv2).rgb;
		NORMAL_MAP = normalize(mix(n1, n2, 0.5));
		NORMAL_MAP_DEPTH = mix(0.35, 0.9, clamp(wave_scale - 0.5, 0.0, 1.0));
	} else {
		NORMAL_MAP = texture(normal_a, p * 0.06 + vec2(u_time * 0.012, u_time * 0.008)).rgb;
		NORMAL_MAP_DEPTH = 0.5;
	}

	vec3 col = mix(shallow_color, mid_color, smoothstep(0.3, 4.5, d));
	col = mix(col, deep_color, smoothstep(4.5, 16.0, d));
	// пена у берега и над отмелями
	float f1 = texture(foam_tex, p * 0.22 + vec2(u_time * 0.03, 0.0)).r;
	float f2 = texture(foam_tex, p * 0.13 - vec2(0.0, u_time * 0.025)).r;
	float shore = 1.0 - smoothstep(0.0, 0.55 + 0.25 * sin(u_time * 0.9 + p.x * 0.3 + p.y * 0.2), d);
	float foam = clamp(shore * (f1 * 0.7 + f2 * 0.6) * 1.6, 0.0, 1.0);
	// барашки в шторм
	float storm = clamp((wave_scale - 1.3) / 1.5, 0.0, 1.0);
	float cap = smoothstep(0.35, 0.8, crest) * smoothstep(0.25, 0.75, f1 * 0.6 + f2 * 0.6);
	foam = max(foam, cap * storm * 0.85);
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
