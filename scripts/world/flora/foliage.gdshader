shader_type spatial;
// Листва FLORA: альфа-отсечение, двусторонность, ветер, мягкое «просвечивание».
// Вес качания — в канале COLOR.r вершины (0 у основания, 1 у кончика).
render_mode cull_disabled, depth_draw_opaque, diffuse_lambert_wrap, specular_schlick_ggx;
#include "res://scripts/world/flora/tree_bend.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.42;
uniform float wind_strength = 0.12;
uniform float wind_speed = 1.3;
uniform float wind_scale = 0.22;
uniform float roughness_v : hint_range(0.0, 1.0) = 0.82;
uniform float translucency : hint_range(0.0, 1.0) = 0.35;
uniform float color_var : hint_range(0.0, 0.5) = 0.12;
// CONTRACT_WEATHER: ветер мира. wind_speed здесь — скорость ветра, м/с (глобальная),
// параметр материала wind_speed выше — частота качания (имя историческое).
global uniform vec2 wind_dir;
global uniform float wind_gust;
global uniform float weather_wetness;
global uniform float weather_storm;

varying float v_var;
varying float v_shade; // COLOR.g: затенение внутренней листвы кроны

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = COLOR.r;
	v_shade = COLOR.g;
	// сила ветра мира: 0 — штиль, 1 — дождь, ~2.6 — шторм
	float wf = clamp(1.0 + weather_storm * 2.0, 0.6, 3.0) * (0.85 + 0.3 * wind_gust);
	// фаза по времени масштабирована медленно меняющимся ветром (без рывков: частота меняется
	// плавно, а сам масштаб входит только в амплитуду)
	float t = TIME * wind_speed * (1.0 + weather_storm * 0.9);
	float gust = 0.6 + 0.4 * sin(t * 0.37 + wp.x * 0.05);
	float s1 = sin(t + wp.x * wind_scale + wp.z * wind_scale * 0.7);
	float s2 = sin(t * 2.3 + wp.z * wind_scale * 1.9 + VERTEX.y);
	float amp = wind_strength * w * gust * min(wf, 1.8);
	VERTEX.x += (s1 * 0.8 + s2 * 0.25) * amp;
	VERTEX.z += (cos(t * 0.9 + wp.x * wind_scale) * 0.5 + s2 * 0.2) * amp;
	VERTEX.y += s2 * wind_strength * 0.25 * w;
	// постоянный изгиб по ветру (кроны пальм «стелются» в шторм): мировое направление → локальное
	float bend = max(0.0, wf - 1.25) * w * w * wind_strength * 7.0 * (0.8 + 0.4 * wind_gust + 0.25 * s1);
	vec3 bw = vec3(wind_dir.x, -0.25, wind_dir.y) * bend;
	vec3 bl = transpose(mat3(MODEL_MATRIX)) * bw;
	float sc2 = max(dot(MODEL_MATRIX[0].xyz, MODEL_MATRIX[0].xyz), 1e-4);
	VERTEX += bl / sc2;
	// изгиб всего дерева (тот же, что у ствола: tree_sway_pbr) — крона идёт вместе со стволом
	VERTEX += tree_bend_local(VERTEX, MODEL_MATRIX, TIME, wind_dir, weather_storm, wind_gust);
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
	ALBEDO *= 1.0 - 0.18 * weather_wetness;
	ROUGHNESS = mix(roughness_v, 0.38, weather_wetness * 0.85);
	SPECULAR = mix(0.25, 0.5, weather_wetness);
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	BACKLIGHT = col * translucency;
}
