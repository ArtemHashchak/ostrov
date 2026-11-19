shader_type spatial;
// Дальнее дерево-«снимок»: квад, повёрнутый к камере вокруг вертикали (цилиндрический
// билборд). Текстура — снимок вида сбоку (TreeImpostors.bake). Освещение — сценой
// (не запечено): нормаль смотрит к камере и вверх, поэтому ночью/в шторм деревья темнеют
// вместе с островом. Появляется дизерингом на fade_in.x..fade_in.y (перекрытие с LOD2).
render_mode cull_disabled, depth_draw_opaque, diffuse_lambert_wrap, specular_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 size = vec2(10.0, 10.0);
uniform float y0 = 0.0;
uniform vec2 fade_in = vec2(595.0, 650.0);
// растворение к границе «Дальности видимости» (ViewDistance; на «Максимуме» — далеко)
uniform vec2 fade_out = vec2(1.0e8, 1.1e8);
uniform float ready = 0.0;
global uniform float weather_wetness;

varying float v_fade;
varying float v_var;

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 to_cam = CAMERA_POSITION_WORLD - o;
	vec2 tc = normalize(to_cam.xz + vec2(1e-4, 0.0));
	vec3 right = vec3(tc.y, 0.0, -tc.x);
	vec3 wp = o + right * (VERTEX.x * size.x * s) + vec3(0.0, (y0 + VERTEX.y * size.y) * s, 0.0);
	mat4 inv = inverse(MODEL_MATRIX);
	VERTEX = (inv * vec4(wp, 1.0)).xyz;
	vec3 nw = normalize(vec3(tc.x, 0.0, tc.y) * 0.55 + vec3(0.0, 0.85, 0.0));
	NORMAL = normalize((inv * vec4(nw, 0.0)).xyz);
	float d = length(to_cam);
	v_fade = smoothstep(fade_in.x, fade_in.y, d) * (1.0 - smoothstep(fade_out.x, fade_out.y, d)) * ready;
	v_var = fract(sin(dot(o.xz, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
}

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	// дизер появления (4×4 Байер): без прозрачного прохода и без «выскакивания»
	ivec2 p = ivec2(FRAGCOORD.xy) % 4;
	int idx = p.x + p.y * 4;
	float bayer[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	if (v_fade < 1.0 && (bayer[idx] + 0.5) / 16.0 > v_fade) {
		discard;
	}
	ALBEDO = c.rgb * (1.0 + v_var * 0.18) * (1.0 - 0.18 * weather_wetness);
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.45;
	ROUGHNESS = 0.9;
	BACKLIGHT = c.rgb * 0.25;
}
