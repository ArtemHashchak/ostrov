// Акула из пака в «толпе»: анимация плавания из VAT (без скелета), MultiMesh.
shader_type spatial;
#include "res://shaders/vat.gdshaderinc"
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D orm_tex : filter_linear_mipmap;
uniform float speed = 1.0;

void vertex() {
	VERTEX += vat_offset(float(VERTEX_ID), TIME * speed + INSTANCE_CUSTOM.x * vat_length);
}

void fragment() {
	ALBEDO = texture(albedo_tex, UV).rgb;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	vec3 orm = texture(orm_tex, UV).rgb;
	AO = orm.r;
	ROUGHNESS = orm.g;
	METALLIC = orm.b;
}
