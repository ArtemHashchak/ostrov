## test-timeout: 1800
extends TestCase
## test-class: render
## Агент O (v5.2): дальние острова у края «Дальности видимости» — раньше призрачные белёсые
## скалы и висящие над ними кроны-«снимки»; теперь растворяются дизером (view_fade).
## Кадры «до» (OSTROVA_NO_VIEWFADE) и «после»: /mnt/user-data/outputs/v52_O_farfade_{before,after}_<vd>.png

func _init() -> void:
	OS.set_environment("OSTROVA_GEN", "5")
	scene_path = "res://scenes/world/world_view.tscn"
	timeout_sec = 1750.0

var cam: Camera3D
var w: World

func run() -> void:
	await wait(2.0)
	w = get_tree().get_first_node_in_group(&"world") as World
	if w == null or not w.is_ready:
		check(false, "мир готов")
		return
	var fl := Flora.new()
	w.get_parent().add_child(fl)
	if ResourceLoader.exists("res://scenes/sea/sea.tscn"):
		w.get_parent().add_child((load("res://scenes/sea/sea.tscn") as PackedScene).instantiate())
	if not fl.populated:
		await fl.flora_ready
	w.set_weather(&"clear", true)
	if w.has_method(&"set_time_paused"):
		w.set_time_paused(true)
	w.set_time_of_day(11.0)
	cam = Camera3D.new()
	cam.far = 8000.0
	cam.fov = 60.0
	w.add_child(cam)
	cam.current = true
	for pl in get_tree().get_nodes_in_group(&"player"):
		(pl as Node).process_mode = Node.PROCESS_MODE_DISABLED
		(pl as Node3D).global_position = Vector3(0, -500, 0)
	for vd in [1000.0, 1800.0]:
		Settings.view_distance = vd
		if Settings.has_method(&"apply_view"):
			Settings.call(&"apply_view")
		var pick := _pick(vd)
		if pick.is_empty():
			print("[O] нет пары островов для vd=%d" % int(vd))
			continue
		var eye: Vector3 = pick.eye
		var look: Vector3 = pick.look
		print("[O] vd=%d: до острова %.0f м, высота %.0f м" % [int(vd), Vector2(eye.x, eye.z).distance_to(Vector2(look.x, look.z)), look.y])
		OS.set_environment("OSTROVA_NO_VIEWFADE", "1")
		await _view(eye, look, "farfade_before_%d" % int(vd))
		OS.set_environment("OSTROVA_NO_VIEWFADE", "")
		await _view(eye, look, "farfade_after_%d" % int(vd))

## Камера на берегу одного острова, взгляд на высокий остров на 0,8–1,02 vd.
func _pick(vd: float) -> Dictionary:
	var a := w.arch as ArchipelagoV5
	var best := {}
	var bscore := -INF
	for A in a.islands:
		for B in a.islands:
			if A == B:
				continue
			var cb: Vector2 = B.center
			var hb := 0.0
			for k in 24:
				var q := cb + Vector2.from_angle(k * TAU / 24.0) * float(B.radius) * 0.4
				hb = maxf(hb, w.height_at(q.x, q.y))
			hb = maxf(hb, w.height_at(cb.x, cb.y))
			if hb < 12.0:
				continue
			var ca: Vector2 = A.center
			var dir := (cb - ca).normalized()
			# точка берега A в сторону B
			var e := ca
			for s in 200:
				var q := ca + dir * (s * 2.0)
				if w.height_at(q.x, q.y) < 1.0:
					break
				e = q
			var d := e.distance_to(cb)
			if d < vd * 0.8 or d > vd * 1.02:
				continue
			var score := hb - absf(d - vd * 0.92) * 0.05
			if score > bscore:
				bscore = score
				best = {"eye": Vector3(e.x, maxf(w.height_at(e.x, e.y), w.water_level()) + 2.0, e.y), "look": Vector3(cb.x, hb * 0.5, cb.y)}
	return best

func _view(pos: Vector3, look: Vector3, nm: String) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	w.terrain.focus_override = [pos] as Array[Vector3]
	await wait(4.0)
	await wait_frames(4)
	var img := get_viewport().get_texture().get_image()
	if img and not img.is_empty():
		img.save_png("/mnt/user-data/outputs/v52_O_%s.png" % nm)
		print("[shot] v52_O_%s.png" % nm)
	shot(nm)
