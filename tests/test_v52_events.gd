extends TestCase
## v5.2 (агент M): события сезона. Мир v5, матч с 1 ботом. Каждое событие запускается через
## SeasonEvents (и консоль), ускоренно (SeasonEvents.time_scale) проверяются: миграция (манты в
## открытом море, вожак идёт по маршруту), красные крабы (сотни на суше, идут к морю, ловятся,
## замедляют), цунами (вода отступает → волна → накрывает низкий берег → вода возвращается),
## награда за лидера (очки убийце), отравленный родник (яд, тест-полоска, боты обходят),
## дрейфующий ящик (на воде, плывёт по течению, боты гонятся), задания зрителей, штиль (зной).
## test-timeout: 1500

func _init() -> void:
	OS.set_environment("OSTROVA_GEN", "5")
	scene_path = "res://scenes/world/match.tscn"
	timeout_sec = 1480.0
	Game.pending_config = {"bots_enemy": 1, "bots_ally": 0, "minutes": 0}

func _match_ready() -> bool:
	for i in 900:
		if scene and scene.is_inside_tree() and not (scene.get(&"loaded_modules") as Array).is_empty() and Game.is_playing():
			return true
		await wait(0.5)
	return false

func run() -> void:
	check(await _match_ready(), "матч загрузился")
	get_viewport().disable_3d = true
	var w := get_tree().get_first_node_in_group(&"world") as World
	var se := SeasonEvents.instance()
	check(se != null, "директор событий есть в матче (Supply)")
	if se == null or w == null:
		return
	se.auto = false
	var pl := scene.get(&"player") as Node3D
	check(pl != null, "игрок есть")
	print("[test] консоль: %s" % DevConsole.execute("event list"))
	await _migration(se, w)
	await _red_crabs(se, w, pl)
	await _poison(se, w, pl)
	await _drift(se, w)
	await _bounty(se, pl)
	await _tasks(se, pl)
	await _calm(se, pl)
	await _tsunami(se, w, pl)
	SeasonEvents.time_scale = 1.0

func _migration(se: SeasonEvents, w: World) -> void:
	var e := se.start(&"migration", {"seed": 7})
	check(e != null, "миграция запустилась")
	if e == null:
		return
	var route: Array = e.get(&"route")
	var bad := 0
	for p: Vector3 in route:
		if not w.sea_ok(p.x, p.z, 6.0):
			bad += 1
	check(route.size() > 20 and bad == 0, "маршрут миграции — открытое море (%d точек, вне моря %d)" % [route.size(), bad])
	var crit: Array = e.get(&"_crit")
	check(crit.size() >= 5, "манты в строю: %d" % crit.size())
	var p0: Vector3 = e.call(&"pod_pos")
	SeasonEvents.time_scale = 10.0
	await wait(3.0)
	SeasonEvents.time_scale = 1.0
	var p1: Vector3 = e.call(&"pod_pos")
	check(p0.distance_to(p1) > 10.0, "вожак миграции идёт по маршруту (%.0f м)" % p0.distance_to(p1))
	var wet := 0
	for c in crit:
		if is_instance_valid(c) and (c as Node3D).global_position.y < w.water_level():
			wet += 1
	check(wet >= crit.size() - 1, "манты под водой (%d/%d)" % [wet, crit.size()])
	se.stop(&"migration")
	await wait(0.3)
	var alive_c := crit.filter(func(c: Variant) -> bool: return is_instance_valid(c))
	check(alive_c.is_empty(), "после миграции манты убраны")

