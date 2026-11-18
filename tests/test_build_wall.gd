extends BuildTestCase
## Стена из брёвен: меню (B) → чертёж → призрак на земле → ЛКМ → игрок носит
## брёвна и жмёт E → стена «прорастает» → готова и не пускает игрока.

func _init() -> void:
	timeout_sec = 240.0

func run() -> void:
	if not await setup_build():
		return
	var start := Vector3(6.0, 0.0, 6.0)
	start.y = BuildEnv.height_at(start.x, start.z) + 0.1
	teleport(start)
	p.set_look(-PI * 0.5, deg_to_rad(-32.0))   # смотрим на +X, в землю
	await wait(0.5)
	var bm := build_mode()
	await tap(&"build_menu")
	check(bm.state == BuildMode.State.MENU, "B открывает список чертежей")
	var wall_idx := bm.entries.find(&"wall")
	check(wall_idx >= 0, "в списке есть стена (%d пунктов)" % bm.entries.size())
	await tap(StringName("hotbar_%d" % (wall_idx + 1)))
	await shot("01_menu")
	await tap(&"attack")
	check(bm.state == BuildMode.State.PLACING and bm.ghost != null, "выбран чертёж — призрак на земле")
	await wait(0.4)
	check(bm.valid, "призрак можно поставить: %s" % bm.reason)
	await shot("02_ghost")
	await tap(&"attack")
	await wait_frames(3)
	var list := mod.blueprints()
	check(list.size() == 1, "чертёж поставлен (%d)" % list.size())
	await tap(&"build_menu")   # закрыть режим
	check(bm.state == BuildMode.State.NONE and bm.ghost == null, "B закрывает режим стройки")
	if list.is_empty():
		return
	var bp := list[0]
	check(bp.def_id == &"wall" and not bp.is_complete(), "это незаполненная стена")
	var need_logs := bp.total_count(&"log")
	check(need_logs == 7, "стене нужно 7 брёвен")

	# Подойти к стене: 2.2 м перед её лицом (со стороны игрока).
	var c := bp.base_xform.origin
	var n := bp.base_xform.basis.z.normalized()
	if n.dot(p.global_position - c) < 0.0:
		n = -n
	var stand := c + n * 2.2
	stand.y = BuildEnv.height_at(stand.x, stand.z) + 0.1
	teleport(stand)
	await wait(0.3)
	var ok := 0
	for i in need_logs:
		if await carry_log_into(bp, c + Vector3.UP * (0.3 + 0.32 * i)):
			ok += 1
		if i == 3:
			await shot("03_half")
	check(ok == need_logs, "игрок уложил брёвна: %d/%d" % [ok, need_logs])
	check(bp.filled_count(&"log") == need_logs, "все брёвна на месте")
	check(not bp.is_complete(), "без палок стена ещё не готова")
	p.inventory.add(&"stick", 4)
	aim_at(c + Vector3.UP * 1.2)
	await wait_frames(3)
	for i in 4:
		await tap(&"interact")
		await wait_frames(2)
	check(bp.is_complete(), "стена достроена палками-скрепами")
	check(p.inventory.count(&"stick") == 0, "палки израсходованы из инвентаря")
	await wait(0.5)
	await shot("04_done")

	# Стена держит игрока.
	var before := n.dot(p.global_position - c)
	aim_at(c + Vector3.UP * 1.5)
	await press(&"move_forward", 2.0)
	var after := n.dot(p.global_position - c)
	check(after > 0.15, "стена не пускает: был в %.2f м, стал %.2f м" % [before, after])

	# Вид со стороны.
	var side := c + n * 5.5 + bp.base_xform.basis.x.normalized() * 3.0
	side.y = BuildEnv.height_at(side.x, side.z) + 0.1
	teleport(side)
	aim_at(c + Vector3.UP * 1.1)
	await wait(0.5)
	await shot("05_side")

	# Дом: ещё стена по сокету, окно, проём, крыша (заполняем add_material — для вида).
	var w2 := mod.place_blueprint(&"wall_window", bp.base_xform * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(1.5, 0, -1.5)), 0)
	var w3 := mod.place_blueprint(&"wall_door", bp.base_xform * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -3.0)), 0)
	var s := mod.find_socket(&"roof", c + Vector3.UP * BuildDefs.WALL_H)
	check(not s.is_empty(), "у стены есть сокет крыши")
	var roof: Blueprint = null
	if not s.is_empty():
		roof = mod.place_blueprint(&"roof", s.xform, 0)
	for b: Blueprint in [w2, w3, roof]:
		if b == null:
			continue
		for t: StringName in [&"log", &"stick", &"rope", &"stone"]:
			b.add_material(t, 99)
		check(b.is_complete(), "%s достроена" % BuildDefs.name_of(b.def_id))
	var ds := mod.find_socket(&"door", w3.global_position)
	check(not ds.is_empty(), "у проёма есть сокет двери")
	if not ds.is_empty():
		var door := mod.place_blueprint(&"door", ds.xform, 0)
		for t: StringName in [&"log", &"stick", &"rope"]:
			door.add_material(t, 99)
		check(door.is_complete(), "дверь готова")
		door.toggle_door()
		await wait(0.5)
		check(door.door_open, "дверь открывается")
	var view := c + n * 7.0 + bp.base_xform.basis.x.normalized() * 5.0
	view.y = BuildEnv.height_at(view.x, view.z) + 1.5
	teleport(view)
	aim_at(c + Vector3.UP * 1.2 - n * 1.5)
	await wait(0.6)
	await shot("06_hut")
