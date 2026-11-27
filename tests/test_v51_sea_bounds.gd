## test-timeout: 1500
extends TestCase
## v5.1 (агент I): морская живность никогда не бывает на суше. Мир v5, камера у разных берегов
## архипелага: все группы SeaLifeCells (вся петля маршрута), особи пака вблизи, существа со скелетом,
## акулы, косяки — в открытом море и под водой. Кит — редкий: не больше 2 групп на карту и только в
## открытом океане; рядом с камерой китов нет.

func _init() -> void:
	OS.set_environment("OSTROVA_GEN", "5")
	scene_path = "res://scenes/world/match.tscn"
	timeout_sec = 1450.0

func run() -> void:
	await wait(2.0)
	var w := get_tree().get_first_node_in_group(&"world") as World
	check(w != null and w.is_ready and w.zones != null, "мир v5 с картой зон готов")
	if w == null or w.zones == null:
		return
	var zm := w.zones
	var sea := get_tree().get_first_node_in_group(&"sea")
	check(sea != null, "модуль моря есть")
	if sea == null:
		return
	var cells := get_tree().get_first_node_in_group(&"sea_life_cells") as SeaLifeCells
	var acts := get_tree().get_first_node_in_group(&"user_sea_actors") as UserSeaActors
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		cam = Camera3D.new()
		w.add_child(cam)
	cam.current = true
	# точки у берегов: мелководье в 6–30 м от суши, по всей карте
	var pts: Array[Vector3] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 51
	var tries := 0
	while pts.size() < 14 and tries < 20000:
		tries += 1
		var x := zm.origin.x + rng.randf() * zm.nx * ZoneMap.STEP
		var z := zm.origin.y + rng.randf() * zm.nz * ZoneMap.STEP
		if not zm.is_sea(x, z):
			continue
		var d := zm.depth_low(x, z)
		if d < 0.8 or d > 5.0 or zm.dist_to_coast(x, z) > 30.0:
			continue
		var far := true
		for q in pts:
			if Vector2(q.x - x, q.z - z).length() < 300.0:
				far = false
		if far:
			pts.append(Vector3(x, -1.2, z))
	print("[test] точек у берега: %d" % pts.size())
	check(pts.size() >= 8, "нашлись точки у берегов: %d" % pts.size())
	var bad: Array[String] = []
	var n_groups := 0
	var n_act := 0
	var n_crit := 0
	var whales_near := 0
	var whale_cells := {}
	for pt in pts:
		cam.global_position = pt
		if cells:
			cells.refresh()
		await wait(5.0)
		# 1) группы (MultiMesh): вся петля маршрута
		if cells:
			for mi in cells.get_children():
				if not (mi is MultiMeshInstance3D) or not (mi as MultiMeshInstance3D).visible:
					continue
				n_groups += 1
				var id := String(mi.get_meta(&"species", ""))
				var d := SeaSpecies.get_species(id)
				var L := float(d.get("length", 0.5))
				var ro := float(d.get("roam", 6.0))
				var c := (mi as Node3D).global_position
				if int(d.get("rare", 0)) > 0:
					whale_cells[Vector2i(floori(c.x / SeaLifeCells.CELL), floori(c.z / SeaLifeCells.CELL))] = true
					if not SeaBounds.deep_ocean(sea, c.x, c.z):
						bad.append("кит не в океане: %s" % c)
				if not SeaBounds.ring_ok(sea, c, ro + L * 0.6, ro * 0.75 + L * 0.6, SeaBounds.need_depth(L) * 0.9, 16):
					bad.append("группа %s у %s: петля задевает берег/мель" % [id, c])
				if c.y > ZoneMap.LOW_TIDE - 0.3:
					bad.append("группа %s у %s выше отлива" % [id, c])
		# 2) особи вблизи
		if acts:
			for a in acts.actors:
				if not is_instance_valid(a) or a.pinned:
					continue
				n_act += 1
				var p := a.global_position
				if float(a.data.get("length", 0.5)) >= UserSeaActors.GIANT_LEN:
					whales_near += 1
				if not SeaBounds.water_ok(sea, p.x, p.z, 0.4) or p.y > float(sea.call(&"water_y")):
					bad.append("особь %s у %s на суше/над водой" % [a.data.get("id", "?"), p])
			for cr in acts.critters:
				if not is_instance_valid(cr) or cr.dead:
					continue
				n_crit += 1
				var p2 := cr.global_position
				if cr.length >= UserSeaActors.GIANT_LEN:
					whales_near += 1
				if cr.mode != SeaCritter.M.BALLISTIC and (not SeaBounds.water_ok(sea, p2.x, p2.z, 0.4) or p2.y > float(sea.call(&"water_y"))):
					bad.append("существо %s у %s на суше/над водой" % [cr.sp.get("id", "?"), p2])
		# 3) акулы и косяки
		for s: Node3D in sea.sharks:
			if is_instance_valid(s) and not bool(s.call(&"is_dead")):
				var p3: Vector3 = s.global_position
				# акула охотится и на мелководье в прилив — проверка по воде сейчас (не по отливу)
				var dn := float(sea.call(&"depth_at", p3.x, p3.z))
				if dn < 0.25 or p3.y > float(sea.call(&"water_y")) + 0.8:   # +0.8 — выпрыгивание (breach)
					bad.append("акула у %s на суше (глубина %.2f)" % [p3, dn])
		# 4) все существа со скелетом в дереве (сценки моря тоже)
		for n: Node in _all(w):
			if n is SeaCritter and not (n as SeaCritter).dead and (n as SeaCritter).mode != SeaCritter.M.BALLISTIC \
					and int((n as SeaCritter).get(&"_bounds")) != 0:
				var p4 := (n as Node3D).global_position
				if not SeaBounds.water_ok(sea, p4.x, p4.z, 0.3):
					bad.append("существо сценки %s у %s на суше" % [(n as SeaCritter).sp.get("id", "?"), p4])
	print("[test] групп %d, особей %d, существ %d, убрано проверкой %d" % [n_groups, n_act, n_crit, acts.removed_dry if acts else -1])
	for b in bad.slice(0, 25):
		print("[test] ✗ ", b)
	check(n_groups > 20, "живность у берегов есть: %d групп" % n_groups)
	check(bad.is_empty(), "морская живность только в море: нарушений %d" % bad.size())
	check(whales_near == 0, "китов рядом с камерой нет (%d)" % whales_near)
	# кит: не больше 2 ячеек на всю карту, все — открытый океан
	var wd := SeaSpecies.get_species("whale_humpback_user")
	if cells and not wd.is_empty():
		var rc := cells._rare_cells(wd)
		print("[test] ячейки кита: %s" % str(rc.keys()))
		check(rc.size() <= 2 and rc.size() >= 1, "кит — 1–2 места на карту (%d)" % rc.size())
		for k: Vector2i in rc:
			var c2 := Vector3((k.x + 0.5) * SeaLifeCells.CELL, 0, (k.y + 0.5) * SeaLifeCells.CELL)
			check(SeaBounds.deep_ocean(sea, c2.x, c2.z) and SeaBounds.ring_ok(sea, c2, 50.0, 50.0, 20.0), "место кита — открытый океан: %s" % c2)
	# Sea.depth_at: вне моря (отрезанные низины, суша) — меньше нуля
	var land := 0
	var wrong := 0
	for i in 4000:
		var x := zm.origin.x + rng.randf() * zm.nx * ZoneMap.STEP
		var z := zm.origin.y + rng.randf() * zm.nz * ZoneMap.STEP
		if not zm.is_sea(x, z):
			land += 1
			if float(sea.call(&"depth_at", x, z)) >= 0.0:
				wrong += 1
	check(land > 100 and wrong == 0, "Sea.depth_at вне моря < 0 (%d из %d)" % [wrong, land])

func _all(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	var st: Array[Node] = [root]
	while not st.is_empty():
		var n: Node = st.pop_back()
		out.append(n)
		st.append_array(n.get_children())
	return out
