## test-timeout: 1800
extends TestCase
## Мир v5 целиком (матч): рассадка флоры по зонам (джунгли-стена, тропы, равные
## стартовые островки, нет деревьев в воде), кораллы только на рифах ниже отлива,
## морская жизнь — в открытом море по местам обитания.

func _init() -> void:
	OS.set_environment("OSTROVA_GEN", "5")
	scene_path = "res://scenes/world/match.tscn"
	timeout_sec = 1750.0

func run() -> void:
	await wait(2.0)
	var w := get_tree().get_first_node_in_group(&"world") as World
	check(w != null and w.is_ready and w.arch is ArchipelagoV5, "мир v5 готов")
	if w == null:
		return
	var zm := w.zones
	var fl := get_tree().get_first_node_in_group(&"flora") as Flora
	check(fl != null and fl.populated, "флора рассажена")
	if fl == null:
		return
	print("[test] флора: %s" % str(fl.stats))
	print("[test] тропы: %s" % str(w.trails.stats))
	check(int(w.trails.stats.get("trails", 0)) >= 8, "звериные тропы: %d" % int(w.trails.stats.get("trails", 0)))
	# 1) деревья не в воде, не на тропах
	var wet := 0
	var on_trail := 0
	for rec in fl._tree_recs:
		var p: Vector3 = rec["pos"]
		if rec["kind"] != &"mangrove" and w.height_at(p.x, p.z) < 0.8:
			wet += 1
		if w.trail_dist(p.x, p.z) < TrailNet.CLEAR:
			on_trail += 1
	check(wet == 0, "деревьев в воде нет (%d из %d)" % [wet, fl._tree_recs.size()])
	check(on_trail == 0, "на тропах деревьев нет (%d)" % on_trail)
	# 2) равные стартовые островки
	var res: Array = []
	for I in w.islands():
		if StringName(I.get("cls", &"")) == &"start":
			res.append(fl.island_resources(int(I.id)))
	var same := res.size() == 8
	for r in res:
		same = same and r == res[0]
	print("[test] ресурсы стартового островка: ", res[0] if not res.is_empty() else {})
	check(same, "у 8 стартовых островков одинаковые ресурсы")
	var tot := 0
	for k in (res[0] as Dictionary):
		tot += int(res[0][k])
	check(tot >= 15, "на стартовом островке есть чем жить: %d записей" % tot)
	for k: String in ["berries", "wild_taro", "boulder", "stone", "stick", "palm"]:
		check(int((res[0] as Dictionary).get(k, 0)) > 0, "на стартовом островке есть %s" % k)
	# 3) джунгли: подлесок гуще в центре острова, чем в поясе пальм
	var C: Dictionary = w.arch.islands[0]
	var cc: Vector2 = C.center
	var core := _bushes_near(fl, cc + Vector2(float(C.radius) * 0.4, 0.0), 30.0)
	var belt := 0
	for k in 8:
		var a := k * TAU / 8.0
		var p := cc + Vector2.from_angle(a) * float(C.radius) * 0.9
		if zm.zone_at(p.x, p.y) == ZoneMap.Z_PALM_BELT:
			belt = maxi(belt, _bushes_near(fl, p, 30.0))
	print("[test] подлесок: центр %d, пояс пальм %d (кустов в круге 30 м)" % [core, belt])
	check(core > 250 and core > belt * 2, "джунгли — стена в центре: %d кустов против %d" % [core, belt])
	# 4) кораллы — только на рифах и ниже самого низкого отлива
	var reefs := get_tree().get_first_node_in_group(&"sea_reefs")
	var bad := 0
	var n := 0
	var off_reef := 0
	if reefs:
		for key: String in reefs._cells:
			var t := key.split("|")[0]
			if t == "grass" or t == "rock":
				continue
			for xf: Transform3D in reefs._cells[key]["xf"]:
				n += 1
				if xf.origin.y > ZoneMap.LOW_TIDE - 0.3:
					bad += 1
				var zt := zm.zone_at(xf.origin.x, xf.origin.z)
				if zt != ZoneMap.Z_REEF_CREST and zt != ZoneMap.Z_REEF_FLAT and zt != ZoneMap.Z_REEF_SLOPE:
					off_reef += 1
	print("[test] кораллов: %d, выше отлива %d, вне рифа %d" % [n, bad, off_reef])
	check(n > 5000 and bad == 0, "кораллы ниже отлива: %d, выше %d" % [n, bad])
	check(off_reef < n * 0.08, "кораллы на рифах (вне рифа %d из %d — край ячейки)" % [off_reef, n])
	# 5) морская живность: камера над рифом — группы только в открытом море и под водой в отлив
	var cam := get_viewport().get_camera_3d()
	var reef_pt := Vector2.ZERO
	for k in zm.zone.size():
		if zm.zone[k] == ZoneMap.Z_REEF_FLAT:
			reef_pt = zm.origin + Vector2(k % zm.nx, k / zm.nx) * ZoneMap.STEP
			break
	if cam:
		cam.global_position = Vector3(reef_pt.x, -1.5, reef_pt.y)
	var cells := get_tree().get_first_node_in_group(&"sea_life_cells")
	if cells:
		cells.call(&"refresh")
		await wait(1.0)
		var groups := 0
		var dry := 0
		for mi in cells.get_children():
			if mi is MultiMeshInstance3D and (mi as MultiMeshInstance3D).visible:
				groups += 1
				var p := (mi as Node3D).global_position
				if not zm.is_sea(p.x, p.z) or p.y > ZoneMap.LOW_TIDE - 0.3:
					dry += 1
		print("[test] живность у рифа: групп %d, вне воды в отлив %d" % [groups, dry])
		check(groups >= 6 and dry == 0, "живность у рифа есть и всегда под водой: %d групп, %d вне" % [groups, dry])

func _bushes_near(fl: Flora, c: Vector2, r: float) -> int:
	var n := 0
	for key in fl._bush:
		for xf: Transform3D in fl._bush[key]:
			if Vector2(xf.origin.x, xf.origin.z).distance_to(c) < r:
				n += 1
	return n
