shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
// Особь из морского пака пользователя ВБЛИЗИ (одиночный MeshInstance3D, поведение — UserSeaActor).
// Вдали те же модели рисует групповой шейдер user_species (MultiMesh).
// Разметка вершин (tools/folder_anim/seg_rig.py) в CUSTOM0/CUSTOM1:
//   рыба:     CUSTOM0 = (t вдоль тела 0 голова..1 хвост, вес грудного плавника, сторона ±1, —)
//   осьминог/кальмар: CUSTOM0 = (номер щупальца 0..7, t вдоль щупальца, плавник мантии, тело 0/1),
//                     CUSTOM1 = (направление основания щупальца xyz, —).
// Состояние особи — instance uniform (один материал на вид, без копий).
// Модель смотрит носом/мантией в −Z.

uniform int mode = 0;                 // 0 рыба, 1 осьминог, 2 кальмар
uniform float body_len = 0.3;
uniform vec3 hub = vec3(0.0);         // центр, откуда растут щупальца (модель)
uniform float arm_len = 0.35;
uniform float arm_base = 0.16;       // от центра до основания щупалец
uniform bool use_tex = true;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec3 base_color : source_color = vec3(0.7, 0.4, 0.3);
// Подкраска вида-«дублёра» (океанский состав, scripts/sea/scenes): модель пака под другой вид.
uniform vec3 tint : source_color = vec3(1.0);
uniform float alpha_cut = 0.4;
uniform vec3 glow_color : source_color = vec3(0.2, 0.9, 1.0);
uniform float glow = 0.0;

// Состояние особи (instance uniform, упаковано — не больше 16 на шейдер):
// рыба:  fish_a = (фаза хвоста, размах хвоста, изгиб в поворот −1..1, C-старт −1..1),
//        fish_b = (фаза трепета грудных плавников, размах плавников, сид, —);
// осьминог/кальмар: octo_a = (фаза шагов, ползёт 0..1, рывок 0..1, сжатие мантии 0..1),
//        octo_b = (прижался, угроза, хват, маскировка), grab_dir — куда тянется (модель).
instance uniform vec4 fish_a = vec4(0.0, 0.06, 0.0, 0.0);
instance uniform vec4 fish_b = vec4(0.0, 0.3, 0.0, 0.0);
instance uniform vec4 octo_a = vec4(0.0);
instance uniform vec4 octo_b = vec4(0.0);
instance uniform vec3 grab_dir = vec3(0.0, 0.0, 1.0);
instance uniform vec3 camo_color : source_color = vec3(0.62, 0.58, 0.48);
const vec2 move_dir = vec2(0.0, 1.0);   // ползёт «глазами вперёд» (+Z модели)

varying float v_arm_t;
varying float v_body;
varying float v_threat;

vec3 rot(vec3 v, vec3 axis, float a) {
	// Родригес: поворот вектора v вокруг единичной оси
	float c = cos(a), s = sin(a);
	return v * c + cross(axis, v) * s + axis * dot(axis, v) * (1.0 - c);
}

// Изгиб щупальца вверх (+)/вниз (−) в его вертикальной полуплоскости, как «изгиб по дуге»:
// часть дальше x0 от центра наматывается на окружность радиуса R = длина/угол — толщина
// сохраняется (не «лопасть»). p — от центра щупалец, n — нормаль; L — длина щупальца.
void bend_arm(inout vec3 p, inout vec3 n, float angle, float x0, float L) {
	if (abs(angle) < 0.002) return;
	float x = length(p.xz);
	if (x <= x0) return;
	vec2 hd = p.xz / x;
	float k = angle / max(L - x0, 0.02);
	float R = 1.0 / k;
	float th = (x - x0) * k;
	float nx = x0 + (R - p.y) * sin(th);
	float ny = R - (R - p.y) * cos(th);
	p = vec3(hd.x * nx, ny, hd.y * nx);
	vec3 ax = normalize(cross(vec3(hd.x, 0.0, hd.y), vec3(0.0, 1.0, 0.0)));
	n = rot(n, ax, th);
}

