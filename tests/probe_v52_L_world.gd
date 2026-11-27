## test-timeout: 2400
extends TestCase
## test-class: render
## Снимки v5.2 (агент L) в настоящем мире v5: сценки режиссёра суши и подсказки мира.
## Каждый кадр — отдельный файл /mnt/user-data/outputs/v52_L_<имя>.png. L_ONLY=имя1,имя2 — выборочно.

func _init() -> void:
	OS.set_environment("OSTROVA_GEN", "5")
	scene_path = "res://scenes/world/world_view.tscn"
	timeout_sec = 2350.0

var cam: Camera3D
var w: World
var d: LandDirector
var h: WorldHints
var only := ""
var _rng := RandomNumberGenerator.new()

func run() -> void:
	await wait(2.0)
	w = get_tree().get_first_node_in_group(&"world") as World
	if w == null or not w.is_ready:
		check(false, "мир готов")
		return
	only = OS.get_environment("L_ONLY")
	# llvmpipe: кадр мира целиком идёт минуты — сцены снимаются вблизи, дальность и флора поменьше
	Settings.view_distance = 500.0
	Settings.flora_distance = 0.5
	Settings.apply_view()
	_rng.seed = 7
	var fl := Flora.new()
	w.get_parent().add_child(fl)
	flora = fl
	var fa := Fauna.new()
	fa.set(&"auto_populate", false)
	w.get_parent().add_child(fa)
	if not fl.populated:
		await fl.flora_ready
	w.set_weather(&"clear", true)
	if w.has_method(&"set_time_paused"):
		w.set_time_paused(true)
	cam = Camera3D.new()
	cam.far = 20000.0
	cam.fov = 62.0
	w.add_child(cam)
	cam.current = true
	for pl in get_tree().get_nodes_in_group(&"player"):
		(pl as Node).process_mode = Node.PROCESS_MODE_DISABLED
		(pl as Node3D).global_position = Vector3(0, -500, 0)
	d = LandDirector.instance()
	h = WorldHints.instance()
	check(d != null and h != null, "режиссёр и подсказки есть в мире v5")
	if d == null or h == null:
		return
	var a := w.arch as ArchipelagoV5
	var st: Dictionary = {}
	for I in a.islands:
		if a.class_of(I) == &"start" and int(I.team) == 0:
			st = I
	var big: Dictionary = {}
	for I in a.islands:
		if a.class_of(I) in [&"large", &"huge"] and (big.is_empty() or float(I.radius) > float(big.radius)):
			big = I
	var sc: Vector2 = st.center
	var bc: Vector2 = big.center if not big.is_empty() else sc
	var beach := _zone(sc, float(st.radius) * 1.3, ZoneMap.Z_BEACH)
	var forest := _zone(bc, float(big.radius) * 0.8 if not big.is_empty() else 60.0, ZoneMap.Z_LOWLAND_FOREST)
	var palm := _zone(bc, float(big.radius) * 1.0 if not big.is_empty() else 60.0, ZoneMap.Z_PALM_BELT)
	var rocks := _zone(bc, float(big.radius) * 1.1 if not big.is_empty() else 60.0, ZoneMap.Z_ROCKS)
	var beach2 := _zone(bc, float(big.radius) * 1.25 if not big.is_empty() else 60.0, ZoneMap.Z_BEACH)
	# --- сценки
	await _scene("gull_crab_drop", beach2 if beach2 != Vector3.INF else beach, 10.0, 45, "gull_carries_crab", 1.7, 0.2, true)
	await _scene_cont("gull_pecks_dropped_crab", 160, 2.2, 0.8)
	await _scene("monitor_carcass", beach2 if beach2 != Vector3.INF else forest, 11.0, 300, "monitor_at_carcass", 3.5, 1.2)
	if _want("carrion_birds_circle_high") and _last and is_instance_valid(_last) and _last.data.has("body"):
		h.add_carrion(_last.data.body)
		for i in 40:
			h._physics_process(0.1)
		# стая кружит на ~30 м: камера поднята к стае (снизу-сбоку, на фоне неба), стая — треть кадра
		var birdc := Vector3.ZERO
		var nb := 0
		for b in get_tree().get_nodes_in_group(&"carrion_birds"):
			birdc += (b as Node3D).global_position
			nb += 1
		if nb > 0:
			birdc /= nb
			var cp: Vector3 = (_last.data.body as Node3D).global_position
			var off := Vector3(birdc.x - cp.x, 0, birdc.z - cp.z)
			var side := Vector3(1, 0, 0.4).normalized() if off.length() < 1.0 else off.normalized()
			await _view(birdc + side * 24.0 + Vector3(0, -9.0, 0), birdc + Vector3(0, -4.0, 0), "carrion_birds_circle_high", 3.0)
	_clean()
	await _scene("crab_march", beach, 18.2, 140, "crab_march_to_sea", 5.0, 2.2)
	_clean()
	await _scene("hatchlings", beach2, 18.3, 130, "hatchlings_to_sea", 2.2, 1.0)
	_clean()
	await _scene("bat_emergence", rocks if rocks != Vector3.INF else forest, 18.4, 60, "bats_emerge_at_dusk", 9.0, -4.0, true)
	_clean()
	await _scene("gulls_fight", beach2, 11.0, 60, "gulls_fight_over_fish", 1.9, 0.7)
	_clean()
	await _scene("iguanas_bask", beach if beach != Vector3.INF else rocks, 8.5, 10, "iguanas_basking", 2.6, 0.9)
	_clean()
	await _scene("boar_family", forest, 13.0, 60, "boar_family_rooting", 4.0, 1.0)
	_clean()
	await _scene("parrots_flock", palm, 9.0, 140, "parrots_on_crown", 2.8, -0.4, true)
	_clean()
	await _scene("hermit_shell", beach2, 12.0, 420, "hermit_crabs_queue_at_shell", 0.75, 0.35)
	_clean()
	await _scene("snake_hunt", forest, 15.0, 100, "snake_stalks_salamander", 1.6, 0.6)
	_clean()
	await _scene("turtle_nesting", beach, 19.2, 900, "turtle_digging_nest", 3.2, 1.2)
	if _want("turtle_tracks_to_nest"):
		_step(_last, 600)
		for n in get_tree().get_nodes_in_group(&"turtle_nests"):
			h.turtle_tracks(n as Node3D)
			var np := (n as Node3D).global_position
			var wp: Vector3 = n.get_meta(&"from_water", np + Vector3(0, 0, -10))
			var mid := np.lerp(wp, 0.5)
			var side := Vector3(wp.z - np.z, 0, np.x - wp.x).normalized()
			await _view(mid + side * 7.0 + Vector3(0, 4.0, 0), mid, "turtle_tracks_to_nest", 3.0)
			break
	_clean()
	var sea := _sea_near(beach2, 60.0)
	await _scene("gulls_fish", sea, 11.0, 60, "gulls_over_fish_school", 10.0, 1.0, true)
	_clean()
	await _scene("air_chase", sea, 11.0, 40, "air_chase_gull_robbed", 6.0, 0.0, true)
	_clean()
	await _scene("monitor_shore", beach2, 10.0, 80, "monitor_patrols_shore", 3.8, 1.2)
	_clean()
	# --- подсказки мира
	w.set_time_of_day(12.0)
	if _want("wrack_line_after_storm"):
		var n := h.spawn_wrack(beach2, 60.0)
		print("[wrack] точек %d" % n)
		var wl := _wrack_point(beach2)
		await _view(wl + Vector3(-5, 2.0, 5), wl, "wrack_line_after_storm", 3.0)
	if _want("guano_and_feathers"):
		h._spawn_guano()
		var gd := get_tree().get_first_node_in_group(&"guano_deposits") as Node3D
		if gd == null:
			gd = h.add_guano(rocks if rocks != Vector3.INF else beach)
		h.feathers(gd.global_position + Vector3(1.2, 0, 0.6), &"gull")
		await _view(gd.global_position + Vector3(2.6, 1.6, 2.6), gd.global_position, "guano_and_feathers", 3.0)
	if _want("ants_and_flies_on_meat"):
		var food: Array[Dictionary] = [{"id": &"meat_raw", "n": 1}]
		var fp := forest + Vector3(2, 0.3, 2)
		var pk := ItemPickup.spawn(w.get_parent(), fp, food)
		await wait(1.0)
		pk.freeze = true
		h.add_ants(pk)
		h.add_flies(pk)
		await _view(pk.global_position + Vector3(1.2, 0.7, 1.2), pk.global_position, "ants_and_flies_on_meat", 2.5)
	if _want("fresh_seep_green_strip"):
		var sp := Vector3.INF
		for m: Dictionary in w.monuments():
			if StringName(m.type) == &"spring":
				sp = m.pos
		if sp == Vector3.INF:
			sp = forest
		h.seep(sp)
		await _view(sp + Vector3(-7, 3.0, 7), sp + Vector3(2, 0, -2), "fresh_seep_green_strip", 3.0)

