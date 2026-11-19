extends CombatTestCase
## Быстрая проверка поз от первого лица: перезарядка арбалета, замах копьём и коктейлем.

func _init() -> void:
	timeout_sec = 600.0

func run() -> void:
	if not await setup_combat():
		return
	p.set_look(0.0, deg_to_rad(-5.0))
	await equip(&"crossbow")
	p.inventory.add(&"bolt", 2)
	await tap(&"reload")
	await wait(1.2)
	await shot("01_crossbow_crank")
	await wait(2.6)
	await equip(&"spear")
	Input.action_press(&"aim")
	await wait(0.8)
	await shot("02_spear_raise")
	Input.action_release(&"aim")
	await wait(0.3)
	await equip(&"molotov")
	Input.action_press(&"attack")
	await wait(0.6)
	await shot("03_molotov_windup")
	Input.action_release(&"attack")
	await wait(0.12)
	await shot("04_molotov_throw")
	await wait(0.6)
	await equip(&"pistol")
	Input.action_press(&"aim")
	await wait(0.8)
	await shot("05_pistol_ads")
	Input.action_release(&"aim")
	for id: StringName in [&"musket", &"crossbow"]:
		await equip(id)
		await wait(0.6)
		await shot("06_%s_hip" % id)
		Input.action_press(&"aim")
		await wait(1.0)
		await shot("07_%s_ads" % id)
		_dump(id)
		Input.action_release(&"aim")
		await wait(0.5)
	check(true, "позы сняты")

func _dump(id: StringName) -> void:
	var c := ctrl()
	var h := p.hands
	var cam := get_viewport().get_camera_3d()
	var inv := cam.global_transform.affine_inverse()
	var out := "[poses] %s wid=%s model=%s" % [id, c.wid, str(c._model)]
	if c._model:
		for m: String in ["Sight", "Forend", "Muzzle", "ads_anchor", "forend"]:
			var n := c._model.find_child(m, true, false) as Node3D
			if n:
				out += " %s=%s" % [m, str((inv * n.global_position).snapped(Vector3.ONE * 0.01))]
	out += " L=%s R=%s pose_l=%s hands.pos=%s" % [str((inv * h.left_arm.global_position).snapped(Vector3.ONE * 0.01)),
		str((inv * h.right_arm.global_position).snapped(Vector3.ONE * 0.01)), str(h.pose_l.snapped(Vector3.ONE * 0.01)),
		str((inv * h.global_position).snapped(Vector3.ONE * 0.01))]
	print(out)
