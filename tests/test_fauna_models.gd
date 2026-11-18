extends TestCase
## Модели всех животных на нейтральном фоне — визуальная проверка (крупно и группами).

func _init() -> void:
	scene_path = ""
	timeout_sec = 600.0

var root: Node3D
var cam: Camera3D
var models := {}

func _place(sp: StringName, pos: Vector3, yaw_deg: float = -90.0) -> Node3D:
	var m := AnimalModels.build(sp)
	root.add_child(m)
	m.position = pos
	m.rotation.y = deg_to_rad(yaw_deg)
	models[sp] = m
	return m

func _look(from: Vector3, at: Vector3, fov: float = 50.0) -> void:
	cam.position = from
	cam.look_at(at)
	cam.fov = fov

func run() -> void:
	root = Node3D.new()
	add_child(root)
	var env := WorldEnvironment.new()
	env.environment = RenderProfile.make_environment()
	root.add_child(env)
	root.add_child(RenderProfile.make_sun())
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.78, 0.7, 0.52)
	gm.roughness = 1.0
	ground.material_override = gm
	root.add_child(ground)
	cam = Camera3D.new()
	root.add_child(cam)
	cam.current = true
	# крупные
	_place(&"croc", Vector3(-2.0, 0, -3.0))
	_place(&"boar", Vector3(2.6, 0, -3.0))
	_place(&"turtle", Vector3(5.2, 0, -3.0))
	# средние
	_place(&"monkey", Vector3(-3.0, 0, 0.0))
	_place(&"iguana", Vector3(-1.0, 0, 0.0))
	_place(&"monitor", Vector3(1.4, 0, 0.0))
	_place(&"snake", Vector3(3.8, 0, 0.0))
	# мелкие
	_place(&"crab", Vector3(-1.2, 0, 2.0))
	_place(&"scorpion", Vector3(-0.6, 0, 2.0))
	_place(&"spider", Vector3(-0.1, 0, 2.0))
	# птицы
	var p := _place(&"parrot", Vector3(0.7, 0.9, 2.0))
	var g := _place(&"gull", Vector3(1.6, 0.9, 2.0))
	var b := _place(&"bat", Vector3(2.4, 0.9, 2.0))
	for m: Node3D in [p, g, b]:
		for w in (m.get_meta(&"wings") as Array):
			((w as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter(&"flap", 0.35)
	await wait(0.5)
	check(models.size() == 13, "13 видов построены")
	for sp in models.keys():
		var m: Node3D = models[sp]
		check(m.get_node_or_null(^"Body") != null or m.get_node_or_null(^"Rig/Body") != null, "%s: есть тело" % sp)
	check((models[&"boar"].get_meta(&"legs") as Array).size() == 4, "у кабана 4 ноги")
	check((models[&"spider"].get_meta(&"legs") as Array).size() == 8, "у паука 8 ног")
	var crab_legs := 8 if not UserCrabRig.available() else 6   # краб из пака: 3 пары ходильных ног
	check((models[&"crab"].get_meta(&"legs") as Array).size() == crab_legs + 2, "у краба %d ног + 2 клешни" % crab_legs)
	_look(Vector3(1.2, 5.5, 10.0), Vector3(1.2, 0.2, -0.5))
	await wait(0.3)
	await shot("overview")
	_look(Vector3(1.0, 1.6, 2.0), Vector3(1.0, 0.4, -3.0), 55.0)
	await wait(0.3)
	await shot("large")
	_look(Vector3(0.2, 1.1, 3.4), Vector3(0.2, 0.15, 0.0), 50.0)
	await wait(0.3)
	await shot("medium")
	_look(Vector3(0.6, 0.6, 3.3), Vector3(0.6, 0.35, 2.0), 50.0)
	await wait(0.3)
	await shot("small_birds")
	_look(Vector3(-2.6, 0.9, -1.3), Vector3(-2.0, 0.25, -3.0), 50.0)
	await wait(0.3)
	await shot("croc_head")
	_look(Vector3(3.7, 0.9, -1.6), Vector3(2.7, 0.55, -3.0), 50.0)
	await wait(0.3)
	await shot("boar_close")
