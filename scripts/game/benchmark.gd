class_name Benchmark
extends Node
## Тест производительности: настоящий матч (4 команды, боты), камера летит
## по фиксированному маршруту ~50 с: у флага → джунгли → низко над проливом →
## обзор архипелага с высоты → чужой остров с ботами. Пишет средний FPS,
## 1 % низких, время по системам (PerfStats) и счётчики рендера по участкам
## в user://benchmark.txt и показывает экран результата.
## Запуск: кнопка в Настройках или аргумент командной строки `-- --benchmark`
## (`--benchmark-quit` — выйти после записи).

const RESULT_PATH := "user://benchmark.txt"
const WARMUP := 4.0

var quit_after := false
var _cam: Camera3D
var _segments: Array[Dictionary] = []
var _seg := -1
var _seg_t := 0.0
var _frames: PackedFloat32Array = []
var _sys_sum: Dictionary = {}
var _sys_n := 0
var _sample_t := 0.0
var _seg_stats: Array[Dictionary] = []
var _running := false
var _world: Node

static func start(tree: SceneTree, quit: bool = false) -> void:
	var old := tree.root.get_node_or_null(^"Benchmark")
	if old:
		old.queue_free()
	var b := Benchmark.new()
	b.name = "Benchmark"
	b.quit_after = quit
	tree.root.add_child(b)
	b._launch()

func _launch() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var tree := get_tree()
	tree.paused = false
	Game.pending_config = {"mode": "ffa", "minutes": 180, "bots_enemy": 1, "bots_ally": 0,
		"difficulty": "normal", "auto_flags": true, "seed": 2026, "benchmark": true}
	var m := (load(GameLauncher.MATCH) as PackedScene).instantiate()
	m.set(&"player_team", 0)
	tree.change_scene_to_node(m)
	_wait_ready()

func _wait_ready() -> void:
	var tree := get_tree()
	for i in 2400:
		await tree.create_timer(0.25, true, false, true).timeout
		var sc := tree.current_scene
		if sc and sc.get(&"loaded_modules") is Array and not (sc.get(&"loaded_modules") as Array).is_empty() \
				and tree.get_first_node_in_group(&"player") != null:
			break
	_world = tree.get_first_node_in_group(&"world")
	if _world == null:
		return
	if _world.has_method(&"set_time_of_day"):
		_world.call(&"set_time_of_day", 10.0)
	if _world.has_method(&"set_weather"):
		_world.call(&"set_weather", &"clear", true)
	var p := tree.get_first_node_in_group(&"player") as Node3D
	p.process_mode = Node.PROCESS_MODE_DISABLED
	_cam = Camera3D.new()
	_cam.name = "BenchmarkCamera"
	_cam.fov = Settings.fov
	_cam.far = 4000.0
	tree.current_scene.add_child(_cam)
	_cam.global_position = p.global_position + Vector3(0, 1.7, 0)
	_cam.current = true
	_build_path(p.global_position)
	await tree.create_timer(WARMUP, true, false, true).timeout
	PerfStats.enabled = true
	PerfStats.reset()
	_running = true
	_next_segment()

func _h(x: float, z: float) -> float:
	return float(_world.call(&"height_at", x, z))

func _wl() -> float:
	return float(_world.call(&"water_level"))

