extends TestCase
## Паук-птицеед пользователя (UserSpiderRig): скелет автора, IK-ноги (стопы на земле в покое,
## шаг тетраподами), дыбы с поднятыми передними ногами, укус, подъём по стволу, сидение на стволе,
## прыжок вниз и приземление, смерть. Снимки (--shots): tests/shots/test_user_spider_*.png.

func _init() -> void:
	scene_path = ""
	timeout_sec = 1200.0

class Dummy extends Node3D:
	var hp: float = 100.0
	var hits: int = 0
	func apply_damage(amount: float, _src: Node = null, _kind: StringName = &"") -> void:
		hp -= amount
		hits += 1
	func is_dead() -> bool:
		return false

var root: Node3D
var cam: Camera3D
var dummy: Dummy

func _run(a: Animal, sec: float, keep_state: bool = true) -> void:
	var t := 0.0
	while t < sec:
		var dt := 1.0 / 30.0
		if keep_state:
			a._think_t = 9999.0
		a.tick(dt)
		await wait_frames(1)
		t += dt

func _look(from: Vector3, at: Vector3, fov: float = 40.0) -> void:
	cam.global_position = from
	cam.look_at(at)
	cam.fov = fov

## Сбоку по ходу животного (справа-спереди).
func _side(a: Animal, d: float = 0.45, h: float = 0.18, ahead: float = 0.25) -> void:
	var b := a.global_transform.basis
	var c := a.global_position + Vector3(0, 0.04, 0)
	_look(c + b.x * d - b.z * d * ahead + Vector3(0, h, 0), c, 40.0)

func _foot_y(r: UserSpiderRig, l: Dictionary) -> float:
	var bones: Array[int] = l["bones"]
	var pts: Array[Vector3] = l["pts"]
	var g := r.skel.get_bone_global_pose(bones[4])
	var rg := r.skel.get_bone_global_rest(bones[4])
	var tip := g.origin + (g.basis * rg.basis.inverse()) * (pts[5] - pts[4])
	return (r.skel.global_transform * tip).y

