## test-timeout: 900
extends TestCase
## Диагностика: где модели стендов и живых участков раздела (POLY_SEC, по умолчанию animals).
func _init() -> void:
	scene_path = "res://scenes/polygon/polygon.tscn"
	timeout_sec = 850.0
func run() -> void:
	var pg := scene as Polygon
	while not pg.is_built:
		await wait(0.5)
	var id := StringName(OS.get_environment("POLY_SEC") if OS.get_environment("POLY_SEC") != "" else "animals")
	for k: StringName in pg.sections.keys():
		pg.unload_section(k)
	await wait_frames(2)
	pg.goto_section(id)
	while not pg.sections.has(id) or not (pg.sections[id] as PolygonSection).is_built:
		await wait(0.5)
	await wait(3.0)
	var s := PolygonLayout.section(id)
	for st: Dictionary in s.stands:
		var p: Vector2 = st.pos
		print("[probe] stand ", st.ex.id, " src=", st.ex.src, " at ", p)
	for n in get_tree().get_nodes_in_group(&"wild_animals") + get_tree().get_nodes_in_group(&"replay_actor"):
		var n3 := n as Node3D
		if n3 and absf(n3.global_position.z - float(s.z0)) < 200.0:
			print("[probe] node ", n3.name, " standpos ", n3.get_meta(&"polygon_stand_pos", Vector3.ZERO), " pos ", n3.global_position, " vis ", n3.is_visible_in_tree(), " stand ", n3.has_meta(&"polygon_stand"), " aabb ", PolygonSection.world_aabb(n3).size, " parent ", n3.get_parent().name)
	var sec: PolygonSection = pg.sections[id]
	for n in sec.find_children("*", "Node3D", false, false):
		if n.has_meta(&"polygon_stand"):
			print("[probe] own-stand ", n.name, " ", (n as Node3D).global_position, " vis ", (n as Node3D).is_visible_in_tree(), " aabb ", PolygonSection.world_aabb(n as Node3D).size)
