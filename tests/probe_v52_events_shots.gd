## test-timeout: 2400
extends TestCase
## test-class: render
## Снимки событий сезона v5.2 (агент M): красные крабы, миграция мант, цунами (отступ воды,
## стена волны, затопление), дрейфующий ящик на лодке, отравленный родник, награда за лидера.
## Каждый кадр — отдельный файл /mnt/user-data/outputs/v52_M_<имя>.png. M_ONLY=… — часть.

func _init() -> void:
	OS.set_environment("OSTROVA_GEN", "5")
	scene_path = "res://scenes/world/world_view.tscn"
	timeout_sec = 2350.0

var cam: Camera3D
var w: World
var se: SeasonEvents

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
	w.set_time_of_day(10.5)
	cam = Camera3D.new()
	cam.far = 20000.0
	cam.fov = 70.0
	w.add_child(cam)
	cam.current = true
	se = SeasonEvents.ensure()
	var a := w.arch as ArchipelagoV5
	var only := OS.get_environment("M_ONLY")
	var wl := w.water_level()
	# стартовый островок команды 0
	var st: Dictionary = {}
	for I in a.islands:
		if a.class_of(I) == &"start" and int(I.team) == 0:
			st = I
	var sc: Vector2 = st.center
	# средний остров рядом — для крабов
	var mid: Dictionary = {}
	for I in a.islands:
		if float(I.radius) > 70.0 and (mid.is_empty() or (I.center as Vector2).distance_to(sc) < (mid.center as Vector2).distance_to(sc)):
			mid = I
	# 1) красные крабы
	if only == "" or only.contains("crabs"):
		var e := se.start(&"red_crabs", {"island_id": int(mid.id), "seed": 4})
		if e:
			SeasonEvents.time_scale = 6.0
			await wait(2.0)
			SeasonEvents.time_scale = 1.0
			var ar := e.get(&"_area") as Area3D
			var c := ar.global_position
			var d := Vector2(cos(float(e.get(&"_src_ang"))), sin(float(e.get(&"_src_ang"))))
			# крупно: камера у земли перед лентой крабов
			var eye := Vector2(c.x, c.z) + d * 3.2 + Vector2(-d.y, d.x) * 1.2
			await _view(Vector3(eye.x, w.height_at(eye.x, eye.y) + 0.9, eye.y), c + Vector3(0, 0.05, 0), "red_crabs_close", 3.0)
			# средний план: камера над открытым местом сбоку от ленты, луч до цели без стволов
			var best := Vector3.INF
			var space := w.get_world_3d().direct_space_state
			for k in 16:
				var ang := TAU * k / 16.0
				for dist: float in [6.0, 8.0, 10.0]:
					var q2 := Vector2(c.x, c.z) + Vector2(cos(ang), sin(ang)) * dist
					var e3p := Vector3(q2.x, w.height_at(q2.x, q2.y) + 4.2, q2.y)
					var rq := PhysicsRayQueryParameters3D.create(e3p, c + Vector3(0, 0.2, 0))
					if space.intersect_ray(rq).is_empty():
						best = e3p
						break
				if best != Vector3.INF:
					break
			if best == Vector3.INF:
				best = c + Vector3(0, 6.0, 8.0)
			await _view(best, c, "red_crabs_stream", 2.0)
			se.stop(&"red_crabs")
	# 2) миграция мант
	if only == "" or only.contains("migr"):
		var e2 := se.start(&"migration", {"seed": 9, "whale_chance": 1.0, "speed": 3.2})
		if e2:
			SeasonEvents.time_scale = 4.0
			await wait(4.0)
			SeasonEvents.time_scale = 1.0
			await wait(2.0)
			var p: Vector3 = e2.call(&"pod_pos")
			var pod := e2.get(&"_pod") as Node3D
			var fwd := -pod.global_basis.z
			var side := Vector3(-fwd.z, 0, fwd.x)
			await _view(p + side * 16.0 + Vector3(0, 6.0, 0) + fwd * 6.0, p + Vector3(0, -1.0, 0), "migration_above", 2.0)
			await _view(p + side * 10.0 + Vector3(0, -2.5 - (wl - p.y) * 0.0, 0) + fwd * 10.0, p + Vector3(0, -0.5, 0), "migration_underwater", 2.0)
			se.stop(&"migration")
	# 3) дрейфующий ящик на лодке
	if only == "" or only.contains("drift"):
		var pos := Vector3.INF
		for k in 36:
			var ang := TAU * k / 36.0
			var q := sc + Vector2(cos(ang), sin(ang)) * (float(st.radius) + 60.0)
			if w.sea_ok(q.x, q.y, 3.0):
				pos = Vector3(q.x, wl, q.y)
				break
		var e3 := se.start(&"drift_crate", {"pos": pos})
		if e3:
			await wait(3.0)
			var cr := e3.get(&"crate") as Node3D
			var cp := cr.global_position
			await _view(cp + Vector3(7.0, 3.2, 6.0), cp + Vector3(0, 0.4, 0), "drift_crate", 2.0)
			se.stop(&"drift_crate")
	# 4) отравленный родник
	if only == "" or only.contains("poison"):
		var e4 := se.start(&"poison_spring", {"exact": true, "seed": 3})
		if e4:
			var sp: Vector3 = e4.get(&"spot")
			var r := float(e4.get(&"radius"))
			await _view(sp + Vector3(r + 2.5, 1.7, r * 0.6 + 1.5), sp, "poison_spring", 2.5)
			se.stop(&"poison_spring")
	# 5) награда за лидера: луч над участником
	if only == "" or only.contains("bounty"):
		var bp := Vector3.INF
		for k in 24:
			var ang := TAU * k / 24.0
			var q := sc + Vector2(cos(ang), sin(ang)) * float(st.radius) * 0.4
			if w.is_land(q.x, q.y):
				bp = Vector3(q.x, w.height_at(q.x, q.y), q.y)
				break
		var bm := BotModel.new().setup(1, 7)
		w.add_child(bm)
		bm.global_position = bp
		await wait(0.3)
		bm.play(&"idle")
		var e5 := se.start(&"bounty", {"target": bm})
		if e5:
			await wait(0.5)
			await _view(bp + Vector3(14.0, 6.0, 18.0), bp + Vector3(0, 8.0, 0), "bounty_beam", 2.0)
			se.stop(&"bounty")
		bm.queue_free()
	# 6) цунами: отступ воды → стена волны → затопленный пляж
	if only == "" or only.contains("tsu"):
		var beach := Vector3.INF
		var to_sea := Vector2.ZERO
		for k in 36:
			var ang := TAU * k / 36.0
			for rr in range(int(float(st.radius) * 0.6), int(float(st.radius) * 1.5), 3):
				var q := sc + Vector2(cos(ang), sin(ang)) * float(rr)
				var h := w.height_at(q.x, q.y)
				if h > wl + 0.4 and h < wl + 1.4:
					beach = Vector3(q.x, h, q.y)
					to_sea = Vector2(cos(ang), sin(ang))
					break
			if beach != Vector3.INF:
				break
		var e6 := se.start(&"tsunami", {"dir_deg": rad_to_deg(atan2(-to_sea.y, -to_sea.x)), "withdraw_s": 30.0,
			"front_speed": 38.0, "surge_hold_s": 30.0, "recede_s": 30.0})
		if e6:
			var eye := Vector2(beach.x, beach.z) - to_sea * 10.0
			var look := Vector3(beach.x + to_sea.x * 60.0, wl - 1.0, beach.z + to_sea.y * 60.0)
			var eyeh := w.height_at(eye.x, eye.y) + 2.2
			await _view(Vector3(eye.x, eyeh, eye.y), look, "tsunami_0_before", 1.0)
			SeasonEvents.time_scale = 5.0
			await wait(5.5)
			SeasonEvents.time_scale = 1.0
			await _view(Vector3(eye.x, eyeh, eye.y), look, "tsunami_1_withdraw", 1.0)
			# ждать, пока фронт будет в ~150 м от берега
			var fr := 0.0
			var t := 0.0
			var dir: Vector2 = e6.get(&"dir")
			while t < 400.0:
				fr = float(e6.get(&"front"))
				if String(e6.get(&"phase")) == "wave" and Vector2(beach.x, beach.z).dot(dir) - fr < 170.0:
					break
				SeasonEvents.time_scale = 8.0
				await wait(0.25)
				t += 2.0
			SeasonEvents.time_scale = 1.0
			await _view(Vector3(eye.x, eyeh + 3.0, eye.y), look + Vector3(0, 4.0, 0), "tsunami_2_wave", 0.6)
			SeasonEvents.time_scale = 8.0
			while String(e6.get(&"phase")) == "wave":
				await wait(0.2)
			SeasonEvents.time_scale = 1.0
			var eye3 := Vector2(beach.x, beach.z) - to_sea * 45.0
			await _view(Vector3(eye3.x, w.height_at(eye3.x, eye3.y) + 6.0, eye3.y), Vector3(beach.x, wl, beach.z), "tsunami_3_flood", 1.5)
			se.stop(&"tsunami")
	SeasonEvents.time_scale = 1.0

func _view(pos: Vector3, look: Vector3, nm: String, settle: float) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	if w.terrain and &"focus_override" in w.terrain:
		w.terrain.focus_override = [pos] as Array[Vector3]
	await wait(settle)
	await wait_frames(3)
	var img := get_viewport().get_texture().get_image()
	if img and not img.is_empty():
		img.save_png("/mnt/user-data/outputs/v52_M_%s.png" % nm)
		print("[shot] v52_M_%s.png" % nm)
	shot(nm)
