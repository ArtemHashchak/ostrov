## test-timeout: 3600
extends TestCase
## test-class: render
## Снимки нового полигона для пользователя (каждый — отдельный файл):
## обзор музея, у каждого раздела — общий вид, ряд стендов на уровне глаз и первый
## «живой» участок (вольер/птичник/террариум/грядка); море — пирс и вольеры в воде;
## стрельбище; меню полигона (разделы, острова). POLY_SECTIONS=animals,birds — только эти.
## Кадры: tests/shots/probe_v5_E_shots_<имя>.png

func _init() -> void:
	scene_path = "res://scenes/polygon/polygon.tscn"
	timeout_sec = 3500.0

func _look(pg: Polygon, eye: Vector3, at: Vector3, name: String, settle := 3.0) -> void:
	pg.cheats.set_fly(true)
	pg.cheats.teleport(eye, at)
	await wait(settle)
	await shot(name)
	print("[probe] снимок ", name)

func run() -> void:
	var pg := scene as Polygon
	while not pg.is_built:
		await wait(0.5)
	var only := OS.get_environment("POLY_SECTIONS")
	pg.cheats.set_time(10.5)
	if pg.world and pg.world.has_method(&"set_time_paused"):
		pg.world.call(&"set_time_paused", true)
	pg.cheats.set_weather(&"clear")
	var gh := PolygonLayout.GROUND_H
	var lay := PolygonLayout.get_layout()
	# обзор музея с высоты над центром
	var extras := only == "" or only == "none"
	if extras:
		var hub: Vector2 = lay.hub
		await _look(pg, Vector3(hub.x - 40.0, 70.0, hub.y - 30.0), Vector3(hub.x, gh, hub.y + 120.0), "museum_overview", 4.0)
	for s: Dictionary in lay.sections:
		var id: StringName = s.id
		if only != "" and not (String(id) in only.split(",")):
			continue
		for k: StringName in pg.sections.keys():
			pg.unload_section(k)
		await wait_frames(2)
		pg.goto_section(id)
		while not pg.sections.has(id) or not (pg.sections[id] as PolygonSection).is_built:
			await wait(0.5)
		var nm := String(id)
		if id == &"sea":
			var ps: Vector2 = s.pier_start
			await _look(pg, Vector3(ps.x - 30.0, 14.0, ps.y - 26.0), Vector3(ps.x, 0.0, ps.y + 30.0), "sea_overview")
			await _look(pg, Vector3(ps.x - 3.0, 2.2, ps.y + 6.0), Vector3(ps.x + 4.0, -2.0, ps.y + 14.0), "sea_pier_tanks")
			var plots: Array = s.plots
			if not plots.is_empty():
				var pp: Vector2 = plots[0].pos
				await _look(pg, Vector3(pp.x - 6.0, -2.5, pp.y - 6.0), Vector3(pp.x, -3.5, pp.y), "sea_pen_underwater")
			continue
		var t: Vector2 = s.title
		var z0 := float(s.z0)
		await _look(pg, Vector3(t.x - 8.0, gh + 9.0, z0 - 6.0), Vector3(t.x + 26.0, gh, z0 + 16.0), nm + "_overview")
		var stands: Array = s.stands
		if not stands.is_empty():
			var sp: Vector2 = stands[mini(2, stands.size() - 1)].pos
			await _look(pg, Vector3(sp.x - 2.0, gh + 1.7, sp.y - 6.5), Vector3(sp.x + 4.0, gh + 0.6, sp.y), nm + "_stands")
		var tables: Array = s.get("tables", [])
		if not tables.is_empty():
			var tp: Vector2 = tables[0].pos
			await _look(pg, Vector3(tp.x - 1.5, gh + 2.0, tp.y - 3.0), Vector3(tp.x + 1.0, gh + 0.8, tp.y), nm + "_tables")
		var plots2: Array = s.plots
		if not plots2.is_empty():
			var pl: Dictionary = plots2[0]
			var pp2: Vector2 = pl.pos
			var sz := float(pl.size)
			await _look(pg, Vector3(pp2.x - sz * 0.7, gh + sz * 0.45, pp2.y - sz * 0.7), Vector3(pp2.x, gh + 0.5, pp2.y), nm + "_live", 5.0)
		if s.has("range"):
			var rg: Vector2 = s.range
			await _look(pg, Vector3(rg.x, gh + 1.7, rg.y), Vector3(rg.x, gh + 1.0, rg.y + 60.0), nm + "_range")
	# меню полигона
	if extras:
		pg.goto_hub()
		await wait(2.0)
		pg.panel.open()
		await wait_frames(4)
		pg.panel.tabs.current_tab = 0
		await wait_frames(3)
		await shot("menu_sections")
		pg.panel.tabs.current_tab = 1
		await wait_frames(3)
		await shot("menu_islands")
		pg.panel.close()
	check(true, "снимки готовы")
