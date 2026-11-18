extends TestCase
## Мост ботов: план моста команды (BotTeam) к соседнему острову достраивается мгновенно,
## навигация видит его как ребро графа, бот (лёгкий — не плавает) переходит по связкам
## брёвен на соседний остров, не заходя в воду.

var bots: Bots
var cam: Camera3D

func _init() -> void:
	scene_path = "res://scenes/world/match.tscn"
	timeout_sec = 1480.0
	Game.pending_config = {"bots_enemy": 0, "bots_ally": 0, "minutes": 0}

func _match_ready() -> bool:
	for i in 900:
		if scene and scene.is_inside_tree() and not (scene.get(&"loaded_modules") as Array).is_empty() and Game.is_playing():
			return true
		await wait(0.5)
	return false

func _fill(bp: Blueprint) -> void:
	for t: StringName in [&"log", &"stick", &"rope", &"stone"]:
		bp.add_material(t, 99)

func run() -> void:
	check(await _match_ready(), "матч загрузился")
	bots = Bots.instance()
	if bots == null:
		check(false, "нет модуля ботов")
		return
	var player := scene.get(&"player") as Node3D
	if player:
		player.set_physics_process(false)
	await wait(1.0)
	var nav := bots.ensure_nav()
	check(nav.pairs.size() >= 10, "соседние острова найдены (%d пар)" % nav.pairs.size())
	var ta := bots.team_ai(1)
	ta.ensure_flag()
	var hid := ta.home_id()
	check(hid >= 0, "домашний остров команды 1")
	# ближайший сосед по длине воды
	var best: Dictionary = {}
	for k in nav.pairs:
		var P: Dictionary = nav.pairs[k]
		if (int(P.a) == hid or int(P.b) == hid) and (best.is_empty() or float(P.water_len) < float(best.water_len)):
			best = P
	check(not best.is_empty(), "у дома есть сосед")
	if best.is_empty():
		return
	var other := int(best.b) if int(best.a) == hid else int(best.a)
	print("[bots] сосед %d, вода %.1f м, пролив %.1f м" % [other, float(best.water_len), float(best.gap)])
	var rev := int(best.a) != hid
	ta.base_done = true
	ta.bridge = {"key": BotNav._key(hid, other), "a": hid, "b": other,
		"from": best.sb if rev else best.sa, "to": best.sa if rev else best.sb,
		"dir": -(best.dir as Vector3) if rev else best.dir, "root": null, "tip": null, "sections": 0, "done": false}
	var n := 0
	for i in 80:
		var bp := ta._next_section()
		if bp == null:
			break
		_fill(bp)
		n += 1
		await wait_frames(2)
	print("[bots] секций моста: ", n, " готов=", ta.bridge.get("done", false))
	check(n >= 2 and bool(ta.bridge.get("done", false)), "мост к соседу построен (%d секций)" % n)
	nav.refresh_links(get_tree())
	check(nav.reachable(hid, other, 0.0), "навигация видит мост (ребро %d→%d)" % [hid, other])
	# бот идёт на соседний остров
	var bot := bots.spawn_bot(1, &"easy")
	bot.brain.mode = &"build"
	var to_pt: Vector3 = (best.sa if rev else best.sb)
	var dir: Vector3 = ta.bridge.dir
	to_pt = nav.ground(to_pt + dir * 12.0)
	bot.brain.order_goto(to_pt, 2.0)
	cam = Camera3D.new()
	scene.add_child(cam)
	cam.current = true
	var on_deck := false
	var swam := false
	var shot_done := false
	var t0 := Game.match_time
	while Game.match_time - t0 < 600.0:
		await wait(0.5)
		if bot.swimming:
			swam = true
		if nav.deck_at(bot.global_position) != null:
			on_deck = true
			if not shot_done:
				shot_done = true
				_look(bot)
				await shot("on_bridge")
		if bot.brain.task.get("type", "") != "goto" and String(bot.brain.task.get("type", "")) != "":
			bot.brain.order_goto(to_pt, 2.0)
		if nav.island_id(bot.global_position) == other and bot.global_position.distance_to(to_pt) < 4.0:
			break
		if int(Game.match_time - t0) % 20 == 0:
			print("[bots] t=%d pos=%s island=%d task=%s path=%d stuck=%d" % [int(Game.match_time - t0), str(bot.global_position.snapped(Vector3.ONE * 0.1)),
				nav.island_id(bot.global_position), bot.brain.status, bot.path.size(), bot.stuck])
	check(on_deck, "бот шёл по секциям моста")
	check(not swam, "бот не плыл")
	check(nav.island_id(bot.global_position) == other, "бот на соседнем острове")
	_look(bot)
	await shot("arrived")

func _look(b: Node3D) -> void:
	var p := b.global_position
	cam.global_position = p + b.global_basis.z * 6.0 + Vector3(1.5, 3.0, 0.0)
	cam.look_at(p + Vector3.UP)
