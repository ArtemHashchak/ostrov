shader_type spatial;
render_mode cull_disabled;
// Кораллы по референсу пользователя (assets/corals/corals.glb, docs/CORALS_REF.md).
// COLOR — запечённый цвет вершин (альбедо × затенение, светлые кончики);
// INSTANCE_CUSTOM.rgb — оттенок экземпляра (множитель), .a — фаза;
// UV.x — тип части: 0 скелет, 1 мягкая ткань, 2..3 слой ворса, 4..5 карточка атласа,
//        6 нить-скелет (веточка/ворс), 7 нить мягкая (щупальце, полип); UV.y — гибкость 0..1.
// Нити (UV.x ≥ 5.5) разворачиваются к камере — см. coral_common.gdshaderinc.
// Узор полипов/кораллитов — процедурный в координатах модели (pattern: 0 — кораллиты-точки,
// 1 — гребни/извилины, 2 — гладкая ткань с кольцами). Свет сзади + цветной ободок вместо SSS.
// lod_begin/lod_end — полоса расстояний экземпляра (м), в которой этот уровень виден; на краях
// полосы (±lod_fade) экземпляр «растворяется» дизерингом, вне полосы его вершины схлопываются.

#include "res://shaders/sea_push.gdshaderinc"
#include "res://scripts/sea/shaders/coral_common.gdshaderinc"

uniform float sway = 0.0;            // амплитуда качания мягкой ткани
uniform float water_level = 0.0;
uniform float caustic_strength = 0.75;
uniform float rough = 0.72;
uniform float wet_spec = 0.35;
uniform int pattern = 0;
uniform float pattern_scale = 90.0;
uniform float detail = 1.0;          // 0 на дальнем LOD — без узора
uniform float strand_scale = 1.0;    // множитель радиуса нитей (на LOD1 нитей меньше — они толще)
uniform float lod_begin = 0.0;       // 0 — без нижней границы
uniform float lod_end = 0.0;         // 0 — без верхней границы
uniform float lod_fade = 1.5;
uniform sampler2D cards : source_color, filter_linear_mipmap, repeat_disable;   // атлас карточек 2×2

varying vec3 wpos;
varying vec3 tint;
varying vec3 lpos;
varying float hue_k;
varying float soft;
varying float shell;      // 1/2 — слой «ворса» (оболочка над пластиной), 0 — обычная поверхность
varying float card;       // 0 — не карточка, 1..4 — плитка атласа + 1
varying float strand;     // 1 — нить
varying float s_x;        // поперечная координата нити −1..1
varying vec3 s_side;      // базис нити в пространстве вида
varying vec3 s_face;
varying float vis;

float caus(vec2 p, float t) {
	vec2 q = p + vec2(sin(p.y * 1.7 + t * 0.9), cos(p.x * 1.3 - t * 0.7)) * 0.6;
	float a = sin(q.x * 2.1 + t) * sin(q.y * 2.3 - t * 0.8);
	vec2 r = p * 1.6 + vec2(cos(p.y * 1.1 - t * 0.6), sin(p.x * 1.4 + t * 0.5)) * 0.8;
	float b = sin(r.x * 1.9 - t * 0.7) * sin(r.y * 2.2 + t * 0.9);
	float c = 1.0 - abs(a + b) * 0.5;
	return pow(clamp(c, 0.0, 1.0), 7.0);
}

