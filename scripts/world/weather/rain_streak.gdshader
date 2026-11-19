shader_type spatial;
// Капля-штрих дождя (частица). Ось Y частицы (align_y) = скорость → штрих вытянут
// вдоль полёта (наклон по ветру); квад разворачивается к камере вокруг этой оси.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(0.78, 0.84, 0.92, 0.5);
uniform float width = 0.011;
uniform float length = 0.75;
uniform float light = 1.0;      // освещённость сцены (день/ночь/вспышка молнии)
uniform float near_fade = 1.2;
uniform float far_fade = 20.0;

varying float v_fade;

void vertex() {
	vec3 c = MODEL_MATRIX[3].xyz;
	vec3 d = normalize(MODEL_MATRIX[1].xyz);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 v = normalize(cam - c);
	vec3 r = normalize(cross(d, v));
	float dist = distance(cam, c);
	// дальние капли чуть толще, чтобы не мерцать между пикселями
	float w = width * (1.0 + dist * 0.06);
	vec3 wp = c + r * VERTEX.x * w + d * VERTEX.y * length;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wp, 1.0);
	v_fade = smoothstep(near_fade * 0.4, near_fade, dist) * (1.0 - smoothstep(far_fade * 0.6, far_fade, dist));
}

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float along = smoothstep(0.0, 0.35, UV.y) * smoothstep(1.0, 0.75, UV.y);
	ALBEDO = color.rgb * light;
	ALPHA = color.a * across * along * v_fade;
}
