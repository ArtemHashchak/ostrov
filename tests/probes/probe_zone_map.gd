extends SceneTree
const COLS := [Color(0.05,0.1,0.3), Color(0.1,0.25,0.55), Color(0.4,0.85,0.85), Color(0.9,0.5,0.6), Color(1,0.2,0.3), Color(0.6,0.2,0.4), Color(0.3,0.6,0.8), Color(0.3,0.45,0.35),
	Color(0.95,0.9,0.6), Color(0.85,0.75,0.45), Color(0.6,0.8,0.3), Color(0.3,0.6,0.2), Color(0.05,0.35,0.08), Color(0.5,0.5,0.5), Color(0.35,0.4,0.2), Color(0.75,0.75,0.35),
	Color(0.2,0.5,1), Color(0.6,0.3,0.1), Color(0.2,0.15,0.15)]
func _init() -> void:
	var sd := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1
	var t0 := Time.get_ticks_msec()
	var a := ArchipelagoV5.new(sd)
	var zm := ZoneMap.new()
	zm.build(a)
	print("zone map %d ms stats %s" % [Time.get_ticks_msec() - t0, str(zm.stats)])
	var img := Image.create(zm.nx, zm.nz, false, Image.FORMAT_RGB8)
	for j in zm.nz:
		for i in zm.nx:
			var k := j * zm.nx + i
			var c: Color = COLS[zm.zone[k]]
			if zm.zone[k] == ZoneMap.Z_JUNGLE or zm.zone[k] == ZoneMap.Z_LOWLAND_FOREST:
				c = c.lerp(Color(0, 0.15, 0), float(zm.jungle[k]) / 255.0 * 0.8)
			img.set_pixel(i, j, c)
	img.save_png("/tmp/c_probe/zones_%d.png" % sd)
	var ex := Image.create(zm.nx, zm.nz, false, Image.FORMAT_RGB8)
	for j in zm.nz:
		for i in zm.nx:
			var k := j * zm.nx + i
			var e := float(zm.expo[k]) / 255.0
			ex.set_pixel(i, j, Color(e, e * 0.6, 1.0 - e) if zm.sea[k] == 1 else Color(0.2, 0.2, 0.2))
	ex.save_png("/tmp/c_probe/expo_%d.png" % sd)
	quit()
