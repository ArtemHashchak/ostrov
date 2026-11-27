## test-timeout: 2400
extends TestCase
## test-class: render
## Снимки v5.2 (агент N) «до/после» одним прогоном — эффект выключен / включён:
## оспинки на песке и листья в лужах (дождь), отражение костра на воде ночью, золотая вода на
## закате, утренний туман над джунглями, роса, кострище и отпечаток тела, скорлупа в кладке.
## Каждый кадр — отдельный файл /mnt/user-data/outputs/v52_N_<имя>.png. N_ONLY — фильтр.

func _init() -> void:
	OS.set_environment("OSTROVA_GEN", "5")
	scene_path = "res://scenes/world/world_view.tscn"
	timeout_sec = 2350.0

var cam: Camera3D
var w: World

func run() -> void:
	await wait(2.0)
	w = get_tree().get_first_node_in_group(&"world") as World
	if w == null or not w.is_ready:
		check(false, "мир готов")
		return
	var fl := Flora.new()
	w.get_parent().add_child(fl)
	if not fl.populated:
		await fl.flora_ready
	w.set_weather(&"clear", true)
	if w.has_method(&"set_time_paused"):
		w.set_time_paused(true)
	cam = Camera3D.new()
	cam.far = 8000.0
	cam.fov = 70.0
	w.add_child(cam)
	cam.current = true
	for pl in get_tree().get_nodes_in_group(&"player"):
		(pl as Node).process_mode = Node.PROCESS_MODE_DISABLED
		(pl as Node3D).global_position = Vector3(0, -500, 0)
	var a := w.arch as ArchipelagoV5
	var zm := w.zones
	var only := OS.get_environment("N_ONLY")
	var wl := w.water_level()
	var st: Dictionary = a.islands[0]
	for I in a.islands:
		if a.class_of(I) == &"start":
			st = I
			break
	var sc: Vector2 = st.center
	var bp := _find_zone_near(sc, float(st.radius) * 1.2, ZoneMap.Z_BEACH)
	var to_sea := (bp - sc).normalized()
	var by := w.height_at(bp.x, bp.y)
	var sky: SkyWeather = w.sky

	# 1) дождь на пляже: оспинки от капель (выкл/вкл)
	if only == "" or only.contains("pits"):
		w.set_time_of_day(13.0)
		w.set_weather(&"rain", true)
		# сухой песок выше прибоя: отступаем вглубь пляжа, смотрим вниз-вдоль берега
		var dp := bp
		for s2 in 30:
			var q := bp - to_sea * (s2 * 0.5)
			if w.height_at(q.x, q.y) > wl + 1.2 and zm.zone_at(q.x, q.y) == ZoneMap.Z_BEACH:
				dp = q
				break
		var dy := w.height_at(dp.x, dp.y)
		var side2 := Vector2(-to_sea.y, to_sea.x)
		var e := Vector3(dp.x - side2.x * 1.0, dy + 1.0, dp.y - side2.y * 1.0)
		var l := Vector3(dp.x + side2.x * 1.4, dy, dp.y + side2.y * 1.4)
		RenderingServer.global_shader_parameter_set(&"weather_rain", 0.0)
		RenderingServer.global_shader_parameter_set(&"weather_wetness", 0.0)
		await _view(e, l, "rain_pits_before", 1.5, func() -> void:
			RenderingServer.global_shader_parameter_set(&"weather_rain", 0.0)
			RenderingServer.global_shader_parameter_set(&"weather_wetness", 0.0))
		await _view(e, l, "rain_pits_after", 1.5, func() -> void:
			RenderingServer.global_shader_parameter_set(&"weather_rain", 0.9)
			RenderingServer.global_shader_parameter_set(&"weather_wetness", 0.9))
		w.set_weather(&"clear", true)
	# 2) кострище и отпечаток тела на песке
	if only == "" or only.contains("pit"):
		w.set_time_of_day(14.0)
		# сухой песок выше наката (иначе волна стирает отпечаток за секунды)
		var fp := bp - to_sea * 4.0
		for s3 in 40:
			var q3 := bp - to_sea * (s3 * 0.5)
			if w.height_at(q3.x, q3.y) > wl + 1.4 and zm.zone_at(q3.x, q3.y) == ZoneMap.Z_BEACH:
				fp = q3
				break
		var fy := w.height_at(fp.x, fp.y)
		GroundMarks.fire_pit(w, Vector3(fp.x, fy, fp.y), 0.75)
		var stt := get_node_or_null("/root/SandTracks")
		if stt:
			var bpos := Vector3(fp.x + 1.8, w.height_at(fp.x + 1.8, fp.y), fp.y)
			stt.body_imprint(bpos, to_sea)
			print("[test] отпечаток тела: штампов %d, песок=%s" % [stt.prints.size(), str(stt.call(&"_is_sand", Vector2(bpos.x, bpos.z)))])
		await _view(Vector3(fp.x - 2.0, fy + 2.3, fp.y - 2.0), Vector3(fp.x + 0.8, fy, fp.y), "firepit", 2.0)
		var bx := fp.x + 1.8
		var byy := w.height_at(bx, fp.y)
		await _view(Vector3(bx - to_sea.x * 1.6 + 0.3, byy + 1.9, fp.y - to_sea.y * 1.6 + 0.3), Vector3(bx, byy, fp.y), "body_imprint", 2.0)
	# 3) отражение костра на воде ночью (выкл/вкл)
	if only == "" or only.contains("fire"):
		w.set_time_of_day(22.5)
		var fp2 := bp
		for s in 40:
			var q := bp + to_sea * (s * 0.4)
			if w.height_at(q.x, q.y) < wl + 0.25:
				break
			fp2 = q
		var f := SvFire.new()
		w.add_child(f)
		f.global_position = Vector3(fp2.x, w.height_at(fp2.x, fp2.y), fp2.y)
		await wait_frames(2)
		f.fuel = 500.0
		f.lit = true
		f.call(&"_apply_lit")
		var side := Vector2(-to_sea.y, to_sea.x)
		var e2 := Vector3(fp2.x + to_sea.x * 14.0 + side.x * 2.0, wl + 1.6, fp2.y + to_sea.y * 14.0 + side.y * 2.0)
		var l2 := Vector3(fp2.x, wl + 0.4, fp2.y)
		await _view(e2, l2, "fire_reflection_before", 3.0, func() -> void:
			RenderingServer.global_shader_parameter_set(&"fire_glow", Vector4(0, -1000, 0, 0)))
		await _view(e2, l2, "fire_reflection_after", 3.0, func() -> void:
			RenderingServer.global_shader_parameter_set(&"fire_glow", Vector4(fp2.x, w.height_at(fp2.x, fp2.y) + 0.5, fp2.y, 1.0)))
		f.queue_free()
	# 4) золотая вода на закате (выкл/вкл: sun_day занижаем вне окна)
	if only == "" or only.contains("golden"):
		w.set_time_of_day(17.25)
		var e3 := Vector3(bp.x, by + 6.0, bp.y)
		var l3 := Vector3(bp.x + to_sea.x * 200.0, wl, bp.y + to_sea.y * 200.0)
		await _view(e3, l3, "golden_water_before", 3.0, func() -> void:
			RenderingServer.global_shader_parameter_set(&"sun_day", 0.6))
		await _view(e3, l3, "golden_water_after", 3.0, func() -> void:
			RenderingServer.global_shader_parameter_set(&"sun_day", 0.12))
	# 5) утренний туман над джунглями (выкл/вкл)
	if only == "" or only.contains("mist"):
		w.set_time_of_day(6.4)
		var C: Dictionary = a.islands[0]
		var cc: Vector2 = C.center
		var jp := cc
		for k in 72:
			var p := cc + Vector2.from_angle(k * 0.0873) * float(C.radius) * 0.55
			if zm.zone_at(p.x, p.y) == ZoneMap.Z_JUNGLE:
				jp = p
				break
		var jy := w.height_at(jp.x, jp.y)
		var e4 := Vector3(jp.x, jy + 9.0, jp.y)
		var l4 := Vector3(jp.x + 30.0, jy + 1.0, jp.y + 10.0)
		var ar: AfterRainFx = sky.after_rain if sky else null
		await _view(e4, l4, "morning_mist_before", 2.0, func() -> void:
			if ar:
				ar.mist.emitting = false
				ar.mist_k = 0.0)
		if ar:
			for i in 40:
				ar.update_fx(0.5, cam, 0.0, 0.7, 0.0, 0.6, 6.4, 0.3, 0.6, Vector2.RIGHT, 1.0, jy, false, false, 1.0)
			ar.mist.global_position = Vector3(jp.x + 18.0, jy + 2.2, jp.y + 6.0)
		await _view(e4, l4, "morning_mist_after", 9.0, func() -> void: pass)
	# 6) скорлупа в разрытой кладке
	if only == "" or only.contains("shell"):
		w.set_time_of_day(11.0)
		var np := bp - to_sea * 2.0
		var ny := w.height_at(np.x, np.y)
		var nest := TurtleNest.new()
		w.add_child(nest)
		nest.global_position = Vector3(np.x, ny, np.y)
		await wait_frames(2)
		nest.eggs = 0
		nest.call(&"_refresh")
		if sky and sky.nature:
			sky.nature.call(&"_tick_nests", nest.global_position)
		await _view(Vector3(np.x - 0.9, ny + 0.9, np.y - 0.9), Vector3(np.x, ny, np.y), "egg_shells", 2.0)

func _find_zone_near(c: Vector2, r: float, z: int) -> Vector2:
	for k in 96:
		var p := c + Vector2.from_angle(k * TAU / 96.0) * r
		for s in 30:
			var q := c + (p - c) * (1.0 - s * 0.03)
			if w.zones.zone_at(q.x, q.y) == z:
				return q
	return c + Vector2(r * 0.8, 0)

## Камера, выдержка, затем `pre` (выставить uniform после того, как погода их перезаписала) и снимок.
func _view(pos: Vector3, look: Vector3, nm: String, settle: float, pre: Callable = Callable()) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	w.terrain.focus_override = [pos] as Array[Vector3]
	await wait(settle)
	if pre.is_valid():
		pre.call()
	# SkyWeather каждый кадр выставляет глобальные uniform заново — снимок сразу после pre
	await RenderingServer.frame_pre_draw
	if pre.is_valid():
		pre.call()
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img and not img.is_empty():
		var out := "/mnt/user-data/outputs/v52_N_%s.png" % nm
		img.save_png(out)
		print("[test] shot ", out)
