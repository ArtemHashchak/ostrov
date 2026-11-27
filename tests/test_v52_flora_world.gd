## test-timeout: 1500
extends TestCase
## v5.2 (агент O): новые растения пользователя (flora_v5) рассажены генерацией мира v5:
## папоротники/стрелиция/ховея/Kingsville/макрозамия по зонам, лианы на деревьях джунглей и
## между ними, травы набора в слое декора; меши есть, не в воде, коллизии solid/soft в индексе
## у игрока, мачете не рубит деревья v5.

func _init() -> void:
	OS.set_environment("OSTROVA_GEN", "5")
	scene_path = "res://scenes/world/world_view.tscn"
	timeout_sec = 1450.0

func run() -> void:
	await wait(2.0)
	var w := get_tree().get_first_node_in_group(&"world") as World
	check(w != null and w.is_ready, "мир v5 готов")
	if w == null:
		return
	var fl := Flora.new()
	w.get_parent().add_child(fl)
	if not fl.populated:
		await fl.flora_ready
	print("[test] v5-флора: ", JSON.stringify(_v5_stats(fl)))
	for g in ["fern", "strelitzia", "howea", "kingsville", "macrozamia", "hang", "span"]:
		check(int(fl.stats.get("v5_" + g, 0)) > 0, "рассажено v5_%s: %d" % [g, int(fl.stats.get("v5_" + g, 0))])
	# меши и вода
	var keys := 0
	var no_mesh := 0
	var wet := 0
	var total := 0
	for key in fl._bush:
		var part := String(key).split("|")[0]
		if not FloraV5World.is_key(part):
			continue
		keys += 1
		if not fl._bush_mm.has(key):
			no_mesh += 1
		var grp := FloraV5World.group_of(FloraV5World.id_of_key(part))
		for xf: Transform3D in fl._bush[key]:
			total += 1
			if grp != "hang" and grp != "span" and w.height_at(xf.origin.x, xf.origin.z) < fl._land_min:
				wet += 1
	check(keys > 0 and no_mesh == 0, "у всех видов v5 есть MultiMesh (%d групп, без меша %d)" % [keys, no_mesh])
	check(wet == 0, "в воде растений v5 нет (%d из %d)" % [wet, total])
	# коллизии: v5 solid/soft в индексе
	var v5col := 0
	for k in fl._pcol_index:
		for it in fl._pcol_index[k]:
			if String(it[0]).begins_with("flora_") and AssetCatalog.get_entry(String(it[0])).get("scene", "").contains("flora_v5"):
				v5col += 1
	check(v5col > 0, "коллизии растений v5 в индексе: %d" % v5col)
	# мачете: дерево Kingsville не рубится
	var kv: Transform3D
	var found := false
	for key in fl._bush:
		if String(key).begins_with(FloraV5World.PREFIX_T + "flora_kingsville"):
			kv = (fl._bush[key] as Array)[0]
			found = true
			break
	if found:
		fl.clear_brush(kv.origin, 1.5)
		var still := false
		for key in fl._bush:
			if String(key).begins_with(FloraV5World.PREFIX_T + "flora_kingsville"):
				for xf: Transform3D in fl._bush[key]:
					if xf.origin.is_equal_approx(kv.origin) and xf.basis.get_scale().x > 0.01:
						still = true
		check(still, "мачете не рубит Kingsville")
	# травы набора в декоре у игрока (стрим чанков вокруг точки суши)
	var a := w.arch as ArchipelagoV5
	var C: Dictionary = a.islands[0]
	var cc: Vector2 = C.center
	var v5g := 0
	for k in 12:
		var p := cc + Vector2.from_angle(k * TAU / 12.0) * float(C.radius) * 0.75
		fl._stream_decor(Vector3(p.x, 0, p.y), 9)
	for k in fl._decor:
		for mmi in fl._decor[k]:
			var mm := (mmi as MultiMeshInstance3D).multimesh
			if mm and mm.mesh and FloraV5World._mesh_cache.values().has(mm.mesh) and mm.instance_count > 0:
				v5g += 1
	check(v5g > 0, "травы набора пользователя в декоре: %d групп" % v5g)

func _v5_stats(fl: Flora) -> Dictionary:
	var d := {}
	for k in fl.stats:
		if String(k).begins_with("v5_"):
			d[k] = fl.stats[k]
	return d
