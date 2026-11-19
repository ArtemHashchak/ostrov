// Изгиб дерева ветром (CONTRACT_WEATHER): общий для коры, кокосов и листвы, поэтому
// крона не «отрывается» от ствола. Смещение растёт как квадрат высоты над основанием
// (локальный y объекта); в шторм ~3 м на 12 м (пальмы заметно «ложатся» по ветру) + порывы.
// Лежащие/падающие объекты (ось Y не вверх) не гнутся.
vec3 tree_bend_local(vec3 v, mat4 model, float t, vec2 wdir, float storm, float gust) {
	float sc = length(model[1].xyz);
	float upness = model[1].y / max(sc, 1e-4);
	float gate = smoothstep(0.85, 0.97, upness);
	vec3 o = model[3].xyz;
	float ph = fract(sin(dot(o.xz, vec2(12.9898, 78.233))) * 43758.5453) * 6.2832;
	float y = max(v.y, 0.0) * sc;
	// постоянный наклон по ветру (шторм) + раскачка порывами + штилевое покачивание
	float lean = storm * (0.75 + 0.5 * gust);
	float sway = (0.12 + 0.25 * storm) * sin(t * (0.9 + 0.5 * storm) + ph)
			+ 0.06 * storm * sin(t * 3.7 + ph * 1.7);
	float k = 0.0065 + 0.028 * storm;
	float d = k * y * y * (lean + sway * (0.15 + storm)) * gate;
	d = min(d, y * 0.38);
	vec3 bw = vec3(wdir.x * d, -d * d / max(2.0 * y, 0.5), wdir.y * d);
	vec3 bl = transpose(mat3(model)) * bw;
	float sc2 = max(dot(model[0].xyz, model[0].xyz), 1e-4);
	return bl / sc2;
}
