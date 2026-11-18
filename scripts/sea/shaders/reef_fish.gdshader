shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
// Тропические рыбы фона (MultiMesh). Всё движение — здесь, процессор только
// задаёт параметры: стая плывёт по плавной кривой, рыбы у рифа кружат каждая у
// своего «дома», испуг (scare) — веерный разлёт от точки с возвратом.
// Меш рыбы: голова в -Z, хвост в +Z, длина 1. UV.x — от носа (0) к хвосту (1).
// COLOR.r — «спинность» (0 брюхо..1 спина), COLOR.g — глаз, COLOR.a — плавник.
// Экземпляр: origin — «дом» рыбы (мир = узел(x,0,z) + origin), базис — единичный.
// INSTANCE_CUSTOM: x — фаза 0..1, y — размах своей петли, z — размер (м), w — оттенок ±.
// Те же формулы повторены в reef_school.gd (fish_pos) — для сценок охоты.

global uniform float sea_time;
global uniform float sea_level;

uniform int mode = 0;               // 0 — стая, 1 — у рифа, 2 — одиночка (движет скрипт)
uniform vec3 roam = vec3(6.0, 0.8, 6.0);
uniform float swim_speed = 0.35;
uniform float lag = 0.12;
uniform float y_min = -100.0;
uniform vec4 scare = vec4(0.0, 0.0, 0.0, -1000.0);
uniform float scare_power = 4.0;
uniform int hidden = -1;
uniform float wiggle_amp = 0.07;
uniform float wiggle_freq = 8.0;
uniform float stun = 0.0;

uniform vec3 col_back : source_color = vec3(0.2, 0.4, 0.8);
uniform vec3 col_belly : source_color = vec3(0.9, 0.9, 0.85);
uniform vec3 col_fin : source_color = vec3(0.9, 0.8, 0.2);
uniform float fin_mix = 0.7;
uniform vec3 col_tail : source_color = vec3(0.9, 0.8, 0.2);
uniform float tail_u = 2.0;
uniform vec3 col_face : source_color = vec3(0.0);
uniform float face_u = -1.0;
uniform vec3 col_bar : source_color = vec3(0.05);
uniform float bar_count = 0.0;
uniform float bar_width = 0.3;
uniform vec2 bar_range = vec2(0.0, 1.0);
uniform vec3 col_stripe : source_color = vec3(0.1, 0.3, 0.9);
uniform float stripe_count = 0.0;
uniform float stripe_width = 0.3;
uniform vec2 stripe_range = vec2(0.0, 1.0);
uniform vec3 col_spot : source_color = vec3(0.1);
uniform float spot_scale = 0.0;
uniform float metal = 0.1;
uniform float glow = 0.1;
uniform float caustic_strength = 0.6;

varying vec3 wpos;
varying float v_shade;

vec3 path(float t, vec4 c, vec3 home) {
	if (mode == 0) {
		float tt = t * swim_speed - (home.z * 0.8 + home.x * 0.25) * lag;
		vec3 d = vec3(sin(tt * 0.37 + 1.3) + 0.4 * sin(tt * 0.11 + 0.5),
				sin(tt * 0.23 + 0.7),
				sin(tt * 0.29 + 0.4) + 0.4 * cos(tt * 0.13)) * roam;
		float ph = c.x * 6.2831;
		d += vec3(sin(t * 0.9 + ph * 3.0), 0.5 * sin(t * 0.7 + ph * 2.0), cos(t * 0.8 + ph * 5.0)) * 0.12 * c.y;
		return d;
	}
	if (mode == 1) {
		float ph = c.x * 6.2831;
		float sp = swim_speed * (0.7 + 0.6 * fract(c.x * 7.31));
		float tt = t * sp + ph * 3.0 + 0.8 * sin(t * 0.37 + ph);
		return vec3(sin(tt * 0.5 + ph), sin(tt * 0.31 + ph * 2.0) * 0.35, sin(tt * 0.41 + ph * 1.3)) * roam * c.y;
	}
	return vec3(0.0);
}

vec3 offset_at(float t, vec4 c, vec3 home) {
	vec3 d = path(t, c, home);
	vec3 wp = home + d;
	float sdt = t - scare.w;
	if (sdt > 0.0 && sdt < 9.0) {
		float f = (1.0 - exp(-sdt * 6.0)) * exp(-sdt * 0.55);
		vec3 aw = wp - scare.xyz;
		aw.y *= 0.35;
		float dist = length(aw) + 0.001;
		d += aw / dist * scare_power * f * clamp(1.4 - dist / 12.0, 0.0, 1.0);
	}
	float y = clamp(home.y + d.y, y_min + 0.25 + c.z * 0.3, sea_level - 0.35);
	d.y = y - home.y;
	return d;
}

