extends BuildTestCase
## Оборона: частокол линией по сокетам + ворота; ворота пускают своих (сами
## открываются) и не пускают чужих; колья ранят чужака; вышка с лестницей —
## игрок поднимается; каменный фундамент не горит, стена на нём — горит;
## Молотов поджигает ворота — они сгорают.

func _init() -> void:
	timeout_sec = 520.0

func run() -> void:
	if not await setup_build():
		return
	var bm := build_mode()
	# --- частокол через режим стройки (призрак) ---
	var z0 := -8.0
	teleport(ground(-4.5, z0 - 5.0) + Vector3.UP * 0.1)
	await wait(0.3)
	await tap(&"build_menu")
	for id: StringName in [&"palisade", &"gate", &"spikes", &"watchtower", &"foundation", &"chest", &"log_holder", &"workbench", &"raft_gate", &"raft_pile"]:
		check(bm.entries.has(id), "в книге стройки есть «%s»" % BuildDefs.name_of(id))
	bm.start_place(&"palisade")
	aim_at(ground(-4.5, z0))
	await wait(0.4)
	check(bm.valid, "частокол можно поставить на землю: %s" % bm.reason)
	await shot("01_ghost")
	await tap(&"attack")
	await wait_frames(3)
	bm.close()
	var first: Blueprint = null
	for b in mod.blueprints():
		if b.def_id == &"palisade":
			first = b
	check(first != null, "частокол поставлен из режима стройки")
	if first == null:
		return
	# дальше — по сокетам линией: +X (ворота), +X, +X
	var line: Array[Blueprint] = [first]
	var gate: BuildGate = null
	for i in 3:
		var last := line[line.size() - 1]
		var s := mod.find_socket(&"palisade", last.base_xform * Vector3(3.0, 0, 0), 1.0)
		check(not s.is_empty(), "у частокола есть сокет продолжения (%d)" % i)
		if s.is_empty():
			return
		var id: StringName = &"gate" if i == 0 else &"palisade"
		var b := mod.place_blueprint(id, s.xform, 0)
		line.append(b)
		if b is BuildGate:
			gate = b as BuildGate
	check(gate != null, "ворота встали в линию частокола")
	for b in line:
		finish(b)
		check(b.is_complete(), "%s достроен(ы)" % BuildDefs.name_of(b.def_id))
	check(int(BuildDefs.cost(&"palisade").get(&"log", 0)) == BuildDefs.PAL_N, "частокол: %s" % BuildDefs.cost_text(&"palisade"))
	check(int(BuildDefs.cost(&"gate").get(&"log", 0)) >= 8, "ворота: %s" % BuildDefs.cost_text(&"gate"))
	var gc := gate.base_xform.origin
	var gn := gate.base_xform.basis.z.normalized()   # «снаружи» — сторона -gn (откуда смотрел игрок)
	# вид снаружи
	teleport(gc - gn * 9.0 + Vector3(2.0, 0.0, 0.0))
	p.global_position.y = BuildEnv.height_at(p.global_position.x, p.global_position.z) + 0.1
	aim_at(gc + Vector3.UP * 1.6)
	await wait(0.8)
	check(not gate.leaf_open, "ворота закрыты, пока своих рядом нет")
	await shot("02_palisade_gate")

	# --- чужак упирается в ворота ---
	teleport(ground(gc.x - 14.0, gc.z - 14.0) + Vector3.UP * 0.2)   # игрок далеко
	var outside := gc - gn * 4.0
	var inside := gc + gn * 4.0
	var enemy := spawn_walker(ground(outside.x, outside.z) + Vector3.UP * 0.1, 1)
	enemy.target = inside
	enemy.walking = true
	await wait(4.0)
	var ez := (enemy.global_position - gc).dot(gn)
	check(ez < -0.2, "чужак не прошёл через закрытые ворота (%.2f м до створки)" % ez)
	check(not gate.leaf_open, "ворота не открылись перед чужим")
	gate.interact(enemy)
	await wait(0.2)
	check(not gate.leaf_open and not gate.held_open, "чужой не может открыть ворота (E)")
	enemy.walking = false
	enemy.global_position = ground(gc.x - 12.0, gc.z - 3.0) + Vector3.UP * 0.2

	# --- свой проходит: створка открывается сама ---
	var from := outside - gn * 1.0
	teleport(ground(from.x, from.z) + Vector3.UP * 0.1)
	aim_at(inside + Vector3.UP * 1.5)
	await wait(0.3)
	Input.action_press(&"move_forward")
	var t := 0.0
	var opened := false
	var shot_open := false
	while t < 5.0 and (p.global_position - gc).dot(gn) < 2.5:
		await wait(0.2)
		t += 0.2
		opened = opened or gate.leaf_open
		if opened and not shot_open and (p.global_position - gc).dot(gn) > -1.2:
			shot_open = true
			await shot("03_gate_open")
	Input.action_release(&"move_forward")
	check(opened, "ворота открылись перед своим")
	check((p.global_position - gc).dot(gn) > 1.5, "игрок прошёл через ворота (%.2f м за створкой)" % (p.global_position - gc).dot(gn))
	teleport(inside + gn * 6.0 + Vector3.UP * 0.2)
	p.global_position.y = BuildEnv.height_at(p.global_position.x, p.global_position.z) + 0.1
	await wait(2.6)
	check(not gate.leaf_open, "ворота закрылись за своим")
	# E своим — держать открытыми
	check(gate.set_gate_open(true, p) and gate.held_open, "свой держит ворота открытыми")
	check(not gate.set_gate_open(false, enemy), "чужой не может управлять воротами")
	gate.set_gate_open(false, p)
	# частокол не пускает
	var wall_c := line[2].base_xform.origin
	enemy.global_position = ground(wall_c.x - gn.x * 3.5, wall_c.z - gn.z * 3.5) + Vector3.UP * 0.1
	enemy.target = wall_c + gn * 3.0
	enemy.walking = true
	await wait(3.0)
	check((enemy.global_position - wall_c).dot(gn) < -0.15, "частокол не пускает чужака")
	enemy.walking = false

	# --- колья ---
	var sp := mod.place_blueprint(&"spikes", Transform3D(Basis(), ground(0.0, 9.0)), 0)
	finish(sp)
	check(sp is BuildSpikes and sp.is_complete(), "колья готовы: %s" % BuildDefs.cost_text(&"spikes"))
	var friend := spawn_walker(ground(-1.0, 12.5) + Vector3.UP * 0.1, 0)
	friend.target = ground(-1.0, 8.0)
	friend.walking = true
	enemy.global_position = ground(0.8, 12.5) + Vector3.UP * 0.1
	enemy.target = ground(0.8, 8.0)
	enemy.health = 100.0
	enemy.hits = 0
	enemy.walking = true
	var sv := sp.base_xform.origin + Vector3(2.8, 0.0, 2.4)
	teleport(ground(sv.x, sv.z) + Vector3.UP * 0.1)
	aim_at(sp.base_xform.origin + Vector3(0.0, 0.4, 0.5))
	await wait(1.4)
	friend.walking = false
	friend.global_position = ground(-6.0, 15.0) + Vector3.UP * 0.2
	await shot("04_spikes")
	await wait(1.7)
	check(enemy.health < 100.0, "колья ранили чужака (hp %.0f, ударов %d)" % [enemy.health, (sp as BuildSpikes).hits_dealt])
	check(friend.health >= 100.0, "своих колья не ранят")
	check((enemy.global_position - sp.base_xform.origin).z > 0.0, "чужака отбросило от кольев")
	enemy.walking = false
	friend.walking = false
	friend.queue_free()

	# --- сторожевая вышка + лестница ---
	var tw := mod.place_blueprint(&"watchtower", Transform3D(Basis(), ground(-16.0, 8.0)), 0)
	var st := mod.find_socket(&"stairs", tw.base_xform * Vector3(0, 0, 4.0), 4.0)
	check(not st.is_empty(), "у вышки есть сокет лестницы")
	var stairs: Blueprint = null
	if not st.is_empty():
		stairs = mod.place_blueprint(&"stairs", st.xform, 0, {}, st.ctx)
	finish(tw)
	check(tw.is_complete(), "вышка достроена: %s" % BuildDefs.cost_text(&"watchtower"))
	if stairs:
		finish(stairs)
		var run := BuildDefs.stairs_dims(stairs.ctx).y
		var foot: Vector3 = stairs.base_xform * Vector3(0, 0, run * 0.5 + 1.2)
		foot.y = BuildEnv.height_at(foot.x, foot.z) + 0.1
		teleport(foot)
		var dd := tw.base_xform.origin - foot
		p.set_look(atan2(-dd.x, -dd.z), 0.0)
		await wait(0.3)
		Input.action_press(&"move_forward")
		t = 0.0
		var top := tw.base_xform.origin.y + BuildDefs.TOWER_H
		while t < 8.0 and p.global_position.y < top - 0.2:
			await wait(0.2)
			t += 0.2
		Input.action_release(&"move_forward")
		await wait(0.3)
		check(p.global_position.y > top - 0.4, "игрок поднялся на вышку (y=%.2f, настил %.2f)" % [p.global_position.y, top])
	var tv := tw.base_xform.origin + Vector3(9.0, 0.0, 9.0)
	teleport(ground(tv.x, tv.z) + Vector3.UP * 0.1)
	aim_at(tw.base_xform.origin + Vector3.UP * 2.6)
	await wait(0.6)
	await shot("05_tower")

	# --- каменный фундамент: не горит; стена на нём горит ---
	var fd := mod.place_blueprint(&"foundation", Transform3D(Basis(), ground(14.0, -2.0)), 0)
	var ws := mod.find_socket(&"wall", fd.base_xform * Vector3(0, BuildDefs.FOUND_H, -1.5), 1.0)
	check(not ws.is_empty(), "на фундаменте есть сокет стены")
	var fw: Blueprint = null
	if not ws.is_empty():
		fw = mod.place_blueprint(&"wall", ws.xform, 0)
		finish(fw)
	finish(fd)
	check(fd.is_complete() and not fd.has_wood(), "фундамент из камня: %s" % BuildDefs.cost_text(&"foundation"))
	Combat.ignite_area(fd.base_xform.origin + Vector3.UP * 0.6, 1.6, enemy, 8.0)
	await wait(0.5)
	check(not fd.burning, "каменный фундамент не загорается")
	check(fw == null or fw.burning, "деревянная стена на фундаменте горит")

	# --- Молотов по воротам ---
	var gate_ref: WeakRef = weakref(gate)
	Combat.ignite_area(gc - gn * 0.8, 2.0, enemy, 12.0)
	await wait(0.4)
	check(gate.burning, "ворота загорелись от Молотова")
	teleport(gc - gn * 9.0 + Vector3(-3.0, 0.0, 0.0))
	p.global_position.y = BuildEnv.height_at(p.global_position.x, p.global_position.z) + 0.1
	aim_at(gc + Vector3.UP * 1.4)
	await wait(2.5)
	await shot("06_gate_fire")
	Engine.time_scale = 4.0
	t = 0.0
	while gate_ref.get_ref() != null and not (gate_ref.get_ref() as Node).is_queued_for_deletion() and t < 90.0:
		await wait(0.5)
		t += 0.5
	Engine.time_scale = 1.0
	var gone := gate_ref.get_ref() == null or (gate_ref.get_ref() as Node).is_queued_for_deletion()
	check(gone, "ворота сгорели (~%.0f с)" % t)
	check(is_instance_valid(fd) and fd.is_complete(), "фундамент цел после пожара")
	await wait(0.5)
	await shot("07_after_fire")
	enemy.global_position = gc - gn * 3.0 + Vector3.UP * 0.3
	enemy.target = gc + gn * 4.0
	enemy.walking = true
	await wait(3.0)
	check((enemy.global_position - gc).dot(gn) > 0.5, "через сгоревшие ворота чужак проходит")
