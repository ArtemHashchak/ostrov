## test-timeout: 1500
extends TestCase
## test-class: render
func _init() -> void:
	scene_path = "res://scenes/polygon/polygon.tscn"
	timeout_sec = 1400.0
func run() -> void:
	var pg := scene as Polygon
	while not pg.is_built:
		await wait(0.5)
	var sec: PolygonSection = pg.sections.get(&"animals")
	while sec == null or not sec.is_built:
		await wait(0.5)
		sec = pg.sections.get(&"animals")
	for mi in sec.find_children("*", "MeshInstance3D", true, false).slice(0, 6):
		var m := mi as MeshInstance3D
		print("[probe] mesh ", m.get_path(), " vis_end ", m.visibility_range_end, " gl ", m.global_position, " visible_in_tree ", m.is_visible_in_tree())
	pg.cheats.set_fly(true)
	pg.cheats.teleport(Vector3(-118, 9, 30), Vector3(-116, 2.2, 50))
	await wait(2.0)
	shot("anim_top")
	pg.cheats.teleport(Vector3(-118, 2.3, 40), Vector3(-118, 2.2, 52))
	await wait(2.0)
	shot("anim_eye")
