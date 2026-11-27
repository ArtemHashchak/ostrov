// Растение, которого касается персонаж, отгибается целиком от основания (шарнир у корня),
// а после того как персонаж прошёл — коротко покачивается (затухающая пружина) и выпрямляется.
// Соседние растения, которых не касаются, не деформируются. Никаких радиальных «линз» вокруг игрока.
//
// Глобальные uniform (SkyWeather._update_plant_push), до трёх ближайших персонажей/зверей:
//   plant_push_a/b/c   — xyz: позиция ног (слегка запаздывает — стебли «догоняют»), w: радиус тела (0 — нет)
//   plant_trail_a/b/c  — xyz: позиция ног ~0,4 с назад (сильнее запаздывает), w: сила покачивания 0..1
// Основание растения — начало координат его инстанса (MODEL_MATRIX[3]); высота вершины над ним даёт
// величину сдвига (чем выше — тем больше), угол ограничен.
global uniform vec4 plant_push_a;
global uniform vec4 plant_push_b;
global uniform vec4 plant_push_c;
global uniform vec4 plant_trail_a;
global uniform vec4 plant_trail_b;
global uniform vec4 plant_trail_c;

const float PLANT_PUSH_MAX_ANGLE = 0.55;   // ~31°

float _pp_hash(vec3 b) {
	return fract(sin(dot(b.xz, vec2(12.9898, 78.233))) * 43758.5453);
}

// Угол наклона (рад) и направление (xz) от одного персонажа.
vec3 _pp_one(vec3 base, vec4 pp, vec4 tr, float reach, float t) {
	if (pp.w <= 0.0) return vec3(0.0);
	vec2 d = base.xz - pp.xz;
	float hd = length(d);
	float lim = reach + pp.w;
	// касание: ноги внутри куста по горизонтали и по высоте у его основания
	float vy = pp.y - base.y;
	float touch = (1.0 - smoothstep(lim * 0.55, lim, hd)) * step(-0.6, vy) * (1.0 - smoothstep(1.2, 1.8, vy));
	vec2 away = hd > 0.02 ? d / hd : vec2(0.0, 1.0);
	float ang = touch * PLANT_PUSH_MAX_ANGLE;
	// покачивание после прохода: растение было рядом с позицией ~0,4 с назад, а сейчас его не касаются
	if (tr.w > 0.0) {
		vec2 dt2 = base.xz - tr.xz;
		float th = length(dt2);
		float was = (1.0 - smoothstep(lim * 0.55, lim, th)) * (1.0 - touch);
		float ph = _pp_hash(base) * 6.2832;
		float sh = sin(t * 11.0 + ph) * 0.5 + sin(t * 17.0 + ph * 1.7) * 0.2;
		ang += was * tr.w * sh * PLANT_PUSH_MAX_ANGLE * 0.45;
		vec2 tdir = th > 0.02 ? dt2 / th : away;
		away = normalize(mix(tdir, away, touch) + vec2(1e-4));
	}
	return vec3(away.x * ang, ang, away.y * ang);
}

// wp — мировая позиция вершины, base — основание растения (мир), flex 0..1 — гибкость вершины
// (0 у корня/ствола), reach — полуширина куста (м). Возвращает мировой сдвиг вершины.
vec3 plant_push_hinge(vec3 wp, vec3 base, float flex, float reach, float t) {
	if (flex <= 0.0) return vec3(0.0);
	vec3 a = _pp_one(base, plant_push_a, plant_trail_a, reach, t)
		+ _pp_one(base, plant_push_b, plant_trail_b, reach, t)
		+ _pp_one(base, plant_push_c, plant_trail_c, reach, t);
	float ang = clamp(a.y, -PLANT_PUSH_MAX_ANGLE, PLANT_PUSH_MAX_ANGLE);
	if (abs(ang) < 1e-4) return vec3(0.0);
	vec2 dir = length(a.xz) > 1e-5 ? normalize(a.xz) : vec2(0.0, 1.0);
	if (a.y < 0.0) dir = -dir;
	ang = abs(ang);
	float h = max(wp.y - base.y, 0.0);
	// поворот вокруг основания: вершина на высоте h уходит вбок на sin(a)*h и опускается на (1-cos)*h
	float s = sin(ang) * h * flex;
	float c = (1.0 - cos(ang)) * h * flex;
	return vec3(dir.x * s, -c, dir.y * s);
}

// Совместимость: старое имя для шейдеров, где основание = начало координат инстанса.
// Трава: маленький радиус — мягкий изгиб только под ногами.
vec3 plant_push(vec3 wp, float w) {
	return vec3(0.0);
}
