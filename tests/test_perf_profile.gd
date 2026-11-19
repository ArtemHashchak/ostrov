extends TestCase
## Профиль производительности матча (не проверка, а замер): счётчики рендера
## с нескольких точек обзора, перепись узлов с _process, время CPU по
## модулям (разница с выключенным модулем), тайминги PerfStats.
## Результат — в лог ([perf] ...) и в tests/logs/perf_profile.txt.

var _out: PackedStringArray = []

func _init() -> void:
	scene_path = "res://scenes/world/match.tscn"
	timeout_sec = 3500.0
	Game.pending_config = {"mode": "ffa", "minutes": 180, "bots_enemy": 1, "bots_ally": 0, "auto_flags": true}

func log_line(s: String) -> void:
	print("[perf] ", s)
	_out.append(s)

func _match_ready() -> bool:
	for i in 1800:
		if scene and scene.is_inside_tree() and not (scene.get(&"loaded_modules") as Array).is_empty() \
				and Game.is_playing() and get_tree().get_first_node_in_group(&"player") != null:
			return true
		await wait(0.5)
	return false

func _cpu_avg(frames: int) -> float:
	await wait_frames(10)
	var s := 0.0
	for i in frames:
		await get_tree().process_frame
		s += Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	return s / frames * 1000.0

func _geometry_census() -> void:
	var by: Dictionary = {}
	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for ch in n.get_children():
			stack.append(ch)
		if not (n is GeometryInstance3D):
			continue
		var gi := n as GeometryInstance3D
		if not gi.is_visible_in_tree():
			continue
		var rel := String(scene.get_path_to(n))
		var parts := rel.split("/")
		var mod := parts[0]
		if parts.size() > 2:
			mod += "/" + parts[1].left(18)
		var key := "%s:%s" % [mod, n.get_class()]
		var c: Array = by.get(key, [0, 0, 0, 0])
		c[0] += 1
		if gi.visibility_range_end <= 0.0:
			c[1] += 1
		if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			c[2] += 1
		if n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh:
			c[3] += (n as MultiMeshInstance3D).multimesh.visible_instance_count if (n as MultiMeshInstance3D).multimesh.visible_instance_count >= 0 else (n as MultiMeshInstance3D).multimesh.instance_count
		by[key] = c
	var rows: Array = []
	for k: String in by:
		rows.append([k] + (by[k] as Array))
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	log_line("geometry (visible_in_tree): module:class  count  no_range  shadow  mm_instances")
	for i in mini(40, rows.size()):
		log_line("  %-48s %6d %6d %6d %8d" % rows[i])
	_in_range_census()

## Что реально попадает в отрисовку от камеры игрока: узлы в пределах своей
## visibility_range и в пирамиде камеры, по имени узла без цифр.
func _in_range_census() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	var re := RegEx.new()
	re.compile("[0-9_\\-|]+")
	var by: Dictionary = {}
	var top: Array = []
	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for ch in n.get_children():
			stack.append(ch)
		if not (n is GeometryInstance3D) or not (n as GeometryInstance3D).is_visible_in_tree():
			continue
		var gi := n as GeometryInstance3D
		var ab := gi.get_aabb()
		var center := gi.global_transform * ab.get_center()
		var d := center.distance_to(cp)
		if gi.visibility_range_end > 0.0 and d > gi.visibility_range_end + gi.visibility_range_end_margin:
			continue
		if d < gi.visibility_range_begin - gi.visibility_range_begin_margin:
			continue
		var rad := ab.size.length() * 0.5 * gi.global_transform.basis.get_scale().length() / 1.732
		var fr := cam.get_frustum()
		var inside := true
		for pl: Plane in fr:
			if pl.distance_to(center) > rad:
				inside = false
				break
		var parts := String(scene.get_path_to(n)).split("/")
		var key := parts[0] + "/" + re.sub(String(n.name), "", true).left(20) + ":" + n.get_class().left(14)
		var c: Array = by.get(key, [0, 0, 0, 0])
		c[0] += 1
		if inside:
			c[1] += 1
			var tn := _tris(gi)
			c[3] += tn
			top.append([tn, String(scene.get_path_to(n)).right(60)])
		if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			c[2] += 1
		by[key] = c
	var rows: Array = []
	for k: String in by:
		rows.append([k] + (by[k] as Array))
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[4] > b[4])
	var tot := 0
	for r: Array in rows:
		tot += int(r[4])
	log_line("in range of camera: name  in_range  in_frustum  shadow  tris_in_frustum (всего %d, без LOD)" % tot)
	for i in mini(30, rows.size()):
		log_line("  ~%-46s %6d %6d %6d %9d" % rows[i])
	top.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	log_line("  самые тяжёлые узлы в кадре:")
	for i in mini(12, top.size()):
		log_line("    %8d  %s" % top[i])

