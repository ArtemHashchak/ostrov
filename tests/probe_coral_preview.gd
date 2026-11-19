extends TestCase
## Быстрый просмотр кораллов пака (для итераций формы): каждый вариант крупно на тёмно-синем фоне
## (как у референса) — косой вид и вид сверху. Типы: переменная окружения CORAL_TYPES (через запятую),
## уровень — CORAL_LOD (0 по умолчанию). Скриншоты: tests/shots/probe_coral_preview_<тип>_v<n>_<вид>.png

func _init() -> void:
	scene_path = ""
	timeout_sec = 3000.0

var cam: Camera3D

func run() -> void:
	var only := OS.get_environment("CORAL_TYPES")
	var lod := int(OS.get_environment("CORAL_LOD")) if OS.get_environment("CORAL_LOD") != "" else 0
	var root := Node3D.new()
	add_child(root)
	var env := WorldEnvironment.new()
	env.environment = RenderProfile.make_environment()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#1B2C5C")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("#8FA6D8")
	env.environment.ambient_light_energy = 0.55
	env.environment.fog_enabled = false
	root.add_child(env)
	root.add_child(RenderProfile.make_sun())
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("#22366A")
	gm.roughness = 1.0
	ground.material_override = gm
	root.add_child(ground)
	cam = Camera3D.new()
	cam.fov = 45.0
	root.add_child(cam)
	cam.current = true
	var holder := Node3D.new()
	root.add_child(holder)
	for t in CoralPack.TYPES.keys():
		if only != "" and not (String(t) in only.split(",")):
			continue
		for v in CoralPack.variants(t):
			for c in holder.get_children():
				c.free()
			var m := CoralPack.mesh(t, v, lod)
			if m == null:
				continue
			var mi := MeshInstance3D.new()
			mi.mesh = m
			mi.material_override = CoralPack.material(t, -100.0, lod)
			holder.add_child(mi)
			print("[test] %s v%d lod%d: %d треуг." % [t, v, lod, CoralPack.tri_count(m)])
			var aabb := m.get_aabb()
			var size := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
			var c := aabb.get_center()
			cam.position = c + Vector3(0.0, size * 0.55, size * 1.2)
			cam.look_at(c, Vector3.UP)
			await wait_frames(4)
			await shot("%s_v%d_l%d_side" % [t, v, lod])
			cam.position = c + Vector3(0.0, size * 1.35, size * 0.25)
			cam.look_at(c, Vector3.UP)
			await wait_frames(3)
			await shot("%s_v%d_l%d_top" % [t, v, lod])
