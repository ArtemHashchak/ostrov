extends TestCase
## Анимация животных из папки пользователя вблизи (UserSeaActor + шейдер user_creature):
## осьминог (ползёт, угроза, хват, рывок с чернилами, прячется), кальмар (толчки, испуг),
## рыбы пака (поворот дугой, зависание с плавниками, C-старт). Серии кадров →
## tests/shots/test_user_anim_folder_*.png. Сцена своя: песчаное дно, вода над ним (заглушка моря).

func _init() -> void:
	scene_path = ""
	timeout_sec = 3000.0

## Заглушка моря: вода на 0, ровное дно на FLOOR.
class StubSea extends RefCounted:
	var floor_y := -2.5
	func water_y() -> float:
		return 0.0
	func floor_at(_x: float, _z: float) -> float:
		return floor_y
	func depth_at(_x: float, _z: float) -> float:
		return -floor_y

## Пловец-раздражитель: «в воде», позицию задаёт тест.
class Swimmer extends Node3D:
	func is_in_water() -> bool:
		return true

var root: Node3D
var cam: Camera3D
var sea := StubSea.new()
var swimmer: Swimmer

func _run(actors: Array, sec: float) -> void:
	var t := 0.0
	while t < sec:
		var dt := 1.0 / 30.0
		for a: UserSeaActor in actors:
			a.tick(dt, cam.global_position, swimmer, true)
		await get_tree().process_frame
		t += dt

func _look(from: Vector3, at: Vector3, fov: float = 45.0) -> void:
	cam.global_position = from
	cam.look_at(at)
	cam.fov = fov

func _species(id: String) -> Dictionary:
	for d: Dictionary in UserSeaPack.species_list():
		if String(d.get("id", "")) == id:
			return d
	return {}

func _spawn(id: String, pos: Vector3, yaw: float) -> UserSeaActor:
	var a := UserSeaActor.new()
	a.setup(_species(id), sea, pos, 4242)
	a.yaw = yaw
	root.add_child(a)
	return a

