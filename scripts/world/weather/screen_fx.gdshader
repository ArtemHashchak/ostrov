shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, blend_add, fog_disabled;
// Экранные эффекты v5 (агент D), один полноэкранный квад перед камерой:
//  • лучи солнца — радиальное размытие ярких пикселей (небо в просветах крон, солнце под водой)
//    к экранной точке солнца (Высокое+: 16–24 выборки);
//  • ослепление солнцем — вуаль и блик, когда взгляд у солнца (стрелок, целящийся в солнце, хуже видит);
// Квад рисуется ДОБАВЛЕНИЕМ поверх кадра (blend_add): копия экрана снимается до прозрачных
// объектов (вода), поэтому сам кадр не перезаписываем — только прибавляем свет. Вуаль ослепления —
// тоже добавлением (свет рассеивается в глазу и прицеле).
//  • радуга — дуга 40–42° вокруг антисолнечной точки после дождя (солнце за спиной, невысоко).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec2 sun_uv = vec2(0.5);           // экранная позиция солнца (может быть за краем)
uniform float sun_vis = 0.0;               // солнце перед камерой и над горизонтом 0..1
uniform float shafts = 0.0;                // сила лучей 0..1
uniform int shaft_samples = 16;
uniform float glare = 0.0;                 // ослепление 0..1
uniform float rainbow = 0.0;               // радуга 0..1
uniform vec3 anti_sun = vec3(0.0, -1.0, 0.0); // мировое направление на антисолнечную точку
uniform vec3 sun_tint : source_color = vec3(1.0, 0.92, 0.78);
uniform float underwater = 0.0;
uniform vec4 meteor = vec4(0.0);           // падающая звезда: начало (uv) и направление (uv/с)
uniform float meteor_t = -1.0;             // 0..1 — ход вспышки, < 0 — нет

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 0.0, 1.0);
}

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 base = textureLod(screen_tex, uv, 0.0).rgb;
	vec3 col = vec3(0.0);
	// --- лучи
	if (shafts > 0.001 && sun_vis > 0.001) {
		vec2 dir = (sun_uv - uv);
		float n = float(shaft_samples);
		vec2 stp = dir / n * 0.9;
		vec2 p = uv;
		float acc = 0.0;
		float decay = 1.0;
		for (int i = 0; i < 24; i++) {
			if (i >= shaft_samples) break;
			p += stp;
			vec3 s = textureLod(screen_tex, clamp(p, vec2(0.001), vec2(0.999)), 1.5).rgb;
			float b = max(luma(s) - mix(0.78, 0.45, underwater), 0.0);
			acc += b * decay;
			decay *= 0.94;
		}
		acc /= n;
		float fall = 1.0 - smoothstep(0.0, 0.9, length(dir * vec2(1.6, 1.0)));
		col += sun_tint * acc * shafts * sun_vis * fall * mix(3.2, 4.5, underwater);
	}
	// --- ослепление: вуаль по всему кадру + мягкое пятно вокруг солнца
	if (glare > 0.001) {
		float dd = length((uv - sun_uv) * vec2(1.7, 1.0));
		float spot = exp(-dd * dd * 30.0);
		col += sun_tint * glare * (0.08 + 0.45 * spot);
	}
	// --- радуга: угол между лучом взгляда и антисолнечной точкой 40–42°
	if (rainbow > 0.001) {
		vec4 ndc = vec4(uv * 2.0 - 1.0, 1.0, 1.0);
		vec4 vv = INV_PROJECTION_MATRIX * ndc;
		vec3 vdir = normalize((INV_VIEW_MATRIX * vec4(normalize(vv.xyz / vv.w), 0.0)).xyz);
		float ang = degrees(acos(clamp(dot(vdir, anti_sun), -1.0, 1.0)));
		float t = (ang - 40.0) / 2.2;               // 0 — фиолетовый (внутри), 1 — красный (снаружи)
		float band = smoothstep(-0.15, 0.1, t) * (1.0 - smoothstep(0.9, 1.15, t));
		vec3 rb = clamp(abs(fract(vec3(0.0, 0.33, 0.67) + (1.0 - t) * 0.8) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
		float above = smoothstep(-0.02, 0.06, vdir.y);  // дуга не уходит под горизонт моря
		col += rb * band * above * rainbow * 0.11 * (0.45 + 0.55 * luma(base));
	}
	// --- падающая звезда: тонкий штрих с ярким концом, гаснет за ~0.8 с
	if (meteor_t >= 0.0 && meteor_t <= 1.0) {
		vec2 head = meteor.xy + meteor.zw * meteor_t;
		vec2 tail = head - meteor.zw * 0.35;
		vec2 pa = (uv - tail) * vec2(1.7, 1.0);
		vec2 ba = (head - tail) * vec2(1.7, 1.0);
		float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
		float dist = length(pa - ba * h);
		float line = (1.0 - smoothstep(0.0, 0.0022, dist)) * h * h;
		float fade = sin(meteor_t * 3.14159);
		col += vec3(0.85, 0.9, 1.0) * line * fade * 1.6;
	}
	ALBEDO = col;
}
