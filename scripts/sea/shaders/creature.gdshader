shader_type spatial;
render_mode cull_disabled;
// Морские обитатели: скат (0), черепаха (1). Нос в -Z.
// Скат: крылья машут волной от корпуса к кончикам (|x|).
// Черепаха: COLOR.a — маска ласт (1 — передние, 0.5 — задние), гребок вокруг корня.

uniform int kind = 0;
uniform float water_level = 0.0;
uniform float caustic_strength = 0.6;
instance uniform float phase = 0.0;
instance uniform float amp = 1.0;
instance uniform float rate = 1.0;

varying vec3 wpos;

float caus(vec2 p, float t) {
	vec2 q = p + vec2(sin(p.y * 1.7 + t * 0.9), cos(p.x * 1.3 - t * 0.7)) * 0.6;
	float a = sin(q.x * 2.1 + t) * sin(q.y * 2.3 - t * 0.8);
	vec2 r = p * 1.6 + vec2(cos(p.y * 1.1 - t * 0.6), sin(p.x * 1.4 + t * 0.5)) * 0.8;
	float b = sin(r.x * 1.9 - t * 0.7) * sin(r.y * 2.2 + t * 0.9);
	return pow(clamp(1.0 - abs(a + b) * 0.5, 0.0, 1.0), 7.0);
}

void vertex() {
	float t = TIME * rate + phase;
	if (kind == 0) {
		float ax = abs(VERTEX.x);
		VERTEX.y += sin(t * 2.2 - ax * 2.4) * amp * 0.22 * pow(ax, 1.4);
		// хвост-хлыст
		if (VERTEX.z > 0.5) {
			VERTEX.x += sin(t * 2.2 - VERTEX.z * 3.0) * 0.06 * (VERTEX.z - 0.5);
		}
	} else if (kind == 1) {
		float m = COLOR.a;
		if (m > 0.9) {
			// передние ласты: «полёт» вверх-вниз и назад
			float ax = abs(VERTEX.x) - 0.18;
			float s = sin(t * 1.6);
			VERTEX.y += s * amp * 0.5 * max(ax, 0.0);
			VERTEX.z += (cos(t * 1.6) * 0.5 + 0.2) * amp * 0.35 * max(ax, 0.0);
		} else if (m > 0.4) {
			float ax = abs(VERTEX.x) - 0.12;
			VERTEX.y += sin(t * 1.6 + 1.2) * amp * 0.18 * max(ax, 0.0);
		}
	}
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (dot(NORMAL, VIEW) < 0.0) {
		NORMAL = -NORMAL;
	}
	float depth = water_level - wpos.y;
	float under = step(0.0, depth);
	float k = caustic_strength * clamp(1.0 - depth / 10.0, 0.0, 1.0) * under;
	float c = caus(wpos.xz * 0.9, TIME * 0.9);
	ALBEDO = COLOR.rgb * (1.0 + c * k);
	ROUGHNESS = kind == 1 ? 0.55 : 0.7;
	SPECULAR = 0.4;
}
