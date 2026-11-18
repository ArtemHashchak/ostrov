extends BuildTestCase
## Мост из плавучих связок брёвен: первая секция у берега (через меню),
## ещё 4 — по сокетам у края предыдущей; заполнение; игрок проходит по мосту;
## поджог средней секции — сгорает, хвост моста отрывается и уплывает.

var sections: Array[Blueprint] = []

func _init() -> void:
	timeout_sec = 280.0

func run() -> void:
	if not await setup_build():
		return
	var wl := BuildEnv.water_level()
	# берег по +X: ищем точку, где глубина ~0.5 м и сзади суша
	var d := 30.0
	var first := {}
	while d < 70.0:
		var r := mod.shore_raft(Vector3(d, wl, 0.0), -PI * 0.5)
		if r.ok:
			first = r
			break
		d += 0.25
	check(not first.is_empty(), "найдено место у берега (x=%.1f)" % d)
	if first.is_empty():
		return
	var c0: Vector3 = (first.xform as Transform3D).origin
	# игрок на берегу, смотрит на воду
	var stand := Vector3(d - 4.5, 0.0, 0.0)
	stand.y = BuildEnv.height_at(stand.x, stand.z) + 0.1
	teleport(stand)
	await wait(0.4)
	var bm := build_mode()
	await tap(&"build_menu")
	var idx := bm.entries.find(&"raft")
	check(idx >= 0, "в списке есть мост")
	bm.sel = idx
	await tap(&"attack")
	aim_at(c0)
	await wait(0.5)
	check(bm.valid, "секцию можно ставить у берега: %s" % bm.reason)
	await shot("01_ghost")
	await tap(&"attack")
	await wait_frames(3)
	var rafts := get_tree().get_nodes_in_group(&"raft_deck")
	check(rafts.size() == 1, "первая секция поставлена")
	if rafts.is_empty():
		return
	sections.append(rafts[0] as Blueprint)
	# вторую — тоже из режима, прицелом у края первой
	aim_at(sections[0].base_xform * Vector3(0, 0, -3.0))
	await wait(0.4)
	check(bm.valid and bm.place_anchor.get("type") == &"raft", "вторая секция липнет к краю первой")
	await shot("02_ghost_next")
	await tap(&"attack")
	await wait_frames(3)
	await tap(&"build_menu")
	rafts = get_tree().get_nodes_in_group(&"raft_deck")
	for n in rafts:
		if not sections.has(n):
			sections.append(n as Blueprint)
	# ещё 3 — через API (как бот)
	while sections.size() < 5:
		var last := sections[sections.size() - 1]
		var s := mod.raft_socket(last.base_now() * Vector3(0, 0, -3.0))
		if s.is_empty():
			break
		sections.append(mod.place_blueprint(&"raft", s.xform, 0, {"type": &"raft", "parent": s.parent, "offset": s.offset}))
	check(sections.size() == 5, "5 секций моста (%d)" % sections.size())
	var cost := BuildDefs.cost(&"raft")
	check(int(cost.get(&"log", 0)) >= 6 and int(cost.get(&"rope", 0)) >= 2, "секция стоит брёвна+верёвку: %s" % BuildDefs.cost_text(&"raft"))

	# первую секцию — брёвнами с плеча
	var s0 := sections[0]
	var near := Vector3(d - 3.0, 0.0, 0.4)
	near.y = BuildEnv.height_at(near.x, near.z) + 0.1
	teleport(near)
	await wait(0.3)
	var put := 0
	var tries := 0
	while put < 6 and tries < 10:
		tries += 1
		if await carry_log_into(s0, s0.global_position + Vector3.UP * 0.05):
			put += 1
		elif p.carrying_log:
			p.set_carrying_log(false)
	check(put == 6, "игрок уложил 6 брёвен в первую секцию (%d)" % put)
	p.inventory.add(&"stick", 2)
	p.inventory.add(&"rope", 2)
	aim_at(s0.global_position)
	await wait_frames(2)
	for i in 4:
		await tap(&"interact")
		await wait_frames(2)
	check(s0.is_complete(), "первая секция готова (палки и верёвка из инвентаря)")
	for i in range(1, sections.size()):
		for t: StringName in [&"log", &"stick", &"rope"]:
			sections[i].add_material(t, 99)
	var all_done := true
	for b in sections:
		all_done = all_done and b.is_complete()
	check(all_done, "все секции достроены")
	await wait(1.0)
	# качка
	var y0 := sections[2].global_position.y
	var r0 := sections[2].global_basis.get_euler()
	await wait(1.2)
	var moved := absf(sections[2].global_position.y - y0) + (sections[2].global_basis.get_euler() - r0).length()
	check(moved > 0.003, "секции качаются на волнах (%.3f)" % moved)
	var side := Vector3(c0.x - 6.0, 0.0, 9.0)
	while BuildEnv.height_at(side.x, side.z) < 0.3 and side.x > 0.0:
		side.x -= 1.0
	side.y = BuildEnv.height_at(side.x, side.z) + 0.1
	teleport(side)
	aim_at(c0 + Vector3(6.0, 0.0, 0.0))
	await wait(0.6)
	await shot("03_bridge")

	# проход по мосту
	var shore_pos := c0 + Vector3(-4.2, 0.0, 0.0)
	shore_pos.y = BuildEnv.height_at(shore_pos.x, shore_pos.z) + 0.15
	teleport(shore_pos)
	p.set_look(-PI * 0.5, deg_to_rad(-10.0))
	await wait(0.4)
	var end_x := sections[4].global_position.x
	Input.action_press(&"move_forward")
	var t := 0.0
	var max_x := p.global_position.x
	var min_y_above := 99.0
	var shot_mid := false
	while t < 9.0 and p.global_position.x < end_x:
		await wait(0.2)
		t += 0.2
		max_x = maxf(max_x, p.global_position.x)
		if p.global_position.x > c0.x:
			min_y_above = minf(min_y_above, p.global_position.y - BuildEnv.water_surface(p.global_position.x, p.global_position.z))
		if not shot_mid and p.global_position.x > sections[2].global_position.x:
			shot_mid = true
			await shot("04_walk")
	Input.action_release(&"move_forward")
	await wait(0.3)
	check(p.global_position.x >= end_x - 0.3, "игрок прошёл по мосту до 5-й секции (x=%.1f, конец %.1f)" % [p.global_position.x, end_x])
	check(min_y_above > 0.05 and not p.swimming, "шёл по настилу, не в воде (мин. над водой %.2f)" % min_y_above)
	check(sections[4].deck_height() > -0.1 and sections[4].deck_height() < 0.6, "deck_height() = %.2f" % sections[4].deck_height())
	await shot("05_end")

	# поджог средней секции
	teleport(side)
	aim_at(sections[2].global_position)
	var s2 := sections[2]
	s2.ignite(p)
	check(s2.burning, "секция горит")
	await wait(2.0)
	await shot("06_fire")
	Engine.time_scale = 4.0
	await wait(7.0)
	Engine.time_scale = 1.0
	await wait(0.3)
	await shot("06b_fire_spread")
	Engine.time_scale = 4.0
	t = 0.0
	while is_instance_valid(s2) and not s2.is_queued_for_deletion() and t < 40.0:
		await wait(0.5)
		t += 0.5
	var burned := not is_instance_valid(s2) or s2.is_queued_for_deletion()
	check(burned, "секция сгорела за ~%.0f с игрового времени" % t)
	var spread := false
	for i in [1, 3]:
		var b := sections[i]
		if not is_instance_valid(b) or b.burning:
			spread = true
	check(spread, "огонь перекинулся на соседние секции")
	var tail_free := false
	for i in [3, 4]:
		var b := sections[i]
		if not is_instance_valid(b) or b.is_drifting():
			tail_free = true
	check(tail_free, "хвост моста оторвался (уплывает или сгорел)")
	Engine.time_scale = 1.0
	await wait(0.5)
	await shot("07_after")