void vertex() {
	float swim_phase = fish_a.x, swim_amp = fish_a.y, turn_bend = fish_a.z, startle = fish_a.w;
	float fin_phase = fish_b.x, fin_amp = fish_b.y, seed = fish_b.z;
	float gait = octo_a.x, crawl = octo_a.y, jet = octo_a.z, jet_pulse = octo_a.w;
	float flatten = octo_b.x, threat = octo_b.y, grab = octo_b.z;
	vec3 lv = VERTEX;
	vec3 ln = NORMAL;
	v_arm_t = 0.0;
	v_body = 1.0;
	v_threat = threat;
	if (mode == 0) {
		float t = CUSTOM0.x;                       // 0 голова … 1 хвост
		float L = body_len;
		// волна по телу: голова почти неподвижна, хвост бьёт
		float w = sin(t * 3.6 - swim_phase) * swim_amp * L * (0.08 + t * t * 1.6);
		// изгиб в поворот: дуга вдоль тела (нос и хвост в одну сторону)
		// (нос и хвост уходят внутрь поворота — тело дугой)
		float bend = turn_bend * 0.9;
		float arc = (t - 0.42);
		w += bend * arc * arc * L;
		// C-старт: тело сворачивается в крутую дугу в сторону рывка
		w += startle * arc * arc * L * 2.4;
		lv.x += w;
		// угол сечения вслед волне — нормали поворачиваем приближённо
		float dw = cos(t * 3.6 - swim_phase) * swim_amp * 3.6 * (0.08 + t * t * 1.6) + (bend + startle * 2.4) * 2.0 * arc;
		ln = normalize(ln + vec3(0.0, 0.0, -dw * ln.x));
		// грудные плавники: трепет вверх-вниз (стороны в противофазе)
		float fw = CUSTOM0.y;
		if (fw > 0.0) {
			float f = sin(fin_phase + CUSTOM0.z * 1.1) * fin_amp;
			float lat = abs(VERTEX.x);
			lv.y += f * fw * lat * 1.4;
			lv.z += -abs(f) * fw * lat * 0.4;
		}
	} else {
		bool is_arm = CUSTOM0.w < 0.5;
		float ai = CUSTOM0.x;
		float t = CUSTOM0.y;
		float ph = ai * 2.399 + seed * 6.2831;          // золотой угол — фазы не совпадают
		if (is_arm) {
			v_body = 0.0;
			v_arm_t = t;
			vec3 dirv = normalize(CUSTOM1.xyz + vec3(1e-4));
			vec3 up = vec3(0.0, 1.0, 0.0);
			if (mode == 2) up = vec3(0.0, 0.0, 1.0);
			vec3 side = normalize(cross(up, dirv) + vec3(0.0, 1e-4, 0.0));
			vec3 lift = normalize(cross(dirv, side));     // «вверх» для щупальца
			vec3 pivot = hub + dirv * 0.02;
			vec3 p = lv - pivot;
			float te = t * t * (3.0 - 2.0 * t);
			// у осьминога на дне щупальца лежат: поднятые в позе модели — прижать к грунту
			if (mode == 1) {
				float g = 0.75 * (1.0 - jet);
				p.y = mix(p.y, 0.012 * (1.0 - t), g * te);
			}
			// 1) медленная волна и завиток кончика (живое щупальце в покое)
			float wave = sin(TIME * 1.7 - t * 6.0 + ph);
			float curl_tip = 0.55 + 0.35 * sin(TIME * 0.6 + ph * 1.3) + wave * 0.25;   // кончик наматывается
			float lift_a = wave * 0.12;                                                 // всё щупальце
			float a_side = sin(TIME * 1.1 - t * 4.0 + ph * 0.7) * 0.25 * t;
			// 2) шаги: щупальца по очереди приподнимаются и переставляются по ходу
			if (mode == 1 && crawl > 0.0) {
				vec2 b2 = normalize(dirv.xz + vec2(1e-4));
				float front = dot(b2, normalize(move_dir + vec2(1e-4)));
				float gp = gait + ai * 3.14159 * 0.5 + (mod(ai, 2.0) * 3.14159);
				float lift_k = max(sin(gp), 0.0);
				float sweep = cos(gp);
				lift_a += crawl * (lift_k * 0.55 + max(front, 0.0) * 0.15);
				curl_tip += crawl * lift_k * 0.6;
				float cr = b2.x * move_dir.y - b2.y * move_dir.x;   // с какой стороны от курса
				a_side += crawl * sweep * 0.35 * te * sign(cr + 0.001);
				// ведущие щупальца ощупывают — тянутся вперёд
				p += dirv * crawl * max(front, 0.0) * 0.05 * te;
			}
			// 3) угроза: щупальца приподнимаются, кончики скручиваются в спираль
			lift_a += threat * 0.75;
			curl_tip += threat * 1.6;
			// 4) прижался: кончики вниз, щупальца распластаны
			lift_a -= flatten * 0.25;
			curl_tip -= flatten * 0.5;
			if (mode == 1) {
				// поворот вбок вокруг вертикали + изгиб по дуге (без «лопастей»)
				p = rot(p, vec3(0.0, 1.0, 0.0), a_side);
				ln = rot(ln, vec3(0.0, 1.0, 0.0), a_side);
				bend_arm(p, ln, curl_tip, arm_base + arm_len * 0.55, arm_base + arm_len);
				bend_arm(p, ln, lift_a, arm_base + arm_len * 0.08, arm_base + arm_len);
			} else {
				float a_up = lift_a * te + curl_tip * 0.5 * t * t;
				p = rot(p, side, -a_up);
				p = rot(p, lift, a_side);
				ln = rot(rot(ln, side, -a_up), lift, a_side);
			}
			// 5) хват: щупальца со стороны цели тянутся к ней и обвивают кончиком
			if (grab > 0.0) {
				vec3 gd = normalize(grab_dir);
				float al = pow(max(dot(dirv, gd), 0.0), 2.0);
				vec3 reach = (gd * arm_len * 1.15 * t) - p;
				p += reach * grab * al * te;
				vec3 ax = normalize(cross(gd, up) + vec3(1e-4));
				float ga = grab * al * t * t * 1.3 * sin(TIME * 3.0 + ph);
				p = rot(p, ax, ga);
				ln = rot(ln, ax, ga);
			}
			// 6) реактивный рывок: щупальца пучком назад (против мантии, +Z)
			if (jet > 0.0) {
				vec3 back = (mode == 2) ? vec3(1.0, 0.0, 0.0) : normalize(vec3(0.0, -0.15, 1.0));
				float ang = ai / 8.0 * 6.2831;
				vec3 spread = vec3(cos(ang), sin(ang) * 0.6, 0.0) * 0.05 * (1.0 - t);
				if (mode == 2) spread = vec3(0.0, cos(ang), sin(ang)) * 0.04 * (1.0 - t);
				vec3 trail = back * (0.03 + t * arm_len) + spread;
				trail += vec3(sin(TIME * 7.0 - t * 8.0 + ph), cos(TIME * 6.0 - t * 7.0 + ph), 0.0) * 0.02 * t;
				p = mix(p, trail, jet * (0.35 + 0.65 * t));
			}
			lv = pivot + p;
			// прижался — ещё и к дну
			lv.y = mix(lv.y, min(lv.y, hub.y + 0.01), flatten * 0.6 * te);
		} else {
			// мантия: дыхание, сжатие в рывке, раздувание в угрозе
			vec3 rel = lv - hub;
			float top = smoothstep(-0.05, 0.25, rel.y / max(body_len, 0.01));
			if (mode == 2) top = smoothstep(0.0, 0.25, -rel.x / max(body_len, 0.01));
			float breath = sin(TIME * 1.4 + seed * 9.0) * 0.035;
			float k = 1.0 + (breath + threat * 0.08 - jet_pulse * 0.16) * top;
			lv = hub + rel * vec3(k, mix(1.0, k, 0.6), k);
			lv.y = mix(lv.y, hub.y + (lv.y - hub.y) * 0.55, flatten);
			// плавники кальмара: волна по краю
			if (mode == 2 && CUSTOM0.z > 0.5) {
				lv.y += sin(TIME * 6.0 + lv.x * 30.0 + seed * 6.0) * 0.025 * (1.0 + jet);
			}
		}
	}
	VERTEX = lv;
	NORMAL = normalize(ln);
}