var _last: LandScene = null

func _want(nm: String) -> bool:
	return only == "" or only.contains(nm)

func _scene(id: String, p: Vector3, hour: float, steps: int, nm: String, dist: float, hgt: float, sky := false) -> void:
	if not _want(nm) and not (nm == "gull_carries_crab" and _want("gull_pecks")) and not (id == "monitor_carcass" and _want("carrion")) and not (id == "turtle_nesting" and _want("turtle_tracks")):
		return
	if p == Vector3.INF:
		print("[skip] нет места для ", id)
		return
	w.set_time_of_day(hour)
	d._recent.clear()
	_last = d.start(id, p, true)
	if _last == null:
		print("[skip] не запустилась ", id)
		return
	_step(_last, steps)
	if _want(nm):
		await _frame(_last, nm, dist, hgt, sky)

func _scene_cont(nm: String, steps: int, dist: float, hgt: float) -> void:
	if not _want(nm) or _last == null or not is_instance_valid(_last):
		return
	_step(_last, steps)
	await _frame(_last, nm, dist, hgt, false)

func _step(s: LandScene, steps: int) -> void:
	if s == null or not is_instance_valid(s):
		return
	for i in steps:
		if s.done:
			break
		s._process(0.1)

func _clean() -> void:
	d.stop_all()
	_last = null

