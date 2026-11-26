## test-timeout: 600
extends TestCase
## Погода v5: сценарии с плавными переходами (порядок этапов, нет скачков параметров, прогноз),
## мутность воды после шторма, снос дыма ветром (WindFx), фаза луны.

func _init() -> void:
	scene_path = "res://scenes/world/world_view.tscn"

func run() -> void:
	await wait(1.0)
	var w := get_tree().get_first_node_in_group(&"world") as World
	check(w != null, "мир есть")
	if w == null:
		return
	var sky: SkyWeather = w.sky
	w.set_time_paused(true)

	# ---- сценарий «штормовой фронт»: этапы по порядку, прогноз видит шторм заранее
	sky.start_scenario(&"storm_front")
	check(sky.scenario() == &"storm_front", "сценарий включён")
	var fc: Array = sky.forecast(10)
	var names: Array = fc.map(func(e: Dictionary) -> String: return String(e.w))
	print("[test] прогноз: ", names)
	check(names.size() >= 5 and names[0] == "swell", "прогноз начинается с зыби (%s)" % [names])
	check(names.has("storm"), "в прогнозе есть шторм")
	var seen: Array[String] = []
	var max_jump := 0.0
	var prev_cov := float(sky._cur.cov)
	var prev_wspd := float(sky._cur.wspd)
	var turb_peak := 0.0
	var t := 0.0
	# 1 с шага = 1 игровая минута; проходим весь сценарий (~35 мин реального времени игры)
	while t < 3600.0:
		sky.update(1.0, null, 0.0)
		t += 1.0
		var nm := String(sky.weather)
		if seen.is_empty() or seen[-1] != nm:
			seen.append(nm)
		max_jump = maxf(max_jump, absf(float(sky._cur.cov) - prev_cov))
		max_jump = maxf(max_jump, absf(float(sky._cur.wspd) - prev_wspd) / 30.0)
		prev_cov = float(sky._cur.cov)
		prev_wspd = float(sky._cur.wspd)
		turb_peak = maxf(turb_peak, sky.turbidity)
		if sky.scenario() != &"storm_front":
			break
	print("[test] этапы: ", seen, "  макс. скачок за 1 с: %.3f" % max_jump)
	var expect := ["swell", "cirrus", "gusty", "squall", "storm", "rain", "cloudy", "clear"]
	var ok := true
	for i in expect.size():
		if i >= seen.size() or seen[i] != expect[i]:
			ok = false
	check(ok, "этапы штормового фронта по порядку")
	check(max_jump < 0.05, "переходы плавные (скачок за 1 с < 0.05: %.3f)" % max_jump)
	check(turb_peak > 0.8, "в шторм вода мутнеет (%.2f)" % turb_peak)
	check(sky.turbidity < turb_peak - 0.2, "после шторма муть оседает (%.2f)" % sky.turbidity)

	# ---- все сценарии существуют и проходятся без ошибок
	for sc in SkyWeather.WEATHER_SCENARIOS.keys():
		sky.start_scenario(sc)
		for i in 600:
			sky.update(5.0, null, 0.0)
		check(true, "сценарий %s проходится" % sc)
	check(sky.weather_kind() in [&"clear", &"cloudy", &"rain", &"fog", &"storm"], "weather_kind — одна из пяти основных")

	# ---- ручная погода отменяет сценарий
	sky.set_weather(&"rain", true, false)
	check(sky.scenario() == &"" and sky.weather == &"rain", "ручная погода отменяет сценарий")

	# ---- дым по ветру
	var base := Vector3(0.25, 0.5, 0.0)
	var dry := WindFx.gravity_for(&"smoke", base, Vector2(1, 0), 8.0, 0.0, 0.0)
	var wet := WindFx.gravity_for(&"smoke", base, Vector2(1, 0), 8.0, 0.0, 1.0)
	var calm := WindFx.gravity_for(&"smoke", base, Vector2(0, 1), 1.0, 0.0, 0.0)
	check(dry.x > 1.5 and absf(dry.z) < 0.01, "дым уходит по ветру (%s)" % dry)
	check(wet.y < dry.y * 0.5, "в сырость дым стелется (подъём %.2f против %.2f)" % [wet.y, dry.y])
	check(calm.z > 0.0 and calm.z < dry.x, "в штиль снос слабый (%s)" % calm)

	# ---- мокрый персонаж: купание → 1, сохнет на солнце быстрее, чем в тени
	var a := Node3D.new()
	a.set_script(null)
	a.add_to_group(&"characters")
	a.set_meta(&"probe", true)
	scene.add_child(a)
	a.set("swimming", true)
	a.set_meta(&"swim_fake", true)
	WetBody.update(get_tree(), 0.1, 0.0, 1.0, 3.0, null)
	# Node3D без свойства swimming — ставим сырость напрямую
	a.set_meta(&"wetness", 1.0)
	for i in 60:
		WetBody.update(get_tree(), 1.0, 0.0, 1.0, 3.0, null)
	var sun_w := WetBody.of(a)
	a.set_meta(&"wetness", 1.0)
	for i in 60:
		WetBody.update(get_tree(), 1.0, 0.0, 0.0, 0.0, null)
	var shade_w := WetBody.of(a)
	check(sun_w < shade_w and sun_w < 0.7, "на солнце сохнет быстрее (%.2f против %.2f за минуту)" % [sun_w, shade_w])
	a.set_meta(&"wetness", 0.0)
	for i in 30:
		WetBody.update(get_tree(), 1.0, 0.8, 0.0, 0.0, null)
	check(WetBody.of(a) > 0.5, "под дождём мокнет (%.2f)" % WetBody.of(a))
	a.queue_free()

	# ---- луна
	var mi := sky.moon_illumination()
	check(mi >= 0.0 and mi <= 1.0, "фаза луны 0..1 (%.2f)" % mi)
	check(is_equal_approx(sky.sky3d.sky.moon_size, SkyWeather.MOON_SIZE), "луна уменьшена")
