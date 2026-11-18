extends TestCase
## Пак моделей пользователя на полигоне: зона «Пак моделей» собрана, нормализованные
## акула и пальма загружаются в бюджете, акула анимирована, водоросли расталкиваются.
## Скриншоты: зона, акула крупно, живая акула в море, водоросли под водой.

var sb: Sandbox

func _init() -> void:
	scene_path = "res://scenes/sandbox/sandbox.tscn"
	timeout_sec = 3500.0

func run() -> void:
	Engine.max_physics_steps_per_frame = 30
	# бюджеты моделей
	for e in [["res://assets/user_pack/animals/animal_shark_great_white.glb", 12000],
			["res://assets/user_pack/trees/tree_palm_coconut_user.glb", 12000]]:
		var ps := load(e[0]) as PackedScene
		check(ps != null, "загружается %s" % e[0].get_file())
		if ps:
			var n := ps.instantiate()
			var tris := 0
			var surfs := 0
			for mi in n.find_children("*", "MeshInstance3D", true, false):
				var m: Mesh = (mi as MeshInstance3D).mesh
				surfs += m.get_surface_count()
				for s in m.get_surface_count():
					tris += (m.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			check(tris <= int(e[1]), "%s: %d треуг. ≤ %d, поверхностей %d" % [e[0].get_file(), tris, e[1], surfs])
			n.free()
	sb = scene as Sandbox
	var t0 := Time.get_ticks_msec()
	while not sb.is_built and Time.get_ticks_msec() - t0 < 1200000:
		await wait(0.5)
	check(sb.is_built, "полигон собран")
	if not sb.is_built:
		return
	var z := sb.zones
	for id in [&"pack", &"pack_shark", &"pack_seaweed"]:
		check(z.points.has(id), "есть точка перемещения: %s" % id)
	var c: Vector2 = SandboxZones.ZONES[&"pack"].c
	var g := SandboxProps.ground(c.x, c.y)
	check(g > 0.3, "зона «Пак моделей» на суше (%.1f м)" % g)
	# акула-экспонат анимирована
	var aps := get_tree().root.find_children("*", "AnimationPlayer", true, false)
	var playing := 0
	for ap in aps:
		if (ap as AnimationPlayer).is_playing() and String((ap as AnimationPlayer).current_animation).contains("swim"):
			playing += 1
	check(playing >= 2, "акулы из пака плывут (анимаций swim: %d)" % playing)
	sb.panel.go(&"pack")
	await wait(2.5)
	await shot("01_zone")
	# крупно экспонат акулы
	var sx := c.x + 12.0
	var sz := c.y - 2.0
	sb.cheats.teleport(Vector3(sx - 4.5, SandboxProps.ground(sx - 4.5, sz + 3.0) + 0.2, sz + 3.0), Vector3(sx, SandboxProps.ground(sx, sz) + 1.8, sz))
	await wait(1.5)
	await shot("02_shark_exhibit")
	sb.cheats.teleport(Vector3(c.x, SandboxProps.ground(c.x, c.y - 4.0) + 0.2, c.y - 4.0), Vector3(c.x, SandboxProps.ground(c.x, c.y + 6.0) + 5.0, c.y + 6.0))
	await wait(1.5)
	await shot("03_palms")
	# краб из пака в загоне (скелет + IK)
	check(z.points.has(&"pack_crab"), "есть точка перемещения: pack_crab")
	if z.points.has(&"pack_crab"):
		sb.panel.go(&"pack_crab")
		await wait(2.0)
		await shot("07_crab")
	# под водой: полёт, чтобы не всплывать
	sb.cheats.set_fly(true)
	sb.panel.go(&"pack_shark")
	await wait(3.0)
	await shot("04_shark_sea")
	var vat := get_tree().root.find_child("PackVatSharks", true, false) as MultiMeshInstance3D
	check(vat != null and vat.multimesh.instance_count == 12, "стая акул на VAT: 12 экземпляров, один MultiMesh")
	check(z.points.has(&"pack_vat"), "есть точка перемещения: pack_vat")
	sb.panel.go(&"pack_vat")
	await wait(2.5)
	await shot("06_vat_school")
	sb.cheats.set_fly(false)
	# водоросли: пловец рядом — материал получает его позицию
	sb.panel.go(&"pack_seaweed")
	await wait(2.0)
	await shot("05_seaweed")
	var mat := SandboxPack.seaweed_mat
	check(mat != null, "материал водорослей создан")
	if mat:
		var pp = mat.get_shader_parameter(&"push_pos")
		var active := false
		if pp is PackedVector4Array:
			for v in pp:
				if v.w > 0.0:
					active = true
		check(active, "водоросли знают позицию пловца (расталкивание)")
