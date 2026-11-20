## test-timeout: 900
extends TestCase
## WEATHER: API ветра/погоды (CONTRACT_WEATHER), дождь, шторм, молния, укрытие от дождя.

func _init() -> void:
	scene_path = "res://scenes/world/match.tscn"
	timeout_sec = 2400.0

var cam: Camera3D
var w: World

func run() -> void:
	await wait(1.0)
	w = get_tree().get_first_node_in_group(&"world") as World
	check(w != null and w.is_ready, "мир готов")
	if w == null:
		return
	cam = Camera3D.new()
	cam.far = 4000.0
	w.add_child(cam)
	cam.make_current()
	var pl := get_tree().get_first_node_in_group(&"player") as Node
	if pl:
		pl.process_mode = Node.PROCESS_MODE_DISABLED
	for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	w.set_time_paused(true)
	w.set_time_of_day(11.0)
	var b := preload("res://tests/test_world_g1.gd").beach_spot(w, 80.0)
	var eye := b + Vector3(0, 1.7, 0)
	var look := Vector3(b.x * 0.4, 3.0, b.z * 0.4)
	var sea_look := b + (b - Vector3(0, b.y, 0)).normalized() * 60.0

	# --- API и диапазоны
	check(w.has_signal(&"weather_changed"), "сигнал weather_changed")
	var got := []
	w.weather_changed.connect(func(x: StringName) -> void: got.append(x))
	w.set_weather(&"clear", true)
	await wait(1.0)
	var ws := w.wind_speed()
	check(ws > 1.5 and ws < 5.0, "ясно: ветер 2–4 м/с (%.1f)" % ws)
	check(absf(w.wind_dir().length() - 1.0) < 0.01, "направление нормировано")
	check(w.rain_intensity() < 0.01 and w.storm_intensity() < 0.01, "ясно: без дождя и шторма")
	await _view(eye, look, "01_calm")
	await _view(eye, sea_look, "01b_calm_sea")

	w.set_weather(&"rain", true)
	await wait(2.0)
	ws = w.wind_speed()
	check(ws > 7.0 and ws < 14.0, "дождь: ветер 8–12 м/с (%.1f)" % ws)
	check(w.rain_intensity() > 0.6, "дождь идёт")
	check(got.has(&"rain"), "weather_changed пришёл")
	var c: Dictionary = w.sky.rain_fx.counts()
	check(int(c.drops) > 0 and int(c.sheets) > 0, "капли и дальние слои дождя: %s" % str(c))
	print("[test] дождь, частицы: ", c)
	await _view(eye, look, "02_rain")
	await _view(eye, sea_look, "02b_rain_sea")

	w.set_weather(&"storm", true)
	await wait(2.0)
	ws = w.wind_speed()
	check(ws > 16.0 and ws < 31.0, "шторм: ветер 18–28 м/с (%.1f)" % ws)
	check(w.storm_intensity() > 0.9, "шторм")
	check(w.wetness() > 0.5, "мир мокрый (%.2f)" % w.wetness())
	c = w.sky.rain_fx.counts()
	print("[test] шторм, частицы: ", c)
	check(int(c.leaves) > 0, "листья летят в шторм")
	await _view(eye, look, "03_storm")
	await _view(eye, sea_look, "03b_storm_sea")
	check(bool(c.get("curtain", false)), "дальняя завеса ливня в шторм")
	# пальмы вблизи: серия кадров — изгиб по ветру и раскачка порывами
	var palm := _near_tree(b)
	if palm != Vector3.INF:
		var wd := w.wind_dir()
		var side := Vector3(-wd.y, 0, wd.x)
		await _view(palm + side * 13.0 + Vector3(0, 4, 0), palm + Vector3(0, 6, 0), "04_storm_palms")
		for i in 6:
			await wait(0.35)
			await shot("04s_palm_seq_%d" % i)
	# лужи и мокрые материалы: смотрим вниз на ровный луг
	var mp := b.lerp(Vector3(0, b.y, 0), 0.22)
	mp.y = w.height_at(mp.x, mp.z)
	var box := MeshInstance3D.new()
	var bxm := BoxMesh.new()
	bxm.size = Vector3(1.2, 0.8, 1.2)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.8, 0.75, 0.68)
	sm.roughness = 0.9
	bxm.material = sm
	box.mesh = bxm
	w.add_child(box)
	box.global_position = mp + Vector3(2.0, 0.4, 0.0)
	# обход сцены идёт кусками (под llvmpipe кадры медленные) — регистрируем ящик сразу,
	# применение сырости проверяем как есть
	WetMaterials.register_node(box)
	for k in 10:
		await wait(0.5)
		if sm.albedo_color.r < 0.7:
			break
	print("[test] мокрых материалов: %d, альбедо пробного ящика %.2f, шероховатость %.2f" % [WetMaterials.count(), sm.albedo_color.r, sm.roughness])
	check(WetMaterials.count() > 0 and sm.albedo_color.r < 0.7 and sm.roughness < 0.6, "обычные материалы мокнут (StandardMaterial3D)")
	await _view(mp + Vector3(-5, 3.5, -5), mp + Vector3(1, 0, 1), "09_puddles")
	box.queue_free()
	# молния
	cam.global_position = eye
	cam.look_at(look)
	w.sky.force_lightning(cam.global_position, false)
	await wait(0.08)
	await shot("05_lightning")
	check(w.sky.lightning.strikes >= 1, "молния ударила")
	await wait(1.0)

	# --- непрерывность ветра (никаких скачков)
	var prev_s := w.wind_speed()
	var prev_d := w.wind_dir()
	var max_ds := 0.0
	var max_dd := 0.0
	for i in 60:
		await wait(0.1)
		max_ds = maxf(max_ds, absf(w.wind_speed() - prev_s))
		max_dd = maxf(max_dd, prev_d.angle_to(w.wind_dir()))
		prev_s = w.wind_speed()
		prev_d = w.wind_dir()
	print("[test] шторм: макс. изменение ветра за 0.1 с: %.2f м/с, %.3f рад" % [max_ds, max_dd])
	check(max_ds < 2.5, "скорость ветра без скачков (%.2f м/с за 0.1 с)" % max_ds)
	check(absf(max_dd) < 0.05, "направление ветра без скачков (%.3f рад)" % max_dd)

	# --- ночь в шторм
	w.set_time_of_day(23.0)
	await wait(1.0)
	await _view(eye, sea_look, "06_storm_night")
	w.sky.force_lightning(cam.global_position, false)
	await wait(0.08)
	await shot("07_lightning_night")
	w.set_time_of_day(11.0)
	await wait(1.0)

	# --- укрытие: крыша над камерой гасит ближние капли
	var roof := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(4, 0.2, 4)
	cs.shape = bx
	roof.add_child(cs)
	var rm := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bx.size
	rm.mesh = bm
	roof.add_child(rm)
	w.add_child(roof)
	roof.global_position = eye + Vector3(0, 1.4, 0)
	cam.global_position = eye
	cam.look_at(look)
	await wait(1.0)
	c = w.sky.rain_fx.counts()
	check(bool(c.covered) and int(c.drops) == 0, "под крышей ближних капель нет: %s" % str(c))
	await shot("08_under_roof")
	roof.queue_free()
	await wait(0.6)
	c = w.sky.rain_fx.counts()
	check(not bool(c.covered), "без крыши — снова дождь")

	# --- плавный переход (без instant): через 10 с шторм→ясно ещё далеко не ясно
	w.set_weather(&"clear", false)
	await wait(10.0)
	check(w.storm_intensity() > 0.5, "переход погоды плавный (шторм %.2f через 10 с)" % w.storm_intensity())
	w.set_weather(&"clear", true)
	await wait(0.5)

func _near_tree(p: Vector3) -> Vector3:
	var fl := get_tree().get_first_node_in_group(&"flora")
	if fl and fl.has_method(&"nodes_near"):
		var arr: Array = fl.call(&"nodes_near", p, 90.0, &"palm")
		if arr.is_empty():
			arr = fl.call(&"nodes_near", p, 90.0, &"")
		if arr.size() > 0:
			var e = arr[0]
			if e is Dictionary and (e as Dictionary).has("position"):
				return (e as Dictionary).position
			if e is Node3D:
				return (e as Node3D).global_position
	return Vector3.INF

func _view(from: Vector3, to: Vector3, name: String) -> void:
	cam.global_position = from
	cam.look_at(to)
	await wait(1.2)
	await shot(name)
