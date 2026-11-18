shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_never, specular_schlick_ggx;
// Медуза: полупрозрачный купол пульсирует (UV.y: 0 — макушка, 1 — край), щупальца (UV.x > 1.5) колышутся.

uniform vec4 tint : source_color = vec4(0.75, 0.6, 0.95, 0.45);
instance uniform float phase = 0.0;

void vertex() {
	float t = TIME * 1.7 + phase;
	float p = sin(t) * 0.5 + 0.5;
	if (UV.x < 1.5) {
		float e = UV.y;
		VERTEX.xz *= 1.0 + (p - 0.5) * 0.28 * e;
		VERTEX.y += (p - 0.5) * 0.08 * e;
	} else {
		float d = -VERTEX.y;
		VERTEX.x += sin(t * 0.8 + d * 2.5 + UV.x) * 0.06 * d;
		VERTEX.z += cos(t * 0.7 + d * 2.1 + UV.x * 1.3) * 0.06 * d;
		VERTEX.xz *= 1.0 + (p - 0.5) * 0.2;
	}
}

void fragment() {
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	ALBEDO = tint.rgb * COLOR.rgb;
	ALPHA = clamp(tint.a * (0.35 + rim * 0.9) * COLOR.a, 0.0, 0.9);
	EMISSION = tint.rgb * (0.15 + rim * 0.35);
	ROUGHNESS = 0.2;
}
