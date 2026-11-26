## test-timeout: 900
extends TestCase
func _init() -> void:
	scene_path = "res://scenes/polygon/polygon.tscn"
	timeout_sec = 800.0
func run() -> void:
	var pg := scene as Polygon
	while not pg.is_built:
		await wait(0.5)
	for k: StringName in pg.sections.keys():
		pg.unload_section(k)
	await wait_frames(2)
	pg.goto_section(&"animals")
	while not pg.sections.has(&"animals") or not (pg.sections[&"animals"] as PolygonSection).is_built:
		await wait(0.5)
	await wait(1.0)
	var sec: PolygonSection = pg.sections[&"animals"]
	print("[probe] sec ", sec.name, " in_tree ", sec.is_inside_tree(), " queued ", sec.is_queued_for_deletion(), " vis ", sec.is_visible_in_tree(), " children ", sec.get_child_count())
	var k := 0
	for c in sec.get_children():
		if c is Node3D and k < 6:
			print("[probe] child ", c.name, " ", (c as Node3D).global_position, " vis ", (c as Node3D).is_visible_in_tree())
			k += 1
	for c in pg.get_children():
		print("[probe] poly child ", c.name, " ", c.get_class())
