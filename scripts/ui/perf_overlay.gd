class_name PerfOverlay
extends CanvasLayer
## Оверлей производительности (F3): FPS, время кадра (CPU скрипты/физика,
## рендер CPU/GPU), вызовы отрисовки, примитивы, объекты, узлы, агенты,
## память, масштаб 3D и время по системам (PerfStats).

const NODE_NAME := "PerfOverlay"
var _label: Label
var _t := 0.0
var _min_fps := 9999.0
var _frames: PackedFloat32Array = []

static func ensure(root: Node) -> void:
	if root == null:
		return
	var cur := root.get_node_or_null(NODE_NAME)
	if Settings.show_perf and cur == null:
		var o := PerfOverlay.new()
		o.name = NODE_NAME
		root.add_child(o)
	elif not Settings.show_perf and cur != null:
		cur.queue_free()
	PerfStats.enabled = Settings.show_perf or PerfStats.enabled

func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.55)
	sb.set_content_margin_all(8)
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override(&"panel", sb)
	panel.position = Vector2(8, 8)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	_label = Label.new()
	_label.add_theme_font_size_override(&"font_size", 12)
	_label.add_theme_color_override(&"font_color", Color(0.9, 1.0, 0.9))
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 3)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_label)
	PerfStats.enabled = true

func _exit_tree() -> void:
	PerfStats.enabled = false

func _process(delta: float) -> void:
	_frames.append(delta * 1000.0)
	if _frames.size() > 240:
		_frames.remove_at(0)
	_t += delta
	if _t < 0.25:
		return
	_t = 0.0
	var s := PerfStats.snapshot()
	var sorted := _frames.duplicate()
	sorted.sort()
	var p99 := sorted[int(sorted.size() * 0.99) - 1] if sorted.size() > 10 else 0.0
	var vp := get_viewport()
	var lines: PackedStringArray = []
	lines.append("FPS %d   кадр %.1f мс (99%% ≤ %.1f мс)" % [s.fps, 1000.0 / maxf(1.0, s.fps), p99])
	lines.append("CPU: скрипты %.1f  физика %.1f  рендер %.1f мс   GPU %.1f мс" % [s.process_ms, s.physics_ms, s.render_cpu_ms, s.gpu_ms])
	lines.append("draw %d   примитивы %dk   объекты %d   узлы %d" % [s.draw_calls, s.primitives / 1000, s.objects, s.nodes])
	lines.append("звери %d  акулы %d  боты %d  косяки %d  тела %d" % [s.animals, s.sharks, s.bots, s.fish, s.bodies])
	lines.append("ОЗУ %.0f МБ  видео %.0f МБ   3D ×%.2f  %s  %s" % [s.mem_mb, s.vram_mb, vp.scaling_3d_scale,
		GraphicsQuality.NAMES[clampi(Settings.graphics_quality, 0, 3)], RenderingServer.get_video_adapter_name()])
	var sea_line := Sea.perf_line()
	if sea_line != "":
		lines.append(sea_line)
	var sys := PerfStats.systems_ms()
	for i in mini(8, sys.size()):
		lines.append("  %-12s %.2f мс" % sys[i])
	_label.text = "\n".join(lines)
