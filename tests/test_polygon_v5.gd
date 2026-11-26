## test-timeout: 1500
extends TestCase
## Новый полигон (версия 5): музей строится из каталога и реестров (все разделы,
## экспонатов > 0), разделы подгружаются по одному и выгружаются, память на раздел —
## в бюджете, меню открывается, режим наблюдателя убирает игрока из «characters»,
## стрельбище и столы с предметами есть, команда консоли tp ведёт по разделам.
## Снимки разделов (--shots): tests/shots/polygon_v5_<раздел>.png.

const MEM_BUDGET_MB := 900.0      # на один раздел (стенды + живые участки)

var pg: Polygon

func _init() -> void:
	scene_path = "res://scenes/polygon/polygon.tscn"
	timeout_sec = 1400.0

func run() -> void:
	Engine.max_physics_steps_per_frame = 30
	pg = scene as Polygon
	var t0 := Time.get_ticks_msec()
	while not pg.is_built and Time.get_ticks_msec() - t0 < 900000:
		await wait(0.5)
	check(pg.is_built, "полигон собран за %d с" % int((Time.get_ticks_msec() - t0) / 1000.0))
	if not pg.is_built:
		return
	var ex := PolygonExhibits.all()
	check(ex.size() >= 60, "экспонатов в музее: %d" % ex.size())
	var lay := PolygonLayout.get_layout()
	var secs: Array = lay.sections
	check(secs.size() == PolygonExhibits.SECTIONS.size(), "разделов: %d" % secs.size())
	var by := {}
	for e: Dictionary in ex:
		by[e.section] = int(by.get(e.section, 0)) + 1
	for s: Dictionary in PolygonExhibits.SECTIONS:
		if s.id == &"characters" and int(by.get(s.id, 0)) == 0:
			print("[test] (персонажей в каталоге пока нет — раздел пустой)")
			continue
		check(int(by.get(s.id, 0)) > 0, "в разделе «%s» есть модели (%d)" % [s.name, int(by.get(s.id, 0))])
	# каталог ассетов (если уже есть) целиком на полигоне
	var cs := PolygonExhibits.catalog_script()
	if cs:
		var ids := {}
		for e: Dictionary in ex:
			ids[e.id] = true
		var miss := 0
		for ce: Dictionary in cs.call(&"entries"):
			if PolygonExhibits.CAT_SECTION.has(String(ce.get("category", ""))) and not ids.has(String(ce.id)):
				miss += 1
		check(miss == 0, "все записи каталога на полигоне (нет: %d)" % miss)
	# рельеф: ровная площадка, у юга — вода под пирсом
	var hh := PolygonLayout.GROUND_H
	var flat := true
	for s: Dictionary in secs:
		if s.id == &"sea":
			continue
		for x in [-100.0, 0.0, 100.0]:
			var h := pg.world.height_at(x, (float(s.z0) + float(s.z1)) * 0.5)
			flat = flat and absf(h - hh) < 0.05
	check(flat, "музей ровный (высота %.1f м)" % hh)
	var sea := PolygonLayout.section(&"sea")
	var ps: Vector2 = sea.pier_start
	check(pg.world.height_at(ps.x, ps.y + 20.0) < -2.0, "у пирса глубина для аквариумов (%.1f м)" % pg.world.height_at(ps.x, ps.y + 20.0))
	# обход разделов: каждый строится, предыдущий выгружается; память на раздел
	for s: Dictionary in secs:
		var id: StringName = s.id
		# память раздела: от состояния «ничего не построено» до построенного раздела
		for k: StringName in pg.sections.keys():
			pg.unload_section(k)
		await wait_frames(3)
		var mem0 := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
		pg.goto_section(id)
		var t1 := Time.get_ticks_msec()
		while (not pg.sections.has(id) or not (pg.sections[id] as PolygonSection).is_built) and Time.get_ticks_msec() - t1 < 240000:
			await wait(0.5)
		var sec: PolygonSection = pg.sections.get(id)
		check(sec != null and sec.is_built, "раздел «%s» построен (%d мс, стендов %d, участков %d, узлов %d)" % [s.name,
			sec.stats.ms if sec else -1, sec.stats.stands if sec else 0, sec.stats.plots if sec else 0, sec.stats.nodes if sec else 0])
		await wait(1.0)
		check(pg.sections.size() <= Polygon.MAX_SECTIONS, "в памяти не больше %d разделов (%d)" % [Polygon.MAX_SECTIONS, pg.sections.size()])
		var mem := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
		check(mem - mem0 < MEM_BUDGET_MB, "память с разделом «%s»: +%.0f МБ" % [s.name, mem - mem0])
		shot("polygon_v5_" + String(id))
		match id:
			&"weapons":
				check(sec.dummies.size() >= 3, "стрельбище: чучела и мишени (%d)" % sec.dummies.size())
				check(get_tree().get_nodes_in_group(&"pickups").size() >= 10, "оружие на столах")
			&"items":
				check(get_tree().get_nodes_in_group(&"pickups").size() >= 30, "предметы на столах (%d)" % get_tree().get_nodes_in_group(&"pickups").size())
			&"buildings":
				var nb := BuildModule.instance().blueprints().size() if BuildModule.instance() else 0
				check(nb >= 14, "постройки стоят (%d, вместе с домом)" % nb)
			&"animals":
				var live := 0
				for a in get_tree().get_nodes_in_group(&"wild_animals"):
					if (a as Node).process_mode != Node.PROCESS_MODE_DISABLED:
						live += 1
				check(live >= 4, "живые животные в вольерах (%d)" % live)
	# возврат в центр: дальние разделы выгружены
	pg.goto_hub()
	await wait(3.0)
	check(pg.sections.size() <= 1, "в центре разделы выгружены (%d)" % pg.sections.size())
	# наблюдатель
	pg.set_observer(true)
	check(not pg.player.is_in_group(&"characters"), "наблюдатель: игрок невидим для животных")
	pg.set_observer(false)
	check(pg.player.is_in_group(&"characters"), "наблюдатель выключен")
	# меню и консоль
	pg.panel.open()
	await wait_frames(2)
	check(pg.panel.visible and pg.panel.tabs.get_tab_count() >= 6, "меню полигона открыто (%d вкладок)" % pg.panel.tabs.get_tab_count())
	pg.panel.close()
	var r: String = DevConsole.execute("tp птицы")
	await wait(1.0)
	check(r.begins_with("Телепорт"), "консоль: tp по разделу (%s)" % r)
	check(PolygonIslands.list().size() >= 10, "острова в меню: %d" % PolygonIslands.list().size())
	check(pg.recorder != null and pg.recorder.frames.size() > 10, "реплей пишет запись (%d кадров)" % (pg.recorder.frames.size() if pg.recorder else 0))
