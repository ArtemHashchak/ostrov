extends TestCase
## WORLD G1: API высот = коллизия, острова/биомы/спавн, океан, небо, погода.

func _init() -> void:
	scene_path = "res://scenes/world/match.tscn"
	timeout_sec = 1400.0

var cam: Camera3D

func run() -> void:
	await wait(1.5)
	var w := get_tree().get_first_node_in_group(&"world") as World
	check(w != null and w.is_ready, "мир готов")
	if w == null:
		return
	print("[test] постройка мира: %d мс, чанки %s" % [w.build_ms, str(w.terrain.chunk_count())])
	check(w.islands().size() >= 3, "острова: %d" % w.islands().size())
	# 1) высоты API = физика (луч сверху)
	var space := w.get_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var maxerr := 0.0
	var samples := 0
	for k in 400:
		var x := rng.randf_range(w.arch.bounds.position.x + 5.0, w.arch.bounds.end.x - 5.0)
		var z := rng.randf_range(w.arch.bounds.position.y + 5.0, w.arch.bounds.end.y - 5.0)
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 80.0, z), Vector3(x, -60.0, z))
		var hit := space.intersect_ray(q)
		# сравниваем только с коллизией рельефа (деревья/камни/постройки G2 тоже на слое 1)
		var guard := 0
		while not hit.is_empty() and not (hit.collider as Node).is_in_group(&"terrain") and guard < 8:
			q.exclude = q.exclude + [hit.rid]
			hit = space.intersect_ray(q)
			guard += 1
		if hit.is_empty() or not (hit.collider as Node).is_in_group(&"terrain"):
			continue
		var e := absf((hit.position as Vector3).y - w.height_at(x, z))
		maxerr = maxf(maxerr, e)
		samples += 1
	check(samples > 300 and maxerr < 0.02, "высоты API совпадают с коллизией: %d точек, макс. ошибка %.4f м" % [samples, maxerr])
	# 2) острова, биомы, спавн
	var sp0 := w.spawn_point(0)
	var sp1 := w.spawn_point(1)
	check(w.is_land(sp0.x, sp0.z) and sp0.y > 2.0, "спавн 0 на суше: %s" % str(sp0))
	check(w.is_land(sp1.x, sp1.z) and sp1.distance_to(sp0) > 300.0, "спавн 1 на острове соперника: %s" % str(sp1))
	var counts := {}
	for k in 3000:
		var x := 525.0 + rng.randf_range(-130.0, 130.0)
		var z := rng.randf_range(-130.0, 130.0)
		var b := w.biome_at(x, z)
		counts[b] = int(counts.get(b, 0)) + 1
	print("[test] биомы домашнего острова: ", counts)
	for b in [&"beach", &"jungle", &"meadow", &"water"]:
		check(int(counts.get(b, 0)) > 20, "есть биом %s" % b)
	# скалы: архипелаг G2 (25 островов 9 типов) — у домашнего их мало, ищем по всему архипелагу
	var rocky := int(counts.get(&"rocky", 0))
	for k in 6000:
		var x := rng.randf_range(w.arch.bounds.position.x, w.arch.bounds.end.x)
		var z := rng.randf_range(w.arch.bounds.position.y, w.arch.bounds.end.y)
		if w.biome_at(x, z) == &"rocky":
			rocky += 1
	check(rocky > 20, "есть биом rocky (%d)" % rocky)
	check(int(counts.get(&"swamp", 0)) > 3, "есть мангры/болото у лагуны (%d)" % int(counts.get(&"swamp", 0)))
	# проливы 40–100 м и отмели
	var isl := w.islands()
	for r in w.arch.routes.slice(0, 3):
		var a: Dictionary = isl[r.a]
		var b: Dictionary = isl[r.b]
		var ca: Vector2 = a.center
		var cb: Vector2 = b.center
		var dir := (cb - ca).normalized()
		var land_a := 0.0
		var land_b := 0.0
		var t := 0.0
		while t < ca.distance_to(cb):
			var p := ca + dir * t
			if w.arch.height(p.x, p.y) > 0.0 and int(w.arch.island_at(p).island.id) == int(a.id):
				land_a = t
			t += 0.5
		t = ca.distance_to(cb)
		while t > 0.0:
			var p := ca + dir * t
			if w.arch.height(p.x, p.y) > 0.0 and int(w.arch.island_at(p).island.id) == int(b.id):
				land_b = t
			t -= 0.5
		var gap := land_b - land_a
		check(gap > 40.0 and gap < 110.0, "пролив %s↔%s: %.0f м" % [a.name, b.name, gap])
	check(w.islets().size() >= 2 and w.sandbars().size() >= 2, "островки и косы для мостов")
	# 3) вода: прилив, волны, совпадение с CPU
	var l0 := w.water_level()
	w.time_s += w.tide_period * 0.25
	var l1 := w.water_level()
	check(absf(l1 - l0) > 0.3, "прилив меняет уровень: %.2f → %.2f" % [l0, l1])
	w.time_s -= w.tide_period * 0.25
	var wh := w.wave_height(80.0, 190.0)
	check(absf(wh - w.water_level()) < 1.0, "wave_height рядом с уровнем: %.2f" % wh)
	# 4) скриншоты
	cam = Camera3D.new()
	cam.far = 4000.0
	w.add_child(cam)
	cam.make_current()
	var pl := get_tree().get_first_node_in_group(&"player") as Node
	if pl:
		pl.set_process(false)
		pl.set_physics_process(false)
	_hide_ui()
	var b := beach_spot(w, 80.0)
	await _view(b, Vector3(b.x * 0.2, 6.0, b.z * 0.2), "01_beach")
	await _view(b, b + Vector3(60.0, -1.5, 40.0), "01b_beach_sea")
	await _view(Vector3(-40.0, 3.0, 150.0), Vector3(30.0, 0.0, 0.0), "02_shore_island")
	await _view(Vector3(120.0, 260.0, 260.0), Vector3(220.0, 0.0, -40.0), "03_top")
	await _view(Vector3(115.0, 2.2, -10.0), Vector3(225.0, 1.0, -70.0), "04_ocean_strait")
	await _view(Vector3(40.0, 14.0, 60.0), Vector3(-20.0, 8.0, -10.0), "05_jungle_hill")

func _view(from: Vector3, to: Vector3, name: String) -> void:
	cam.global_position = from
	cam.look_at(to)
	await wait(0.8)
	await shot(name)

## Точка на сухом пляже: идём от центра острова наружу до h < 1.0.
static func beach_spot(w: World, ang_deg: float) -> Vector3:
	var d := Vector2.from_angle(deg_to_rad(ang_deg))
	var r := 20.0
	while r < 200.0 and w.height_at(d.x * r, d.y * r) > 1.1:
		r += 0.5
	r -= 4.0
	return Vector3(d.x * r, w.height_at(d.x * r, d.y * r) + 1.7, d.y * r)

func _hide_ui() -> void:
	for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
