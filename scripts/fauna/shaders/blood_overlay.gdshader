shader_type spatial;
// Кровь из маски повреждений (v5.1, агент I): next_pass поверх материала существа.
// mask: R — кровь, G — глубина раны (дыра), B — рваная мякоть по краю. UV0 меша.
// Цвет свежая → запёкшаяся (dry), мокрый блеск (низкая шероховатость), рельеф из маски (карта нормалей),
// spread — кровь на туше расползается. Работает в gl_compatibility и Forward+.
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D mask : filter_linear, repeat_disable;
uniform float texel = 0.001953125;
uniform float spread = 0.0;   // туша: расползание считается в маске (3D), здесь — только чуть темнее
uniform float dry = 0.0;
uniform float push = 0.0015;

void vertex() {
	VERTEX += NORMAL * push;
}

float hgt(vec3 c) {
	return c.r * 0.35 + c.b * 0.55 - c.g * 1.2;
}

void fragment() {
	vec4 m4 = texture(mask, UV);
	vec3 c = m4.rgb;
	float bruise = m4.a;
	float b = c.r;
	float hole = c.g;
	float flesh = c.b;
	float cov = max(max(b, hole), max(flesh, bruise * 0.5));
	if (cov < 0.015) {
		discard;
	}
	float thick = smoothstep(0.25, 1.0, b);
	vec3 fresh = vec3(0.30, 0.012, 0.010);
	vec3 deep = vec3(0.11, 0.004, 0.004);
	vec3 dried = vec3(0.15, 0.035, 0.022);
	vec3 blood = mix(fresh, deep, thick * 0.55);
	blood = mix(blood, deep, spread * 0.25);
	blood = mix(blood, dried, dry);
	vec3 meat = mix(vec3(0.50, 0.10, 0.08), vec3(0.22, 0.05, 0.03), dry);
	vec3 col = mix(blood, meat, clamp(flesh * 0.9 - hole, 0.0, 1.0));
	col = mix(col, vec3(0.025, 0.0, 0.0), smoothstep(0.0, 0.8, hole));
	float ba = smoothstep(0.015, 0.45, b) * mix(0.55, 0.97, thick) + hole + flesh * 0.9;
	col = mix(vec3(0.07, 0.025, 0.03), col, clamp(ba * 1.5, 0.0, 1.0));
	ALBEDO = col;
	// рельеф: плёнка крови чуть выпуклая, мякоть рваная, дыра — провал
	float hx = hgt(texture(mask, UV + vec2(texel, 0.0)).rgb) - hgt(texture(mask, UV - vec2(texel, 0.0)).rgb);
	float hy = hgt(texture(mask, UV + vec2(0.0, texel)).rgb) - hgt(texture(mask, UV - vec2(0.0, texel)).rgb);
	NORMAL_MAP = normalize(vec3(-hx * 2.2, -hy * 2.2, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
	ROUGHNESS = clamp(mix(0.14, 0.55, dry) + hole * 0.35 + (1.0 - thick) * 0.12, 0.04, 1.0);
	SPECULAR = mix(0.4, 0.25, dry);
	METALLIC = 0.0;
	// края: тонкая плёнка полупрозрачна (кожа просвечивает), густая кровь и рана — плотные
	ALPHA = clamp(max(ba, bruise * 0.45), 0.0, 1.0);
}
