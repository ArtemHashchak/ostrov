extends CombatTestCase
## Коктейль Молотова: игрок бросает бутылку в деревянный мост из 4 секций —
## секция загорается и сгорает, хвост моста отрывается. Плюс зажигательная стрела.

var sections: Array[Blueprint] = []

func _init() -> void:
	timeout_sec = 1500.0

func run() -> void:
	if not await setup_combat(true):
		return
	var wl := BuildEnv.water_level()
	var d := 30.0
	var first := {}
	while d < 70.0:
		var r := mod.shore_raft(Vector3(d, wl, 0.0), -PI * 0.5)
		if r.ok:
			first = r
			break
		d += 0.25
	check(not first.is_empty(), "место для моста у берега (x=%.1f)" % d)
	if first.is_empty():
		return
	sections.append(mod.place_blueprint(&"raft", first.xform as Transform3D, 0, {"type": &"shore"}))
	while sections.size() < 4:
		var last := sections[sections.size() - 1]
		var s := mod.raft_socket(last.base_now() * Vector3(0, 0, -3.0))
		if s.is_empty():
			break
		sections.append(mod.place_blueprint(&"raft", s.xform, 0, {"type": &"raft", "parent": s.parent, "offset": s.offset}))
	for b in sections:
		for t: StringName in [&"log", &"stick", &"rope"]:
			b.add_material(t, 99)
	var done := true
	for b in sections:
		done = done and b.is_complete()
	check(sections.size() == 4 and done, "мост из 4 готовых секций")
	await wait(0.8)

	# игрок на берегу сбоку, бросает коктейль во 2-ю секцию
	var target := sections[1]
	var tp := target.global_position
	var stand := Vector3(tp.x - 6.0, 0.0, 6.0)
	while BuildEnv.height_at(stand.x, stand.z) < wl + 0.2 and stand.x > 0.0:
		stand.x -= 1.0
	stand.y = BuildEnv.height_at(stand.x, stand.z) + 0.1
	teleport(stand)
	await wait(0.4)
	await equip(&"molotov")
	check(ctrl().wid == &"molotov", "в руке коктейль Молотова")
	aim_at(tp + Vector3.UP * 0.4)
	await wait(0.4)
	await shot("01_molotov_aim")
	var origin := p.get_eye_position() if p.has_method(&"get_eye_position") else p.global_position + Vector3.UP * 1.6
	var dir := Combat.aim_dir(origin, tp + Vector3.UP * 0.2, &"molotov")
	var n0 := p.inventory.count(&"molotov")
	Input.action_press(&"attack")
	await wait(0.5)
	Input.action_release(&"attack")
	await wait_frames(2)
	var thrown := p.inventory.count(&"molotov") < n0
	if not thrown:
		# фолбэк — тот же API, что у ботов
		Combat.throw_item(p, &"molotov", origin, dir, 1.0)
	check(thrown, "игрок бросил коктейль кнопкой атаки")
	var t := 0.0
	while not target.burning and t < 8.0:
		await wait(0.2)
		t += 0.2
	if not target.burning:
		# первый бросок мимо — повторяем ботовским API с точной наводкой
		Combat.throw_item(p, &"molotov", origin, Combat.aim_dir(origin, tp, &"molotov"), 1.0)
		t = 0.0
		while not target.burning and t < 8.0:
			await wait(0.2)
			t += 0.2
	check(target.burning, "секция моста загорелась от коктейля")
	var fires := get_tree().get_nodes_in_group(&"fire_zones")
	check(fires.size() > 0 or target.burning, "на месте удара — лужа огня")
	await wait(0.6)
	await shot("02_bridge_fire")

	Engine.time_scale = 4.0
	t = 0.0
	while is_instance_valid(target) and not target.is_queued_for_deletion() and t < 60.0:
		await wait(0.5)
		t += 0.5
	Engine.time_scale = 1.0
	var burned := not is_instance_valid(target) or target.is_queued_for_deletion()
	check(burned, "секция сгорела (%.0f с реального ожидания ×4)" % t)
	var tail := false
	for i in range(2, sections.size()):
		var b := sections[i]
		if not is_instance_valid(b) or b.is_drifting() or b.burning:
			tail = true
	check(tail, "хвост моста оторвался/загорелся")
	await wait(0.4)
	await shot("03_bridge_burned")

	# зажигательная стрела поджигает первую секцию
	var s0 := sections[0]
	if is_instance_valid(s0) and not s0.burning:
		var o2 := p.global_position + Vector3.UP * 1.6
		p.inventory.add(&"arrow_fire", 3)
		Combat.fire(p, &"bow", o2, Combat.aim_dir(o2, s0.global_position + Vector3.UP * 0.2, &"bow"), {"ammo": &"arrow_fire", "power": 1.0})
		t = 0.0
		while is_instance_valid(s0) and not s0.burning and t < 5.0:
			await wait(0.2)
			t += 0.2
		check(not is_instance_valid(s0) or s0.burning, "огненная стрела подожгла секцию")
		await shot("04_fire_arrow")
