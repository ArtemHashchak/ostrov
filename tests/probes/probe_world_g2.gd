extends SceneTree
func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var a := Archipelago.new(2026)
	print("layout ms ", Time.get_ticks_msec() - t0, " islands ", a.islands.size(), " bars ", a.bars.size(), " islets ", a.islets.size(), " lakes ", a.lakes.size(), " bounds ", a.bounds)
	for I in a.islands:
		print(I.id, " ", I.kind, " t", I.team, " ", I.center, " r", I.radius)
	for r in a.routes:
		print("route ", r.a, "-", r.b, " gap ", snappedf(r.gap, 0.1))
	t0 = Time.get_ticks_usec()
	var s := 0.0
	for k in 20000:
		s += a.height(randf_range(-600, 600), randf_range(-600, 600))
	print("height us/call ", (Time.get_ticks_usec() - t0) / 20000.0)
	t0 = Time.get_ticks_usec()
	for k in 5000:
		a.biome_weights(randf_range(-600, 600), randf_range(-600, 600), 3.0)
	print("biome us/call ", (Time.get_ticks_usec() - t0) / 5000.0)
	for L in a.lakes:
		print("lake ", L.kind, " ", L.center, " lvl ", L.level, " h_center ", a.height(L.center.x, L.center.y))
	quit()
