// Общие функции кораллов пака: «нити» (strands), узоры, полоса LOD по расстоянию экземпляра.
// Подключают coral_pack.gdshader (игра) и coral_bake.gdshader (запекание импосторов).
//
// НИТЬ (strand, UV.x ≥ 5.5): тонкая трубка (щупальце, веточка, ворс) хранится как лента из двух
// вершин на точку осевой линии: VERTEX — точка на оси, NORMAL — направление оси (единичное),
// UV2.x — сторона −1/+1, UV2.y — радиус в метрах. В вершинном шейдере лента разворачивается
// к камере поперёк оси (цилиндрический билборд), во фрагментном нормаль восстанавливается как у
// цилиндра — со всех сторон выглядит круглой трубкой ценой 2 треугольников на отрезок.

float coral_hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// Ячеистый шум: расстояние до ближайшей «чашечки» кораллита.
float coral_cells(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float d = 1.0;
	for (int z = -1; z <= 1; z++)
	for (int y = -1; y <= 1; y++)
	for (int x = -1; x <= 1; x++) {
		vec3 g = vec3(float(x), float(y), float(z));
		vec3 o = vec3(coral_hash3(i + g), coral_hash3(i + g + 17.1), coral_hash3(i + g + 31.7));
		d = min(d, length(g + o - f));
	}
	return d;
}

// Положение камеры в координатах модели (поворот + равномерный масштаб, без перекоса).
vec3 coral_cam_local(mat4 model, vec3 cam_world) {
	float s = max(length(model[0].xyz), 0.0001);
	return transpose(mat3(model)) * (cam_world - model[3].xyz) / (s * s);
}

// Разворот нити: center — точка оси (локально), axis — ось, side −1/+1, rad — радиус.
// Возвращает позицию вершины; side_dir/face_dir — базис «поперёк оси» и «к камере» (локально).
vec3 coral_strand_expand(vec3 center, vec3 axis, float side, float rad, vec3 cam_l, out vec3 side_dir, out vec3 face_dir) {
	vec3 to_cam = cam_l - center;
	float l = length(to_cam);
	to_cam = l > 0.00001 ? to_cam / l : vec3(0.0, 1.0, 0.0);
	vec3 sd = cross(axis, to_cam);
	float sl = length(sd);
	if (sl < 0.0001) {
		// смотрим вдоль оси — любой перпендикуляр
		sd = abs(axis.y) < 0.9 ? cross(axis, vec3(0.0, 1.0, 0.0)) : cross(axis, vec3(1.0, 0.0, 0.0));
		sl = length(sd);
	}
	sd /= sl;
	side_dir = sd;
	face_dir = normalize(cross(sd, axis));
	if (dot(face_dir, to_cam) < 0.0) {
		face_dir = -face_dir;
	}
	return center + sd * side * rad;
}

// Нормаль цилиндра по поперечной координате x (−1..1).
vec3 coral_strand_normal(vec3 side_dir, vec3 face_dir, float x) {
	float xc = clamp(x, -1.0, 1.0);
	return normalize(side_dir * xc + face_dir * sqrt(max(0.0, 1.0 - xc * xc)));
}

// Порог «растворения» по расстоянию экземпляра: 1 — виден, 0 — нет (плавно в полосе fade).
float coral_lod_vis(float dist, float b, float e, float fade) {
	float a = b <= 0.0 ? 1.0 : smoothstep(b - fade, b + fade, dist);
	float z = e <= 0.0 ? 1.0 : 1.0 - smoothstep(e - fade, e + fade, dist);
	return a * z;
}

// Упорядоченный дизеринг 4×4 (0..1) по пикселю — для перехода между LOD без прозрачности.
float coral_dither(vec2 frag) {
	ivec2 p = ivec2(mod(frag, 4.0));
	int i = p.x + p.y * 4;
	float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[i] + 0.5) / 16.0;
}
