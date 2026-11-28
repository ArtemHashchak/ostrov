## test-timeout: 2400
extends TestCase
## test-class: render
## Проба агента O (v5.2): открытое море у островов — над водой и под водой. Ищем «шесты»
## (вертикальные палки) и спам «Too many instances using shader instance variables».
## Кадры: /mnt/user-data/outputs/v52_O_sea_*.png

func _init() -> void:
	OS.set_environment("OSTROVA_GEN", "5")
	scene_path = "res://scenes/world/world_view.tscn"
	timeout_sec = 2350.0

var cam: Camera3D
var w: World

func run() -> void:
	await wait(2.0)
	w = get_tree().get_first_node_in_group(&"world") as World
	if w == null or not w.is_ready:
		check(false, "мир готов")
		return
	var fl := Flora.new()
	w.get_parent().add_child(fl)
	if not fl.populated:
		await fl.flora_ready
	w.set_weather(&"clear", true)
	if w.has_method(&"set_time_paused"):
		w.set_time_paused(true)
	w.set_time_of_day(10.5)
	cam = Camera3D.new()
	cam.far = 3000.0
	cam.fov = 70.0
	w.add_child(cam)
	cam.current = true
	for pl in get_tree().get_nodes_in_group(&"player"):
		(pl as Node).process_mode = Node.PROCESS_MODE_DISABLED
		(pl as Node3D).global_position = Vector3(0, -500, 0)
	var a := w.arch as ArchipelagoV5
	# мелководье у берега: глаз на пляже, взгляд на воду под углом (раньше дно «гранями»)
	var shal := 0
	var skip_first := OS.get_environment("O_SHAL_FROM") != ""
	for I in a.islands:
		if shal >= 2 or OS.get_environment("O_SKIP_SHALLOW") != "":
			break
		var c0: Vector2 = I.center
		var r0 := float(I.radius)
		for kk in 36:
			var dd := Vector2.from_angle(kk * TAU / 36.0 + 0.3)
			var beach := Vector2.INF
			for s in 60:
				var q := c0 + dd * (r0 * 0.6 + s * 4.0)
				var hq := w.height_at(q.x, q.y)
				if hq > 0.2 and hq < 1.2 and w.zone_at(q.x, q.y) == &"beach":
					beach = q
				if hq < -2.5:
					break
			if beach == Vector2.INF:
				continue
			# под водой впереди 10–40 м должно быть мелко (0,5–3 м)
			var ok := true
			for s2 in range(3, 10):
				var q3 := beach + dd * (s2 * 4.0)
				var hh := w.height_at(q3.x, q3.y)
				if hh > -0.3 or hh < -3.5:
					ok = false
					break
			if not ok:
				continue
			if skip_first:
				skip_first = false
				shal += 1
				break
			var eye := Vector3(beach.x, w.height_at(beach.x, beach.y) + 1.7, beach.y)
			var look := Vector3(beach.x + dd.x * 14.0, w.water_level() - 1.5, beach.y + dd.y * 14.0)
			await _view(eye, look, "shallow_%d" % shal)
			if OS.get_environment("O_DIAG") != "":
				w.ocean.visible = false
				await _view(eye, look, "diag_shallow_%d_noocean" % shal)
				w.ocean.visible = true
				var hid: Array = []
				for ch in w.terrain.get_children():
					if ch is Node3D and String(ch.name).begins_with("Tfar"):
						(ch as Node3D).visible = false
						hid.append(ch)
				await _view(eye, look, "diag_shallow_%d_nofar" % shal)
				for ch in hid:
					(ch as Node3D).visible = true
				var hs: Array = []
				for ch in w.terrain.get_children():
					if ch is Node3D and String(ch.name).ends_with("_shadow"):
						(ch as Node3D).visible = false
						hs.append(ch)
				await _view(eye, look, "diag_shallow_%d_noshadowproxy" % shal)
				for ch in hs:
					(ch as Node3D).visible = true
				print("[O] chunks near: ", _near_chunks(eye))
				var edge := Vector3(beach.x + dd.x * 6.0, w.water_level(), beach.y + dd.y * 6.0)
				print("[O] meshes near edge: ", _near_all(edge))
				# по очереди прячем группы и снимаем
				for grp in ["_lod0", "_lod1", "_lod2", "Tsea"]:
					var hidden: Array = []
					for ch in w.terrain.get_children():
						if ch is Node3D and (String(ch.name).ends_with(grp) or String(ch.name).begins_with(grp)):
							(ch as Node3D).visible = false
							hidden.append(ch)
					await _view(eye, look, "diag_shallow_%d_hide%s" % [shal, grp])
					for ch in hidden:
						(ch as Node3D).visible = true
			shal += 1
			break
	var only := OS.get_environment("O_SEA_N")
	var n := int(only) if only != "" else 3
	var k := 0
	for I in a.islands:
		if k >= n:
			break
		var c: Vector2 = I.center
		var r := float(I.radius)
		if r < 120.0:
			continue
		var d := Vector2.from_angle(0.7 + k * 2.1)
		var sea := c + d * (r + 140.0)
		if w.height_at(sea.x, sea.y) > -3.0:
			continue
		var wl := w.water_level()
		await _view(Vector3(sea.x, wl + 2.5, sea.y), Vector3(c.x, wl + 8.0, c.y), "sea_%d_above" % k)
		await _view(Vector3(sea.x, wl - 3.0, sea.y), Vector3(c.x, wl - 4.0, c.y), "sea_%d_under" % k)
		var back := c + d * (r + 420.0)
		await _view(Vector3(back.x, wl + 2.5, back.y), Vector3(back.x + d.x * 300.0, wl, back.y + d.y * 300.0), "sea_%d_open" % k)
		k += 1
	check(k > 0, "снято точек моря: %d" % k)

func _view(pos: Vector3, look: Vector3, nm: String) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	w.terrain.focus_override = [pos] as Array[Vector3]
	await wait(4.0)
	await wait_frames(3)
	var img := get_viewport().get_texture().get_image()
	if img and not img.is_empty():
		img.save_png("/mnt/user-data/outputs/v52_O_%s.png" % nm)
		print("[shot] v52_O_%s.png" % nm)

func _near_chunks(p: Vector3) -> String:
	var out := []
	for ch in w.terrain.get_children():
		if ch is MeshInstance3D and (ch as MeshInstance3D).mesh:
			var ab := (ch as MeshInstance3D).global_transform * (ch as MeshInstance3D).mesh.get_aabb()
			if ab.grow(5.0).has_point(Vector3(p.x, ab.get_center().y, p.z)):
				out.append("%s vis=%s" % [ch.name, str((ch as MeshInstance3D).visible)])
	return ", ".join(out)

func _near_all(p: Vector3) -> String:
	var out := []
	var st: Array = [get_tree().root]
	while not st.is_empty():
		var n: Node = st.pop_back()
		for c in n.get_children():
			st.append(c)
		if n is GeometryInstance3D and (n as Node3D).is_visible_in_tree():
			var gi := n as GeometryInstance3D
			var ab := gi.get_aabb()
			ab = gi.global_transform * ab
			if ab.size.length() < 2000.0 and ab.grow(3.0).has_point(p):
				out.append("%s(%s)" % [gi.name, gi.get_class()])
	return ", ".join(out)
