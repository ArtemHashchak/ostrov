extends TestCase
## Полный матч в match.tscn: конфиг лобби, флаги всех команд на старте,
## матчевый HUD (флаги, компас, таймер, мини-карта, большая карта),
## возрождение у флага, флаг уничтожен → нет возрождения → выбывание →
## конец матча с победителем и экраном итога.

var _ended := -99
var _elim: Array[int] = []

func _init() -> void:
	scene_path = "res://scenes/world/match.tscn"
	timeout_sec = 3500.0 # под нагрузкой (2 ядра, другие агенты) — TEST_TIMEOUT=3600
	Game.pending_config = {"mode": "ffa", "minutes": 60, "bots_enemy": 0, "bots_ally": 0, "auto_flags": true}

func _enemy(team: int, nm: String, pos: Vector3) -> Node3D:
	var s := GDScript.new()
	s.source_code = "extends Node3D\nvar team := %d\nvar alive := true\nvar display_name := \"%s\"\nfunc is_dead() -> bool:\n\treturn not alive\n" % [team, nm]
	s.reload()
	var n := Node3D.new()
	n.set_script(s)
	n.add_to_group(&"characters")
	scene.add_child(n)
	n.global_position = pos
	Game.register_character(n, team)
	return n

func run() -> void:
	Events.match_ended.connect(func(w: int) -> void: _ended = w)
	Events.team_eliminated.connect(func(t: int) -> void: _elim.append(t))
	# Под нагрузкой кадры редкие — пусть игровое время не отстаёт.
	Engine.max_physics_steps_per_frame = 30
	var t0 := Time.get_ticks_msec()
	while Game.state != Game.State.PLAYING or get_tree().get_first_node_in_group(&"player") == null:
		await wait(0.5)
		if Time.get_ticks_msec() - t0 > 900000:
			break
	await wait(1.0)
	var p := get_tree().get_first_node_in_group(&"player") as Node3D
	check(p != null, "игрок в матче")
	check(Game.is_playing() and Game.teams.size() == 4 and is_equal_approx(Game.match_length, 3600.0), "матч идёт: 4 команды, 60 мин из лобби")
	var ui := MatchUI.instance()
	check(ui != null and ui.hud != null, "модуль UI подключён")
	var bm := BuildModule.instance()
	var placed := 0
	for t in 4:
		if Game.teams[t].flag_placed and bm and bm.flag_of(t) != null:
			placed += 1
	check(placed == 4, "флаги всех 4 команд стоят (%d)" % placed)
	var inv := p.get(&"inventory") as Inventory
	check(inv != null and inv.count(&"flag") == 0, "предмет «флаг» забран у игрока")
	var fp: Vector3 = Game.teams[0].flag_pos
	check(p.global_position.distance_to(fp) < 30.0, "флаг рядом со стартом (%.1f м)" % p.global_position.distance_to(fp))
	# Смотрим на свой флаг.
	p.call(&"set_look", atan2(-(fp.x - p.global_position.x), -(fp.z - p.global_position.z)), -0.15)
	var t1 := Time.get_ticks_msec()
	while not ui.hud.minimap.is_baked() and Time.get_ticks_msec() - t1 < 60000:
		await wait(0.5)
	check(ui.hud.minimap.is_baked(), "мини-карта снята с рельефа")
	ui.hud.announce("Ваш флаг атакуют!", UITheme.DANGER)
	var e1 := _enemy(1, "Бот Синих", p.global_position + Vector3(3, 0, 3))
	Events.character_died.emit(e1, p) # строка ленты убийств (Бот Синих тут же «воскресает»)
	await wait(0.5)
	await shot("01_hud")
	ui.hud.toggle_big_map()
	await wait(0.3)
	await shot("02_big_map")
	ui.hud.toggle_big_map()
	check(not ui.hud.is_big_map_open(), "большая карта закрывается")
	# Возрождение у флага, пока флаг цел.
	p.call(&"apply_damage", 9999.0, null, &"fall")
	await wait(1.5)
	check(p.call(&"is_dead"), "игрок погиб")
	await shot("03_respawn_countdown")
	check(float(p.get(&"respawn_left")) > Game.RESPAWN_TIME - 5.0, "отсчёт возрождения ~%d с" % int(Game.RESPAWN_TIME))
	p.set(&"respawn_left", 0.3) # не ждём все 10 с под llvmpipe
	await wait(1.5)
	check(not p.call(&"is_dead"), "возродился у флага через %d с" % int(Game.RESPAWN_TIME))
	check(p.global_position.distance_to(fp) < 6.0, "возрождение у флага")
	# Флаги соперников 1 и 2 сломаны; у 1 есть «бот» — пока он жив, команда в игре.
	Game.damage_flag(1, 9999.0, p)
	Game.damage_flag(2, 9999.0, p)
	await wait(0.8)
	check(_elim.has(2) and not _elim.has(1), "Зелёные (без людей) выбыли, Синие — нет, пока жив бот")
	e1.set(&"alive", false)
	Events.character_died.emit(e1, p)
	await wait(0.6)
	check(_elim.has(1), "Синие выбыли: флаг уничтожен и погиб последний")
	await shot("04_flags_destroyed")
	# Свой флаг уничтожен → гибель без возрождения → выбывание → Жёлтые побеждают.
	var e3 := _enemy(3, "Бот Жёлтых", fp + Vector3(2, 0, 0))
	if bm and bm.flag_of(0):
		bm.flag_of(0).apply_damage(9999.0, e3, &"axe")
	check(not Game.teams[0].flag_alive, "свой флаг уничтожен")
	p.call(&"apply_damage", 9999.0, e3, &"melee")
	await wait(1.5)
	check(p.call(&"is_dead") and bool(p.get(&"eliminated")), "без флага — нет возрождения")
	check(_elim.has(0), "своя команда выбыла")
	check(_ended == 3, "матч окончен, победили Жёлтые (есть %d)" % _ended)
	await wait(2.6)
	check(ui.end_screen.visible and ui.end_screen.final, "экран итога")
	check(int(Game.stats[p.get_instance_id()].flags) == 2 and int(Game.stats[p.get_instance_id()].deaths) == 2, "статистика игрока: 2 флага, 2 смерти")
	await shot("05_end_screen")
	get_tree().paused = false
	# наблюдение: камера облетает живого бота
	ui.end_screen.visible = false
	var sc := SpectatorCam.start(get_tree(), 0)
	await wait(1.0)
	check(sc != null and sc.current and sc.global_position.distance_to(e3.global_position) < 30.0,
		"камера наблюдения следит за живым персонажем")
	await shot("06_spectate")
	sc.queue_free()
	Game.end_session()
