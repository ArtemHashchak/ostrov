extends TestCase
## Пак пользователя №2: пляжный песок (Грунт/Песок) + следы на песке (SandTracks),
## ящерица (Ящерицы/lizard_model.blend) и летучая мышь (Птицы/Flying Bat) в мире.
## SECTIONS=sand,tracks,lizard,bat (переменная окружения PACK2_SECTIONS), по умолчанию всё.

func _init() -> void:
	scene_path = "res://scenes/world/world_view.tscn"
	timeout_sec = 3000.0

var w: World
var cam: Camera3D

func _sections() -> PackedStringArray:
	var s := OS.get_environment("PACK2_SECTIONS")
	if s == "":
		return PackedStringArray(["sand", "tracks", "lizard", "bat"])
	return s.split(",")

func _beach_spot(min_len := 6.0) -> Dictionary:
	# точка сухого пляжа + направление к воде
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for I in w.islands():
		var c: Vector2 = I.center
		var R: float = I.radius
		for i in 600:
			var a := rng.randf() * TAU
			var r := rng.randf_range(0.5, 1.3) * R
			var p := c + Vector2(cos(a), sin(a)) * r
			if w.biome_at(p.x, p.y) != &"beach":
				continue
			if w.normal_at(p.x, p.y).y < 0.95:
				continue
			# к воде: вдоль радиуса наружу
			var d := (p - c).normalized()
			var ok := true
			for k in range(1, int(min_len)):
				var q := p - d * k
				if w.biome_at(q.x, q.y) != &"beach":
					ok = false
					break
			if not ok:
				continue
			return {"p": p, "to_sea": d}
	return {}

func _place_cam(from: Vector3, look: Vector3) -> void:
	cam.global_position = from
	cam.look_at(look, Vector3.UP)
	await wait_frames(4)

