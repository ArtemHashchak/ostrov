// Водоросли-«карточки» из атласа пака пользователя: покачивание течением + расталкивание пловцом.
// Цена: атлас 2048×1024, 24 треугольника на куст, MultiMesh (1 вызов отрисовки на заросль), без теней.
shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/sea_push.gdshaderinc"

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float cells = 8.0;
uniform float sway = 0.22;
uniform vec3 tint : source_color = vec3(0.85, 0.95, 0.85);

varying float v_cell;

void vertex() {
	float h = 1.0 - UV.y;                       // 0 у дна, 1 у верхушки
	v_cell = INSTANCE_CUSTOM.x;
	float ph = INSTANCE_CUSTOM.y * 6.2831;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float s = sin(TIME * 0.9 + ph + wp.x * 0.35) * 0.6 + sin(TIME * 1.7 + ph * 1.3 + wp.z * 0.5) * 0.4;
	VERTEX.x += s * sway * h * h;
	VERTEX.z += cos(TIME * 0.7 + ph) * sway * 0.5 * h * h;
	VERTEX += sea_push_local(MODEL_MATRIX, wp, h);
}

void fragment() {
	vec2 uv = vec2((v_cell + UV.x) / cells, UV.y);
	vec4 c = texture(atlas, uv);
	ALBEDO = c.rgb * tint;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.35;
	ROUGHNESS = 0.6;
	SPECULAR = 0.3;
	BACKLIGHT = vec3(0.25, 0.35, 0.2);
}
