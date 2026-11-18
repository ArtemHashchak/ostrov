shader_type spatial;
// Тропический рельеф: мокрый/сухой песок, луг, подстилка джунглей, ил мангров,
// скалы/утёсы (трипланар), коралловый гравий под водой, каустика на мелководье.
// Веса биомов — в цвете вершин: R — джунгли, G — болото/мангры, B — утёс.

uniform sampler2D sand_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D wet_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D jungle_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D jungle_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D mud_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D volc_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D volc_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D seabed_albedo : source_color, filter_linear_mipmap, repeat_enable;

uniform float tile = 0.2;
uniform float rock_tile = 0.07;
uniform float water_level = 0.0;   // текущий уровень (прилив)
uniform float sand_top = 1.25;
uniform float grass_start = 1.75;
uniform float rock_slope = 0.74;
uniform float time_s = 0.0;
uniform vec3 sand_tint : source_color = vec3(1.3, 1.22, 1.04);

varying vec3 wpos;
varying vec3 wnrm;
varying vec3 biome;
varying float volcanic;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	biome = COLOR.rgb;
	volcanic = COLOR.a;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

// две шкалы одной текстуры — меньше видны повторы
vec3 tex2(sampler2D t, vec2 uv) {
	return mix(texture(t, uv).rgb, texture(t, uv * 0.37 + 0.13).rgb, 0.35);
}

vec3 tri(sampler2D t, vec3 p, vec3 n, float s) {
	vec3 b = pow(abs(n), vec3(4.0));
	b /= (b.x + b.y + b.z);
	return texture(t, p.zy * s).rgb * b.x + texture(t, p.xz * s).rgb * b.y + texture(t, p.xy * s).rgb * b.z;
}

void fragment() {
	vec2 uv = wpos.xz * tile;
	float h = wpos.y;
	float slope = wnrm.y;
	float macro = vnoise(wpos.xz * 0.025) * 0.6 + vnoise(wpos.xz * 0.11) * 0.4;

	vec3 sand = tex2(sand_albedo, uv) * sand_tint;
	vec3 wet = texture(wet_albedo, uv).rgb;
	vec3 grass = tex2(grass_albedo, uv * 0.8);
	grass *= mix(vec3(0.70, 0.95, 0.55), vec3(0.88, 1.02, 0.70), macro);
	vec3 jungle = tex2(jungle_albedo, uv * 0.9);
	// подлесок: листовой опад вперемешку с мхом/папоротником
	jungle = mix(jungle, grass * vec3(0.62, 0.78, 0.55), 0.35 + 0.3 * macro);
	vec3 mud = texture(mud_albedo, uv).rgb;
	vec3 rock = tri(rock_albedo, wpos, wnrm, rock_tile);
	vec3 seabed = tex2(seabed_albedo, uv * 0.7);
	vec3 volc = tri(volc_albedo, wpos, wnrm, rock_tile * 1.6) * mix(vec3(0.78), vec3(0.95, 0.9, 0.86), macro);

	// мокрая полоса двигается с приливом
	float k_wet = 1.0 - smoothstep(water_level - 0.1, water_level + 0.55 + macro * 0.25, h);
	float k_grass = smoothstep(sand_top + macro * 0.3, grass_start + macro * 0.4, h);
	float k_jungle = clamp(biome.r * 1.15, 0.0, 1.0) * k_grass;
	float k_mud = clamp(biome.g, 0.0, 1.0) * (1.0 - smoothstep(water_level + 1.6, water_level + 2.6, h));
	float k_rock = max(1.0 - smoothstep(rock_slope - 0.1, rock_slope + 0.06, slope), clamp(biome.b, 0.0, 1.0) * (1.0 - smoothstep(0.92, 0.98, slope)) * 0.85);
	float k_sea = 1.0 - smoothstep(water_level - 1.6, water_level - 0.4, h);

	vec3 col = mix(sand, wet, k_wet);
	col = mix(col, grass, k_grass);
	col = mix(col, jungle, k_jungle);
	col = mix(col, mud, k_mud);
	col = mix(col, rock, k_rock);
	// вулкан: тёмная порода и пепел (поверх травы, но не у самой воды)
	float k_volc = clamp(volcanic, 0.0, 1.0) * smoothstep(water_level + 0.8, water_level + 2.5, h);
	col = mix(col, mix(volc, volc * vec3(0.55, 0.52, 0.5), 1.0 - slope), k_volc);
	// чёрный вулканический песок у подножия
	col = mix(col, col * vec3(0.42, 0.42, 0.44), clamp(volcanic, 0.0, 1.0) * (1.0 - smoothstep(water_level + 1.0, water_level + 2.6, h)) * 0.6);
	// мелководье — светлый коралловый песок, глубже — галька/коралл
	vec3 bed = mix(sand * 1.05, seabed * vec3(0.9, 0.97, 1.0), smoothstep(water_level - 1.5, water_level - 6.0, h) * (0.5 + 0.5 * macro));
	col = mix(col, bed, k_sea);

	// под водой: синеватый тон по глубине и каустика
	float depth = max(water_level - h, 0.0);
	if (depth > 0.0) {
		vec2 cp = wpos.xz * 0.35;
		float c1 = sin(cp.x * 2.1 + time_s * 1.3 + sin(cp.y * 1.7 + time_s)) ;
		float c2 = sin(cp.y * 2.4 - time_s * 1.1 + sin(cp.x * 1.3 - time_s * 0.7));
		float caust = pow(max(0.0, 1.0 - abs(c1 + c2) * 0.6), 6.0) * exp(-depth * 0.35);
		col *= mix(vec3(1.0), vec3(0.55, 0.78, 0.82), clamp(depth * 0.18, 0.0, 0.85));
		col += vec3(0.55, 0.65, 0.55) * caust * 0.35;
	}
	ALBEDO = col;

	vec3 n_s = texture(sand_normal, uv).rgb;
	vec3 n_g = texture(grass_normal, uv * 0.8).rgb;
	vec3 n_j = texture(jungle_normal, uv * 0.9).rgb;
	vec3 n_r = tri(rock_normal, wpos, wnrm, rock_tile);
	vec3 nm = mix(n_s, n_g, k_grass);
	nm = mix(nm, n_j, k_jungle);
	nm = mix(nm, n_r, k_rock);
	nm = mix(nm, tri(volc_normal, wpos, wnrm, rock_tile * 1.6), k_volc);
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = mix(1.0, 1.6, k_rock);
	ROUGHNESS = mix(mix(0.93, 0.35, k_wet * (1.0 - k_grass)), 0.95, max(max(k_grass, k_rock), k_volc));
	SPECULAR = mix(0.3, 0.65, k_wet * (1.0 - k_grass));
}
