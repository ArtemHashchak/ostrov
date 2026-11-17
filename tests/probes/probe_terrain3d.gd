extends TestCase
## Проба: работает ли Terrain3D в gl_compatibility под xvfb.
func _init() -> void:
	scene_path = ""
func run() -> void:
	var ok := ClassDB.class_exists(&"Terrain3D")
	check(ok, "класс Terrain3D загружен")
	if not ok:
		return
	var root := Node3D.new()
	get_tree().root.add_child(root)
	var env := WorldEnvironment.new(); env.environment = RenderProfile.make_environment(); root.add_child(env)
	root.add_child(RenderProfile.make_sun())
	var t: Node3D = ClassDB.instantiate(&"Terrain3D")
	root.add_child(t)
	var img := Image.create_empty(256, 256, false, Image.FORMAT_RF)
	for y in 256:
		for x in 256:
			var d := Vector2(x - 128, y - 128).length()
			img.set_pixel(x, y, Color(maxf(0.0, 12.0 - d * 0.12), 0, 0))
	t.get(&"data").call(&"import_images", [img, null, null], Vector3(-128, 0, -128), 0.0, 1.0)
	await wait(1.0)
	var h: float = t.get(&"data").call(&"get_height", Vector3(0, 0, 0))
	check(absf(h - 12.0) < 0.6, "высота в центре %.2f" % h)
	var cam := Camera3D.new(); root.add_child(cam); cam.position = Vector3(60, 40, 60); cam.look_at(Vector3.ZERO); cam.current = true
	await wait(1.0)
	await shot("terrain3d")
	var space := root.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(0, 50, 0), Vector3(0, -50, 0))
	var hit := space.intersect_ray(q)
	check(not hit.is_empty(), "коллизия Terrain3D: %s" % str(hit.get("position", "нет")))
