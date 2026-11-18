extends TestCase
## Анимация кабана, обезьяны, птиц и летучей мыши: последовательности кадров.
## Мир — простая заглушка: ровная земля, справа пруд (вода 0, дно −1.3), одно «дерево».

func _init() -> void:
	scene_path = ""
	timeout_sec = 1500.0

const WORLD_SRC := """extends Node3D
var night := false
func height_at(x: float, z: float) -> float:
	if x > 9.0:
		return -1.3
	if x > 7.0:
		return lerpf(0.0, -1.3, (x - 7.0) / 2.0)
	return 0.02 * sin(x * 0.7) + 0.02 * cos(z * 0.9)
func water_level() -> float:
	return -0.15
func is_night() -> bool:
	return night
func biome_at(x: float, z: float) -> StringName:
	return &"jungle"
"""
const TREE_SRC := """extends Node3D
var felled := false
"""

var root: Node3D
var cam: Camera3D
var fauna: Fauna
var dummy: Node3D
var world: Node3D

func _look(from: Vector3, at: Vector3, fov: float = 45.0) -> void:
	cam.global_position = from
	cam.look_at(at)
	cam.fov = fov

func _seq(prefix: String, n: int, step: float) -> void:
	for i in n:
		await wait(step)
		await shot("%s_%d" % [prefix, i])

func _hip_angles(a: Animal) -> Array:
	var out := []
	for l in (a._model.get_meta(&"legs") as Array):
		out.append((l as Node3D).rotation.x)
	return out

func run() -> void:
	root = Node3D.new()
	add_child(root)
	var ws := GDScript.new()
	ws.source_code = WORLD_SRC
	ws.reload()
	world = Node3D.new()
	world.set_script(ws)
	world.add_to_group(&"world")
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = RenderProfile.make_environment()
	root.add_child(env)
	root.add_child(RenderProfile.make_sun())
	# земля и пруд
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(16, 40)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.45, 0.4, 0.28)
	gm.roughness = 1.0
	ground.material_override = gm
	ground.position = Vector3(-1.0, 0.0, 0.0)
	root.add_child(ground)
	var water := MeshInstance3D.new()
	var wp := PlaneMesh.new()
	wp.size = Vector2(14, 40)
	water.mesh = wp
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.1, 0.35, 0.42, 0.75)
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.roughness = 0.1
	water.material_override = wmat
	water.position = Vector3(14.0, -0.15, 0.0)
	root.add_child(water)
	# «дерево» для ночёвки летучих мышей
	var ts := GDScript.new()
	ts.source_code = TREE_SRC
	ts.reload()
	var tree := Node3D.new()
	tree.set_script(ts)
	tree.add_to_group(&"trees")
	tree.position = Vector3(-4.0, 0.0, 8.0)
	root.add_child(tree)
	var trunk := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.15
	cyl.bottom_radius = 0.22
	cyl.height = 7.0
	trunk.mesh = cyl
	trunk.position = Vector3(0, 3.5, 0)
	tree.add_child(trunk)
	var crown := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 1.2
	cm.height = 1.0
	crown.mesh = cm
	var crm := StandardMaterial3D.new()
	crm.albedo_color = Color(0.15, 0.35, 0.12)
	crown.material_override = crm
	crown.position = Vector3(0, 7.2, 0)
	tree.add_child(crown)
	cam = Camera3D.new()
	root.add_child(cam)
	cam.current = true
	dummy = Node3D.new()
	dummy.name = "Dummy"
	dummy.add_to_group(&"characters")
	root.add_child(dummy)
	dummy.global_position = Vector3(0, 0, 60)
	fauna = (load("res://scenes/fauna/fauna.tscn") as PackedScene).instantiate() as Fauna
	fauna.auto_populate = false
	root.add_child(fauna)
	await wait(0.3)
	check(fauna.world == world, "фауна видит мир-заглушку")
	await _boar_tests()
	await _monkey_tests()
	await _bird_tests()
	await _bat_tests()

