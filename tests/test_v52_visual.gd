## test-timeout: 900
extends TestCase
## v5.2 визуал (агент N): пресет «Высокое» включает SDFGI/объёмный туман; новые растения flora_v5
## получают общий шейдер листвы; следы черепахи/игуаны/варана/кабана; отпечаток тела; кострище;
## дождь стирает следы; капли с листьев/пар/утренний туман/листопад/роса (AfterRainFx); дождь
## гасит открытый костёр; предвестники грозы (StormOmens); NatureDetails: кокосы падают сами,
## скорлупа в разрытой кладке, брошенную еду растаскивают, кости после туши.

class Walker extends Node3D:
	var velocity := Vector3.ZERO
	var species: StringName = &"boar"
	var dead := false
	var growth := 1.0

var w: World
var st: Node

func _init() -> void:
	scene_path = "res://scenes/world/world_view.tscn"

func _beach_spot() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	for I in w.islands():
		var c: Vector2 = I.center
		var R: float = I.radius
		for i in 800:
			var a := rng.randf() * TAU
			var p := c + Vector2(cos(a), sin(a)) * rng.randf_range(0.5, 1.3) * R
			if w.biome_at(p.x, p.y) != &"beach" or w.normal_at(p.x, p.y).y < 0.95:
				continue
			var t := Vector2(-sin(a), cos(a))
			var ok := true
			for k in range(-8, 9):
				var q := p + t * k
				if w.biome_at(q.x, q.y) != &"beach":
					ok = false
					break
			if ok:
				return {"p": p, "t": t}
	return {}

func _count(type: int) -> int:
	var n := 0
	for p: Array in st.prints:
		if int(p[7]) == type:
			n += 1
	return n

