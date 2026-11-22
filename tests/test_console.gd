## test-timeout: 900
extends TestCase
## Консоль разработчика (` / Ё) и CreatureSpawner: list берёт виды из реестров, spawn 100 крабов
## (партиями, счёт сходится), морские виды — настоящие особи в воде, kill/clear, лимиты,
## автодополнение, «Каталог существ» полигона. Пишет время кадра со 100 крабами.

var sb: Sandbox

func _init() -> void:
	scene_path = "res://scenes/sandbox/sandbox.tscn"
	timeout_sec = 900.0

func _frame_ms(n: int) -> float:
	var t := Time.get_ticks_usec()
	for i in n:
		await get_tree().process_frame
		await get_tree().physics_frame
	return float(Time.get_ticks_usec() - t) / 1000.0 / float(n)

func run() -> void:
	Engine.max_physics_steps_per_frame = 30
	sb = scene as Sandbox
	var t0 := Time.get_ticks_msec()
	while not sb.is_built and Time.get_ticks_msec() - t0 < 600000:
		await wait(0.5)
	check(sb.is_built, "полигон собран")
	if not sb.is_built:
		return
	var con: Node = get_tree().root.get_node_or_null(^"DevConsole")
	check(con != null, "автозагрузка DevConsole есть")
	if con == null:
		return
	check(con.call(&"enabled"), "консоль доступна на полигоне без режима разработчика")

	# ---- список видов — из реестров
	var all := CreatureSpawner.all_species()
	var cats := {}
	for d in all:
		cats[d.cat] = int(cats.get(d.cat, 0)) + 1
	print("[test] видов: %d  %s" % [all.size(), cats])
	for sp: StringName in Animal.SPECIES:
		check(not CreatureSpawner.find(String(sp)).is_empty(), "в списке вид фауны %s" % sp)
	check(int(cats.get("sea", 0)) >= OceanRoster.all_species().size() / 2, "морских видов ≥ половины состава океана (%d)" % int(cats.get("sea", 0)))
	check(int(cats.get("plants", 0)) >= Flora.VARIANTS.size() + 3, "растения есть (%d)" % int(cats.get("plants", 0)))
	check(int(cats.get("birds", 0)) >= 2, "птицы есть")
	check(CreatureSpawner.find("краб").get("id", "") == "crab", "поиск по-русски: «краб» → crab")
	var lst := String(con.call(&"execute", "list sea"))
	check(lst.contains("Море") and not lst.begins_with("!"), "list sea отвечает")
	check(String(con.call(&"execute", "список")).contains("Всего видов: %d" % all.size()), "список (RU) — все виды")
	check(String(con.call(&"execute", "абракадабра")).begins_with("!"), "неизвестная команда — ошибка")
	var comp: PackedStringArray = con.call(&"completions", "spawn cr")
	check(comp.has("crab") or comp.has("croc"), "Tab: spawn cr → %s" % ", ".join(comp))
	check((con.call(&"completions", "spa") as PackedStringArray).has("spawn"), "Tab дополняет команду")

	# ---- 100 крабов у прицела
	var p := sb.player
	var beach: Vector3 = sb.zones.points[&"beach"].pos if sb.zones.points.has(&"beach") else p.global_position
	sb.cheats.teleport(beach)
	await wait(1.0)
	var base_ms: float = await _frame_ms(60)
	var res := String(con.call(&"execute", "spawn краб 100"))
	check(res.contains("×100"), "spawn краб 100 → «%s»" % res)
	var cs := CreatureSpawner.instance()
	var t1 := Time.get_ticks_msec()
	while cs.queued() > 0 and Time.get_ticks_msec() - t1 < 240000:
		await get_tree().process_frame
	check(cs.queued() == 0, "очередь разобрана партиями за %d мс" % (Time.get_ticks_msec() - t1))
	check(cs.live_count("crab") == 100, "живых крабов от консоли: %d (ждём 100)" % cs.live_count("crab"))
	var on_ground := 0
	for e in cs.spawned:
		var a := e.node as Animal
		if a and absf(a.global_position.y - Fauna.ground_y_at(a, a.global_position.x, a.global_position.z)) < 1.5:
			on_ground += 1
	check(on_ground >= 95, "крабы на земле: %d/100" % on_ground)
	await wait(1.0)
	var crab_ms: float = await _frame_ms(120)
	print("[test] PERF 100 крабов: кадр %.2f мс (без них %.2f мс, +%.2f)" % [crab_ms, base_ms, crab_ms - base_ms])
	check(String(con.call(&"execute", "count")).contains("Краб") or String(con.call(&"execute", "count")).contains("краб"), "count показывает крабов")
	await shot("crabs100")

	# ---- лимит за команду
	var got := cs.request("crab", beach, 5000)
	check(got == CreatureSpawner.MAX_PER_CMD, "лимит за команду: %d" % got)
	cs._queue.clear()

	# ---- kill / clear
	var killed := String(con.call(&"execute", "kill краб 0"))
	check(cs.live_count("crab") == 0, "kill краб: живых крабов 0 (%s)" % killed)
	var cl := String(con.call(&"execute", "clear"))
	await wait_frames(2)
	check(cs.spawned.is_empty(), "clear убрал всё созданное (%s)" % cl)

	# ---- море: настоящие особи в воде
	var sea_ids: Array[String] = []
	for d in CreatureSpawner.all_species("sea"):
		if d.src in ["roster", "pack"] and sea_ids.size() < 6:
			sea_ids.append(String(d.id))
	var pier: Vector3 = sb.zones.points[&"pier"].pos if sb.zones.points.has(&"pier") else beach
	var wy := cs._water()
	var made := 0
	var in_water := 0
	for id in sea_ids:
		made += maxi(cs.spawn_now(id, pier + Vector3(0, 0, 12), 3, 6.0), 0)
	for e in cs.spawned:
		var n := e.node as Node3D
		if n and n.global_position.y < wy + 0.05:
			in_water += 1
	print("[test] море: %s → создано %d, в воде %d" % [sea_ids, made, in_water])
	check(made >= 6, "морские существа созданы (%d)" % made)
	check(in_water >= made * 0.8, "морские — в воде (%d/%d)" % [in_water, made])
	await wait(1.0)
	var moved := 0
	for e in cs.spawned:
		if e.node is SeaCritter:
			moved += 1
	print("[test] SeaCritter в «сцене» консоли: %d" % moved)

	# ---- акула и растения
	check(cs.spawn_now("shark_reef", pier + Vector3(0, 0, 20), 1) == 1, "акула призвана")
	check(cs.spawn_now("palm", beach + Vector3(6, 0, 0), 2) == 2, "пальмы посажены")
	check(cs.spawn_now("boulder", beach + Vector3(-6, 0, 0), 1) == 1, "валун")
	var res_id := String(ResourceNode.INFO.keys()[0])
	check(cs.spawn_now(res_id, beach + Vector3(0, 0, 6), 3) == 3, "ресурс %s" % res_id)
	check(cs.spawn_now("parrot", beach, 5) == 5, "птицы стаей")
	var ckey := cs.clear(Vector3.ZERO, 0.0)
	check(ckey > 0 and cs.spawned.is_empty(), "clear всего: %d" % ckey)

	# ---- spawn_all по категориям
	con.call(&"execute", "spawn_all animals")
	t1 = Time.get_ticks_msec()
	while cs.queued() > 0 and Time.get_ticks_msec() - t1 < 240000:
		await get_tree().process_frame
	check(cs.live_count() >= CreatureSpawner.all_species("animals").size() - 1, "spawn_all animals: %d" % cs.live_count())

	# ---- tame, time, weather, god, give
	var tm := String(con.call(&"execute", "tame кабан"))
	print("[test] ", tm)
	check(not String(con.call(&"execute", "time 21")).begins_with("!"), "time 21")
	check(absf(sb.world.time_of_day() - 21.0) < 0.6, "время стало ~21 (%.2f)" % sb.world.time_of_day())
	check(not String(con.call(&"execute", "погода дождь")).begins_with("!"), "погода дождь")
	var g0 := sb.cheats.god
	con.call(&"execute", "god")
	check(sb.cheats.god != g0, "god переключает бессмертие")
	con.call(&"execute", "god")
	var gv := String(con.call(&"execute", "give " + String(Items.items.keys()[0]) + " 3"))
	check(gv.begins_with("Выдано"), "give: %s" % gv)
	check(String(con.call(&"execute", "tp 0 0")).begins_with("Телепорт"), "tp x z")
	con.call(&"execute", "time 13")
	con.call(&"execute", "weather ясно")

	# ---- каталог в меню F1
	sb.cheats.teleport(beach)
	await wait(0.5)
	sb.panel.open_panel()
	sb.panel.open_catalog()
	await wait_frames(3)
	var cat: SandboxCatalog = sb.panel.catalog
	var btns := 0
	for g in cat.find_children("*", "Button", true, false):
		btns += 1
	check(btns >= all.size(), "в каталоге кнопок ≥ видов (%d ≥ %d)" % [btns, all.size()])
	await shot("catalog")
	cat._count = 10
	check(cat.spawn("iguana") == 10, "каталог: ×10 игуан")
	sb.panel.close_panel()
	cs.clear(Vector3.ZERO, 0.0)
	await wait_frames(2)

	# ---- консоль открыта (кадр для скриншота)
	con.call(&"open")
	con.call(&"execute", "spawn краб 40")
	con.call(&"execute", "list birds")
	con.call(&"execute", "count")
	await wait(1.0)
	check(con.call(&"is_open"), "консоль открывается")
	await shot("console")
	con.call(&"close")
	cs.clear(Vector3.ZERO, 0.0)
