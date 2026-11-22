extends TestCase
## FLORA: лежащий ствол выглядит цельным деревом — один меш коры на непрерывный кусок
## (без торцов/швов посередине), надпил появляется только после удара, после распила —
## оставшиеся куски перестраиваются, на срезах торцы с кольцами. Лиственное дерево и пальма.
## Скриншоты крупным планом: до распила, надпил, после распила.

var cam: Camera3D

func _hh(x: float, z: float) -> float:
	return float(scene.call(&"height_at", x, z))

func run() -> void:
	timeout_sec = 900.0
	Engine.max_physics_steps_per_frame = 40
	await wait(0.6)
	for c in scene.get_children():
		if String(c.name).begins_with("Tree") or c.scene_file_path.contains("polyhaven"):
			c.queue_free()
	var p := get_tree().get_first_node_in_group(&"player") as Node3D
	if p:
		p.global_position = Vector3(-40, _hh(-40, -40) + 1.0, -40)
	cam = Camera3D.new()
	scene.add_child(cam)
	cam.fov = 60.0
	cam.make_current()
	await _case(&"broadleaf", 1, Vector3(8, 0, 6))
	await _case(&"palm", 2, Vector3(-6, 0, 10))
	await wait(2.0) # щепки (CPUParticles) живут 1.5 с — не оставлять их к выходу