func run() -> void:
	root = Node3D.new()
	add_child(root)
	var env := WorldEnvironment.new()
	# «под водой»: сине-зелёный фон и дымка
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.09, 0.3, 0.36)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.62, 0.66)
	e.ambient_light_energy = 0.9
	e.fog_enabled = true
	e.fog_light_color = Color(0.09, 0.3, 0.36)
	e.fog_density = 0.04
	root.add_child(env)
	env.environment = e
	root.add_child(RenderProfile.make_sun())
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.78, 0.72, 0.56)
	gm.roughness = 1.0
	ground.material_override = gm
	ground.position.y = sea.floor_y
	root.add_child(ground)
	cam = Camera3D.new()
	root.add_child(cam)
	cam.current = true
	swimmer = Swimmer.new()
	root.add_child(swimmer)
	swimmer.global_position = Vector3(0, -1.0, 40.0)   # далеко

	# --- разметка мешей
	for id in ["octopus_user", "squid_user", "discus_user", "redfish_user", "spotted_user", "shark_pack8_user"]:
		var d := _species(id)
		check(not d.is_empty(), "вид пака есть: %s" % id)
		var m := UserSeaPack.species_mesh(d)
		check(m != null and m.has_meta(&"rig"), "%s: меш с разметкой для анимации вблизи" % id)
		if m:
			var arr := m.surface_get_arrays(0)
			check(arr[Mesh.ARRAY_CUSTOM0] != null and arr[Mesh.ARRAY_CUSTOM1] != null, "%s: CUSTOM0/1 в меше" % id)
	var octo_rig: Dictionary = UserSeaPack.species_mesh(_species("octopus_user")).get_meta(&"rig", {})
	check(int(octo_rig.get("arms", 0)) == 8, "у осьминога размечено 8 щупалец (%s)" % str(octo_rig.get("arms", 0)))

	# --- осьминог
	var o := _spawn("octopus_user", Vector3(0, sea.floor_y + 0.02, 0), 0.0)
	o.state = UserSeaActor.S.CRAWL
	o._goal = Vector3(0, sea.floor_y, 6.0)
	var p0 := o.global_position
	for k in 4:
		await _run([o], 0.45)
		_look(o.global_position + Vector3(1.3, 0.9, 1.3), o.global_position + Vector3(0, 0.1, 0))
		await wait_frames(2)
		await shot("octo_crawl_%d" % k)
	check(o.global_position.distance_to(p0) > 0.15, "осьминог ползёт по дну (%.2f м)" % o.global_position.distance_to(p0))
	check(absf(o.global_position.y - (sea.floor_y + 0.02)) < 0.1, "держится дна")
	o.state = UserSeaActor.S.PAUSE
	o._t = 0.0
	await _run([o], 2.0)
	_look(o.global_position + Vector3(0.0, 1.6, 0.6), o.global_position)
	await wait_frames(2)
	await shot("octo_pause_top")
	# угроза: пловец подплывает к глазам (+Z модели)
	var eyes := o.global_position - o.forward() * 2.6
	swimmer.global_position = eyes + Vector3(0, 0.2, 0)
	await _run([o], 0.25)
	check(o.state == UserSeaActor.S.THREAT, "осьминог в угрозе, когда пловец рядом")
	await _run([o], 0.6)
	_look(o.global_position - o.forward() * 1.7 + Vector3(0.5, 0.6, 0.0), o.global_position + Vector3(0, 0.15, 0))
	await wait_frames(2)
	await shot("octo_threat")
	# хват: пловец вплотную
	swimmer.global_position = o.global_position - o.forward() * 1.1 + Vector3(0, 0.3, 0)
	await _run([o], 0.6)
	check(o.state == UserSeaActor.S.GRAB, "осьминог хватает щупальцами")
	_look(o.global_position - o.forward() * 1.5 + Vector3(-0.7, 0.5, 0.0), o.global_position + Vector3(0, 0.2, 0))
	await wait_frames(2)
	await shot("octo_grab")
	await _run([o], 0.7)
	check(o.state == UserSeaActor.S.JET, "после хвата — рывок мантией")
	var inks := 0
	for c in root.get_children():
		if c is CPUParticles3D:
			inks += 1
	check(inks > 0, "облако чернил (%d)" % inks)
	var pj := o.global_position
	await _run([o], 0.5)
	_look(o.global_position + o.forward().cross(Vector3.UP) * 2.2 + Vector3(0, 0.4, 0), o.global_position)
	await wait_frames(2)
	await shot("octo_jet")
	_look(pj + Vector3(0.0, 0.6, 3.0), pj)
	await wait_frames(2)
	await shot("octo_ink")
	await _run([o], 1.2)
	check(o.global_position.distance_to(pj) > 1.0, "рывком уходит от пловца (%.1f м)" % o.global_position.distance_to(pj))
	swimmer.global_position = Vector3(0, -1.0, 40.0)
	await _run([o], 3.0)
	check(o.state == UserSeaActor.S.HIDE, "прячется: распластался под цвет дна")
	_look(o.global_position + Vector3(1.2, 1.0, 1.0), o.global_position)
	await wait_frames(2)
	await shot("octo_hide")
	o.queue_free()

	# --- кальмар
	var sq: Array = []
	for k in 3:
		var s := _spawn("squid_user", Vector3(k * 0.9 - 0.9, -1.3 + k * 0.15, 0.0), 0.3 * k)
		s._goal = Vector3(0, -1.2, -10.0)
		sq.append(s)
	await _run(sq, 1.2)
	_look((sq[1] as Node3D).global_position + Vector3(2.4, 0.4, 0.6), (sq[1] as Node3D).global_position)
	await wait_frames(2)
	await shot("squid_hover")
	swimmer.global_position = (sq[1] as Node3D).global_position + Vector3(0.0, 0.0, 1.2)
	await _run(sq, 0.3)
	check((sq[1] as UserSeaActor).state == UserSeaActor.S.JET, "кальмар пугается: вспышка и рывок")
	await _run(sq, 0.2)
	_look((sq[1] as Node3D).global_position + Vector3(2.0, 0.5, 0.0), (sq[1] as Node3D).global_position)
	await wait_frames(2)
	await shot("squid_jet")
	for s: Node in sq:
		s.queue_free()
	swimmer.global_position = Vector3(0, -1.0, 40.0)

	# --- рыбы
	var fish_ids := ["discus_user", "redfish_user", "spotted_user", "shark_pack8_user"]
	for id in fish_ids:
		var d := _species(id)
		var L := float(d.get("length", 0.3))
		var f := _spawn(id, Vector3(0, -1.2, 0), 0.0)
		# поворот: цель сбоку — тело дугой
		f.state = UserSeaActor.S.CRUISE
		f._goal = Vector3(L * 12.0, -1.2, -L * 2.0)
		await _run([f], 0.5)
		var turn := f._turn_rate
		_look(f.global_position + Vector3(0, L * 3.2 + 0.3, 0.01), f.global_position, 40.0)
		await wait_frames(2)
		await shot("%s_turn" % id)
		check(absf(turn) > 0.2, "%s: изгиб в повороте (%.2f)" % [id, turn])
		# зависание
		f.state = UserSeaActor.S.HOVER
		f._t = 0.0
		var ph0 := f._swim_phase
		await _run([f], 1.0)
		var hover_rate := f._swim_phase - ph0
		_look(f.global_position + f.forward().cross(Vector3.UP) * (L * 3.0 + 0.2) + Vector3(0, L * 0.6, 0), f.global_position, 40.0)
		await wait_frames(2)
		await shot("%s_hover" % id)
		# испуг: пловец рядом
		var cruise := float(d.get("speed", 0.6))
		swimmer.global_position = f.global_position - f.forward() * (L * 2.0 + 0.4)
		await _run([f], 0.12)
		check(f.state == UserSeaActor.S.STARTLE, "%s: испуг от пловца" % id)
		_look(f.global_position + Vector3(0, L * 3.2 + 0.3, 0.01), f.global_position, 40.0)
		await wait_frames(2)
		await shot("%s_startle" % id)
		ph0 = f._swim_phase
		await _run([f], 0.4)
		var burst_rate := (f._swim_phase - ph0) / 0.4
		check(f.speed > cruise * 2.5, "%s: рывок прочь (%.2f > %.2f)" % [id, f.speed, cruise * 2.5])
		check(burst_rate > hover_rate * 1.5, "%s: хвост бьёт чаще на скорости (%.1f > %.1f)" % [id, burst_rate, hover_rate])
		swimmer.global_position = Vector3(0, -1.0, 40.0)
		f.queue_free()
		await wait_frames(2)

	# --- большая белая: смешивание клипов пака
	await _shark()

