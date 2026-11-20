## test-timeout: 900
extends TestCase
## Сцены морской жизни (scripts/sea/scenes): все 34 сцены каталога ставятся режиссёром на
## заглушке моря (пологое дно от берега в глубину), идут несколько секунд с пловцом рядом,
## по каждой — кадры tests/shots/test_sea_scenes_<id>_a/b/c.png. Проверки: сцена встала,
## в ней есть существа; ключевые реакции (укрытие, взрыв косяка, прыжки, засада, скат,
## осьминог в норе), реакции режиссёра (ночь — искры планктона, шторм — муть), цена тика.

func _init() -> void:
	scene_path = ""
	timeout_sec = 3400.0

## Заглушка мира: дно пологим склоном — пляж на x < −20, глубже к +x (до 60 м).
class StubWorld extends Node3D:
	var night := false
	var storm := 0.0
	func height_at(x: float, z: float) -> float:
		var h := -0.2 - (x + 20.0) * 0.16
		h += sin(x * 0.7) * cos(z * 0.6) * 0.15
		return clampf(h, -60.0, 0.6)
	func water_level() -> float:
		return 0.0
	func is_night() -> bool:
		return night
	func time_of_day() -> float:
		return 23.0 if night else 12.0
	func storm_intensity() -> float:
		return storm
	func wind_dir() -> Vector2:
		return Vector2(0.8, 0.6).normalized()
	func biome_at(x: float, z: float) -> StringName:
		return &"water" if height_at(x, z) < 0.0 else &"beach"

class StubSea extends RefCounted:
	var w: StubWorld
	func water_y() -> float:
		return 0.0
	func floor_at(x: float, z: float) -> float:
		return w.height_at(x, z)
	func depth_at(x: float, z: float) -> float:
		return -w.height_at(x, z)

## Пловец-игрок: «в воде», позицию задаёт тест.
class Swimmer extends Node3D:
	func _ready() -> void:
		add_to_group(&"player")
		add_to_group(&"characters")
	func is_in_water() -> bool:
		return true
	func is_dead() -> bool:
		return false

var root: Node3D
var cam: Camera3D
var world: StubWorld
var sea := StubSea.new()
var swimmer: Swimmer
var dir: SeaSceneDirector
var env: Environment

func _ground_mesh() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x0 := -40.0
	var z0 := -60.0
	var nx := 120
	var nz := 60
	var step := 2.6
	for i in nx:
		for j in nz:
			var xa := x0 + i * step
			var za := z0 + j * step
			var p := [Vector3(xa, 0, za), Vector3(xa + step, 0, za), Vector3(xa + step, 0, za + step), Vector3(xa, 0, za + step)]
			for k in 4:
				p[k].y = world.height_at(p[k].x, p[k].z)
			for idx in [0, 1, 2, 0, 2, 3]:
				var v: Vector3 = p[idx]
				var sand := Color(0.84, 0.77, 0.6).lerp(Color(0.62, 0.6, 0.52), clampf(-v.y / 25.0, 0.0, 1.0))
				st.set_color(sand)
				st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	mi.material_override = m
	return mi

func _water_surface() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(700, 700)
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.1, 0.45, 0.55, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.1
	mi.material_override = m
	mi.position = Vector3(150, 0, 0)
	return mi

func _set_under(under: bool) -> void:
	if under:
		env.background_color = Color(0.08, 0.3, 0.37)
		env.fog_light_color = Color(0.08, 0.3, 0.37)
		env.fog_density = 0.045
	else:
		env.background_color = Color(0.55, 0.75, 0.92)
		env.fog_light_color = Color(0.7, 0.82, 0.92)
		env.fog_density = 0.004

func _look(from: Vector3, at: Vector3) -> void:
	cam.global_position = from
	cam.look_at(at)
	_set_under(from.y < 0.0)

