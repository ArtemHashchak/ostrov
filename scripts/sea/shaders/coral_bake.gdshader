shader_type spatial;
render_mode unshaded, cull_disabled;
// Запекание импосторов кораллов (tools/model_gen/corals/bake_impostors.gd): тот же меш, что в игре
// (нити разворачиваются к камере запекания), вывод без освещения:
//   mode 0 — альбедо (цвет вершин × узор кораллитов), mode 1 — нормаль в координатах модели (×0.5+0.5).

#include "res://scripts/sea/shaders/coral_common.gdshaderinc"

uniform int mode = 0;
uniform int pattern = 0;
uniform float pattern_scale = 90.0;

varying vec3 lpos;
varying vec3 mnrm;
varying float strand;
varying float s_x;
varying vec3 m_side;
varying vec3 m_face;
varying vec3 v_l;

void vertex() {
	strand = UV.x > 5.5 ? 1.0 : 0.0;
	s_x = UV2.x;
	mnrm = NORMAL;
	vec3 cam_l = coral_cam_local(MODEL_MATRIX, CAMERA_POSITION_WORLD);
	v_l = normalize(cam_l - VERTEX);
	if (strand > 0.5) {
		vec3 sd;
		vec3 fd;
		VERTEX = coral_strand_expand(VERTEX, normalize(NORMAL), UV2.x, UV2.y, cam_l, sd, fd);
		m_side = sd;
		m_face = fd;
		NORMAL = fd;
	} else {
		m_side = vec3(1.0, 0.0, 0.0);
		m_face = vec3(0.0, 1.0, 0.0);
	}
	lpos = VERTEX;
}

// Вывод проходит линейный → sRGB при показе вьюпорта: нормаль заранее переводим «обратно»,
// чтобы в PNG легло ровно n*0.5+0.5.
vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	// карточки и слои ворса старых версий в запекании не участвуют
	if (UV.x > 1.5 && UV.x < 5.5) {
		discard;
	}
	vec3 n;
	if (strand > 0.5) {
		n = coral_strand_normal(m_side, m_face, s_x);
	} else {
		n = normalize(mnrm);
		// обращённая от камеры сторона — переворачиваем (камера смотрит вдоль −VIEW)
		if (dot(n, normalize(v_l)) < 0.0) {
			n = -n;
		}
	}
	if (mode == 1) {
		ALBEDO = to_linear(clamp(n * 0.5 + 0.5, 0.0, 1.0));
	} else {
		vec3 col = COLOR.rgb;
		vec3 q = lpos * pattern_scale;
		if (pattern == 0) {
			float c = coral_cells(q);
			float cav = 1.0 - smoothstep(0.12, 0.32, c);
			col *= 1.0 - cav * 0.22;
		} else if (pattern == 1) {
			float r = sin(q.x * 0.7 + sin(q.z * 0.6) * 2.0) * sin(q.y * 0.65 + sin(q.x * 0.5) * 2.0) * sin(q.z * 0.7 + q.y * 0.3);
			col *= 1.0 - smoothstep(0.0, 0.6, -r) * 0.18;
		}
		ALBEDO = col;
	}
}
