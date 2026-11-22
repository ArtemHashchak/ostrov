extends TestCase
## Модели чата моделирования (2026-11-22) с клипами автора — UserClipRig:
## куфии (зелёная, синяя), питоны (королевский, ковровый), комодский варан, зелёная игуана,
## огненная саламандра, гигантская сколопендра, рак-отшельник, попугаи (пионус, кеа).
## Для каждого варианта: модель собрана, клипы на месте, состояние → клип (покой, ход, бег, угроза,
## атака, удар, смерть с удержанием кадра), скорость клипа подстроена под скорость животного.
## Отшельник прячется в раковину от человека. Снимки (--shots): tests/shots/test_user_land2_*.png.
## LAND2_ONLY=snake,python … — только эти виды.

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

func _mk(sp: StringName, vi: int, pos: Vector3) -> Animal:
	UserClipRig.next_variant = vi
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
			if is_instance_valid(a):
				if keep_state:
					a._think_t = 9999.0
				if a.cfg.get("fly", false) and not a.dead:
					a._anim_t += dt
					a._animate(dt)   # птица: состояние задаёт тест (без стаи)
				else:
					a.tick(dt)
		await wait_frames(1)
		t += dt

func _look(from: Vector3, at: Vector3, fov: float = 40.0) -> void:
	cam.global_position = from
	cam.look_at(at)
	cam.fov = fov

## Камера сбоку-спереди на расстоянии по длине животного.
func _frame(a: Animal, side := 1.0, up := 0.45) -> void:
	var L := float(a._model.get_meta(&"length", 0.5)) * a.growth
	var d := maxf(L * 1.25, 0.35)
	var c := a.global_position + Vector3(0, L * 0.08, 0)
	_look(c + Vector3(d * 0.8 * side, d * up, -d * 0.75), c, 40.0)

func _only() -> PackedStringArray:
	var s := OS.get_environment("LAND2_ONLY")
	return PackedStringArray() if s == "" else s.split(",")

func run() -> void:
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
	gm.albedo_color = Color(0.62, 0.56, 0.42)
	gm.roughness = 1.0
	ground.material_override = gm
	root.add_child(ground)
	cam = Camera3D.new()
	root.add_child(cam)
	cam.current = true
	dummy = Dummy.new()
	root.add_child(dummy)
	dummy.add_to_group(&"characters")
	dummy.position = Vector3(60, 0, 60)
	var only := _only()
	var n := 0
	for sp: StringName in UserClipRig.VARIANTS:
		if not only.is_empty() and not (String(sp) in only):
			continue
		check(UserClipRig.available(sp), "%s: модели пака на месте" % sp)
		check(Animal.SPECIES.has(sp), "%s: вид есть в Animal.SPECIES" % sp)
		var vs: Array = UserClipRig.variants(sp)
		for vi in vs.size():
			await _variant(sp, vi, Vector3(n * 6.0 - 30.0, 0, 0))
			n += 1
	if only.is_empty() or "hermit_crab" in only:
		await _hermit()