void vertex() {
	tint = INSTANCE_CUSTOM.rgb;
	if (dot(tint, tint) < 0.0001) {
		tint = vec3(1.0);
	}
	float idist = length(CAMERA_POSITION_WORLD - MODEL_MATRIX[3].xyz);
	vis = coral_lod_vis(idist, lod_begin, lod_end, lod_fade);
	hue_k = fract(INSTANCE_CUSTOM.a * 7.13) - 0.5;
	strand = UV.x > 5.5 ? 1.0 : 0.0;
	soft = UV.x > 6.5 ? 1.0 : (UV.x < 1.5 ? UV.x : (UV.x > 3.5 && UV.x < 5.5 ? 1.0 : 0.0));
	shell = (UV.x > 1.5 && UV.x < 3.5) ? UV.x - 2.0 : 0.0;
	card = (UV.x > 3.5 && UV.x < 5.5) ? floor(UV.x - 4.0 + 0.5) + 1.0 : 0.0;
	s_x = UV2.x;
	vec3 axis = NORMAL;
	float h = UV.y;
	if (sway > 0.0 && h > 0.0) {
		float ph = INSTANCE_CUSTOM.a * 6.2831;
		vec3 w0 = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float t = TIME;
		// мягкая ткань колышется: медленная общая волна + быстрая мелкая по точке
		vec2 off = vec2(sin(t * 0.9 + ph + w0.x * 0.6 + w0.z * 0.3) + 0.4 * sin(t * 2.1 + ph * 1.7 + w0.y * 4.0),
				cos(t * 0.8 + ph + w0.z * 0.5) + 0.3 * cos(t * 1.9 + w0.x * 3.0)) * sway * h * h;
		float s = max(length(MODEL_MATRIX[0].xyz), 0.001);
		VERTEX += transpose(mat3(MODEL_MATRIX)) * vec3(off.x, -0.2 * dot(off, off), off.y) / (s * s);
		VERTEX += sea_push_local(MODEL_MATRIX, (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, h);
	}
	if (strand > 0.5) {
		vec3 sd;
		vec3 fd;
		vec3 cam_l = coral_cam_local(MODEL_MATRIX, CAMERA_POSITION_WORLD);
		VERTEX = coral_strand_expand(VERTEX, normalize(axis), UV2.x, UV2.y * strand_scale, cam_l, sd, fd);
		NORMAL = fd;
		s_side = normalize((MODELVIEW_MATRIX * vec4(sd, 0.0)).xyz);
		s_face = normalize((MODELVIEW_MATRIX * vec4(fd, 0.0)).xyz);
	} else {
		s_side = vec3(1.0, 0.0, 0.0);
		s_face = vec3(0.0, 0.0, 1.0);
	}
	lpos = VERTEX;
	if (vis <= 0.0) {
		VERTEX = vec3(0.0);   // экземпляр вне своей полосы LOD — ничего не рисуем
	}
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (vis < 0.999 && vis <= coral_dither(FRAGCOORD.xy)) {
		discard;
	}
	if (strand > 0.5) {
		NORMAL = coral_strand_normal(s_side, s_face, s_x);
	} else if (dot(NORMAL, VIEW) < 0.0) {
		NORMAL = -NORMAL;
	}
	if (shell > 0.5) {
		// ворс: оставляем только «кончики веточек» — точки ячеистого шума, выше слой — точки меньше
		if (detail <= 0.0) {
			discard;
		}
		vec2 q2 = lpos.xz * pattern_scale * 0.32;
		float cd = coral_cells(vec3(q2, shell * 7.3));
		float rad = shell < 0.9 ? 0.36 : 0.24;
		if (cd > rad) {
			discard;
		}
	}
	vec3 col = COLOR.rgb * tint;
	if (card > 0.5) {
		float ti = card - 1.0;
		vec2 auv = (vec2(mod(ti, 2.0), floor(ti / 2.0)) + clamp(UV2, vec2(0.004), vec2(0.996))) * 0.5;
		vec4 tx = texture(cards, auv);
		if (tx.a < 0.35) {
			discard;
		}
		col *= tx.rgb;
	}
	col = mix(col, col.gbr, hue_k * 0.10);
	float cav = 0.0;
	if (detail > 0.0 && card < 0.5) {
		vec3 q = lpos * pattern_scale;
		if (pattern == 0) {
			// кораллиты: тёмные чашечки с светлым ободком
			float c = coral_cells(q);
			cav = 1.0 - smoothstep(0.12, 0.32, c);
			col *= 1.0 - cav * 0.28 * detail;
			col += vec3(0.05) * smoothstep(0.32, 0.42, c) * (1.0 - smoothstep(0.42, 0.55, c)) * detail;
		} else if (pattern == 1) {
			// извилины/гребни лопастей
			float r = sin(q.x * 0.7 + sin(q.z * 0.6) * 2.0) * sin(q.y * 0.65 + sin(q.x * 0.5) * 2.0) * sin(q.z * 0.7 + q.y * 0.3);
			cav = smoothstep(0.0, 0.6, -r);
			col *= 1.0 - cav * 0.22 * detail;
			float c2 = coral_cells(q * 1.8);
			col *= 1.0 - (1.0 - smoothstep(0.1, 0.25, c2)) * 0.12 * detail;
		} else if (strand < 0.5) {
			// гладкая ткань: тонкие кольца вдоль щупалец, светлее к кончикам
			float rings = sin(lpos.y * pattern_scale * 1.3 + lpos.x * 20.0) * 0.5 + 0.5;
			col *= 1.0 - rings * 0.06 * detail;
		}
	}
	float depth = water_level - wpos.y;
	float under = step(0.0, depth);
	float k = caustic_strength * clamp(1.0 - depth / 11.0, 0.0, 1.0) * under;
	float c = caus(wpos.xz * 0.85, TIME * 0.9) + 0.6 * caus(wpos.xz * 1.9 + 3.1, TIME * 1.15);
	vec3 absorb = mix(vec3(1.0), vec3(0.6, 0.86, 0.95), clamp(depth / 10.0, 0.0, 1.0) * under);
	ALBEDO = col * absorb * (1.0 + c * k);
	EMISSION = col * c * k * 0.10;
	ROUGHNESS = rough + cav * 0.15 - soft * 0.15;
	SPECULAR = wet_spec + soft * 0.15;
	// «подповерхностное» рассеяние дёшево: свет сзади (сильнее у мягкой ткани) и ободок цвета ткани
	BACKLIGHT = col * (0.3 + 0.35 * soft);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION += col * rim * (0.08 + 0.1 * soft) * (1.0 - clamp(depth / 14.0, 0.0, 1.0) * under);
}
