extends TestCase
## Волны: устойчивые (без скачков направления/силы), «сеты», шторм ×3+, нагон воды.
## CPU-проверки ведут океан вручную шагами 0.05 с (быстро, без кадров), затем —
## кадры на GPU: последовательность штиля, шторм, нагон на пляже.

func _init() -> void:
	scene_path = "res://scenes/world/world_view.tscn"
	timeout_sec = 3000.0

var w: World
var oc: Ocean

func _advance(seconds: float, dt: float, pts: Array[Vector2], out: Array) -> void:
	var cam := Vector3(pts[0].x, 3.0, pts[0].y)
	var n := int(seconds / dt)
	for i in n:
		w._update_surge(dt)
		oc.set_weather_drive(w.wind_dir(), w.wind_speed(), w.storm_intensity(), w.rain_factor())
		oc.update(dt, cam, w.water_level(), w.sky.wave_scale())
		var row := []
		for p in pts:
			row.append(oc.wave_height(p.x, p.y))
		out.append(row)

func _stats(rows: Array, col: int) -> Dictionary:
	var lo := 1e9
	var hi := -1e9
	var step := 0.0
	var jerk := 0.0
	for i in rows.size():
		var h: float = rows[i][col]
		lo = minf(lo, h)
		hi = maxf(hi, h)
		if i > 0:
			step = maxf(step, absf(h - float(rows[i - 1][col])))
		if i > 1:
			jerk = maxf(jerk, absf(h - 2.0 * float(rows[i - 1][col]) + float(rows[i - 2][col])))
	return {"range": hi - lo, "step": step, "jerk": jerk}

