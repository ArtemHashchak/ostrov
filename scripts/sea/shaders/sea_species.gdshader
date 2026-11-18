shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
// Группа живности одного вида целиком на видеокарте (MultiMesh, 1 вызов отрисовки):
//  * маршрут группы — замкнутая петля вокруг центра узла (NODE_POSITION_WORLD), каждый
//    кадр считается в шейдере, процессор не трогает экземпляры;
//  * экземпляр = особь: его смещение от центра — место в группе, INSTANCE_CUSTOM:
//    r — запаздывание по маршруту, g — вариант цвета (0..1), b — разброс скорости, a — фаза анимации;
//  * анимация тела: рыба (хвост), угорь (бегущая волна), скат (крылья), медуза (пульс), VAT;
//  * пловцы рядом (push_pos из sea_push) — группа расступается.
#include "res://shaders/sea_push.gdshaderinc"
#include "res://shaders/vat.gdshaderinc"

uniform int anim_mode = 0;          // 0 рыба, 1 угорь, 2 скат, 3 медуза, 4 статичная, 5 VAT
uniform float body_len = 0.3;
uniform float wiggle = 0.07;
uniform float tail_speed = 10.0;
uniform vec2 roam = vec2(8.0, 6.0); // полуоси петли, м
uniform float ang_speed = 0.2;      // рад/с по петле (знак — направление)
uniform float bob = 0.5;            // вертикальное покачивание маршрута, м
uniform float flee = 2.2;           // как далеко отплывают от пловца, м
uniform int fwd_axis = 0;           // 0: -Z, 1: +Z, 2: +X, 3: -X
uniform vec3 color_a : source_color = vec3(0.7);
uniform vec3 color_b : source_color = vec3(0.5);
uniform bool use_vertex_color = true;
uniform bool use_tex = false;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform float model_scale = 1.0;    // приведение модели к длине вида (VAT)
uniform float vat_speed = 1.0;      // скорость проигрывания VAT

varying vec3 v_col;

mat3 fwd_basis(vec3 f) {
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 r = normalize(cross(up, f) + vec3(0.0001, 0.0, 0.0));
	vec3 u = cross(f, r);
	// столбцы: X = вправо, Y = вверх, Z = назад (модель смотрит в -Z)
	return mat3(r, u, -f);
}

vec3 axis_fix(vec3 v) {
	if (fwd_axis == 1) return vec3(-v.x, v.y, -v.z);
	if (fwd_axis == 2) return vec3(v.z, v.y, -v.x);
	if (fwd_axis == 3) return vec3(-v.z, v.y, v.x);
	return v;
}

void vertex() {
	vec4 cu = INSTANCE_CUSTOM;
	float ph = cu.a * 6.2831;
	vec3 lv = VERTEX;
	vec3 ln = NORMAL;
	if (anim_mode == 5) {
		lv = (VERTEX + vat_offset(float(VERTEX_ID), TIME * vat_speed + cu.a * vat_length)) * model_scale;
		ln = NORMAL;
	}
	lv = axis_fix(lv);
	ln = axis_fix(ln);
	// масштаб особи — из преобразования экземпляра
	float s = length(MODEL_MATRIX[0].xyz);
	float t = clamp(lv.z / max(body_len, 0.01) + 0.5, 0.0, 1.0);   // 0 голова … 1 хвост
	if (anim_mode == 0) {
		lv.x += sin(t * 4.0 - TIME * tail_speed * (0.85 + cu.b * 0.3) - ph) * wiggle * body_len * t * t * 2.0;
	} else if (anim_mode == 1) {
		lv.x += sin(t * 9.0 - TIME * tail_speed * 0.5 - ph) * wiggle * body_len * (0.3 + t);
	} else if (anim_mode == 2) {
		float span = max(body_len * 0.6, 0.01);
		lv.y += sin(TIME * tail_speed * 0.25 + ph - abs(lv.x) / span * 1.2) * abs(lv.x) / span * wiggle * body_len * 3.0;
	} else if (anim_mode == 3) {
		float p = sin(TIME * 2.2 + ph);
		lv.xz *= 1.0 + p * 0.12 * smoothstep(-0.1, 0.4, lv.y / max(body_len, 0.01));
		lv.y *= 1.0 - p * 0.08;
	}
	// маршрут группы
	vec3 center = NODE_POSITION_WORLD;
	vec3 inst = MODEL_MATRIX[3].xyz;
	vec3 member = inst - center;
	float gph = fract(sin(dot(center.xz, vec2(12.9898, 78.233))) * 43758.5453) * 6.2831;
	float th = TIME * ang_speed + cu.r * 0.15 + gph;
	vec3 path = vec3(cos(th) * roam.x, sin(th * 1.7 + cu.r) * bob, sin(th) * roam.y);
	vec3 dir = normalize(vec3(-sin(th) * roam.x, cos(th * 1.7 + cu.r) * 1.7 * bob * 0.3, cos(th) * roam.y) * sign(ang_speed + 0.0001));
	if (anim_mode == 3 || anim_mode == 4) {
		// медузы и неподвижные — только дрейф/покачивание на месте
		path = vec3(sin(TIME * 0.11 + ph) * 0.6, sin(TIME * 0.27 + ph) * bob, cos(TIME * 0.13 + ph) * 0.6);
		dir = normalize(vec3(sin(ph), 0.0, cos(ph)));
	}
	mat3 B = fwd_basis(dir);
	vec3 body_c = center + path + B * member;
	// расступиться перед пловцом (центр особи уходит, тело не гнётся)
	body_c += sea_push_world(body_c, 1.0) * flee;
	vec3 wv = body_c + B * (lv * s);
	vec3 wn = normalize(B * ln);
	mat4 inv = inverse(MODEL_MATRIX);
	VERTEX = (inv * vec4(wv, 1.0)).xyz;
	NORMAL = normalize((inv * vec4(wn, 0.0)).xyz);
	v_col = mix(color_a, color_b, cu.g);
}

void fragment() {
	vec3 col = v_col;
	if (use_tex) {
		col = texture(albedo_tex, UV).rgb * mix(vec3(1.0), v_col, 0.15);
	} else if (use_vertex_color) {
		// процедурная рыбка: COLOR.r — «спинность», COLOR.g — полосы
		vec3 back = col * 0.55;
		vec3 belly = mix(col, vec3(0.92, 0.93, 0.9), 0.55);
		col = mix(belly, back, smoothstep(0.35, 0.75, COLOR.r)) * max(COLOR.g, 0.4);
	}
	ALBEDO = col;
	ROUGHNESS = 0.3;
	SPECULAR = 0.6;
	METALLIC = 0.1;
}