## Камера на актёров сценки: сценка на паузе (кадр — ключевой момент), центр по актёрам,
## камера в dist м с той стороны, откуда рельеф не загораживает; актёры в кадре проверяются.
var flora: Flora

## Сколько растений (деревья, кусты, папоротники) стоит на линии камера → актёры: листва закрывает кадр.
func _foliage_on_line(a: Vector3, b: Vector3) -> float:
	if flora == null:
		return 0.0
	var pen := 0.0
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	for e in flora.nodes_near((a + b) * 0.5, a.distance_to(b) * 0.5 + 3.0):
		var q: Vector3 = e.position
		var q2 := Vector2(q.x, q.z)
		var cl := Geometry2D.get_closest_point_to_segment(q2, a2, b2)
		var dd := cl.distance_to(q2)
		if q2.distance_to(b2) < 0.8:
			continue                      # у самих актёров — пусть
		if dd < 1.6:
			pen += 10.0 if String(e.kind) in ["tree", "palm"] else 6.0
		if q2.distance_to(a2) < 2.2:
			pen += 12.0                   # камера в кусте/кроне
	return pen

func _frame(s: LandScene, nm: String, dist: float, hgt: float, sky: bool) -> void:
	s.set_process(false)
	var pts: Array[Vector3] = []
	for av: Variant in s.actors:
		if is_instance_valid(av):
			var a := av as Animal
			if sky and not a.cfg.get("fly", false):
				continue
			pts.append(a.global_position + Vector3(0, 0.15, 0))
	if pts.is_empty():
		pts.append(s.global_position)
	var c := Vector3.ZERO
	for p in pts:
		c += p
	c /= pts.size()
	var best := Vector3.INF
	var bscore := -INF
	var space := get_viewport().get_world_3d().direct_space_state
	# солнце: снимаем со стороны солнца (актёры освещены, не чёрные силуэты)
	var to_sun := Vector3.UP
	for L in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		if (L as DirectionalLight3D).visible and (L as DirectionalLight3D).light_energy > 0.05:
			to_sun = (L as DirectionalLight3D).global_basis.z
			break
	# главный актёр (первый живой наземный) — снимать сбоку, не с хвоста
	var hero_fwd := Vector3.ZERO
	for av: Variant in s.actors:
		if is_instance_valid(av) and not (av as Animal).dead and not (av as Animal).cfg.get("fly", false):
			hero_fwd = (av as Animal).global_basis.z
			break
	for k in 32:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, TAU * (k % 16) / 16.0)
		var p := c + dir * dist * (1.0 if k < 16 else 0.8)
		var g := maxf(w.height_at(p.x, p.z), w.water_level())
		var y := maxf(c.y + hgt, g + 0.8)
		var cp := Vector3(p.x, y, p.z)
		var score := -absf(y - (c.y + hgt))
		# рельеф между камерой и центром
		for t in [0.04, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9]:
			var q: Vector3 = cp.lerp(c, t)
			if w.height_at(q.x, q.z) > q.y - 0.1:
				score -= 20.0
		var vd := (c - cp).normalized()
		score += maxf(0.0, Vector2(-vd.x, -vd.z).normalized().dot(Vector2(to_sun.x, to_sun.z).normalized())) * 4.0
		if hero_fwd != Vector3.ZERO:
			score -= absf(Vector2(vd.x, vd.z).normalized().dot(Vector2(hero_fwd.x, hero_fwd.z).normalized())) * 3.0
		score -= _foliage_on_line(cp, c)
		score -= maxf(0.0, cp.distance_to(c) - dist * 1.4) * 4.0   # склон поднял камеру — актёры мелкие
		# камера внутри камня/ствола/постройки (луч изнутри коллизии не ловит) — кадр чёрный
		var pq := PhysicsPointQueryParameters3D.new()
		pq.position = cp
		if not space.intersect_point(pq, 1).is_empty():
			score -= 60.0
		for pr: Variant in s.props:
			if is_instance_valid(pr) and (pr as Node3D).global_position.distance_to(cp) < 1.5:
				score -= 20.0
		# стволы/камни/постройки между камерой и актёрами (коллизии) — такой ракурс не годится
		for ap in pts:
			var rq := PhysicsRayQueryParameters3D.create(cp, ap)
			var hit := space.intersect_ray(rq)
			if not hit.is_empty() and (hit.position as Vector3).distance_to(ap) > 0.6 and not (hit.collider is Animal) \
					and not (hit.collider as Node).get_parent() is Animal:
				score -= 30.0
		# со стороны моря/пониже — меньше листвы в кадре
		score -= maxf(0.0, w.height_at(p.x, p.z) - c.y) * 2.0
		if w.zones and w.zones.inside(p.x, p.z) and w.zones.jungle_density(p.x, p.z) > 0.3:
			score -= 6.0
		if score > bscore:
			bscore = score
			best = cp
	cam.global_position = best
	cam.look_at(c, Vector3.UP)
	var inside := 0
	for p in pts:
		if cam.is_position_in_frustum(p):
			inside += 1
	print("[frame] %s актёров в кадре %d/%d, камера %.1f м" % [nm, inside, pts.size(), best.distance_to(c)])
	await _view(best, c, nm, 2.0)
	s.set_process(true)

