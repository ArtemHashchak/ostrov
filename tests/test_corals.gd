extends TestCase
## Кораллы по референсу пользователя (CoralPack, docs/CORALS_REF.md): все виды и варианты
## загружаются, LOD0/LOD1 в бюджете, материал с качанием у мягких; скриншоты каждого вида
## крупно (на песке и под водой) и общий «риф» из всех видов. Риф в море — test_sea_reef.

func _init() -> void:
	scene_path = ""
	timeout_sec = 2400.0

var root: Node3D
var cam: Camera3D

## LOD0 вместе с карточками: обычные ≤ ~3k, «герои» (столовая, кустовая, актиния) ≤ ~4.2k.
const BUDGET0 := {&"table": 4000, &"staghorn": 4200, &"corymbose": 3000, &"lobed": 3000, &"foliose": 3000,
	&"antler": 3000, &"softcoral": 3000, &"leather": 3000, &"anemone": 4000, &"bubble": 3000, &"crinoid": 3000,
	&"mound": 900, &"millepora": 3000}

func run() -> void:
	check(CoralPack.available(), "кораллы пака загружаются из %s" % CoralPack.GLB)
	if not CoralPack.available():
		return
	var total := 0
	for t in CoralPack.TYPES.keys():
		for v in CoralPack.variants(t):
			var m0 := CoralPack.mesh(t, v, 0)
			var m1 := CoralPack.mesh(t, v, 1)
			var m2 := CoralPack.mesh(t, v, 2)
			check(m0 != null and m1 != null and m2 != null, "%s v%d: есть LOD0, LOD1, LOD2" % [t, v])
			if m0 == null or m1 == null or m2 == null:
				continue
			var a := CoralPack.tri_count(m0)
			var b := CoralPack.tri_count(m1)
			var c2 := CoralPack.tri_count(m2)
			total += 1
			check(a <= int(BUDGET0[t]) and b < a and c2 < b, "%s v%d: %d / %d / %d треуг. (бюджет LOD0 %d)" % [t, v, a, b, c2, int(BUDGET0[t])])
			var arr := m0.surface_get_arrays(0)
			check((arr[Mesh.ARRAY_COLOR] as PackedColorArray).size() > 0, "%s v%d: есть цвет вершин" % [t, v])
	print("[test] видов×вариантов: %d" % total)
	check(CoralPack.material(&"anemone", 0.0, 0).get_shader_parameter(&"sway") > 0.0, "актиния качается")
	check(is_zero_approx(float(CoralPack.material(&"table", 0.0, 0).get_shader_parameter(&"sway"))), "столовая не качается")

	root = Node3D.new()
	add_child(root)
	var env := WorldEnvironment.new()
	env.environment = RenderProfile.make_environment()
	# фон как у референса: тёмно-синяя студия
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
	cam.fov = 50.0
	root.add_child(cam)
	cam.current = true
	await wait_frames(3)

	# ---------- каждый вид крупно (на песке, как витрина) ----------
	var holder := Node3D.new()
	root.add_child(holder)
	for t in CoralPack.TYPES.keys():
		for v in CoralPack.variants(t):
			for c in holder.get_children():
				c.free()
			var tint := CoralPack.pick_tint(t, _rng(v))
			# оттенок экземпляра — через MultiMesh из одного экземпляра (как на рифе)
			var mmi := _one(t, v, tint, -100.0)
			holder.add_child(mmi)
			var aabb := CoralPack.mesh(t, v, 0).get_aabb()
			var size := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
			var c := aabb.get_center()
			cam.position = c + Vector3(0.0, size * 0.55, size * 1.25)
			cam.look_at(c, Vector3.UP)
			await wait_frames(4)
			await shot("%s_v%d" % [t, v])

	# ---------- общий риф (все виды вперемешку), вид сверху-сбоку и «под водой» ----------
	for c in holder.get_children():
		c.free()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var items: Array = []
	for t in CoralPack.TYPES.keys():
		for v in CoralPack.variants(t):
			items.append([t, v])
	for n in 120:
		var it: Array = items[rng.randi() % items.size()]
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 7.0
		var d: Dictionary = CoralPack.TYPES[it[0]]
		var s := rng.randf_range(float(d.smin), float(d.smax))
		var m := _one(it[0], it[1], CoralPack.pick_tint(it[0], rng), 4.0)
		m.transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(cos(a) * r, 0.0, sin(a) * r))
		holder.add_child(m)
	cam.position = Vector3(0, 3.2, 9.5)
	cam.look_at(Vector3(0, 0.4, 0), Vector3.UP)
	await wait(1.0)
	await shot("reef_side")
	cam.position = Vector3(2.0, 1.2, 4.5)
	cam.look_at(Vector3(-0.5, 0.5, 0), Vector3.UP)
	await wait(0.6)
	await shot("reef_close")
	cam.position = Vector3(0, 9.0, 6.0)
	cam.look_at(Vector3(0, 0, 0), Vector3.UP)
	await wait(0.6)
	await shot("reef_top")


func _rng(v: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 10 + v
	return r


func _one(t: StringName, v: int, tint: Color, water: float) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true
	mm.mesh = CoralPack.mesh(t, v, 0)
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D.IDENTITY)
	mm.set_instance_custom_data(0, tint)
	mm.set_instance_color(0, Color(1, 1, 1, 1))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = CoralPack.material(t, water, 0)
	return mmi
