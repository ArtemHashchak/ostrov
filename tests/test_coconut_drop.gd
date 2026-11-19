extends TestCase
## Кокосы не «убегают»: падение с кроны медленное, на песке втыкаются и замирают,
## на земле прокатываются ≤ ~2 м, на камне чуть дальше, в воде плавают.

func _init() -> void:
	scene_path = "res://scenes/world/world_view.tscn"
	timeout_sec = 1800.0

var w: World
var cam: Camera3D

func _find(biome: StringName, rng: RandomNumberGenerator, need_flat: bool = false) -> Vector3:
	for I in w.islands():
		var c: Vector2 = I.center
		var R: float = I.radius
		for i in 400:
			var a := rng.randf() * TAU
			var r := rng.randf_range(0.2, 1.25) * R
			var x := c.x + cos(a) * r
			var z := c.y + sin(a) * r
			if w.biome_at(x, z) != biome:
				continue
			if need_flat and w.normal_at(x, z).y < 0.9:
				continue
			if biome == &"water":
				if w.height_at(x, z) > w.water_level() - 1.5 or w.lake_level_at(x, z) > -INF:
					continue
			else:
				# окрестность 3 м того же типа — чтобы прокатка не уводила в другой биом
				var ok := true
				for k in 6:
					var b := TAU * k / 6.0
					if w.biome_at(x + cos(b) * 2.5, z + sin(b) * 2.5) != biome:
						ok = false
						break
				if not ok:
					continue
			return Vector3(x, w.height_at(x, z), z)
	return Vector3.INF

func _drop(at: Vector3, n: int, rng: RandomNumberGenerator) -> Array[FloraPickup]:
	var out: Array[FloraPickup] = []
	for i in n:
		var p := FloraPickup.make_coconut()
		scene.add_child(p)
		p.global_position = at + Vector3(rng.randf_range(-0.4, 0.4), 9.0 + rng.randf() * 2.0, rng.randf_range(-0.4, 0.4))
		p.debug = at.y < 0.0
		p.freeze = false
		# заведомо «как раньше»: толчок до 1.4 м/с в сторону
		p.linear_velocity = Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * 1.4
		out.append(p)
	return out

func _check_group(name: String, at: Vector3, nuts: Array[FloraPickup], max_dist: float, expect_mode: int) -> void:
	var worst := 0.0
	var all_mode := true
	var reach := true
	for p in nuts:
		if not is_instance_valid(p):
			continue
		var d := Vector2(p.global_position.x - at.x, p.global_position.z - at.z).length()
		worst = maxf(worst, d)
		if p.mode != expect_mode:
			all_mode = false
		if expect_mode == FloraPickup.REST:
			var g := w.height_at(p.global_position.x, p.global_position.z)
			if p.global_position.y > g + 0.4 or not p.freeze:
				reach = false
	print("[test] %s: худшее смещение %.2f м, режимы %s" % [name, worst, str(nuts.map(func(q): return q.mode))])
	check(all_mode, "%s: все кокосы в нужном состоянии (%d)" % [name, expect_mode])
	check(worst <= max_dist, "%s: смещение %.2f ≤ %.1f м" % [name, worst, max_dist])
	if expect_mode == FloraPickup.REST:
		check(reach, "%s: лежат на земле и заморожены (можно подобрать)" % name)

func run() -> void:
	Engine.max_physics_steps_per_frame = 40
	await wait(1.0)
	w = get_tree().get_first_node_in_group(&"world") as World
	check(w != null and w.is_ready, "мир готов")
	if w == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	cam = Camera3D.new()
	scene.add_child(cam)
	cam.fov = 60.0
	cam.make_current()

	var sand := _find(&"beach", rng, true)
	var soil := _find(&"meadow", rng, true)
	if soil == Vector3.INF:
		soil = _find(&"jungle", rng, true)
	var rock := _find(&"rocky", rng)
	var sea := _find(&"water", rng)
	check(sand != Vector3.INF and soil != Vector3.INF, "нашлись песок и земля")

	var groups := {}
	if sand != Vector3.INF:
		groups["песок"] = [sand, _drop(sand, 5, rng), 2.0, FloraPickup.REST]
	if soil != Vector3.INF:
		groups["земля"] = [soil, _drop(soil, 5, rng), 3.6, FloraPickup.REST]
	if rock != Vector3.INF:
		groups["камень"] = [rock, _drop(rock, 4, rng), 5.0, FloraPickup.REST]
	if sea != Vector3.INF:
		groups["вода"] = [sea, _drop(sea, 3, rng), 3.5, FloraPickup.FLOAT]
	# ждём, пока всё упадёт и успокоится (в игровом времени)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 240000:
		await wait(1.0)
		var busy := false
		for k in groups:
			for p in groups[k][1]:
				if is_instance_valid(p) and (p.mode == FloraPickup.FALL or p.mode == FloraPickup.ROLL):
					busy = true
		if not busy:
			break
	await wait(2.0)
	for k in groups:
		var G: Array = groups[k]
		_check_group(k, G[0], G[1], G[2], G[3])
	# песок: воткнулся (ниже центра шара над землёй)
	if groups.has("песок"):
		var sunk := 0
		for p in groups["песок"][1]:
			var g := w.height_at(p.global_position.x, p.global_position.z)
			if p.global_position.y < g + p._r - 0.02:
				sunk += 1
		check(sunk >= 4, "песок: кокосы воткнулись (%d из 5)" % sunk)
		cam.global_position = sand + Vector3(2.2, 1.6, 2.2)
		cam.look_at(sand + Vector3(0, 0.1, 0))
		await wait(0.8)
		await shot("01_sand")
	if groups.has("земля"):
		cam.global_position = soil + Vector3(2.5, 1.8, 2.5)
		cam.look_at(soil + Vector3(0, 0.1, 0))
		await wait(0.8)
		await shot("02_soil")
	if groups.has("вода"):
		var p0: FloraPickup = groups["вода"][1][0]
		var wh := w.wave_height(p0.global_position.x, p0.global_position.z)
		check(absf(p0.global_position.y - (wh - p0._r * 0.35)) < 0.2, "вода: кокос на поверхности (%.2f vs %.2f)" % [p0.global_position.y, wh])
		cam.global_position = p0.global_position + Vector3(2.5, 1.4, 2.5)
		cam.look_at(p0.global_position)
		await wait(0.8)
		await shot("03_water")
	# подбор: игрока нет в world_view — проверяем интерфейс подбора
	var any: FloraPickup = groups["песок"][1][0] if groups.has("песок") else null
	if any:
		check(any.item_id == &"coconut" and any.has_method(&"interact"), "кокос подбирается (interact)")