func _case(kind: StringName, idx: int, at: Vector3) -> void:
	var v := FloraLib.variant(kind, idx)
	var tree := ChoppableTree.new()
	tree.setup(v)
	tree.position = Vector3(at.x, _hh(at.x, at.z) - 0.05, at.z)
	scene.add_child(tree)
	await wait(0.1)
	var hitter := Node3D.new()
	scene.add_child(hitter)
	hitter.global_position = tree.global_position + Vector3(-1.3, 1.0, 0)
	# ---- стоящее дерево: ствол — один меш без торцов
	var tm := (tree.get_node("Trunk") as MeshInstance3D).mesh
	if v.has("pack"):
		# модель пака: стоящее дерево — авторский меш (кора + листва), процедурного ствола нет до удара
		var cm := (tree.get_node("Crown") as MeshInstance3D).mesh
		check(tm == null and cm != null and cm.get_surface_count() == 2, "%s: стоящее дерево — модель пака (%s)" % [kind, v["pack"]])
	else:
		check(tm.get_surface_count() == 1, "%s: стоящий ствол — одна поверхность коры (%d)" % [kind, tm.get_surface_count()])
	var n := 0
	while not tree.felled and n < 60:
		tree.on_hit(hitter, {"position": tree.global_position + Vector3(-0.3, 1.0, 0), "normal": Vector3.LEFT, "tool": &"axe", "damage": 14.0})
		n += 1
	check(tree.felled, "%s: срублено (%d ударов)" % [kind, n])
	var sm := (tree.get_node("Trunk") as MeshInstance3D).mesh
	check(sm.get_surface_count() == 2, "%s: пень — кора + торец (%d поверхн.)" % [kind, sm.get_surface_count()])
	var trunk: FallenTrunk = null
	for c in scene.get_children():
		if c is FallenTrunk and (c as FallenTrunk).variant == v:
			trunk = c
	check(trunk != null, "%s: лежащий ствол есть" % kind)
	if trunk == null:
		return
	var t := 0.0
	while not trunk.settled and t < 14.0:
		await wait(0.25)
		t += 0.25
	await wait(0.3)
	var segs0 := trunk.logs_left()
	# у зонтичного дерева пака ствол до развилки — одно бревно (ещё брёвна дают ветви кроны)
	var multi := segs0 >= 2 or not v.has("pack")
	check(segs0 >= (2 if not v.has("pack") else 1), "%s: участков-брёвен %d" % [kind, segs0])
	check(trunk.piece_count() == 1, "%s: до распила ствол — ОДИН цельный меш (кусков %d)" % [kind, trunk.piece_count()])
	var same := true
	for s: Dictionary in trunk.segments:
		same = same and s["mesh"] == trunk.segments[0]["mesh"]
	check(same, "%s: все участки ссылаются на общий меш" % kind)
	var pm := (trunk.segments[0]["mesh"] as MeshInstance3D).mesh
	check(pm.get_surface_count() == 2, "%s: кора + один торец у пня, без внутренних торцов (%d поверхн.)" % [kind, pm.get_surface_count()])
	# число торцевых треугольников: только нижний срез (12 сторон)
	check(pm.surface_get_array_len(1) == 12 * 3, "%s: торец только на срезе у пня (%d вершин)" % [kind, pm.surface_get_array_len(1)])
	var H: float = v["H"]
	var mid := trunk.global_transform * FloraLib.trunk_point(v, H * 0.45)
	var along := trunk.global_transform.basis.y.normalized()
	var side := along.cross(Vector3.UP).normalized()
	_look(mid + side * 3.6 + Vector3.UP * 1.3 - along * 0.5, mid)
	await wait(0.4)
	await shot("%s_1_fallen" % kind)
	# ---- первый удар по участку: появляется надпил (только теперь)
	var si := mini(1, trunk.segments.size() - 1)
	var s1: Dictionary = trunk.segments[si]
	var hp := trunk.global_transform * FloraLib.trunk_point(v, (float(s1["h0"]) + float(s1["h1"])) * 0.5)
	trunk.on_hit(hitter, {"position": hp, "normal": Vector3.UP, "tool": &"axe", "damage": 14.0})
	trunk.on_hit(hitter, {"position": hp, "normal": Vector3.UP, "tool": &"axe", "damage": 14.0})
	await wait(0.1)
	check(trunk.logs_left() == segs0, "%s: два удара ещё не отделили бревно" % kind)
	check(trunk.piece_count() == 1, "%s: с надпилом ствол всё ещё цельный" % kind)
	var pm2 := (trunk.segments[0]["mesh"] as MeshInstance3D).mesh
	check(not multi or pm2.get_surface_count() == 3, "%s: надпил виден после удара (%d поверхн.)" % [kind, pm2.get_surface_count()])
	var nh: float = trunk._notch.get("h", 0.0)
	var np := trunk.global_transform * FloraLib.trunk_point(v, nh)
	_look(np + side * 1.8 + Vector3.UP * 1.4 + along * 0.4, np)
	await wait(0.3)
	await shot("%s_2_notch" % kind)
	# ---- распил
	var k := 0
	while trunk.logs_left() == segs0 and k < 10:
		trunk.on_hit(hitter, {"position": hp, "normal": Vector3.UP, "tool": &"axe", "damage": 14.0})
		k += 1
	check(trunk.logs_left() == segs0 - 1, "%s: отделено бревно (%d → %d)" % [kind, segs0, trunk.logs_left()])
	await wait(0.1)
	if not multi:
		hitter.queue_free()
		return
	var runs := 1 if si == 0 or si == segs0 - 1 else 2
	check(trunk.piece_count() == runs, "%s: после распила кусков %d (ждали %d)" % [kind, trunk.piece_count(), runs])
	var caps_ok := true
	for s: Dictionary in trunk.segments:
		var m := (s["mesh"] as MeshInstance3D).mesh
		caps_ok = caps_ok and m.get_surface_count() == 2 and m.surface_get_array_len(1) >= 12 * 3
	check(caps_ok, "%s: у кусков кора + торцы на срезах, надпил убран" % kind)
	# бревно — отдельно, с торцами
	var lg: FloraLog = null
	for c in scene.get_children():
		if c is FloraLog:
			lg = c
	check(lg != null, "%s: бревно появилось" % kind)
	await wait(1.5)
	_look(np + side * 2.6 + Vector3.UP * 1.6 + along * 1.2, np + along * 0.3)
	await wait(0.3)
	await shot("%s_3_cut" % kind)
	_look(mid + side * 4.5 + Vector3.UP * 2.0 - along * 1.0, mid)
	await wait(0.3)
	await shot("%s_4_cut_wide" % kind)
	# убрать бревно, чтобы не путать со следующим деревом
	if lg:
		lg.queue_free()
	hitter.queue_free()

func _look(from: Vector3, to: Vector3) -> void:
	cam.global_position = from
	cam.look_at(to)
	cam.make_current()
