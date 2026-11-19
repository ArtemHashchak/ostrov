extends TestCase
## Кораллы пака на полигоне: витрины всех видов на песке и коралловый сад под водой
## (точки pack_corals / pack_corals_reef), скриншоты сверху и под водой.

var sb: Sandbox

func _init() -> void:
	scene_path = "res://scenes/sandbox/sandbox.tscn"
	timeout_sec = 3500.0

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
	for id in [&"pack_corals", &"pack_corals_reef"]:
		check(z.points.has(id), "есть точка перемещения: %s" % id)
	var row := get_tree().root.find_children("Coral_*", "MeshInstance3D", true, false).size()
	check(row == 22, "витрин кораллов: %d" % row)
	var garden := get_tree().root.find_child("CoralGarden", true, false)
	check(garden != null and garden.get_child_count() >= 12, "коралловый сад: %d групп" % (garden.get_child_count() if garden else 0))
	sb.panel.go(&"pack_corals")
	await wait(3.0)
	await shot("01_row")
	sb.cheats.set_fly(true)
	sb.panel.go(&"pack_corals_reef")
	await wait(3.0)
	await shot("02_reef_a")
	if garden:
		var p: Vector3 = sb.zones.points[&"pack_corals_reef"].look
		sb.cheats.teleport(p + Vector3(3.0, 1.2, 3.0), p + Vector3(0, 0.3, 0))
		await wait(2.0)
		await shot("03_reef_close")
		sb.cheats.teleport(p + Vector3(-2.0, 0.6, 2.5), p + Vector3(0.5, 0.4, 0))
		await wait(2.0)
		await shot("04_reef_low")
	sb.cheats.set_fly(false)