# ------------------------------------------------------------------
func _boar_tests() -> void:
	var b := fauna.spawn(&"boar", Vector3(0, 0, 0), 30.0)
	await wait(0.1)
	check(b.anim_ctl != null, "у кабана свой контроллер анимации")
	check(b._model.has_meta(&"rig"), "кабан: модель-риг")
	check(b._model.get_node_or_null(^"Body") != null, "кабан: узел Body")
	# шаг: вдоль оси X, камера сбоку
	b.global_position = Vector3(-5, 0, 0)
	b.heading = -PI * 0.5   # нос в +X
	b.move_to = Vector3(6, 0, 0)
	b._set_state(&"wander")
	var a0 := _hip_angles(b)
	_look(Vector3(-2.5, 0.7, 3.6), Vector3(-2.5, 0.45, 0.0))
	await wait(0.6)
	var a1 := _hip_angles(b)
	check(a0 != a1, "кабан: ноги двигаются при ходьбе")
	cam.global_position = Vector3(b.global_position.x + 0.3, 0.7, 3.4)
	await _seq("boar_walk", 4, 0.13)
	# галоп: убегает от «игрока»
	b.global_position = Vector3(-6, 0, 0)
	b.heading = -PI * 0.5
	dummy.global_position = Vector3(-12, 0, 0)
	b.target = dummy
	b._set_state(&"flee")
	await wait(1.0)
	print("[test] boar flee speed=", b.speed)
	check(b.speed > 4.3, "кабан разогнался до галопа (%.1f)" % b.speed)
	for i in 4:
		_look(b.global_position + Vector3(0.2, 0.6, 3.6), b.global_position + Vector3(0, 0.45, 0))
		await wait(0.06)
		await shot("boar_gallop_%d" % i)
	dummy.global_position = Vector3(0, 0, 60)
	b.target = null
	# рыло в землю, потом лёг
	b.global_position = Vector3(0, 0, 0)
	b.speed = 0.0
	b._set_state(&"idle")
	b._think_t = 999.0
	_look(Vector3(-1.4, 0.8, 2.4), Vector3(-0.3, 0.35, 0))
	await wait(2.0)
	await shot("boar_rooting")
	b.state_t = 7.5
	await wait(1.6)
	await shot("boar_lying")
	# атака: бросок с ударом клыками
	b._set_state(&"idle")
	b.state_t = 0.0
	await wait(0.6)
	b._attack_cd = float(b.cfg["cd"])
	await wait(0.05)
	check(float(b.anim_state.get("toss", 0.0)) > 0.0, "кабан: удар клыками запущен")
	await _seq("boar_toss", 3, 0.08)
	b._think_t = 0.0
	# плавание
	b.global_position = Vector3(11, -1.3, 0)
	b.heading = -PI * 0.5
	b.move_to = Vector3(14, -1.3, 0)
	b._set_state(&"to_water")
	_look(Vector3(11.5, 0.6, 3.0), Vector3(11.5, -0.2, 0))
	await wait(1.2)
	check(float(b.anim_state.get("swim", 0.0)) > 0.8, "кабан плывёт (спина у поверхности)")
	await _seq("boar_swim", 2, 0.15)
	# смерть
	b.global_position = Vector3(0, 0, 0)
	b._set_state(&"idle")
	await wait(0.4)
	b.die(null)
	_look(Vector3(0.3, 1.0, 2.6), Vector3(0, 0.25, 0))
	await wait(0.3)
	await shot("boar_dying")
	await wait(2.0)
	await shot("boar_dead")
	var body: Node3D = b._model.get_meta(&"rig")["body"]
	check(body.position.x > 0.15, "мёртвый кабан лёг на бок, а не в землю")
	b.queue_free()