func _variant(sp: StringName, vi: int, pos: Vector3) -> void:
	var v: Dictionary = UserClipRig.variants(sp)[vi]
	var tag := String(v["id"])
	var a := _mk(sp, vi, pos)
	var r := a.anim_ctrl as UserClipRig
	check(r != null and r.player != null, "%s: контроллер клипов и AnimationPlayer" % tag)
	if r == null or r.player == null:
		a.queue_free()
		return
	check(a.display_name() == String(v["name"]), "%s: подпись «%s»" % [tag, a.display_name()])
	for role: String in (v["clips"] as Dictionary):
		var c := String(v["clips"][role])
		check(r._has.has(c), "%s: клип %s (%s) есть в модели" % [tag, c, role])
	var fly := bool(a.cfg.get("fly", false))
	if fly:
		a.state = &"perch"
		a.alt = 0.0
	await _run([a], 0.6)
	var idle := String(v["clips"]["idle"])
	check(r._cur == idle or r._oneshot != "", "%s: в покое — %s (сейчас %s)" % [tag, idle, r._cur])
	_frame(a)
	await shot(tag + "_idle")
	if fly:
		# полёт: взмахи / планирование
		a.state = &"fly"
		a.alt = 6.0
		a.position.y = 1.2
		await _run([a], 0.8)
		check(r._cur in [String(v["clips"]["fly"]), String(v["clips"]["glide"]), String(v["clips"].get("takeoff", ""))],
			"%s: в воздухе — fly/glide/takeoff (%s)" % [tag, r._cur])
		_frame(a, 1.0, 0.1)
		await shot(tag + "_fly")
		a.position.y = 0.0
	else:
		# ход
		a.move_to = pos + Vector3(0, 0, -40)
		a._set_state(&"wander")
		await _run([a], 1.0)
		var mv := String(v["clips"]["move"])
		check(r._cur == mv, "%s: идёт — клип %s (сейчас %s, скорость %.2f)" % [tag, mv, r._cur, a.speed])
		check(r.player.speed_scale >= UserClipRig.SPEED_MIN - 0.01 and r.player.speed_scale <= UserClipRig.SPEED_MAX + 0.01,
			"%s: скорость клипа в пределах (%.2f)" % [tag, r.player.speed_scale])
		_frame(a)
		await shot(tag + "_move")
		if (v["clips"] as Dictionary).has("run"):
			a.target = dummy
			a._set_state(&"flee")
			await _run([a], 0.8)
			check(r._cur == String(v["clips"]["run"]), "%s: бежит — %s (сейчас %s, %.2f м/с)" % [tag, v["clips"]["run"], r._cur, a.speed])
			a.target = null
		# угроза
		a.speed = 0.0
		a._set_state(&"warn")
		a.target = dummy
		a._warn_t = 99.0
		await _run([a], 1.6)
		var w := String(v["clips"]["warn"])
		var w2 := String(v["clips"].get("warn2", w))
		check(r._cur in [w, w2] or r._oneshot != "", "%s: угроза — %s (сейчас %s)" % [tag, w, r._cur])
		_frame(a, -1.0, 0.3)
		await shot(tag + "_warn")
		a.target = null
		a._set_state(&"idle")
	# атака / удар
	a.anim_event(&"attack")
	await _run([a], 0.35)
	_frame(a, -1.0, 0.35)
	await shot(tag + "_attack")
	await _run([a], 1.4)
	a.anim_event(&"hurt")
	await _run([a], 0.1)
	check(r._cur == String(v["clips"]["hurt"]) or r._cur == String(v["clips"].get("attack", "")), "%s: удар — %s (%s)" % [tag, v["clips"]["hurt"], r._cur])
	await _run([a], 1.0)
	# смерть: клип death, тушка не переворачивается кодом Animal
	a.apply_damage(9999.0, null)
	check(a.dead, "%s: погиб" % tag)
	await _run([a], 2.8, false)
	check(r._cur == String(v["clips"]["death"]), "%s: клип смерти (%s)" % [tag, r._cur])
	check(absf(a._model.rotation.z) < 0.01, "%s: модель не перевёрнута кодом (rot.z %.2f)" % [tag, a._model.rotation.z])
	_frame(a, 1.0, 0.6)
	await shot(tag + "_death")
	a.queue_free()
	await wait_frames(2)

func _hermit() -> void:
	var a := _mk(&"hermit_crab", 0, Vector3(0, 0, 10))
	a._think_t = 0.0
	dummy.position = Vector3(0.6, 0, 10)
	var t := 0.0
	var hid := false
	var r := a.anim_ctrl as UserClipRig
	while t < 2.0:
		a.tick(1.0 / 30.0)
		await wait_frames(1)
		t += 1.0 / 30.0
		if a.state == &"hide":
			hid = true
	check(hid, "отшельник спрятался в раковину от человека (state %s)" % a.state)
	check(r != null and r._cur == "hide_in_shell", "клип hide_in_shell (%s)" % (r._cur if r else "?"))
	_frame(a)
	await shot("hermit_hidden")
	dummy.position = Vector3(30, 0, 30)
	t = 0.0
	var peeked := false
	var left := false
	while t < 9.0:
		a.tick(1.0 / 30.0)
		await wait_frames(1)
		t += 1.0 / 30.0
		peeked = peeked or a.state == &"peek"
		left = left or (peeked and a.state in [&"idle", &"flee", &"wander"])
	check(peeked, "выглянул из раковины")
	check(left, "после выглядывания — снова ходит (%s)" % a.state)
	a.queue_free()
	dummy.position = Vector3(60, 0, 60)
