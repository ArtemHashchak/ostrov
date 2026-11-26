## test-timeout: 600
## test-class: render
extends CombatTestCase
## Снимки АК сбоку (справа) крупно: покой, рама сзади + спуск нажат, предохранитель/авто/
## одиночный, магазин качнут/снят. Для проверки осей деталей модели пользователя.

func _init() -> void:
	timeout_sec = 600.0

func run() -> void:
	if not await setup_combat():
		return
	SupplyItems.register()
	await equip(&"rifle")
	p.inventory.add(&"rifle_ammo", 60)
	var c := ctrl()
	var m: Node3D = c._model
	check(m != null, "модель в руке")
	if m == null:
		return
	var cam := Camera3D.new()
	cam.fov = 30.0
	m.add_child(cam)
	cam.position = Vector3(0.75, 0.05, -0.15)
	cam.look_at(m.global_transform * Vector3(0, 0.0, -0.15), m.global_basis.y)
	cam.make_current()
	c.set_process(false)
	await wait(0.5)
	c._update_parts()
	await shot("right_idle")
	var d0 := WeaponDef.of(&"rifle")
	var bolt := m.find_child(d0.bolt_node, true, false) as Node3D
	var trg := m.find_child(d0.trigger_node, true, false) as Node3D
	var b0: Transform3D = c._rest_xf(bolt)
	var t0: Transform3D = c._rest_xf(trg)
	bolt.position = b0.origin + Vector3(0, 0, d0.bolt_travel)
	trg.basis = t0.basis * Basis(Vector3.RIGHT, deg_to_rad(d0.trigger_pull_deg))
	await shot("right_bolt_back_trigger")
	bolt.transform = b0
	trg.transform = t0
	for mode in [&"safe", &"semi"]:
		Combat.state(p)["modes"] = {&"rifle": mode}
		var sl := m.find_child(WeaponDef.of(&"rifle").selector_node, true, false) as Node3D
		sl.basis = c._rest_xf(sl).basis * Basis(Vector3.RIGHT, deg_to_rad(float(WeaponDef.of(&"rifle").selector_deg[mode])))
		await shot("right_selector_" + String(mode))
	var sl2 := m.find_child(WeaponDef.of(&"rifle").selector_node, true, false) as Node3D
	sl2.basis = c._rest_xf(sl2).basis * Basis(Vector3.RIGHT, deg_to_rad(5.5))
	await shot("right_selector_auto")
	# магазин: качнуть и снять (вручную задаём прогресс перезарядки)
	var d := WeaponDef.of(&"rifle")
	var mg := m.find_child(d.mag_node, true, false) as Node3D
	var r0: Transform3D = c._rest_xf(mg)
	mg.transform = Transform3D(r0.basis * Basis(Vector3.RIGHT, deg_to_rad(d.mag_rock_deg)), r0.origin)
	await shot("right_mag_rocked")
	mg.transform = Transform3D(r0.basis * Basis(Vector3.RIGHT, deg_to_rad(d.mag_rock_deg)), r0.origin + d.mag_drop * 0.5)
	await shot("right_mag_half_out")
	mg.transform = r0
