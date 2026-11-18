// Общее «расталкивание» мягкой подводной растительности пловцами.
// Подключение:   #include "res://shaders/sea_push.gdshaderinc"
// В vertex():    VERTEX += sea_push_local(MODEL_MATRIX, (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, h);
//   где h — 0 у основания .. 1 у верхушки (насколько гнётся точка).
// Позиции пловцов (до 4: xyz — центр тела, w — радиус, 0 — нет) ставит SeaPush
// каждый кадр всем зарегистрированным материалам (SeaPush.register(mat)).
// Цена: 4 расстояния на вершину, только у ближних экземпляров; процессор не участвует.

uniform vec4 push_pos[4];
uniform float push_strength = 0.55;

vec3 sea_push_world(vec3 wp, float h) {
	vec3 off = vec3(0.0);
	for (int i = 0; i < 4; i++) {
		vec4 s = push_pos[i];
		if (s.w <= 0.0) continue;
		vec3 d = wp - s.xyz;
		d.y *= 0.6;                            // по высоте толща чуть «длиннее»
		float r = length(d);
		float k = 1.0 - smoothstep(s.w * 0.25, s.w, r);
		if (k <= 0.0) continue;
		vec2 dir = normalize(d.xz + vec2(0.0001, 0.0));
		off.xz += dir * k * push_strength * s.w;
		off.y -= k * 0.25 * push_strength * s.w;   // отогнутая — ниже
	}
	return off * h * h;
}

// То же в локальных координатах экземпляра (для VERTEX в MultiMesh/MeshInstance).
vec3 sea_push_local(mat4 model, vec3 wp, float h) {
	vec3 off = sea_push_world(wp, h);
	float s = max(length(model[0].xyz), 0.001);
	return transpose(mat3(model)) * off / (s * s);
}
