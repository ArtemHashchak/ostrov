## test-timeout: 600
extends CombatTestCase
## АК («Автомат», WeaponDef rifle): подвижные детали по контракту имён (BoltCarrier с
## рукояткой взведения, Trigger, Selector, Magazine). Проверяем: затворная рама откатывается
## назад на выстреле и возвращается (~60–80 мс), спуск тянется при зажатой атаке, переводчик
## на 3 положения (авто → одиночный → предохранитель → авто), на предохранителе выстрела нет,
## магазин «качается» и уходит при перезарядке, после пустого магазина затвор НЕ стоит на
## задержке (у АК её нет) и при полной перезарядке взводится; общий множитель отдачи.
## Снимки (не в быстром режиме): покой, середина выстрела, предохранитель, магазин снят.

func _init() -> void:
	timeout_sec = 600.0

func model() -> Node3D:
	return ctrl()._model

func part(nm: String) -> Node3D:
	return model().find_child(nm, true, false) as Node3D if model() else null

func run() -> void:
	if not await setup_combat():
		return
	SupplyItems.register()
	Engine.max_physics_steps_per_frame = 16
	var rd := WeaponDef.of(&"rifle")
	check(rd != null and rd.fire_modes == [&"auto", &"semi", &"safe"], "режимы АК: авто, одиночный, предохранитель")
	check(absf(Gunplay.RECOIL_MULT - 1.12) < 0.001 and rd.recoil_mult > 1.05, "отдача: общий ×1.12, у АК ещё ×%.2f" % rd.recoil_mult)
	check(not rd.bolt_hold_open and rd.charge_on_empty and rd.muzzle_brake, "АК: без затворной задержки, взвод после пустого, дульный тормоз")
	await equip(&"rifle")
	p.inventory.add(&"rifle_ammo", 90)
	check(model() != null, "модель автомата в руке")
	for nm in ["BoltCarrier", "Trigger", "Selector", "Magazine"]:
		check(part(nm) != null, "деталь «%s» в модели" % nm)
	if part("BoltCarrier") == null:
		return
	ctrl()._start_reload()
	await wait(rd.reload_full + 0.4)
	check(Combat.rounds(p, &"rifle") >= rd.mag_size, "заряжен: %d" % Combat.rounds(p, &"rifle"))
	var bolt := part("BoltCarrier")
	var z0 := bolt.position.z
	await shot("ak_idle")

	# ---- одиночный: рама назад и обратно, спуск ----
	await tap(&"fire_mode")
	check(Combat.fire_mode(p, &"rifle") == &"semi", "V → одиночный")
	var trig := part("Trigger")
	var tr0 := trig.basis
	var r0 := Combat.rounds(p, &"rifle")
	Input.action_press(&"attack")
	var max_back := 0.0
	var trig_moved := false
	var shot_taken := false
	for i in 12:
		await wait_frames(1)
		max_back = maxf(max_back, bolt.position.z - z0)
		if not trig.basis.is_equal_approx(tr0):
			trig_moved = true
		if not shot_taken and bolt.position.z - z0 > rd.bolt_travel * 0.5:
			shot_taken = true
			await shot("ak_mid_shot")
	Input.action_release(&"attack")
	await wait(0.3)
	check(Combat.rounds(p, &"rifle") == r0 - 1, "одиночный: ушёл один патрон (%d → %d)" % [r0, Combat.rounds(p, &"rifle")])
	check(max_back > rd.bolt_travel * 0.5, "затворная рама откатилась на %.3f м (ход %.3f)" % [max_back, rd.bolt_travel])
	check(absf(bolt.position.z - z0) < 0.002, "рама вернулась вперёд")
	check(trig_moved, "спусковой крючок тянется при нажатии")
	check(trig.basis.is_equal_approx(tr0), "спуск вернулся")

	# ---- предохранитель ----
	var sel := part("Selector")
	var s_semi := sel.basis
	await tap(&"fire_mode")
	await wait(0.2)
	check(Combat.fire_mode(p, &"rifle") == &"safe", "V → предохранитель")
	check(not sel.basis.is_equal_approx(s_semi), "переводчик повернулся")
	var r1 := Combat.rounds(p, &"rifle")
	await press(&"attack", 0.3)
	await wait(0.1)
	check(Combat.rounds(p, &"rifle") == r1, "на предохранителе выстрела нет")
	check(not Combat.fire(p, &"rifle", p.global_position + Vector3.UP, Vector3.FORWARD), "Combat.fire на предохранителе — false")
	await shot("ak_safe")
	await tap(&"fire_mode")
	await wait(0.2)
	check(Combat.fire_mode(p, &"rifle") == &"auto", "V → снова автоматический")

	# ---- до пустого: нет затворной задержки ----
	Input.action_press(&"attack")
	var tt := 0.0
	while Combat.rounds(p, &"rifle") > 0 and tt < 6.0:
		await wait(0.1)
		tt += 0.1
	Input.action_release(&"attack")
	await wait(0.3)
	check(Combat.rounds(p, &"rifle") == 0, "магазин расстрелян очередью")
	check(absf(bolt.position.z - z0) < 0.002, "пустой АК: рама впереди (затворной задержки нет)")

	# ---- полная перезарядка: магазин качнулся и ушёл, затвор взведён ----
	var mag := part("Magazine")
	var m0 := mag.transform
	ctrl()._start_reload()
	var mag_moved := false
	var charged := 0.0
	var shot_mag := false
	var nf := 0
	while Combat.is_reloading(p) and nf < 900:
		await wait_frames(1)
		nf += 1
		if mag.transform.origin.distance_to(m0.origin) > 0.05:
			mag_moved = true
			if not shot_mag:
				shot_mag = true
				await shot("ak_mag_out")
		charged = maxf(charged, bolt.position.z - z0)
	await wait(0.2)
	check(mag_moved, "магазин вынимается при перезарядке")
	check(mag.transform.origin.distance_to(m0.origin) < 0.003 and mag.visible, "новый магазин на месте")
	check(charged > rd.bolt_travel * 0.5, "после пустого — затвор взведён (%.3f м)" % charged)
	check(Combat.rounds(p, &"rifle") == rd.mag_size, "перезаряжен: %d" % Combat.rounds(p, &"rifle"))