func run() -> void:
	# ---- 54: пресеты
	var hi := GraphicsQuality.preset(2)
	check(bool(hi.sdfgi) and bool(hi.vol_fog), "«Высокое»: SDFGI и объёмный туман включены")
	check(int(hi.get("sdfgi_cascades", 4)) < int(GraphicsQuality.preset(3).get("sdfgi_cascades", 4)), "«Высокое» легче «Ультры» (каскады SDFGI)")
	var med := GraphicsQuality.preset(1)
	check(not bool(med.sdfgi) and not bool(med.vol_fog), "«Среднее»: без SDFGI и объёмного тумана")

	# ---- 55: новые растения — шейдер листвы
	var n_conv := 0
	var n_v5 := 0
	for e in AssetCatalog.entries():
		if not FloraV5Mat.is_v5(String(e.get("scene", ""))):
			continue
		n_v5 += 1
		if n_v5 > 12:
			break
		var node := AssetCatalog.instantiate(String(e.id))
		if node == null:
			continue
		var has_sh := false
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			for si in m.mesh.get_surface_count():
				var mat := m.get_surface_override_material(si) as ShaderMaterial
				if mat and mat.shader == FloraV5Mat.SHADER:
					has_sh = true
		if has_sh:
			n_conv += 1
		node.free()
	check(n_v5 > 0 and n_conv == mini(n_v5, 12), "flora_v5: шейдер листвы у всех проверенных (%d/%d)" % [n_conv, mini(n_v5, 12)])
	var pr := FloraV5Mat.params_for({"size_m": [1.2, 1.6, 1.0], "collision": "soft", "category": "plant", "tags": []})
	check(float(pr.flex) > 0.9, "мягкий куст v5 отгибается при касании")
	pr = FloraV5Mat.params_for({"size_m": [5, 9, 5], "collision": "solid", "category": "tree", "tags": []})
	check(float(pr.flex) == 0.0 and float(pr.bend) == 1.0, "дерево v5: без отгибания, гнётся ветром целиком")

	var t0 := Time.get_ticks_msec()
	while w == null and Time.get_ticks_msec() - t0 < 120000:
		await wait(0.5)
		w = get_tree().get_first_node_in_group(&"world") as World
	check(w != null, "мир есть")
	if w == null:
		return
	st = get_node_or_null("/root/SandTracks")
	var spot := _beach_spot()
	check(not spot.is_empty(), "найден пляж")
	if spot.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		cam = Camera3D.new()
		get_tree().current_scene.add_child(cam)
		cam.make_current()
	var p: Vector2 = spot.p
	var dir: Vector2 = spot.t
	var gy := w.height_at(p.x, p.y)
	cam.global_position = Vector3(p.x, gy + 1.7, p.y)
	await wait(1.0)

	# ---- 58: следы зверей (черепаха, игуана, варан, кабан)
	for sp in [&"turtle", &"iguana", &"monitor", &"boar"]:
		st.clear()
		st.walk_line(sp, Vector3(p.x, gy, p.y), Vector3(p.x + dir.x * 3.0, gy, p.y + dir.y * 3.0))
		check(st.prints.size() >= 4, "следы %s: %d отпечатков" % [sp, st.prints.size()])
	# живой зверь (группа animals) оставляет следы сам
	st.clear()
	var a := Walker.new()
	a.species = &"monitor"
	a.add_to_group(&"animals")
	get_tree().current_scene.add_child(a)
	var q := p
	a.global_position = Vector3(q.x, gy, q.y)
	await wait_frames(2)
	for i in 90:
		q += dir * 0.9 / 60.0 * 2.0
		a.global_position = Vector3(q.x, w.height_at(q.x, q.y), q.y)
		await wait_frames(1)
	check(_count(2) >= 4, "варан идёт по песку — когтистые следы (%d)" % _count(2))
	a.queue_free()

	# отпечаток тела
	st.clear()
	st.body_imprint(Vector3(p.x, gy, p.y), dir)
	check(_count(11) == 1, "отпечаток тела на песке")
	# дождь стирает следы: «сила» отпечатка падает быстрее при дожде
	st.clear()
	st.walk_line(&"human", Vector3(p.x, gy, p.y), Vector3(p.x + dir.x * 4.0, gy, p.y + dir.y * 4.0))
	var s0 := float(st.prints[0][6]) if st.prints.size() > 0 else 0.0
	var sky := w.get(&"sky") as SkyWeather
	if sky == null:
		sky = w.find_child("SkyWeather", true, false) as SkyWeather
	check(sky != null, "SkyWeather в мире")
	if sky:
		sky.set_weather(&"rain", true, false)
	await wait(4.0)
	var s1 := float(st.prints[0][6]) if st.prints.size() > 0 else 0.0
	print("[test] свежесть следа: %.3f → %.3f за 4 с дождя" % [s0, s1])
	check(s0 - s1 > 4.0 / 200.0, "дождь стирает следы (−%.3f за 4 с)" % (s0 - s1))

	if sky == null:
		return
	# ---- 56: капли с листьев / пар / туман / листопад / роса
	var ar: AfterRainFx = sky.after_rain
	check(ar != null, "AfterRainFx создан")
	if ar:
		ar.update_fx(0.5, cam, 0.8, 0.8, 0.0, 1.0, 13.0, 0.0, 0.8, Vector2.RIGHT, 2.0, gy, false, false, 1.0)
		check(bool(ar.state.drips), "в дождь под пологом капает с листьев")
		for i in 60:
			ar.update_fx(0.5, cam, 0.0, 0.8, 0.0, 0.0, 13.0, 0.95, 1.0, Vector2.RIGHT, 2.0, gy, false, false, 0.0)
		check(bool(ar.state.steam), "после дождя на солнце от земли идёт пар")
		for i in 80:
			ar.update_fx(0.5, cam, 0.0, 0.6, 0.0, 0.5, 6.5, 0.3, 0.6, Vector2.RIGHT, 1.0, gy, false, false, 1.0)
		check(bool(ar.state.mist), "утром над джунглями стелется туман")
		check(float(ar.state.dew) > 0.3, "утренняя роса (%.2f)" % float(ar.state.dew))
		check(bool(ar.state.leaves), "в лесу в тишину падают листья")

	# ---- 56: дождь гасит открытый костёр, остаётся кострище
	var fire := SvFire.new()
	get_tree().current_scene.add_child(fire)
	fire.global_position = Vector3(p.x + dir.x * 6.0, gy, p.y + dir.y * 6.0)
	await wait_frames(2)
	fire.fuel = 400.0
	fire.lit = true
	fire.set(&"_burned", 60.0)
	sky.set_weather(&"storm", true, false)
	Survival.rain_override = 1.0
	var before := GroundMarks.count()
	for i in 200:
		fire.tick(0.5)
		if not fire.lit:
			break
	check(not fire.lit and fire.put_out_by_rain, "ливень залил костёр")
	check(GroundMarks.count() > before, "после костра осталось кострище")
	Survival.rain_override = -1.0

	# ---- 57: предвестники грозы
	var om: StormOmens = sky.storm_omens
	check(om != null, "StormOmens создан")
	if om:
		var heard := []
		var cb := func(stim: Dictionary) -> void:
			if StringName(stim.kind) == &"storm_coming":
				heard.append(stim)
		Perception.stimulus.connect(cb)
		om.fire(30.0, cam.global_position)
		Perception.stimulus.disconnect(cb)
		check(heard.size() == 1, "storm_coming разослан через Perception")
	sky.set_weather(&"clear", true, false)

	# ---- 60: NatureDetails
	var nd: NatureDetails = sky.nature
	check(nd != null, "NatureDetails создан")
	if nd:
		check(Items.items.has(&"bone"), "предмет «Кости» зарегистрирован")
		var nest := TurtleNest.new()
		get_tree().current_scene.add_child(nest)
		nest.global_position = Vector3(p.x - dir.x * 5.0, gy, p.y - dir.y * 5.0)
		nest.set(&"eggs", 0)
		nd.call(&"_tick_nests", cam.global_position)
		check(nest.find_child("EggShells", true, false) != null, "в разрытой кладке скорлупа")
		var food := ItemPickup.spawn(get_tree().current_scene, Vector3(p.x, gy + 0.3, p.y), [{"id": &"coconut", "n": 1}])
		if food:
			for i in 400:
				nd.call(&"_tick_food", 0.5, cam.global_position)
			await wait_frames(2)
			check(not is_instance_valid(food), "брошенную еду растащили")