## Маршрут из точек мира (детерминирован: сид 2026).
func _build_path(spawn: Vector3) -> void:
	var isl: Array = _world.call(&"islands")
	var home := Vector2(spawn.x, spawn.z)
	var center := Vector2.ZERO
	var enemy := home + Vector2(300, 0)
	var best := 1e9
	for I: Dictionary in isl:
		if String(I.kind) == "center":
			center = I.center
		if int(I.team) > 0:
			var d := (I.center as Vector2).distance_to(home)
			if d < best:
				best = d
				enemy = I.center
	var to_c := (center - home).normalized()
	var side := Vector2(-to_c.y, to_c.x)
	_segments = [
		{"name": "У флага", "dur": 8.0, "kind": "pan", "pos": home, "eye": 1.7},
		{"name": "Джунгли", "dur": 10.0, "kind": "walk", "a": home, "b": home + side * 55.0, "eye": 1.7},
		{"name": "Над проливом", "dur": 12.0, "kind": "fly", "a": home + to_c * 30.0, "b": center - to_c * 40.0, "alt": 4.0, "sea": true},
		{"name": "Обзор с высоты", "dur": 10.0, "kind": "orbit", "pos": center, "alt": 90.0, "r": 160.0},
		{"name": "Остров соперника", "dur": 10.0, "kind": "walk", "a": enemy - (enemy - home).normalized() * 50.0, "b": enemy, "eye": 1.7},
	]

func _next_segment() -> void:
	if _seg >= 0:
		_close_segment()
	_seg += 1
	_seg_t = 0.0
	_frames = []
	if _seg >= _segments.size():
		_finish()

func _close_segment() -> void:
	var s := PerfStats.snapshot()
	var st := _frame_stats(_frames)
	st["name"] = _segments[_seg].name
	st["draw"] = s.draw_calls
	st["prim"] = s.primitives
	st["objects"] = s.objects
	_seg_stats.append(st)

static func _frame_stats(fr: PackedFloat32Array) -> Dictionary:
	if fr.is_empty():
		return {"avg_fps": 0.0, "low1_fps": 0.0, "max_ms": 0.0, "frames": 0}
	var sum := 0.0
	for f in fr:
		sum += f
	var sorted := fr.duplicate()
	sorted.sort()
	var n1 := maxi(1, int(sorted.size() * 0.01))
	var worst := 0.0
	for i in n1:
		worst += sorted[sorted.size() - 1 - i]
	worst /= n1
	return {"avg_fps": 1000.0 / (sum / fr.size()), "low1_fps": 1000.0 / worst,
		"max_ms": sorted[sorted.size() - 1], "frames": fr.size()}

var _all: PackedFloat32Array = []

func _process(delta: float) -> void:
	if not _running or _cam == null or not is_instance_valid(_cam):
		return
	_frames.append(delta * 1000.0)
	_all.append(delta * 1000.0)
	_seg_t += delta
	_sample_t += delta
	if _sample_t >= 0.5:
		_sample_t = 0.0
		_sys_n += 1
		for row: Array in PerfStats.systems_ms():
			_sys_sum[row[0]] = float(_sys_sum.get(row[0], 0.0)) + float(row[1])
	var sg: Dictionary = _segments[_seg]
	var k := clampf(_seg_t / float(sg.dur), 0.0, 1.0)
	match String(sg.kind):
		"pan":
			var p2: Vector2 = sg.pos
			_cam.global_position = Vector3(p2.x, _h(p2.x, p2.y) + float(sg.eye), p2.y)
			_cam.rotation = Vector3(-0.05, k * TAU, 0.0)
		"walk":
			var q: Vector2 = (sg.a as Vector2).lerp(sg.b, k)
			var y := maxf(_h(q.x, q.y), _wl()) + float(sg.eye)
			_cam.global_position = Vector3(q.x, y, q.y)
			var dir: Vector2 = ((sg.b as Vector2) - (sg.a as Vector2)).normalized()
			_cam.look_at(_cam.global_position + Vector3(dir.x, -0.05, dir.y), Vector3.UP)
		"fly":
			var q2: Vector2 = (sg.a as Vector2).lerp(sg.b, k)
			_cam.global_position = Vector3(q2.x, maxf(_h(q2.x, q2.y), _wl()) + float(sg.alt), q2.y)
			var d2: Vector2 = ((sg.b as Vector2) - (sg.a as Vector2)).normalized()
			_cam.look_at(_cam.global_position + Vector3(d2.x, -0.12, d2.y), Vector3.UP)
		"orbit":
			var c: Vector2 = sg.pos
			var a := k * PI
			var r := float(sg.r)
			_cam.global_position = Vector3(c.x + cos(a) * r, float(sg.alt), c.y + sin(a) * r)
			_cam.look_at(Vector3(c.x, 0.0, c.y), Vector3.UP)
	if _seg_t >= float(sg.dur):
		_next_segment()

