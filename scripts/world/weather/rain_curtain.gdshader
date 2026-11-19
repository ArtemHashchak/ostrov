shader_type spatial;
// Дальние «завесы» ливня в шторм: цилиндр ~110 м вокруг камеры (изнутри). Широкие
// размытые полосы дождя, плывущие по ветру, с разной плотностью — дальние острова и
// горизонт тонут в серой пелене. Ближе — штрихи RainFx, здесь только пелена.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(0.62, 0.66, 0.72, 0.5);
uniform float amount = 0.0;      // 0..1 (шторм/ливень)
uniform float light = 1.0;
uniform float drift = 0.0;       // смещение по окружности (ветер), накапливается в скрипте


// Мягкое пересечение с геометрией (рельеф/вода/скалы): без резкой линии там, где
// цилиндр слоя входит в землю — иначе вокруг игрока читается «круг».
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float soft_dist = 4.0;
float soft_fade(vec2 suv, float frag_z, mat4 inv_proj) {
	float raw = texture(depth_tex, suv).r;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	raw = raw * 2.0 - 1.0;
	#endif
	vec4 v = inv_proj * vec4(suv * 2.0 - 1.0, raw, 1.0);
	float scene_d = -v.z / v.w;
	return clamp((scene_d - frag_z) / soft_dist, 0.0, 1.0);
}

float hash(float n) { return fract(sin(n * 12.9898) * 43758.5453); }
float vn(float x) {
	float i = floor(x), f = fract(x);
	float u = f * f * (3.0 - 2.0 * f);
	return mix(hash(i), hash(i + 1.0), u);
}

void fragment() {
	float x = UV.x * 26.0 + drift;
	// крупные «рукава» ливня + мелкая полосатость падающей воды
	float big = vn(x) * 0.65 + vn(x * 2.7 + 13.0) * 0.35;
	float sheet = smoothstep(0.35, 0.8, big);
	float streak = 0.75 + 0.25 * vn(UV.x * 420.0 + UV.y * 3.0 + TIME * 0.0) * vn(UV.y * 9.0 - TIME * 3.0 + UV.x * 60.0);
	// снизу плотнее (вода у поверхности), к верху растворяется в облаках
	float vfade = smoothstep(0.0, 0.08, UV.y) * (1.0 - smoothstep(0.55, 1.0, UV.y));
	vfade = mix(vfade, 1.0 - UV.y, 0.3);
	ALBEDO = color.rgb * clamp(light, 0.25, 1.3);
	ALPHA = color.a * amount * (0.35 + 0.65 * sheet) * streak * clamp(vfade, 0.0, 1.0) * soft_fade(SCREEN_UV, -VERTEX.z, INV_PROJECTION_MATRIX);
}
