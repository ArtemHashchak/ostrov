extends TestCase
## Дальность обзора и «цилиндр»: виды на горизонт с уровня глаз и с 40 м на полигоне
## в ясную погоду, в дождь и в шторм; серия кадров при ходьбе (нет «выскакивания»).
## Снимки: tests/shots/test_view_distance_*.png

var sb: PolygonIslandStage

func _init() -> void:
	PolygonIslandStage.island_id = "archipelago_match"
	scene_path = "res://scenes/polygon/polygon_island.tscn"
	timeout_sec = 3500.0

func _stats() -> String:
	var rs := RenderingServer
	var dc := rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var pr := rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var ob := rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	return "draw=%d prim=%d obj=%d" % [dc, pr, ob]

func run() -> void:
	Engine.max_physics_steps_per_frame = 30
	sb = scene as PolygonIslandStage
	var t0 := Time.get_ticks_msec()
	while not sb.is_built and Time.get_ticks_msec() - t0 < 1200000:
		await wait(0.5)
	check(sb.is_built, "полигон собран")
	if not sb.is_built:
		return
	var hub: Vector3 = sb.spawn_pos()
	sb.cheats.set_time(10.0)
	for wname: StringName in [&"clear", &"rain", &"storm"]:
		sb.cheats.set_weather(wname)
		await wait(2.0)
		# уровень глаз: в центре, взгляд к морю/горизонту в двух направлениях
		sb.cheats.set_fly(false)
		sb.cheats.teleport(hub)
		await wait(2.0)
		for i in 2:
			var dir := Vector3(-1, 0, -0.3).normalized() if i == 0 else Vector3(0.6, 0, 1).normalized()
			var p := sb.player.global_position
			sb.cheats.teleport(p, p + dir * 100.0)
			await wait(1.5)
			print("[view] %s eye%d %s" % [wname, i, _stats()])
			await shot("%s_eye%d" % [wname, i])
		# с высоты 40 м
		var top := Vector3(hub.x + 40.0, 0.0, hub.z + 40.0)
		top.y = SandboxProps.ground(top.x, top.z) + 40.0
		sb.cheats.set_fly(true)
		sb.cheats.teleport(top, Vector3(hub.x - 200.0, 0.0, hub.z - 200.0))
		await wait(2.0)
		print("[view] %s top %s" % [wname, _stats()])
		await shot("%s_top40" % wname)
	# серия кадров при движении (ясно): проверка «выскакивания»
	sb.cheats.set_weather(&"clear")
	sb.cheats.set_fly(true)
	var a := Vector3(hub.x + 60.0, 0.0, hub.z + 60.0)
	a.y = SandboxProps.ground(a.x, a.z) + 4.0
	var look := Vector3(hub.x - 300.0, 0.0, hub.z - 300.0)
	for k in 6:
		var pos := a.lerp(Vector3(hub.x - 30.0, a.y, hub.z - 30.0), k / 5.0)
		sb.cheats.teleport(pos, look)
		await wait(0.6)
		await shot("walk_%d" % k)
	sb.cheats.set_fly(false)
	check(true, "снимки сняты")
