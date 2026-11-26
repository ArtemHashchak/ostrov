extends TestCase
## Мир v5: острова в 250–700 м воды. Бот собирает лодку на берегу своего острова,
## плывёт по морской переправе (BotNav.sea_routes) и выходит на соседний остров.
## Лодка остаётся у чужого берега; в сильный шторм переправа не начинается.
## test-timeout: 1500

var bots: Bots
var cam: Camera3D

func _init() -> void:
	OS.set_environment("OSTROVA_GEN", "5")
	scene_path = "res://scenes/world/match.tscn"
	timeout_sec = 1480.0
	Game.pending_config = {"bots_enemy": 0, "bots_ally": 0, "minutes": 0}

func _match_ready() -> bool:
	for i in 900:
		if scene and scene.is_inside_tree() and not (scene.get(&"loaded_modules") as Array).is_empty() and Game.is_playing():
			return true
		await wait(0.5)
	return false

func run() -> void:
	check(await _match_ready(), "матч загрузился")
	get_viewport().disable_3d = true
	bots = Bots.instance()
	if bots == null:
		check(false, "нет модуля ботов")
		return
	var player := scene.get(&"player") as Node3D
	if player:
		player.set_physics_process(false)
	await wait(1.0)
	var nav := bots.ensure_nav()
	check(nav.boats_ok, "навигация знает о лодках (мир v5)")
	check(nav.sea_routes.size() >= 6, "морские переправы найдены (%d)" % nav.sea_routes.size())
	var ta := bots.team_ai(1)
	ta.ensure_flag()
	var hid := ta.home_id()
	check(hid >= 0, "домашний остров команды 1")
	var best: Dictionary = {}
	for k in nav.sea_routes:
		var R: Dictionary = nav.sea_routes[k]
		if (int(R.a) == hid or int(R.b) == hid) and (best.is_empty() or float(R.gap) < float(best.gap)):
			best = R
	check(not best.is_empty(), "у дома есть морская переправа")
	if best.is_empty():
		return
	var rev := int(best.a) != hid
	var other := int(best.a) if rev else int(best.b)
	print("[boat] дом %d → %d, вода %.0f м" % [hid, other, float(best.gap)])
	check(float(best.gap) >= 150.0 and float(best.gap) <= 820.0, "длина переправы в пределах лодки")
	check(nav.reachable(hid, other, 0.0), "граф: остров %d достижим лодкой" % other)
	# шторм: переправа не планируется
	var w := scene.get(&"world") as Node
	var sky: Node = w.get(&"sky") if w else null
	if sky and sky.has_method(&"set_weather"):
		sky.call(&"set_weather", &"storm", true, false)
		await wait(0.5)
		check(not BotBoat.storm_ok(w), "в сильный шторм лодкой не плаваем (шторм %.2f)" % float(w.call(&"storm_intensity")))
		sky.call(&"set_weather", &"clear", true, false)
		await wait(0.5)
		check(BotBoat.storm_ok(w), "в ясную погоду можно плыть")
	var bot := bots.spawn_bot(1, &"easy")
	bot.brain.mode = &"build"
	var s1: Vector3 = best.sa if rev else best.sb
	var dir: Vector3 = -(best.dir as Vector3) if rev else best.dir
	var to_pt := nav.ground(s1 + dir * 10.0)
	bot.brain.order_goto(to_pt, 3.0)
	Engine.time_scale = 4.0
	var rode := false
	var t0 := Game.match_time
	while Game.match_time - t0 < 900.0:
		await wait(0.5)
		if bot.riding != null:
			if not rode:
				print("[boat] сел в лодку t=%.0f" % (Game.match_time - t0))
				_shot_cam(bot)
				get_viewport().disable_3d = false
				await wait_frames(3)
				await shot("rowing")
				get_viewport().disable_3d = true
			rode = true
		if String(bot.brain.task.get("type", "")) != "goto":
			bot.brain.order_goto(to_pt, 3.0)
		if nav.island_id(bot.global_position) == other and bot.riding == null:
			break
		if int(Game.match_time - t0) % 30 == 0:
			print("[boat] t=%d pos=%s остров=%d путь=%d лодок=%d" % [int(Game.match_time - t0), str(bot.global_position.snapped(Vector3.ONE)),
				nav.island_id(bot.global_position), bot.path.size(), get_tree().get_nodes_in_group(&"boat").size()])
	Engine.time_scale = 1.0
	check(rode, "бот плыл в лодке")
	check(nav.island_id(bot.global_position) == other, "бот вышел на соседний остров")
	check(bot.boat_trips >= 1, "переправа засчитана")
	check(get_tree().get_nodes_in_group(&"boat").size() >= 1, "лодка осталась у берега")

func _shot_cam(b: Node3D) -> void:
	if cam == null:
		cam = Camera3D.new()
		scene.add_child(cam)
	cam.current = true
	var p := b.global_position
	cam.global_position = p + Vector3(9.0, 4.0, 9.0)
	cam.look_at(p)
