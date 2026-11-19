shader_type spatial;
// Капля-штрих дождя (частица). Ось Y частицы (align_y) = скорость → штрих вытянут
// вдоль полёта (наклон по ветру); квад разворачивается к камере вокруг этой оси.
// У каждой капли (INSTANCE_ID) своя длина, толщина и яркость — дождь не «гребёнкой».
// Аддитивно: в тёмный шторм штрихи светлее фона, на ярком небе почти не видны.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(0.80, 0.85, 0.92, 0.30);
uniform float width = 0.008;
uniform float length = 0.75;
uniform float light = 1.0;      // освещённость сцены (день/ночь/вспышка молнии)
uniform float near_fade = 1.4;
uniform float far_fade = 20.0;

varying float v_fade;
varying float v_bright;

float h1(float n) { return fract(sin(n * 12.9898 + 4.1) * 43758.5453); }

void vertex() {
	vec3 c = MODEL_MATRIX[3].xyz;
	vec3 d = normalize(MODEL_MATRIX[1].xyz);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 v = normalize(cam - c);
	vec3 r = normalize(cross(d, v));
	float dist = distance(cam, c);
	float id = float(INSTANCE_ID);
	float rl = mix(0.45, 1.5, h1(id));
	float rw = mix(0.6, 1.3, h1(id + 17.0));
	v_bright = mix(0.35, 1.25, h1(id + 41.0));
	// дальние капли чуть толще, чтобы не мерцать между пикселями
	float w = width * rw * (1.0 + dist * 0.07);
	vec3 wp = c + r * VERTEX.x * w + d * VERTEX.y * length * rl;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wp, 1.0);
	// у самой камеры — мягкое появление (без «палок» в лицо), вдали — растворение
	v_fade = smoothstep(near_fade * 0.5, near_fade * 1.6, dist) * (1.0 - smoothstep(far_fade * 0.5, far_fade, dist));
}

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	across *= across;
	float along = smoothstep(0.0, 0.4, UV.y) * smoothstep(1.0, 0.7, UV.y);
	float l = clamp(light, 0.35, 1.6);
	ALBEDO = color.rgb * l;
	ALPHA = color.a * across * along * v_fade * v_bright;
}
