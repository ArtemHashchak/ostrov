extends TestCase
## test-class: render
## Живность по реестру SeaSpecies в ячейках вокруг игрока (пузырь), шейдерная анимация,
## расталкивание пловцом, VAT-запекание скелетной анимации, свои виды из JSON.

class Swimmer extends Node3D:
	func _ready() -> void:
		add_to_group(&"characters")
	func is_in_water() -> bool:
		return true
	func is_dead() -> bool:
		return false

func _init() -> void:
	scene_path = "res://scenes/world/world_view.tscn"
	timeout_sec = 3000.0

func run() -> void:
	await wait(1.0)
	var w := get_tree().get_first_node_in_group(&"world") as World
	check(w != null and w.is_ready, "мир готов")
	if w == null:
		return
	# --- реестр ---
	SeaSpecies.reload()
	var n_builtin := SeaSpecies.all().size()
	check(n_builtin >= 5, "встроенных видов: %d" % n_builtin)
	check(not SeaSpecies.get_species("moray").is_empty(), "вид по id")

	# --- VAT на синтетическом скелете ---
	_vat_check()

	var sea := Sea.new()
	sea.auto_populate = false
	scene.add_child(sea)
	sea._find_world()
	sea.populate()
	var cells := sea.life_cells
	check(cells != null, "ячейки живности созданы")
	w.set_time_of_day(12.0)
	w.set_weather(&"clear", true)
	w.set_time_paused(true)
	Settings.graphics_quality = 2
	Settings.graphics_changed.emit()
	# риф: точка с глубиной ~4 м
	var zones := sea.reef_zones()
	var best: Dictionary = {}
	for z in zones:
		if z.kind == &"atoll" and (best.is_empty() or int(z.corals) > int(best.corals)):
			best = z
	var c: Vector2 = best.center
	var spot := Vector3(c.x, 0, c.y)
	var bd := 99.0
	for i in 48:
		var a := TAU * i / 48.0
		for r: float in [0.0, 5.0, 10.0, 15.0]:
			var x := c.x + cos(a) * r
			var zz := c.y + sin(a) * r
			var d := sea.depth_at(x, zz)
			if absf(d - 4.5) < bd:
				bd = absf(d - 4.5)
				spot = Vector3(x, 0, zz)
	var fy := sea.floor_at(spot.x, spot.z)
	var cam := Camera3D.new()
	scene.add_child(cam)
	cam.current = true
	cam.global_position = Vector3(spot.x, fy + 1.6, spot.z)
	cam.look_at(Vector3(spot.x + 6.0, fy + 0.3, spot.z + 3.0))
	await wait(1.2)
	cells.refresh()
	print("[test] групп: %d, особей: %d, ячеек: %d" % [cells.groups_active, cells.instances_active, cells._cells.size()])
	check(cells._cells.size() == 9, "пузырь 3×3 ячейки на высоком: %d" % cells._cells.size())
	check(cells.groups_active > 0 and cells.instances_active > 10, "живность в пузыре: %d групп" % cells.groups_active)
	var species_seen := {}
	for k in cells._cells:
		for mi: MultiMeshInstance3D in cells._cells[k]:
			species_seen[String(mi.get_meta(&"species"))] = true
	print("[test] виды рядом: ", species_seen.keys())
	check(species_seen.size() >= 2, "несколько видов рядом: %d" % species_seen.size())
	# производительность обновления пузыря
	var t0 := Time.get_ticks_usec()
	for i in 20:
		cells.refresh()
	var us := (Time.get_ticks_usec() - t0) / 20.0
	print("[test] refresh без смены ячеек: %.0f мкс" % us)
	check(us < 3000.0, "обновление пузыря дешёвое: %.0f мкс" % us)
	await shot("reef_life")
	# уход далеко — ячейки освобождаются, группы уходят в пул
	var groups_before := cells.groups_active
	cam.global_position += Vector3(600, 0, 0)
	await get_tree().process_frame
	cells.refresh()
	var pooled := 0
	for k in cells._pool:
		pooled += (cells._pool[k] as Array).size()
	var nodes := cells.get_child_count()
	print("[test] после ухода: групп %d, в пуле %d, узлов %d (было %d)" % [cells.groups_active, pooled, nodes, groups_before])
	check(nodes == cells.groups_active + pooled, "все узлы учтены: активные + пул")
	check(nodes <= maxi(groups_before, cells.groups_active) + groups_before, "узлы переиспользуются из пула")
	cam.global_position = Vector3(spot.x, fy + 1.8, spot.z)
	cells.refresh()
	check(cells.groups_active == groups_before, "вернулся — те же группы (%d)" % cells.groups_active)

	# --- расталкивание: пловец у травы ---
	var grass := Vector3.ZERO
	for z in zones:
		var cc: Vector2 = z.center
		for i in 64:
			var a := TAU * i / 64.0
			var p := Vector3(cc.x + cos(a) * 6.0, 0, cc.y + sin(a) * 6.0)
			var d := sea.depth_at(p.x, p.z)
			if d > 1.0 and d < 3.0:
				grass = p
				break
		if grass != Vector3.ZERO:
			break
	if grass != Vector3.ZERO:
		var gy := sea.floor_at(grass.x, grass.z)
		cam.global_position = Vector3(grass.x - 2.5, gy + 1.1, grass.z - 2.5)
		cam.look_at(Vector3(grass.x, gy + 0.3, grass.z))
		await wait(0.6)
		await shot("grass_calm")
		var sw := Swimmer.new()
		scene.add_child(sw)
		sw.global_position = Vector3(grass.x, gy + 0.1, grass.z)
		await wait(0.8)
		check(SeaPush._last.size() == 4 and SeaPush._last[0].w > 0.0, "пловец передан в шейдер расталкивания")
		await shot("grass_pushed")
		sw.queue_free()

	# --- свои виды из JSON ---
	var tmp := [{"id": "test_ray", "name": "Тестовый скат", "category": "medium", "biome": ["any"],
		"depth": [0.5, 60.0], "school": [1, 2], "groups": 3.0, "anim": "ray", "length": 1.2,
		"colors": ["#556677"]}]
	var f := FileAccess.open(SeaSpecies.USER_FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(tmp))
		f.close()
		SeaSpecies.reload()
		check(SeaSpecies.all().size() == n_builtin + 1, "вид из JSON добавлен")
		check(SeaSpecies.get_species("test_ray").colors[0] is Color, "цвета из строк")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SeaSpecies.USER_FILE))
		SeaSpecies.reload()
	else:
		print("[test] JSON не записать (только чтение) — пропуск")

	# под водой с поверхности: акулы глубже 1.6 м не рисуются издали
	cam.global_position = Vector3(spot.x, sea.water_y() + 6.0, spot.z)
	await wait(0.4)
	var hidden := 0
	var deep := 0
	for s in sea.sharks:
		var dd := s.global_position.distance_to(cam.global_position)
		if dd > 30.0 and dd < 200.0 and s.global_position.y < sea.water_y() - 2.0:
			deep += 1
			if not s.visible:
				hidden += 1
	print("[test] глубоких акул рядом %d, скрыто %d" % [deep, hidden])
	check(deep == 0 or hidden == deep, "глубокие акулы над водой не рисуются")

