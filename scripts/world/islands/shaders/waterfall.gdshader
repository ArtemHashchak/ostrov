shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;
// Водопад: завеса, UV.x — поперёк, UV.y — метры падения от кромки вниз.
// Струи — вытянутый вдоль падения шум, бегущий вниз со скоростью падения;
// у кромки вода плотная и гладкая, ниже распадается на струи и пелену.

uniform float fall_h = 20.0;
uniform vec3 water_color : source_color = vec3(0.70, 0.80, 0.80);
uniform vec3 deep_color : source_color = vec3(0.16, 0.26, 0.25);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	float y = UV.y;                       // м от кромки
	float t = TIME;
	// скорость растёт с падением: смещение ~ sqrt(y)
	float flow = sqrt(max(y, 0.0)) * 4.2 - t * 5.0;
	float streaks = vnoise(vec2(UV.x * 26.0, flow * 0.9)) * 0.6 + vnoise(vec2(UV.x * 61.0 + 4.0, flow * 1.7)) * 0.4;
	float breakup = smoothstep(0.0, fall_h * 0.6, y);
	float dens = mix(0.95, 0.35 + streaks * 0.75, breakup);
	float white = smoothstep(0.45, 0.9, streaks) * (0.35 + breakup * 0.6);
	// края завесы рваные
	float edge = min(UV.x, 1.0 - UV.x);
	float edge_n = vnoise(vec2(flow * 0.6, UV.x * 8.0));
	float e = smoothstep(0.0, 0.08 + edge_n * 0.12, edge);
	ALBEDO = mix(deep_color, water_color, 0.35 + white * 0.65);
	ROUGHNESS = mix(0.08, 0.45, white);
	SPECULAR = 0.5;
	ALPHA = clamp(dens * e, 0.0, 0.96);
	// у подножия — пелена брызг (светлее, прозрачнее)
	float foot = smoothstep(fall_h * 0.82, fall_h, y);
	ALBEDO = mix(ALBEDO, vec3(0.9, 0.93, 0.94), foot * 0.7);
	ALPHA *= 1.0 - foot * 0.35;
}
