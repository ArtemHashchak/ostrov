extends TestCase
## SEA+ на полном архипелаге: рифы у атоллов и общих островов, обитатели (скаты,
## черепахи, медузы), распределение акул (проливы гуще, рифы реже), ожоги медуз,
## производительность, скриншоты рифа под водой и с поверхности.

class Swimmer extends Node3D:
	var health: float = 100.0
	var max_health: float = 100.0
	var stings: int = 0
	func _ready() -> void:
		add_to_group(&"characters")
	func is_in_water() -> bool:
		return true
	func is_dead() -> bool:
		return false
	func apply_damage(amount: float, _source: Node, kind: StringName) -> void:
		if kind == &"sting":
			stings += 1
		health -= amount

func _init() -> void:
	scene_path = "res://scenes/world/world_view.tscn"
	timeout_sec = 1450.0

func run() -> void:
	await wait(1.0)
	var w := get_tree().get_first_node_in_group(&"world") as World
	check(w != null and w.is_ready, "мир готов")
	if w == null:
		return
	var t0 := Time.get_ticks_msec()
	var sea := Sea.new()
	sea.auto_populate = false
	scene.add_child(sea)
	sea._find_world()
	sea.populate()
	var build_ms := Time.get_ticks_msec() - t0
	print("[test] заселение моря: %d мс" % build_ms)
	check(build_ms < 30000, "море заселено за %.1f с" % (build_ms / 1000.0))
	var reefs := sea.reefs as SeaReefs
	check(reefs != null and reefs.instances > 2000, "рифы: %d экземпляров, %d узлов" % [reefs.instances if reefs else 0, reefs.get_child_count() if reefs else 0])
	var zones := sea.reef_zones()
	var zkinds := {}
	for z in zones:
		zkinds[z.kind] = int(zkinds.get(z.kind, 0)) + 1
	print("[test] пятна рифа: ", zkinds)
	check(int(zkinds.get(&"atoll", 0)) >= 3 and int(zkinds.get(&"shared", 0)) >= 3, "рифы у атоллов и общих островов")
	check(not zkinds.has(&"swamp"), "у болот рифов нет")
	var life := sea.life as SeaLife
	var nr := life.count_of(SeaCreature.Kind.RAY)
	var nt := life.count_of(SeaCreature.Kind.TURTLE)
	var nj := life.count_of(SeaCreature.Kind.JELLY)
	check(nr >= 10 and nt >= 15 and nj >= 10, "обитатели: скатов %d, черепах %d, медуз %d" % [nr, nt, nj])
	var st := sea.straits()
	check(st.size() >= 20, "проливов: %d" % st.size())
	check(sea.sharks.size() >= 50 and sea.sharks.size() <= Sea.MAX_SHARKS, "акул: %d" % sea.sharks.size())
	# плотность: середины проливов против рифов атоллов
	var ds := 0.0
	for s in st:
		var m: Vector2 = s.mid
		ds += sea.shark_density_at(Vector3(m.x, 0, m.y))
	ds /= maxf(st.size(), 1)
	var dr := 0.0
	var nz := 0
	for z in zones:
		if z.kind == &"atoll":
			var c: Vector2 = z.center
			dr += sea.shark_density_at(Vector3(c.x, 0, c.y))
			nz += 1
	dr /= maxf(nz, 1)
	check(ds > dr, "в проливах акул больше, чем над рифами атоллов: %.2f > %.2f" % [ds, dr])
	var big_strait := 0
	var big_all := 0
	for s in sea.sharks:
		if s.species != &"reef":
			big_all += 1
			for q in st:
				if (q.mid as Vector2).distance_to(s.home) < 1.0:
					big_strait += 1
					break
	check(big_strait * 2 >= big_all, "крупные акулы в основном в проливах: %d из %d" % [big_strait, big_all])
	# переправа: длинный пролив опаснее, чем мелководье у берега
	var s0: Dictionary = st[0]
	var p0: Vector2 = s0.p0
	var p1: Vector2 = s0.p1
	var cross := sea.safe_crossing_score(Vector3(p0.x, 0, p0.y), Vector3(p1.x, 0, p1.y))
	print("[test] безопасность переправы через пролив %.0f м: %.2f" % [s0.gap, cross])
	check(cross < 0.95, "переправа через пролив небезопасна: %.2f" % cross)

	# --- медуза жалит ---
	var jelly: SeaCreature = null
	for c in life.creatures:
		if c.kind == SeaCreature.Kind.JELLY:
			jelly = c
			break
	var cam := Camera3D.new()
	scene.add_child(cam)
	cam.current = true
	cam.far = 900.0
	var sw := Swimmer.new()
	scene.add_child(sw)
	cam.global_position = jelly.global_position + Vector3(-2.5, 0.2, 2.0)
	cam.look_at(jelly.global_position)
	sw.global_position = jelly.global_position + Vector3(0, -0.5, 0)
	await wait(1.0)
	sw.global_position = jelly.global_position + Vector3(0, -0.5, 0)
	await wait(0.5)
	check(sw.stings >= 1 and sw.health < 100.0, "медуза обожгла пловца: %d раз, здоровье %.0f" % [sw.stings, sw.health])
	await shot("jelly")
	sw.queue_free()

	# --- скриншоты рифа ---
	var best: Dictionary = {}
	for z in zones:
		if z.kind == &"atoll" and (best.is_empty() or int(z.corals) > int(best.corals)):
			best = z
	var c: Vector2 = best.center
	var wy := sea.water_y()
	# ищем поблизости место с глубиной 3–5 м
	var spot := Vector3(c.x, 0, c.y)
	var bestd := 99.0
	for i in 60:
		var a := TAU * i / 60.0
		for r in [0.0, 4.0, 8.0, 12.0, 16.0]:
			var x := c.x + cos(a) * r
			var z := c.y + sin(a) * r
			var d := sea.depth_at(x, z)
			if absf(d - 4.0) < bestd:
				bestd = absf(d - 4.0)
				spot = Vector3(x, 0, z)
	var fy := sea.floor_at(spot.x, spot.z)
	w.set_time_of_day(12.0)
	w.set_weather(&"clear", true)
	cam.global_position = Vector3(spot.x, fy + 1.6, spot.z)
	cam.look_at(Vector3(spot.x + 6.0, fy + 0.3, spot.z + 3.0))
	await wait(1.5)
	await shot("reef_under")
	cam.global_position = Vector3(spot.x - 6.0, fy + 1.2, spot.z - 2.0)
	cam.look_at(Vector3(spot.x, fy + 0.6, spot.z))
	await wait(0.6)
	await shot("reef_under2")
	cam.global_position = Vector3(spot.x - 4.0, wy + 6.0, spot.z - 4.0)
	cam.look_at(Vector3(spot.x + 6.0, fy, spot.z + 6.0))
	await wait(0.8)
	await shot("reef_above")
	# скат и черепаха крупно
	for k in [SeaCreature.Kind.RAY, SeaCreature.Kind.TURTLE]:
		var cr: SeaCreature = null
		for x in life.creatures:
			if x.kind == k:
				cr = x
				break
		if cr:
			cam.global_position = cr.global_position + Vector3(-2.6, 0.9, 2.2)
			cam.look_at(cr.global_position)
			await wait(0.4)
			cam.global_position = cr.global_position + Vector3(-2.6, 0.9, 2.2)
			cam.look_at(cr.global_position)
			await wait_frames(2)
			await shot("ray" if k == SeaCreature.Kind.RAY else "turtle")

	# --- производительность ---
	cam.global_position = Vector3(spot.x, fy + 1.6, spot.z)
	await wait(0.5)
	var t1 := Time.get_ticks_usec()
	for i in 30:
		sea._physics_process(1.0 / 60.0)
	var ms_sea := float(Time.get_ticks_usec() - t1) / 30000.0
	t1 = Time.get_ticks_usec()
	for i in 30:
		life._physics_process(1.0 / 60.0)
	var ms_life := float(Time.get_ticks_usec() - t1) / 30000.0
	print("[test] шаг моря %.2f мс, жизни %.2f мс" % [ms_sea, ms_life])
	check(ms_sea < 6.0 and ms_life < 4.0, "обновление: море %.2f мс, жизнь %.2f мс (%d акул, %d обитателей)" % [ms_sea, ms_life, sea.sharks.size(), life.creatures.size()])
	var tris := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	print("[test] кадр у рифа: %d треуг., %d вызовов" % [tris, calls])
	sea.queue_free()
	await wait(0.5)
