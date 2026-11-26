## test-timeout: 900
extends TestCase
func _init() -> void:
	scene_path = "res://scenes/polygon/polygon.tscn"
	timeout_sec = 800.0
func run() -> void:
	var pg := scene as Polygon
	while not pg.is_built:
		await wait(0.5)
	pg.goto_section(&"animals")
	while not pg.sections.has(&"animals") or not (pg.sections[&"animals"] as PolygonSection).is_built:
		await wait(0.5)
	await wait(1.0)
	var s := PolygonLayout.section(&"animals")
	print("[probe] player ", pg.player.global_position, " look yaw ", pg.player.get(&"_yaw"), " z0 ", s.z0, " z1 ", s.z1, " title ", s.title)
	for st in s.stands:
		print("[probe] stand ", st.pos, " ", st.ex.name)
	var sec: PolygonSection = pg.sections[&"animals"]
	var k := 0
	for c in sec.get_children():
		if c is Node3D and k < 12:
			print("[probe] child ", c.name, " ", (c as Node3D).global_position, " vis ", (c as Node3D).visible)
			k += 1
	print("[probe] sections ", pg.sections.keys())
