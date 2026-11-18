extends TestCase
## Океан: FFT-зыбь по пресету (высокое — включена, низкое — Герстнер), совпадение
## wave_height с формулой шейдера по смыслу (непрерывность, амплитуда), вид снизу,
## скриншоты: берег, открытое море, закат, под водой (взгляд вверх и на риф), низкое.

func _init() -> void:
	scene_path = "res://scenes/world/world_view.tscn"
	timeout_sec = 3000.0

func run() -> void:
	await wait(1.0)
	var w := get_tree().get_first_node_in_group(&"world") as World
	check(w != null and w.is_ready, "мир готов")
	if w == null:
		return
	var oc := w.ocean
	Settings.graphics_quality = 2
	Settings.graphics_changed.emit()
	check(oc.use_fft, "высокое: FFT-зыбь включена")
	check(oc.GRID == Ocean.GRID_BY_Q[2], "сетка высокого: %d" % oc.GRID)
	var sea := Sea.new()
	sea.auto_populate = false
	scene.add_child(sea)
	sea._find_world()
	sea.populate()
	w.set_time_of_day(11.5)
	w.set_weather(&"clear", true)
	w.set_time_paused(true)

	# --- wave_height: гладкая по пространству и времени, амплитуда в разумных пределах ---
	var I: Dictionary = w.islands()[0]
	var c: Vector2 = I.center
	var r: float = I.radius
	var sea_pt := Vector3(c.x + r + 70.0, 0, c.y)
	var best_d := 0.0
	for i in 48:
		var a := TAU * i / 48.0
		for dd: float in [45.0, 70.0, 95.0]:
			var q := c + Vector2(cos(a), sin(a)) * (r + dd)
			var dep := oc.depth_at(q.x, q.y)
			if dep > best_d:
				best_d = dep
				sea_pt = Vector3(q.x, 0, q.y)
	print("[test] открытое море: глубина %.1f м" % best_d)
	var cam := Camera3D.new()
	scene.add_child(cam)
	cam.current = true
	cam.far = 4000.0
	cam.global_position = sea_pt + Vector3(0, 3, 0)
	await wait(0.3)
	var lo := 99.0
	var hi := -99.0
	var jump := 0.0
	var prev := w.wave_height(sea_pt.x, sea_pt.z)
	for i in 120:
		await get_tree().process_frame
		var h := w.wave_height(sea_pt.x, sea_pt.z)
		lo = minf(lo, h)
		hi = maxf(hi, h)
		jump = maxf(jump, absf(h - prev))
		prev = h
	print("[test] волна в точке: %.2f..%.2f, макс. шаг за кадр %.3f" % [lo, hi, jump])
	check(hi - lo > 0.05 and hi - lo < 2.5, "размах волны %.2f м" % (hi - lo))
	check(jump < 0.12, "высота меняется плавно (шаг %.3f м)" % jump)
	var sj := 0.0
	var h0 := w.wave_height(sea_pt.x, sea_pt.z)
	for i in 40:
		var h1 := w.wave_height(sea_pt.x + (i + 1) * 0.25, sea_pt.z)
		sj = maxf(sj, absf(h1 - h0))
		h0 = h1
	check(sj < 0.2, "высота непрерывна по пространству (шаг %.3f м на 25 см)" % sj)

	# --- стоимость CPU-выборки (боты и плоты зовут часто) ---
	var t0 := Time.get_ticks_usec()
	for i in 2000:
		w.wave_height(sea_pt.x + i * 0.37, sea_pt.z - i * 0.21)
	var us := float(Time.get_ticks_usec() - t0) / 2000.0
	print("[test] wave_height: %.1f мкс/вызов" % us)
	check(us < 60.0, "wave_height дешёвая: %.1f мкс" % us)

	# --- скриншоты ---
	var wy := w.water_level()
	var shore := Vector3(c.x + r * 0.92, 0, c.y)
	cam.global_position = Vector3(shore.x - 6.0, w.height_at(shore.x - 6.0, shore.z) + 2.2, shore.z + 2.0)
	cam.look_at(Vector3(shore.x + 40.0, wy, shore.z + 10.0))
	await wait(1.2)
	await shot("shore")
	cam.global_position = sea_pt + Vector3(0, 2.4, 0)
	cam.look_at(sea_pt + Vector3(60, 1.0, 25))
	await wait(0.8)
	await shot("open_sea")
	cam.global_position = sea_pt + Vector3(0, 12.0, 0)
	cam.look_at(sea_pt + Vector3(200, 0.0, 30))
	await wait(0.5)
	await shot("open_sea_high")
	w.set_time_of_day(18.6)
	await wait(1.5)
	cam.global_position = sea_pt + Vector3(0, 3.0, 0)
	cam.look_at(sea_pt + Vector3(-200, 4.0, 0))
	await wait(0.8)
	await shot("sunset_w")
	cam.look_at(sea_pt + Vector3(200, 4.0, 0))
	await wait(0.5)
	await shot("sunset_e")
	w.set_time_of_day(12.0)
	await wait(1.0)
	# под водой: взгляд вверх на поверхность (окно Снеллиуса) и вдаль
	var deep := sea_pt + Vector3(0, -3.5, 0)
	cam.global_position = deep
	cam.look_at(deep + Vector3(4.0, 6.0, 1.0))
	await wait(1.0)
	await shot("under_up")
	cam.look_at(deep + Vector3(20.0, -2.0, 4.0))
	await wait(0.5)
	await shot("under_far")
	# низкое качество: Герстнер без зыби
	cam.global_position = sea_pt + Vector3(0, 2.4, 0)
	cam.look_at(sea_pt + Vector3(60, 1.0, 25))
	Settings.graphics_quality = 0
	Settings.graphics_changed.emit()
	check(not oc.use_fft and oc.GRID == Ocean.GRID_BY_Q[0], "низкое: без FFT, сетка %d" % oc.GRID)
	await wait(0.8)
	await shot("open_sea_low")
	Settings.graphics_quality = 2
	Settings.graphics_changed.emit()
	await wait(0.2)
