## test-timeout: 1200
extends TestCase
## Генератор мира v5: ArchipelagoV5 (граф островов, расстояния, барьерный риф,
## памятники) и карта зон ZoneMap (маска моря, отлив, открытость волнам, зоны).

func _init() -> void:
	OS.set_environment("OSTROVA_GEN", "5")
	scene_path = "res://scenes/world/world_view.tscn"
	timeout_sec = 1150.0

func run() -> void:
	await wait(1.0)
	var w := get_tree().get_first_node_in_group(&"world") as World
	check(w != null and w.is_ready, "мир готов")
	if w == null:
		return
	check(w.arch is ArchipelagoV5, "мир построен генератором v5")
	var a := w.arch as ArchipelagoV5
	print("[test] мир v5: %s; зоны %s" % [str(w.build_stats), str(w.zones.stats.get("zones", {}))])
	# 1) детерминизм: то же зерно — та же раскладка, другое — другая
	var a2 := ArchipelagoV5.new(w.seed_value)
	var same := a2.islands.size() == a.islands.size()
	for i in mini(a.islands.size(), a2.islands.size()):
		same = same and (a.islands[i].center as Vector2).distance_to(a2.islands[i].center) < 0.01
	check(same, "одно зерно — одна раскладка")
	var a3 := ArchipelagoV5.new(w.seed_value + 1)
	var diff := 0.0
	for i in mini(a.islands.size(), a3.islands.size()):
		diff += (a.islands[i].center as Vector2).distance_to(a3.islands[i].center)
	check(diff > 500.0, "другое зерно — другая карта (Σ сдвигов %.0f м)" % diff)
	# 2) граф и расстояния
	var cls := a.summary().classes as Dictionary
	check(int(cls.get(&"huge", 0)) == 1 and int(cls.get(&"large", 0)) == 4 and int(cls.get(&"medium", 0)) == 4
		and int(cls.get(&"start", 0)) == 8, "классы островов: %s" % str(cls))
	var mn := 1e9
	for i in a.islands.size():
		for j in range(i + 1, a.islands.size()):
			mn = minf(mn, a.strait_gap(a.islands[i], a.islands[j]))
	check(mn >= 240.0, "между любыми островами ≥240 м воды (мин. %.0f)" % mn)
	var in_range := 0
	for L in a.links:
		if float(L.gap) >= 240.0 and float(L.gap) <= 720.0:
			in_range += 1
	check(in_range >= int(a.links.size() * 0.8), "маршруты 3–6 мин на плоту (250–700 м): %d из %d" % [in_range, a.links.size()])
	check(a.bounds.size.x <= 3100.0 and a.bounds.size.y <= 3100.0, "карта ≈3×3 км: %s" % str(a.bounds.size))
	# стартовые островки одинаковы
	var radii := {}
	var teams := {}
	for I in a.islands:
		if a.class_of(I) == &"start":
			radii[snappedf(float(I.radius), 0.1)] = true
			if int(I.team) >= 0:
				teams[int(I.team)] = true
	check(radii.size() == 1 and teams.size() == 4, "8 одинаковых стартовых островков, у 4 команд свой: радиусы %s, команды %s" % [str(radii.keys()), str(teams.keys())])
	for t in 4:
		var sp := w.spawn_point(t)
		check(w.is_land(sp.x, sp.z) and sp.y > 1.5, "спавн команды %d на суше %s (%s)" % [t, str(sp), w.zone_at(sp.x, sp.z)])
	# 3) памятники
	var types := {}
	for m in w.monuments():
		types[m.type] = true
	for t: StringName in [&"shipwreck", &"spring", &"lagoon", &"lighthouse"]:
		check(types.has(t), "памятник: %s" % t)
	# 4) риф: проходы, гребень всегда под водой в отлив
	check(a.reef_passes.size() >= 4, "проходы в барьерном рифе: %d" % a.reef_passes.size())
	var zm := w.zones
	var reef_cells := 0
	var reef_bad := 0
	for k in zm.zone.size():
		var z := int(zm.zone[k])
		if z == ZoneMap.Z_REEF_CREST or z == ZoneMap.Z_REEF_FLAT or z == ZoneMap.Z_REEF_SLOPE:
			reef_cells += 1
			if zm.h[k] > ZoneMap.LOW_TIDE - 0.2 or zm.sea[k] != 1:
				reef_bad += 1
	check(reef_cells > 3000 and reef_bad == 0, "рифы: %d ячеек, выше отлива/вне моря %d" % [reef_cells, reef_bad])
	# 5) маска моря: открытое море связно, у берега с подветренной стороны тише
	var hist := zm.zone_histogram().zones as Dictionary
	for zn: StringName in [&"beach", &"jungle", &"palm_belt", &"lagoon", &"reef_crest", &"deep_ocean", &"rocks", &"mangrove"]:
		check(int(hist.get(zn, 0)) > 20, "зона %s есть (%d)" % [zn, int(hist.get(zn, 0))])
	var wind := IslandGen.WIND_FROM
	var ww := 0.0
	var lw := 0.0
	var n := 0
	for I in a.islands:
		var c: Vector2 = I.center
		var R := float(I.radius)
		var pw := c + wind * R * 1.35
		var pl := c - wind * R * 1.35
		if zm.is_sea(pw.x, pw.y) and zm.is_sea(pl.x, pl.y):
			ww += zm.exposure(pw.x, pw.y)
			lw += zm.exposure(pl.x, pl.y)
			n += 1
	check(n > 10 and ww > lw * 1.5, "наветренный берег открыт волнам сильнее подветренного: %.2f против %.2f" % [ww / maxf(n, 1), lw / maxf(n, 1)])
	# 6) джунгли: в центре большого острова гуще, чем у края
	var core := 0.0
	var edge := 0.0
	var C: Dictionary = a.islands[0]
	for k in 200:
		var ang := k * TAU / 200.0
		var pc := (C.center as Vector2) + Vector2.from_angle(ang) * float(C.radius) * 0.45
		var pe := (C.center as Vector2) + Vector2.from_angle(ang) * float(C.radius) * 0.85
		core += zm.jungle_density(pc.x, pc.y)
		edge += zm.jungle_density(pe.x, pe.y)
	check(core > edge * 1.3, "джунгли гуще к центру острова: %.2f против %.2f" % [core / 200.0, edge / 200.0])
	# 7) потоковый рельеф: вокруг фокуса — подробные чанки и коллизия = API высот
	var tc := w.terrain
	check(tc.streaming, "рельеф v5 — потоковый")
	var sp := w.spawn_point(0)
	tc.focus_override = [sp] as Array[Vector3]
	await wait(3.0)
	check(tc.live_count() > 10, "вокруг спавна загружены подробные чанки: %d" % tc.live_count())
	var space := w.get_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var maxerr := 0.0
	var samples := 0
	for k in 300:
		var x := sp.x + rng.randf_range(-120.0, 120.0)
		var z := sp.z + rng.randf_range(-120.0, 120.0)
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 80.0, z), Vector3(x, -60.0, z))
		var hit := space.intersect_ray(q)
		if hit.is_empty() or not (hit.collider as Node).is_in_group(&"terrain"):
			continue
		maxerr = maxf(maxerr, absf((hit.position as Vector3).y - w.height_at(x, z)))
		samples += 1
	check(samples > 200 and maxerr < 0.02, "у спавна коллизия = API высот: %d точек, ошибка %.4f" % [samples, maxerr])
	# фокус «прыгнул» на другой остров: старые чанки выгружаются, новые грузятся
	var far := w.spawn_point(2)
	tc.focus_override = [far] as Array[Vector3]
	await wait(3.0)
	var hit2 := space.intersect_ray(PhysicsRayQueryParameters3D.create(far + Vector3(0, 40, 0), far - Vector3(0, 40, 0)))
	check(not hit2.is_empty(), "после прыжка под новым фокусом есть коллизия")
	var hit3 := space.intersect_ray(PhysicsRayQueryParameters3D.create(sp + Vector3(0, 40, 0), sp - Vector3(0, 40, 0)))
	check(hit3.is_empty() or not (hit3.collider as Node).is_in_group(&"terrain"), "у старого фокуса подробный рельеф выгружен")
	print("[test] подробных чанков: %d; рельеф %s" % [tc.live_count(), str(tc.stats)])
	tc.focus_override = [] as Array[Vector3]
