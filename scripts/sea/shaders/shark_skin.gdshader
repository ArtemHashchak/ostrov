shader_type spatial;
// Кожа акулы: тёмная спина / светлое брюхо (контртень), «мокрый» блеск,
// полосы тигровой акулы, тёмные кончики плавников, изгиб тела при плавании.
// COLOR.r — «спинность» (0 брюхо … 1 спина), COLOR.g — метки (1 норм., <1 темнее),
// COLOR.b — «плавник» (1 — кончик плавника).
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 back_color : source_color = vec3(0.33, 0.38, 0.42);
uniform vec3 belly_color : source_color = vec3(0.86, 0.86, 0.82);
uniform float line_softness = 0.18;   // мягкость границы спина/брюхо
uniform float line_height = 0.42;     // где проходит граница
uniform float stripes = 0.0;          // сила полос (тигровая)
uniform float tip_dark = 0.0;         // тёмные кончики плавников (рифовая)
uniform float body_length = 2.0;
uniform float swim_phase = 0.0;       // фаза волны (накопленная, чтобы скорость меняла частоту плавно)
uniform float swim_amp = 0.08;        // амплитуда изгиба (доля длины)
uniform float turn_bend = 0.0;        // изгиб в повороте (-1..1)
uniform float wetness = 0.65;

varying vec3 v_local;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	v_local = VERTEX;
	// t: 0 — нос (-Z), 1 — конец хвоста (+Z)
	float t = clamp((VERTEX.z / body_length) + 0.5, 0.0, 1.0);
	float w = pow(t, 1.7);
	float wave = sin(t * 5.2 - swim_phase);
	float dx = wave * w * swim_amp * body_length;
	dx += turn_bend * t * t * body_length * 0.18;
	// голова чуть «рыскает» в противофазе — естественнее
	dx -= sin(-swim_phase) * (1.0 - t) * swim_amp * body_length * 0.15;
	VERTEX.x += dx;
	// поворот нормали по производной изгиба
	float slope = cos(t * 5.2 - swim_phase) * 5.2 * w * swim_amp + turn_bend * 2.0 * t * 0.18;
	NORMAL = normalize(NORMAL + vec3(0.0, 0.0, -NORMAL.x * slope));
}

void fragment() {
	float dorsal = COLOR.r;
	float marks = COLOR.g;
	float fin_tip = COLOR.b;
	float k = smoothstep(line_height - line_softness, line_height + line_softness, dorsal);
	// неровная граница контртени
	k = clamp(k + (vnoise(v_local.zx * 3.0) - 0.5) * 0.25 * line_softness * 4.0, 0.0, 1.0);
	vec3 col = mix(belly_color, back_color, k);
	// мелкая пятнистость кожи
	float n = vnoise(v_local.zy * 9.0) * 0.5 + vnoise(v_local.zx * 23.0) * 0.5;
	col *= 0.92 + n * 0.12;
	// полосы тигровой акулы — только на спине
	if (stripes > 0.0) {
		float s = sin(v_local.z * 16.0 / max(body_length * 0.25, 0.1) + vnoise(v_local.zy * 2.5) * 3.0);
		float band = smoothstep(0.7, 0.92, s) * smoothstep(0.35, 0.7, dorsal);
		col = mix(col, col * 0.45, band * stripes);
	}
	col = mix(col, vec3(0.05, 0.05, 0.06), fin_tip * tip_dark);
	col *= marks;
	ALBEDO = col;
	ROUGHNESS = mix(0.55, 0.22, wetness) + n * 0.08;
	SPECULAR = 0.55;
	// лёгкий френель «мокрой» поверхности
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = vec3(0.06, 0.09, 0.11) * fres * wetness;
}