func _red_crabs(se: SeasonEvents, w: World, pl: Node3D) -> void:
	var e := se.start(&"red_crabs", {"seed": 3})
	check(e != null, "нашествие крабов запустилось")
	if e == null:
		return
	var n0 := int(e.call(&"alive_count"))
	check(n0 >= 300, "крабов на острове: %d" % n0)
	var crabs: Array = e.get(&"crabs")
	var on_land := 0
	for c: Dictionary in crabs:
		if c.alive and w.height_at((c.p as Vector2).x, (c.p as Vector2).y) > w.water_level() - 0.05:
			on_land += 1
	check(on_land >= n0 * 0.95, "крабы на суше: %d/%d" % [on_land, n0])
	var area := e.get(&"_area") as Area3D
	check(area != null and area.is_in_group(&"soft_plant") and float(area.get_meta(&"speed_mul", 1.0)) < 0.8, "поток крабов замедляет (soft_plant)")
	var first: Vector2 = (crabs[0] as Dictionary).p
	SeasonEvents.time_scale = 8.0
	await wait(3.0)
	SeasonEvents.time_scale = 1.0
	check(int(e.get(&"reached")) > 0 or ((crabs[0] as Dictionary).p as Vector2).distance_to(first) > 2.0, "крабы идут к морю (дошли: %d)" % int(e.get(&"reached")))
	# поймать у ног
	var alive_c := {}
	for c: Dictionary in crabs:
		if c.alive:
			alive_c = c
			break
	var cp: Vector2 = alive_c.p
	var before := BuildEnv.inv_count(pl, &"crab_meat")
	var got := int(e.call(&"catch_at", pl, Vector3(cp.x, 0, cp.y), 3))
	check(got >= 1 and BuildEnv.inv_count(pl, &"crab_meat") == before + got, "пойманы красные крабы: %d → в инвентаре" % got)
	se.stop(&"red_crabs")

func _poison(se: SeasonEvents, w: World, pl: Node3D) -> void:
	var e := se.start(&"poison_spring", {"seed": 5, "exact": false})
	check(e != null, "отравленный родник запустился")
	if e == null:
		return
	var spot: Vector3 = e.get(&"spot")
	check(SeasonEvents.is_poisoned(spot), "источник отравлен")
	check(BuildEnv.inv_count(pl, &"water_test_kit") >= 1, "у игрока тест-полоска")
	var sv := Survival.instance()
	if sv:
		check(not sv.is_fresh_at(spot), "отравленная вода не считается пресной")
	var bot := get_tree().get_first_node_in_group(&"bots") as Node3D
	if bot:
		var far := not bool(e.call(&"bot_knows", spot, bot)) or bot.global_position.distance_to(spot) < 40.0
		check(far, "бот без признаков и предупреждения не «знает» (честно)")
		var old := bot.global_position
		bot.global_position = spot + Vector3(5, 0, 0)
		check(SeasonEvents.bot_avoids_water(spot, bot), "бот у источника видит дохлую рыбу и обходит")
		bot.global_position = old
	Survival.set_poison(pl, 0.0, 0.0)
	e.call(&"poison", pl)
	check(Survival.get_poison(pl).x > 0.0, "выпил — отравление")
	Survival.set_poison(pl, 0.0, 0.0)
	se.stop(&"poison_spring")
	check(not SeasonEvents.is_poisoned(spot), "после события вода чистая")

func _drift(se: SeasonEvents, w: World) -> void:
	var e := se.start(&"drift_crate", {"seed": 11})
	check(e != null, "дрейфующий ящик запустился")
	if e == null:
		return
	var c := e.get(&"crate") as SupplyCrate
	check(c != null and c.has_meta(&"drift"), "ящик на лодке с течением")
	await wait(2.5)
	check(c.state == SupplyCrate.State.FLOATING, "ящик плавает")
	var p0 := c.global_position
	await wait(6.0)
	var moved := Vector2(c.global_position.x - p0.x, c.global_position.z - p0.z).length()
	check(moved > 1.0, "ящик дрейфует (%.1f м за 6 с)" % moved)
	var bb := get_tree().get_first_node_in_group(&"bots")
	if bb and bb.get(&"brain"):
		var job: Dictionary = (bb.get(&"brain") as Object).call(&"_supply_job")
		print("[test] бот и ящик: %s (до ящика %.0f м)" % [str(job.get("type", "—")), (bb as Node3D).global_position.distance_to(c.global_position)])
	se.stop(&"drift_crate")
	await wait(0.2)
	check(not is_instance_valid(c), "невскрытый ящик уходит после события")

func _bounty(se: SeasonEvents, pl: Node3D) -> void:
	var bot := get_tree().get_first_node_in_group(&"bots") as Node3D
	if bot == null:
		check(false, "нет бота для награды")
		return
	var e := se.start(&"bounty", {"target": bot})
	check(e != null and SeasonEvents.bounty_target() == bot, "награда за голову назначена")
	var before := ShowBus.points_of(pl)
	bot.call(&"apply_damage", 9999.0, pl, &"gun")
	await wait(0.5)
	var gain := ShowBus.points_of(pl) - before
	check(gain >= 79.0, "убийца лидера получил очки: +%.0f" % gain)
	check(not se.is_active(&"bounty"), "награда закрыта после убийства")