func run() -> void:
	root = Node3D.new()
	add_child(root)
	world = StubWorld.new()
	world.add_to_group(&"world")
	root.add_child(world)
	sea.w = world
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.68, 0.72)
	env.ambient_light_energy = 0.9
	env.fog_enabled = true
	we.environment = env
	root.add_child(we)
	root.add_child(RenderProfile.make_sun())
	root.add_child(_ground_mesh())
	root.add_child(_water_surface())
	# фауна (крабы сцен, чайки) — без заселения, мир — заглушка
	var fs := load("res://scenes/fauna/fauna.tscn") as PackedScene
	var fauna := fs.instantiate()
	fauna.set(&"auto_populate", false)
	root.add_child(fauna)
	await wait_frames(3)
	cam = Camera3D.new()
	cam.fov = 60.0
	root.add_child(cam)
	cam.current = true
	swimmer = Swimmer.new()
	root.add_child(swimmer)
	swimmer.global_position = Vector3(0, -50, 300)
	dir = SeaSceneDirector.new()
	dir.sea = sea
	dir.world = world
	dir.auto = false
	root.add_child(dir)

	# --- состав
	var n_sp := OceanRoster.all_species().size()
	var n_pl := OceanRoster.all_plants().size()
	check(n_sp >= 28, "океанский состав: %d видов" % n_sp)
	check(n_pl >= 8, "растения: %d видов" % n_pl)
	var stand := 0
	for sp: Dictionary in OceanRoster.all_species():
		var vis := OceanRoster.visual(sp)
		if String(vis.get("kind", "")) != "":
			stand += 1
	check(stand == n_sp, "у каждого вида есть модель или дублёр (%d/%d)" % [stand, n_sp])
	check(SeaScenesLib.ids().size() >= 26, "сцен в каталоге: %d" % SeaScenesLib.ids().size())

	var cost: Array[String] = []
	var ok_start := 0
	var only := OS.get_environment("SEA_SCENES_ONLY")  # «id1,id2» — прогнать только эти сцены
	for id: String in SeaScenesLib.ids():
		if only != "" and not (id in only.split(",")):
			continue
		var info: Dictionary = SeaScenesLib.CATALOG[id]
		dir.forced_time = String(info.get("time", "any")) if String(info.get("time", "any")) != "any" else "day"
		if dir.forced_time == "dusk":
			dir.forced_time = "dusk"
		world.night = dir.forced_time == "night"
		dir.forced_storm = 0.8 if String(info.get("weather", "any")) == "storm" else 0.0
		world.storm = dir.forced_storm
		var origin := Vector3(-10, 0, 0) if bool(info.get("far", false)) else Vector3(10, 0, 0)
		var pos: Variant = dir.find_spot_around(info, origin, 220.0)
		check(pos != null, "%s: нашлось место по глубине %s" % [id, str(info.depth)])
		if pos == null:
			continue
		var s := dir.play(id, pos as Vector3)
		check(s != null, "%s: сцена поставлена" % id)
		if s == null:
			continue
		ok_start += 1
		var view := String(info.get("view", "underwater"))
		var at: Vector3 = s.at
		var wy := 0.0
		var dep := -at.y
		var eye: Vector3
		var look := at + Vector3(0, minf(1.0, dep * 0.4), 0)
		if bool(info.get("far", false)):
			eye = Vector3(at.x - 90.0, 3.0, at.z - 40.0)
			look = Vector3(at.x, 4.0, at.z)
		elif view == "surface":
			eye = at + Vector3(-7.0, 0.0, -7.0)
			eye.y = wy + 3.5
			look = Vector3(at.x, wy + 0.5, at.z)
		else:
			eye = at + Vector3(-4.5, 0.0, -4.5)
			eye.y = clampf(world.height_at(eye.x, eye.z) + maxf(dep * 0.5, 0.6), world.height_at(eye.x, eye.z) + 0.4, wy - 0.4)
			if dep > 12.0:
				eye.y = at.y + 4.0
				look = at + Vector3(0, 2.0, 0)
		swimmer.global_position = Vector3(at.x, -60, at.z + 300)
		_look(eye, look)
		await wait(2.0)
		await shot("%s_a" % id)
		# пловец подплывает (реакции: укрытие, засада, скат, осьминог)
		swimmer.global_position = at + Vector3(-1.5, minf(1.2, dep * 0.5), -1.2)
		await wait(4.0)
		_look(eye, look)
		await shot("%s_b" % id)
		await wait(5.0)
		await shot("%s_c" % id)
		var content := s.critters.size() + s.schools.size() + s.crabs.size() + s.plants.size() + s.sharks.size()
		check(content > 0, "%s: в сцене есть существа/растения (%d)" % [id, content])
		cost.append("%s %.0f мкс" % [id, s.cpu_us])
		_specific(id, s)
		dir.stop_all()
		await wait_frames(2)
	if OS.get_environment("SEA_SCENES_ONLY") == "":
		check(ok_start >= 26, "поставлено сцен: %d" % ok_start)
	print("[test] цена тика сцен (среднее, мкс): ", ", ".join(cost))

	# --- реакции режиссёра: ночь — искры планктона вокруг движущегося пловца
	dir.forced_time = "night"
	world.night = true
	var p0 := Vector3(30, -3, 0)
	swimmer.global_position = p0
	_look(p0 + Vector3(-1.5, 0.3, -1.5), p0)
	var sparks_before := _count_particles()
	for k in 12:
		swimmer.global_position = p0 + Vector3(k * 0.25, 0, 0)
		await wait(0.3)
	check(_count_particles() > sparks_before, "ночью пловец «зажигает» планктон")
	await shot("night_plankton")
	# шторм — режиссёр сам ставит муть
	dir.forced_time = "day"
	world.night = false
	dir.forced_storm = 0.8
	world.storm = 0.8
	_look(Vector3(25, -2, 0), Vector3(30, -3, 0))
	dir._storm_cd = 0.0
	await wait(1.0)
	var has_storm := false
	for s in dir.active:
		if s.id == "storm_churn":
			has_storm = true
	check(has_storm, "в шторм под водой режиссёр ставит «муть и обломки»")
	dir.stop_all()
	# авто-режим: сам ставит сцену у камеры
	dir.forced_storm = 0.0
	world.storm = 0.0
	dir.auto = true
	dir._acc = SeaSceneDirector.AUTO_EVERY
	_look(Vector3(20, -2.5, 0), Vector3(30, -3, 0))
	await wait(1.0)
	check(dir.active.size() > 0, "авто-режим: сцена поставлена сама (%d)" % dir.active.size())
	dir.auto = false
	dir.stop_all()
	await wait_frames(3)

