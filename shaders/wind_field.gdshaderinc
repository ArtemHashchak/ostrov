// Видимые порывы ветра (v5, агент D): поле порывов бежит по миру по направлению ветра со скоростью
// ветра. Один и тот же порыв проходит сначала по траве, потом по кустам и пальмам, по воде — тёмной
// рябью («кошачьи лапы»). Вход — мировая точка xz, время, направление ветра, шторм 0..1, порыв мира.
// Выход — множитель качания ~0.55 (затишье между порывами) .. ~1.9 (сердцевина порыва).
float wf_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float wf_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = wf_hash(i);
	float b = wf_hash(i + vec2(1.0, 0.0));
	float c = wf_hash(i + vec2(0.0, 1.0));
	float d = wf_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
// Скорость бега фронта порыва, м/с: штиль ~3, свежий ветер ~8, шторм ~20.
float wind_front_speed(float storm) {
	return 3.0 + 17.0 * storm;
}
// 0..1: насколько точка сейчас внутри порыва.
float wind_gust_raw(vec2 p, float t, vec2 wdir, float storm) {
	vec2 d = length(wdir) > 0.01 ? normalize(wdir) : vec2(1.0, 0.0);
	float s = dot(p, d) - t * wind_front_speed(storm);   // вдоль ветра, вместе с порывом
	float q = dot(p, vec2(-d.y, d.x));                   // поперёк
	// порывы — вытянутые поперёк ветра пятна 20–60 м, плюс мелкая рябь внутри
	float n = wf_noise(vec2(s * 0.022, q * 0.011 + t * 0.01)) * 0.7
			+ wf_noise(vec2(s * 0.07, q * 0.045)) * 0.3;
	return smoothstep(0.48, 0.82, n);
}
float wind_gust_field(vec2 p, float t, vec2 wdir, float storm, float gust) {
	float g = wind_gust_raw(p, t, wdir, storm);
	return 0.55 + g * (0.9 + 0.45 * gust);
}
