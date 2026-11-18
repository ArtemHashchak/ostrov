extends SceneTree
func _init() -> void:
	var s := SkyWeather.new()
	root.add_child(s)
	s.setup(8.0)
	for t in [5.5, 6.0, 6.5, 7.0, 16.5, 17.0, 17.25, 17.5, 17.75, 18.0, 19.0]:
		s.set_time_of_day(t)
		for f in 6:
			await process_frame
		var d: Vector3 = -s.sky3d.sun.global_transform.basis.z
		print("t=", t, " ct=", snappedf(s.time_of_day(),0.01), " sun_y=", snappedf(d.y, 0.01), " daylight=", snappedf(s.daylight(), 0.01), " tod=", s.sky3d.tod.latitude if "latitude" in s.sky3d.tod else -1)
	quit()
