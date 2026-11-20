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
		return PackedStringArray(["sand", "tracks", "prints", "moss", "rocks", "lizard", "bat"])
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

	if sec.has("prints"):
		await _prints_section(p, d, gy)
	if sec.has("moss"):
		await _moss_section()
	if sec.has("rocks"):
		await _rocks_section(p, d, gy)
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
		# покой: строго сбоку от зверя (по его собственному боку) и три четверти спереди
		var side: Vector3 = (a.global_transform.basis.x * Vector3(1, 0, 1)).normalized()
		var fwd: Vector3 = (-a.global_transform.basis.z * Vector3(1, 0, 1)).normalized()
		await _place_cam(a.global_position + side * 1.6 + Vector3(0, 0.35, 0), a.global_position + Vector3(0, 0.08, 0))
		await shot("%s_rest_side" % sp)
		await _place_cam(a.global_position + (fwd + side * 0.8).normalized() * 1.4 + Vector3(0, 0.3, 0), a.global_position + Vector3(0, 0.08, 0))
		await shot("%s_rest_front34" % sp)
		_check_feet(a, sp, "покой")
		# идёт вдоль пляжа: серия кадров походки
		var tgt: Vector3 = a.global_position + right * 8.0
		a.set("move_to", tgt)
		a.call("_set_state", &"wander")
		for i in 8:
			await wait(0.22)
			var ap: Vector3 = a.global_position
			await _place_cam(ap - Vector3(d.x, 0, d.y) * 2.3 + Vector3(0, 0.9, 0), ap + Vector3(0, 0.15, 0))
			await shot("%s_walk_%d" % [sp, i])
			if i == 4:
				_check_feet(a, sp, "ходьба", true)
		check(a.global_position.distance_to(tgt) < 7.5, "%s прошла к цели" % sp)
		a.queue_free()
		await wait(0.2)
		at += right * 3.0

## Стопы обеих сторон — на земле (IK), брюхо низко. walking: опорные стопы (две из четырёх в переносе).
var _k_ref := 0.0

func _check_feet(a: Node3D, sp: StringName, what: String, walking := false) -> void:
	var sk := a.find_child("Skeleton3D", true, false) as Skeleton3D
	if sk == null:
		for c in a.find_children("*", "Skeleton3D", true, false):
			sk = c
	if sk == null:
		check(false, "%s: скелет не найден" % sp)
		return
	var hs: Array = []
	for bn in ["hand_front01.l", "hand_front01.r", "hand_back1.l", "hand_back1.r"]:
		var bi := sk.find_bone(bn)
		if bi < 0:
			continue
		var g := sk.global_transform * sk.get_bone_global_pose(bi)
		hs.append(g.origin.y - w.height_at(g.origin.x, g.origin.z))
	var bi2 := sk.find_bone("Body_control02")
	var belly := 0.0
	if bi2 >= 0:
		var g2 := sk.global_transform * sk.get_bone_global_pose(bi2)
		belly = g2.origin.y - w.height_at(g2.origin.x, g2.origin.z)
	print("[test] %s %s: стопы над землёй %s, ось туловища %.3f м" % [sp, what, str(hs.map(func(v): return snappedf(v, 0.005))), belly])
	# высота кости запястья над подошвой растёт с размером зверя: пороги масштабируются
	# по масштабу модели относительно игуаны (варан крупнее ≈ в 1.4 раза)
	var body := a.find_child("Body", true, false) as Node3D
	var ks: float = body.scale.x if body else 1.0
	if sp == &"iguana" or _k_ref <= 0.0:
		_k_ref = ks if sp == &"iguana" else (_k_ref if _k_ref > 0.0 else ks)
	var kf: float = maxf(1.0, ks / maxf(_k_ref, 1e-5))
	if hs.size() == 4:
		var sorted_h: Array = hs.duplicate()
		sorted_h.sort()
		var planted: float = sorted_h[1] if walking else sorted_h[3]
		check(absf(sorted_h[0]) < 0.06 * kf and planted < 0.07 * kf, "%s %s: стопы обеих сторон на земле" % [sp, what])
		check(absf(float(hs[0]) - float(hs[1])) < 0.05 or walking, "%s %s: левая и правая стороны симметричны" % [sp, what])

