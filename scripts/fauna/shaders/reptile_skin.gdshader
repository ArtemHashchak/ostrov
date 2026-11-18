shader_type spatial;
// Кожа рептилий: fauna_skin + деформация по «позвоночнику» (змея, крокодил, ящерицы),
// челюсть крокодила, язык, голова черепахи. Параметры fauna_skin сохранены.
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
// --- позвоночник: 16 точек в пространстве модели, от носа (spine_z0) к хвосту (spine_z1) ---
uniform float spine_on = 0.0;
uniform vec3 spine_pts[16];
uniform float spine_z0 = -0.5;
uniform float spine_z1 = 0.5;
uniform float spine_y = 0.0;      // высота осевой линии тела в покое
// --- язык: вершины с z < tongue_z — язык; tongue_out 0 — втянут, 1 — высунут ---
uniform float tongue_z = -100.0;
uniform float tongue_out = 1.0;
// --- челюсть (крокодил): нижняя челюсть ниже линии рта, впереди шарнира ---
uniform float jaw_open = 0.0;     // рад
uniform vec2 jaw_hinge = vec2(0.21, -1.0);   // (y, z)
uniform float jaw_slope = 0.05;   // наклон линии рта dy/dz
uniform float jaw_y_off = -0.005;
// --- голова черепахи: вершины кожи (COLOR.g > 0.5) впереди neck_z ---
uniform float head_on = 0.0;
uniform vec3 neck_pivot = vec3(0.0, 0.15, -0.42);
uniform vec3 head_rot = vec3(0.0);  // x — кивок, y — поворот
uniform float head_ext = 0.0;       // + выдвинуть вперёд, − втянуть

varying float v_back;
varying float v_pat;
varying vec3 v_obj;
varying float v_mouth;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) { float a = 0.5, s = 0.0; for (int i = 0; i < 4; i++) { s += a * vnoise(p); p *= 2.07; a *= 0.5; } return s; }

mat3 rot_x(float a) { float c = cos(a), s = sin(a); return mat3(vec3(1,0,0), vec3(0,c,s), vec3(0,-s,c)); }
mat3 rot_y(float a) { float c = cos(a), s = sin(a); return mat3(vec3(c,0,-s), vec3(0,1,0), vec3(s,0,c)); }

void vertex() {
	vec3 rest = VERTEX;
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	float b = COLOR.b;
	v_mouth = 0.0;
	// язык: втягивается к кончику морды
	if (v.z < tongue_z) {
		v.z = mix(tongue_z + 0.004, v.z, tongue_out);
	}
	// челюсть
	if (jaw_open > 0.0005 && COLOR.g < 0.9) {
		float line = jaw_hinge.x + (v.z - jaw_hinge.y) * jaw_slope + jaw_y_off;
		float below = 1.0 - smoothstep(line - 0.012, line + 0.012, v.y);
		float front = smoothstep(jaw_hinge.y + 0.12, jaw_hinge.y - 0.05, v.z);
		float w = below * front;
		if (w > 0.0) {
			float a = jaw_open * w;
			vec2 r = vec2(v.y - jaw_hinge.x, v.z - jaw_hinge.y);
			float c = cos(a), s = sin(a);
			v.y = jaw_hinge.x + r.x * c + r.y * s;
			v.z = jaw_hinge.y + r.y * c - r.x * s;
			n = rot_x(-a) * n;
			v_mouth = w;
		}
	}
	// голова черепахи
	if (head_on > 0.5 && COLOR.g > 0.5 && v.z < neck_pivot.z + 0.02) {
		float k = smoothstep(neck_pivot.z + 0.02, neck_pivot.z - 0.08, v.z);
		mat3 R = rot_y(head_rot.y * k) * rot_x(head_rot.x * k);
		v = neck_pivot + R * (v - neck_pivot) + vec3(0.0, 0.0, -head_ext * k);
		n = R * n;
	}
	if (spine_on > 0.5) {
		float u = clamp((rest.z - spine_z0) / (spine_z1 - spine_z0), 0.0, 1.0) * 15.0;
		int i = int(min(floor(u), 14.0));
		float f = u - float(i);
		vec3 p0 = spine_pts[i];
		vec3 p1 = spine_pts[i + 1];
		vec3 t0 = p1 - p0;
		vec3 ta = (i > 0) ? (p0 - spine_pts[i - 1]) : t0;
		vec3 tb = (i < 14) ? (spine_pts[i + 2] - p1) : t0;
		vec3 T = normalize(mix(normalize(ta + t0), normalize(t0 + tb), f) + vec3(0.0, 0.0, 1e-5));
		vec3 X = normalize(cross(vec3(0.0, 1.0, 0.0), T) + vec3(1e-5, 0.0, 0.0));
		vec3 Y = cross(T, X);
		vec3 P = mix(p0, p1, f);
		float zr = (spine_z0 + (spine_z1 - spine_z0) * (u / 15.0));
		v = P + X * v.x + Y * (v.y - spine_y) + T * (v.z - zr);
		n = X * n.x + Y * n.y + T * n.z;
	} else if (bend_amp > 0.0001 || abs(bend_static) > 0.0001) {
		float t = (v.z / max(body_length, 0.01)) * bend_freq * 6.2831 - TIME * bend_speed + bend_phase;
		float off = sin(t) * bend_amp * b * body_length + bend_static * b * b * body_length;
		v.x += off;
	}
	VERTEX = v;
	NORMAL = n;
	v_back = COLOR.r;
	v_pat = COLOR.g;
	v_obj = rest;
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
	float mb = clamp(v_mouth * (1.0 - v_mouth) * 4.0, 0.0, 1.0) * clamp(jaw_open * 4.0, 0.0, 1.0);
	col = mix(col, vec3(0.5, 0.26, 0.24), mb);
	ALBEDO = col;
	ROUGHNESS = clamp(roughness_base - wetness * 0.45 + (grain - 0.5) * 0.1, 0.05, 1.0);
	SPECULAR = 0.35 + wetness * 0.4;
	if (sheen > 0.0) {
		float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
		EMISSION = base * rim * sheen * 0.25;
	}
}
