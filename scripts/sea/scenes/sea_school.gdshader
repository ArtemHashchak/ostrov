shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
// Стая сцены моря (SeaSchool): особи — экземпляры MultiMesh, их положение и курс считает
// процессор (стайное поведение), здесь — только волна по телу и цвет.
// INSTANCE_CUSTOM = (фаза хвоста 0..1·2π, размах, изгиб в поворот −1..1, C-старт −1..1).
// Модель пака с разметкой CUSTOM0.x (0 голова … 1 хвост); без разметки — по оси Z.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform bool use_tex = true;
uniform vec3 tint : source_color = vec3(1.0);
uniform vec3 base_color : source_color = vec3(0.75, 0.8, 0.85);
uniform float body_len = 0.3;
uniform float alpha_cut = 0.4;
uniform bool has_rig = true;
uniform float flash = 0.0;        // серебристый блеск боков при развороте стаи

varying float v_turn;

void vertex() {
	vec4 cu = INSTANCE_CUSTOM;
	float t = has_rig ? CUSTOM0.x : clamp(VERTEX.z / max(body_len, 0.01) + 0.5, 0.0, 1.0);
	float ph = cu.x * 6.2831;
	float amp = cu.y;
	float L = body_len;
	float w = sin(t * 3.6 - ph) * amp * L * (0.08 + t * t * 1.6);
	float arc = t - 0.42;
	w += cu.z * 0.9 * arc * arc * L;
	w += cu.w * arc * arc * L * 2.4;
	VERTEX.x += w;
	v_turn = abs(cu.z);
}

void fragment() {
	vec3 c = base_color;
	if (use_tex) {
		vec4 tx = texture(albedo_tex, UV);
		if (tx.a < alpha_cut) discard;
		c = tx.rgb;
	}
	c *= tint;
	ALBEDO = c;
	ROUGHNESS = 0.3;
	SPECULAR = 0.6 + v_turn * flash;
	METALLIC = 0.15 + v_turn * flash * 0.4;
}
