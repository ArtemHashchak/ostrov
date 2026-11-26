// Растения раздвигаются, когда сквозь них идёт персонаж (v5, агент D), и выпрямляются обратно.
// До трёх ближайших к камере персонажей: global vec4 plant_push_a/b/c — xyz позиция ног, w — радиус
// (0 — нет). Смещение — от персонажа в стороны и чуть вниз, растёт к верхушке (вес w ветра).
// Пружинистость: позиции в SkyWeather сглажены с запаздыванием, поэтому стебли «догоняют» и качаются.
global uniform vec4 plant_push_a;
global uniform vec4 plant_push_b;
global uniform vec4 plant_push_c;

vec3 push_one(vec3 wp, vec4 pp, float w) {
	if (pp.w <= 0.0) return vec3(0.0);
	vec3 d = wp - pp.xyz;
	float hd = length(d.xz);
	float k = 1.0 - smoothstep(pp.w * 0.35, pp.w, hd);
	k *= step(-0.5, d.y) * (1.0 - smoothstep(1.4, 2.2, d.y));   // только ниже ~2 м над ногами
	vec2 away = hd > 0.001 ? d.xz / hd : vec2(1.0, 0.0);
	float amt = k * w * min(pp.w * 0.55, 0.6);
	return vec3(away.x * amt, -amt * 0.45, away.y * amt);
}

vec3 plant_push(vec3 wp, float w) {
	return push_one(wp, plant_push_a, w) + push_one(wp, plant_push_b, w) + push_one(wp, plant_push_c, w);
}
