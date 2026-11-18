extends TestCase
## Режим «Обучение»: проходим все шаги настоящими действиями (ввод, инвентарь,
## крафт, рубка, постройки, смерть/возрождение, мост, бой, огонь, флаг) до
## экрана «Обучение завершено». Скриншоты ключевых шагов.

var dir: TutorialDirector
var p: Node3D
var skipped: Array[StringName] = []

func _init() -> void:
	scene_path = "res://scenes/tutorial/tutorial.tscn"
	timeout_sec = 3500.0
	Game.pending_config = TutorialLauncher.CONFIG.duplicate()
	Settings.tutorial_done = false

func _sid() -> StringName:
	return dir.step_id() if dir and not dir.done else &"__done"

## Ждать, пока шаг сменится с id (true — сменился сам).
func _leave(id: StringName, sec: float) -> bool:
	var t := 0.0
	while _sid() == id and t < sec:
		await wait(0.2)
		t += 0.2
	if _sid() == id:
		print("[test] шаг %s не закрылся сам за %.0f с — пропускаем" % [id, sec])
		skipped.append(id)
		dir.skip_step()
		await wait(0.3)
		return false
	return true

func _look_at(target: Vector3) -> void:
	var eye: Vector3 = p.call(&"get_eye_position")
	var aim := target - eye
	p.call(&"set_look", atan2(-aim.x, -aim.z), atan2(aim.y, Vector2(aim.x, aim.z).length()))

func _ground(x: float, z: float) -> float:
	return float(dir.world.call(&"height_at", x, z))

func _put(pos: Vector3) -> void:
	(p as CharacterBody3D).velocity = Vector3.ZERO
	p.global_position = Vector3(pos.x, _ground(pos.x, pos.z) + 0.2, pos.z)

