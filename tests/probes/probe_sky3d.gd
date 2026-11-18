extends TestCase
## Проба Sky3D в gl_compatibility: день, закат, ночь.
func _init() -> void:
	scene_path = ""
	timeout_sec = 200.0

func run() -> void:
	var root := Node3D.new()
	get_tree().root.add_child(root)
	var sky := Sky3D.new()
	root.add_child(sky)
	var m := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(200, 200); m.mesh = pm
	root.add_child(m)
	var b := MeshInstance3D.new(); b.mesh = BoxMesh.new(); b.position = Vector3(0, 0.5, 0); root.add_child(b)
	var cam := Camera3D.new(); cam.position = Vector3(4, 2, 6); root.add_child(cam); cam.look_at(Vector3(0, 3, -20))
	await wait(1.0)
	print("[test] sun=", sky.sun, " tod=", sky.tod, " time=", sky.current_time)
	for t in [8.0, 12.0, 18.3, 19.0, 23.0, 5.8]:
		sky.current_time = t
		await wait(1.0)
		await shot("t%02d" % int(t * 10))
	check(sky.sun != null, "sun")
