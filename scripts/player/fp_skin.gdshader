shader_type spatial;
// Кожа рук от первого лица. Цвет, ногти (COLOR.a) и затенение складок запечены в
// вершинах (tools/gen_fp_hands.py). Здесь — поры и мелкий рельеф кожи (bump по
// производным экрана, без текстур и касательных), пятнистость, блеск ногтей,
// подповерхностное рассеяние (Forward+) и просвет тонких мест против солнца.
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 tint : source_color = vec3(1.0);
uniform float bump_mm = 0.09;      // глубина пор, мм
uniform float sss = 0.45;
uniform float dirt = 0.25;         // «неделя на острове»
uniform float wet = 0.0;           // v5 (агент D): мокрые руки — темнее, блестят, капли (WetBody)

varying vec3 rp;       // позиция в покое (метры) — шум не «плывёт» при сгибе пальцев
varying float nail_m;
varying float dorsal;

void vertex() {
	rp = vec3(UV.x, UV2.x, UV.y);
	nail_m = COLOR.a;
	dorsal = UV2.y;
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
				   mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				   mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fragment() {
	// Мелкий рельеф: поры + «кожная сетка» (растянутый шум) + крупная неровность.
	float pores = vnoise(rp * 2600.0);
	float lines = vnoise(rp * vec3(700.0, 2400.0, 700.0));
	float lumps = vnoise(rp * 260.0);
	float h = (pores * 0.45 + lines * 0.35 + lumps * 0.6) * (1.0 - nail_m * 0.85);
	float hm = h * bump_mm * 0.001;
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float hx = dFdx(hm);
	float hy = dFdy(hm);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (hx * r1 + hy * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad);

	vec3 c = COLOR.rgb * tint;
	// пятнистость, веснушки на тыле, грязь на ладонях и кончиках
	float blot = vnoise(rp * 120.0) * 0.5 + vnoise(rp * 420.0) * 0.5;
	c *= 0.96 + 0.07 * blot;
	float freckle = smoothstep(0.82, 0.95, vnoise(rp * 900.0)) * clamp(dorsal, 0.0, 1.0);
	c = mix(c, c * vec3(0.84, 0.74, 0.68), freckle * 0.3);
	float grime = smoothstep(0.45, 0.8, vnoise(rp * 180.0 + 3.0)) * dirt * clamp(0.6 - dorsal, 0.0, 1.0);
	c = mix(c, c * vec3(0.62, 0.55, 0.48), grime);
	// грязь под краем ногтя
	c = mix(c, c * 0.7, nail_m * smoothstep(0.55, 0.8, vnoise(rp * 600.0)) * dirt);
	// мокрая кожа: темнее и насыщеннее, гладкий блеск плёнки воды, капли (бусины) на тыле
	float beads = smoothstep(0.78, 0.86, vnoise(rp * 520.0 + vec3(0.0, TIME * 0.004, 0.0))) * clamp(dorsal + 0.3, 0.0, 1.0);
	c *= 1.0 - 0.12 * wet;
	ALBEDO = c;
	ROUGHNESS = mix(mix(0.5 + 0.12 * pores + grime * 0.15, 0.24, nail_m), mix(0.16, 0.05, beads), wet);
	SPECULAR = mix(mix(0.38, 0.5, nail_m), 0.6, wet);
	RIM = 0.08;
	RIM_TINT = 0.7;
	BACKLIGHT = vec3(0.14, 0.05, 0.03) * (1.0 - nail_m);
#if CURRENT_RENDERER == RENDERER_FORWARD_PLUS
	SSS_STRENGTH = sss * (1.0 - nail_m);
#endif
}
