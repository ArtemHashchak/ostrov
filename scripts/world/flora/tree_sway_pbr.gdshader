shader_type spatial;
// Кора/кокосы стоящего дерева: PBR как у StandardMaterial3D (альбедо, нормаль,
// шероховатость R, AO) + изгиб ветром (tree_bend) + сырость (CONTRACT_WEATHER).
render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://scripts/world/flora/tree_bend.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool has_albedo = true;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool has_normal = false;
uniform sampler2D rough_tex : hint_roughness_r, filter_linear_mipmap, repeat_enable;
uniform bool has_rough = false;
uniform float roughness_v = 1.0;
uniform vec4 rough_mask = vec4(1.0, 0.0, 0.0, 0.0);
uniform sampler2D ao_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool has_ao = false;
uniform vec3 uv_scale = vec3(1.0);

global uniform vec2 wind_dir;
global uniform float wind_gust;
global uniform float weather_storm;
global uniform float weather_wetness;

void vertex() {
	UV *= uv_scale.xy;
	VERTEX += tree_bend_local(VERTEX, MODEL_MATRIX, TIME, wind_dir, weather_storm, wind_gust);
}

void fragment() {
	vec3 c = albedo_color.rgb;
	if (has_albedo) {
		c *= texture(albedo_tex, UV).rgb;
	}
	float r = roughness_v;
	if (has_rough) {
		r *= dot(texture(rough_tex, UV), rough_mask);
	}
	ALBEDO = c * (1.0 - 0.3 * weather_wetness);
	ROUGHNESS = mix(r, 0.3, weather_wetness * 0.8);
	SPECULAR = mix(0.5, 0.7, weather_wetness);
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
	if (has_ao) {
		AO = texture(ao_tex, UV).r;
	}
}
