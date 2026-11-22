## test-timeout: 1800
extends TestCase
## test-class: render
## Полигон «Пак моделей»: морские модели со скелетом (SeaSkel) — витрины на суше (каждая модель
## отдельным снимком, клипы по кругу) и живые особи под водой у пирса (поведение по заданиям автора),
## стаи сардин (VAT) и хирургов. Снимки — tests/shots/test_sea_skel_show_*.png.

var sb: Sandbox

func _init() -> void:
	scene_path = "res://scenes/sandbox/sandbox.tscn"
	timeout_sec = 1800.0

func run() -> void:
	Engine.max_physics_steps_per_frame = 30
	sb = scene as Sandbox
	var t0 := Time.get_ticks_msec()
	while not sb.is_built and Time.get_ticks_msec() - t0 < 1200000:
		await wait(0.5)
	check(sb.is_built, "полигон собран")
	if not sb.is_built:
		return
	var z := sb.zones
	for id in [&"pack_skel_row", &"pack_skel_sea"]:
		check(z.points.has(id), "точка перемещения: %s" % id)
	var shows := get_tree().root.find_children("SkelShow_*", "Node3D", true, false)
	check(shows.size() >= 30, "витрин моделей со скелетом: %d" % shows.size())
	sb.panel.go(&"pack_skel_row")
	await wait(3.0)
	await shot("00_rows")
	var only := OS.get_environment("SKEL_SHOW_ONLY")
	for n: Node3D in shows:
		var id := String(n.name).substr(9)
		if only != "" and not (id in only.split(",")):
			continue
		var s: SeaSkel = (n as SandboxSeaSkel.Showcase).s
		var ab := SeaSkel.bounds(id)
		var size := maxf(ab.size.z, ab.size.x) * s.scale_k
		var p := n.global_position
		var dist := clampf(size * 1.25, 0.9, 5.5)
		var from := p + Vector3(0.35 * dist, 0.35 * dist + 0.1, dist) if not bool(s.d.get("ground", false)) \
			else p + Vector3(0.5 * dist, 0.9 * dist, 0.6 * dist)
		sb.cheats.teleport(from - Vector3(0, 1.6, 0), p)
		await wait(1.6)
		await shot("01_%s" % id)
	# под водой
	var live := get_tree().root.find_child("PackSeaLive", true, false) as UserSeaActors
	check(live != null and live.critters.size() >= 20, "живых особей со скелетом под водой: %d" % (live.critters.size() if live else 0))
	sb.cheats.set_fly(true)
	sb.panel.go(&"pack_skel_sea")
	await wait(4.0)
	await shot("02_sea_overview")
	if live:
		var seen := {}
		for c: SeaCritter in live.critters:
			if not is_instance_valid(c) or c.skel == null or seen.has(c.skel.id):
				continue
			if only != "" and not (c.skel.id in only.split(",")):
				continue
			seen[c.skel.id] = true
			var L := c.length
			var d := clampf(L * 2.2, 0.6, 7.0)
			var p := c.global_position
			sb.cheats.teleport(p + Vector3(d * 0.7, d * 0.35, d * 0.7) - Vector3(0, 1.6, 0), p)
			await wait(0.8)
			p = c.global_position
			sb.cheats.teleport(p + Vector3(d * 0.7, d * 0.35, d * 0.7) - Vector3(0, 1.6, 0), p)
			await wait(0.4)
			await shot("03_live_%s" % c.skel.id)
	var st := get_tree().root.find_child("PackSkelSchools", true, false) as SeaScene
	if st:
		for i in st.schools.size():
			var s: SeaSchool = st.schools[i]
			var p := s.mean_pos()
			sb.cheats.teleport(p + Vector3(4.0, 1.0, 4.0) - Vector3(0, 1.6, 0), p)
			await wait(1.5)
			await shot("04_school_%d" % i)
	sb.cheats.set_fly(false)