func _count_particles() -> int:
	var n := 0
	for c in dir.get_children():
		if c is CPUParticles3D:
			n += 1
	return n

func _specific(id: String, s: SeaScene) -> void:
	match id:
		"hide_coral":
			var sch: SeaSchool = s.get(&"sch")
			check(sch != null and (sch.mode == SeaSchool.M.HIDE or sch.hidden_ratio > 0.0), "hide_coral: стая прячется в укрытия при пловце")
		"shark_hunt":
			check(int(s.get(&"hits")) >= 1, "shark_hunt: акула бросилась на косяк (%d)" % int(s.get(&"hits")))
		"bait_ball":
			var sch: SeaSchool = s.get(&"sch")
			check(sch != null and sch.n >= 40, "bait_ball: шар мелочи из %d рыб" % (sch.n if sch else 0))
		"octopus_den":
			check(s.phase >= 1, "octopus_den: осьминог дополз до норы/спрятался (фаза %d)" % s.phase)
		"ray_bury":
			check(s.phase >= 1, "ray_bury: скат взлетел, когда подплыли")
		"crab_chase", "crab_rivals", "lobster_march", "hermit_swap":
			check(s.crabs.size() > 0 and (s.crabs[0] as Animal).scripted, "%s: крабы под управлением сцены" % id)
		"turtle_grazing", "seagrass_nursery", "kelp_forest", "seahorse_grass", "sargassum_raft":
			check(s.plants.size() > 0 and s.plants[0].multimesh.visible_instance_count > 0, "%s: растения посажены" % id)