func _bat_section(p: Vector2, d: Vector2, gy: float) -> void:
	if not ResourceLoader.exists("res://assets/user_pack/animals/bat/bat_user.glb"):
		check(false, "нет модели летучей мыши пользователя")
		return
	var fauna = await _fauna()
	if fauna == null or not fauna.has_method("spawn"):
		return
	# --- полёт: днём летучих мышей не видно (висят) — для съёмки включаем «ночной» режим при дневном свете
	fauna.force_night_birds = true
	if w.has_method("set_time_of_day"):
		w.set_time_of_day(15.0)
	# вглубь острова от пляжа (−d — к центру), над сушей
	var q := p - d * 14.0
	var gq := w.height_at(q.x, q.y)
	var b: Node3D = fauna.spawn(&"bat", Vector3(q.x, maxf(gq, w.water_level()) + 3.5, q.y))
	check(b != null, "летучая мышь появилась")
	if b == null:
		return
	if b.has_method("set_growth"):
		b.set_growth(1.0)
	check(b.find_child("UserBat", true, false) != null, "летучая мышь — модель пользователя")
	await wait(0.6)
	# камера ведёт мышь каждый кадр (иначе быстрая мышь уходит из кадра между установкой и снимком)
	var under := [0]
	var ang := [0.0]
	var follow := func() -> void:
		if not is_instance_valid(b):
			return
		var bp := b.global_position
		var c := _safe_cam(bp + Vector3(1.4, 0.3, 0.0).rotated(Vector3.UP, ang[0]))
		if c.y < w.water_level() + 0.3:
			under[0] += 1
		cam.global_position = c
		cam.look_at(bp, Vector3.UP)
	get_tree().process_frame.connect(follow)
	for i in 10:
		ang[0] = i * 0.35
		await wait_frames(2)
		await shot("bat_fly_%d" % i)
		await wait(0.08)
	get_tree().process_frame.disconnect(follow)
	var under_n: int = under[0]
	check(under_n == 0, "камера над водой во всех кадрах полёта")
	# --- днёвка: обычный режим, день — стая висит вниз головой под кроной
	fauna.force_night_birds = false
	if w.has_method("set_time_of_day"):
		w.set_time_of_day(12.0)
	await wait(1.2)
	print("[test] летучая мышь днём: state=%s visible=%s pos=%s" % [b.get("state"), b.visible, b.global_position])
	if b.get("state") == &"roost" and b.visible:
		check(true, "днём висит вниз головой (roost)")
		# камера на высоте мыши, с той стороны, где склон ниже (иначе объектив в траве)
		var bp: Vector3 = b.global_position
		var best := Vector3.ZERO
		var best_clear := -INF
		for k in 16:
			var dd := Vector3(1.3, 0.0, 0.0).rotated(Vector3.UP, k * TAU / 16.0)
			var c := bp + dd + Vector3(0, 0.1, 0)
			var clear := c.y - w.height_at(c.x, c.z)
			if clear > best_clear:
				best_clear = clear
				best = dd
		print("[test] днёвка: высота мыши над землёй %.2f м, просвет камеры %.2f м" % [bp.y - w.height_at(bp.x, bp.z), best_clear])
		for i in 5:
			bp = b.global_position
			var c := _safe_cam(bp + best.rotated(Vector3.UP, (i - 2) * 0.25) + Vector3(0, 0.1, 0))
			await _place_cam(c, bp)
			await shot("bat_roost_%d" % i)
			await wait(0.3)
	else:
		print("[test] деревьев для днёвки нет — кадры висения пропущены")

## Точка камеры не ниже рельефа и воды.
func _safe_cam(c: Vector3) -> Vector3:
	c.y = maxf(c.y, maxf(w.height_at(c.x, c.z) + 0.4, w.water_level() + 0.6))
	return c


