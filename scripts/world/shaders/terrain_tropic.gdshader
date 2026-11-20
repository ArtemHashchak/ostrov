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
global uniform float weather_wetness;  // CONTRACT_WEATHER: сырость после дождя
global uniform float weather_rain;     // CONTRACT_WEATHER: сила дождя сейчас (рябь в лужах)
global uniform float weather_storm;    // CONTRACT_WEATHER: сила шторма (каустика гаснет под тучами)
uniform vec3 sand_tint : source_color = vec3(1.3, 1.22, 1.04);

// Пляжный песок из пака пользователя (Грунт/Песок): высота/шероховатость; утоптанный песок со следами.
// use_beach_sand = 0 — прежний песок coast_sand_01.
uniform float use_beach_sand = 0.0;
uniform float sand_tile = 1.0;                // ~1 м на повтор: зерно и мелкая рябь, без «пузырей»
uniform sampler2D sand_height : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_rough : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D tramp_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tramp_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D tramp_height : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float tramp_tile = 0.66;              // 1.5 м на повтор (как у исходника)
// Мшистая земля пользователя (Грунт/Procedural Mossy Dirt → assets/textures/mossy_ground): пятна мха
// и сырой земли в подлеске. rhm: R — шероховатость, G — высота, B — маска мха.
uniform float use_mossy = 0.0;
uniform sampler2D mossy_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D mossy_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D mossy_rhm : filter_linear_mipmap, repeat_enable;
uniform float mossy_tile = 0.42;              // 2.4 м на повтор (масштаб узлов автора)
// Карта следов (SandTracks): R — глубина лунки 0..1, G — валик выдавленного песка 0..1;
// rect = (x0, z0, размер окна м, вкл)
global uniform sampler2D sand_tracks_map : filter_linear, repeat_disable;
global uniform vec4 sand_tracks_rect;
const float TRACK_DEPTH = 0.055;   // м — полная глубина отпечатка (пятка взрослого в сухом песке)
const float RIM_H = 0.32;          // высота валика в долях глубины
float track_f(vec2 p) {            // «глубина» поля следов: >0 — лунка, <0 — валик
	vec2 m = texture(sand_tracks_map, p).rg;
	return m.r - m.g * RIM_H;
}

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