func _shark() -> void:
	if not SharkModel.pack_available():
		check(false, "модель большой белой из пака есть")
		return
	var m := SharkModel.build_pack(&"white")
	root.add_child(m)
	m.global_position = Vector3(0, -1.3, 0)
	var pa := PackSharkAnim.new()
	check(pa.setup(m), "акула: дерево анимации собрано (все клипы)")
	if pa.tree == null:
		return
	check(pa.jaw != null, "акула: модификатор пасти на кости JawLower")
	var side := Vector3(5.5, 0.2, 0.0)
	var top := Vector3(0.0, 6.0, 0.01)
	var steps := [
		["swim", 1.0, 0.0, 0.0, side], ["idle", 0.1, 0.0, 0.0, side], ["fast", 2.6, 0.0, 0.0, side],
		["turn_left", 1.0, 1.0, 0.0, top], ["turn_right", 1.0, -1.0, 0.0, top], ["gape", 1.4, 0.0, 1.0, Vector3(3.2, 0.3, -2.6)],
	]
	for st: Array in steps:
		var tt := 0.0
		while tt < 1.4:
			pa.update(1.0 / 30.0, float(st[1]), float(st[2]), float(st[3]))
			await get_tree().process_frame
			tt += 1.0 / 30.0
		_look(m.global_position + (st[4] as Vector3), m.global_position, 50.0)
		await wait_frames(2)
		await shot("shark_%s" % st[0])
	var bp: Vector2 = pa.tree.get(&"parameters/loco/blend_position")
	check(bp.y > 0.8 and bp.y < 1.6, "акула: смешивание по скорости (%.2f)" % bp.y)
	var shot_i := 0
	for one in [&"bite", &"bite", &"eat", &"hurt"]:
		pa.fire(one)
		var tt := 0.0
		var seen := false
		while tt < 0.45:
			pa.update(1.0 / 30.0, 1.2, 0.0, 0.0)
			seen = seen or pa.is_playing_oneshot()
			await get_tree().process_frame
			tt += 1.0 / 30.0
		check(seen, "акула: разовая анимация %s" % one)
		_look(m.global_position + Vector3(3.0, 0.4, -2.4), m.global_position + Vector3(0, 0, -1.2), 50.0)
		await wait_frames(1)
		shot_i += 1
		await shot("shark_%d_%s" % [shot_i, one])
		await wait(0.6)
	pa.fire(&"die")
	await wait(1.4)
	_look(m.global_position + side, m.global_position, 50.0)
	await wait_frames(2)
	await shot("shark_die")
	check(String(pa.tree.get(&"parameters/life/current_state")) == "dead", "акула: смерть — клип die")
	m.queue_free()

	# --- краб пака: глаза на стебельках (кости R.Eye / L.Eye)
	await _crab_eyes()

