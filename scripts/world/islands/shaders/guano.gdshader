shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;
// Потёки птичьего помёта на скале: рваное беловато-серое пятно с прожилками,
// неровный край, у каждого экземпляра — свой узор (по мировой позиции).

varying vec3 wpos;
varying vec3 ipos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	ipos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
}

void fragment() {
	vec2 q = UV - 0.5;
	vec2 seed = ipos.xz * 0.37;
	float n = vnoise(wpos.xz * 3.0 + seed) * 0.6 + vnoise(wpos.xz * 9.0 + seed * 2.0) * 0.4;
	float r = length(q) * 2.0;
	float blob = smoothstep(0.95, 0.45, r + (n - 0.5) * 0.9);
	float speck = smoothstep(0.55, 0.75, vnoise(wpos.xz * 22.0 + seed));
	vec3 c = mix(vec3(0.62, 0.62, 0.58), vec3(0.88, 0.87, 0.82), n);
	ALBEDO = c;
	ROUGHNESS = 0.85;
	ALPHA = clamp(blob * (0.55 + 0.45 * speck), 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = 0.3;
}