## Следы разных видов рядом: человек, кабан, игуана, варан, крокодил, черепаха, обезьяна —
## дорожки поперёк пляжа; кадры с высоты глаз (1.65 м), вблизи и скользящим взглядом.
func _prints_section(p: Vector2, d: Vector2, gy: float) -> void:
	var st := get_node_or_null("/root/SandTracks")
	if st == null:
		return
	st.clear()
	var perp := Vector2(-d.y, d.x)
	var kinds := [&"human", &"boar", &"iguana", &"monitor", &"croc", &"turtle", &"monkey"]
	var x0 := p - perp * 4.2
	for i in kinds.size():
		var a := x0 + perp * (i * 1.4) - d * 2.5
		var b := a + d * 6.0
		st.walk_line(kinds[i], Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y))
	await wait(0.5)
	check(st.prints.size() > 60, "дорожки следов всех видов (%d отпечатков)" % st.prints.size())
	var types := {}
	for q: Array in st.prints:
		types[int(q[7])] = true
	check(types.size() >= 6, "штампы всех типов (%d)" % types.size())
	# как видит игрок стоя: 1.65 м, взгляд на 3–6 м вперёд
	var e := p - d * 5.5 + perp * 0.3
	await _place_cam(Vector3(e.x, gy + 1.65, e.y), Vector3(p.x, gy, p.y))
	await wait(0.3)
	await shot("prints_eye")
	# вблизи, глядя под ноги, на людскую и кабанью дорожки
	var h := x0 + perp * 0.7 - d * 1.2
	await _place_cam(Vector3(h.x - d.x * 1.0, gy + 1.2, h.y - d.y * 1.0), Vector3(h.x + d.x * 0.6, gy, h.y + d.y * 0.6))
	await shot("prints_close_human_boar")
	var l := x0 + perp * 3.5 - d * 1.0
	await _place_cam(Vector3(l.x - d.x * 1.0, gy + 1.1, l.y - d.y * 1.0), Vector3(l.x + d.x * 0.5, gy, l.y + d.y * 0.5))
	await shot("prints_close_lizards")
	var t := x0 + perp * 7.7 - d * 1.0
	await _place_cam(Vector3(t.x - d.x * 1.0, gy + 1.2, t.y - d.y * 1.0), Vector3(t.x + d.x * 0.6, gy, t.y + d.y * 0.6))
	await shot("prints_close_turtle_monkey")
	# скользящий взгляд — проверка глубины (параллакс) и валика
	var g := p + perp * 6.0 + d * 0.5
	await _place_cam(Vector3(g.x, gy + 0.5, g.y), Vector3(p.x - perp.x * 2.0, gy, p.y - perp.y * 2.0))
	await shot("prints_grazing")
	# высоко сверху — читаемость рисунка дорожек
	await _place_cam(Vector3(p.x - d.x * 0.5, gy + 6.0, p.y - d.y * 0.5 + 0.01), Vector3(p.x, gy, p.y))
	await shot("prints_top")


## Мшистая земля в подлеске: до/после (use_mossy), с высоты глаз и вблизи, в дождь.
func _moss_section() -> void:
	var mat := w.terrain_material
	check(float(mat.get_shader_parameter(&"use_mossy")) > 0.5, "мшистая земля включена в материале рельефа")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var spot := Vector2.INF
	var dir := Vector2.ZERO
	for I in w.islands():
		for i in 800:
			var a := rng.randf() * TAU
			var q: Vector2 = I.center + Vector2(cos(a), sin(a)) * rng.randf_range(0.1, 0.8) * float(I.radius)
			if w.biome_at(q.x, q.y) != &"jungle" or w.normal_at(q.x, q.y).y < 0.95:
				continue
			var dd := Vector2(cos(a + 1.3), sin(a + 1.3))
			var ok := true
			for k in range(1, 7):
				var r := q + dd * k
				if w.biome_at(r.x, r.y) != &"jungle":
					ok = false
					break
			if ok:
				spot = q
				dir = dd
				break
		if spot != Vector2.INF:
			break
	check(spot != Vector2.INF, "нашёлся ровный подлесок")
	if spot == Vector2.INF:
		return
	var gy := w.height_at(spot.x, spot.y)
	var eye := Vector3(spot.x, gy + 1.65, spot.y)
	var look := Vector3(spot.x + dir.x * 6.0, w.height_at(spot.x + dir.x * 6.0, spot.y + dir.y * 6.0), spot.y + dir.y * 6.0)
	await _place_cam(eye, look)
	await wait(0.6)
	mat.set_shader_parameter(&"use_mossy", 0.0)
	await wait_frames(3)
	await shot("moss_before_eye")
	mat.set_shader_parameter(&"use_mossy", 1.0)
	await wait_frames(3)
	await shot("moss_after_eye")
	var c := spot + dir * 1.5
	await _place_cam(Vector3(spot.x, gy + 1.2, spot.y), Vector3(c.x, w.height_at(c.x, c.y), c.y))
	mat.set_shader_parameter(&"use_mossy", 0.0)
	await wait_frames(3)
	await shot("moss_before_close")
	mat.set_shader_parameter(&"use_mossy", 1.0)
	await wait_frames(3)
	await shot("moss_after_close")
	RenderingServer.global_shader_parameter_set(&"weather_wetness", 0.8)
	await wait_frames(3)
	await shot("moss_after_rain")
	RenderingServer.global_shader_parameter_set(&"weather_wetness", 0.0)

