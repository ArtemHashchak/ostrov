shader_type spatial;
// Листва FLORA: альфа-отсечение, двусторонность, ветер, мягкое «просвечивание».
// Вес качания — в канале COLOR.r вершины (0 у основания, 1 у кончика).
render_mode cull_disabled, depth_draw_opaque, diffuse_lambert_wrap, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.42;
uniform float wind_strength = 0.12;
uniform float wind_speed = 1.3;
uniform float wind_scale = 0.22;
uniform float roughness_v : hint_range(0.0, 1.0) = 0.82;
uniform float translucency : hint_range(0.0, 1.0) = 0.35;
uniform float color_var : hint_range(0.0, 0.5) = 0.12;

varying float v_var;
varying float v_shade; // COLOR.g: затенение внутренней листвы кроны

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = COLOR.r;
	v_shade = COLOR.g;
	float t = TIME * wind_speed;
	float gust = 0.6 + 0.4 * sin(t * 0.37 + wp.x * 0.05);
	float s1 = sin(t + wp.x * wind_scale + wp.z * wind_scale * 0.7);
	float s2 = sin(t * 2.3 + wp.z * wind_scale * 1.9 + VERTEX.y);
	VERTEX.x += (s1 * 0.8 + s2 * 0.25) * wind_strength * w * gust;
	VERTEX.z += (cos(t * 0.9 + wp.x * wind_scale) * 0.5 + s2 * 0.2) * wind_strength * w * gust;
	VERTEX.y += s2 * wind_strength * 0.25 * w;
	// разброс оттенка по позиции объекта
	vec3 o = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_var = fract(sin(dot(o.xz, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
}

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	vec3 col = c.rgb * tint.rgb * (1.0 + v_var * color_var * 2.0) * v_shade;
	col.r *= 1.0 + v_var * color_var;
	ALBEDO = col;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = roughness_v;
	SPECULAR = 0.25;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	BACKLIGHT = col * translucency;
}
