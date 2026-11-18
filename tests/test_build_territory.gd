extends BuildTestCase
## Территория флага: радиус 40 м. Чужим внутри строить нельзя (API и призрак),
## свои строят быстрее (каждое 2-е бревно — даром). Рамка территории видна
## в режиме стройки.

func _init() -> void:
	timeout_sec = 240.0

func run() -> void:
	if not await setup_build():
		return
	var fpos := ground(4.0, 4.0)
	var flag := mod.place_flag(0, fpos)
	check(flag != null, "флаг команды 0 поставлен")
	await wait_frames(2)
	check(mod.territory_of(fpos + Vector3(10, 0, 0)) == 0, "в 10 м от флага — территория команды 0")
	check(mod.territory_of(fpos + Vector3(39, 0, 0)) == 0, "в 39 м — ещё своя")
	check(mod.territory_of(fpos + Vector3(45, 0, 0)) == -1, "в 45 м — ничья")
	check(mod.territories().size() == 1, "территорий: %d" % mod.territories().size())
	# чужая команда не может поставить чертёж внутри
	var xf := Transform3D(Basis(), ground(12.0, 4.0))
	check(mod.check_ground(&"wall", xf, 1) != "", "check_ground: чужим внутри нельзя («%s»)" % mod.check_ground(&"wall", xf, 1))
	check(mod.check_ground(&"wall", xf, 0) == "", "check_ground: своим можно")
	var bad := mod.place_blueprint(&"wall", xf, 1)
	check(bad == null, "place_blueprint чужой команды внутри территории → null")
	var far := ground(-30.0, -20.0)
	check(mod.territory_of(far) == -1, "далеко — ничья территория")
	var ok_enemy := mod.place_blueprint(&"wall", Transform3D(Basis(), far), 1)
	check(ok_enemy != null, "вне территории чужой строит свободно")

	# призрак: игрок команды 1 внутри — красный с причиной
	var bm := build_mode()
	p.team = 1
	teleport(ground(10.0, 1.0) + Vector3.UP * 0.1)
	p.set_look(-PI * 0.5, deg_to_rad(-32.0))
	await wait(0.3)
	bm.start_place(&"palisade")
	await wait(0.4)
	check(not bm.valid and bm.reason.find("Чужая") >= 0, "призрак чужого — нельзя: «%s»" % bm.reason)
	check(bm._rings.size() == 1, "в режиме стройки видна рамка территории")
	await shot("01_enemy_ghost")
	bm.close()
	check(bm._rings.is_empty(), "рамка убирается при выходе из режима")
	p.team = 0
	bm.start_place(&"palisade")
	await wait(0.4)
	check(bm.valid, "своему можно: %s" % bm.reason)
	var view := fpos + Vector3(-6.0, 0.0, 30.0)
	teleport(ground(view.x, view.z) + Vector3.UP * 0.1)
	p.set_look(0.0, deg_to_rad(-6.0))
	aim_at(fpos + Vector3(0.0, 1.0, 0.0))
	await wait(0.5)
	await shot("02_territory_ring")
	bm.close()

	# свои строят быстрее: стене нужно 7 брёвен, у флага хватает 4 принесённых
	var own := mod.place_blueprint(&"wall", Transform3D(Basis(), ground(9.0, 8.0)), 0)
	var c := own.base_xform.origin
	var n := own.base_xform.basis.z.normalized()
	teleport(Vector3(c.x + n.x * 2.2, BuildEnv.height_at(c.x + n.x * 2.2, c.z + n.z * 2.2) + 0.1, c.z + n.z * 2.2))
	await wait(0.3)
	var carried := 0
	var tries := 0
	while own.filled_count(&"log") < own.total_count(&"log") and tries < 10:
		tries += 1
		if await carry_log_into(own, c + Vector3.UP * (0.3 + 0.3 * carried)):
			carried += 1
		elif p.carrying_log:
			p.set_carrying_log(false)
	check(own.filled_count(&"log") == 7, "стена у флага получила все 7 брёвен")
	check(carried <= 4, "на своей территории хватило %d брёвен вместо 7" % carried)
	# снаружи бонуса нет
	var out := mod.place_blueprint(&"wall", Transform3D(Basis(), ground(-30.0, -26.0)), 0)
	var oc := out.base_xform.origin
	teleport(Vector3(oc.x + 2.2 * out.base_xform.basis.z.x, BuildEnv.height_at(oc.x, oc.z + 2.2) + 0.1, oc.z + 2.2 * out.base_xform.basis.z.z))
	await wait(0.3)
	for i in 3:
		await carry_log_into(out, oc + Vector3.UP * (0.3 + 0.3 * i))
	check(out.filled_count(&"log") == 3, "вне территории — бревно за бревно (%d из 3)" % out.filled_count(&"log"))
	# флаг упал — территории нет
	Game.damage_flag(0, 99999.0, null)
	await wait(0.3)
	check(mod.territory_of(fpos) == -1, "у сломанного флага территории нет")
