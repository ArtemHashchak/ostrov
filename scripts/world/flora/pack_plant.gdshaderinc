// Растения пака пользователя (MODELS/Tree, MODELS/Plants): PBR по атласам автора
// (albedo, normal, ORM: R — AO, G — шероховатость), ветер из UV2 автора (x — вес качания
// 0 у основания … 1 у кончика, y — фаза), общий изгиб дерева ветром (tree_bend: кора и листва
// гнутся одинаково), сырость (CONTRACT_WEATHER), уход вдали для мелких растений (fade_far).
// Срез для рубки: clip_lo/clip_hi — отбросить всё ниже/выше локальной высоты; hole — полоса
// коры, которую заменяет процедурная зарубка (у копии материала конкретного дерева).
#include "res://scripts/world/flora/tree_bend.gdshaderinc"
#include "res://shaders/plant_push.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.5;
uniform float wind_amp = 0.06;      // м на вес 1 в штиль
uniform float rough_k = 1.0;
uniform float translucency : hint_range(0.0, 1.0) = 0.3;
uniform float bend_k = 1.0;         // 0 — без изгиба целиком (кусты гнутся только листвой)
uniform float clip_lo = -1000.0;
uniform float clip_hi = 1000.0;
uniform vec2 hole = vec2(0.0, 0.0);
uniform float fade_far = 0.0;
uniform float fade_len = 14.0;

global uniform vec2 wind_dir;
global uniform float wind_gust;
global uniform float weather_storm;
global uniform float weather_wetness;

varying float v_ly;
varying float v_var;

void pack_vertex(inout vec3 vtx, vec2 uv2, mat4 model, vec3 cam, float t) {
	if (fade_far > 0.0) {
		vec3 io = model[3].xyz;
		float d = distance(io, cam);
		float f = 1.0 - smoothstep(fade_far - fade_len, fade_far, d);
		vtx *= vec3(mix(f, 1.0, f), f * f * (3.0 - 2.0 * f), mix(f, 1.0, f));
	}
	vec3 wp = (model * vec4(vtx, 1.0)).xyz;
	float w = clamp(uv2.x, 0.0, 1.0);
	float ph = uv2.y * 1.7;
	float wf = clamp(1.0 + weather_storm * 2.0, 0.6, 3.0) * (0.85 + 0.3 * wind_gust);
	float tt = t * (1.3 + weather_storm * 1.1);
	float amp = wind_amp * w * min(wf, 2.2) * wind_gust_field(wp.xz, t, wind_dir, weather_storm, wind_gust);
	vec3 fl = vec3(sin(tt + ph + wp.x * 0.21) * 0.8 + sin(tt * 2.7 + ph * 1.3) * 0.25,
			sin(tt * 3.1 + ph * 0.7) * 0.35,
			cos(tt * 0.9 + ph + wp.z * 0.21) * 0.6);
	vec3 dw = fl * amp;
	dw += plant_push(wp, w * (1.0 - bend_k));   // кусты/папоротники раздвигаются (деревья — нет)
	// листья «стелются» по ветру в шторм
	float lay = max(0.0, wf - 1.25) * w * wind_amp * 4.0;
	dw += vec3(wind_dir.x, -0.2, wind_dir.y) * lay;
	vec3 dl = transpose(mat3(model)) * dw;
	float sc2 = max(dot(model[0].xyz, model[0].xyz), 1e-4);
	vtx += dl / sc2;
	vtx += bend_k * tree_bend_local(vtx, model, t, wind_dir, weather_storm, wind_gust);
}

float pack_var(mat4 model) {
	return fract(sin(dot(model[3].xz, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
}

bool pack_clipped(float ly, bool bark) {
	if (ly < clip_lo || ly > clip_hi) {
		return true;
	}
	return bark && ly > hole.x && ly < hole.y;
}
