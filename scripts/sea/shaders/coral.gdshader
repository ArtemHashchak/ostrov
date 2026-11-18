shader_type spatial;
render_mode cull_disabled;
// Кораллы, губки, водоросли, камни рифа (MultiMesh).
// Цвет: вершинный цвет × INSTANCE_CUSTOM.rgb (оттенок экземпляра); INSTANCE_CUSTOM.a — фаза покачивания.
// UV.y — высота точки над основанием (0..1): водоросли и веера качаются сильнее у верхушки.
// Каустика: световая сетка от волн на всём, что под водой, слабеет с глубиной.

uniform float sway = 0.0;
uniform float water_level = 0.0;
uniform float caustic_strength = 0.75;
uniform float rough = 0.78;
uniform float wet_spec = 0.35;

varying vec3 wpos;
varying vec3 tint;

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
	}
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 col = COLOR.rgb * tint;
	float depth = water_level - wpos.y;
	float under = step(0.0, depth);
	float k = caustic_strength * clamp(1.0 - depth / 11.0, 0.0, 1.0) * under;
	float c = caus(wpos.xz * 0.85, TIME * 0.9) + 0.6 * caus(wpos.xz * 1.9 + 3.1, TIME * 1.15);
	// вода гасит красный с глубиной
	vec3 absorb = mix(vec3(1.0), vec3(0.55, 0.85, 0.95), clamp(depth / 9.0, 0.0, 1.0) * under);
	ALBEDO = col * absorb * (1.0 + c * k);
	EMISSION = col * c * k * 0.12;
	ROUGHNESS = rough;
	SPECULAR = wet_spec;
}
