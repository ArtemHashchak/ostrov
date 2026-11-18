extends TestCase
## Живой риф (фон): тысячи тропических рыб в шейдерах, растительность, донная
## живность; испуг стаи от пловца; сценки охоты (барракуда, акула, электрический
## скат, чайка); бюджет процессора; скриншоты под водой и с поверхности.

class Swimmer extends Node3D:
	func _ready() -> void:
		add_to_group(&"characters")
	func is_in_water() -> bool:
		return true

var sea: Sea
var life: ReefLife
var cam: Camera3D

func _init() -> void:
	scene_path = "res://scenes/world/world_view.tscn"
	timeout_sec = 2900.0

func _best_zone() -> Dictionary:
	var best: Dictionary = {}
	for z in sea.reef_zones():
		if z.kind == &"atoll" and (best.is_empty() or int(z.corals) > int(best.corals)):
			best = z
	return best

func run() -> void:
	await wait(1.0)
	var w := get_tree().get_first_node_in_group(&"world") as World
	check(w != null and w.is_ready, "мир готов")
	if w == null:
		return
	w.set_time_of_day(11.5)
	w.set_weather(&"clear", true)
	var t0 := Time.get_ticks_msec()
	sea = Sea.new()
	sea.auto_populate = false
	scene.add_child(sea)
	sea._find_world()
	sea.populate()
	var ms := Time.get_ticks_msec() - t0
	life = sea.reef_life as ReefLife
	check(life != null, "живой риф построен")
	if life == null:
		return
	print("[test] заселение моря: %d мс" % ms)
	cam = Camera3D.new()
	scene.add_child(cam)
	cam.current = true
	cam.far = 900.0
	var z := _best_zone()
	var c: Vector2 = z.center
	var spot := Vector3(c.x, 0, c.y)
	var bestd := 99.0
	for i in 48:
		var a := TAU * i / 48.0
		for r: float in [0.0, 5.0, 10.0, 15.0, 25.0, 40.0]:
			var x := c.x + cos(a) * r
			var zz := c.y + sin(a) * r
			var d := sea.depth_at(x, zz)
			if absf(d - 4.0) < bestd:
				bestd = absf(d - 4.0)
				spot = Vector3(x, 0, zz)
	var t1 := Time.get_ticks_usec()
	life.stream_now(Vector3(spot.x, sea.floor_at(spot.x, spot.z) + 1.4, spot.z))
	var ms_stream := float(Time.get_ticks_usec() - t1) / 1000.0
	print("[test] подгрузка 5×5 клеток: %.0f мс (%.1f мс на клетку); рыб %d в %d группах, декора %d, ходоков %d, голов %d" % [
		ms_stream, ms_stream / maxf(life.cells_built, 1), life.fish_count, life.schools.size(), life.decor_count, life.crawler_count, life.heads_count])
	check(ms_stream / maxf(life.cells_built, 1) < 60.0, "клетка строится быстро: %.1f мс" % (ms_stream / maxf(life.cells_built, 1)))
	check(life.fish_count >= 1500, "рыб вокруг: %d в %d группах" % [life.fish_count, life.schools.size()])
	check(life.decor_count >= 3000, "растительности и декора вокруг: %d" % life.decor_count)
	check(life.crawler_count >= 40, "крабов и лангустов вокруг: %d" % life.crawler_count)
	var kinds := {}
	for s in life.schools:
		kinds[s.species] = true
	check(kinds.size() >= 10, "видов рыб вокруг: %d" % kinds.size())
	var fy := sea.floor_at(spot.x, spot.z)
	life.scenes.set(&"enabled", false)
	cam.global_position = Vector3(spot.x, fy + 1.4, spot.z)
	cam.look_at(Vector3(spot.x + 8.0, fy + 0.8, spot.z + 3.0))
	await wait(1.5)
	await shot("01_reef")
	cam.global_position = Vector3(spot.x - 5.0, fy + 2.2, spot.z - 4.0)
	cam.look_at(Vector3(spot.x + 3.0, fy + 0.4, spot.z + 2.0))
	await wait(0.6)
	await shot("02_reef_wide")
	# группа рыб крупно
	var near := life.schools_near(cam.global_position, 30.0)
	var grp: ReefSchool = null
	for s in near:
		if s.mode == 1 and s.species != &"clownfish" and s.count() >= 3 and (grp == null or s.count() > grp.count()):
			grp = s
	if grp:
		var gc := grp.current_center()
		cam.global_position = _in_water(gc + Vector3(-2.5, 0.4, 2.0))
		cam.look_at(gc)
		await wait(0.5)
		await shot("03_group_" + String(grp.species))
	# рыбы-клоуны в актинии
	var clown: ReefSchool = null
	for s in life.schools:
		if s.species == &"clownfish" and s.center.distance_to(cam.global_position) < 200.0:
			clown = s
			break
	if clown:
		cam.global_position = _in_water(clown.center + Vector3(-0.8, 0.25, 0.7))
		cam.look_at(clown.center + Vector3(0, -0.15, 0))
		await wait(0.5)
		await shot("04_clownfish")
	# стая в толще
	var open: ReefSchool = null
	for s in life.schools_near(Vector3(spot.x, fy, spot.z), 80.0):
		if s.mode == 0 and s.species != &"sardine":
			open = s
			break
	if open:
		var oc := open.current_center()
		cam.global_position = _in_water(oc + Vector3(-7.0, 0.3, 4.0))
		cam.look_at(oc)
		await wait(0.4)
		await shot("05_school_" + String(open.species))
		# пловец рядом — стая разлетается
		var sw := Swimmer.new()
		scene.add_child(sw)
		sw.global_position = open.current_center() + Vector3(0.5, 0, 0)
		await wait(0.8)
		check(open.is_scared(), "стая %s разлетелась от пловца" % open.species)
		await shot("06_school_scared")
		sw.queue_free()
	else:
		check(false, "нет стаи рядом с рифом")
	# морская трава / дно у берега
	cam.global_position = Vector3(spot.x, fy + 1.4, spot.z)
	cam.look_at(Vector3(spot.x + 8.0, fy + 0.8, spot.z + 3.0))
	await wait(0.3)

	# --- бюджет процессора ---
	t1 = Time.get_ticks_usec()
	for i in 60:
		life._process(1.0 / 60.0)
	var ms_life := float(Time.get_ticks_usec() - t1) / 60000.0
	life._scare_acc = 0.0
	t1 = Time.get_ticks_usec()
	for i in 20:
		life._scare_near_threats()
	var ms_scare := float(Time.get_ticks_usec() - t1) / 20000.0
	print("[test] живой риф: кадр %.3f мс, проверка испуга %.3f мс (раз в %.2f с)" % [ms_life, ms_scare, ReefLife.SCARE_STEP])
	check(ms_life < 0.5, "кадр живого рифа %.3f мс" % ms_life)
	var tris := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	print("[test] кадр у рифа: %d треуг., %d вызовов" % [tris, calls])

	# --- сценки ---
	var sc := life.scenes as ReefScenes
	for kind: StringName in [&"hunt", &"shark", &"ray"]:
		w.set_time_of_day(11.5)
		cam.global_position = Vector3(spot.x, fy + 1.4, spot.z)
		cam.look_at(Vector3(spot.x + 8.0, fy + 0.8, spot.z + 3.0))
		await wait(0.2)
		var ok := false
		for attempt in 4:
			if sc.force(kind):
				ok = true
				break
			cam.rotate_y(PI * 0.5)
			await wait(0.2)
		check(ok, "сценка %s запущена" % kind)
		if not ok:
			continue
		var shot_done := false
		var t_start := Time.get_ticks_msec()
		var g0 := ReefLife.time
		while int(sc.done.get(kind, 0)) == 0 and ReefLife.time - g0 < 45.0 and Time.get_ticks_msec() - t_start < 900000 and sc.active_count() > 0:
			await wait(0.25)
			var s: Dictionary = sc._active[sc._active.size() - 1]
			if s.kind != kind:
				continue
			var focus := _focus(s)
			if focus != Vector3.INF:
				cam.global_position = _in_water(focus + Vector3(-3.2, 0.8, 2.6))
				cam.look_at(focus)
			if not shot_done and int(s.get("phase", 0)) >= 1:
				shot_done = true
				await shot("07_scene_%s" % kind)
		check(int(sc.done.get(kind, 0)) >= 1, "сценка %s: добыча поймана" % kind)
		await shot("08_after_%s" % kind)
		# дождаться конца, чтобы не мешать следующей
		var t_end := Time.get_ticks_msec()
		var g1 := ReefLife.time
		while sc.active_count() > 0 and ReefLife.time - g1 < 45.0 and Time.get_ticks_msec() - t_end < 600000:
			await wait(0.5)
	# чайка — с поверхности над косяком сардин
	w.set_time_of_day(11.5)
	if life.bait_balls.is_empty():
		for r: float in [40.0, 70.0, 100.0, 140.0]:
			for i in 12:
				var a := TAU * i / 12.0
				var q := Vector3(spot.x + cos(a) * r, sea.water_y() + 2.0, spot.z + sin(a) * r)
				cam.global_position = q
				life.stream_now(q)
				if not life.bait_balls.is_empty():
					break
			if not life.bait_balls.is_empty():
				break
	check(not life.bait_balls.is_empty(), "косяк сардин нашёлся")
	if life.bait_balls.is_empty():
		return
	var bb: ReefSchool = life.bait_balls[0]
	var bc := bb.current_center()
	cam.global_position = Vector3(bc.x - 14.0, sea.water_y() + 2.5, bc.z - 10.0)
	cam.look_at(Vector3(bc.x, sea.water_y() + 3.0, bc.z))
	await wait(0.3)
	check(sc.force(&"gull"), "сценка gull запущена")
	var tg := Time.get_ticks_msec()
	var g2 := ReefLife.time
	var dive_shot := false
	while sc.active_count() > 0 and ReefLife.time - g2 < 45.0 and Time.get_ticks_msec() - tg < 900000:
		await wait(0.2)
		if sc._active.is_empty():
			break
		var s: Dictionary = {}
		for x: Dictionary in sc._active:
			if x.kind == &"gull":
				s = x
		if s.is_empty():
			break
		var g: Node3D = s.gull
		cam.look_at(g.global_position.lerp(Vector3(bc.x, sea.water_y(), bc.z), 0.5))
		if not dive_shot and int(s.phase) >= 1 and g.global_position.y < sea.water_y() + 4.0:
			dive_shot = true
			await shot("09_gull_dive")
		if int(s.phase) == 3 and float(s.get("leave_t", 0.0)) > 0.6:
			await shot("10_gull_catch")
			break
	check(int(sc.done.get(&"gull", 0)) + int(sc.started.get(&"gull", 0)) >= 1, "чайка ныряла (поймала: %d)" % int(sc.done.get(&"gull", 0)))
	# с поверхности: тени стай и трава видны сверху
	cam.global_position = Vector3(spot.x - 4.0, sea.water_y() + 5.0, spot.z - 4.0)
	cam.look_at(Vector3(spot.x + 6.0, fy, spot.z + 6.0))
	await wait(0.5)
	await shot("11_from_above")
	sea.queue_free()
	await wait(0.5)

func _in_water(p: Vector3) -> Vector3:
	var f := sea.floor_at(p.x, p.z)
	p.y = clampf(p.y, f + 0.4, sea.water_y() - 0.4)
	return p

func _focus(s: Dictionary) -> Vector3:
	if s.has("fish") and s.fish is Node3D and is_instance_valid(s.fish):
		return (s.fish as Node3D).global_position
	var preds: Array = s.get("predators", [])
	if not preds.is_empty() and is_instance_valid(preds[0]):
		return (preds[0] as Node3D).global_position
	return Vector3.INF