func _finish() -> void:
	_running = false
	var vp := get_viewport()
	var total := _frame_stats(_all)
	var lines: PackedStringArray = []
	lines.append("Острова — тест производительности  %s" % Time.get_datetime_string_from_system(false, true))
	lines.append("Система: %s | %s | %s | %s" % [OS.get_name(), OS.get_processor_name(),
		RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_driver_name()])
	var win := get_tree().root
	lines.append("Окно %dx%d  3D ×%.2f (режим %d)  пресет: %s  дин.разрешение: %s  vsync: %s  лимит: %d" % [
		win.size.x, win.size.y, vp.scaling_3d_scale, vp.scaling_3d_mode,
		GraphicsQuality.NAMES[clampi(Settings.graphics_quality, 0, 3)],
		"да" if Settings.dynamic_resolution else "нет", "да" if Settings.vsync else "нет", Settings.fps_cap])
	lines.append("")
	lines.append("ИТОГ: средний %.1f FPS, 1%% низких %.1f FPS, худший кадр %.1f мс, кадров %d" % [
		total.avg_fps, total.low1_fps, total.max_ms, total.frames])
	lines.append("")
	lines.append("Участок              FPS   1%низ  макс.мс   draw   примитивы  объекты")
	for st: Dictionary in _seg_stats:
		lines.append("%-18s %6.1f %6.1f %8.1f %6d %10d %8d" % [st.name, st.avg_fps, st.low1_fps, st.max_ms, st.draw, st.prim, st.objects])
	lines.append("")
	lines.append("CPU по системам (мс/кадр, среднее):")
	var keys := _sys_sum.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return float(_sys_sum[a]) > float(_sys_sum[b]))
	for kk: String in keys:
		lines.append("  %-14s %.2f" % [kk, float(_sys_sum[kk]) / maxf(1.0, _sys_n)])
	var snap := PerfStats.snapshot()
	lines.append("Узлы %d, звери %d, акулы %d, боты %d, ОЗУ %.0f МБ, видео %.0f МБ" % [
		snap.nodes, snap.animals, snap.sharks, snap.bots, snap.mem_mb, snap.vram_mb])
	var text := "\n".join(lines)
	print(text)
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string(text + "\n")
		f.close()
	PerfStats.enabled = Settings.show_perf
	if quit_after:
		get_tree().quit(0)
		return
	_show_result(text, total)

func _show_result(text: String, total: Dictionary) -> void:
	var tree := get_tree()
	tree.paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var layer := CanvasLayer.new()
	layer.layer = 110
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var panel := PanelContainer.new()
	panel.theme = UITheme.get_theme()
	panel.add_theme_stylebox_override(&"panel", UITheme.box(UITheme.PANEL, 8, UITheme.LINE, 1, 20))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	layer.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 10)
	panel.add_child(v)
	v.add_child(UITheme.title("Тест производительности: %.0f FPS (1%% низких %.0f)" % [total.avg_fps, total.low1_fps], 24))
	var body := Label.new()
	body.text = text
	body.add_theme_font_size_override(&"font_size", 12)
	v.add_child(body)
	v.add_child(UITheme.label("Файл: " + ProjectSettings.globalize_path(RESULT_PATH), 12, UITheme.TEXT_DIM))
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 12)
	v.add_child(h)
	var copy := Button.new()
	copy.text = "Скопировать результат"
	copy.pressed.connect(func() -> void: DisplayServer.clipboard_set(text))
	h.add_child(copy)
	var menu := Button.new()
	menu.text = "В меню"
	menu.pressed.connect(func() -> void:
		queue_free()
		GameLauncher.to_menu(tree))
	h.add_child(menu)
