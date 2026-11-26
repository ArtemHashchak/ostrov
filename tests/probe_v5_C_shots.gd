## test-timeout: 2400
extends TestCase
## test-class: render
## Снимки мира v5 для пользователя: обзор архипелага, барьерный риф, стартовый
## островок, джунгли изнутри, звериная тропа, риф под водой.
## Каждый кадр — отдельный файл /mnt/user-data/outputs/v5_C_<имя>.png.

func _init() -> void:
	OS.set_environment("OSTROVA_GEN", "5")
	scene_path = "res://scenes/world/world_view.tscn"   # без зверей/ботов — меньше памяти
	timeout_sec = 2350.0

var cam: Camera3D
var w: World

func run() -> void:
	await wait(2.0)
	w = get_tree().get_first_node_in_group(&"world") as World
	if w == null or not w.is_ready:
		check(false, "мир готов")
		return
	Settings.view_distance = ViewDistance.SLIDER_MAXIMUM
	if Settings.has_method(&"apply_view"):
		Settings.call(&"apply_view")
	var fl := Flora.new()
	w.get_parent().add_child(fl)
	if ResourceLoader.exists("res://scenes/sea/sea.tscn"):
		w.get_parent().add_child((load("res://scenes/sea/sea.tscn") as PackedScene).instantiate())
	if not fl.populated:
		await fl.flora_ready
	w.set_time_of_day(10.5)
	w.set_weather(&"clear", true)
	cam = Camera3D.new()
	cam.far = 20000.0
	w.add_child(cam)
	cam.current = true
	for pl in get_tree().get_nodes_in_group(&"player"):
		(pl as Node).process_mode = Node.PROCESS_MODE_DISABLED
		(pl as Node3D).global_position = Vector3(0, -500, 0)
	var a := w.arch as ArchipelagoV5
	# 1) обзор архипелага
	await _view(Vector3(0, 1500, 1750), Vector3(0, 0, 150), "overview", 4.0)
	if OS.get_environment("ONLY_OVERVIEW") == "1":
		return
	# 2) барьерный риф и проход
	var ps: Vector2 = a.reef_passes[0]
	var rp := Vector2.from_angle(ps.x) * a.ring_r(ps.x)
	var out := Vector2.from_angle(ps.x)
	var side := Vector2(-out.y, out.x)
	await _view(Vector3(rp.x, 0, rp.y) + Vector3(out.x, 0, out.y) * -260.0 + Vector3(side.x, 0, side.y) * 160.0 + Vector3(0, 230, 0),
			Vector3(rp.x, 0, rp.y), "barrier_reef", 4.0)
	# 3) стартовый островок с воздуха
	var st: Dictionary = {}
	for I in a.islands:
		if a.class_of(I) == &"start" and int(I.team) == 0:
			st = I
	var sc: Vector2 = st.center
	var sd := sc.normalized()
	await _view(Vector3(sc.x, 0, sc.y) + Vector3(sd.x, 0, sd.y) * 140.0 + Vector3(0, 75, 0), Vector3(sc.x, 2, sc.y), "starter_islet", 5.0)
	# 4) центр — опушка и стена джунглей
	var C: Dictionary = a.islands[0]
	var cc: Vector2 = C.center
	var zm := w.zones
	var edge := cc + Vector2(float(C.radius) * 0.62, 0)
	for k in 40:
		var p := cc + Vector2.from_angle(k * 0.157) * float(C.radius) * 0.62
		if zm.zone_at(p.x, p.y) == ZoneMap.Z_JUNGLE:
			edge = p
			break
	var dirc := (cc - edge).normalized()
	var eye := edge - dirc * 6.0
	await _view(Vector3(eye.x, w.height_at(eye.x, eye.y) + 1.7, eye.y), Vector3(edge.x + dirc.x * 20.0, w.height_at(edge.x, edge.y) + 1.4, edge.y + dirc.y * 20.0), "jungle_wall", 6.0)
	# 5) звериная тропа
	if not w.trails.trails.is_empty():
		var best: PackedVector2Array = w.trails.trails[0]
		for t in w.trails.trails:
			if t.size() > best.size():
				best = t
		var i0 := best.size() / 3
		var p0 := best[i0]
		var p1 := best[mini(i0 + 4, best.size() - 1)]
		await _view(Vector3(p0.x, w.height_at(p0.x, p0.y) + 1.0, p0.y), Vector3(p1.x, w.height_at(p1.x, p1.y) + 0.8, p1.y), "animal_trail", 6.0)
	# 6) риф под водой
	var reef := Vector2.ZERO
	for k in range(0, zm.zone.size(), 37):
		if zm.zone[k] == ZoneMap.Z_REEF_FLAT and zm.reef[k] > 200:
			reef = zm.origin + Vector2(k % zm.nx, k / zm.nx) * ZoneMap.STEP
			var fy := w.height_at(reef.x, reef.y)
			if fy < -2.0 and fy > -4.0:
				break
	var fy0 := w.height_at(reef.x, reef.y)
	await _view(Vector3(reef.x - 6, fy0 + 1.6, reef.y - 6), Vector3(reef.x + 6, fy0 + 0.2, reef.y + 6), "reef_underwater", 6.0)
	# 7) зоны — карта (вид сверху, отладочные цвета)
	_zone_png()

func _view(pos: Vector3, look: Vector3, nm: String, settle: float) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	w.terrain.focus_override = [pos] as Array[Vector3]
	await wait(settle)
	await wait_frames(3)
	var img := get_viewport().get_texture().get_image()
	if img and not img.is_empty():
		img.save_png("/mnt/user-data/outputs/v5_C_%s.png" % nm)
		print("[shot] v5_C_%s.png" % nm)
	shot(nm)

const COLS := [Color(0.05,0.1,0.3), Color(0.1,0.25,0.55), Color(0.4,0.85,0.85), Color(0.9,0.5,0.6), Color(1,0.2,0.3), Color(0.6,0.2,0.4), Color(0.3,0.6,0.8), Color(0.3,0.45,0.35),
	Color(0.95,0.9,0.6), Color(0.85,0.75,0.45), Color(0.6,0.8,0.3), Color(0.3,0.6,0.2), Color(0.05,0.35,0.08), Color(0.5,0.5,0.5), Color(0.35,0.4,0.2), Color(0.75,0.75,0.35),
	Color(0.2,0.5,1), Color(0.6,0.3,0.1), Color(0.2,0.15,0.15)]

func _zone_png() -> void:
	var zm := w.zones
	var img := Image.create(zm.nx, zm.nz, false, Image.FORMAT_RGB8)
	for j in zm.nz:
		for i in zm.nx:
			var k := j * zm.nx + i
			var c: Color = COLS[zm.zone[k]]
			if zm.zone[k] == ZoneMap.Z_JUNGLE or zm.zone[k] == ZoneMap.Z_LOWLAND_FOREST:
				c = c.lerp(Color(0, 0.12, 0), float(zm.jungle[k]) / 255.0 * 0.8)
			img.set_pixel(i, j, c)
	for t in w.trails.trails:
		for p in t:
			var i := int((p.x - zm.origin.x) / ZoneMap.STEP)
			var j := int((p.y - zm.origin.y) / ZoneMap.STEP)
			if i >= 0 and j >= 0 and i < zm.nx and j < zm.nz:
				img.set_pixel(i, j, Color(1, 0.55, 0))
	img.resize(zm.nx * 2, zm.nz * 2, Image.INTERPOLATE_NEAREST)
	img.save_png("/mnt/user-data/outputs/v5_C_zone_map.png")