func run() -> void:
	check(UserSpiderRig.spider_available(), "модель паука-птицееда в проекте")
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
	gm.albedo_color = Color(0.6, 0.55, 0.42)
	gm.roughness = 1.0
	ground.material_override = gm
	root.add_child(ground)
	cam = Camera3D.new()
	root.add_child(cam)
	cam.current = true
	dummy = Dummy.new()
	root.add_child(dummy)
	dummy.add_to_group(&"characters")
	dummy.position = Vector3(40, 0, 40)
	# ствол для лазанья
	var trunk := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.12
	cm.bottom_radius = 0.16
	cm.height = 3.0
	trunk.mesh = cm
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.35, 0.27, 0.2)
	trunk.material_override = tm
	root.add_child(trunk)
	trunk.position = Vector3(1.2, 1.5, -1.0)

	var a := Animal.create(&"spider", Vector3.ZERO)
	root.add_child(a)
	a.heading = 0.0
	a._think_t = 9999.0
	var r := a.anim_ctrl as UserSpiderRig
	check(r != null, "паук — модель пака (UserSpiderRig)")
	if r == null:
		return
	check(r.skel.get_bone_count() >= 60, "скелет автора (%d костей)" % r.skel.get_bone_count())
	check(r.legs.size() == 8, "8 ног на IK")
	await _run(a, 0.6)
	var mx := 0.0
	for l: Dictionary in r.legs:
		mx = maxf(mx, absf(_foot_y(r, l)))
	check(mx < 0.012, "в покое лапки на земле (макс. %.3f м)" % mx)
	_side(a)
	await shot("idle")
	_look(Vector3(0.0, 0.55, -0.35), Vector3(0, 0.0, 0.0), 40.0)
	await shot("idle_top")
	# ходьба
	a.move_to = Vector3(0, 0, -30)
	a._set_state(&"wander")
	await _run(a, 1.2)
	check(a.speed > 0.1, "идёт (%.2f м/с)" % a.speed)
	var lifted := 0
	for l: Dictionary in r.legs:
		if _foot_y(r, l) > 0.006:
			lifted += 1
	check(lifted >= 1 and lifted <= 6, "часть ног в переносе (%d)" % lifted)
	_side(a)
	await shot("walk")
	# угроза — дыбы
	a.speed = 0.0
	a._set_state(&"warn")
	a.target = dummy
	a._warn_t = 99.0
	dummy.position = a.global_position + Vector3(0, 0, -1.0)
	await _run(a, 1.0)
	var front_up := (_foot_y(r, r.legs[0]) + _foot_y(r, r.legs[1])) * 0.5
	check(front_up > 0.03, "на дыбах передние ноги подняты (%.3f м)" % front_up)
	_side(a, 0.5, 0.12, 0.6)
	await shot("threat")
	a.anim_event(&"attack")
	await _run(a, 0.12)
	_side(a, 0.4, 0.08, 0.9)
	await shot("bite")
	await _run(a, 0.6)
	dummy.position = Vector3(40, 0, 40)
	a.target = null
	a._set_state(&"idle")
	await _run(a, 0.5)
	# лазанье: столб рядом
	a.climb_post = Vector4(trunk.position.x, 0.0, trunk.position.z, 0.14)
	check(a._find_trunk(), "нашёл ствол")
	a._tree_h = 1.4
	a._set_state(&"to_tree")
	var t := 0.0
	while t < 20.0 and a.state != &"on_tree":
		a._think_t = 9999.0
		a.tick(1.0 / 30.0)
		await wait_frames(1)
		t += 1.0 / 30.0
		if a.state == &"climb" and a._climb_y > 0.5 and a._climb_y < 0.6:
			_look(a.global_position + a._tree_out * 0.8 + a.global_transform.basis.x * 0.5 + Vector3(0, 0.1, 0), a.global_position, 40.0)
			await shot("climb")
	check(a.state == &"on_tree", "взобрался на ствол (%s, %.2f м)" % [a.state, a._climb_y])
	check(a.global_position.y > 1.2, "сидит на высоте %.2f м" % a.global_position.y)
	check(absf(a._model.rotation.x - PI * 0.5) < 0.2, "головой вверх по стволу (наклон %.2f)" % a._model.rotation.x)
	await _run(a, 0.5)
	_look(a.global_position + a._tree_out * 0.9 + Vector3(0.3, 0.2, 0), a.global_position, 40.0)
	await shot("on_tree")
	# человек подошёл — прыгает на него
	dummy.position = Vector3(trunk.position.x, 0.0, trunk.position.z) + a._tree_out * 1.6
	var hits0 := dummy.hits
	a._think_t = 0.0
	var jumped := false
	var air_shot := false
	t = 0.0
	while t < 6.0:
		a.tick(1.0 / 30.0)
		await wait_frames(1)
		t += 1.0 / 30.0
		if a.state == &"jump":
			jumped = true
			if not air_shot and a._jump_v.y < 0.3:
				air_shot = true
				_look(a.global_position + a.global_transform.basis.x * 0.9 + Vector3(0, 0.1, 0), a.global_position, 45.0)
				await shot("jump")
		elif jumped and a.state != &"jump":
			break
	check(jumped, "спрыгнул со ствола")
	check(a.global_position.y < 0.05, "приземлился (y %.2f)" % a.global_position.y)
	check(dummy.hits > hits0, "укусил при приземлении рядом с человеком")
	_side(a)
	await shot("landed")
	# смерть
	dummy.position = Vector3(40, 0, 40)
	a.apply_damage(999.0, null)
	await _run(a, 2.0, false)
	check(a.dead, "погиб")
	_look(a.global_position + Vector3(0.35, 0.3, 0.2), a.global_position, 40.0)
	await shot("dead")
