extends TestCase
## test-class: render
## WORLD G2: полный архипелаг (25 островов), пресная вода, места для модулей,
## совпадение высот с коллизией, LOD/производительность, скриншоты.

func _init() -> void:
	OS.set_environment("OSTROVA_GEN", "4")   # прежний архипелаг (25 островов, проливы 40–110 м)
	scene_path = "res://scenes/world/world_view.tscn"
	timeout_sec = 1450.0

var cam: Camera3D
var w: World

func run() -> void:
	await wait(1.0)
	w = get_tree().get_first_node_in_group(&"world") as World
	check(w != null and w.is_ready, "мир готов")
	if w == null:
		return
	print("[test] постройка: ", w.build_stats)
	var isl := w.islands()
	var kinds := {}
	for I in isl:
		kinds[I.kind] = int(kinds.get(I.kind, 0)) + 1
	print("[test] острова: ", kinds)
	check(isl.size() >= 20 and isl.size() <= 30, "островов 20–30: %d" % isl.size())
	for k in [&"home", &"shared"]:
		check(int(kinds.get(k, 0)) == 4, "%s ×4" % k)
	for k in [&"center", &"spring", &"swamp", &"rocky", &"atoll", &"wreck"]:
		check(int(kinds.get(k, 0)) >= 1, "есть %s" % k)
	var teams := []
	for I in isl:
		if I.kind == &"home":
			teams.append(int(I.team))
	teams.sort()
	check(teams == [0, 1, 2, 3], "домашние у команд 0–3")
	var biggest: Dictionary = isl[0]
	for I in isl:
		if float(I.radius) > float(biggest.radius):
			biggest = I
	check(biggest.kind == &"center", "вулкан — самый большой")
	# 1) высоты API = физика
	var space := w.get_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var maxerr := 0.0
	var samples := 0
	for k in 600:
		var I: Dictionary = isl[k % isl.size()]
		var c: Vector2 = I.center
		var x := c.x + rng.randf_range(-1.3, 1.3) * float(I.radius)
		var z := c.y + rng.randf_range(-1.3, 1.3) * float(I.radius)
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 120.0, z), Vector3(x, -60.0, z))
		var hit := space.intersect_ray(q)
		if hit.is_empty() or not hit.collider.is_in_group(&"terrain"):
			continue
		maxerr = maxf(maxerr, absf((hit.position as Vector3).y - w.height_at(x, z)))
		samples += 1
	check(samples > 450 and maxerr < 0.02, "высоты = коллизия: %d точек, макс. %.4f м" % [samples, maxerr])
	# 2) проливы
	var gaps := []
	var bad := []
	for r in w.arch.routes:
		var g := _gap(w.arch.islands[r.a], w.arch.islands[r.b])
		gaps.append(roundi(g))
		if g < 40.0 or g > 112.0:
			bad.append("%s↔%s %.0f" % [w.arch.islands[r.a].name, w.arch.islands[r.b].name, g])
	print("[test] проливы: ", gaps)
	check(bad.is_empty(), "проливы 40–110 м (%d шт.) %s" % [gaps.size(), str(bad)])
	check(w.islets().size() >= 8 and w.sandbars().size() >= 16, "островки %d, косы %d" % [w.islets().size(), w.sandbars().size()])
	# 3) пресная вода
	var sp := w.springs()
	check(sp.size() >= 4, "родников/озёр: %d" % sp.size())
	var fw_ok := 0
	for s in sp:
		if w.fresh_water_at(s - Vector3(0, 0.4, 0)) and not w.fresh_water_at(s + Vector3(0, 3.0, 0)) \
				and w.height_at(s.x, s.z) < s.y - 0.5:
			fw_ok += 1
	check(fw_ok == sp.size(), "озёра: вода над дном, fresh_water_at верно (%d/%d)" % [fw_ok, sp.size()])
	var lk_ok := 0
	for s in sp:
		if w.biome_at(s.x, s.z) == &"water" and not w.is_land(s.x, s.z) and w.lake_level_at(s.x, s.z) > -1.0:
			lk_ok += 1
	check(lk_ok == sp.size(), "дно озера — не суша: biome water, is_land false (%d/%d)" % [lk_ok, sp.size()])
	# вода озера не висит над низким берегом снаружи котловины (маска)
	var leak := 0
	for L in w.arch.lakes:
		var c: Vector2 = L.center
		for k in 64:
			var q := c + Vector2.from_angle(k * TAU / 64.0) * float(L.radius) * 1.45
			var hq := w.height_at(q.x, q.y)
			if hq < float(L.level) and w.lake_level_at(q.x, q.y) > -1.0 and hq < float(L.level) - 1.5:
				leak += 1
	check(leak == 0, "вода озёр только в котловине (утечек %d)" % leak)
	var sea_fresh := 0
	for k in 300:
		var p := Vector3(rng.randf_range(-700, 700), -0.3, rng.randf_range(-700, 700))
		if w.height_at(p.x, p.z) < -0.5 and w.fresh_water_at(p):
			sea_fresh += 1
	check(sea_fresh == 0, "в море вода не пресная")
	for L in w.lakes():
		# берег вокруг озера выше уровня (вода не «вытекает»)
		var lowest := 99.0
		for k in 36:
			var a := k * TAU / 36.0
			var p := (L.pos as Vector3) + Vector3(cos(a), 0, sin(a)) * float(L.radius) * 1.36
			lowest = minf(lowest, w.height_at(p.x, p.z))
		check(lowest > float(L.level) + 0.05, "берег озера %s выше воды (мин. %.2f > %.2f)" % [L.kind, lowest, L.level])
	# 4) места для модулей
	var tb := w.trash_beaches()
	var tu := w.turtle_beaches()
	var sw := w.swamps()
	print("[test] мусорных берегов %d, черепашьих %d, болот %d, остовов %d" % [tb.size(), tu.size(), sw.size(), w.wrecks().size()])
	check(tb.size() >= 8 and tu.size() >= 8 and sw.size() >= 4, "точки trash/turtle/swamps есть")
	var dry := 0
	for b in tb + tu:
		var p: Vector3 = b.pos
		if p.y > 0.0 and p.y < 2.6 and w.biome_at(p.x, p.z) == &"beach":
			dry += 1
		else:
			print("[test]   не пляж: %s h=%.2f %s остров %s" % [str(p), p.y, w.biome_at(p.x, p.z), w.arch.islands[b.island].kind])
	check(dry >= int((tb.size() + tu.size()) * 0.8), "пляжные точки на песке: %d/%d" % [dry, tb.size() + tu.size()])
	var swc := 0
	for k in 600:
		var I: Dictionary = isl[16]
		var c: Vector2 = I.center
		var b := w.biome_at(c.x + rng.randf_range(-40, 40), c.y + rng.randf_range(-40, 40))
		if b == &"swamp":
			swc += 1
	check(swc > 150, "мангровый остров — болото (%d/600)" % swc)
	# 5) спавны
	for t in 4:
		var s := w.spawn_point(t)
		check(w.is_land(s.x, s.z) and s.y > 2.0, "спавн команды %d на суше %s" % [t, str(s)])
	# 6) скриншоты + треугольники в кадре
	cam = Camera3D.new()
	cam.far = 5000.0
	w.add_child(cam)
	cam.make_current()
	w.set_time_paused(true)
	w.set_time_of_day(11.0)
	var home: Dictionary = isl[1]
	var hc: Vector2 = home.center
	var spr: Dictionary = isl[9]
	var sc: Vector2 = spr.center
	var env: Environment = w.sky._env
	var fog_was := env.fog_enabled if env else false
	var vfog_was := env.volumetric_fog_enabled if env else false
	if env:
		env.fog_enabled = false
		env.volumetric_fog_enabled = false
	await _view(Vector3(0, 1150, 1), Vector3.ZERO, "01_map_top", 66.0)
	if env:
		env.fog_enabled = fog_was
		env.volumetric_fog_enabled = vfog_was
	await _view(Vector3(sc.x - 70, 45, sc.y + 70), Vector3(sc.x, 4, sc.y), "02_spring_lake")
	var sl: Vector3 = sp[0]
	var lr := float(w.lakes()[0].radius)
	var lg := sl + Vector3(-1.0, 0, 0.6).normalized() * lr * 1.5
	await _view(Vector3(lg.x, w.height_at(lg.x, lg.z) + 1.7, lg.z), sl + (sl - lg) * 0.6 - Vector3(0, 0.5, 0), "03_lake_ground")
	var swi: Dictionary = isl[16]
	var swc2: Vector2 = swi.center
	await _view(Vector3(swc2.x + 70, 35, swc2.y - 60), Vector3(swc2.x, 0, swc2.y), "04_mangrove")
	var at: Dictionary = isl[17]
	var ac: Vector2 = at.center
	await _view(Vector3(ac.x + 60, 55, ac.y + 70), Vector3(ac.x, 0, ac.y), "05_atoll")
	var wr: Dictionary = isl[18]
	var wc: Vector2 = wr.center
	var wk: Dictionary = w.wrecks()[0]
	var wp: Vector3 = wk.pos
	await _view(Vector3(wc.x + 75, 30, wc.y - 40), Vector3(wc.x, 0, wc.y), "06_wreck_graveyard")
	var wcam := wp + (Vector3(wc.x, 0, wc.y) - wp).normalized() * 28.0
	await _view(Vector3(wcam.x, maxf(w.height_at(wcam.x, wcam.z), 0.0) + 2.5, wcam.z), wp + Vector3(0, 2, 0), "07_wreck_close")
	await _view(Vector3(260, 60, 120), Vector3(0, 25, 0), "08_volcano")
	await _view(Vector3(hc.x - 20, w.height_at(hc.x - 20, hc.y) + 12, hc.y - 30), Vector3(sc.x, 6, sc.y), "09_home_to_center")
	var rk: Dictionary = isl[13]
	var rc: Vector2 = rk.center
	await _view(Vector3(rc.x - 80, 25, rc.y - 20), Vector3(rc.x, 10, rc.y), "10_rocky")
	# производительность: треугольники в кадре с земли домашнего острова
	var sp0 := w.spawn_point(0) + Vector3(0, 1.6, 0)
	var tris := []
	for k in 4:
		cam.global_position = sp0
		cam.rotation = Vector3(-0.05, k * PI * 0.5, 0)
		await wait(0.6)
		await RenderingServer.frame_post_draw
		tris.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	print("[test] треугольники в кадре со спавна (4 стороны): %s, draw calls %d, оценка рельефа в радиусе: %d, FPS %.1f" % [str(tris), dc, w.terrain.tris_in_range(sp0), Engine.get_frames_per_second()])
	# вклад слоёв в кадр (взгляд на остров с самым большим числом треугольников)
	cam.rotation = Vector3(-0.05, PI * 0.5, 0)
	var parts := {}
	for nm in ["Terrain", "Ocean", "Wrecks", "Lakes"]:
		var node := w.get_node_or_null(nm) as Node3D
		if node == null:
			continue
		node.visible = false
		await wait(0.3)
		await RenderingServer.frame_post_draw
		parts[nm] = int(tris[1]) - RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		node.visible = true
	print("[test] вклад в кадр (треугольники, с тенями): ", parts)
	var mx := 0
	for t in tris:
		mx = maxi(mx, int(t))
	check(mx < 1500000, "треугольников в кадре < 1.5 млн (макс %d)" % mx)
	check(w.build_ms < 120000, "мир строится < 120 с (%d мс)" % w.build_ms)

func _view(from: Vector3, to: Vector3, name: String, fov: float = 70.0) -> void:
	cam.fov = fov
	cam.global_position = from
	cam.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.FORWARD)
	await wait(0.8)
	await shot(name)
	print("[test] %s: треугольников %d" % [name, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])

## Ширина пролива по прямой между центрами: от последней суши A до первой суши B.
func _gap(a: Dictionary, b: Dictionary) -> float:
	var ca: Vector2 = a.center
	var cb: Vector2 = b.center
	var dir := (cb - ca).normalized()
	var L := ca.distance_to(cb)
	var land_a := 0.0
	var t := 0.0
	while t < L:
		var p := ca + dir * t
		if w.arch.height(p.x, p.y) > 0.0 and int(w.arch.island_at(p).island.get("id", -1)) == int(a.id):
			land_a = t
		t += 0.5
	var land_b := L
	t = L
	while t > 0.0:
		var p := ca + dir * t
		if w.arch.height(p.x, p.y) > 0.0 and int(w.arch.island_at(p).island.get("id", -1)) == int(b.id):
			land_b = t
		t -= 0.5
	return land_b - land_a
