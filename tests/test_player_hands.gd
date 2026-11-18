extends CombatTestCase
## Руки от первого лица: скриншоты в разных состояниях (для доводки вида) и
## проверки API: сигналы удара/использования, перехват предмета, хват пальцев.

func _init() -> void:
	timeout_sec = 900.0

func _hands() -> FPHands:
	return p.hands

func run() -> void:
	if not await setup_combat():
		return
	var h := _hands()
	p.global_position = Vector3(-42.0, float(scene.call(&"height_at", -42.0, -12.0)) + 0.2, -12.0)
	p.set_look(deg_to_rad(70.0), deg_to_rad(-8.0))
	var inv := p.inventory
	inv.clear()
	await wait(0.6)
	await shot("01_empty")
	check(h.held_id == &"", "пустые руки")
	var sk := h.right_arm.get_node_or_null(^"Skeleton") as Skeleton3D
	check(sk != null and sk.get_bone_count() == 17, "скелет кисти: 17 костей")
	await equip(&"axe_crude")
	await wait(0.4)
	await shot("02_axe")
	check(h.held_id == &"axe_crude", "в руке топор")
	check(h.held_root.visible and h.held_root.get_child_count() == 1, "модель топора видна")
	# хват: средний палец согнут сильно
	var mid := sk.find_bone("middle2")
	var ang := (sk.get_bone_rest(mid).basis.get_rotation_quaternion().inverse() * sk.get_bone_pose_rotation(mid)).get_angle()
	check(ang > deg_to_rad(50.0), "пальцы обхватывают рукоять (%.0f°)" % rad_to_deg(ang))
	var impacts := [0]
	var fin := [0]
	h.swing_impact.connect(func() -> void: impacts[0] += 1)
	h.swing_finished.connect(func() -> void: fin[0] += 1)
	p.swing()
	await wait(0.2)
	await shot("03_axe_windup")
	await wait(0.1)
	await shot("04_axe_strike")
	await wait(0.6)
	check(impacts[0] == 1 and fin[0] == 1, "сигналы swing_impact/swing_finished")
	await equip(&"axe_modern")
	await wait(0.3)
	await shot("05_axe_modern")
	await equip(&"spear")
	await wait(0.3)
	await shot("06_spear")
	p.swing()
	await wait(0.22)
	await shot("07_spear_thrust")
	await wait(0.5)
	inv.select(8)
	await wait(0.6)
	p.swing()
	await wait(0.17)
	await shot("08_punch")
	await wait(0.5)
	await equip(&"coconut")
	await wait(0.3)
	await shot("09_coconut")
	# перехват: посреди смены предмета рука опущена
	inv.add(&"stick", 1)
	await equip(&"water_bottle")
	await wait(0.3)
	await shot("10_bottle")
	var used := [0]
	h.use_finished.connect(func() -> void: used[0] += 1)
	h.play_use()
	await wait(0.45)
	await shot("11_drink")
	await wait(0.7)
	check(used[0] == 1, "сигнал use_finished")
	inv.select(8)
	await wait(0.5)
	h.set_carry(true)
	await wait(0.6)
	await shot("12_log")
	h.set_carry(false)
	await wait(0.4)
	# оружие COMBAT
	p.inventory.add(&"arrow", 5)
	await equip(&"bow")
	await wait(0.4)
	Input.action_press(&"attack")
	await wait(0.9)
	await shot("13_bow_draw")
	Input.action_release(&"attack")
	await wait(0.6)
	await equip(&"pistol")
	await wait(0.4)
	await shot("14_pistol")
	await equip(&"musket")
	await wait(0.4)
	await shot("15_musket")
	Input.action_press(&"aim")
	await wait(0.8)
	await shot("16_musket_ads")
	Input.action_release(&"aim")
	await wait(0.4)
	await equip(&"crossbow")
	await wait(0.4)
	await shot("17_crossbow")
	# широкий FOV
	var fov0 := Settings.fov
	Settings.fov = 90.0
	await equip(&"axe_crude")
	await wait(0.8)
	await shot("18_axe_fov90")
	Settings.fov = fov0
	# инерция: резкий поворот — руки отстают
	var x0 := h.position
	p.set_look(deg_to_rad(110.0), deg_to_rad(-8.0))
	await wait_frames(2)
	check(h.position.distance_to(x0) > 0.001 or h.rotation.length() > 0.001, "руки отстают от поворота камеры")
	await wait(0.8)
	check(h.position.length() < 0.02, "инерция затухает")