func _view(pos: Vector3, look: Vector3, nm: String, settle: float) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	w.terrain.focus_override = [pos] as Array[Vector3]
	await wait(minf(settle, 1.0))
	await wait_frames(2)
	var img := get_viewport().get_texture().get_image()
	if img and not img.is_empty():
		img.save_png("/mnt/user-data/outputs/v52_L_%s.png" % nm)
		var lum := 0.0
		for i in 64:
			lum += img.get_pixel(int(img.get_width() * ((i % 8) + 0.5) / 8.0), int(img.get_height() * ((i / 8) + 0.5) / 8.0)).get_luminance()
		print("[lum] %s %.2f cam=%s" % [nm, lum / 64.0, pos])
		print("[shot] v52_L_%s.png" % nm)

func _zone(c: Vector2, r: float, z: int) -> Vector3:
	for k in 96:
		var p := c + Vector2.from_angle(k * TAU / 96.0 + 0.3) * r
		for s in 30:
			var q := c + (p - c) * (1.0 - s * 0.03)
			if w.zones.zone_at(q.x, q.y) == z:
				return Vector3(q.x, w.height_at(q.x, q.y), q.y)
	return Vector3.INF

func _sea_near(p: Vector3, r: float) -> Vector3:
	for k in 48:
		var dir := Vector2.from_angle(k * TAU / 48.0)
		for s in range(10, int(r), 4):
			var q := Vector2(p.x, p.z) + dir * s
			var depth := w.water_level() - w.height_at(q.x, q.y)
			if depth > 3.0:
				return Vector3(q.x, w.water_level(), q.y)
	return p + Vector3(40, 0, 0)

func _wrack_point(c: Vector3) -> Vector3:
	for ch in h.get_children():
		if ch.name.begins_with("WrackLine"):
			var mmi := ch.get_child(0) as MultiMeshInstance3D
			if mmi and mmi.multimesh.instance_count > 0:
				var best := Vector3.INF
				for i in mmi.multimesh.instance_count:
					var o := mmi.multimesh.get_instance_transform(i).origin
					if best == Vector3.INF or o.distance_to(c) < best.distance_to(c):
						best = o
				return best
	return c