func run() -> void:
	w = scene.get_node("World") as World if scene.has_node("World") else get_tree().get_first_node_in_group(&"world") as World
	while w == null or not w.is_ready:
		await wait(0.5)
		w = get_tree().get_first_node_in_group(&"world") as World
	cam = get_viewport().get_camera_3d()
	if cam == null:
		cam = Camera3D.new()
		scene.add_child(cam)
	cam.current = true
	cam.far = 3000.0
	if w.has_method("set_time_of_day"):
		w.set_time_of_day(10.5)
	if w.has_method("set_time_paused"):
		w.set_time_paused(true)
	if w.has_method("set_weather"):
		w.set_weather(&"clear")
	await wait(2.0)
	var sec := _sections()
	var spot := _beach_spot()
	check(not spot.is_empty(), "нашёлся ровный пляж")
	if spot.is_empty():
		return
	var p: Vector2 = spot.p
	var d: Vector2 = spot.to_sea
	var gy := w.height_at(p.x, p.y)
	var eye := Vector3(p.x, gy + 1.65, p.y)
	var look := Vector3(p.x + d.x * 8.0, gy - 0.4, p.y + d.y * 8.0)
	var mat := w.terrain_material

	if sec.has("sand"):
		check(float(mat.get_shader_parameter(&"use_beach_sand")) > 0.5, "песок пользователя включён в материале рельефа")
		await _place_cam(eye, look)
		await wait(1.0)
		mat.set_shader_parameter(&"use_beach_sand", 0.0)
		await wait_frames(3)
		await shot("sand_before_eye")
		mat.set_shader_parameter(&"use_beach_sand", 1.0)
		await wait_frames(3)
		await shot("sand_after_eye")
		# сверху-вниз крупно (зерно, рябь, граница мокрого)
		var close_from := Vector3(p.x - d.x * 1.5, gy + 1.6, p.y - d.y * 1.5)
		await _place_cam(close_from, Vector3(p.x + d.x * 0.6, gy, p.y + d.y * 0.6))
		await shot("sand_after_close")
		# общий план: пляж-джунгли-скала
		await _place_cam(Vector3(p.x + d.x * 30.0, gy + 14.0, p.y + d.y * 30.0), Vector3(p.x - d.x * 20.0, gy + 2.0, p.y - d.y * 20.0))
		await shot("sand_after_overview")
		mat.set_shader_parameter(&"use_beach_sand", 0.0)
		await wait_frames(3)
		await shot("sand_before_overview")
		mat.set_shader_parameter(&"use_beach_sand", 1.0)
		# дождь: мокрый песок
		if w.has_method("set_weather"):
			w.set_weather(&"rain")
			RenderingServer.global_shader_parameter_set(&"weather_wetness", 0.8)
			await _place_cam(eye, look)
			await wait(1.0)
			await shot("sand_after_rain")
			w.set_weather(&"clear")
			RenderingServer.global_shader_parameter_set(&"weather_wetness", 0.0)

	if sec.has("tracks"):
		var st := get_node_or_null("/root/SandTracks")
		check(st != null, "автозагрузка SandTracks есть")
		if st:
			await _place_cam(eye, look)
			await wait(0.5)
			# цепочка шагов от сухого пляжа к воде и обратно вдоль берега
			var side := 0
			var q := p - d * 3.0
			for i in 18:
				var g := Vector3(q.x, w.height_at(q.x, q.y), q.y)
				st.stamp_foot(g, d, side)
				side = 1 - side
				q += d * 0.72
			var perp := Vector2(-d.y, d.x)
			q = p + perp * 1.6
			for i in 12:
				st.stamp_foot(Vector3(q.x, 0, q.y), perp, side)
				side = 1 - side
				q += perp * 0.72
			await wait(0.4)
			check(st.stamps_total >= 25, "следы проставлены (%d)" % st.stamps_total)
			var hi := Vector3(p.x - d.x * 1.0, gy + 2.6, p.y - d.y * 1.0)
			await _place_cam(hi, Vector3(p.x + d.x * 4.0, gy, p.y + d.y * 4.0))
			await shot("tracks_fresh")
			await _place_cam(Vector3(p.x + perp.x * 5.5, gy + 1.7, p.y + perp.y * 5.5), Vector3(p.x, gy, p.y))
			await shot("tracks_side")
			# крупно: отпечатки у ног (как видит игрок, глядя вниз)
			var cq := p - d * 1.6
			await _place_cam(Vector3(cq.x + perp.x * 0.9, gy + 1.25, cq.y + perp.y * 0.9), Vector3(cq.x + d.x * 0.9, gy, cq.y + d.y * 0.9))
			await shot("tracks_close")
			# игрок-«ходок»: персонаж в группе characters идёт по пляжу — следы ставятся сами
			var walker := Node3D.new()
			walker.add_to_group(&"characters")
			scene.add_child(walker)
			var wq := p - perp * 2.0
			walker.global_position = Vector3(wq.x, w.height_at(wq.x, wq.y) + 0.9, wq.y)
			await wait_frames(2)
			var before: int = st.stamps_total
			for i in 40:
				wq += -perp * 0.25
				walker.global_position = Vector3(wq.x, w.height_at(wq.x, wq.y) + 0.9, wq.y)
				await wait_frames(1)
			check(st.stamps_total > before + 8, "идущий персонаж оставляет следы (%d)" % (st.stamps_total - before))
			walker.queue_free()
			# размыв: у воды следы исчезают за секунды, выше по пляжу — остаются
			var wet_pt := p + d * 9.0
			var dry_pt := p - d * 3.0
			# ставим по отпечатку точно в контрольные точки
			st.stamp_foot(Vector3(dry_pt.x, 0, dry_pt.y), d, 0)
			st.stamp_foot(Vector3(wet_pt.x, 0, wet_pt.y), d, 0)
			var dry0: float = st.depth_at(dry_pt.x, dry_pt.y)
			var wet0: float = st.depth_at(wet_pt.x, wet_pt.y)
			await wait(6.0)
			var dry1: float = st.depth_at(dry_pt.x, dry_pt.y)
			var wet1: float = st.depth_at(wet_pt.x, wet_pt.y)
			print("[test] следы: сухо %.2f→%.2f, у воды %.2f→%.2f (h воды-точки %.2f, уровень %.2f)" % [dry0, dry1, wet0, wet1, w.height_at(wet_pt.x, wet_pt.y), w.water_level()])
			check(dry0 > 0.9 and dry1 > 0.9, "на сухом песке следы держатся")
			if w.height_at(wet_pt.x, wet_pt.y) < w.water_level() + 0.3:
				check(wet1 < wet0 * 0.5, "у кромки волна размывает следы")
			await _place_cam(hi, Vector3(p.x + d.x * 4.0, gy, p.y + d.y * 4.0))
			await shot("tracks_after_wash")

	if sec.has("lizard"):
		await _lizard_section(p, d, gy)
	if sec.has("bat"):
		await _bat_section(p, d, gy)

