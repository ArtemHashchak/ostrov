shader_type spatial;
// Валуны пака пользователя (Rocks/Stone0XX): поверхность камня пользователя кладётся трипланарно в мировых
// координатах — одна плотность текселей на любом размере/повороте валуна, без швов UV.
// Нормаль — «whiteout»-смешение трёх проекций; сверху — мох/лишайник по вогнутостям (джунгли),
// у основания — налипший песок/пыль; в дождь камень темнеет и блестит (weather_wetness).
render_mode cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orh_tex : filter_linear_mipmap_anisotropic, repeat_enable;   // R — AO, G — шероховатость, B — высота
uniform float tile = 0.75;              // повторов на метр (текстура ≈ 1.3 м)
uniform vec3 tint : source_color = vec3(1.0);
uniform float gain = 1.0;               // яркость (калибровка под общий ряд)
uniform float normal_depth = 1.2;
uniform float moss = 0.0;               // 0..1 — сколько мха на верхних гранях
uniform vec3 moss_color : source_color = vec3(0.13, 0.19, 0.06);
uniform float dust = 0.35;              // пыль/песок у основания
uniform vec3 dust_color : source_color = vec3(0.6, 0.53, 0.4);
global uniform float weather_wetness;

varying vec3 wp;
varying vec3 wn;
varying float hb;   // высота над основанием, м

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	hb = wp.y - MODEL_MATRIX[3].y;
}

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), u.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	vec3 n = normalize(wn);
	vec3 b = pow(abs(n), vec3(5.0));
	b /= (b.x + b.y + b.z);
	// случайный сдвиг по валуну — соседние валуны не повторяют рисунок
	vec2 off = MODEL_MATRIX[3].xz * 0.37;
	vec2 ux = wp.zy * tile + off;
	vec2 uy = wp.xz * tile + off.yx;
	vec2 uz = wp.xy * tile - off;
	vec3 a = texture(albedo_tex, ux).rgb * b.x + texture(albedo_tex, uy).rgb * b.y + texture(albedo_tex, uz).rgb * b.z;
	vec3 o = texture(orh_tex, ux).rgb * b.x + texture(orh_tex, uy).rgb * b.y + texture(orh_tex, uz).rgb * b.z;
	// нормали проекций (OpenGL: G вверх по картинке = против v) → мир, смешение whiteout
	vec3 tx = texture(normal_tex, ux).rgb * 2.0 - 1.0;
	vec3 ty = texture(normal_tex, uy).rgb * 2.0 - 1.0;
	vec3 tz = texture(normal_tex, uz).rgb * 2.0 - 1.0;
	tx.y = -tx.y; ty.y = -ty.y; tz.y = -tz.y;
	tx.xy *= normal_depth; ty.xy *= normal_depth; tz.xy *= normal_depth;
	vec3 nx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
	vec3 ny = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
	vec3 nz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
	vec3 wnrm = normalize(nx.zyx * b.x + ny.xzy * b.y + nz.xyz * b.z);

	vec3 col = a * tint * gain;
	float rough = o.g;
	// мох: верхние грани и вогнутости (тёмная AO, низкая высота), пятнами
	float up = smoothstep(0.25, 0.85, wnrm.y);
	float patch = vn(wp.xz * 1.7) * 0.6 + vn(wp.xz * 5.3) * 0.4;
	float km = moss * up * smoothstep(0.35, 0.65, patch + (1.0 - o.b) * 0.35 + (1.0 - o.r) * 0.3);
	col = mix(col, moss_color * (0.75 + 0.5 * o.b), km);
	rough = mix(rough, 0.92, km);
	// у основания — песок/пыль (камень «сидит» в грунте)
	float kd = dust * (1.0 - smoothstep(0.02, 0.22, hb)) * (0.6 + 0.4 * vn(wp.xz * 9.0));
	col = mix(col, dust_color, kd);
	// дождь: темнеет и блестит, сильнее на верхних гранях
	float wet = clamp(weather_wetness, 0.0, 1.0) * mix(0.6, 1.0, up);
	col *= mix(1.0, 0.58, wet);
	rough = mix(rough, 0.22, wet * (1.0 - km * 0.6));

	ALBEDO = col;
	AO = o.r;
	AO_LIGHT_AFFECT = 0.25;
	ROUGHNESS = rough;
	SPECULAR = 0.4;
	NORMAL = normalize((VIEW_MATRIX * vec4(wnrm, 0.0)).xyz);
}
