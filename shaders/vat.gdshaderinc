// VAT — анимация из текстуры вершин (tools/bake_vat.gd). Скелета нет, процессор не участвует:
// одна заросль/стая/толпа = один MultiMesh = один вызов отрисовки.
// В vertex():  VERTEX += vat_offset(float(VERTEX_ID), TIME * speed + INSTANCE_CUSTOM.x);
// (VERTEX_ID — порядок вершин меша из bake_vat; UV2.x дублирует его на случай сжатия меша)
uniform sampler2D vat_tex : filter_nearest, repeat_disable;
uniform float vat_frames = 24.0;
uniform float vat_length = 1.0;

vec3 vat_offset(float vid, float t) {
	float f = fract(t / vat_length) * vat_frames;
	int f0 = int(floor(f));
	int f1 = (f0 + 1) % int(vat_frames);
	int x = int(vid);
	vec3 a = texelFetch(vat_tex, ivec2(x, f0), 0).xyz;
	vec3 b = texelFetch(vat_tex, ivec2(x, f1), 0).xyz;
	return mix(a, b, fract(f));
}