// Рябь от капель в луже: сетка ячеек, в каждой — расходящееся кольцо со своей фазой.
// Возвращает наклон нормали (xy). Два слоя со сдвигом — без видимой сетки.
vec2 rain_ripples(vec2 p, float t) {
	vec2 g = vec2(0.0);
	for (int k = 0; k < 2; k++) {
		vec2 q = p + vec2(float(k) * 0.37, float(k) * 0.61);
		vec2 cell = floor(q);
		vec2 f = fract(q) - 0.5;
		vec2 o = vec2(hash(cell), hash(cell + 7.3)) - 0.5;
		float ph = fract(t * (0.9 + 0.3 * hash(cell + 3.1)) + hash(cell + 1.7));
		vec2 d = f - o * 0.5;
		float r = length(d);
		float rr = ph * 0.45;
		float ring = sin((r - rr) * 55.0) * exp(-abs(r - rr) * 18.0) * (1.0 - ph);
		g += (d / max(r, 1e-3)) * ring;
	}
	return g * 0.5;
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
	float sh = 0.5;
	float tr = 0.0;     // глубина следа 0..1 (после параллакса)
	float trim = 0.0;   // валик 0..1
	vec2 tuv = vec2(-1.0);
	vec2 tg = vec2(0.0);  // градиент поля следов (для нормали)
	vec2 sp = wpos.xz;    // точка песка, видимая через параллакс лунки
	if (use_beach_sand > 0.5 && sand_tracks_rect.w > 0.5) {
		tuv = (wpos.xz - sand_tracks_rect.xy) / sand_tracks_rect.z;
		if (all(greaterThan(tuv, vec2(0.01))) && all(lessThan(tuv, vec2(0.99)))) {
			// луч от камеры уходит в лунку: смещение tuv на единицу глубины
			vec3 wv = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
			vec2 dxz = -wv.xz / max(wv.y, 0.18) * (TRACK_DEPTH / sand_tracks_rect.z);
			float pre = abs(track_f(tuv)) + abs(track_f(tuv + dxz)) + abs(track_f(tuv + dxz * 0.5));
			if (pre > 0.002) {
				// POM: 14 шагов от верха валика вниз, потом линейное уточнение
				float t = -RIM_H;
				float dt = (1.0 + RIM_H) / 14.0;
				float f = track_f(tuv + dxz * t);
				float pt = t;
				float pf = f;
				for (int i = 0; i < 14; i++) {
					if (t >= f) { break; }
					pt = t; pf = f;
					t += dt;
					f = track_f(tuv + dxz * t);
				}
				float den = (pf - pt) - (f - t);
				float tt = mix(pt, t, clamp((pf - pt) / max(den, 1e-4), 0.0, 1.0));
				tuv += dxz * tt;
				sp = wpos.xz + dxz * tt * sand_tracks_rect.z;
				vec2 m = texture(sand_tracks_map, tuv).rg;
				tr = m.r;
				trim = m.g;
				float e = 1.5 / 2048.0;
				tg = vec2(track_f(tuv + vec2(e, 0.0)) - track_f(tuv - vec2(e, 0.0)),
						track_f(tuv + vec2(0.0, e)) - track_f(tuv - vec2(0.0, e))) * (TRACK_DEPTH / (2.0 * e * sand_tracks_rect.z));
			}
		}
	}
	// --- пляжный песок пользователя: две шкалы (вторая повернута — нет сетки повтора) + пятна оттенка
	vec2 suv = sp * sand_tile;
	vec2 suv2 = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * suv * 0.47 + vec2(0.37, 0.71);
	if (use_beach_sand > 0.5) {
		vec3 s1 = texture(sand_albedo, suv).rgb;
		vec3 s2 = texture(sand_albedo, suv2).rgb;
		float mv = vnoise(wpos.xz * 0.06) * 0.55 + vnoise(wpos.xz * 0.23 + 3.0) * 0.3 + vnoise(wpos.xz * 0.9 + 9.0) * 0.15;
		sand = mix(s1, s2, 0.35) * sand_tint;
		// светлее у гребня пляжа, теплее/темнее в низинах (цвет, не рельеф)
		sand *= mix(vec3(0.94, 0.93, 0.91), vec3(1.04, 1.03, 1.01), mv);
		sh = mix(texture(sand_height, suv).r, texture(sand_height, suv2).r, 0.35);
		if (tr + trim > 0.003) {
			vec2 puv = sp * tramp_tile;
			float th = texture(tramp_height, puv).r;
			// дно отпечатка: утоптанное зерно пользователя, влажнее и темнее (песок под коркой сырой),
			// глубже — темнее; валик — сухой рыхлый песок, чуть светлее
			float k = smoothstep(0.02, 0.35, tr) * (0.75 + 0.25 * smoothstep(0.2, 0.8, th));
			vec3 tcol = texture(tramp_albedo, puv).rgb * sand_tint;
			tcol *= dot(sand, vec3(0.333)) / max(dot(tcol, vec3(0.333)), 0.02);
			sand = mix(sand, tcol * vec3(0.9, 0.88, 0.85), k * 0.75);
			// лунка темнее (тень стенок + сырой песок) — читается с высоты глаз; валик светлее (сухой, рыхлый)
			sand *= 1.0 - 0.38 * smoothstep(0.05, 0.9, tr);
			sand *= 1.0 + 0.12 * trim * (1.0 - k);
			sh = mix(sh, th, k);
		}
	}
	// мокрый песок: тот же тёплый песок, темнее (текстура damp_sand без тинта давала
	// серые «лужи» на широких отмелях выше уровня моря)
	vec3 wet = mix(sand * 0.62, texture(wet_albedo, uv).rgb * sand_tint * 0.85, 0.45);
	wet *= mix(0.92, 1.06, macro);
	vec3 grass = tex2(grass_albedo, uv * 0.8);
	grass *= mix(vec3(0.70, 0.95, 0.55), vec3(0.88, 1.02, 0.70), macro);
	vec3 jungle = tex2(jungle_albedo, uv * 0.9);
	// подлесок: листовой опад вперемешку с мхом/папоротником
	jungle = mix(jungle, grass * vec3(0.62, 0.78, 0.55), 0.35 + 0.3 * macro);
	// мшистая земля: крупные пятна (сырые низины, ровные места), вторая шкала повернута — без повтора
	float k_moss = 0.0;
	vec2 muv = wpos.xz * mossy_tile;
	vec2 muv2 = mat2(vec2(0.6, 0.8), vec2(-0.8, 0.6)) * muv * 0.41 + vec2(0.21, 0.57);
	if (use_mossy > 0.5) {
		vec3 mcol = mix(texture(mossy_albedo, muv).rgb, texture(mossy_albedo, muv2).rgb, 0.35);
		float pm = vnoise(wpos.xz * 0.07) * 0.55 + vnoise(wpos.xz * 0.27 + 7.0) * 0.3 + vnoise(wpos.xz * 1.1 + 2.0) * 0.15;
		k_moss = smoothstep(0.46, 0.68, pm) * smoothstep(0.8, 0.95, slope) * 0.85;
		// опад поверх мха не исчезает целиком: светлые листья подлеска проступают по краям пятен
		float litter = smoothstep(0.55, 0.8, dot(jungle, vec3(0.333)) / max(dot(mcol, vec3(0.333)), 0.02) * 0.5);
		jungle = mix(jungle, mcol, k_moss * (1.0 - litter * 0.5 * (1.0 - k_moss)));
	}
	vec3 mud = texture(mud_albedo, uv).rgb;
	vec3 rock = tri(rock_albedo, wpos, wnrm, rock_tile);
	vec3 seabed = tex2(seabed_albedo, uv * 0.7);
	vec3 volc = tri(volc_albedo, wpos, wnrm, rock_tile * 1.6) * mix(vec3(0.78), vec3(0.95, 0.9, 0.86), macro);

	// мокрая полоса двигается с приливом
	float k_wet = 1.0 - smoothstep(water_level - 0.1, water_level + 0.55 + macro * 0.25, h);
	// на новом песке граница мокрого рваная: вода дольше стоит в ямках
	k_wet = clamp(k_wet + (0.5 - sh) * 0.5 * use_beach_sand * k_wet * (1.0 - k_wet) * 4.0, 0.0, 1.0);
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
		// каустика только под водой заметной глубины: у кромки (волна то открывает, то закрывает песок)
		// её нет — иначе на мокром песке у воды «светящиеся линии»; под тучами/в дождь гаснет
		float caust = pow(max(0.0, 1.0 - abs(c1 + c2) * 0.6), 6.0) * exp(-depth * 0.35)
				* smoothstep(0.35, 1.4, depth) * (1.0 - 0.85 * clamp(max(weather_storm, weather_rain), 0.0, 1.0));
		col *= mix(vec3(1.0), vec3(0.55, 0.78, 0.82), clamp(depth * 0.18, 0.0, 0.85));
		col += vec3(0.55, 0.65, 0.55) * caust * 0.35;
	}
	// дождь: суша темнеет и блестит (песок/камень сильнее, трава слабее)
	float rain_wet = weather_wetness * (1.0 - k_sea) * (1.0 - k_wet);
	float soak = mix(0.62, 0.8, k_grass * (1.0 - k_rock));
	col *= mix(1.0, soak, rain_wet);
	// лужи: ровные места вне скал и прибоя, проступают по мере намокания (песок впитывает)
	float flatness = smoothstep(0.972, 0.995, wnrm.y);
	float pn = vnoise(wpos.xz * 0.11) * 0.65 + vnoise(wpos.xz * 0.43 + 5.0) * 0.35;
	float grow = smoothstep(0.35, 0.95, weather_wetness);
	float puddle = smoothstep(0.66 - 0.1 * grow, 0.72 - 0.1 * grow, pn) * grow * flatness
			* (1.0 - k_sea) * (1.0 - k_wet) * (1.0 - k_rock) * (1.0 - k_volc * 0.6) * mix(0.25, 1.0, max(k_grass, k_mud));
	col = mix(col, col * 0.42 + vec3(0.015, 0.02, 0.025), puddle);
	ALBEDO = col;

	vec3 n_s = texture(sand_normal, uv).rgb;
	if (use_beach_sand > 0.5) {
		n_s = mix(texture(sand_normal, suv).rgb, texture(sand_normal, suv2).rgb, 0.35);
		if (tr + trim > 0.003) {
			n_s = mix(n_s, texture(tramp_normal, sp * tramp_tile).rgb, smoothstep(0.02, 0.4, tr) * 0.8);
			// стенки лунки и валик: настоящий наклон по градиенту поля следов (м/м); итог — поверх
			// мелкой нормали песка (глубина нормали песка ниже, поэтому делим на неё)
			vec3 nb = n_s * 2.0 - 1.0;
			vec3 nt = normalize(vec3(nb.xy + tg / 0.7, max(nb.z, 0.2)));
			n_s = nt * 0.5 + 0.5;
		}
	}
	vec3 n_g = texture(grass_normal, uv * 0.8).rgb;
	vec3 n_j = texture(jungle_normal, uv * 0.9).rgb;
	if (k_moss > 0.001) {
		n_j = mix(n_j, mix(texture(mossy_normal, muv).rgb, texture(mossy_normal, muv2).rgb, 0.35), k_moss);
	}
	vec3 n_r = tri(rock_normal, wpos, wnrm, rock_tile);
	vec3 nm = mix(n_s, n_g, k_grass);
	nm = mix(nm, n_j, k_jungle);
	nm = mix(nm, n_r, k_rock);
	nm = mix(nm, tri(volc_normal, wpos, wnrm, rock_tile * 1.6), k_volc);
	if (puddle > 0.01) {
		vec2 rip = rain_ripples(wpos.xz * 2.6, TIME * 1.1) * clamp(weather_rain * 1.5, 0.0, 1.0);
		nm = mix(nm, vec3(0.5 + rip.x * 0.35, 0.5 + rip.y * 0.35, 1.0), puddle);
	}
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = mix(mix(1.0, 0.7, use_beach_sand * (1.0 - k_grass) * (1.0 - k_sea)), 1.6, k_rock);
	float sand_r = mix(0.93, texture(sand_rough, suv).r, use_beach_sand);
	ROUGHNESS = mix(mix(sand_r, 0.6, k_wet * (1.0 - k_grass)), 0.95, max(max(k_grass, k_rock), k_volc));
	ROUGHNESS = mix(ROUGHNESS, mix(0.32, 0.55, k_grass), rain_wet);
	SPECULAR = mix(mix(0.3, 0.45, k_wet * (1.0 - k_grass)), 0.55, rain_wet * 0.8);
	ROUGHNESS = mix(ROUGHNESS, 0.04, puddle);
	SPECULAR = mix(SPECULAR, 0.65, puddle);
}
