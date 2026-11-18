shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
// Каустика на дне: сетка-«покрывало» над рельефом дна вокруг камеры. Только под водой,
// ярче на мелководье, гаснет к краям сетки.

uniform float water_level = 0.0;
uniform float strength = 0.22;
uniform vec3 grid_center = vec3(0.0);
uniform float grid_half = 28.0;
uniform float sun = 1.0;

varying vec3 wpos;

float caus(vec2 p, float t) {
	vec2 q = p + vec2(sin(p.y * 1.7 + t * 0.9), cos(p.x * 1.3 - t * 0.7)) * 0.6;
	float a = sin(q.x * 2.1 + t) * sin(q.y * 2.3 - t * 0.8);
	vec2 r = p * 1.6 + vec2(cos(p.y * 1.1 - t * 0.6), sin(p.x * 1.4 + t * 0.5)) * 0.8;
	float b = sin(r.x * 1.9 - t * 0.7) * sin(r.y * 2.2 + t * 0.9);
	return pow(clamp(1.0 - abs(a + b) * 0.5, 0.0, 1.0), 7.0);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float depth = water_level - wpos.y;
	if (depth < 0.05) {
		discard;
	}
	vec2 e = abs(wpos.xz - grid_center.xz) / grid_half;
	float edge = 1.0 - smoothstep(0.65, 1.0, max(e.x, e.y));
	float fade = clamp(1.0 - depth / 9.0, 0.0, 1.0) * smoothstep(0.05, 0.6, depth);
	float c = caus(wpos.xz * 0.85, TIME * 0.9) + 0.6 * caus(wpos.xz * 1.9 + 3.1, TIME * 1.15);
	ALBEDO = vec3(0.85, 1.0, 0.9) * c * strength * fade * edge * sun;
}
