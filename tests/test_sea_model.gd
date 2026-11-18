extends TestCase
## Модели акул (3 вида) на нейтральном фоне + рыбы — визуальная проверка.

func _init() -> void:
	scene_path = ""
	timeout_sec = 120.0

func run() -> void:
	var root := Node3D.new()
	add_child(root)
	var env := WorldEnvironment.new()
	env.environment = RenderProfile.make_environment()
	root.add_child(env)
	root.add_child(RenderProfile.make_sun())
	var x := -5.5
	var sharks: Array[Node3D] = []
	for sp: StringName in [&"reef", &"tiger", &"white"]:
		var m := SharkModel.build(sp)
		root.add_child(m)
		var L: float = SharkModel.SPECIES[sp]["length"]
		m.position = Vector3(x, 0.0, 0.0)
		m.rotation.y = deg_to_rad(-90.0)  # нос вправо
		sharks.append(m)
		x += L * 0.5 + 2.6
	var fish := FishSchool.new()
	fish.count = 40
	fish.radius = 1.6
	fish.center = Vector3(0.0, 2.6, -1.5)
	fish.water_level = 10.0
	root.add_child(fish)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0.5, 2.6, 9.5)
	cam.look_at(Vector3(0.5, 0.2, 0.0))
	cam.current = true
	await wait(1.0)
	check(sharks.size() == 3, "три вида акул построены")
	var body := sharks[2].get_node(^"Body") as MeshInstance3D
	check(body.mesh.get_surface_count() > 0, "у белой акулы есть меш")
	await shot("side")
	cam.position = Vector3(2.0, 6.0, 4.0)
	cam.look_at(Vector3(1.0, 0.0, 0.0))
	await wait(0.5)
	await shot("top")
	cam.position = Vector3(7.5, -1.0, 2.2)
	cam.look_at(Vector3(5.0, 0.2, 0.0))
	await wait(0.5)
	await shot("white_close")
	# всплеск и кровь крупно
	var sea := Sea.new()
	sea.auto_populate = false
	sea.underwater_fx = false
	root.add_child(sea)
	cam.position = Vector3(0.0, 1.6, 6.0)
	cam.look_at(Vector3(0.0, 0.5, 0.0))
	sea.splash(Vector3(-1.5, 0.0, 0.0), 1.2)
	sea.add_blood(Vector3(1.8, 0.0, 0.0), 20.0, true)
	await wait(0.35)
	await shot("splash")
