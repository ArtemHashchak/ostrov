shader_type canvas_item;
// Жажда (V5): экран мутнеет по краям и чуть «плывёт».
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec2 uv = SCREEN_UV;
	float edge = smoothstep(0.15, 0.75, length(uv - vec2(0.5)) * 1.4);
	float lod = amount * (1.5 + 3.0 * edge);
	vec2 wob = vec2(sin(TIME * 1.7 + uv.y * 9.0), cos(TIME * 1.3 + uv.x * 7.0)) * 0.002 * amount;
	vec3 c = textureLod(screen_tex, uv + wob, lod).rgb;
	c = mix(c, c * vec3(1.05, 0.98, 0.9), amount * 0.4);
	COLOR = vec4(c, clamp(amount * (0.35 + 0.65 * edge) * 1.2, 0.0, 1.0));
}
