extends TestCase
## SURVIVAL — еда: порча в слоте, коптильня, огород (посадка, полив, рост со
## стадиями, увядание, урожай), установка набора ПКМ, травы/припарка против яда,
## кокос (нужен инструмент), мусор: ящик, бочка, жесть → котелок.

var p: Player
var sv: Survival

func _init() -> void:
	timeout_sec = 1300.0

func aim_at(target: Vector3) -> void:
	var d := target - p.get_eye_position()
	p.set_look(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))

func put(id: StringName, n: int, slot: int = 0) -> void:
	p.inventory.set_slot(slot, {"id": id, "n": n})
	p.inventory.select(slot)

func ground(x: float, z: float) -> Vector3:
	return Vector3(x, scene.call(&"height_at", x, z), z)

func until(cond: Callable, sec: float) -> bool:
	var t := 0.0
	while t < sec:
		if cond.call():
			return true
		await wait(0.25)
		t += 0.25
	return bool(cond.call())

func run() -> void:
	await wait(1.0)
	p = get_tree().get_first_node_in_group(&"player") as Player
	sv = (load("res://scenes/survival/survival.tscn") as PackedScene).instantiate() as Survival
	sv.spawn_debris = true
	scene.add_child(sv)
	if not sv.populated:
		await sv.populated_done
	p.inventory.clear()

	# ---------- порча ----------
	Survival.speed = 60.0 # 10 мин сырого мяса → 10 с
	p.inventory.set_slot(5, {"id": &"meat_raw", "n": 3})
	await wait(2.5)
	var fr := Survival.freshness(p, 5)
	check(fr > 0.0 and fr < 0.95, "свежесть сырого мяса падает: %.2f" % fr)
	p.inventory.add(&"meat_raw", 3) # свежие куски освежают стек
	await wait(0.3)
	var fr2 := Survival.freshness(p, 5)
	check(fr2 > fr, "свежие куски подняли среднюю свежесть: %.2f > %.2f" % [fr2, fr])
	await until(func() -> bool: return p.inventory.count(&"rotten_food") > 0, 20.0)
	check(p.inventory.count(&"rotten_food") == 6 and p.inventory.count(&"meat_raw") == 0, "мясо сгнило целиком")
	check(Survival.freshness(p, 5) < 0.0, "гниль больше не портится")
	Survival.speed = 1.0

	# ---------- огород ----------
	var gpos := ground(-12.0, 10.0)
	p.global_position = gpos + Vector3(0, 0.2, 3.5)
	await wait(0.5)
	put(&"garden_kit", 2, 0)
	aim_at(gpos)
	await wait(0.3)
	p.use_selected()
	await wait_frames(3)
	var plots := sv.stations_near(gpos, &"garden", 6.0)
	check(plots.size() == 1 and p.inventory.count(&"garden_kit") == 1, "грядка поставлена ПКМ с набором")
	if plots.is_empty():
		return
	var g := plots[0] as SvGarden
	put(&"seed_maize", 3, 1)
	g.interact(p)
	check(g.crop == &"maize" and p.inventory.count(&"seed_maize") == 2, "посажена кукуруза")
	put(&"water_bottle", 1, 2)
	g.interact(p)
	check(g.moisture > 0.95 and p.inventory.count(&"bottle_empty") == 1, "полито из бутылки, бутылка пустая")
	var g2 := sv.place_structure(null, &"garden", g.global_position + Vector3(2.6, 0, 0)) as SvGarden
	var g3 := sv.place_structure(null, &"garden", g.global_position + Vector3(-2.6, 0, 0)) as SvGarden
	g2.plant(null, &"seed_melon")
	g3.plant(null, &"seed_taro")
	g2.moisture = 1.0
	g3.moisture = 0.0
	Survival.speed = 150.0
	await until(func() -> bool: return g.stage() >= 2, 15.0)
	check(g.stage() >= 2, "кукуруза растёт: стадия %d" % g.stage())
	await wait(0.5)
	aim_at(g.global_position + Vector3(0, 0.3, 0))
	await shot("01_garden_growing")
	check(g3.is_dead() or g3.wilt() > 0.5, "без воды таро вянет: %.2f" % g3.wilt())
	# грядка сохнет быстрее, чем зреет урожай: за цикл нужен ещё один полив
	await until(func() -> bool:
		g.moisture = maxf(g.moisture, 0.6)
		g2.moisture = maxf(g2.moisture, 0.6)
		return g.is_ready() and g2.is_ready(), 30.0)
	Survival.speed = 1.0
	check(g.is_ready() and g2.is_ready(), "урожай созрел: %.2f / %.2f" % [g.growth, g2.growth])
	p.global_position = g.global_position + Vector3(1.0, 0.3, 3.2)
	await wait(0.6)
	aim_at(g.global_position + Vector3(0.6, 0.4, 0))
	await wait(0.5)
	await shot("02_garden_ripe")
	g.interact(p)
	check(p.inventory.count(&"maize") == 4 and p.inventory.count(&"seed_maize") >= 4, "собрал кукурузу и семена")
	check(g.crop == &"", "грядка свободна после урожая")
	put(&"rotten_food", 2, 3)
	g.interact(p)
	check(g.fertile > 0.0, "удобрил гнилью")

	# ---------- коптильня ----------
	var spos := ground(-6.0, 14.0)
	var sm := sv.place_structure(null, &"smoker", spos) as SvSmoker
	p.inventory.set_slot(4, {"id": &"fish_raw", "n": 2})
	p.inventory.set_slot(6, {"id": &"meat_raw", "n": 2})
	p.inventory.set_slot(7, {"id": &"stick", "n": 4})
	p.inventory.select(4)
	sm.interact(p)
	p.inventory.select(6)
	sm.interact(p)
	check(sm.racks.size() == 4, "на вешалах 4 куска")
	p.inventory.select(7)
	sm.interact(p)
	check(sm.smoldering(), "коптильня дымит")
	Survival.speed = 15.0
	await wait(3.0)
	p.global_position = spos + Vector3(0.5, 0.3, 3.0)
	await wait(0.3)
	aim_at(spos + Vector3(0, 0.9, 0))
	await wait(0.5)
	await shot("03_smoker")
	await until(func() -> bool: return sm.ready_count() == 4, 20.0)
	await wait(0.3)
	await shot("03b_smoker_ready")   # готовая рыба — модель из пака (если есть)
	Survival.speed = 1.0
	sm.interact(p)
	check(p.inventory.count(&"smoked_fish") == 2 and p.inventory.count(&"smoked_meat") == 2, "копчёное готово")

	# ---------- травы и яд ----------
	var herbs := sv.herb_sources(p.global_position, 200.0)
	check(not herbs.is_empty(), "API: herb_sources")
	if not herbs.is_empty():
		var hn := herbs[0].node as SvWild
		p.global_position = hn.global_position + Vector3(0.3, 0.3, 1.6)
		await wait(0.4)
		aim_at(hn.global_position + Vector3(0, 0.2, 0))
		await wait(0.4)
		await shot("04_herb")
		hn.interact(p)
	check(p.inventory.count(&"herb") >= 2, "нарвал лечебной травы")
	p.inventory.add(&"leaf", 2)
	var r: Variant = Items.recipes[&"r_poultice"]
	check(PlayerItems.craft(p, r), "скрафтил припарку")
	sv.apply_poison(p, 2.0, 30.0)
	var hp0 := p.health
	await wait(1.6)
	check(p.health < hp0, "яд ранит: %.1f→%.1f" % [hp0, p.health])
	p.consume(&"poultice")
	check(Survival.get_poison(p).y <= 0.0, "припарка сняла яд")

	# ---------- кокос ----------
	p.inventory.clear()
	put(&"coconut", 2, 0)
	p.thirst = 40.0
	check(sv.on_use_item(p, &"coconut") and p.inventory.count(&"coconut") == 2, "без инструмента зелёный кокос не очистить")
	p.inventory.add(&"rock", 1)
	check(sv.on_use_item(p, &"coconut") and p.inventory.count(&"coconut") == 1 and p.inventory.count(&"coconut_peeled") == 1 \
		and p.inventory.count(&"coconut_husk") == 1, "с камнем зелёный кокос очищается: очищенный + шелуха")
	check(not sv.on_use_item(p, &"coconut_peeled"), "очищенный с камнем — можно расколоть")
	check(sv.consume_item(p, &"coconut_peeled"), "выпил кокос")
	check(p.thirst >= 40.0 + float(PlayerItems.data(&"coconut_peeled").get("thirst", 10.0)) - 0.5 and p.thirst > 48.0 and p.inventory.count(&"coconut_shell") == 1, "кокос поит, остаётся скорлупа: жажда %.1f, скорлуп %d" % [p.thirst, p.inventory.count(&"coconut_shell")])

	# ---------- мусор: ящик, бочка, жесть → котелок ----------
	var debris := sv.debris_near(p.global_position, 500.0)
	var crate: SvDebris = null
	var barrel: SvDebris = null
	var scrap: SvDebris = null
	for d in debris:
		var dn := d.node as SvDebris
		if dn.kind == &"crate" and crate == null: crate = dn
		elif dn.kind == &"barrel" and barrel == null: barrel = dn
		elif dn.kind == &"scrap" and scrap == null: scrap = dn
	if crate == null:
		crate = _make_debris(&"crate")
	if barrel == null:
		barrel = _make_debris(&"barrel")
	if scrap == null:
		scrap = _make_debris(&"scrap")
	p.global_position = crate.global_position + Vector3(0.0, 0.3, 2.6)
	await wait(0.5)
	aim_at(crate.global_position + Vector3(0, 0.3, 0))
	await wait(0.5)
	await shot("05_crate")
	var broke := false
	for i in 12:
		if sv.break_debris(p, crate, 10.0):
			broke = true
			break
	check(broke and p.inventory.count(&"plank") >= 2, "ящик разбит: доски ×%d" % p.inventory.count(&"plank"))
	sv.salvage_debris(p, barrel)
	check(p.inventory.count(&"barrel") == 1, "бочку забрал целиком")
	var got := 0
	for i in 30:
		if not is_instance_valid(scrap) or scrap.is_queued_for_deletion():
			break
		sv.break_debris(p, scrap, 9.0, &"rock")
	got = p.inventory.count(&"scrap_metal")
	check(got >= 3, "жести набрал: %d" % got)
	p.inventory.add(&"rope", 1)
	check(PlayerItems.craft(p, Items.recipes[&"r_pot"]), "из жести — котелок")
	# бочка ставится как дождевая
	put(&"barrel", 1, 0)
	p.global_position = ground(-2.0, 18.0) + Vector3.UP * 0.2
	await wait(0.3)
	aim_at(ground(-2.0, 15.0))
	await wait(0.2)
	var nb := sv.stations_near(p.global_position, &"rain_barrel", 8.0).size()
	p.use_selected()
	await wait_frames(2)
	check(sv.stations_near(p.global_position, &"rain_barrel", 8.0).size() == nb + 1, "бочка поставлена как дождевая")
	check(not sv.food_sources(p.global_position, 300.0).is_empty(), "API: food_sources")

func _make_debris(k: StringName) -> SvDebris:
	var d := SvDebris.new()
	d.kind = k
	d.seed_v = 3
	sv.structures.add_child(d)
	d.global_position = ground(4.0 + randf() * 4.0, 20.0)
	return d