func _crab_eyes() -> void:
	if not UserCrabRig.available():
		check(false, "модель краба из пака есть")
		return
	var c := Animal.create(&"crab", Vector3(0, sea.floor_y, 0))
	root.add_child(c)
	c.heading = 0.0
	c.rotation.y = 0.0
	var r := c.anim_ctrl as UserCrabRig
	check(r != null, "краб — из пака (UserCrabRig)")
	if r == null:
		return
	var eb := r.skel.find_bone("R.Eye")
	check(eb >= 0 and r.eyes.size() == 2, "у краба кости глаз R.Eye/L.Eye (%d глаз)" % r.eyes.size())
	if eb < 0:
		return
	var eye_w := func() -> Vector3:
		var g := r.skel.get_bone_global_pose(eb)
		return g.basis.y
	var t := 0.0
	var dirs: Array[Vector3] = []
	while t < 2.5:
		c._think_t = 9999.0
		c.tick(1.0 / 30.0)
		if fmod(t, 0.5) < 1.0 / 30.0:
			dirs.append(eye_w.call())
		await get_tree().process_frame
		t += 1.0 / 30.0
	var spread := 0.0
	for d in dirs:
		spread = maxf(spread, d.angle_to(dirs[0]))
	check(spread > 0.05, "глаза подёргиваются (%.2f рад)" % spread)
	_look(c.global_position + Vector3(0.25, 0.42, -0.62), c.global_position + Vector3(0, 0.24, -0.1), 35.0)
	await wait_frames(2)
	await shot("crab_eyes_up")
	var up: Vector3 = eye_w.call()
	r.on_event(c, &"hurt")
	t = 0.0
	while t < 0.22:
		c._think_t = 9999.0
		c.tick(1.0 / 30.0)
		await get_tree().process_frame
		t += 1.0 / 30.0
	var down: Vector3 = eye_w.call()
	await shot("crab_eyes_hidden")
	check(down.angle_to(up) > 0.5, "при боли глаза прячутся (%.2f рад)" % down.angle_to(up))
	c.queue_free()
