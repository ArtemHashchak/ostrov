## test-timeout: 2400
extends TestCase
## test-class: render
## Снимки мира v5 для пользователя (агент G): бот в лодке между островами, тропа,
## джунгли изнутри днём, пляж стартового островка, архипелаг с холма на закате,
## лагуна под водой с рыбами, памятник (корабль на мели / маяк).
## Каждый кадр — отдельный файл /mnt/user-data/outputs/v5_G_<имя>.png.

func _init() -> void:
	OS.set_environment("OSTROVA_GEN", "5")
	scene_path = "res://scenes/world/world_view.tscn"
	timeout_sec = 2350.0

var cam: Camera3D
var w: World

func run() -> void:
	await wait(2.0)
	w = get_tree().get_first_node_in_group(&"world") as World
	if w == null or not w.is_ready:
		check(false, "мир готов")
		return
	Settings.view_distance = ViewDistance.SLIDER_MAXIMUM
	if Settings.has_method(&"apply_view"):
		Settings.call(&"apply_view")
	var fl := Flora.new()
	w.get_parent().add_child(fl)
	if ResourceLoader.exists("res://scenes/sea/sea.tscn"):
		w.get_parent().add_child((load("res://scenes/sea/sea.tscn") as PackedScene).instantiate())
	if not fl.populated:
		await fl.flora_ready
	w.set_weather(&"clear", true)
	cam = Camera3D.new()
	cam.far = 20000.0
	cam.fov = 70.0
	w.add_child(cam)
	cam.current = true
	for pl in get_tree().get_nodes_in_group(&"player"):
		(pl as Node).process_mode = Node.PROCESS_MODE_DISABLED
		(pl as Node3D).global_position = Vector3(0, -500, 0)
	var a := w.arch as ArchipelagoV5
	var zm := w.zones
	var only := OS.get_environment("G_ONLY")
	# стартовый островок команды 0 и его ближайший сосед
	var st: Dictionary = {}
	for I in a.islands:
		if a.class_of(I) == &"start" and int(I.team) == 0:
			st = I
	var sc: Vector2 = st.center
	var nb: Dictionary = {}
	for I in a.islands:
		if int(I.id) != int(st.id) and (nb.is_empty() or (I.center as Vector2).distance_to(sc) < (nb.center as Vector2).distance_to(sc)):
			nb = I
	var nc: Vector2 = nb.center
	var wl := w.water_level()
	# 1) лодка с ботом посреди пролива
	if only == "" or only.contains("boat"):
		w.set_time_of_day(9.5)
		var d := (nc - sc).normalized()
		var mid := sc + d * (float(st.radius) + ((nc - sc).length() - float(st.radius) - float(nb.radius)) * 0.45)
		var yaw := atan2(-d.x, -d.y)
		var boat := BotBoat.spawn(w, Vector3(mid.x, wl, mid.y), yaw, 1)
		boat.set_physics_process(true)
		var bm := BotModel.new().setup(1, 7)
		boat.add_child(bm)
		bm.position = BotBoat.SEAT
		await wait(0.5)
		bm.play(&"idle")
		var side := Vector2(-d.y, d.x)
		var eye := mid + side * 9.0 - d * 6.0
		await _view(Vector3(eye.x, wl + 3.2, eye.y), Vector3(mid.x, wl + 0.6, mid.y), "bot_boat", 5.0)
		await _view(Vector3(mid.x - d.x * 14.0 + side.x * 3.0, wl + 5.0, mid.y - d.y * 14.0 + side.y * 3.0), Vector3(nc.x, wl + 4.0, nc.y), "bot_boat_toward_island", 4.0)
		boat.queue_free()
	# 2) пляж стартового островка
	if only == "" or only.contains("beach"):
		w.set_time_of_day(10.0)
		var bp := _find_zone_near(sc, float(st.radius) * 1.2, ZoneMap.Z_BEACH)
		var outd := (bp - sc).normalized()
		var along := Vector2(-outd.y, outd.x)
		var eye2 := bp + along * 4.0
		await _view(Vector3(eye2.x, w.height_at(eye2.x, eye2.y) + 1.7, eye2.y), Vector3(bp.x - along.x * 30.0 + outd.x * 6.0, wl + 0.8, bp.y - along.y * 30.0 + outd.y * 6.0), "starter_beach", 5.0)
	# 3) звериная тропа (рост пригнувшегося игрока)
	if (only == "" or only.contains("trail")) and not w.trails.trails.is_empty():
		w.set_time_of_day(11.5)
		var best: PackedVector2Array = w.trails.trails[0]
		for t in w.trails.trails:
			if t.size() > best.size():
				best = t
		var i0 := best.size() / 2
		var p0 := best[i0]
		var p1 := best[mini(i0 + 5, best.size() - 1)]
		await _view(Vector3(p0.x, w.height_at(p0.x, p0.y) + 1.05, p0.y), Vector3(p1.x, w.height_at(p1.x, p1.y) + 0.7, p1.y), "trail_crouch", 6.0)
	# 4) джунгли изнутри днём — полдень, смотрим в просвет вдоль склона
	if only == "" or only.contains("jungle"):
		w.set_time_of_day(12.5)
		var C: Dictionary = a.islands[0]
		var cc: Vector2 = C.center
		var jp := cc
		var best_j := -1
		for k in 72:
			var p := cc + Vector2.from_angle(k * 0.0873) * float(C.radius) * 0.5
			var kk: int = -1
			if zm.zone_at(p.x, p.y) == ZoneMap.Z_JUNGLE:
				var j := int(zm.jungle[kk]) if kk >= 0 else 128
				if best_j < 0 or abs(j - 150) < abs(best_j - 150):
					best_j = j
					jp = p
		var dd := (cc - jp).normalized().rotated(0.6)
		await _view(Vector3(jp.x, w.height_at(jp.x, jp.y) + 1.7, jp.y), Vector3(jp.x + dd.x * 15.0, w.height_at(jp.x, jp.y) + 3.5, jp.y + dd.y * 15.0), "jungle_inside", 6.0)
	# 5) архипелаг с холма на закате — вершина крупного острова
	if only == "" or only.contains("sunset"):
		w.set_time_of_day(18.35)
		var top := Vector2.ZERO
		var th := -INF
		var L: Dictionary = {}
		for I in a.islands:
			if a.class_of(I) == &"large":
				L = I
				break
		if L.is_empty():
			L = a.islands[0]
		var lc: Vector2 = L.center
		for k in 400:
			var p := lc + Vector2.from_angle(k * 2.399) * float(L.radius) * sqrt(float(k) / 400.0) * 0.9
			var hh := w.height_at(p.x, p.y)
			if hh > th:
				th = hh
				top = p
		var outv := (top - Vector2.ZERO).normalized() * -1.0
		var sun: Vector3 = Vector3(-1, 0.1, 0)
		var lk := Vector2(sun.x, sun.z).normalized() if Vector2(sun.x, sun.z).length() > 0.1 else outv
		await _view(Vector3(top.x, th + 6.0, top.y), Vector3(top.x + lk.x * 400.0, th - 40.0, top.y + lk.y * 400.0), "sunset_hill", 6.0)
		await _view(Vector3(top.x, th + 6.0, top.y), Vector3(top.x + outv.x * 400.0, th - 60.0, top.y + outv.y * 400.0), "sunset_archipelago", 4.0)
	# 6) лагуна под водой с рыбами
	if only == "" or only.contains("lagoon"):
		w.set_time_of_day(11.0)
		var lg := Vector2.ZERO
		for k in range(0, zm.zone.size(), 23):
			if zm.zone[k] == ZoneMap.Z_LAGOON:
				var p := zm.origin + Vector2(k % zm.nx, k / zm.nx) * ZoneMap.STEP
				var fy := w.height_at(p.x, p.y)
				if fy < wl - 3.0 and fy > wl - 6.0:
					lg = p
					break
		var fy0 := w.height_at(lg.x, lg.y)
		await _view(Vector3(lg.x - 5, fy0 + 1.8, lg.y - 5), Vector3(lg.x + 6, fy0 + 1.0, lg.y + 6), "lagoon_underwater", 8.0)
	# 7) памятники
	if only == "" or only.contains("monument"):
		w.set_time_of_day(16.0)
		var done := {}
		for m in w.monuments():
			var t := StringName(m.type)
			if done.has(t) or not (t in [&"shipwreck", &"lighthouse"]):
				continue
			done[t] = true
			var mp: Vector2 = m.pos
			var mh := w.height_at(mp.x, mp.y)
			var off := Vector2.from_angle(float(m.get("yaw", 0.0)) + 0.9) * (28.0 if t == &"shipwreck" else 55.0)
			var eh := maxf(w.height_at(mp.x + off.x, mp.y + off.y), wl) + (4.0 if t == &"shipwreck" else 12.0)
			await _view(Vector3(mp.x + off.x, eh, mp.y + off.y), Vector3(mp.x, maxf(mh, wl) + (2.0 if t == &"shipwreck" else 14.0), mp.y), "monument_%s" % t, 6.0)

func _find_zone_near(c: Vector2, r: float, z: int) -> Vector2:
	for k in 96:
		var p := c + Vector2.from_angle(k * TAU / 96.0) * r
		for s in 30:
			var q := c + (p - c) * (1.0 - s * 0.03)
			if w.zones.zone_at(q.x, q.y) == z:
				return q
	return c + Vector2(r * 0.8, 0)

func _view(pos: Vector3, look: Vector3, nm: String, settle: float) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	w.terrain.focus_override = [pos] as Array[Vector3]
	await wait(settle)
	await wait_frames(3)
	var img := get_viewport().get_texture().get_image()
	if img and not img.is_empty():
		img.save_png("/mnt/user-data/outputs/v5_G_%s.png" % nm)
		print("[shot] v5_G_%s.png" % nm)
	shot(nm)
