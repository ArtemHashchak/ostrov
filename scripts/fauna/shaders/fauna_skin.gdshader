shader_type spatial;
// Кожа/мех/чешуя/панцирь животных.
// COLOR вершин: r — спинная зона (1 = спина, 0 = брюхо), g — маска узора/детали,
// b — коэффициент изгиба (0 у головы → 1 к хвосту), a — маска крыльев (взмах).
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 back_color : source_color = vec3(0.35, 0.27, 0.2);
uniform vec3 belly_color : source_color = vec3(0.72, 0.62, 0.5);
uniform vec3 pattern_color : source_color = vec3(0.12, 0.1, 0.08);
uniform vec3 detail_color : source_color = vec3(0.9, 0.85, 0.7);
uniform float pattern_kind = 0.0;   // 0 — нет, 1 — пятна, 2 — полосы поперёк, 3 — ромбы (змея), 4 — щитки (черепаха/крокодил), 5 — мех
uniform float pattern_scale = 6.0;
uniform float pattern_amount = 0.6;
uniform float body_length = 1.0;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.7;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float sheen : hint_range(0.0, 1.0) = 0.0;   // мех — мягкий отсвет по краю
// Анимация изгиба (змея, крокодил, ящерицы): волна вдоль тела (ось Z, нос в -Z).
uniform float bend_amp = 0.0;
uniform float bend_freq = 2.0;
uniform float bend_speed = 3.0;
uniform float bend_phase = 0.0;
uniform float bend_static = 0.0;   // постоянный изгиб (поворот хвоста)
// Взмах крыльев (птицы, летучие мыши): поворот по маске a вокруг оси Z.
uniform float flap = 0.0;          // -1..1 — фаза взмаха (задаёт скрипт)
uniform float wing_span = 0.4;

varying float v_back;
varying float v_pat;
varying vec3 v_obj;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) { float a = 0.5, s = 0.0; for (int i = 0; i < 4; i++) { s += a * vnoise(p); p *= 2.07; a *= 0.5; } return s; }

void vertex() {
	vec3 v = VERTEX;
	float b = COLOR.b;
	if (bend_amp > 0.0001 || abs(bend_static) > 0.0001) {
		float t = (v.z / max(body_length, 0.01)) * bend_freq * 6.2831 - TIME * bend_speed + bend_phase;
		float off = sin(t) * bend_amp * b * body_length + bend_static * b * b * body_length;
		v.x += off;
	}
	if (COLOR.a > 0.001) {
		float side = sign(v.x);
		float ang = flap * 1.0 * COLOR.a;
		float r = abs(v.x);
		v.y += sin(ang) * r * side * side;
		v.x = side * cos(ang) * r;
	}
	VERTEX = v;
	v_back = COLOR.r;
	v_pat = COLOR.g;
	v_obj = VERTEX;
}

void fragment() {
	vec3 base = mix(belly_color, back_color, smoothstep(0.0, 1.0, v_back));
	float p = 0.0;
	vec2 uv = v_obj.xz * pattern_scale + vec2(v_obj.y * 0.5 * pattern_scale);
	if (pattern_kind > 0.5 && pattern_kind < 1.5) {
		p = smoothstep(0.62, 0.72, fbm(uv * 0.9));
	} else if (pattern_kind > 1.5 && pattern_kind < 2.5) {
		p = smoothstep(0.55, 0.75, sin(v_obj.z * pattern_scale * 3.0 + fbm(uv) * 3.0) * 0.5 + 0.5);
	} else if (pattern_kind > 2.5 && pattern_kind < 3.5) {
		vec2 q = vec2(v_obj.z * pattern_scale * 2.2, v_obj.x * pattern_scale * 2.6 + v_obj.y * pattern_scale * 1.3);
		vec2 f = abs(fract(q) - 0.5);
		p = smoothstep(0.32, 0.4, f.x + f.y) * 0.8 + smoothstep(0.5, 0.75, fbm(q)) * 0.2;
	} else if (pattern_kind > 3.5 && pattern_kind < 4.5) {
		vec2 q = vec2(v_obj.z, v_obj.x + v_obj.y) * pattern_scale * 2.0;
		q.x += floor(q.y) * 0.5;                       // щитки вразбежку
		q += vec2(fbm(q * 0.7), fbm(q * 0.7 + 3.1)) * 0.25; // неровные края
		vec2 f = abs(fract(q) - 0.5);
		vec2 cell = floor(q);
		// тёмные швы между щитками + разный тон самих щитков
		p = smoothstep(0.41, 0.49, max(f.x, f.y)) * 0.8 + hash(cell) * 0.3;
	} else if (pattern_kind > 4.5) {
		p = fbm(uv * 3.0) * 0.8;
	}
	p *= pattern_amount * (0.35 + 0.65 * smoothstep(0.1, 0.6, v_back));
	vec3 col = mix(base, pattern_color, clamp(p, 0.0, 1.0));
	col = mix(col, detail_color, clamp(v_pat, 0.0, 1.0));
	// мелкая неравномерность (поры, шерсть)
	float grain = fbm(v_obj.xz * 40.0 + v_obj.y * 30.0);
	col *= 0.86 + 0.24 * grain;
	ALBEDO = col;
	ROUGHNESS = clamp(roughness_base - wetness * 0.45 + (grain - 0.5) * 0.1, 0.05, 1.0);
	SPECULAR = 0.35 + wetness * 0.4;
	if (sheen > 0.0) {
		float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
		EMISSION = base * rim * sheen * 0.25;
	}
}
