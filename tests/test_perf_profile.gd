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
		var c: Array = by.get(key, [0, 0, 0])
		c[0] += 1
		if inside:
			c[1] += 1
		if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			c[2] += 1
		by[key] = c
	var rows: Array = []
	for k: String in by:
		rows.append([k] + (by[k] as Array))
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	log_line("in range of camera: name  in_range  in_frustum  shadow")
	for i in mini(30, rows.size()):
		log_line("  ~%-46s %6d %6d %6d" % rows[i])

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
