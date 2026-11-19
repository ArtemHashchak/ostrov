shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;
// Ручей: лента по руслу, UV.x — поперёк (0..1), UV.y — вдоль течения (м).
// COLOR.r — уклон (быстрее течение, больше пены на перекатах).
// foam_only — плоская пена у подножия водопада (кольцо с шумом).

uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 deep_color : source_color = vec3(0.05, 0.16, 0.14);
uniform vec3 shallow_color : source_color = vec3(0.24, 0.36, 0.30);
uniform float speed = 0.9;
uniform bool foam_only = false;
global uniform float weather_rain;

varying float slope;
varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) { return vnoise(p) * 0.55 + vnoise(p * 2.1 + 3.7) * 0.3 + vnoise(p * 4.3 + 7.1) * 0.15; }

void vertex() {
	slope = COLOR.r;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (foam_only) {
		vec2 q = UV - 0.5;
		float r = length(q * vec2(1.0, 1.2));
		float t = TIME;
		float n = fbm(wpos.xz * 1.3 + vec2(t * 0.6, -t * 0.4)) * 0.6 + fbm(wpos.xz * 3.1 - vec2(t * 0.9, t * 0.3)) * 0.4;
		float a = smoothstep(0.5, 0.15, r) * smoothstep(0.35, 0.65, n);
		ALBEDO = vec3(0.92, 0.95, 0.96);
		ROUGHNESS = 0.6;
		ALPHA = a * 0.85;
	} else {
		float sp = speed * (1.0 + slope * 6.0);
		vec2 uv = vec2(UV.x * 1.6, UV.y * 0.35);
		vec3 n1 = texture(normal_tex, uv - vec2(0.0, TIME * sp * 0.35)).rgb;
		vec3 n2 = texture(normal_tex, uv * 1.7 + vec2(0.31, -TIME * sp * 0.52)).rgb;
		NORMAL_MAP = normalize(mix(n1, n2, 0.5) * 2.0 - 1.0) * 0.5 + 0.5;
		NORMAL_MAP_DEPTH = 0.6 + slope * 0.8;
		// глубже к середине русла
		float mid = 1.0 - abs(UV.x - 0.5) * 2.0;
		vec3 col = mix(shallow_color, deep_color, smoothstep(0.0, 0.8, mid));
		// пена: на перекатах и у берегов, тянется по течению
		float fn = fbm(vec2(UV.x * 5.0, UV.y * 0.8 - TIME * sp * 1.1));
		float foam = smoothstep(0.62, 0.85, fn) * (0.25 + slope * 3.0) + smoothstep(0.82, 1.0, 1.0 - mid) * 0.35 * fn;
		foam = clamp(foam, 0.0, 0.85);
		ALBEDO = mix(col, vec3(0.9, 0.93, 0.92), foam);
		ROUGHNESS = mix(0.04, 0.5, foam) + weather_rain * 0.1;
		SPECULAR = 0.6;
		ALPHA = clamp(0.78 + foam * 0.2, 0.0, 1.0) * smoothstep(0.0, 0.12, min(UV.x, 1.0 - UV.x));
	}
}