## Валуны: ряд форм пака (камень пользователя) рядом с прежними polyhaven, вблизи; валуны рассадки в мире.
func _rocks_section(p: Vector2, d: Vector2, gy: float) -> void:
	check(UserRocks.available(), "валуны пака есть")
	if not UserRocks.available():
		return
	var perp := Vector2(-d.y, d.x)
	var base := p - d * 4.0 - perp * 5.0
	var holder := Node3D.new()
	scene.add_child(holder)
	var old := ["boulder_01", "boulder_02", "rock_07", "rock_moss_set_01_rock03", "rock_moss_set_02_rock09"]
	for i in UserRocks.SHAPES.size():
		var q := base + perp * (i * 2.0)
		var r := UserRocks.make(i, 1.4)
		holder.add_child(r)
		r.global_position = Vector3(q.x, w.height_at(q.x, q.y) - 0.03, q.y)
		r.rotation.y = i * 1.1
		var lb := Label3D.new()
		lb.text = "%s\n3.6k треуг." % UserRocks.SHAPES[i]
		lb.font_size = 40
		lb.pixel_size = 0.004
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		holder.add_child(lb)
		lb.global_position = r.global_position + Vector3(0, 1.3, 0)
		if i < old.size():
			var q2 := q - d * 2.6
			var op := "res://assets/models/polyhaven/%s.glb" % old[i]
			if ResourceLoader.exists(op):
				var o := (load(op) as PackedScene).instantiate() as Node3D
				holder.add_child(o)
				var bb := AABB()
				for mi in o.find_children("*", "MeshInstance3D", true, false):
					bb = bb.merge((mi as MeshInstance3D).get_aabb())
				o.scale = Vector3.ONE * (1.4 / maxf(bb.get_longest_axis_size(), 0.01))
				o.global_position = Vector3(q2.x, w.height_at(q2.x, q2.y) - 0.03, q2.y)
	await wait(0.4)
	var mid := base + perp * 5.0
	var mgy := w.height_at(mid.x, mid.y)
	await _place_cam(Vector3(mid.x + d.x * 5.5, mgy + 2.4, mid.y + d.y * 5.5), Vector3(mid.x - d.x * 1.2, mgy + 0.3, mid.y - d.y * 1.2))
	await shot("rocks_row")
	for i: int in [0, 1, 3, 4]:
		var q: Vector2 = base + perp * (i * 2.0)
		var rg := w.height_at(q.x, q.y)
		await _place_cam(Vector3(q.x + d.x * 1.9 + perp.x * 0.6, rg + 1.0, q.y + d.y * 1.9 + perp.y * 0.6), Vector3(q.x, rg + 0.35, q.y))
		await shot("rocks_close_%s" % UserRocks.SHAPES[i])
	RenderingServer.global_shader_parameter_set(&"weather_wetness", 0.85)
	await wait_frames(3)
	await _place_cam(Vector3(mid.x + d.x * 5.5, mgy + 2.4, mid.y + d.y * 5.5), Vector3(mid.x - d.x * 1.2, mgy + 0.3, mid.y - d.y * 1.2))
	await shot("rocks_row_rain")
	RenderingServer.global_shader_parameter_set(&"weather_wetness", 0.0)
	holder.queue_free()
	# валуны рассадки (flora → ResourceRock) — формы пака; в world_view рассадки нет — добавляем её
	if get_tree().get_nodes_in_group(&"rocks").is_empty() and get_tree().get_first_node_in_group(&"flora") == null:
		var fl := Flora.new()
		scene.add_child(fl)
		var t1 := Time.get_ticks_msec()
		while get_tree().get_nodes_in_group(&"rocks").is_empty() and Time.get_ticks_msec() - t1 < 90000:
			await wait(1.0)
	var rocks := get_tree().get_nodes_in_group(&"rocks")
	var user := 0
	var any: Node3D = null
	for r in rocks:
		var sp: String = String(r.get("scene_path"))
		if UserRocks.is_user_rock(sp):
			user += 1
			if any == null or (r as Node3D).global_position.distance_to(cam.global_position) < any.global_position.distance_to(cam.global_position):
				any = r
	print("[test] валунов в мире: %d, из них пака: %d" % [rocks.size(), user])
	check(user > 0 and user * 10 >= rocks.size() * 9, "валуны рассадки — формы пака (%d из %d)" % [user, rocks.size()])
	if any:
		var ap := any.global_position
		var dir3 := Vector3(1, 0, 0.4).normalized()
		var cp := _safe_cam(ap + dir3 * 4.0 + Vector3(0, 1.6, 0))
		await _place_cam(cp, ap + Vector3(0, 0.5, 0))
		await wait(0.3)
		await shot("rocks_world")
