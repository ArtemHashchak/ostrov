shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
// Стая из модели автора с клипами, запечёнными в текстуру (VAT): сардина.
// Текстура смещений: x — вершина (UV2.x, центр текселя), y — кадр (строка), RGB — смещение в метрах
// в пространстве модели. Клипы — диапазоны строк (row_start, frames). Кадры между строками —
// линейно. INSTANCE_CUSTOM = (фаза 0..1, размах, поворот, испуг): фаза листает клип плавания,
// большой размах (быстро/рассыпались) — клип swim_fast. Положение и курс считает SeaSchool.

uniform sampler2D vat_tex : filter_nearest, repeat_disable;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(1.0);
uniform float vat_h = 83.0;                 // строк в текстуре
uniform vec2 clip_slow = vec2(0.0, 21.0);   // swim: первая строка, кадров
uniform vec2 clip_fast = vec2(21.0, 11.0);  // swim_fast
uniform float fast_amp = 0.085;             // размах, с которого — быстрый клип
uniform float alpha_cut = 0.35;
uniform float flash = 0.6;
uniform float rough = 0.32;

varying float v_turn;

vec3 vat_at(float u, float row) {
	return texture(vat_tex, vec2(u, (row + 0.5) / vat_h)).rgb;
}

void vertex() {
	vec4 cu = INSTANCE_CUSTOM;
	vec2 clip = cu.y > fast_amp ? clip_fast : clip_slow;
	float f = fract(cu.x) * clip.y;
	float f0 = floor(f);
	float f1 = mod(f0 + 1.0, clip.y);
	float t = f - f0;
	vec3 o0 = vat_at(UV2.x, clip.x + f0);
	vec3 o1 = vat_at(UV2.x, clip.x + f1);
	VERTEX += mix(o0, o1, t);
	v_turn = abs(cu.z);
}

void fragment() {
	vec4 tx = texture(albedo_tex, UV);
	if (tx.a < alpha_cut) discard;
	ALBEDO = tx.rgb * tint;
	ROUGHNESS = rough;
	SPECULAR = 0.6 + v_turn * flash;
	METALLIC = 0.2 + v_turn * flash * 0.4;
}