void vertex() {
	vec4 c = INSTANCE_CUSTOM;
	float size = c.z > 0.0 ? c.z : 1.0;
	vec3 home = MODEL_MATRIX[3].xyz;
	float u = UV.x;
	vec3 v = VERTEX;
	if (mode == 2) {
		float tw = stun * sin(sea_time * 31.0) * 0.25;
		v.x += sin(u * 4.0 - sea_time * wiggle_freq * (1.0 - stun)) * wiggle_amp * u * u * 2.0 + tw * u;
		VERTEX = v * size;
	} else if (INSTANCE_ID == hidden) {
		VERTEX = vec3(0.0);
	} else {
		float t = sea_time;
		vec3 p0 = offset_at(t, c, home);
		vec3 p1 = offset_at(t + 0.08, c, home);
		vec3 dir = p1 - p0;
		float spd = length(dir) / 0.08;
		dir.y = clamp(dir.y, -0.4 * length(dir.xz) - 0.001, 0.4 * length(dir.xz) + 0.001);
		vec3 fwd = length(dir) > 0.00001 ? normalize(dir) : vec3(0.0, 0.0, -1.0);
		vec3 zb = -fwd;
		vec3 xb = normalize(cross(vec3(0.0, 1.0, 0.0), zb) + vec3(0.0001, 0.0, 0.0));
		vec3 yb = cross(zb, xb);
		mat3 B = mat3(xb, yb, zb);
		float beat = wiggle_freq * (0.6 + clamp(spd / max(size, 0.05) * 0.25, 0.0, 2.5));
		v.x += sin(u * 4.0 - t * beat - c.x * 6.2831) * wiggle_amp * u * u * 2.0;
		VERTEX = p0 + B * (v * size);
		NORMAL = B * NORMAL;
	}
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_shade = 1.0 + (c.w - 0.5) * 0.25;
}

float caus(vec2 p, float t) {
	vec2 q = p + vec2(sin(p.y * 1.7 + t * 0.9), cos(p.x * 1.3 - t * 0.7)) * 0.6;
	float a = sin(q.x * 2.1 + t) * sin(q.y * 2.3 - t * 0.8);
	vec2 r = p * 1.6 + vec2(cos(p.y * 1.1 - t * 0.6), sin(p.x * 1.4 + t * 0.5)) * 0.8;
	float b = sin(r.x * 1.9 - t * 0.7) * sin(r.y * 2.2 + t * 0.9);
	return pow(clamp(1.0 - abs(a + b) * 0.5, 0.0, 1.0), 7.0);
}

void fragment() {
	if (dot(NORMAL, VIEW) < 0.0) {
		NORMAL = -NORMAL;
	}
	float u = UV.x;
	float dv = COLOR.r;
	vec3 col = mix(col_belly, col_back, smoothstep(0.28, 0.72, dv));
	if (stripe_count > 0.0) {
		float s = abs(fract(dv * stripe_count) - 0.5) * 2.0;
		float m = smoothstep(stripe_width, stripe_width * 0.55, s) * step(stripe_range.x, dv) * step(dv, stripe_range.y)
				* step(0.12, u) * step(u, 0.86);
		col = mix(col, col_stripe, m);
	}
	if (spot_scale > 0.0) {
		vec2 g = vec2(u * spot_scale, dv * spot_scale * 0.45);
		vec2 f = fract(g) - 0.5;
		float h = fract(sin(dot(floor(g), vec2(12.9898, 78.233))) * 43758.5453);
		float m = smoothstep(0.32, 0.18, length(f + (h - 0.5) * 0.3));
		col = mix(col, col_spot, m * 0.85);
	}
	if (bar_count > 0.0) {
		float uu = (u - bar_range.x) / max(bar_range.y - bar_range.x, 0.001);
		float s = abs(fract(uu * bar_count) - 0.5) * 2.0;
		float m = smoothstep(bar_width, bar_width * 0.75, 1.0 - s) * step(0.0, uu) * step(uu, 1.0);
		col = mix(col, col_bar, m);
	}
	col = mix(col, col_face, step(u, face_u) * step(0.0, face_u));
	col = mix(col, col_tail, step(tail_u, u));
	col = mix(col, col_fin, COLOR.a * fin_mix);
	col = mix(col, vec3(0.02, 0.02, 0.03), COLOR.g);
	col *= v_shade;
	float depth = sea_level - wpos.y;
	float under = step(0.0, depth);
	float k = caustic_strength * clamp(1.0 - depth / 10.0, 0.0, 1.0) * under * smoothstep(0.3, 0.9, NORMAL.y * 0.5 + 0.5);
	float cs = caus(wpos.xz * 0.85, sea_time * 0.9);
	vec3 absorb = mix(vec3(1.0), vec3(0.7, 0.9, 0.97), clamp(depth / 10.0, 0.0, 1.0) * under);
	ALBEDO = col * absorb * (1.0 + cs * k);
	ROUGHNESS = mix(0.4, 0.22, metal);
	SPECULAR = 0.6;
	METALLIC = metal;
	EMISSION = col * glow * under;
}
