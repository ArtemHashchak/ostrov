extends TestCase
## Проба: лучи/частицы под водой и цвет кораллов при простом свете.

func _init() -> void:
	scene_path = ""
	timeout_sec = 300.0

func run() -> void:
	if scene == null:
		scene = Node3D.new()
		get_tree().root.add_child(scene)
	var env := WorldEnvironment.new()
	env.environment = RenderProfile.make_environment()
	scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	scene.add_child(sun)
	var sea := Sea.new()
	sea.auto_populate = false
	scene.add_child(sea)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.8, 0.75, 0.6)
	floor_mi.material_override = fm
	scene.add_child(floor_mi)
	floor_mi.position.y = -6.0
	var types := [SeaMeshes.coral_branch(0), SeaMeshes.coral_brain(0), SeaMeshes.coral_table(0), SeaMeshes.coral_fan(), SeaMeshes.sponge(), SeaMeshes.reef_rock(0), SeaMeshes.grass_clump(9)]
	for i in types.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.use_colors = true
		mm.mesh = types[i]
		mm.instance_count = 1
		mm.set_instance_color(0, Color.WHITE)
		mm.set_instance_transform(0, Transform3D(Basis(), Vector3(-6 + i * 2.0, -6.0, -6.0)))
		mm.set_instance_custom_data(0, Color(0.9, 0.5, 0.6, 0.3))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = SeaMeshes.coral_material(0.0, 0.0)
		scene.add_child(mi)
	var cam := Camera3D.new()
	scene.add_child(cam)
	cam.current = true
	cam.global_position = Vector3(0, 2.0, 4.0)
	cam.look_at(Vector3(0, -6, -6))
	await wait(1.0)
	await shot("above")
	cam.global_position = Vector3(0, -4.0, 2.0)
	cam.look_at(Vector3(0, -5.5, -6))
	await wait(1.5)
	await shot("under")
	sea.queue_free()
