## test-timeout: 2000
extends TestCase
## test-class: render
## Снимки агента O (v5.2): новые растения пользователя в мире v5 — лианы на деревьях и между
## ними, страусник и стрелиция в подлеске, ховея/Kingsville на опушке; пляж с водорослями
## на отливе. Каждый кадр — отдельный файл /mnt/user-data/outputs/v52_O_<имя>.png.

func _init() -> void:
	OS.set_environment("OSTROVA_GEN", "5")
	scene_path = "res://scenes/world/world_view.tscn"
	timeout_sec = 1950.0

var cam: Camera3D
var w: World
var fl: Flora

func run() -> void:
	await wait(2.0)
	w = get_tree().get_first_node_in_group(&"world") as World
	if w == null or not w.is_ready:
		check(false, "мир готов")
		return
	fl = Flora.new()
	w.get_parent().add_child(fl)
	if not fl.populated:
		await fl.flora_ready
	w.set_weather(&"clear", true)
	if w.has_method(&"set_time_paused"):
		w.set_time_paused(true)
	w.set_time_of_day(10.5)
	cam = Camera3D.new()
	cam.far = 3000.0
	cam.fov = 70.0
	w.add_child(cam)
	cam.current = true
	for pl in get_tree().get_nodes_in_group(&"player"):
		(pl as Node).process_mode = Node.PROCESS_MODE_DISABLED
		(pl as Node3D).global_position = Vector3(0, -500, 0)
	# 1) свисающая лиана на дереве джунглей
	var hang := _first_of(["flora_liana_hang_curtain_05", "flora_liana_hang_ivy_06", "flora_liana_climb_07"], true)
	if hang != Vector3.INF:
		await _shot_at(hang, 7.0, 2.2, "jungle_liana_hang")
	# 2) лиана, перекинутая между деревьями
	var span := _first_of(["flora_liana_span_01", "flora_liana_span_leafy_04", "flora_liana_span_braid_02"], true)
	if span != Vector3.INF:
		await _shot_at(span, 9.0, 1.7, "jungle_liana_span")
	# 3) подлесок: страусник и стрелиция
	var fern := _first_of(["flora_strelitzia"], false)
	if fern != Vector3.INF:
		await _shot_at(fern, 4.5, 1.6, "understory_strelitzia")
	var mat := _first_of(["flora_matteuccia_a", "flora_matteuccia_b"], false)
	if mat != Vector3.INF:
		await _shot_at(mat, 4.0, 1.5, "understory_fern")
	# 4) опушка: ховея / Kingsville / макрозамия
	var hw := _first_of(["flora_howea_1", "flora_howea_2"], false)
	if hw != Vector3.INF:
		await _shot_at(hw, 8.0, 1.7, "edge_howea")
	var kv := _first_of(["flora_kingsville_1", "flora_kingsville_3"], false)
	if kv != Vector3.INF:
		await _shot_at(kv, 10.0, 1.7, "edge_kingsville")
	# 5) пляж на отливе с водорослями
	var sw := fl.get_node_or_null(^"ShoreSeaweed") as ShoreSeaweed
	if sw:
		sw.set_process(false)
		w.set(&"event_sea_offset", -1.6)   # отлив поглубже, чтобы полоса открылась
		var best := Vector3.INF
		var a := w.arch as ArchipelagoV5
		for I in a.islands:
			if best != Vector3.INF:
				break
			var c: Vector2 = I.center
			for k in 48:
				var p := c + Vector2.from_angle(k * TAU / 48.0) * float(I.radius)
				for s in 40:
					var q := c + (p - c) * (1.25 - s * 0.01)
					var h := w.height_at(q.x, q.y)
					if h > -0.5 and h < 0.4 and w.zone_at(q.x, q.y) == &"beach":
						best = Vector3(q.x, h, q.y)
						break
				if best != Vector3.INF:
					break
		if best != Vector3.INF:
			cam.global_position = best + Vector3(0, 1.6, 0)
			for i in 6:
				sw._stream(best)
				await wait_frames(2)
			for k in sw._chunks:
				sw._update(sw._chunks[k], w.water_level(), 400.0)
			# камера: вдоль берега, с суши на море
			var c2: Vector2 = Vector2(best.x, best.z)
			var land := Vector2.ZERO
			for k in 16:
				var d := Vector2.from_angle(k * TAU / 16.0)
				if w.height_at(c2.x + d.x * 8.0, c2.y + d.y * 8.0) > w.height_at(c2.x + land.x * 8.0, c2.y + land.y * 8.0):
					land = d
			var eye := c2 + land * 5.0
			await _view(Vector3(eye.x, w.height_at(eye.x, eye.y) + 1.5, eye.y), Vector3(c2.x - land.x * 3.0, best.y, c2.y - land.y * 3.0), "beach_seaweed_lowtide", 4.0)
			print("[O] seaweed clumps=%d chunks=%d" % [int(sw.stats.clumps), int(sw.stats.chunks)])

func _first_of(ids: Array, need_jungle: bool) -> Vector3:
	var a := w.arch as ArchipelagoV5
	var c0: Vector2 = a.islands[0].center
	var best := Vector3.INF
	var bd := INF
	for key in fl._bush:
		var part := String(key).split("|")[0]
		if not FloraV5World.is_key(part) or not ids.has(FloraV5World.id_of_key(part)):
			continue
		for xf: Transform3D in fl._bush[key]:
			var o := xf.origin
			if need_jungle and w.zone_at(o.x, o.z) != &"jungle" and w.zone_at(o.x, o.z) != &"lowland_forest":
				continue
			var d := Vector2(o.x, o.z).distance_to(c0)
			if d < bd:
				bd = d
				best = o
	return best

func _shot_at(target: Vector3, dist: float, eye_h: float, nm: String) -> void:
	# ищем направление, откуда ближайшие 2/3 пути свободны от стволов
	var best_dir := Vector2(1, 0)
	var best_score := -INF
	for k in 12:
		var d := Vector2.from_angle(k * TAU / 12.0)
		var score := 0.0
		for s in 6:
			var q := Vector2(target.x, target.z) + d * dist * (0.3 + s * 0.12)
			score -= float(fl.trees_near(Vector3(q.x, 0, q.y), 1.2).size()) if fl.has_method(&"trees_near") else 0.0
			score -= absf(w.height_at(q.x, q.y) - target.y) * 0.3
		if score > best_score:
			best_score = score
			best_dir = d
	var e := Vector2(target.x, target.z) + best_dir * dist
	var ey := w.height_at(e.x, e.y) + eye_h
	await _view(Vector3(e.x, ey, e.y), target + Vector3(0, eye_h * 0.6, 0), nm, 5.0)

func _view(pos: Vector3, look: Vector3, nm: String, settle: float) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	w.terrain.focus_override = [pos] as Array[Vector3]
	await wait(settle)
	await wait_frames(3)
	var img := get_viewport().get_texture().get_image()
	if img and not img.is_empty():
		img.save_png("/mnt/user-data/outputs/v52_O_%s.png" % nm)
		print("[shot] v52_O_%s.png" % nm)
	shot(nm)
