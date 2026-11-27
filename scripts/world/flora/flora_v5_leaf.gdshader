shader_type spatial;
// Новые растения пользователя (assets/user_pack/flora_v5, GLTF со StandardMaterial3D):
// тот же ветер и изгиб от касания, что у растений пака (pack_plant.gdshaderinc). Веса ветра в UV2
// у этих моделей нет — вес считается по высоте вершины над основанием (0 у корня … 1 на верхушке
// model_height), фаза — от положения вершины. Материал создаёт FloraV5Mat.convert() из исходного.
render_mode cull_disabled, depth_draw_opaque, diffuse_lambert_wrap, specular_schlick_ggx;
#include "res://scripts/world/flora/pack_plant.gdshaderinc"

uniform float model_height = 1.5;     // м, высота модели (по каталогу size_m.y)
uniform float sway_from = 0.08;       // доля высоты, ниже которой ветер не качает (корень)
uniform bool has_normal = false;
uniform bool has_rough = false;
uniform float rough_value = 0.8;
uniform float metal_value = 0.0;
uniform int rough_channel = 1;        // канал шероховатости в orm_tex (glTF: G)
uniform bool hanging = false;         // лианы: качаются свисающие нижние концы, а не верх

void vertex() {
	v_ly = VERTEX.y;
	v_var = pack_var(MODEL_MATRIX);
	float h = max(model_height, 0.05);
	float w = clamp((VERTEX.y / h - sway_from) / max(1.0 - sway_from, 0.01), 0.0, 1.0);
	if (hanging) {
		w = clamp(1.0 - VERTEX.y / h, 0.0, 1.0);
	}
	w = w * w * (3.0 - 2.0 * w);
	vec2 uv2w = vec2(w, fract(dot(VERTEX.xz, vec2(0.37, 0.61))) * 3.0);
	pack_vertex(VERTEX, uv2w, MODEL_MATRIX, CAMERA_POSITION_WORLD, TIME);
}

void fragment() {
	if (pack_clipped(v_ly, false)) {
		discard;
	}
	vec4 c = texture(albedo_tex, UV) * tint;
	vec3 col = c.rgb * COLOR.rgb * (1.0 + v_var * 0.12);
	ALBEDO = col * (1.0 - 0.18 * weather_wetness);
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
	float r = rough_value;
	if (has_rough) {
		vec4 o = texture(orm_tex, UV);
		r = (rough_channel == 0 ? o.r : (rough_channel == 2 ? o.b : (rough_channel == 3 ? o.a : o.g))) * rough_value;
	}
	ROUGHNESS = mix(clamp(r * rough_k, 0.0, 1.0), 0.38, weather_wetness * 0.85);
	METALLIC = metal_value;
	SPECULAR = mix(0.3, 0.5, weather_wetness);
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	BACKLIGHT = col * translucency;
	// v5.2: роса — листья глянцевые, на верхней стороне блестят капли
	if (dew_amount > 0.01) {
		ROUGHNESS = mix(ROUGHNESS, 0.16, dew_amount * 0.7);
		SPECULAR = mix(SPECULAR, 0.6, dew_amount);
		float sp = dew_sparkle(UV) * dew_amount * (FRONT_FACING ? 1.0 : 0.3);
		ALBEDO = mix(ALBEDO, vec3(0.85, 0.9, 0.95), sp * 0.35);
		EMISSION = vec3(0.9, 0.95, 1.0) * sp * 0.12;
	}
}