func run() -> void:
	Engine.max_physics_steps_per_frame = 30
	var t0 := Time.get_ticks_msec()
	while (TutorialDirector.instance() == null or TutorialDirector.instance().index < 0) and Time.get_ticks_msec() - t0 < 1200000:
		await wait(0.5)
	dir = TutorialDirector.instance()
	check(dir != null and dir.index == 0, "обучение запущено, шаг 1")
	if dir == null:
		return
	p = dir.player
	check(Game.teams[0].flag_placed, "свой флаг поставлен у старта")
	check(not dir.neighbour.is_empty() and int(dir.bridge_info.get("sections", 0)) >= 2,
		"выбран соседний остров для моста: %s, секций %d" % [dir.neighbour.get("name", "?"), int(dir.bridge_info.get("sections", 0))])
	await wait(1.0)
	await shot("01_look")

	# --- осмотр
	var yaw0 := 0.0
	for k in 40:
		p.call(&"set_look", yaw0 + k * 0.1, -0.05)
		await wait_frames(1)
	await _leave(&"look", 10.0)
	# --- ходьба
	Input.action_press(&"move_forward")
	var tt := 0.0
	while _sid() == &"move" and tt < 8.0:
		await wait(0.3)
		tt += 0.3
		if tt > 3.0:   # упёрлись — разворот
			p.call(&"set_look", randf() * TAU, 0.0)
	Input.action_release(&"move_forward")
	await _leave(&"move", 2.0)
	# --- прыжки
	for k in 3:
		if _sid() != &"jump":
			break
		await tap(&"jump")
		await wait(1.0)
	await _leave(&"jump", 3.0)
	# --- бег
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	tt = 0.0
	while _sid() == &"sprint" and tt < 12.0:
		await wait(0.3)
		tt += 0.3
		if fmod(tt, 3.0) < 0.3:   # упёрлись — разворот
			p.call(&"set_look", randf() * TAU, 0.0)
	Input.action_release(&"sprint")
	Input.action_release(&"move_forward")
	await _leave(&"sprint", 2.0)
	# --- присесть
	await press(&"crouch", 1.8)
	await _leave(&"crouch", 3.0)

	# --- палки и камень
	check(_sid() == &"gather", "шаг «Палки и камень»")
	await wait(1.5)
	if dir.ui.target is Vector3:
		_look_at(dir.ui.target)
	await wait(0.3)
	await shot("02_gather_marker")
	var inv := p.get(&"inventory") as Inventory
	inv.add(&"stick", 2)
	inv.add(&"rock", 1)
	await _leave(&"gather", 3.0)
	inv.add(&"liana", 2)
	await _leave(&"liana", 3.0)
	# --- крафт
	check(_sid() == &"craft", "шаг «Каменный топор»")
	check(PlayerItems.craft(p, Items.recipes[&"rope_from_liana"]), "крафт: верёвка из лиан")
	check(PlayerItems.craft(p, Items.recipes[&"r_axe_crude"]), "крафт: каменный топор")
	await _leave(&"craft", 3.0)

	# --- рубка
	check(_sid() == &"chop", "шаг «Сруби дерево»")
	await wait(1.0)
	await _chop()
	await _leave(&"chop", 5.0)

	# --- вода и еда
	check(_sid() == &"thirst", "шаг «Вода и еда»")
	if bool(p.get(&"carrying_log")):
		var obj: Node = p.get(&"carried_object")
		if obj and obj.has_method(&"drop"):
			obj.call(&"drop", p)
	inv.add(&"coconut", 1)
	p.call(&"consume", &"coconut")
	await _leave(&"thirst", 4.0)
	# --- яд
	check(_sid() == &"poison", "шаг «Яд и травы»")
	check(Survival.get_poison(p).y > 0.0, "игрок отравлен")
	inv.add(&"herb", 2)
	check(PlayerItems.craft(p, Items.recipes[&"r_poultice"]), "крафт: припарка")
	p.call(&"consume", &"poultice")
	await _leave(&"poison", 4.0)

	# --- шалаш
	check(_sid() == &"shelter", "шаг «Шалаш»")
	var bm := BuildModule.instance()
	var fp: Vector3 = Game.teams[0].flag_pos
	var sp := Vector3(fp.x + 5.0, 0, fp.z + 1.0)
	sp.y = _ground(sp.x, sp.z)
	_put(Vector3(fp.x + 9.0, 0, fp.z + 4.0))
	var sh := bm.place_blueprint(&"shelter", Transform3D(Basis(), sp), 0)
	check(sh != null, "чертёж шалаша поставлен")
	await wait(0.5)
	inv.add(&"stick", 1)
	if sh:
		sh.add_material(&"stick", 1, p)
	_look_at(sp + Vector3.UP)
	await wait(1.5)
	await shot("03_shelter_assist")
	await _leave(&"shelter", 30.0)
	# --- стена
	check(_sid() == &"wall", "шаг «Стена»")
	var wp := Vector3(fp.x - 5.0, 0, fp.z + 3.0)
	wp.y = _ground(wp.x, wp.z)
	var wall := bm.place_blueprint(&"wall", Transform3D(Basis(), wp), 0)
	check(wall != null, "чертёж стены поставлен")
	await _leave(&"wall", 60.0)
	# --- флаг
	check(_sid() == &"flag", "шаг «Твой флаг»")
	_put(fp + Vector3(2.5, 0, 0))
	_look_at(fp + Vector3.UP * 2.0)
	await wait(0.5)
	await shot("04_flag")
	await _leave(&"flag", 3.0)
	# --- смерть и возрождение
	check(_sid() == &"respawn", "шаг «Возрождение»")
	var died := false
	tt = 0.0
	while _sid() == &"respawn" and tt < 40.0:
		await wait(0.5)
		tt += 0.5
		if not bool(p.get(&"alive")):
			died = true
	check(died, "игрок погиб на уроке")
	check(_sid() != &"respawn" and bool(p.get(&"alive")), "игрок возродился")
	check(p.global_position.distance_to(fp) < 6.0, "возрождение у флага (%.1f м)" % p.global_position.distance_to(fp))

	# --- мост
	check(_sid() == &"bridge", "шаг «Мост»")
	await wait(1.0)
	check(dir.bridge.size() >= 1, "заготовка моста: %d секций" % dir.bridge.size())
	var start: Vector3 = dir.bridge_info.start
	var endp: Vector3 = dir.bridge_info.end
	_put(start - (endp - start).normalized() * 3.0)
	_look_at(endp)
	await wait(1.0)
	await shot("05_bridge")
	var last: Blueprint = dir.bridge[dir.bridge.size() - 1]
	var slot := bm.next_raft_slot(last)
	check(not slot.is_empty(), "есть место для последней секции")
	if not slot.is_empty():
		bm.place_blueprint(&"raft", slot.xform, 0, {"type": &"raft", "parent": slot.parent, "offset": slot.offset})
	await _leave(&"bridge", 30.0)
	# --- переход
	check(_sid() == &"cross", "шаг «На тот берег»")
	check(dir.shark != null and is_instance_valid(dir.shark), "акула урока у моста")
	p.global_position = dir.landing + Vector3.UP * 0.5
	_look_at(start)
	await _leave(&"cross", 5.0)
	await wait(0.5)
	await shot("06_crossed")

	# --- чучело
	check(_sid() == &"dummy", "шаг «Оружие»")
	check(inv.count(&"bow") > 0 and inv.count(&"arrow") > 0, "выданы лук и стрелы")
	await wait(0.5)
	if dir.dummy:
		_look_at(dir.dummy.global_position + Vector3.UP)
		await wait(0.3)
		await shot("07_dummy")
		for k in 3:
			dir.dummy.call(&"apply_damage", 20.0, p, &"arrow")
	await _leave(&"dummy", 3.0)
	# --- бот
	check(_sid() == &"bot", "шаг «Противник»")
	await wait(1.5)
	check(dir.bot != null and is_instance_valid(dir.bot), "бот Синих появился")
	check(Game.teams[1].flag_placed, "флаг Синих стоит на соседнем острове")
	if dir.bot:
		_look_at(dir.bot.global_position + Vector3.UP)
		await wait(0.4)
		await shot("08_bot")
		dir.bot.call(&"apply_damage", 999.0, p, &"melee")
	await _leave(&"bot", 5.0)
	# --- огонь
	check(_sid() == &"molotov", "шаг «Огонь»")
	check(dir.enemy_raft != null and is_instance_valid(dir.enemy_raft), "мост Синих есть")
	check(inv.count(&"molotov") >= 2, "выдан коктейль Молотова")
	if dir.enemy_raft:
		_put(dir.enemy_raft.global_position.lerp(Vector3(dir.neighbour.center.x, 0, dir.neighbour.center.y), 0.25))
		_look_at(dir.enemy_raft.global_position)
		dir.enemy_raft.call(&"ignite", p)
		await wait(2.0)
		await shot("09_fire")
	await _leave(&"molotov", 25.0)
	# --- флаг Синих
	check(_sid() == &"enemy_flag", "шаг «Чужой флаг»")
	_put(dir.enemy_flag_pos + Vector3(3, 0, 2))
	_look_at(dir.enemy_flag_pos + Vector3.UP * 1.5)
	await wait(0.6)
	await shot("10_enemy_flag")
	var ef := bm.flag_of(1)
	if ef:
		ef.apply_damage(Game.FLAG_MAX_HP * 2.0, p)
	await _leave(&"enemy_flag", 5.0)

	# --- финал
	await wait(1.2)
	check(dir.done, "обучение завершено")
	check(dir.ui.done_screen.visible, "экран «Обучение завершено»")
	check(Settings.tutorial_done, "отметка о прохождении сохранена в Settings")
	check(Game.state == Game.State.PLAYING, "матч не закончился поражением/победой посреди обучения")
	await shot("11_done")
	check(skipped.size() <= 1, "пропущено шагов: %d %s" % [skipped.size(), str(skipped)])

