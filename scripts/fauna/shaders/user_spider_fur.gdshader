shader_type spatial;
// Волоски паука-птицееда (карточки модели автора): цвет — градиент автора по UV.y (у корня
// почти чёрный, к кончику серо-бурый) × текстура волоска; альфа — вырез по текстуре.
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D hair_tex : source_color, filter_linear_mipmap;
uniform vec3 col_root : source_color = vec3(0.10, 0.0, 0.0);
uniform vec3 col_tip : source_color = vec3(0.349, 0.332, 0.313);
uniform float cut = 0.35;

void fragment() {
	vec4 h = texture(hair_tex, UV);
	ALBEDO = mix(col_root, col_tip, clamp(UV.y, 0.0, 1.0)) * h.rgb;
	ALPHA = h.a;
	ALPHA_SCISSOR_THRESHOLD = cut;
	ROUGHNESS = 0.6;
	SPECULAR = 0.35;
}
