shader_type spatial;
// Сплат рельефа по высоте и уклону: мокрый песок → песок → трава → скала.
// Мировые UV (без растяжения на склонах — для скал трипланар по XZ/XY/ZY).
uniform sampler2D sand_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D wet_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float tile = 0.22;
uniform float rock_tile = 0.12;
uniform float water_level = 0.0;
uniform float sand_top = 1.1;
uniform float grass_start = 1.5;
uniform float rock_slope = 0.72;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 tri(sampler2D t, vec3 p, vec3 n, float s) {
	vec3 b = pow(abs(n), vec3(4.0));
	b /= (b.x + b.y + b.z);
	return texture(t, p.zy * s).rgb * b.x + texture(t, p.xz * s).rgb * b.y + texture(t, p.xy * s).rgb * b.z;
}

void fragment() {
	vec2 uv = wpos.xz * tile;
	float h = wpos.y;
	float slope = wnrm.y; // 1 — плоско
	vec3 sand = texture(sand_albedo, uv).rgb;
	vec3 wet = texture(wet_albedo, uv).rgb;
	vec3 grass = texture(grass_albedo, uv * 0.8).rgb;
	vec3 rock = tri(rock_albedo, wpos, wnrm, rock_tile);
	float k_wet = 1.0 - smoothstep(water_level - 0.2, water_level + 0.45, h);
	float k_grass = smoothstep(sand_top, grass_start, h);
	float k_rock = 1.0 - smoothstep(rock_slope - 0.08, rock_slope + 0.06, slope);
	vec3 col = mix(sand, wet, k_wet);
	col = mix(col, grass, k_grass);
	col = mix(col, rock, k_rock);
	ALBEDO = col;
	vec3 n_s = texture(sand_normal, uv).rgb;
	vec3 n_g = texture(grass_normal, uv * 0.8).rgb;
	vec3 n_r = texture(rock_normal, wpos.xz * rock_tile).rgb;
	NORMAL_MAP = mix(mix(n_s, n_g, k_grass), n_r, k_rock);
	NORMAL_MAP_DEPTH = 1.0;
	ROUGHNESS = mix(mix(0.92, 0.55, k_wet), 0.95, max(k_grass, k_rock));
	SPECULAR = mix(0.3, 0.6, k_wet);
}
