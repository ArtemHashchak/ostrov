extends TestCase
## Краб из пака пользователя (скелет + IK): покой, ходьба боком с качанием клешней, бег, угроза,
## щипок с уроном, кормёжка, закапывание, смерть. Серии кадров → tests/shots/test_user_crab_*.png.

func _init() -> void:
	scene_path = ""
	timeout_sec = 3000.0

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

func _mk(sp: StringName, pos: Vector3) -> Animal:
	var a := Animal.create(sp, pos)
	root.add_child(a)
	a.heading = 0.0
	a.rotation.y = 0.0
	a._think_t = 9999.0
	return a

func _run(animals: Array, sec: float, keep_state: bool = true) -> void:
	var t := 0.0
	while t < sec:
		var dt := 1.0 / 30.0
		for a: Animal in animals:
			if keep_state:
				a._think_t = 9999.0
			a.tick(dt)
		await get_tree().process_frame
		t += dt

func _look(from: Vector3, at: Vector3, fov: float = 40.0) -> void:
	cam.global_position = from
	cam.look_at(at)
	cam.fov = fov

func _follow(a: Node3D, off: Vector3, fov: float = 40.0) -> void:
	_look(a.global_position + off, a.global_position + Vector3(0, 0.15, 0), fov)

## Мировая точка кончика последней кости ноги.
func _foot(r: UserCrabRig, l: Dictionary) -> Vector3:
	var bones: Array[int] = l["bones"]
	var pts: Array[Vector3] = l["pts"]
	var bi := bones[3]
	var g := r.skel.get_bone_global_pose(bi)
	var rg := r.skel.get_bone_global_rest(bi)
	var tip := g.origin + (g.basis * rg.basis.inverse()) * (pts[4] - pts[3])
	return r.skel.global_transform * tip

func _finger_open(r: UserCrabRig, side: int) -> float:
	var c: Dictionary = r.claws[side]
	return float(c["open"])

