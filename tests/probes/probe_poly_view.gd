## test-timeout: 3000
extends TestCase
## test-class: render
## Снимки разделов полигона сверху-сбоку (по одному разделу в памяти).
## POLY_SECTIONS=animals,birds — только эти. Кадры: tests/shots/probe_poly_view_<раздел>.png
func _init() -> void:
	scene_path = "res://scenes/polygon/polygon.tscn"
	timeout_sec = 2900.0
func run() -> void:
	var pg := scene as Polygon
	while not pg.is_built:
		await wait(0.5)
	var only := OS.get_environment("POLY_SECTIONS")
	pg.cheats.set_time(10.0)
	pg.cheats.set_weather(&"clear")
	for s: Dictionary in PolygonLayout.get_layout().sections:
		var id: StringName = s.id
		if only != "" and not (String(id) in only.split(",")):
			continue
		for k: StringName in pg.sections.keys():
			pg.unload_section(k)
		await wait_frames(2)
		pg.goto_section(id)
		while not pg.sections.has(id) or not (pg.sections[id] as PolygonSection).is_built:
			await wait(0.5)
		var t: Vector2 = s.title
		var z0 := float(s.z0)
		# с северо-западного угла раздела вдоль рядов (стенды идут от x = −126 на восток)
		var eye := Vector3(t.x - 8.0, PolygonLayout.GROUND_H + 9.0, z0 - 6.0)
		var at := Vector3(t.x + 26.0, PolygonLayout.GROUND_H, z0 + 16.0)
		if id == &"sea":
			var ps: Vector2 = s.pier_start
			eye = Vector3(ps.x - 30.0, 14.0, ps.y - 26.0)
			at = Vector3(ps.x, 0.0, ps.y + 30.0)
		pg.cheats.set_fly(true)
		pg.cheats.teleport(eye, at)
		await wait(3.0)
		shot(String(id))
		print("[probe] снимок ", id)
