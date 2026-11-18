extends TestCase
## Диагностика: стволы пальм «в воде» на кадре FLORA 08_beach.

func _init() -> void:
	scene_path = "res://scenes/world/match.tscn"
	timeout_sec = 1450.0

func run() -> void:
	var t := 0.0
	while Flora.instance() == null or not Flora.instance().populated:
		await wait(0.5)
		t += 0.5
		if t > 300.0:
			break
	var flora := Flora.instance()
	var w := get_tree().get_first_node_in_group(&"world")
	var list := flora.nodes_near(Vector3.ZERO, 5000.0, &"palm")
	var lowest := 99.0
	var n := 0
	for e in list:
		var pos: Vector3 = e.position
		var h := float(w.call(&"height_at", pos.x, pos.z))
		lowest = minf(lowest, pos.y)
		if n < 6:
			print("[probe] palm y=%.2f h=%.2f wl=%.2f wave=%.2f arch=%.2f" % [pos.y, h, w.water_level(), w.wave_height(pos.x, pos.z), w.arch.height(pos.x, pos.z)])
		n += 1
	print("[probe] palms %d lowest y %.2f, tide %.2f wave_scale %.2f" % [n, lowest, w.water_level(), w.sky.wave_scale()])
	var oc = w.ocean
	print("[probe] ocean pos ", oc.global_position, " mat water_level ", oc.material_override.get_shader_parameter(&"water_level"), " mean ", oc.material_override.get_shader_parameter(&"water_mean"), " scale ", oc.material_override.get_shader_parameter(&"wave_scale"))
	print("[probe] terrain chunks pos ", w.terrain.global_position, " world pos ", w.global_position, " ocean parent ", oc.get_parent().name)
	var cam := get_viewport().get_camera_3d()
	print("[probe] cam ", cam.global_position if cam else Vector3.ZERO)
	# повтор кадра 08_beach
	var pick: Dictionary = {}
	var best := -1.0
	for e in list.slice(0, 300):
		var pos: Vector3 = e.position
		if w.biome_at(pos.x, pos.z) != &"beach":
			continue
		var score := float(flora.nodes_near(pos, 14.0).size())
		if score > best:
			best = score
			pick = e
	var tp: Vector3 = pick.position
	var off := Vector3(10, 0, 8)
	var at := tp + off
	var wl: float = w.water_level()
	var found := false
	for a in 8:
		var o := off.rotated(Vector3.UP, a * PI / 4.0)
		if w.height_at(tp.x + o.x, tp.z + o.z) > wl + 0.35:
			at = tp + o
			found = true
			break
	var gy: float = maxf(w.height_at(at.x, at.z), wl + 0.3)
	print("[probe] pick ", tp, " h ", w.height_at(tp.x, tp.z), " cam_found_land ", found, " cam ground ", w.height_at(at.x, at.z), " gy ", gy)
	for k in 11:
		var q := tp.lerp(at, k / 10.0)
		print("[probe]   line %d: terrain %.2f wave %.2f biome %s" % [k, w.height_at(q.x, q.z), w.wave_height(q.x, q.z), w.biome_at(q.x, q.z)])
	var c := Camera3D.new()
	get_tree().root.add_child(c)
	c.current = true
	c.global_position = Vector3(at.x, gy + 1.7, at.z)
	c.look_at(tp + Vector3(0, 5, 0))
	flora._tick(true)
	await wait(1.5)
	await shot("a_ocean")
	w.ocean.visible = false
	await wait(1.0)
	await shot("b_no_ocean")
	w.ocean.visible = true
	check(true, "probe")
