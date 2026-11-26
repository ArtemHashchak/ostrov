## test-timeout: 1800
extends TestCase
## test-class: render
## Замер мира v5 на пресете «Среднее» (агент G): счётчики рендера и время кадра
## (под llvmpipe абсолютное время ничего не значит — важны вызовы отрисовки,
## треугольники и узлы) в трёх точках: старт на островке, джунгли, риф.
## Итог: [perf5] строки в логе и tests/logs/perf_v5_medium.txt.

func _init() -> void:
	OS.set_environment("OSTROVA_GEN", "5")
	Settings.graphics_quality = 1
	scene_path = "res://scenes/world/world_view.tscn"
	timeout_sec = 1750.0

var cam: Camera3D
var w: World
var out: PackedStringArray = []

func run() -> void:
	await wait(2.0)
	w = get_tree().get_first_node_in_group(&"world") as World
	if w == null or not w.is_ready:
		check(false, "мир готов")
		return
	var fl := Flora.new()
	w.get_parent().add_child(fl)
	if ResourceLoader.exists("res://scenes/sea/sea.tscn"):
		w.get_parent().add_child((load("res://scenes/sea/sea.tscn") as PackedScene).instantiate())
	if not fl.populated:
		await fl.flora_ready
	w.set_time_of_day(11.0)
	w.set_weather(&"clear", true)
	cam = Camera3D.new()
	cam.far = 20000.0
	cam.fov = 75.0
	w.add_child(cam)
	cam.current = true
	for pl in get_tree().get_nodes_in_group(&"player"):
		(pl as Node).process_mode = Node.PROCESS_MODE_DISABLED
		(pl as Node3D).global_position = Vector3(0, -500, 0)
	var a := w.arch as ArchipelagoV5
	var zm := w.zones
	var wl := w.water_level()
	var st: Dictionary = {}
	for I in a.islands:
		if a.class_of(I) == &"start" and int(I.team) == 0:
			st = I
	var sc: Vector2 = st.center
	var sp := sc + (Vector2.ZERO - sc).normalized() * float(st.radius) * 0.4
	await _measure("spawn", Vector3(sp.x, w.height_at(sp.x, sp.y) + 1.7, sp.y), Vector3(0, 20, 0))
	var C: Dictionary = a.islands[0]
	var cc: Vector2 = C.center
	var jp := cc
	for k in 72:
		var p := cc + Vector2.from_angle(k * 0.0873) * float(C.radius) * 0.5
		if zm.zone_at(p.x, p.y) == ZoneMap.Z_JUNGLE:
			jp = p
			break
	await _measure("jungle", Vector3(jp.x, w.height_at(jp.x, jp.y) + 1.7, jp.y), Vector3(cc.x, w.height_at(cc.x, cc.y) + 2.0, cc.y))
	var reef := Vector2.ZERO
	for k in range(0, zm.zone.size(), 37):
		if zm.zone[k] == ZoneMap.Z_REEF_FLAT and zm.reef[k] > 200:
			reef = zm.origin + Vector2(k % zm.nx, k / zm.nx) * ZoneMap.STEP
			var fy := w.height_at(reef.x, reef.y)
			if fy < wl - 2.0 and fy > wl - 4.0:
				break
	var fy0 := w.height_at(reef.x, reef.y)
	await _measure("reef", Vector3(reef.x - 6, fy0 + 1.6, reef.y - 6), Vector3(reef.x + 6, fy0 + 0.2, reef.y + 6))
	var f := FileAccess.open("res://tests/logs/perf_v5_medium.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out) + "\n")
	check(true, "замер сделан")

func _measure(nm: String, pos: Vector3, look: Vector3) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	w.terrain.focus_override = [pos] as Array[Vector3]
	await wait(5.0)
	await wait_frames(5)
	var dc := 0.0
	var prim := 0.0
	var obj := 0.0
	var ft := 0.0
	var n := 20
	for i in n:
		await get_tree().process_frame
		dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prim += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		obj += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		ft += Performance.get_monitor(Performance.TIME_PROCESS)
	var s := "%s: draw_calls=%d primitives=%d objects=%d nodes=%d process_ms=%.1f vram_mb=%.0f mem_mb=%.0f" % [nm, int(dc / n), int(prim / n), int(obj / n),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), ft / n * 1000.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0]
	print("[perf5] ", s)
	out.append(s)
