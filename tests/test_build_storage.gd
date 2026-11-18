extends BuildTestCase
## Хранилища и верстак: сундук (12 ячеек, окно, свои/чужие, при разрушении
## вещи высыпаются), поленница (10 брёвен: положить/взять на плечо, при
## разрушении брёвна раскатываются), верстак (станция для рецептов).

func _init() -> void:
	timeout_sec = 300.0

func run() -> void:
	if not await setup_build():
		return
	var base := ground(8.0, -6.0)
	# --- сундук ---
	var chest := mod.place_blueprint(&"chest", Transform3D(Basis(Vector3.UP, 0.3), base), 0) as BuildChest
	check(chest != null, "сундук поставлен (класс BuildChest)")
	if chest == null:
		return
	check(chest.storage.size() == 12, "в сундуке 12 ячеек")
	finish(chest)
	check(chest.is_complete(), "сундук достроен: %s" % BuildDefs.cost_text(&"chest"))
	p.inventory.add(&"stick", 15)
	p.inventory.add(&"rope", 3)
	p.inventory.add(&"stone", 7)
	var stand := base + chest.global_basis.z.normalized() * -1.6
	teleport(Vector3(stand.x, BuildEnv.height_at(stand.x, stand.z) + 0.1, stand.z))
	aim_at(chest.global_position + Vector3.UP * 0.4)
	await wait(0.4)
	await tap(&"interact")
	await wait(0.3)
	var panel := p.get_node_or_null(^"ChestPanel") as BuildChestPanel
	check(panel != null, "E открывает окно сундука")
	if panel == null:
		return
	check(bool(p.ui_open), "окно сундука освобождает мышь (ui_open)")
	await wait(0.7)
	check(chest.leaf_open, "крышка сундука откинута")
	# перенос: палки целиком, камни — половину
	var si := -1
	var ri := -1
	for i in p.inventory.slots.size():
		var s: Dictionary = p.inventory.slots[i]
		if not s.is_empty() and s.id == &"stick":
			si = i
		if not s.is_empty() and s.id == &"stone":
			ri = i
	panel.transfer(false, si, false)
	panel.transfer(false, ri, true)
	check(chest.storage.count(&"stick") == 15 and p.inventory.count(&"stick") == 0, "палки переложены в сундук")
	check(chest.storage.count(&"stone") == 3 and p.inventory.count(&"stone") == 4, "ПКМ — половина стека камней (3 из 7)")
	await wait(0.3)
	await shot("01_chest_ui")
	panel.transfer(true, 0, false)
	check(p.inventory.count(&"stick") == 15 and chest.storage.count(&"stick") == 0, "палки забраны обратно")
	await tap(&"interact")
	await wait(0.3)
	check(not is_instance_valid(panel) or panel.is_queued_for_deletion(), "E закрывает окно")
	check(not bool(p.ui_open), "мышь снова у игрока")
	await wait(0.8)
	check(not chest.leaf_open, "крышка закрылась")
	check(chest.storage.add(&"log", 1) == 1, "бревно в сундук не кладётся (носится на плече)")
	var enemy := spawn_walker(base + Vector3(2.0, 0.2, 2.0), 1)
	check(not chest.can_open(enemy), "чужой не может открыть сундук")
	chest.storage.add(&"rope", 5)
	var before_pickups := get_tree().get_nodes_in_group(&"pickups").size()
	var stored := chest.storage.total()
	check(stored >= 15, "в сундуке %d предметов" % stored)
	chest.apply_damage(9999.0, enemy, &"explosion")
	await wait(0.4)
	var pk := get_tree().get_nodes_in_group(&"pickups")
	check(pk.size() > before_pickups, "сломанный сундук высыпал вещи (мешок)")
	var spilled := 0
	for n in pk:
		var ip := n as ItemPickup
		if ip:
			for s: Dictionary in ip.stacks:
				spilled += int(s.n)
	check(spilled >= stored, "в мешке все вещи сундука (%d/%d)" % [spilled, stored])

	# --- поленница ---
	var lh := mod.place_blueprint(&"log_holder", Transform3D(Basis(Vector3.UP, -0.2), ground(2.0, -10.0)), 0) as BuildLogHolder
	finish(lh)
	check(lh != null and lh.is_complete(), "поленница достроена: %s" % BuildDefs.cost_text(&"log_holder"))
	var lstand := lh.global_position + Vector3(0.0, 0.0, 1.9)
	teleport(Vector3(lstand.x, BuildEnv.height_at(lstand.x, lstand.z) + 0.1, lstand.z))
	for i in 3:
		give_log()
		aim_at(lh.global_position + Vector3.UP * 0.5)
		await wait_frames(3)
		await tap(&"interact")
		await wait_frames(2)
	check(lh.logs == 3 and not p.carrying_log, "игрок положил 3 бревна (%d)" % lh.logs)
	aim_at(lh.global_position + Vector3.UP * 0.5)
	await wait_frames(3)
	await tap(&"interact")
	await wait_frames(3)
	check(p.carrying_log and lh.logs == 2, "E — взять бревно на плечо")
	# взятое бревно годится для стройки
	var wall := mod.place_blueprint(&"wall", Transform3D(Basis(), ground(-3.0, -12.0)), 0)
	var wn := wall.base_xform.origin + Vector3(0, 0, 2.2)
	teleport(Vector3(wn.x, BuildEnv.height_at(wn.x, wn.z) + 0.1, wn.z))
	aim_at(wall.base_xform.origin + Vector3.UP * 0.4)
	await wait_frames(3)
	await tap(&"interact")
	await wait_frames(2)
	check(wall.filled_count(&"log") == 1 and not p.carrying_log, "бревно из поленницы уложено в стену")
	check(lh.add_logs(20) == 8 and lh.logs == 10, "поленница вмещает 10 брёвен")
	var view := lh.global_position + Vector3(2.5, 0.0, 3.0)
	teleport(Vector3(view.x, BuildEnv.height_at(view.x, view.z) + 0.1, view.z))
	aim_at(lh.global_position + Vector3.UP * 0.6)
	await wait(0.5)
	await shot("02_log_holder")
	var logs_before := get_tree().get_nodes_in_group(&"log").size()
	lh.destroy(enemy)
	await wait(0.5)
	check(get_tree().get_nodes_in_group(&"log").size() >= logs_before + 10, "сломанная поленница: 10 брёвен раскатились")

	# --- верстак ---
	var wb := mod.place_blueprint(&"workbench", Transform3D(Basis(Vector3.UP, 0.5), ground(12.0, -12.0)), 0)
	check(not wb.is_in_group(&"workbench"), "недостроенный верстак — не станция")
	finish(wb)
	check(wb.is_complete() and wb.is_in_group(&"workbench"), "верстак достроен и стал станцией: %s" % BuildDefs.cost_text(&"workbench"))
	if not Items.recipes.has(&"r_test_bench"):
		Items.register_recipe(&"r_test_bench", &"rope", {&"stick": 1}, 1, &"workbench")
	var r = Items.recipes[&"r_test_bench"]
	teleport(ground(30.0, 30.0) + Vector3.UP * 0.1)
	await wait_frames(2)
	check(PlayerItems.craft_block_reason(p, r) != "", "вдали от верстака рецепт недоступен")
	var bstand := wb.global_position + wb.global_basis.z.normalized() * 1.4
	teleport(Vector3(bstand.x, BuildEnv.height_at(bstand.x, bstand.z) + 0.1, bstand.z))
	await wait_frames(2)
	check(PlayerItems.craft_block_reason(p, r) == "", "у верстака рецепт доступен: «%s»" % PlayerItems.craft_block_reason(p, r))
	aim_at(wb.global_position + Vector3.UP * 0.7)
	await wait(0.4)
	await shot("03_workbench")
	wb.apply_damage(60.0, enemy, &"axe")
	check(not wb.is_in_group(&"workbench"), "сломанный верстак перестаёт быть станцией")
	finish(wb)
	check(wb.is_in_group(&"workbench"), "отремонтированный верстак снова станция")