# ------------------------------------------------------------------
func _monkey_tests() -> void:
	var m := fauna.spawn(&"monkey", Vector3(-4, 0, 0), 30.0)
	await wait(0.1)
	check(m.anim_ctl != null, "у обезьяны свой контроллер анимации")
	m.heading = -PI * 0.5
	m.move_to = Vector3(6, 0, 0)
	m._set_state(&"wander")
	m._think_t = 999.0
	await wait(0.6)
	for i in 4:
		_look(m.global_position + Vector3(0.1, 0.55, 2.2), m.global_position + Vector3(0, 0.35, 0))
		await wait(0.1)
		await shot("monkey_walk_%d" % i)
	# сидит и чешется
	m.speed = 0.0
	m._set_state(&"idle")
	m.global_position = Vector3(0, 0, -3)
	m.anim_state["scratch_cd"] = 0.8
	_look(Vector3(0.9, 0.7, -1.4), Vector3(0, 0.35, -3))
	await wait(1.8)
	await shot("monkey_sit_scratch")
	check(float(m.anim_state.get("rest", 0.0)) > 0.8, "обезьяна села")
	# бежит с добычей
	m.stolen = [{"id": &"banana", "n": 1}]
	m.global_position = Vector3(-6, 0, -3)
	m.heading = -PI * 0.5
	m.move_to = Vector3(8, 0, -3)
	m.set_meta(&"steal_phase", &"escape")
	m._set_state(&"steal")
	await wait(0.8)
	var hand: Node3D = m._model.get_meta(&"rig")["hand"]
	check(hand.get_node_or_null(^"Loot") != null and (hand.get_node(^"Loot") as Node3D).visible, "добыча в руке")
	for i in 3:
		_look(m.global_position + Vector3(0.2, 0.6, 2.4), m.global_position + Vector3(0, 0.35, 0))
		await wait(0.07)
		await shot("monkey_steal_%d" % i)
	m.stolen.clear()
	# залезает на дерево и бросает орех в «игрока»
	m.global_position = Vector3(-3.4, 0, 8.0)
	m.heading = 0.0
	m.speed = 0.0
	m._set_state(&"perch")
	m.anim_state["throw_cd"] = 99.0
	_look(Vector3(-0.8, 2.2, 10.5), Vector3(-3.4, 1.9, 8.0), 55.0)
	await wait(1.0)
	await shot("monkey_climb")
	await wait(2.0)
	check(float(m.anim_state.get("climb", 0.0)) >= 0.99, "обезьяна забралась наверх")
	await shot("monkey_on_tree")
	dummy.global_position = Vector3(-3.4, 0, 14.0)
	m.anim_state["throw_cd"] = 0.0
	await wait(0.45)
	await shot("monkey_throw")
	await wait(0.6)
	check(m.anim_state.get("thrown", false) == true, "обезьяна бросила орех")
	dummy.global_position = Vector3(0, 0, 60)
	m.queue_free()

# ------------------------------------------------------------------
func _bird_tests() -> void:
	var fl := fauna.spawn_flock(&"parrot", Vector3(0, 0, -6), 4, 8.0)
	var g := fauna.spawn_flock(&"gull", Vector3(4, 0, -8), 3, 8.0)
	await wait(0.2)
	check(fl[0].anim_ctl != null, "у попугая свой контроллер анимации")
	var p: Animal = fl[0]
	for i in 4:
		_look(p.global_position + Vector3(0.3, 0.3, 2.0), p.global_position)
		await wait(0.035)
		await shot("parrot_fly_%d" % i)
	var gl: Animal = g[0]
	await wait(1.5)
	for i in 2:
		_look(gl.global_position + Vector3(0.0, 0.6, 2.6), gl.global_position)
		await wait(0.1)
		await shot("gull_fly_%d" % i)
	# стая садится на землю (в заглушке нет кроны с variant — садятся на точку)
	var flock: Dictionary = p.flock
	flock["perch"] = Vector3(1.0, 0.08, -4.0)
	flock["mode"] = &"perch"
	flock["t"] = 60.0
	_look(Vector3(1.5, 0.6, -2.6), Vector3(1.0, 0.1, -4.0))
	var landed := false
	for k in 40:
		await wait(0.15)
		if k == 6:
			await shot("parrot_landing")
		if p.state == &"perch" and float(p.anim_state.get("fold", 0.0)) > 0.9:
			landed = true
			break
	check(landed, "попугай сел и сложил крылья")
	await wait(0.8)
	await shot("parrot_perched")
	p.anim_state["preen_cd"] = 0.0
	await wait(0.5)
	await shot("parrot_preen")
	for a in fl + g:
		a.queue_free()

# ------------------------------------------------------------------
func _bat_tests() -> void:
	fauna.force_night_birds = true
	var bats := fauna.spawn_flock(&"bat", Vector3(-4, 0, 4), 4, 6.0)
	await wait(0.6)
	var bt: Animal = bats[0]
	for i in 3:
		_look(bt.global_position + Vector3(0.0, 0.15, 0.9), bt.global_position)
		await wait(0.03)
		await shot("bat_fly_%d" % i)
	# день: висят под кроной вниз головой
	fauna.force_night_birds = false
	await wait(0.6)
	check(bt.state == &"roost" and bt.visible, "днём летучая мышь висит на дереве")
	var top := Vector3(-4.0, 7.0, 8.0)
	_look(top + Vector3(0.6, -0.9, 1.6), bt.global_position, 50.0)
	await wait(0.5)
	await shot("bat_roost")
	for a in bats:
		a.queue_free()