var _tri_cache: Dictionary = {}

## Точная раскладка: прячем модуль (или выключаем тени солнца) и смотрим, сколько
## вызовов/примитивов исчезло. Узлы модулей — дети сцены и их прямые дети.
func _attribute(view: String, base: Dictionary) -> void:
	var groups: Array = []
	for ch in scene.get_children():
		if ch is Node3D and (ch as Node3D).visible:
			if ch.get_child_count() == 1 and ch.get_child(0) is Node3D:
				ch = ch.get_child(0)   # Flora/Flora
			var subs: Array = []
			for c2 in ch.get_children():
				if c2 is Node3D and (c2 as Node3D).visible:
					subs.append(c2)
			if subs.size() >= 2 and subs.size() <= 40:
				for c2: Node3D in subs:
					groups.append([c2])
			elif subs.size() > 40:
				# много детей (Flora): группы по префиксу имени без чисел
				var by: Dictionary = {}
				for c2: Node3D in subs:
					var nm := String(c2.name).split("_")
					var key := String(ch.name) + "/" + ("@auto" if nm[0].begins_with("@") else nm[0]) + ("_" + nm[1].rstrip("0123456789") if nm.size() > 1 and not nm[1].is_valid_int() else "") + "*"
					if not by.has(key):
						by[key] = []
					(by[key] as Array).append(c2)
				for key: String in by:
					groups.append(by[key])
			else:
				groups.append([ch])
	var rows: Array = []
	for g0: Array in groups:
		var g: Array = g0.filter(func(x: Variant) -> bool: return is_instance_valid(x))
		if g.is_empty():
			continue
		await wait_frames(3)
		base = PerfStats.snapshot()
		for n3: Variant in g:
			if is_instance_valid(n3):
				(n3 as Node3D).visible = false
		await wait_frames(3)
		var s2 := PerfStats.snapshot()
		for n3: Variant in g:
			if is_instance_valid(n3):
				(n3 as Node3D).visible = true
		if not is_instance_valid(g[0]):
			continue
		var dd := int(base.draw_calls) - int(s2.draw_calls)
		var dp := int(base.primitives) - int(s2.primitives)
		if dd > 4 or dp > 5000:
			var label := String(scene.get_path_to(g[0])).left(40)
			if g.size() > 1:
				var nm0 := String(g[0].name).split("_")
				label = "%s/%s_%s* ×%d" % [String(scene.get_path_to(g[0].get_parent())), nm0[0], nm0[1] if nm0.size() > 1 else "", g.size()]
			rows.append([dp, dd, label])
	var sun: DirectionalLight3D = null
	for n in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		if (n as DirectionalLight3D).shadow_enabled and (n as DirectionalLight3D).visible:
			sun = n
			break
	if sun:
		await wait_frames(3)
		base = PerfStats.snapshot()
		sun.shadow_enabled = false
		await wait_frames(3)
		var s3 := PerfStats.snapshot()
		sun.shadow_enabled = true
		rows.append([int(base.primitives) - int(s3.primitives), int(base.draw_calls) - int(s3.draw_calls), "<тени солнца>"])
	await wait_frames(3)
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	log_line("  раскладка %s (−prim, −draw, узел):" % view)
	for r: Array in rows:
		log_line("    %9d %5d  %s" % r)

