## test-timeout: 900
extends TestCase
## v5.2 (агент K): поведение животных.
##  17 распорядок дня (Routines) · 21 краб замирает и ловится, мелочь гибнет под ногой ·
##  22 раковина отшельника · 24 кокос с пальмы бьёт по голове, ветер срывает кокосы ·
##  25 варан чует тушу, змея — дрожь шагов, ящерица удирает · 26 морской ёж → хромота, сандалии ·
##  30 пальмовый вор тащит кокос ночью · 31 чайка выхватывает еду · 32 попугай кричит на чужого ·
##  спотыкание о кокос.

var p: Player
var fauna: Fauna
var w: Node

func _init() -> void:
	timeout_sec = 880.0

func _set_hour(h: float) -> void:
	Routines.debug_hour = h

func _think_n(a: Animal, n: int) -> void:
	for i in n:
		a._routine_t = 0.0
		a._think_t = 0.0
		a.tick(0.3)

func run() -> void:
	await wait(1.0)
	p = get_tree().get_first_node_in_group(&"player") as Player
	w = get_tree().get_first_node_in_group(&"world")
	check(p != null, "игрок есть")
	fauna = (load("res://scenes/fauna/fauna.tscn") as PackedScene).instantiate() as Fauna
	fauna.set(&"auto_populate", false)
	scene.add_child(fauna)
	await wait(1.0)
	var ext: Node = fauna.ext
	check(ext != null, "FaunaExt создан у Fauna")
	var base := p.global_position

	# ---------- 17: распорядок ----------
	check(Routines.mode(&"iguana", 8.0, false) == &"bask", "игуана утром греется")
	check(Routines.mode(&"iguana", 23.0, false) == &"hidden", "игуана ночью в укрытии")
	check(Routines.mode(&"crab", 13.0, false) == &"hidden" and Routines.mode(&"crab", 13.0, true) == &"active", "краб днём: прилив — в норе, отлив — снаружи")
	check(Routines.mode(&"turtle", 23.0, false) == &"active" and Routines.mode(&"turtle", 12.0, false) == &"rest", "черепаха активна ночью")
	check(Routines.activity(&"shark", 18.5) > 1.3 and Routines.activity(&"shark", 13.0) < 0.9, "акулы на закате активнее, в полдень ленивее (%.2f / %.2f)" % [Routines.activity(&"shark", 18.5), Routines.activity(&"shark", 13.0)])
	check(Routines.mode(&"gull", 23.0, false) == &"rest", "чайки ночью сидят")
	var ig := fauna.spawn(&"iguana", base + Vector3(25, 0, 0), 8.0)
	_set_hour(8.0)
	await wait(0.3)
	_think_n(ig, 6)
	check(ig.routine == &"bask" and ig.state == &"bask", "игуана в 8:00 — греется (routine %s, state %s)" % [ig.routine, ig.state])
	_set_hour(23.0)
	_think_n(ig, 6)
	check(ig.routine == &"hidden" and ig.state in [&"to_cover", &"rest_hidden"], "игуана ночью уходит в укрытие (%s)" % ig.state)
	ig.queue_free()
	_set_hour(13.0)
	Routines.debug_hour = -1.0

	# ---------- 21: краб замирает и ловится ----------
	var crab := fauna.spawn(&"crab", base + Vector3(1.4, 0, 0), 4.0)
	await wait(0.2)
	p.crouching = true
	crab._set_state(&"idle")
	var frozen := false
	for i in 20:
		crab._think_t = 0.0
		crab.tick(0.3)
		if crab.state == &"freeze":
			frozen = true
			break
		crab._set_state(&"idle")
	check(frozen, "к крабу подкрадываются вприсядку — он замирает")
	crab._set_state(&"freeze")
	check(crab.get_interact_text(p).begins_with("E — поймать"), "у замершего краба подсказка «поймать»")
	var had := p.inventory.count(&"crab_live")
	crab.interact(p)
	await wait_frames(2)
	check(p.inventory.count(&"crab_live") == had + 1 and not is_instance_valid(crab), "краб пойман: «Живой краб» в инвентаре")
	p.crouching = false

	# ---------- 21: мелочь гибнет под ногой ----------
	var sc := fauna.spawn(&"scorpion", p.global_position + Vector3(0.05, 0, 0), 2.0)
	sc.global_position.y = p.global_position.y
	await wait(0.2)
	p.velocity = Vector3(1.5, 0, 0)
	sc.lod = 0
	sc._crush_cd = 0.0
	AnimalBehaviourShim.crush(sc)
	check(sc.dead and sc.has_meta(&"crushed"), "наступили на скорпиона — раздавлен")
	p.velocity = Vector3.ZERO
	var sc2 := fauna.spawn(&"scorpion", p.global_position + Vector3(0.05, 0, 0), 2.0)
	sc2.global_position.y = p.global_position.y
	sc2._crush_cd = 0.0
	AnimalBehaviourShim.crush(sc2)
	check(not sc2.dead, "стоящий на месте — не давит")
	sc2.queue_free()

	# ---------- 22: раковина отшельника ----------
	var hc := fauna.spawn(&"hermit_crab", base + Vector3(-6, 0, 3), 2.0)
	await wait(0.2)
	var n_pick := get_tree().get_nodes_in_group(&"pickups").size()
	hc.die(p)
	await wait_frames(3)
	var shell_found := false
	for n in get_tree().get_nodes_in_group(&"pickups"):
		var pu := n as ItemPickup
		if pu and pu.global_position.distance_to(hc.global_position) < 3.0:
			for s: Dictionary in pu.stacks:
				if s.id == &"seashell":
					shell_found = true
	check(shell_found and get_tree().get_nodes_in_group(&"pickups").size() > n_pick, "после разделки отшельника остаётся раковина")

	# ---------- 24: кокос бьёт по голове ----------
	var hp0 := p.health
	var nut := FloraPickup.make_coconut()
	scene.add_child(nut)
	nut.global_position = p.global_position + Vector3(0, 9.0, 0)
	nut.freeze = false
	await wait(2.5)
	check(p.health < hp0, "кокос с высоты 9 м по голове: %.0f → %.0f" % [hp0, p.health])
	if is_instance_valid(nut):
		nut.queue_free()
	p.health = p.max_health
	# ветер срывает кокосы (с пальм вокруг игрока, если есть)
	var palms := 0
	for t in get_tree().get_nodes_in_group(&"choppable"):
		if StringName(t.get(&"kind")) == &"palm" and int(t.get(&"coconuts")) > 0 and (t as Node3D).global_position.distance_to(p.global_position) < 60.0:
			palms += 1
	var fake := FakePalm.new()
	fake.add_to_group(&"choppable")
	scene.add_child(fake)
	fake.global_position = p.global_position + Vector3(8, 0, 0)
	ext.debug_wind = 4.0
	await wait(4.0)
	check(fake.drops == 0, "в слабый ветер (4 м/с) кокосы не падают")
	ext.debug_wind = 30.0
	await wait(12.0)
	ext.debug_wind = -1.0
	check(fake.drops > 0 and int(ext.stats.wind_drops) >= fake.drops, "шторм (30 м/с) срывает кокосы: %d за 12 с (пальм у игрока: %d+1)" % [fake.drops, palms])
	fake.queue_free()

	# ---------- спотыкание, хромота ----------
	var m0 := p._env_speed()
	p.stumble()
	check(p._env_speed() < m0 * 0.6, "споткнулся — скорость падает (%.2f → %.2f)" % [m0, p._env_speed()])
	await wait(0.8)
	check(p._env_speed() > m0 * 0.9, "через 0,8 с — снова на ногах")

	# ---------- 26: морской ёж ----------
	check(not FaunaExtShim.footwear(p), "босиком (сандалий нет)")
	p.limp(5.0)
	var lm := p._env_speed()
	check(lm < m0 * 0.8, "укол ежа: хромота замедляет (%.2f)" % lm)
	p.limp_t = 0.0
	p.inventory.add(&"sandals", 1)
	check(FaunaExtShim.footwear(p), "сандалии в инвентаре — защищают ступни")
	p.inventory.remove(&"sandals", 1)

	# ---------- 25: варан чует тушу, змея — шаги, ящерица удирает ----------
	var mon := fauna.spawn(&"monitor", base + Vector3(-30, 0, -10), 6.0)
	await wait(0.2)
	mon._set_state(&"idle")
	var pc := get_node(^"/root/Perception")
	pc.call(&"emit", &"carrion", mon.global_position + Vector3(20, 0, 0), 80.0, 1.0, null)
	check(mon.state == &"investigate" and mon.move_to.distance_to(mon.global_position + Vector3(20, 0, 0)) < 1.0, "варан учуял тушу в 20 м — идёт к ней (%s)" % mon.state)
	var src := mon.global_position + Vector3(25, 0, 0)
	var k_up := AnimalBehaviourShim.downwind(mon, mon.global_position + Vector3(25, 0, 0))
	var k_dn := AnimalBehaviourShim.downwind(mon, mon.global_position - Vector3(25, 0, 0))
	check(absf(k_up - k_dn) > 0.01 or AnimalBehaviourShim.wind_speed(mon) < 0.5, "запах зависит от ветра (%.2f / %.2f)" % [k_up, k_dn])
	mon.queue_free()
	var sn := fauna.spawn(&"snake", base + Vector3(30, 0, 10), 4.0)
	await wait(0.2)
	sn._set_state(&"idle")
	pc.call(&"step", p, sn.global_position + Vector3(0, 0, 0.15), 0.1, 0.4)   # крадётся
	check(sn.state == &"idle", "змея не чувствует крадущегося")
	pc.call(&"step", p, sn.global_position + Vector3(4, 0, 0), 1.0, 1.0)      # бег
	check(sn.state == &"flee", "змея чувствует дрожь от бега в 4 м — уползает (%s)" % sn.state)
	sn.queue_free()
	var liz := fauna.spawn(&"iguana", base + Vector3(30, 0, -10), 4.0)
	await wait(0.2)
	liz._set_state(&"idle")
	pc.call(&"step", p, liz.global_position + Vector3(12, 0, 0), 1.0, 1.0)
	check(liz.state == &"flee", "игуана удирает от шагов в 12 м (%s)" % liz.state)
	liz.queue_free()

	# ---------- 30: пальмовый вор тащит кокос ----------
	_set_hour(23.0)
	var cc := fauna.spawn(&"coconut_crab", base + Vector3(14, 0, 14), 4.0)
	var nut2 := FloraPickup.make_coconut()
	scene.add_child(nut2)
	var np := base + Vector3(19, 0, 14)
	nut2.global_position = Vector3(np.x, Fauna.ground_y_at(fauna, np.x, np.z) + 0.12, np.z)
	await wait(0.3)
	cc.home = cc.global_position + Vector3(-6, 0, 0)
	cc._set_state(&"idle")
	cc.state_t = 3.0
	_think_n(cc, 1)
	check(cc.state == &"fetch", "ночью пальмовый вор идёт к кокосу (%s)" % cc.state)
	var n0 := nut2.global_position
	var moved := false
	for i in 120:
		cc._think_t = 1.0
		cc.tick(0.1)
		if cc.state == &"drag" and nut2.global_position.distance_to(n0) > 1.0:
			moved = true
			break
	check(moved, "кокос волочится (сдвинут на %.1f м, состояние %s)" % [nut2.global_position.distance_to(n0), cc.state])
	cc.queue_free()
	Routines.debug_hour = -1.0

	# ---------- 31: чайка выхватывает еду ----------
	var gulls := fauna.spawn_flock(&"gull", base + Vector3(-20, 0, 20), 3, 10.0)
	var food := ItemPickup.spawn(scene, base + Vector3(-16, 0.3, 18), [{"id": &"meat_raw", "n": 2}])
	await wait(0.3)
	var g := gulls[0]
	g.set_meta(&"dive", {"target": food, "phase": &"in", "t": 0.0})
	for i in 200:
		g.tick(0.05)
		if not g.has_meta(&"dive") or g.get_meta(&"dive").phase == &"out":
			break
	var left := 0
	if is_instance_valid(food):
		for s: Dictionary in food.stacks:
			left += int(s.n)
	check(left == 1 and g.stolen.size() == 1, "чайка спикировала и унесла 1 мясо (осталось %d)" % left)
	if is_instance_valid(food):
		food.queue_free()

	# ---------- 32: попугай-сторож ----------
	var par := fauna.spawn(&"parrot", p.global_position + Vector3(1, 1.5, 0), 4.0)
	await wait(0.2)
	par.tame_by(p)
	var stranger := Node3D.new()
	stranger.add_to_group(&"characters")
	scene.add_child(stranger)
	stranger.global_position = p.global_position + Vector3(10, 0, 0)
	var a0 := int(ext.stats.parrot_alarms)
	await wait(2.5)
	check(int(ext.stats.parrot_alarms) > a0, "попугай кричит: в 10 м чужой")
	stranger.queue_free()

class FakePalm extends Node3D:
	var kind: StringName = &"palm"
	var felled := false
	var coconuts := 6
	var drops := 0
	func _drop_coconut(_by: Node) -> void:
		drops += 1

# Тонкие обёртки над приватными помощниками (чтобы тест не зависел от их сигнатур).
class AnimalBehaviourShim:
	static func crush(a: Animal) -> void:
		preload("res://scripts/fauna/animal_behaviour.gd").check_crush(a)
	static func downwind(a: Animal, src: Vector3) -> float:
		return preload("res://scripts/fauna/animal_behaviour.gd").downwind_k(a, src)
	static func wind_speed(a: Animal) -> float:
		var w: Node = Fauna._world_of(a)
		return float(w.call(&"wind_speed")) if w and w.has_method(&"wind_speed") else 0.0

class FaunaExtShim:
	static func footwear(ch: Node) -> bool:
		return preload("res://scripts/fauna/fauna_ext.gd").has_footwear(ch)
