extends TestCase
## Анимация членистоногих: краб (ходьба боком, бег, угроза, щипок, кормёжка, закапывание, смерть),
## скорпион (хвост, удар жалом), паук (походка, дыбы). Кадры — серии скриншотов.

func _init() -> void:
	scene_path = ""
	timeout_sec = 1500.0

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

## Прогон тиков: think выключен, состояние задаёт тест.
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

func _follow(a: Node3D, off: Vector3, fov: float = 38.0) -> void:
	_look(a.global_position + off, a.global_position + Vector3(0, 0.06, 0), fov)

func run() -> void:
	UserCrabRig.use_pack = false   # тест процедурного краба (краб пака — test_user_crab)
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

	# ---------- краб: покой и кормёжка ----------
	var c := _mk(&"crab", Vector3(0, 0, 0))
	var rigc: ArthropodRig = c.anim_ctrl as ArthropodRig
	check(rigc != null, "у краба есть контроллер анимации")
	check(rigc != null and rigc.legs.size() == 8 and rigc.claws.size() == 2 and rigc.eyes.size() == 2, "краб: 8 ног, 2 клешни, 2 глаза на стебельках")
	_follow(c, Vector3(0.55, 0.42, -0.75))
	await _run([c], 0.6)
	await shot("crab_idle")
	rigc._start_eat()
	await _run([c], 0.45)
	await shot("crab_eat_pinch")
	await _run([c], 0.75)
	await shot("crab_eat_mouth")

	# ---------- ходьба боком: стопы не скользят ----------
	c.move_to = Vector3(0, 0, -30)
	c._set_state(&"wander")
	await _run([c], 1.2)
	var l0: Dictionary = rigc.legs[0]
	var fem: Node3D = l0["fem"]
	var tip := Vector3(0, 0, -float(l0["b"]))
	var p_prev := (l0["tib"] as Node3D).global_transform * tip
	var max_planted_slip := 0.0
	var lifted := false
	var heights: Array[float] = []
	for i in 30:
		await _run([c], 1.0 / 30.0)
		var p := (l0["tib"] as Node3D).global_transform * tip
		heights.append(p.y)
		if p.y < 0.006 and p_prev.y < 0.006:
			max_planted_slip = maxf(max_planted_slip, Vector2(p.x - p_prev.x, p.z - p_prev.z).length())
		if p.y > 0.015:
			lifted = true
		p_prev = p
	check(c.speed > 0.4, "краб идёт (скорость %.2f)" % c.speed)
	check(lifted, "нога поднимается в переносе")
	check(max_planted_slip < 0.006, "стопа в опоре почти не скользит (%.4f м/кадр)" % max_planted_slip)
	check(absf(c._model.rotation.y - PI * 0.5) < 0.3, "краб идёт боком")
	check(fem.visible, "бедро видно")
	for i in 4:
		_follow(c, Vector3(0.6, 0.35, 0.55))
		await shot("crab_walk_%d" % i)
		await _run([c], 0.09)
	# бег
	c._set_state(&"flee")
	c.target = dummy
	dummy.global_position = c.global_position + Vector3(0, 0, 3)
	await _run([c], 0.6)
	_follow(c, Vector3(0.7, 0.4, 0.6))
	await shot("crab_run")
	check(c.speed > 1.5, "краб бежит (%.2f)" % c.speed)

	# ---------- угроза и щипок ----------
	c.global_position = Vector3(3, 0, 0)
	c.speed = 0.0
	c._set_state(&"warn")
	dummy.global_position = Vector3(3, 0, -0.9)
	c.target = dummy
	await _run([c], 1.0)
	_look(Vector3(3.35, 0.32, -0.7), Vector3(3, 0.1, 0), 40.0)
	await shot("crab_threat")
	check(rigc._threat > 0.8, "угроза: клешни подняты")
	var sh: Node3D = rigc.claws[1]["sh"]
	check(sh.rotation.x > 0.6, "клешня поднята (%.2f)" % sh.rotation.x)
	dummy.global_position = Vector3(3, 0, -0.45)
	var hits0 := dummy.hits
	c._set_state(&"attack")
	await _run([c], 0.12)
	await shot("crab_attack_windup")
	await _run([c], 0.1)
	await shot("crab_attack_snap")
	await _run([c], 0.3)
	check(dummy.hits > hits0, "щипок наносит урон")
	check(c.state == &"flee", "ущипнув, краб удирает")

	# ---------- закапывание ----------
	c.global_position = Vector3(6, 0, 0)
	c.speed = 0.0
	c._set_state(&"burrow")
	await _run([c], 0.45)
	_look(Vector3(6.45, 0.35, -0.6), Vector3(6, 0.04, 0), 38.0)
	await shot("crab_burrow_dig")
	await _run([c], 1.4)
	await shot("crab_burrowed")
	var body: Node3D = rigc.rig
	check(body.position.y < -0.08, "краб ушёл в песок (%.3f)" % body.position.y)
	c._set_state(&"idle")
	await _run([c], 1.0)
	await shot("crab_emerged")
	check(body.position.y > -0.02, "краб вылез из песка")

	# ---------- смерть ----------
	c.global_position = Vector3(9, 0, 0)
	c._set_state(&"idle")
	await _run([c], 0.3)
	c.apply_damage(100.0, null)
	await _run([c], 0.35)
	_look(Vector3(9.45, 0.38, -0.6), Vector3(9, 0.05, 0), 38.0)
	await shot("crab_death_twitch")
	await _run([c], 2.0)
	await shot("crab_dead")
	check(c._model.position.y > 0.08, "перевёрнутый краб лежит на земле, а не в ней")

	# ---------- скорпион ----------
	var s := _mk(&"scorpion", Vector3(12, 0, 0))
	var rigs: ArthropodRig = s.anim_ctrl as ArthropodRig
	check(rigs != null and rigs.tail.size() == 6, "у скорпиона хвост из 6 шарниров")
	s.move_to = Vector3(12, 0, -20)
	s._set_state(&"wander")
	await _run([s], 0.8)
	_follow(s, Vector3(0.28, 0.16, 0.18), 40.0)
	await shot("scorpion_walk")
	s.speed = 0.0
	s.global_position = Vector3(12, 0, 0)
	s._set_state(&"warn")
	dummy.global_position = Vector3(12, 0, -0.5)
	s.target = dummy
	s._warn_t = 99.0
	await _run([s], 0.8)
	_look(Vector3(12.3, 0.14, -0.12), Vector3(12, 0.04, 0), 40.0)
	await shot("scorpion_threat")
	s._set_state(&"attack")
	await _run([s], 0.2)
	await _run([s], 0.08)
	await shot("scorpion_sting")
	await _run([s], 0.4)

	# ---------- паук ----------
	var p := _mk(&"spider", Vector3(15, 0, 0))
	var rigp: ArthropodRig = p.anim_ctrl as ArthropodRig
	check(rigp != null and rigp.legs.size() == 8, "у паука 8 сочленённых ног")
	p.move_to = Vector3(15, 0, -20)
	p._set_state(&"wander")
	await _run([p], 0.8)
	_follow(p, Vector3(0.25, 0.16, 0.12), 40.0)
	await shot("spider_walk")
	p.speed = 0.0
	p.global_position = Vector3(15, 0, 0)
	p._set_state(&"warn")
	dummy.global_position = Vector3(15, 0, -0.4)
	p.target = dummy
	p._warn_t = 99.0
	await _run([p], 1.0)
	_look(Vector3(15.25, 0.1, -0.22), Vector3(15, 0.05, 0), 40.0)
	await shot("spider_rear_up")
	check(rigp.rig.rotation.x > 0.3, "паук встал на дыбы")

	# ---------- LOD анимации: вдали заморожена ----------
	var far := _mk(&"crab", Vector3(0, 0, -200))
	far.move_to = Vector3(0, 0, -260)
	far._set_state(&"wander")
	var rf: ArthropodRig = far.anim_ctrl as ArthropodRig
	var t0 := rf._t
	await _run([far], 0.3)
	check(is_equal_approx(rf._t, t0), "дальний краб не анимируется (LOD)")
