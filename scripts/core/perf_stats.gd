class_name PerfStats
extends RefCounted
## Замеры производительности: время по системам (мкс за кадр, скользящее
## среднее), счётчики рендера, активные агенты. Используют оверлей F3 и
## бенчмарк. Вызов из модулей:
##   var t := PerfStats.begin()
##   ... работа ...
##   PerfStats.end(&"fauna", t)

## Включается оверлеем/бенчмарком, чтобы в обычной игре не тратить время.
static var enabled: bool = false
static var _acc: Dictionary = {}     # система → мкс в текущем кадре
static var _avg: Dictionary = {}     # система → сглаженные мкс/кадр
static var _frame: int = -1

static func begin() -> int:
	return Time.get_ticks_usec() if enabled else 0

static func end(system: StringName, t0: int) -> void:
	if not enabled or t0 == 0:
		return
	_roll()
	_acc[system] = int(_acc.get(system, 0)) + (Time.get_ticks_usec() - t0)

## Сдвинуть кадр: накопленное за прошлый кадр уходит в среднее.
static func _roll() -> void:
	var f := Engine.get_process_frames()
	if f == _frame:
		return
	_frame = f
	for k: StringName in _avg.keys():
		if not _acc.has(k):
			_avg[k] = float(_avg[k]) * 0.95
	for k: StringName in _acc.keys():
		_avg[k] = lerpf(float(_avg.get(k, 0.0)), float(_acc[k]), 0.05)
	_acc.clear()

## Сглаженное время систем, мс/кадр, по убыванию.
static func systems_ms() -> Array:
	_roll()
	var out: Array = []
	for k: StringName in _avg.keys():
		out.append([String(k), float(_avg[k]) / 1000.0])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	return out

static func reset() -> void:
	_acc.clear()
	_avg.clear()

## Снимок счётчиков движка.
static func snapshot() -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	var d := {
		"fps": Engine.get_frames_per_second(),
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"mem_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"vram_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"bodies": int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
	}
	if tree:
		d["animals"] = tree.get_node_count_in_group(&"animals")
		d["sharks"] = tree.get_node_count_in_group(&"sharks")
		d["bots"] = tree.get_node_count_in_group(&"bots")
		d["fish"] = tree.get_node_count_in_group(&"fish_schools")
		var vp := tree.root
		var rid := vp.get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(rid, true)
		d["gpu_ms"] = RenderingServer.viewport_get_measured_render_time_gpu(rid)
		d["render_cpu_ms"] = RenderingServer.viewport_get_measured_render_time_cpu(rid)
	return d

## Сколько узлов с включённым _process/_physics_process — по скрипту/классу.
static func processing_census(root: Node) -> Array:
	var counts: Dictionary = {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var p := n.is_processing()
		var pp := n.is_physics_processing()
		if (p or pp) and n.can_process():
			var s := n.get_script() as Script
			var key := s.resource_path.get_file() if s else n.get_class()
			if key == "":
				key = n.get_class()
			var c: Array = counts.get(key, [0, 0])
			if p: c[0] += 1
			if pp: c[1] += 1
			counts[key] = c
		for ch in n.get_children():
			stack.append(ch)
	var out: Array = []
	for k: String in counts:
		out.append([k, counts[k][0], counts[k][1]])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[1] + a[2] > b[1] + b[2])
	return out
