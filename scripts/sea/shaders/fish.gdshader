shader_type spatial;
// Рыба в стае (MultiMesh): цвет — INSTANCE_CUSTOM.rgb, фаза — INSTANCE_CUSTOM.a.
// COLOR.r вершины — «спинность», COLOR.g — полосы/пятна.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform float fish_length = 0.32;
uniform float wiggle = 0.06;
uniform float speed = 11.0;

varying vec4 v_custom;
varying vec3 v_local;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	v_local = VERTEX;
	float t = clamp(VERTEX.z / fish_length + 0.5, 0.0, 1.0);
	VERTEX.x += sin(t * 4.0 - TIME * speed - v_custom.a * 6.2831) * wiggle * fish_length * t * t * 2.0;
}

void fragment() {
	vec3 base = v_custom.rgb;
	float dorsal = COLOR.r;
	vec3 back = base * 0.55;
	vec3 belly = mix(base, vec3(0.92, 0.93, 0.9), 0.55);
	vec3 col = mix(belly, back, smoothstep(0.35, 0.75, dorsal));
	col *= COLOR.g;
	ALBEDO = col;
	ROUGHNESS = 0.25;
	SPECULAR = 0.7;
	METALLIC = 0.15; // чешуйчатый блеск
}