func _vat_check() -> void:
	var root := Node3D.new()
	scene.add_child(root)
	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	root.add_child(skel)
	skel.add_bone("root")
	skel.add_bone("tail")
	skel.set_bone_parent(1, 0)
	skel.set_bone_rest(1, Transform3D(Basis(), Vector3(0, 0, 0.0)))
	skel.reset_bone_poses()
	var v := PackedVector3Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var idx := PackedInt32Array()
	var seg := 10
	for i in seg + 1:
		var z := -0.5 + float(i) / seg
		for xx: float in [-0.05, 0.05]:
			v.append(Vector3(xx, 0, z))
			var wt := clampf(z + 0.5, 0.0, 1.0)
			bones.append_array([0, 1, 0, 0])
			weights.append_array([1.0 - wt, wt, 0.0, 0.0])
	for i in seg:
		var a := i * 2
		idx.append_array([a, a + 1, a + 3, a, a + 3, a + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_BONES] = bones
	arr[Mesh.ARRAY_WEIGHTS] = weights
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	skel.add_child(mi)
	mi.skeleton = NodePath("..")
	mi.skin = skel.create_skin_from_rest_transforms()
	var ap := AnimationPlayer.new()
	root.add_child(ap)
	var lib := AnimationLibrary.new()
	var an := Animation.new()
	an.length = 1.0
	var tr := an.add_track(Animation.TYPE_ROTATION_3D)
	an.track_set_path(tr, NodePath("Skeleton3D:tail"))
	an.rotation_track_insert_key(tr, 0.0, Quaternion())
	an.rotation_track_insert_key(tr, 0.5, Quaternion(Vector3.UP, 0.8))
	an.rotation_track_insert_key(tr, 1.0, Quaternion())
	lib.add_animation(&"swim", an)
	ap.add_animation_library(&"", lib)
	await get_tree().process_frame
	var data := VatBaker.bake(root, "swim", 8)
	check(not data.is_empty(), "VAT запечён")
	if data.is_empty():
		root.queue_free()
		return
	var img := (data.texture as ImageTexture).get_image()
	var tail_i := v.size() - 1      # (0.05, 0, 0.5)
	var head_i := 0                 # (-0.05, 0, -0.5)
	var t0 := img.get_pixel(tail_i, 0)
	var t4 := img.get_pixel(tail_i, 4)
	var h4 := img.get_pixel(head_i, 4)
	print("[test] VAT смещение хвоста кадр0 (%.2f,%.2f) кадр4 (%.2f,%.2f), головы кадр4 (%.2f,%.2f)" % [t0.r, t0.b, t4.r, t4.b, h4.r, h4.b])
	var rest: PackedVector3Array = (data.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(rest[tail_i].distance_to(Vector3(0.05, 0, 0.5)) < 0.02, "меш VAT — поза кадра 0 в пространстве модели")
	check(absf(t0.r) + absf(t0.b) < 0.01 and absf(t4.r) > 0.2, "хвост в середине цикла смещён (смещения от кадра 0)")
	check(absf(h4.r) + absf(h4.b) < 0.02, "голова (вес 0 у хвоста) на месте")
	check(int(data.verts) == v.size(), "вершин: %d" % int(data.verts))
	# материал вида на VAT собирается без ошибок
	var m := ShaderMaterial.new()
	m.shader = SeaLifeCells.SHADER
	VatBaker.apply(data, m)
	check(m.get_shader_parameter(&"vat_tex") != null and float(m.get_shader_parameter(&"vat_frames")) == 8.0, "материал получил VAT")
	root.queue_free()
