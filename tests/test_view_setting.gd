extends TestCase
## Настройка «Дальность видимости» (ViewDistance): три значения (600 м, 1800 м, «Максимум»),
## применение на лету, дальности рельефа/деревьев/предметов и туман по границе.
## Снимки с уровня глаз и с 40 м: tests/shots/test_view_setting_*.png

var sb: Sandbox

func _init() -> void:
	scene_path = "res://scenes/sandbox/sandbox.tscn"
	timeout_sec = 3500.0

func _stats() -> String:
	var rs := RenderingServer
	var dc := rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var pr := rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var ob := rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	return "draw=%d prim=%d obj=%d" % [dc, pr, ob]

func _env() -> Environment:
	var w := sb.get_viewport().find_world_3d()
	return w.environment if w else null

func _max_end(group: StringName) -> float:
	var m := 0.0
	for n in sb.get_tree().get_nodes_in_group(group):
		var gi := n as GeometryInstance3D
		if gi and gi.visible:
			m = maxf(m, gi.visibility_range_end)
	return m

func run() -> void:
	Engine.max_physics_steps_per_frame = 30
	sb = scene as Sandbox
	var t0 := Time.get_ticks_msec()
	while not sb.is_built and Time.get_ticks_msec() - t0 < 1200000:
		await wait(0.5)
	check(sb.is_built, "полигон собран")
	if not sb.is_built:
		return
	var saved_vd := Settings.view_distance
	var saved_fl := Settings.flora_distance
	# авто по пресету
	Settings.view_distance = 0.0
	Settings.apply_view()
	check(is_equal_approx(ViewDistance.meters(), ViewDistance.PRESET_DEFAULT[Settings.graphics_quality]), "авто = значение пресета")
	var z := sb.zones
	var hub: Vector3 = z.points[&"hub"].pos
	sb.cheats.set_time(10.0)
	sb.cheats.set_weather(&"clear")
	await wait(2.0)
	var cases := [[600.0, "600"], [1800.0, "1800"], [4000.0, "max"]]
	for c in cases:
		Settings.view_distance = float(c[0])
		Settings.apply_view()
		await wait(1.5)
		var vd := ViewDistance.meters()
		var env := _env()
		var tend := _max_end(ViewDistance.G_TERRAIN)
		print("[vd] %s: meters=%d terrain_end=%d lod2_end=%d imp_end=%d fog=%s autolod_max=%d" % [
			c[1], int(vd), int(tend), int(_max_end(ViewDistance.G_TREE_LOD2)), int(_max_end(ViewDistance.G_TREE_IMP)),
			ViewDistance.describe(env), int(_max_end(AutoLOD.GROUP))])
		check(tend <= vd + 0.5, "%s: рельеф не дальше дальности (%d ≤ %d)" % [c[1], int(tend), int(vd)])
		check(_max_end(AutoLOD.GROUP) <= vd + 0.5, "%s: предметы не дальше дальности" % c[1])
		if env and not ViewDistance.is_max():
			check(env.fog_mode == Environment.FOG_MODE_DEPTH and env.fog_depth_end <= vd + 0.5,
				"%s: туман густеет к границе (%s)" % [c[1], ViewDistance.describe(env)])
		elif env:
			check(env.fog_mode == Environment.FOG_MODE_EXPONENTIAL, "max: только погодный туман")
		# уровень глаз — на море/горизонт
		sb.cheats.set_fly(false)
		sb.panel.go(&"hub")
		await wait(2.0)
		var p := sb.player.global_position
		sb.cheats.teleport(p, p + Vector3(-1, 0, -0.3).normalized() * 100.0)
		await wait(2.0)
		print("[vd] %s eye %s" % [c[1], _stats()])
		await shot("%s_eye" % c[1])
		# с 40 м
		var top := Vector3(hub.x + 40.0, 0.0, hub.z + 40.0)
		top.y = SandboxProps.ground(top.x, top.z) + 40.0
		sb.cheats.set_fly(true)
		sb.cheats.teleport(top, Vector3(hub.x - 200.0, 0.0, hub.z - 200.0))
		await wait(2.0)
		print("[vd] %s top40 %s" % [c[1], _stats()])
		await shot("%s_top40" % c[1])
	# дальность растений: множитель доходит до флоры
	Settings.flora_distance = 0.5
	Settings.apply_view()
	var k_lo := GraphicsQuality.detail()
	Settings.flora_distance = 2.0
	Settings.apply_view()
	var k_hi := GraphicsQuality.detail()
	check(k_hi > k_lo * 3.5, "дальность растений меняет detail (%.2f → %.2f)" % [k_lo, k_hi])
	# под водой туман экспоненциальный и после всплытия возвращается
	Settings.view_distance = saved_vd
	Settings.flora_distance = saved_fl
	Settings.apply_view()
	sb.cheats.set_fly(false)
	check(true, "снимки сняты")