func run() -> void:
	check(UserCrabRig.available(), "модель краба из пака есть в проекте")
	root = Node3D.new()
	add_child(root)
	var env := WorldEnvironment.new()
	env.environment = RenderProfile.make_environment()
	root.add_child(env)
	root.add_child(RenderProfile.make_sun())
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.82, 0.74, 0.56)
	gm.roughness = 1.0
	ground.material_override = gm
	root.add_child(ground)
	cam = Camera3D.new()
	root.add_child(cam)
	cam.current = true
	dummy = Dummy.new()
	root.add_child(dummy)
	dummy.add_to_group(&"characters")
	dummy.position = Vector3(50, 0, 50)

	# ---------- модель ----------
	var c := _mk(&"crab", Vector3(0, 0, 0))
	var r := c.anim_ctrl as UserCrabRig
	check(r != null, "краб — модель пака (UserCrabRig)")
	if r == null:
		return
	check(r.skel != null and r.skel.get_bone_count() >= 36, "скелет загружен (%d костей)" % (r.skel.get_bone_count() if r.skel else 0))
	check(r.legs.size() == 6 and r.claws.size() == 2, "6 ног и 2 клешни")
	await _run([c], 0.8)
	_follow(c, Vector3(0.75, 0.55, -1.0))
	await shot("idle_front")
	_look(Vector3(1.3, 0.35, 0.0), Vector3(0, 0.15, 0), 35.0)
	await shot("idle_side")
	# стопы на земле в покое
	var max_h := 0.0
	for l: Dictionary in r.legs:
		max_h = maxf(max_h, absf(_foot(r, l).y))
	check(max_h < 0.03, "в покое стопы на земле (макс. %.3f м)" % max_h)

	# ---------- кормёжка ----------
	r._start_eat()
	await _run([c], 0.6)
	_follow(c, Vector3(0.75, 0.45, -0.95))
	await shot("eat_pinch")
	await _run([c], 0.8)
	await shot("eat_mouth")

	# ---------- ходьба боком: стопы не скользят, клешни качаются ----------
	c.move_to = Vector3(0, 0, -30)
	c._set_state(&"wander")
	await _run([c], 1.2)
	var l0: Dictionary = r.legs[0]
	var p_prev := _foot(r, l0)
	var slip := 0.0
	var lifted := false
	var claw_y: Array[float] = []
	var opens: Array[float] = []
	for i in 30:
		await _run([c], 1.0 / 30.0)
		var p := _foot(r, l0)
		if p.y < 0.004 and p_prev.y < 0.004:
			slip = maxf(slip, Vector2(p.x - p_prev.x, p.z - p_prev.z).length())
		if p.y > 0.03:
			lifted = true
		p_prev = p
		claw_y.append((r.claws[0]["w"] as Vector3).y)
		opens.append(_finger_open(r, 0))
	check(c.speed > 0.4, "краб идёт (%.2f м/с)" % c.speed)
	check(lifted, "нога поднимается в переносе")
	check(slip < 0.008, "стопа в опоре почти не скользит (%.4f м/кадр)" % slip)
	check(claw_y.max() - claw_y.min() > 0.015, "клешни покачиваются при ходьбе (%.3f м)" % (claw_y.max() - claw_y.min()))
	check(opens.max() - opens.min() > 0.08, "пальцы клешни пощёлкивают на ходу")
	for i in 6:
		_follow(c, Vector3(0.95, 0.6, 0.75))
		await shot("walk_%d" % i)
		await _run([c], 0.07)
	_follow(c, Vector3(1.2, 0.18, 0.0), 38.0)
	await shot("walk_low")
	# бег
	c._set_state(&"flee")
	c.target = dummy
	dummy.global_position = c.global_position + Vector3(0, 0, 3)
	await _run([c], 0.6)
	_follow(c, Vector3(1.0, 0.6, 0.8))
	await shot("run")

	# ---------- угроза и щипок ----------
	c.global_position = Vector3(4, 0, 0)
	c.speed = 0.0
	c._set_state(&"warn")
	dummy.global_position = Vector3(4, 0, -1.2)
	c.target = dummy
	await _run([c], 1.0)
	_look(Vector3(4.65, 0.5, -1.1), Vector3(4, 0.2, 0), 42.0)
	await shot("threat")
	check(r._threat > 0.8, "угроза: клешни подняты")
	check((r.claws[1]["w"] as Vector3).y > 0.25, "запястье поднято (%.2f)" % (r.claws[1]["w"] as Vector3).y)
	check(_finger_open(r, 1) > 0.45, "пальцы раскрыты в угрозе")
	dummy.global_position = Vector3(4, 0, -0.5)
	var hits0 := dummy.hits
	c._set_state(&"attack")
	await _run([c], 0.12)
	await shot("attack_windup")
	var waited := 0.0
	while r._strike < 0.0 and waited < 2.0:
		await _run([c], 1.0 / 30.0)
		waited += 1.0 / 30.0
	await _run([c], 0.1)
	await shot("attack_snap")
	await _run([c], 0.3)
	check(dummy.hits > hits0, "щипок наносит урон")

	# ---------- закапывание ----------
	c.global_position = Vector3(8, 0, 0)
	c.speed = 0.0
	c._set_state(&"burrow")
	await _run([c], 0.45)
	_look(Vector3(8.7, 0.55, -0.9), Vector3(8, 0.08, 0), 40.0)
	await shot("burrow_dig")
	await _run([c], 1.4)
	await shot("burrowed")
	check(r.rig.position.y < -0.15, "краб ушёл в песок (%.3f)" % r.rig.position.y)
	c._set_state(&"idle")
	await _run([c], 1.2)
	await shot("emerged")
	check(r.rig.position.y > -0.03, "краб вылез из песка")

	# ---------- смерть ----------
	c.global_position = Vector3(12, 0, 0)
	c._set_state(&"idle")
	await _run([c], 0.3)
	c.apply_damage(100.0, null)
	await _run([c], 0.35)
	_look(Vector3(12.7, 0.55, -0.9), Vector3(12, 0.1, 0), 40.0)
	await shot("death_twitch")
	await _run([c], 2.0)
	await shot("dead")
	check(c._model.position.y > 0.15, "перевёрнутый краб лежит на земле")
