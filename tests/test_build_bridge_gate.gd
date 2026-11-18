extends BuildTestCase
## Мост с воротами и сваями: берег → секция → секция с воротами → секция →
## секция на сваях → секция. Ворота не пускают чужака, свой проходит.
## Секция на сваях не качается и не уплывает. Ремонт секции. Огонь по
## мосту ползёт медленно; ворота сгорают, хвост до свай уплывает, а свая стоит.
## API ботов: defs, find_bridge_target, next_raft_slot, structures_of.

class TwoIslands extends Node:
	var a: Node
	var off := 130.0
	func _ready() -> void:
		add_to_group(&"world")
	func height_at(x: float, z: float) -> float:
		return maxf(float(a.call(&"height_at", x, z)), float(a.call(&"height_at", x - off, z)))
	func water_level() -> float:
		return 0.0
	func is_land(x: float, z: float) -> bool:
		return height_at(x, z) > 0.05
	func islands() -> Array:
		return [{"center": Vector2.ZERO, "radius": 55.0, "kind": "home", "team": 0},
			{"center": Vector2(off, 0.0), "radius": 55.0, "kind": "home", "team": 1}]

var sec: Array[Blueprint] = []

func _init() -> void:
	timeout_sec = 420.0

func run() -> void:
	if not await setup_build():
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
	check(not first.is_empty(), "место у берега (x=%.1f)" % d)
	if first.is_empty():
		return
	sec.append(mod.place_blueprint(&"raft", first.xform, 0))
	var kinds: Array[StringName] = [&"raft_gate", &"raft", &"raft_pile", &"raft"]
	for k in kinds:
		var s := mod.next_raft_slot(sec[sec.size() - 1])
		check(not s.is_empty(), "next_raft_slot даёт место для «%s»" % BuildDefs.name_of(k))
		if s.is_empty():
			return
		sec.append(mod.place_blueprint(k, s.xform, 0, {"type": &"raft", "parent": s.parent, "offset": s.offset}))
	for b in sec:
		finish(b)
	var all_ok := true
	for b in sec:
		all_ok = all_ok and b.is_complete()
	check(all_ok, "все 5 секций достроены")
	var gate := sec[1] as BuildGate
	var pile := sec[3]
	check(gate != null, "секция с воротами — BuildGate (%s)" % BuildDefs.cost_text(&"raft_gate"))
	check(pile.anchor.get("type") == &"pile", "секция на сваях стоит сама (%s)" % BuildDefs.cost_text(&"raft_pile"))
	check(mod.structures_of(0).size() == 5 and mod.structures_by_def(0, &"raft_gate").size() == 1, "structures_of / structures_by_def")
	var cat: Dictionary = mod.defs
	check(cat.has(&"palisade") and (cat[&"raft_pile"].cost as Dictionary).get(&"log", 0) == 10 and cat[&"gate"].size is Vector3,
		"каталог defs: %d чертежей" % cat.size())
	await wait(1.0)
	# сваи: не качается
	var py := pile.global_position.y
	var ry := sec[2].global_position.y
	var rr := sec[2].global_basis.get_euler()
	var pb := pile.global_basis.get_euler()
	await wait(1.5)
	check(absf(pile.global_position.y - py) < 0.01 and (pile.global_basis.get_euler() - pb).length() < 0.002, "секция на сваях не качается")
	check(absf(sec[2].global_position.y - ry) + (sec[2].global_basis.get_euler() - rr).length() > 0.002, "обычная секция качается")
	var side := Vector3(sec[2].global_position.x - 4.0, 0.0, 10.0)
	while BuildEnv.height_at(side.x, side.z) < 0.3 and side.x > 0.0:
		side.x -= 1.0
	side.y = BuildEnv.height_at(side.x, side.z) + 0.1
	teleport(side)
	aim_at(sec[2].global_position + Vector3(0, 0.8, 0))
	await wait(0.6)
	await shot("01_bridge")

	# чужак упирается в ворота на мосту
	var gx := gate.global_position.x
	var enemy := spawn_walker(sec[0].global_position + Vector3(0, 0.35, 0), 1)
	enemy.target = sec[2].global_position
	enemy.walking = true
	await wait(3.5)
	check(enemy.global_position.x < gx - 0.1 and enemy.global_position.y > wl - 0.3, "чужак не прошёл ворота на мосту (x=%.2f, ворота %.2f)" % [enemy.global_position.x, gx])
	await shot("02_enemy_at_gate")
	enemy.walking = false
	enemy.global_position = ground(d - 14.0, -6.0) + Vector3.UP * 0.2

	# свой проходит по всему мосту
	var shore_pos := sec[0].global_position + Vector3(-4.2, 0.0, 0.0)
	shore_pos.y = BuildEnv.height_at(shore_pos.x, shore_pos.z) + 0.15
	teleport(shore_pos)
	p.set_look(-PI * 0.5, deg_to_rad(-8.0))
	await wait(0.4)
	var end_x := sec[4].global_position.x
	Input.action_press(&"move_forward")
	var t := 0.0
	var opened := false
	while t < 10.0 and p.global_position.x < end_x:
		await wait(0.2)
		t += 0.2
		opened = opened or gate.leaf_open
	Input.action_release(&"move_forward")
	check(opened, "ворота на мосту открылись перед своим")
	check(p.global_position.x >= end_x - 0.4 and not p.swimming, "свой прошёл по мосту до конца (x=%.1f из %.1f)" % [p.global_position.x, end_x])
	teleport(side)
	await wait(2.5)
	check(not gate.leaf_open, "ворота за своим закрылись")

	# ремонт: топором отрубили брёвна — достраиваем
	var s2 := sec[2]
	s2.apply_damage(90.0, enemy, &"axe")
	var lost := s2.total_count(&"log") - s2.filled_count(&"log")
	check(lost >= 1 and not s2.is_complete(), "секция повреждена (снято брёвен: %d)" % lost)
	s2.add_material(&"log", lost)
	s2.add_material(&"stick", 9)
	s2.add_material(&"rope", 9)
	check(s2.is_complete(), "секция отремонтирована")

	# огонь: ворота горят; по мосту огонь ползёт медленно
	gate.ignite(enemy)
	check(gate.burning, "секция с воротами горит")
	aim_at(gate.global_position + Vector3.UP * 1.0)
	Engine.time_scale = 4.0
	await wait(6.0)
	Engine.time_scale = 1.0
	check(not sec[0].burning and not sec[2].burning, "через 6 с огонь ещё не перекинулся на соседей")
	await wait(1.5)
	await shot("03_gate_fire")
	Engine.time_scale = 4.0
	await wait(8.0)
	check(sec[0].burning or sec[2].burning or not is_instance_valid(sec[2]), "через ~14 с огонь пополз по мосту")
	var gref := weakref(gate)
	t = 0.0
	while gref.get_ref() != null and not (gref.get_ref() as Node).is_queued_for_deletion() and t < 70.0:
		await wait(0.5)
		t += 0.5
	check(gref.get_ref() == null or (gref.get_ref() as Node).is_queued_for_deletion(), "ворота на мосту сгорели")
	for b in sec:
		if is_instance_valid(b) and not b.is_queued_for_deletion():
			b.extinguish()
	Engine.time_scale = 1.0
	await wait(0.5)
	check(not is_instance_valid(sec[2]) or sec[2].is_drifting() or sec[2].is_queued_for_deletion(), "секция за воротами оторвалась")
	check(is_instance_valid(pile) and not pile.is_drifting() and pile.global_position.distance_to(pile.base_xform.origin) < 1.0,
		"секция на сваях стоит на месте")
	check(is_instance_valid(sec[4]) and not sec[4].is_drifting(), "секция за сваями держится за них")
	await wait(0.5)
	await shot("04_after_fire")

	# свая посреди воды
	var deep := Vector3(d + 22.0, wl, 8.0)
	var pr := mod.pile_raft(deep, 0.0)
	check(pr.ok, "секцию на сваях можно поставить посреди воды: %s" % pr.reason)
	var shallow := mod.pile_raft(ground(0.0, 0.0), 0.0)
	check(not shallow.ok, "на суше свая не ставится: %s" % shallow.reason)
	var lone := mod.place_blueprint(&"raft_pile", pr.xform, 0)
	finish(lone)
	check(lone.is_complete() and lone.anchor.get("type") == &"pile", "одиночная секция на сваях готова")
	lone.detach("тест")
	await wait(1.0)
	check(not lone.is_drifting(), "свая не уплывает даже без связей")

	# find_bridge_target: два острова (мок мира)
	var tw := TwoIslands.new()
	tw.a = BuildEnv.world()
	scene.add_child(tw)
	BuildEnv._world_cache = null
	var bt := mod.find_bridge_target(0, 1)
	check(bool(bt.get("ok", false)), "find_bridge_target нашёл пролив")
	if bt.get("ok", false):
		var dir: Vector3 = bt.dir
		var gap := (bt.end as Vector3).x - (bt.start as Vector3).x
		check(dir.x > 0.9, "мост идёт к острову B (dir %s)" % str(dir))
		check(int(bt.sections) * BuildDefs.RAFT_L >= float(bt.length) - 0.1 and int(bt.sections) <= int(ceil(gap / BuildDefs.RAFT_L)) + 2,
			"секций %d на %.1f м воды (пролив %.1f м), из них на сваях %d" % [int(bt.sections), float(bt.length), gap, int(bt.piles)])
		var xf: Transform3D = bt.xform
		check(BuildEnv.height_at(xf.origin.x, xf.origin.z) < wl - 0.3, "первая секция — на воде у берега A")
		var fwd := -xf.basis.z.normalized()
		check(fwd.dot(dir) > 0.95, "секция смотрит (-Z) на остров B")
	tw.queue_free()
	BuildEnv._world_cache = null
