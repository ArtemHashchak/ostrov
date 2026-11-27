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
			# средний план: поток идёт к морю — камера на пляже по ходу потока, смотрит на крабов
			SeasonEvents.time_scale = 10.0
			await wait(5.0)
			SeasonEvents.time_scale = 1.0
			var crabs: Array = e.get(&"crabs")
			# передний край потока
			var lead := Vector2(c.x, c.z)
			var lead_s := -INF
			for cc: Dictionary in crabs:
				if cc.alive:
					var sp := (cc.p as Vector2).dot(d)
					if sp > lead_s:
						lead_s = sp
						lead = cc.p
			var cam_p := lead + d * 9.0
			for k in 30:
				var q2 := lead + d * (4.0 + k * 1.5)
				var zn := StringName(w.zone_at(q2.x, q2.y))
				if zn in [&"beach", &"dunes", &"meadow"] and w.jungle_density(q2.x, q2.y) < 0.1:
					cam_p = q2
					break
			var bh := w.height_at(cam_p.x, cam_p.y)
			var tgt := lead - d * 6.0
			await _view(Vector3(cam_p.x, bh + 1.7, cam_p.y), Vector3(tgt.x, w.height_at(tgt.x, tgt.y) + 0.1, tgt.y), "red_crabs_stream", 2.0)
			se.stop(&"red_crabs")
	# 2) миграция мант
	if only == "" or only.contains("migr"):
		var e2 := se.start(&"migration", {"seed": 9, "whale_chance": 1.0})
		if e2:
			SeasonEvents.time_scale = 3.0
			await wait(6.0)
			SeasonEvents.time_scale = 1.0
			await wait(3.0)
			var p: Vector3 = e2.call(&"group_center")
			var pod := e2.get(&"_pod") as Node3D
			var fwd := (pod.global_position - p)
			fwd.y = 0.0
			fwd = fwd.normalized() if fwd.length() > 0.5 else -pod.global_basis.z
			var side := Vector3(-fwd.z, 0, fwd.x)
			await _view(p + side * 9.0 + Vector3(0, wl - p.y + 4.5, 0) - fwd * 4.0, p, "migration_above", 1.5)
			# под водой: камера у ближайшей манты (≈6 м сбоку, чуть ниже), смотрит на неё и стаю за ней
			var crit: Array = e2.get(&"_crit")
			var wn := e2.get(&"_whale_node") as Node3D
			var near: Node3D = null
			for c in crit:
				if is_instance_valid(c) and c != wn:
					if near == null or (c as Node3D).global_position.distance_to(p) < near.global_position.distance_to(p):
						near = c as Node3D
			if near:
				var mp := near.global_position
				var eye := mp + side * 6.0 - fwd * 2.5 + Vector3(0, -0.8, 0)
				eye.y = minf(eye.y, wl - 1.0)
				await _view(eye, mp + fwd * 3.0, "migration_underwater", 1.0)
			if wn and is_instance_valid(wn):
				var wp := wn.global_position
				var eyew := wp + side * 22.0 - fwd * 8.0
				eyew.y = minf(wp.y + 1.0, wl - 1.5)
				await _view(eyew, wp, "migration_whale", 1.0)
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
			# камера над водой у края, смотрит на дохлую рыбу (центр признаков)
			var dec := e4.get(&"_decor") as Node3D
			var fc := sp
			var nfi := 0
			for ch in dec.get_children():
				if ch is MeshInstance3D:
					fc += (ch as Node3D).global_position
					nfi += 1
			fc = (fc - sp) / float(maxi(nfi, 1)) if nfi > 0 else sp
			var away := Vector3(fc.x - sp.x, 0, fc.z - sp.z)
			away = away.normalized() if away.length() > 0.2 else Vector3(1, 0, 0)
			var eyep := fc - away * minf(r * 0.9, 5.0) + Vector3(0, 1.3, 0)
			eyep.y = maxf(eyep.y, w.height_at(eyep.x, eyep.z) + 1.2)
			await _view(eyep, fc, "poison_spring", 2.5)
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