func _fauna() -> Node:
	var f := get_tree().get_first_node_in_group(&"fauna")
	if f == null:
		var fa := Fauna.new()
		fa.auto_populate = false
		scene.add_child(fa)
		await wait(0.5)
		f = fa
	return f

func _lizard_section(p: Vector2, d: Vector2, gy: float) -> void:
	if not ClassDB.class_exists("Node") or not ResourceLoader.exists("res://assets/user_pack/animals/lizard/lizard_user.glb"):
		check(false, "нет модели ящерицы пользователя")
		return
	var fauna = await _fauna()
	var at := Vector3(p.x - d.x * 2.0, gy, p.y - d.y * 2.0)
	for sp in [&"iguana", &"monitor"]:
		var a: Node3D = null
		if fauna and fauna.has_method("spawn"):
			a = fauna.spawn(sp, at)
		check(a != null, "%s появилась" % sp)
		if a == null:
			continue
		if a.has_method("set_growth"):
			a.set_growth(1.0)
		await wait(0.5)
		var mdl := a.find_child("UserLizard", true, false)
		check(mdl != null, "%s — модель пользователя" % sp)
		var right := Vector3(-d.y, 0, d.x)
		# покой: сбоку и спереди
		await _place_cam(a.global_position + right * 2.0 + Vector3(0, 0.8, 0), a.global_position + Vector3(0, 0.15, 0))
		await shot("%s_rest_side" % sp)
		# идёт вдоль пляжа: серия кадров походки
		var tgt: Vector3 = a.global_position + right * 8.0
		a.set("move_to", tgt)
		a.call("_set_state", &"wander")
		for i in 8:
			await wait(0.22)
			var ap: Vector3 = a.global_position
			await _place_cam(ap - Vector3(d.x, 0, d.y) * 2.3 + Vector3(0, 0.9, 0), ap + Vector3(0, 0.15, 0))
			await shot("%s_walk_%d" % [sp, i])
		check(a.global_position.distance_to(tgt) < 7.5, "%s прошла к цели" % sp)
		a.queue_free()
		await wait(0.2)
		at += right * 3.0

func _bat_section(p: Vector2, d: Vector2, gy: float) -> void:
	if not ResourceLoader.exists("res://assets/user_pack/animals/bat/bat_user.glb"):
		check(false, "нет модели летучей мыши пользователя")
		return
	var fauna = await _fauna()
	if fauna and fauna.has_method("spawn"):
		var at := Vector3(p.x, gy + 4.0, p.y)
		var b: Node3D = fauna.spawn(&"bat", at)
		check(b != null, "летучая мышь появилась")
		if b and b.has_method("set_growth"):
			b.set_growth(1.0)
		if b:
			var mdl := b.find_child("UserBat", true, false)
			check(mdl != null, "летучая мышь — модель пользователя")
			if w.has_method("set_time_of_day"):
				w.set_time_of_day(16.5)
			for i in 6:
				await _place_cam(b.global_position + Vector3(1.2, 0.35, 0.8), b.global_position)
				await shot("bat_seq_%d" % i)
				await wait(0.12)
