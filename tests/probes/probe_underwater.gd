extends SceneTree
func _init() -> void:
	var w := World.new()
	root.add_child(w)
	var cam := Camera3D.new()
	w.add_child(cam)
	cam.make_current()
	await process_frame
	cam.global_position = Vector3(80.0, -1.8, 140.0)
	cam.look_at(Vector3(60.0, -4.0, 120.0))
	for i in 12:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://tests/shots/probe_underwater.png")
	print("under=", w.sky.is_underwater_view(), " h=", w.height_at(80, 140))
	quit()