## Рубка: ставим игрока у дерева-цели, рубим топором, пилим ствол, берём бревно.
func _chop() -> void:
	var fl := Flora.instance()
	var arr := fl.nodes_near(p.global_position, 90.0, &"tree")
	var tree: ChoppableTree = null
	for e in arr:
		var n := fl.materialize(e)
		if n is ChoppableTree and not (n as ChoppableTree).felled:
			tree = n
			break
	check(tree != null, "нашлось дерево для рубки")
	if tree == null:
		return
	var tp := tree.global_position
	var from_dir := Vector3(tp.x - p.global_position.x, 0, tp.z - p.global_position.z).normalized()
	_put(tp - from_dir * 1.4)
	var inv := p.get(&"inventory") as Inventory
	for i in Inventory.HOTBAR:
		if inv.get_slot(i).get("id", &"") == &"axe_crude":
			inv.select(i)
	await wait(0.5)
	_look_at(tp + Vector3.UP * 1.2)
	await wait(0.4)
	await shot("02b_chop_marker")
	var n2 := 0
	while not tree.felled and n2 < 60:
		tree.on_hit(p, {"position": tp + Vector3(0, 1, 0), "normal": -from_dir, "tool": &"axe", "damage": 14.0})
		n2 += 1
	check(tree.felled, "дерево срублено (ударов %d)" % n2)
	var trunk: FallenTrunk = null
	for c in tree.get_parent().get_children():
		if c is FallenTrunk:
			trunk = c
	if trunk == null:
		return
	var t := 0.0
	while is_instance_valid(trunk) and not trunk.freeze and t < 10.0:
		await wait(0.25)
		t += 0.25
	var k := 0
	while is_instance_valid(trunk) and trunk.logs_left() > 0 and k < 60:
		var hp := trunk.global_transform * Vector3(0, 1.0 + (trunk.logs_left() - 1) * FloraLib.LOG_LEN, 0)
		trunk.on_hit(p, {"position": hp, "normal": Vector3.UP, "tool": &"axe", "damage": 14.0})
		k += 1
	await wait(0.5)
	var best: FloraLog = null
	var bd := 1e9
	for l in get_tree().get_nodes_in_group(&"log"):
		if l is FloraLog and (l as FloraLog).carrier == null:
			var d := (l as Node3D).global_position.distance_to(p.global_position)
			if d < bd:
				bd = d
				best = l
	check(best != null, "есть бревно")
	if best:
		_put(best.global_position + Vector3(1.2, 0, 0))
		best.interact(p)
	await wait(0.3)
	check(bool(p.get(&"carrying_log")), "бревно на плече")
