shader_type spatial;
render_mode cull_disabled;
// Донные ходоки (MultiMesh): крабы бегают боком, лангусты пятятся/ползут вперёд.
// Экземпляр: базис — поворот по дну и масштаб, origin — середина пути.
// INSTANCE_CUSTOM: x — фаза, y — длина пути (м), z — скорость (м/с), w — оттенок.
// COLOR.rgb — цвет вершины; COLOR.a — нога/усик (1) — двигается при ходьбе.
// UV.x — номер ноги (0..1) для сдвига фазы, UV.y — высота над дном (усики качаются).

global uniform float sea_time;
global uniform float sea_level;

uniform vec3 axis = vec3(1.0, 0.0, 0.0);
uniform vec3 tint_a : source_color = vec3(1.0);
uniform vec3 tint_b : source_color = vec3(1.0);
uniform float antenna_sway = 0.0;
uniform float caustic_strength = 0.6;

varying vec3 wpos;
varying vec3 tint;

float travel(float q) {
	// 0..0.3 туда, 0.3..0.5 стоит, 0.5..0.8 обратно, 0.8..1 стоит
	if (q < 0.3) return smoothstep(0.0, 0.3, q);
	if (q < 0.5) return 1.0;
	if (q < 0.8) return 1.0 - smoothstep(0.5, 0.8, q);
	return 0.0;
}

void vertex() {
	vec4 c = INSTANCE_CUSTOM;
	float L = max(c.y, 0.01);
	float spd = max(c.z, 0.01);
	float period = L / spd / 0.3 * 1.0 + 4.0 * fract(c.x * 5.3);
	float q = fract(sea_time / period + c.x);
	float s = travel(q) - 0.5;
	float moving = (q < 0.3 || (q > 0.5 && q < 0.8)) ? 1.0 : 0.0;
	float sc = max(length(MODEL_MATRIX[0].xyz), 0.001);
	vec3 v = VERTEX;
	float leg = COLOR.a;
	v.y += leg * moving * abs(sin(sea_time * 22.0 + UV.x * 9.0)) * 0.08;
	v.x += leg * moving * sin(sea_time * 22.0 + UV.x * 9.0) * 0.04;
	if (antenna_sway > 0.0) {
		float h = UV.y;
		v.x += sin(sea_time * 1.7 + c.x * 6.2831 + h * 2.0) * antenna_sway * h * h;
	}
	VERTEX = v + axis * s * L / sc;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	tint = mix(tint_a, tint_b, c.w);
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
	vec3 col = COLOR.rgb * tint;
	float depth = sea_level - wpos.y;
	float under = step(0.0, depth);
	float k = caustic_strength * clamp(1.0 - depth / 10.0, 0.0, 1.0) * under;
	float cs = caus(wpos.xz * 0.85, sea_time * 0.9);
	vec3 absorb = mix(vec3(1.0), vec3(0.65, 0.88, 0.96), clamp(depth / 10.0, 0.0, 1.0) * under);
	ALBEDO = col * absorb * (1.0 + cs * k);
	ROUGHNESS = 0.45;
	SPECULAR = 0.5;
	EMISSION = col * 0.06 * under;
}
