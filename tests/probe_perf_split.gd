extends TestCase
## Раскладка стоимости кадра (замер, не проверка): с точек обзора прячем группы
## узлов и смотрим, сколько вызовов отрисовки/примитивов исчезло.
## Вывод: [split] ... в лог и tests/logs/perf_split.txt.

var _out: PackedStringArray = []

func _init() -> void:
	scene_path = "res://scenes/world/match.tscn"
	timeout_sec = 3500.0
	Game.pending_config = {"mode": "ffa", "minutes": 180, "bots_enemy": 1, "bots_ally": 0, "auto_flags": true}

func log_line(s: String) -> void:
	print("[split] ", s)
	_out.append(s)

func _match_ready() -> bool:
	for i in 1800:
		if scene and scene.is_inside_tree() and not (scene.get(&"loaded_modules") as Array).is_empty() \
				and Game.is_playing() and get_tree().get_first_node_in_group(&"player") != null:
			return true
		await wait(0.5)
	return false

func _measure() -> Vector2i:
	await wait_frames(8)
	var d := 0
	var p := 0
	for i in 3:
		await get_tree().process_frame
		d += int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		p += int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	return Vector2i(d / 3, p / 3)

## Группа = список GeometryInstance3D по предикату (путь от сцены, узел).
func _collect(pred: Callable) -> Array:
	var res: Array = []
	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for ch in n.get_children():
			stack.append(ch)
		if n is GeometryInstance3D and (n as GeometryInstance3D).visible:
			var path := String(scene.get_path_to(n))
			if pred.call(path, n):
				res.append(n)
	return res

func run() -> void:
	check(await _match_ready(), "матч загрузился")
	PerfStats.enabled = true
	await wait(3.0)
	var p := get_tree().get_first_node_in_group(&"player") as Node3D
	var world := get_tree().get_first_node_in_group(&"world") as Node
	var sun: DirectionalLight3D = null
	for n in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		if (n as DirectionalLight3D).visible:
			sun = n
			break
	var cam := Camera3D.new()
	cam.far = 4000.0
	scene.add_child(cam)
	var sp: Vector3 = p.global_position
	var views := {
		"spawn_eye": [sp + Vector3(0, 1.7, 0), sp + Vector3(20, 1.5, 20)],
		"spawn_to_center": [sp + Vector3(0, 1.7, 0), Vector3.ZERO],
		"jungle": [sp + Vector3(-15, 2.0, -10), sp + Vector3(-60, 2.0, -50)],
	}
	var groups := {
		"flora_trees0": func(path: String, n: Node) -> bool: return path.begins_with("Flora") and String(n.name).begins_with("Trees0"),
		"flora_trees1": func(path: String, n: Node) -> bool: return path.begins_with("Flora") and String(n.name).begins_with("Trees1"),
		"flora_tshadow": func(path: String, n: Node) -> bool: return path.begins_with("Flora") and String(n.name).begins_with("TreesShadow"),
		"flora_trees2": func(path: String, n: Node) -> bool: return path.begins_with("Flora") and String(n.name).begins_with("Trees2"),
		"flora_decor": func(path: String, n: Node) -> bool: return path.begins_with("Flora") and String(n.name).begins_with("Decor"),
		"flora_bush": func(path: String, n: Node) -> bool: return path.begins_with("Flora") and String(n.name).begins_with("Bush"),
		"flora_meshinst": func(path: String, n: Node) -> bool: return path.begins_with("Flora") and n is MeshInstance3D,
		"flora_other_mm": func(path: String, n: Node) -> bool: return path.begins_with("Flora") and n is MultiMeshInstance3D and not (String(n.name).begins_with("Trees") or String(n.name).begins_with("Decor") or String(n.name).begins_with("Bush")),
		"terrain": func(path: String, _n: Node) -> bool: return path.begins_with("World/Terrain"),
		"world_other": func(path: String, _n: Node) -> bool: return path.begins_with("World") and not path.begins_with("World/Terrain"),
		"sea": func(path: String, _n: Node) -> bool: return path.begins_with("Sea"),
		"survival": func(path: String, _n: Node) -> bool: return path.begins_with("Survival"),
		"fauna": func(path: String, _n: Node) -> bool: return path.begins_with("Fauna"),
		"build": func(path: String, _n: Node) -> bool: return path.begins_with("Build"),
		"supply_show": func(path: String, _n: Node) -> bool: return path.begins_with("Supply") or path.begins_with("Show"),
	}
	cam.current = true
	for v: String in views:
		var a: Vector3 = views[v][0]
		var b: Vector3 = views[v][1]
		if world and world.has_method(&"height_at"):
			a.y = maxf(a.y, float(world.call(&"height_at", a.x, a.z)) + 1.7)
		cam.global_position = a
		cam.look_at(b, Vector3.UP)
		var base := await _measure()
		log_line("view %s total draw=%d prim=%d" % [v, base.x, base.y])
		if sun:
			sun.shadow_enabled = false
			var ns := await _measure()
			sun.shadow_enabled = true
			log_line("  %-16s -draw=%5d -prim=%8d" % ["sun_shadows", base.x - ns.x, base.y - ns.y])
		for g: String in groups:
			var nodes := _collect(groups[g])
			if nodes.is_empty():
				continue
			base = await _measure()
			for n in nodes:
				if is_instance_valid(n):
					(n as GeometryInstance3D).visible = false
			var m := await _measure()
			for n in nodes:
				if is_instance_valid(n):
					(n as GeometryInstance3D).visible = true
			# те же, но без тени (только тени группы)
			var sh: Array = []
			for n in nodes:
				if is_instance_valid(n) and (n as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
					sh.append([n, (n as GeometryInstance3D).cast_shadow])
					(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var ms := base
			if not sh.is_empty():
				ms = await _measure()
			for e: Array in sh:
				if is_instance_valid(e[0]):
					(e[0] as GeometryInstance3D).cast_shadow = e[1]
			log_line("  %-16s n=%5d -draw=%5d -prim=%8d | shadow part -draw=%5d -prim=%8d" % [g, nodes.size(), base.x - m.x, base.y - m.y, base.x - ms.x, base.y - ms.y])
		await shot(v)
	cam.current = false
	cam.queue_free()
	# Самые тяжёлые одиночные меши (треугольники × экземпляры) в 150 м от спавна
	var heavy: Array = []
	for n in _collect(func(_p: String, _n: Node) -> bool: return true):
		var gi := n as GeometryInstance3D
		var mesh: Mesh = null
		var inst := 1
		if gi is MeshInstance3D:
			mesh = (gi as MeshInstance3D).mesh
		elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh:
			mesh = (gi as MultiMeshInstance3D).multimesh.mesh
			inst = (gi as MultiMeshInstance3D).multimesh.instance_count
		if mesh == null or gi.global_position.distance_to(sp) > 150.0:
			continue
		var tris := 0
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			var idx = arr[Mesh.ARRAY_INDEX]
			tris += (idx.size() if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		heavy.append([String(scene.get_path_to(gi)).left(60), tris, inst])
	heavy.sort_custom(func(x: Array, y: Array) -> bool: return x[1] > y[1])
	log_line("heaviest meshes within 150 m (tris per instance, instances):")
	var seen := {}
	var shown := 0
	for h: Array in heavy:
		var k := String(h[0]).get_slice("/", 0) + ":" + str(h[1])
		if seen.has(k):
			continue
		seen[k] = true
		log_line("  %-60s %7d x%d" % h)
		shown += 1
		if shown >= 25:
			break
	var f := FileAccess.open("res://tests/logs/perf_split.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_out) + "\n")
	check(true, "замер выполнен")
