## test-timeout: 2400
extends TestCase
## test-class: render
## Сцены моря в настоящей среде: полигон, коралловый сад и склон (кораллы, трава, каустика,
## подводный туман, настоящий уровень моря). Каждая сцена ставится режиссёром рядом с садом
## (по своей глубине), камера — в 3–8 м от действия, 3 кадра на сцену:
## tests/shots/test_sea_scenes_real_<id>_a/b/c.png. SEA_SCENES_ONLY=id1,id2 — только эти.

var sb: Sandbox

func _init() -> void:
	scene_path = "res://scenes/sandbox/sandbox.tscn"
	timeout_sec = 5400.0

func _photo(on: bool) -> void:
	var pl := sb.player
	if pl:
		if pl.hands:
			pl.hands.visible = not on
		for c in pl.get_children():
			if c is CanvasLayer:
				(c as CanvasLayer).visible = not on
	for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
		if n.name in ["SeaScenesUI"] or n.get_class() == "CanvasLayer":
			(n as CanvasLayer).visible = not on
	for l in get_tree().root.find_children("*", "Label3D", true, false):
		(l as Label3D).visible = not on

## Центр действия: средняя точка существ, стай и крабов сцены.
func _focus(s: SeaScene) -> Vector3:
	var acc := Vector3.ZERO
	var n := 0
	for c in s.critters:
		if is_instance_valid(c):
			acc += c.global_position
			n += 1
	for sc in s.schools:
		if is_instance_valid(sc):
			acc += sc.center
			n += 1
	for a in s.crabs + s.sharks:
		if is_instance_valid(a):
			acc += (a as Node3D).global_position
			n += 1
	return acc / n if n > 0 else s.at + Vector3(0, 0.6, 0)

func _frame(s: SeaScene, view: String, k: int) -> void:
	var f := _focus(s)
	var wy := s.water_y()
	var small := s.id in ["crab_chase", "crab_rivals", "hermit_swap", "lobster_march", "seahorse_grass", "star_barrens", "clownfish_anemone", "cleaner_station", "octopus_den", "octopus_hunt", "moray_ambush", "parrotfish_crunch"]
	var dist := 3.5 if small else 6.0
	var ang0 := 0.7 + k * 0.5
	var p := f
	var fl := 0.0
	# точка камеры, где воды хотя бы 0.9 м (не на границе воды): перебираем направления
	# ищем точку поглубже (≥1.6 м воды), отходя дальше, если рядом мелко
	var found := false
	for r in [dist, dist * 1.6, dist * 2.4]:
		for i in 12:
			var ang := ang0 + i * 0.52
			p = f + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
			fl = s.floor_y(p.x, p.z)
			if wy - fl >= 1.6:
				found = true
				break
		if found:
			break
	if s.id == "sargassum_raft":
		# снизу вверх на плот: золотистый силуэт, свисающие плети, мальки под ним
		p = Vector3(s.at.x + 2.0 + k, wy - 2.2, s.at.z + 1.5)
		p.y = maxf(p.y, s.floor_y(p.x, p.z) + 0.4)
		f = Vector3(s.at.x, wy - 0.4, s.at.z)
	elif s.id == "kelp_forest":
		# из-под полога келпа: снизу против света
		# с края леса (не внутри ленты), снизу вверх против света
		p = s.at + Vector3(cos(ang0) * 5.0, 0.0, sin(ang0) * 5.0)
		fl = s.floor_y(p.x, p.z)
		p.y = clampf(fl + 0.6, fl + 0.4, wy - 0.8)
		f = s.at + Vector3(0.0, minf(3.0, (wy - s.at.y) * 0.7), 0.0)
	elif view == "surface" or s.id in ["whale_breach", "gulls_steal", "dolphins_bait", "bait_ball"]:
		p.y = wy + 1.4
		if s.id == "whale_breach":
			p = f + Vector3(cos(ang0) * 60.0, 0.0, sin(ang0) * 60.0)
			p.y = wy + 3.0
	else:
		p.y = clampf(f.y + (0.3 if small else 0.6), fl + 0.3, wy - 0.45)
	# реальная поверхность у камеры (волна + прилив) — подводный кадр не должен вылезать из воды
	if view != "surface" and not (s.id in ["whale_breach", "gulls_steal", "dolphins_bait", "bait_ball"]):
		var surf := wy
		if sb.world and sb.world.has_method("wave_height"):
			surf = minf(wy, float(sb.world.wave_height(p.x, p.z)))
		p.y = minf(p.y, surf - 0.8)
		p.y = maxf(p.y, s.floor_y(p.x, p.z) + 0.3)
	sb.cheats.teleport(p, f)

func run() -> void:
	Engine.max_physics_steps_per_frame = 30
	sb = scene as Sandbox
	var t0 := Time.get_ticks_msec()
	while not sb.is_built and Time.get_ticks_msec() - t0 < 1200000:
		await wait(0.5)
	check(sb.is_built, "полигон собран")
	if not sb.is_built:
		return
	var d := SeaSceneDirector.instance()
	check(d != null, "режиссёр сцен на полигоне")
	if d == null:
		return
	d.auto = false
	d.stop_all()
	var w := sb.world
	var garden := get_tree().root.find_child("CoralGarden", true, false) as Node3D
	var gc := Vector3.ZERO
	if sb.zones.points.has(&"pack_corals_reef"):
		gc = sb.zones.points[&"pack_corals_reef"].look
	check(garden != null, "коралловый сад есть")
	sb.cheats.set_fly(true)
	_photo(true)
	var only := OS.get_environment("SEA_SCENES_ONLY")
	var done := 0
	for id: String in SeaScenesLib.ids():
		if only != "" and not (id in only.split(",")):
			continue
		var info: Dictionary = SeaScenesLib.CATALOG[id]
		var tm := String(info.get("time", "any"))
		w.set_time_of_day({"night": 22.5, "dusk": 18.6}.get(tm, 10.5))
		w.set_weather(&"storm" if String(info.get("weather", "any")) == "storm" else &"clear", true)
		await wait(0.3)
		var pos: Variant = d.find_spot_around(info, gc, 260.0)
		if pos == null:
			check(false, "%s: нет места по глубине %s" % [id, str(info.get("depth"))])
			continue
		var s := d.play(id, pos as Vector3)
		check(s != null, "%s: сцена поставлена" % id)
		if s == null:
			continue
		var view := String(info.get("view", "underwater"))
		for k in 3:
			await wait(2.5 if k == 0 else 3.5)
			if not is_instance_valid(s):
				break
			_frame(s, view, k)
			await wait(0.4)
			await shot("%s_%s" % [id, "abc"[k]])
		d.stop_all()
		done += 1
		await wait(0.3)
	_photo(false)
	sb.cheats.set_fly(false)
	check(done > 0, "отснято сцен: %d" % done)
