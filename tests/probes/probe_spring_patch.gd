extends TestCase
func _init() -> void:
	scene_path = "res://scenes/world/world_view.tscn"
	timeout_sec = 1400.0
func run() -> void:
	await wait(1.0)
	var w := get_tree().get_first_node_in_group(&"world") as World
	var isl := w.islands()
	var spr: Dictionary = isl[9]
	var sc: Vector2 = spr.center
	print("[test] spring ", spr.kind, " c=", sc, " r=", spr.radius, " cliff=", spr.cliff_dir, " lagoon=", spr.lagoon_dir)
	var cam := Camera3D.new(); cam.far = 3000.0; w.add_child(cam); cam.make_current()
	w.set_time_paused(true); w.set_time_of_day(11.0)
	cam.global_position = Vector3(sc.x, 150, sc.y + 0.1); cam.look_at(Vector3(sc.x, 0, sc.y)); cam.fov = 50
	await wait(0.8); await shot("top")
	# ищем точки суши ниже уровня воды (котловины, где видно море)
	var low := 0
	for k in 4000:
		var a := k * 0.0123 * TAU
		var d := fmod(k * 0.37, 1.0) * float(spr.radius) * 1.1
		var x := sc.x + cos(a) * d
		var z := sc.y + sin(a) * d
		var h := w.height_at(x, z)
		if h < w.water_level() and d < float(spr.radius) * 0.85:
			low += 1
			if low < 6: print("[test] низина ", Vector2(x, z), " h=", h, " d/r=", d / float(spr.radius))
	print("[test] низин внутри острова: ", low)
