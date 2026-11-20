shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
// Дублёры видов океанского состава (SeaProxyMeshes) и растения сцен моря.
// Цвет — в вершинах; COLOR.a — вес изгиба (0 у головы/основания … 1 на конце).
// Состояние особи — instance uniform anim = (фаза, размах, изгиб в поворот −1..1, доп.):
//   mode 0 рыба, 1 угорь (бегущая волна), 2 скат/манта (взмахи крыльев), 3 медуза (пульс купола),
//        4 черепаха (гребки ластами), 5 неподвижный, 6 растение (качание течением/прибоем и ветром),
//        7 ползущий (звезда/ёж: едва заметное шевеление), 8 креветка (подёргивание усиков).
// MultiMesh: фаза берётся из INSTANCE_CUSTOM.a (растения/стаи).
#include "res://shaders/sea_push.gdshaderinc"

uniform int mode = 0;
uniform float body_len = 1.0;     // размер узла (м) — для амплитуд
uniform vec3 tint : source_color = vec3(1.0);
uniform float sway = 0.4;         // растения: сила качания
uniform float surge = 1.0;        // растения: прибой (берег — сильнее)
uniform float rough = 0.6;
uniform float transl = 0.0;       // растения: просвет листьев (келп, саргассум) 0..1
global uniform vec2 wind_dir;
global uniform float weather_storm;

instance uniform vec4 anim = vec4(0.0, 0.06, 0.0, 0.0);

varying float v_w;

void vertex() {
	vec4 cu = INSTANCE_CUSTOM;
	float ph = anim.x + cu.a * 6.2831;
	float amp = anim.y;
	float turn = anim.z;
	float w = COLOR.a;
	v_w = w;
	vec3 v = VERTEX;
	if (mode == 0) {
		float t = clamp(v.z + 0.5, 0.0, 1.0);
		v.x += sin(t * 3.6 - ph) * amp * (0.08 + t * t * 1.6);
		float arc = t - 0.42;
		v.x += turn * 0.9 * arc * arc;
	} else if (mode == 1) {
		float t = clamp(v.z + 0.5, 0.0, 1.0);
		v.x += sin(t * 9.0 - ph) * amp * (0.25 + t);
		v.x += turn * (t - 0.4) * (t - 0.4) * 0.8;
	} else if (mode == 2) {
		float span = 0.95;
		float k = clamp(abs(v.x) / span, 0.0, 1.0);
		v.y += sin(ph - k * 1.4) * k * k * amp * 3.0;
		v.y += sin(ph * 0.5 + v.z * 3.0) * 0.02 * (1.0 - k);
	} else if (mode == 3) {
		float p = sin(ph);
		float top = smoothstep(-0.2, 0.3, v.y);
		v.xz *= 1.0 + p * 0.14 * top;
		v.y *= 1.0 - p * 0.1;
		// щупальца тянутся вслед
		float tail = smoothstep(0.0, -0.6, v.y);
		v.x += sin(ph - v.y * 6.0) * 0.04 * tail;
	} else if (mode == 4) {
		float side = sign(v.x);
		float k = smoothstep(0.25, 0.6, abs(v.x));
		float front = smoothstep(0.1, -0.3, v.z);
		v.y += sin(ph) * k * (0.2 + 0.5 * front) * amp * 4.0;
		v.z += cos(ph) * k * front * amp * 2.0;
	} else if (mode == 6) {
		vec3 wp = (MODEL_MATRIX * vec4(v, 1.0)).xyz;
		float t = TIME * (0.6 + weather_storm * 0.8);
		vec2 wd = normalize(wind_dir + vec2(0.0001));
		float s = sin(t + wp.x * 0.35 + wp.z * 0.27 + cu.a * 6.28) * 0.6 + sin(t * 1.9 + wp.z * 0.5) * 0.4;
		float k = sway * (1.0 + weather_storm * 1.6) * surge;
		vec2 off = (wd * (0.35 + 0.65 * s) + vec2(-wd.y, wd.x) * s * 0.3) * k * w * w;
		float sc = max(length(MODEL_MATRIX[0].xyz), 0.001);
		vec3 ow = vec3(off.x, -abs(s) * k * 0.15 * w * w, off.y);
		v += transpose(mat3(MODEL_MATRIX)) * ow / (sc * sc);
		v += sea_push_local(MODEL_MATRIX, wp, w);
	} else if (mode == 7) {
		v.y += sin(TIME * 0.7 + cu.a * 6.28 + atan(v.z, v.x) * 2.0) * 0.012 * w;
	} else if (mode == 8) {
		v.x += sin(TIME * 9.0 + ph) * 0.03 * w * step(v.y, 0.5);
		v.y += sin(TIME * 3.0 + ph) * 0.01;
	}
	VERTEX = v;
}

void fragment() {
	vec3 c = COLOR.rgb * tint;
	// двусторонние ленты (келп, листья, плавники): у обратной стороны нормаль должна смотреть
	// на камеру, иначе изнанка неосвещённая и почти чёрная
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = 0.45;
	if (mode == 3) {
		EMISSION = c * (0.18 + 0.12 * (1.0 - v_w));
		BACKLIGHT = c * 0.6;
	}
	if (mode == 6) {
		// просвет на тонких листьях: снизу против света келп и саргассум светятся золотисто-оливковым,
		// а не становятся чёрными силуэтами; немного собственного «пропущенного» света
		BACKLIGHT = c * (0.35 + transl * 0.55);
		EMISSION = c * transl * 0.07;
	}
}