func _tasks(se: SeasonEvents, pl: Node3D) -> void:
	var e := se.start(&"viewer_task", {"task_id": "crabs_5"})
	check(e != null, "задание зрителей выдано")
	if e == null:
		return
	var before := ShowBus.points_of(pl)
	se.game_fact.emit(&"crab_caught", pl, {"n": 3})
	check(se.is_active(&"viewer_task"), "3 краба из 5 — задание ещё идёт")
	se.game_fact.emit(&"crab_caught", pl, {"n": 2})
	await wait(0.2)
	check(not se.is_active(&"viewer_task"), "5 крабов — задание выполнено")
	check(ShowBus.points_of(pl) - before >= 44.0, "награда за задание: +%.0f" % (ShowBus.points_of(pl) - before))

func _calm(se: SeasonEvents, pl: Node3D) -> void:
	var w := get_tree().get_first_node_in_group(&"world") as World
	w.set_time_of_day(13.0)
	var e := se.start(&"calm")
	check(e != null and w.weather() == &"calm", "штиль: погода calm")
	SeasonEvents.time_scale = 30.0
	await wait(4.0)
	SeasonEvents.time_scale = 1.0
	check(SeasonEvents.heat() > 0.1, "зной штиля: %.2f" % SeasonEvents.heat())
	se.stop(&"calm")
	check(SeasonEvents.heat() == 0.0, "после штиля зноя нет")

func _tsunami(se: SeasonEvents, w: World, pl: Node3D) -> void:
	# игрок на низком берегу у воды
	var spot := Vector3.INF
	for I: Dictionary in w.islands():
		var c: Vector2 = I.center
		for k in 24:
			var a := TAU * k / 24.0
			for r in range(int(float(I.radius) * 0.5), int(float(I.radius) * 1.4), 4):
				var q := c + Vector2(cos(a), sin(a)) * float(r)
				var h := w.height_at(q.x, q.y)
				if h > w.water_level() + 0.3 and h < w.water_level() + 1.2:
					spot = Vector3(q.x, h + 0.1, q.y)
					break
			if spot != Vector3.INF:
				break
		if spot != Vector3.INF:
			break
	check(spot != Vector3.INF, "низкий пляж для проверки волны")
	pl.set_physics_process(false)
	pl.global_position = spot
	var hp0 := float(pl.get(&"health"))
	var e := se.start(&"tsunami", {"dir_deg": 0.0, "withdraw_s": 6.0, "surge_hold_s": 4.0, "recede_s": 8.0, "front_speed": 400.0})
	check(e != null, "цунами запустилось")
	if e == null:
		return
	await wait(3.0)
	check(w.event_sea_offset < -0.8 and String(SeasonEvents.tsunami_info().phase) == "withdraw", "море отступает (%.2f м)" % w.event_sea_offset)
	var saw_wall := false
	var t := 0.0
	while t < 20.0 and String(SeasonEvents.tsunami_info().get("phase", "")) in ["withdraw", "wave"]:
		if e.get(&"_wall") != null:
			saw_wall = true
		await wait(0.2)
		t += 0.2
	check(saw_wall, "стена волны появилась")
	check(w.event_sea_offset > 2.0, "вода поднялась (%.2f м)" % w.event_sea_offset)
	var hp1 := float(pl.get(&"health"))
	check(hp1 < hp0 or not pl.get(&"alive"), "волна накрыла игрока на пляже (здоровье %.0f → %.0f)" % [hp0, hp1])
	var moved := Vector2(pl.global_position.x - spot.x, pl.global_position.z - spot.z).length()
	check(moved > 2.0, "игрока протащило волной (%.1f м)" % moved)
	t = 0.0
	while se.is_active(&"tsunami") and t < 30.0:
		await wait(0.5)
		t += 0.5
	check(absf(w.event_sea_offset) < 0.01, "вода вернулась (%.2f)" % w.event_sea_offset)