void fragment() {
	float seed = fish_b.z, camo = octo_b.w, jet = octo_a.z;
	vec3 col = base_color;
	if (use_tex) {
		vec4 tx = texture(albedo_tex, UV);
		if (tx.a < alpha_cut) discard;
		col = tx.rgb;
	}
	col *= tint;
	if (mode != 0) {
		// осьминог: маскировка под дно и вспышки угрозы (темнеет/бледнеет волнами)
		col = mix(col, camo_color * (0.85 + 0.3 * col), camo * 0.75);
		float flash = sin(TIME * 9.0 - v_arm_t * 6.0) * 0.5 + 0.5;
		col = mix(col, mix(col * 0.45, col * 0.6 + vec3(0.3, 0.27, 0.24), flash), v_threat * 0.55);
	}
	ALBEDO = col;
	ROUGHNESS = mode == 0 ? 0.32 : 0.45;
	SPECULAR = 0.55;
	if (glow > 0.0) {
		float pulse = 0.55 + 0.45 * sin(TIME * 2.4 + seed * 6.0);
		float run = 0.5 + 0.5 * sin(TIME * 5.0 - v_arm_t * 9.0 + seed * 3.0);
		EMISSION = glow_color * glow * (pulse * mix(0.3, 1.0, run * v_arm_t) + jet * 0.0) * (1.0 + v_threat * 2.0);
	}
}
