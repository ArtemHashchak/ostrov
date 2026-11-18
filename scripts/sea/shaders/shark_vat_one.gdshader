shader_type spatial;
// Дальняя акула из пака: плавание из VAT (без скелета и AnimationPlayer).
// Фаза своя у каждой акулы (свой материал — дальние акулы и так рисуются по одной).
#include "res://shaders/vat.gdshaderinc"
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec3 tint = vec3(1.0);
uniform float speed = 1.0;
uniform float phase = 0.0;

void vertex() {
	VERTEX += vat_offset(float(VERTEX_ID), TIME * speed + phase * vat_length);
}

void fragment() {
	ALBEDO = texture(albedo_tex, UV).rgb * tint;
	ROUGHNESS = 0.55;
	SPECULAR = 0.4;
}
