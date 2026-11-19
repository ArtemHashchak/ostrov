shader_type spatial;
// Дальние слои дождя: цилиндр вокруг камеры (изнутри), процедурные бегущие штрихи.
// Наклон по ветру — поворотом узла. Перекрывается стенами/крышами через тест глубины.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(0.75, 0.8, 0.88, 0.22);
uniform float columns = 900.0;      // штрихов по окружности
uniform float rows = 7.0;           // повторов по высоте
uniform float speed = 2.2;          // скорость бегущего узора (UV/с)
uniform float streak_len = 0.22;    // длина штриха (доля периода)
uniform float thickness = 0.16;     // толщина штриха (доля колонки)
uniform float light = 1.0;
uniform float amount = 1.0;         // 0..1 сила дождя
uniform float sheet_fade = 1.0;     // общая прозрачность слоя

float hash(float n) { return fract(sin(n * 12.9898) * 43758.5453); }

void fragment() {
	float cx = UV.x * columns;
	float col = floor(cx);
	float h1 = hash(col);
	float h2 = hash(col + 71.3);
	// не каждая колонка — капля: плотность от силы дождя
	float on = step(h2, 0.25 + 0.75 * amount);
	float fx = fract(cx) - 0.5;
	float line = 1.0 - smoothstep(thickness * 0.5, thickness, abs(fx));
	float y = UV.y * rows * (0.8 + 0.4 * h1) + TIME * speed * (0.85 + 0.3 * h2) + h1 * 10.0;
	float fy = fract(y);
	float drop = smoothstep(0.0, streak_len * 0.4, fy) * (1.0 - smoothstep(streak_len * 0.6, streak_len, fy));
	// края цилиндра по высоте растворяются
	float vfade = smoothstep(0.0, 0.25, UV.y) * smoothstep(1.0, 0.7, UV.y);
	ALBEDO = color.rgb * clamp(light, 0.35, 1.6);
	ALPHA = color.a * line * drop * on * vfade * sheet_fade * amount;
}
