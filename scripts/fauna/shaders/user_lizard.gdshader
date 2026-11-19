shader_type spatial;
// Кожа ящерицы из пака пользователя (Ящерицы/lizard_model.blend): авторские текстуры
// (цвет, нормали, шероховатость). Исходник — голубая ящерица с оранжевыми пятнами; под вид
// перекрашивается «палитрой»: яркость исходника → от тёмного к светлому цвету вида, оранжевые
// пятна → цвет крапа вида (игуана — оливково-зелёная, варан — серо-бурый с жёлтым крапом).
// В дождь кожа темнеет и блестит.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D rough_tex : hint_roughness_r, filter_linear_mipmap, repeat_disable;
uniform float hue_shift = 0.0;          // доля оборота (0..1)
uniform float saturation = 1.0;
uniform float value_k = 1.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform float spot_warm = 0.0;          // усилить тёплые пятна (варан)
uniform float use_palette = 1.0;
uniform vec3 col_dark : source_color = vec3(0.10, 0.13, 0.07);
uniform vec3 col_light : source_color = vec3(0.56, 0.6, 0.42);
uniform vec3 col_spot : source_color = vec3(0.42, 0.36, 0.18);
uniform float contrast = 1.0;
uniform float wetness = 0.0;
global uniform float weather_wetness;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}
vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * clamp(p - 1.0, 0.0, 1.0);
}

void fragment() {
	vec3 base = texture(albedo_tex, UV).rgb;
	vec3 hsv = rgb2hsv(base);
	// тёплые (оранжевые) пятна исходника не крутим — это узор; крутим только голубую «основу»
	float warm = smoothstep(0.05, 0.02, abs(hsv.x - 0.07)) * smoothstep(0.25, 0.45, hsv.y);
	vec3 shifted = hsv;
	shifted.x = fract(hsv.x + hue_shift);
	shifted.y = clamp(hsv.y * saturation, 0.0, 1.0);
	shifted.z = hsv.z * value_k;
	vec3 col = hsv2rgb(shifted) * tint;
	vec3 spot = mix(base, base * vec3(1.15, 0.95, 0.6), spot_warm);
	col = mix(col, spot * value_k, warm * (0.6 + 0.4 * spot_warm));
	if (use_palette > 0.5) {
		// яркость исходника (0.25..0.85) → палитра вида; детали чешуи сохраняются
		float lum = dot(base, vec3(0.299, 0.587, 0.114));
		float t = clamp((lum - 0.25) / 0.6, 0.0, 1.0);
		t = clamp((t - 0.5) * contrast + 0.5, 0.0, 1.0);
		vec3 pal = mix(col_dark, col_light, t);
		// пятна: тёплый оттенок исходника (широкий допуск по тону)
		float spotm = smoothstep(0.16, 0.04, min(hsv.x, 1.0 - hsv.x) ) * smoothstep(0.2, 0.4, hsv.y);
		col = mix(pal, col_spot * (0.7 + 0.6 * t), spotm);
	}
	float wet = clamp(max(wetness, weather_wetness), 0.0, 1.0);
	ALBEDO = col * mix(1.0, 0.82, wet);
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = 1.0;
	float r = texture(rough_tex, UV).r;
	ROUGHNESS = mix(r, r * 0.35, wet);
	SPECULAR = mix(0.4, 0.6, wet);
}
