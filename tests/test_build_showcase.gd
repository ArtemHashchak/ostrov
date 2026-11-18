extends BuildTestCase
## Витрина всех чертежей (готовые + один полузаполненный) — для скриншотов вида.

func _init() -> void:
	timeout_sec = 200.0

func run() -> void:
	if not await setup_build():
		return
	var base := Vector3(-10.0, 0.0, -8.0)
	var yaw := 0.0
	var made: Array[Blueprint] = []
	var at := func(dx: float, dz: float, r: float = 0.0) -> Transform3D:
		var x := base.x + dx
		var z := base.z + dz
		return Transform3D(Basis(Vector3.UP, yaw + r), Vector3(x, BuildEnv.height_at(x, z), z))
	# платформа + стены на ней + крыша + лестница
	var plat := mod.place_blueprint(&"platform", at.call(0.0, 0.0), 0)
	made.append(plat)
	var s := mod.find_socket(&"wall", plat.base_xform * Vector3(0, BuildDefs.DECK_H, -1.5), 1.0)
	check(not s.is_empty(), "на платформе есть сокет стены")
	if not s.is_empty():
		made.append(mod.place_blueprint(&"wall_window", s.xform, 0))
	var st := mod.find_socket(&"stairs", plat.base_xform * Vector3(0, 0, 3.0), 3.0)
	check(not st.is_empty(), "у платформы есть сокет лестницы")
	if not st.is_empty():
		made.append(mod.place_blueprint(&"stairs", st.xform, 0, {}, st.ctx))
	made.append(mod.place_blueprint(&"shelter", at.call(6.0, 1.0, 0.5), 0))
	made.append(mod.place_blueprint(&"fire_pit", at.call(6.5, 4.5), 0))
	var half := mod.place_blueprint(&"wall", at.call(-5.0, 1.5, 0.3), 0)
	for b in made:
		for t: StringName in [&"log", &"stick", &"rope", &"stone"]:
			b.add_material(t, 99)
		check(b.is_complete(), "%s готов(а)" % BuildDefs.name_of(b.def_id))
	half.add_material(&"log", 3)
	await wait(0.5)
	var view := base + Vector3(2.0, 0.0, 10.0)
	view.y = BuildEnv.height_at(view.x, view.z) + 0.1
	teleport(view)
	aim_at(base + Vector3(1.0, 1.0, 0.0))
	await wait(0.8)
	await shot("01_all")
	view = base + Vector3(8.0, 0.0, 9.0)
	view.y = BuildEnv.height_at(view.x, view.z) + 0.1
	teleport(view)
	aim_at(base + Vector3(6.0, 0.6, 2.5))
	await wait(0.8)
	await shot("02_shelter")
	# по лестнице на платформу
	if made.size() > 2 and made[2].def_id == &"stairs":
		var stairs := made[2]
		var run := BuildDefs.stairs_dims(stairs.ctx).y
		var foot := stairs.base_xform * Vector3(0, 0, run * 0.5 + 0.9)
		foot.y = BuildEnv.height_at(foot.x, foot.z) + 0.15
		teleport(foot)
		aim_at(plat.base_xform.origin + Vector3.UP * 1.6)
		await wait(0.3)
		await press(&"move_forward", 2.4)
		p.set_look(p._yaw, 0.0)
		check(p.global_position.y > plat.base_xform.origin.y + BuildDefs.DECK_H - 0.3, "поднялся по лестнице на платформу (y=%.2f, настил %.2f)" % [p.global_position.y, plat.base_xform.origin.y + BuildDefs.DECK_H])
		await shot("03_on_platform")
