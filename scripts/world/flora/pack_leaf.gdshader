shader_type spatial;
// Листва/цветы/кокосы пака: альфа-отсечение, двусторонность, просвечивание; см. pack_plant.gdshaderinc.
render_mode cull_disabled, depth_draw_opaque, diffuse_lambert_wrap, specular_schlick_ggx;
#include "res://scripts/world/flora/pack_plant.gdshaderinc"

void vertex() {
	v_ly = VERTEX.y;
	v_var = pack_var(MODEL_MATRIX);
	pack_vertex(VERTEX, UV2, MODEL_MATRIX, CAMERA_POSITION_WORLD, TIME);
}

void fragment() {
	if (pack_clipped(v_ly, false)) {
		discard;
	}
	vec4 c = texture(albedo_tex, UV);
	vec3 orm = texture(orm_tex, UV).rgb;
	vec3 col = c.rgb * tint.rgb * COLOR.rgb * (1.0 + v_var * 0.16);
	ALBEDO = col * (1.0 - 0.18 * weather_wetness);
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.4;
	ROUGHNESS = mix(clamp(orm.g * rough_k, 0.0, 1.0), 0.38, weather_wetness * 0.85);
	SPECULAR = mix(0.3, 0.5, weather_wetness);
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	BACKLIGHT = col * translucency;
}
