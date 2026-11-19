extends TestCase
## «Полигон» v2: компактная раскладка (все зоны рядом с центром), бесконечные предметы
## (на столах и в инвентаре), смена погоды/времени/ветра (кнопки и F5/F6), убитые
## животные и акулы появляются снова, «вернуть всех».

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
	var w := sb.world
	# ---- раскладка: зоны рядом с центром
	var hub: Vector3 = z.points[&"hub"].pos
	for id: StringName in [&"flora", &"fauna", &"items", &"range", &"build", &"survival", &"bots", &"pack"]:
		if not z.points.has(id):
			check(false, "есть точка %s" % id)
			continue
		var d := Vector2(hub.x, hub.z).distance_to(Vector2((z.points[id].pos as Vector3).x, (z.points[id].pos as Vector3).z))
		check(d <= 60.0, "зона «%s» в %.0f м от центра (≤ 60)" % [z.points[id].name, d])
	for id: StringName in [&"sea", &"beach"]:
		if z.points.has(id):
			var d := Vector2(hub.x, hub.z).distance_to(Vector2((z.points[id].pos as Vector3).x, (z.points[id].pos as Vector3).z))
			check(d <= 85.0, "берег: «%s» в %.0f м от центра (≤ 85)" % [z.points[id].name, d])
	var fa := Fauna.instance()
	var species := {}
	for a in fa.animals:
		if is_instance_valid(a):
			species[a.species] = true
	check(species.size() >= 13, "все виды животных на месте (%d)" % species.size())
	# ---- бесконечные предметы
	check(sb.cheats.infinite and z.infinite_tables, "бесконечные предметы включены по умолчанию")
	var e: Dictionary = {}
	for it: Dictionary in z._table_items:
		if it.zone == &"items" and is_instance_valid(it.node):
			e = it
			break
	check(not e.is_empty(), "предметы лежат на столах (%d)" % z._table_items.size())
	if not e.is_empty():
		var old: Node = e.node
		p.inventory.add(e.id, int(e.n))
		old.queue_free()
		await wait(0.8)
		check(is_instance_valid(e.node) and e.node != old, "взятый со стола предмет «%s» появился снова" % Items.item_name(e.id))
	var ammo := &"ammo_9mm" if Items.get_item(&"ammo_9mm") else &"stone"
	p.inventory.add(ammo, 10)
	await wait(0.6)
	var have := p.inventory.count(ammo)
	p.inventory.remove(ammo, 6)
	await wait(0.8)
	check(p.inventory.count(ammo) >= have, "расход не уменьшает запас: %s %d → %d" % [ammo, have, p.inventory.count(ammo)])
	# ---- погода, время, ветер
	sb.cheats.set_weather(&"storm")
	await wait(0.5)
	check(w.weather() == &"storm" and w.storm_intensity() > 0.5, "кнопка «Гроза» (%s, шторм %.2f)" % [w.weather(), w.storm_intensity()])
	await _key(KEY_F5)
	await wait(0.3)
	check(w.weather() == &"clear", "F5 — следующая погода (%s)" % w.weather())
	await _key(KEY_F5)
	await wait(0.3)
	check(w.weather() == &"cloudy", "F5 ещё раз — облачно (%s)" % w.weather())
	sb.cheats.set_time(13.0)
	await wait(0.3)
	await _key(KEY_F6)
	await wait(0.3)
	check(absf(w.time_of_day() - 19.0) < 0.3, "F6 — следующее время суток (%.2f)" % w.time_of_day())
	sb.cheats.set_wind(22.0)
	await wait(1.0)
	check(w.wind_speed() > 15.0, "ползунок ветра: %.1f м/с" % w.wind_speed())
	sb.cheats.set_wind(-1.0)
	await wait(1.0)
	check(w.wind_speed() < 12.0, "ветер вернулся к погоде: %.1f м/с" % w.wind_speed())
	# снимки центра в разную погоду
	sb.cheats.set_weather(&"clear")
	sb.cheats.set_time(10.0)
	sb.panel.go(&"hub")
	await wait(2.0)
	await shot("01_hub")
	var top := Vector3(hub.x - 30.0, 0.0, hub.z + 55.0)
	top.y = SandboxProps.ground(top.x, top.z) + 55.0
	sb.cheats.set_fly(true)
	sb.cheats.teleport(top, Vector3(hub.x + 5.0, 0.0, hub.z - 15.0))
	await wait(2.5)
	await shot("02_overview")
	sb.cheats.set_weather(&"rain")
	await wait(1.5)
	await shot("03_overview_rain")
	sb.cheats.set_weather(&"clear")
	sb.cheats.set_fly(false)
	sb.panel.go(&"fauna")
	await wait(2.0)
	await shot("04_fauna_row")
	sb.panel.go(&"items")
	await wait(2.0)
	await shot("05_items")
	sb.panel.go(&"range")
	await wait(2.0)
	await shot("06_range")
	# ---- убить животное → оно появляется снова
	var pe: Dictionary = {}
	for r: Dictionary in z._respawns:
		if r.kind == &"pen" and r.sp == &"croc" and is_instance_valid(r.node):
			pe = r
			break
	check(not pe.is_empty(), "крокодил в загоне отслеживается")
	if not pe.is_empty():
		var a := pe.node as Animal
		a.die(p)
		await wait(1.0)
		check(a.is_dead(), "крокодил убит")
		await wait(SandboxZones.RESPAWN_S + 2.0)
		var b := pe.node as Animal
		check(is_instance_valid(b) and b != a and not b.is_dead() and b.species == &"croc", "крокодил появился снова")
		if is_instance_valid(b):
			var s: Vector2 = pe.s
			check(Vector2(b.global_position.x, b.global_position.z).distance_to(s) < float(pe.r) + 0.5, "в своём загоне")
	# акула у пирса
	var se: Dictionary = {}
	for r: Dictionary in z._respawns:
		if r.kind == &"shark" and is_instance_valid(r.node):
			se = r
			break
	check(not se.is_empty(), "акулы у пирса отслеживаются")
	if not se.is_empty():
		var sh: Node = se.node
		sh.queue_free()
		await wait(SandboxZones.RESPAWN_S + 2.0)
		check(is_instance_valid(se.node) and se.node != sh, "акула появилась снова")
	# «вернуть всех» — сразу
	var k: Dictionary = {}
	for r: Dictionary in z._respawns:
		if r.kind == &"pen" and r.sp == &"boar" and is_instance_valid(r.node):
			k = r
			break
	if not k.is_empty():
		(k.node as Animal).die(p)
		await wait(0.5)
		var n := z.respawn_all()
		await wait(0.3)
		check(n >= 1 and is_instance_valid(k.node) and not (k.node as Animal).is_dead(), "«Вернуть убитых» — сразу (%d)" % n)
	# анимация прицела: кривая без рывков на концах
	var e0 := CombatController._ease_ads(0.0)
	var e1 := CombatController._ease_ads(1.0)
	var d0 := CombatController._ease_ads(0.02) - e0
	check(e0 == 0.0 and e1 == 1.0 and d0 < 0.001, "вход в прицел плавный (начало %.5f)" % d0)

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