## Треугольники узла (полная детализация меша × видимые экземпляры MultiMesh).
func _tris(gi: GeometryInstance3D) -> int:
	var mesh: Mesh = null
	var mult := 1
	if gi is MeshInstance3D:
		mesh = (gi as MeshInstance3D).mesh
	elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh:
		var mm := (gi as MultiMeshInstance3D).multimesh
		mesh = mm.mesh
		mult = mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
	if mesh == null:
		return 0
	var id := mesh.get_rid().get_id()
	if not _tri_cache.has(id):
		var t := 0
		if mesh is ArrayMesh:
			var am := mesh as ArrayMesh
			for si in am.get_surface_count():
				var il := am.surface_get_array_index_len(si)
				t += (il if il > 0 else am.surface_get_array_len(si)) / 3
		else:
			t = mesh.get_faces().size() / 3
		_tri_cache[id] = t
	return int(_tri_cache[id]) * mult

func run() -> void:
	check(await _match_ready(), "матч загрузился")
	PerfStats.enabled = true
	await wait(3.0)
	var p := get_tree().get_first_node_in_group(&"player") as Node3D
	var world := get_tree().get_first_node_in_group(&"world") as Node
	# --- рендер с точек обзора
	var cam := Camera3D.new()
	cam.far = 4000.0
	scene.add_child(cam)
	var sp: Vector3 = p.global_position
	var center := Vector3.ZERO
	var views := {
		"spawn_eye": [sp + Vector3(0, 1.7, 0), sp + Vector3(20, 1.5, 20)],
		"spawn_to_center": [sp + Vector3(0, 1.7, 0), center],
		"overview_40m": [sp + Vector3(0, 40, 0), center],
		"jungle": [sp + Vector3(-15, 2.0, -10), sp + Vector3(-60, 2.0, -50)],
	}
	cam.current = true
	for v: String in views:
		var a: Vector3 = views[v][0]
		var b: Vector3 = views[v][1]
		if world and world.has_method(&"height_at"):
			a.y = maxf(a.y, float(world.call(&"height_at", a.x, a.z)) + 1.7)
		cam.global_position = a
		cam.look_at(b, Vector3.UP)
		await wait_frames(20)
		var snap := PerfStats.snapshot()
		log_line("view %-16s draw=%d prim=%d obj=%d" % [v, snap.draw_calls, snap.primitives, snap.objects])
		_in_range_census()
		if v in ["spawn_eye", "spawn_to_center"]:   # раскладка медленная (~10 мин на вид под llvmpipe)
			await _attribute(v, snap)
		await shot(v)
	cam.current = false
	cam.queue_free()
	await wait_frames(5)
	var snap0 := PerfStats.snapshot()
	log_line("nodes=%d animals=%d sharks=%d bots=%d fish=%d bodies=%d mem=%.0fMB" % [snap0.nodes, snap0.animals, snap0.sharks, snap0.bots, snap0.fish, snap0.bodies, snap0.mem_mb])
	# --- перепись
	var census := PerfStats.processing_census(get_tree().root)
	var tot_p := 0
	var tot_pp := 0
	for c: Array in census:
		tot_p += int(c[1])
		tot_pp += int(c[2])
	log_line("processing nodes: _process=%d _physics=%d" % [tot_p, tot_pp])
	for i in mini(25, census.size()):
		log_line("  %-34s p=%d pp=%d" % census[i])
	# --- геометрия по модулям: видимые экземпляры, без дальности видимости, с тенью
	_geometry_census()
	# --- CPU по системам (PerfStats) за 6 с обычной игры
	PerfStats.reset()
	var worst := 0.0
	var t_end := Time.get_ticks_msec() + 8000
	var long_frames := 0
	while Time.get_ticks_msec() < t_end:
		await get_tree().process_frame
		var ms := (Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
		worst = maxf(worst, ms)
		if ms > 50.0:
			long_frames += 1
	log_line("cpu worst frame %.1f ms, frames >50 ms: %d" % [worst, long_frames])
	for spk: Array in PerfStats.spikes:
		var parts: PackedStringArray = []
		for k: StringName in (spk[1] as Dictionary):
			parts.append("%s=%.1f" % [k, float(spk[1][k]) / 1000.0])
		log_line("  spike frame %d: %s" % [spk[0], ", ".join(parts)])
	var snapc := PerfStats.snapshot()
	log_line("cpu: process %.2f ms, physics %.2f ms (последний кадр)" % [snapc.process_ms, snapc.physics_ms])
	for row: Array in PerfStats.systems_ms():
		log_line("  sys %-14s %.2f ms" % row)
	var f := FileAccess.open("res://tests/logs/perf_profile.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_out) + "\n")
	check(true, "замер выполнен")
