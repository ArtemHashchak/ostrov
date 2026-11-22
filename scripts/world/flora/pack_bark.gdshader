shader_type spatial;
// Кора деревьев пака (стоящее дерево): см. pack_plant.gdshaderinc.
render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://scripts/world/flora/pack_plant.gdshaderinc"

void vertex() {
	v_ly = VERTEX.y;
	v_var = pack_var(MODEL_MATRIX);
	pack_vertex(VERTEX, UV2, MODEL_MATRIX, CAMERA_POSITION_WORLD, TIME);
}

void fragment() {
	if (pack_clipped(v_ly, true)) {
		discard;
	}
	vec3 orm = texture(orm_tex, UV).rgb;
	ALBEDO = texture(albedo_tex, UV).rgb * tint.rgb * COLOR.rgb * (1.0 + v_var * 0.08) * (1.0 - 0.3 * weather_wetness);
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	AO = orm.r;
	ROUGHNESS = mix(clamp(orm.g * rough_k, 0.0, 1.0), 0.3, weather_wetness * 0.8);
	SPECULAR = mix(0.4, 0.7, weather_wetness);
}