func run() -> void:
	await wait(1.0)
	w = get_tree().get_first_node_in_group(&"world") as World
	check(w != null and w.is_ready, "мир готов")
	if w == null:
		return
	oc = w.ocean
	Settings.graphics_quality = 2
	Settings.graphics_changed.emit()
	w.set_time_of_day(11.5)
	w.set_weather(&"clear", true)
	w.set_time_paused(true)
	w.set_process(false)   # океан ведём вручную
	# открытое море у первого острова
	var I: Dictionary = w.islands()[0]
	var c: Vector2 = I.center
	var r: float = I.radius
	var sea := c + Vector2(r + 80.0, 0.0)
	var best := 0.0
	for i in 36:
		var q := c + Vector2.from_angle(TAU * i / 36.0) * (r + 80.0)
		if oc.depth_at(q.x, q.y) > best:
			best = oc.depth_at(q.x, q.y)
			sea = q
	# точка у берега (глубина ~3 м) на луче к острову — для шоалинга
	var near := sea
	for k in 400:
		var q := sea.lerp(c, float(k) / 400.0)
		if oc.depth_at(q.x, q.y) < 3.0:
			near = q
			break
	var pts: Array[Vector2] = [sea, sea + Vector2(17.0, -9.0), sea + Vector2(-31.0, 22.0), near]
	print("[test] точка моря: глубина %.1f м; у берега: %.1f м" % [best, oc.depth_at(near.x, near.y)])

	# --- штиль/ясно: 120 с, шаг 0.05 с ---
	_advance(20.0, 0.05, pts, [])   # сглаживание погоды устоялось
	var dir0 := oc.swell_dir
	var rows: Array = []
	_advance(120.0, 0.05, pts, rows)
	var st := _stats(rows, 0)
	print("[test] ясно: размах %.2f м, макс. шаг %.4f м/0.05с, макс. 2-я разность %.5f" % [st.range, st.step, st.jerk])
	check(st.range > 0.25 and st.range < 2.0, "ясно: размах волны %.2f м" % st.range)
	check(st.step < 0.06, "ясно: высота меняется плавно (%.4f м за 0.05 с)" % st.step)
	check(st.jerk < 0.006, "ясно: нет рывков (2-я разность %.5f)" % st.jerk)
	var turn := rad_to_deg(absf(angle_difference(dir0.angle(), oc.swell_dir.angle())))
	print("[test] поворот зыби за 120 с: %.2f°" % turn)
	check(turn < 10.0, "направление зыби меняется медленно (%.2f° за 2 мин)" % turn)
	# «сеты»: огибающая (размах в окнах 12 с) меняется, но плавно
	var env: Array[float] = []
	for k in 10:
		var lo := 1e9
		var hi := -1e9
		for i in range(k * 240, (k + 1) * 240):
			lo = minf(lo, rows[i][0])
			hi = maxf(hi, rows[i][0])
		env.append(hi - lo)
	print("[test] огибающая по 12 с: ", env.map(func(v): return snappedf(v, 0.01)))
	check(env.max() / maxf(env.min(), 0.01) > 1.25, "есть сеты: волны то выше, то ниже (%.2f×)" % (env.max() / maxf(env.min(), 0.01)))

	# --- пространство: гладкость вдоль 10 м ---
	var sj := 0.0
	var h0 := oc.wave_height(sea.x, sea.y)
	for i in 40:
		var h1 := oc.wave_height(sea.x + (i + 1) * 0.25, sea.y)
		sj = maxf(sj, absf(h1 - h0))
		h0 = h1
	check(sj < 0.12, "высота непрерывна по пространству (%.3f м на 25 см)" % sj)

	# --- стоимость CPU ---
	# лучший из 5 замеров по 400 вызовов: машина с тестами общая, одиночный замер
	# ловит чужую нагрузку (llvmpipe других процессов занимает оба ядра)
	var us := INF
	for rep in 5:
		var t0 := Time.get_ticks_usec()
		for i in 400:
			oc.wave_height(sea.x + i * 0.37, sea.y - i * 0.21)
		us = minf(us, float(Time.get_ticks_usec() - t0) / 400.0)
		await wait(0.05)
	print("[test] wave_height: %.1f мкс/вызов" % us)
	check(us < 40.0, "wave_height дешёвая: %.1f мкс" % us)

	# --- шторм: волны в разы выше, нагон воды ---
	var lvl0 := w.water_level() - w.storm_surge()
	w.set_weather(&"storm", true)
	_advance(360.0, 0.1, pts, [])   # 6 мин: погода, волны и нагон устоялись
	var srows: Array = []
	_advance(120.0, 0.05, pts, srows)
	var ss := _stats(srows, 0)
	print("[test] шторм: размах %.2f м (ясно %.2f), шаг %.4f, ветер %.1f м/с, шторм %.2f, нагон %.2f м" % [ss.range, st.range, ss.step, w.wind_speed(), w.storm_intensity(), w.storm_surge()])
	check(ss.range > st.range * 2.5, "шторм: волны в %.1f раза выше" % (ss.range / maxf(st.range, 0.01)))
	check(ss.step < 0.2, "шторм: всё равно плавно (%.4f м за 0.05 с)" % ss.step)
	var sn := _stats(srows, 3)
	print("[test] шторм у берега (глубина ~3 м): размах %.2f м (в море %.2f)" % [sn.range, ss.range])
	check(sn.range > ss.range * 1.05, "шоалинг: у берега волны выше, чем в море (%.2f > %.2f)" % [sn.range, ss.range])
	check(sn.step < 0.3, "у берега плавно (%.4f м за 0.05 с)" % sn.step)
	check(w.storm_surge() > 0.8, "нагон воды в шторм %.2f м" % w.storm_surge())
	check(absf(w.water_level() - lvl0 - w.storm_surge()) < 0.01, "water_level включает нагон")
	var storm_level := w.water_level()
	# после шторма вода уходит
	w.set_weather(&"clear", true)
	_advance(600.0, 0.2, pts, [])
	print("[test] через 10 мин после шторма: нагон %.2f м" % w.storm_surge())
	check(w.storm_surge() < 0.3, "нагон спадает после шторма (%.2f м)" % w.storm_surge())

	# --- кадры на GPU ---
	w.set_process(true)
	var cam := Camera3D.new()
	scene.add_child(cam)
	cam.current = true
	cam.far = 4000.0
	await _shoot_sequence(cam, sea, "calm")
	var beach := _beach_point(sea, c)
	await _beach_shot(cam, beach, sea, "beach_eye_calm_day")
	w.set_weather(&"storm", true)
	w.set_process(false)
	_advance(360.0, 0.1, pts, [])
	w.set_process(true)
	cam.global_position = Vector3(sea.x, w.water_level() + 5.0, sea.y)
	cam.look_at(Vector3(sea.x + 80.0, w.water_level(), sea.y + 30.0))
	await wait(1.0)
	await shot("storm_open")
	# брызги частицами выключены (белые точки в воздухе — отзыв пользователя)
	check(oc._sprays.is_empty(), "шторм: нет частиц-брызг над водой")
	cam.global_position = Vector3(sea.x, w.water_level() + 14.0, sea.y)
	cam.look_at(Vector3(sea.x + 180.0, w.water_level(), sea.y + 40.0))
	await wait(0.6)
	await shot("storm_high")
	# уровень глаз (пловец/плот) и вид с 40 м, днём и ночью
	cam.global_position = Vector3(sea.x, w.wave_height(sea.x, sea.y) + 1.7, sea.y)
	cam.look_at(Vector3(sea.x + 60.0, w.water_level() + 0.5, sea.y + 20.0))
	await wait(0.8)
	await shot("storm_eye_day")
	cam.global_position = Vector3(sea.x, w.water_level() + 40.0, sea.y)
	cam.look_at(Vector3(sea.x + 160.0, w.water_level(), sea.y + 60.0))
	await wait(0.6)
	await shot("storm_40m_day")
	w.set_time_of_day(23.0)
	await wait(1.0)
	await shot("storm_40m_night")
	cam.global_position = Vector3(sea.x, w.wave_height(sea.x, sea.y) + 1.7, sea.y)
	cam.look_at(Vector3(sea.x + 60.0, w.water_level() + 0.5, sea.y + 20.0))
	await wait(0.6)
	await shot("storm_eye_night")
	await _beach_shot(cam, beach, sea, "beach_eye_storm_night")
	w.set_time_of_day(11.5)
	await wait(0.6)
	await _beach_shot(cam, beach, sea, "beach_eye_storm_day")
	# нагон на пляже: смотрим с суши на берег
	var shore := c + (sea - c).normalized() * (r * 0.9)
	var land := c + (sea - c).normalized() * (r * 0.6)
	cam.global_position = Vector3(land.x, w.height_at(land.x, land.y) + 3.0, land.y)
	cam.look_at(Vector3(shore.x, storm_level, shore.y) + Vector3(0, 0.0, 0))
	await wait(1.0)
	await shot("storm_surge_beach")
	w.set_weather(&"clear", true)
	w.set_process(false)
	_advance(900.0, 0.25, pts, [])
	w.set_process(true)
	await wait(0.8)
	await shot("calm_beach_after")

func _shoot_sequence(cam: Camera3D, sea: Vector2, tag: String) -> void:
	cam.global_position = Vector3(sea.x, w.water_level() + 3.0, sea.y)
	cam.look_at(Vector3(sea.x + 70.0, w.water_level(), sea.y + 25.0))
	await wait(1.0)
	for i in 6:
		await shot("%s_seq_%d" % [tag, i])
		await wait(0.4)

## Точка на пляже: от моря к центру острова, где суша чуть выше воды.
func _beach_point(sea: Vector2, c: Vector2) -> Vector2:
	for k in 600:
		var q := sea.lerp(c, float(k) / 600.0)
		if w.height_at(q.x, q.y) > w.water_level() + 0.6:
			return q
	return c

## Стоим на пляже (глаза 1.7 м), смотрим в море.
func _beach_shot(cam: Camera3D, beach: Vector2, sea: Vector2, tag: String) -> void:
	var back := beach + (beach - sea).normalized() * 3.0
	cam.global_position = Vector3(back.x, w.height_at(back.x, back.y) + 1.7, back.y)
	cam.look_at(Vector3(sea.x, w.water_level() + 0.3, sea.y))
	await wait(1.2)
	await shot(tag)
