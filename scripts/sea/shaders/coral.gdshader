shader_type spatial;
render_mode cull_disabled;
// Кораллы, губки, водоросли, камни рифа (MultiMesh).
// Цвет: вершинный цвет × INSTANCE_CUSTOM.rgb (оттенок экземпляра); INSTANCE_CUSTOM.a — фаза покачивания.
// UV.y — высота точки над основанием (0..1): водоросли и веера качаются сильнее у верхушки.
// Каустика: световая сетка от волн на всём, что под водой, слабеет с глубиной.

#include "res://shaders/sea_push.gdshaderinc"

uniform float sway = 0.0;
uniform float water_level = 0.0;
uniform float caustic_strength = 0.75;
uniform float rough = 0.78;
uniform float wet_spec = 0.35;

varying vec3 wpos;
varying vec3 tint;
varying vec3 lpos;      // точка в координатах модели (узор полипов не «плывёт»)
varying float hue_k;

float caus(vec2 p, float t) {
	vec2 q = p + vec2(sin(p.y * 1.7 + t * 0.9), cos(p.x * 1.3 - t * 0.7)) * 0.6;
	float a = sin(q.x * 2.1 + t) * sin(q.y * 2.3 - t * 0.8);
	vec2 r = p * 1.6 + vec2(cos(p.y * 1.1 - t * 0.6), sin(p.x * 1.4 + t * 0.5)) * 0.8;
	float b = sin(r.x * 1.9 - t * 0.7) * sin(r.y * 2.2 + t * 0.9);
	float c = 1.0 - abs(a + b) * 0.5;
	return pow(clamp(c, 0.0, 1.0), 7.0);
}

void vertex() {
	tint = INSTANCE_CUSTOM.rgb;
	lpos = VERTEX;
	hue_k = fract(INSTANCE_CUSTOM.a * 7.13) - 0.5;
	if (dot(tint, tint) < 0.0001) {
		tint = vec3(1.0);
	}
	float ph = INSTANCE_CUSTOM.a * 6.2831;
	vec3 w0 = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = UV.y;
	if (sway > 0.0) {
		float t = TIME;
		vec2 off = vec2(sin(t * 1.1 + ph + w0.x * 0.35 + w0.z * 0.2) + 0.35 * sin(t * 2.3 + ph * 1.7),
				cos(t * 0.9 + ph + w0.z * 0.3)) * sway * h * h;
		float s = max(length(MODEL_MATRIX[0].xyz), 0.001);
		vec3 lo = transpose(mat3(MODEL_MATRIX)) * vec3(off.x, -0.25 * dot(off, off), off.y) / (s * s);
		VERTEX += lo;
		// пловец рядом — мягкое отгибает (общая реализация sea_push)
		VERTEX += sea_push_local(MODEL_MATRIX, (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, h);
	}
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (dot(NORMAL, VIEW) < 0.0) {
		NORMAL = -NORMAL;
	}
	vec3 col = COLOR.rgb * tint * 1.2;
	// разброс оттенка экземпляра (лёгкий сдвиг к соседнему цвету)
	col = mix(col, col.gbr, hue_k * 0.16);
	// узор полипов/пор: дешёвая «текстура» из синусов в координатах модели
	vec3 q = lpos * 120.0;
	float pp = sin(q.x + sin(q.y * 0.7)) * sin(q.y * 1.13 + q.z * 0.37) * sin(q.z * 0.91 - q.x * 0.29 + sin(q.x * 0.5));
	float pores = smoothstep(0.45, 0.9, abs(pp));
	float fine = sin(lpos.x * 230.0 + lpos.y * 160.0) * sin(lpos.z * 205.0 - lpos.y * 120.0);
	col *= 1.0 - pores * 0.1 - max(fine, 0.0) * 0.05;
	float depth = water_level - wpos.y;
	float under = step(0.0, depth);
	float k = caustic_strength * clamp(1.0 - depth / 11.0, 0.0, 1.0) * under;
	float c = caus(wpos.xz * 0.85, TIME * 0.9) + 0.6 * caus(wpos.xz * 1.9 + 3.1, TIME * 1.15);
	// вода гасит красный с глубиной
	vec3 absorb = mix(vec3(1.0), vec3(0.55, 0.85, 0.95), clamp(depth / 9.0, 0.0, 1.0) * under);
	ALBEDO = col * absorb * (1.0 + c * k);
	EMISSION = col * c * k * 0.12;
	ROUGHNESS = rough + pores * 0.12;
	SPECULAR = wet_spec;
	// «подповерхностное» рассеяние дёшево: свет сзади и мягкий ободок цвета ткани
	BACKLIGHT = col * 0.35;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION += col * rim * 0.10 * (1.0 - clamp(depth / 14.0, 0.0, 1.0) * under);
}
