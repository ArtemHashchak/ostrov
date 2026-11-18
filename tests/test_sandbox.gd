extends TestCase
## «Полигон»: сцена собирается, все точки быстрого перемещения доступны
## (скриншот каждой зоны), меню F1 открывается, создаются бот и животное,
## полёт V двигает игрока сквозь стену, бессмертие держит здоровье.

var sb: Sandbox

func _init() -> void:
	scene_path = "res://scenes/sandbox/sandbox.tscn"
	timeout_sec = 3500.0

func run() -> void:
	Engine.max_physics_steps_per_frame = 30
	sb = scene as Sandbox
	var t0 := Time.get_ticks_msec()
	while not sb.is_built and Time.get_ticks_msec() - t0 < 1200000:
		await wait(0.5)
	check(sb.is_built, "полигон собран за %d с" % int((Time.get_ticks_msec() - t0) / 1000.0))
	if not sb.is_built:
		return
	var p := sb.player
	var z := sb.zones
	check(p != null and p.alive, "игрок на полигоне")
	var need: Array[StringName] = [&"hub", &"flora", &"fauna", &"items", &"range", &"build", &"bridge", &"survival",
		&"beach", &"sea", &"reef", &"bots"]
	for id in need:
		check(z.points.has(id), "есть точка перемещения: %s" % id)
	# содержимое зон
	var fa := Fauna.instance()
	var species := {}
	if fa:
		for a in fa.animals:
			if is_instance_valid(a):
				species[a.species] = true
	check(species.size() >= 13, "в загонах все виды животных (%d)" % species.size())
	var pickups := get_tree().get_nodes_in_group(&"pickups").size()
	check(pickups >= 60, "предметы разложены на столах (%d)" % pickups)
	var bm := BuildModule.instance()
	var defs := {}
	for b in bm.blueprints():
		defs[b.def_id] = true
	var all_defs: Array[StringName] = [&"wall", &"wall_window", &"wall_door", &"door", &"platform", &"stairs", &"roof",
		&"shelter", &"fire_pit", &"raft", &"palisade", &"gate", &"spikes", &"watchtower", &"foundation", &"chest",
		&"log_holder", &"workbench", &"raft_gate"]
	var missing: Array[String] = []
	for d in all_defs:
		if not defs.has(d):
			missing.append(String(d))
	check(missing.is_empty(), "все постройки на месте (нет: %s)" % ", ".join(missing))
	check(Game.teams[0].flag_placed, "флаг команды стоит в зоне стройки")
	check(get_tree().get_nodes_in_group(&"dummies").size() >= 4, "чучела на стрельбище")
	check(get_tree().get_nodes_in_group(&"sv_station").size() >= 10, "станции выживания и мусор на пляже")
	# быстрое перемещение по всем точкам + скриншоты
	var i := 0
	for id: StringName in z.order:
		sb.panel.go(id)
		await wait(2.5 if i == 0 else 1.6)
		var pt: Dictionary = z.points[id]
		var d := p.global_position.distance_to(pt.pos)
		check(d < 3.0, "перемещение «%s» (%.1f м от точки)" % [pt.name, d])
		await shot("%02d_%s" % [i, id])
		i += 1
	# крупно: подписи читаются
	for e in [["92_flora_row", Vector3(-74, 0, -47), Vector3(-74, 0.8, -55)],
			["93_fauna_pens", Vector3(55, 0, -50), Vector3(55, 0.6, -63)],
			["94_items_table", Vector3(-12, 0, 12.5), Vector3(-12, 0.9, 16)],
			["95_build_house", Vector3(-90, 0, -4), Vector3(-92, 1.5, -15)]]:
		var at: Vector3 = e[1]
		at.y = SandboxProps.ground(at.x, at.z) + 0.2
		var lk: Vector3 = e[2]
		lk.y += SandboxProps.ground(lk.x, lk.z)
		sb.cheats.teleport(at, lk)
		await wait(1.5)
		await shot(e[0])
	# меню F1
	sb.panel.go(&"bots")
	await wait(1.0)
	await _key(KEY_F1)
	check(sb.panel.visible and p.ui_open, "F1 открывает меню полигона")
	await wait(0.5)
	await shot("90_panel")
	await _key(KEY_F1)
	check(not sb.panel.visible and not p.ui_open, "F1 закрывает меню")
	# бот и животное
	var nb := Bots.instance().bots.size() if Bots.instance() else 0
	sb.panel.call(&"_spawn_bot", true)
	await wait(0.5)
	check(Bots.instance() != null and Bots.instance().bots.size() == nb + 1, "бот создан на арене")
	var na := fa.animals.size() if fa else 0
	sb.panel.call(&"_spawn_animal")
	await wait(0.3)
	check(fa != null and fa.animals.size() == na + 1, "животное создано у прицела")
	# клик по карте — перемещение
	sb.panel.open_panel()
	await wait_frames(3)
	var target := Vector2(-60.0, 74.0)
	sb.panel.call(&"_on_map_click", target)
	await wait(0.5)
	check(Vector2(p.global_position.x, p.global_position.z).distance_to(target) < 2.0 and not sb.panel.visible,
			"клик по карте переносит игрока")
	# полёт: сквозь стену дома вверх и вперёд
	sb.panel.go(&"build")
	await wait(1.0)
	await _key(KEY_V)
	check(sb.cheats.fly, "V включает полёт")
	var y0 := p.global_position.y
	Input.action_press(&"jump")
	await wait(1.0)
	Input.action_release(&"jump")
	check(p.global_position.y > y0 + 5.0, "полёт вверх (%.1f → %.1f)" % [y0, p.global_position.y])
	var x0 := p.global_position
	p.set_look(PI * 0.5, -0.2) # на запад — сквозь постройки
	Input.action_press(&"sprint")
	Input.action_press(&"move_forward")
	await wait(1.2)
	Input.action_release(&"move_forward")
	Input.action_release(&"sprint")
	check(p.global_position.distance_to(x0) > 20.0, "полёт с ускорением (%.1f м)" % p.global_position.distance_to(x0))
	await shot("91_fly")
	await _key(KEY_V)
	check(not sb.cheats.fly, "V выключает полёт")
	# бессмертие
	p.apply_damage(60.0, null, &"melee")
	await wait(0.3)
	check(p.alive and p.health > 99.0, "бессмертие восстанавливает здоровье")
	# урон по чучелу показывает число
	var dm := get_tree().get_nodes_in_group(&"dummies")[0] as TrainingDummy
	dm.apply_damage(25.0, p, &"melee")
	await wait(0.3)
	check(dm.total >= 25.0, "чучело получает урон")

func _key(k: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = k
	ev.keycode = k
	ev.pressed = true
	Input.parse_input_event(ev)
	await wait_frames(2)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	await wait_frames(2)
