extends TestCase
## Инвентарь, хотбар, крафт и панели UI: API Inventory, стеки, тяжёлые предметы,
## выбор ячейки цифрой, наведение+цифра, перетаскивание (move), крафт через
## панель, пауза/настройки, HUD. Скриншоты HUD/инвентаря/крафта/паузы.

func _init() -> void:
	timeout_sec = 400.0

func run() -> void:
	await wait(1.0)
	var p := get_tree().get_first_node_in_group(&"player") as Player
	check(p != null and p.inventory != null, "у игрока есть Inventory")
	if p == null:
		return
	var inv := p.inventory
	check(p.get_node_or_null(^"Inventory") == inv, "Inventory — дочерний узел 'Inventory'")
	check(inv.count(&"flag") == 1, "стартовый флаг в инвентаре")
	check(p.hud != null and p.hud is HUD, "HUD создан")
	inv.clear()

	# --- API ---
	var changed := [0]
	inv.changed.connect(func() -> void: changed[0] += 1)
	check(inv.add(&"stick", 5) == 0, "add палка ×5")
	check(inv.count(&"stick") == 5, "count палка = 5")
	var st := Inventory.stack_of(&"stick")
	var rest := inv.add(&"rock", 1000)
	check(rest > 0 and inv.count(&"rock") == 1000 - rest, "переполнение: вернул остаток %d" % rest)
	inv.remove(&"rock", inv.count(&"rock"))
	check(inv.count(&"rock") == 0, "remove всех камней")
	check(inv.has({&"stick": 5}) and not inv.has({&"stick": 6}), "has() учитывает количество")
	check(not inv.remove(&"stick", 99) and inv.count(&"stick") == 5, "remove больше, чем есть — false, ничего не трогает")
	check(changed[0] >= 3, "сигнал changed (%d)" % changed[0])
	check(st >= 10, "стек палок %d" % st)
	if Items.get_item(&"log"):
		check(inv.add(&"log", 1) == 1, "бревно в инвентарь не кладётся (тяжёлое)")

	# --- хотбар ---
	inv.clear()
	inv.add(&"axe_modern", 1)
	inv.add(&"spear", 1)
	inv.add(&"rock", 3)
	check(inv.get_slot(0).get("id") == &"axe_modern" and inv.get_slot(1).get("id") == &"spear", "инструменты ложатся в хотбар")
	await tap(&"hotbar_2")
	check(inv.selected == 1 and p.held_item() == &"spear", "цифра 2 — копьё в руке")
	await tap(&"hotbar_1")
	check(p.held_item() == &"axe_modern", "цифра 1 — топор в руке")
	await wait(0.4)
	await shot("01_hud_axe")

	# --- панель инвентаря ---
	inv.add(&"stick", 12)
	inv.add(&"fiber", 7)
	inv.add(&"coconut", 2)
	inv.add(&"cloth", 2)
	inv.add(&"meat_raw", 1)
	await tap(&"inventory")
	await wait(0.6)
	var hud := p.hud as HUD
	check(hud.inventory_panel.visible and p.ui_open, "I — открылся рюкзак, игрок в режиме UI")
	await wait(1.0) # иконки рендерятся
	await shot("02_inventory")

	# Перетаскивание (то, что делает drop) — move между ячейками.
	var from := -1
	for i in range(Inventory.HOTBAR, Inventory.SIZE):
		if inv.get_slot(i).get("id") == &"stick":
			from = i
	check(from >= Inventory.HOTBAR, "палки в рюкзаке (ячейка %d)" % from)
	inv.move(from, Inventory.HOTBAR + 20)
	check(inv.get_slot(Inventory.HOTBAR + 20).get("id") == &"stick" and inv.get_slot(from).is_empty(), "перетаскивание в пустую ячейку")
	# Объединение стеков.
	inv.set_slot(Inventory.HOTBAR + 21, {"id": &"stick", "n": 3})
	inv.move(Inventory.HOTBAR + 21, Inventory.HOTBAR + 20)
	check(int(inv.get_slot(Inventory.HOTBAR + 20).n) == 15, "стеки объединились: %d" % int(inv.get_slot(Inventory.HOTBAR + 20).n))

	# Наведение + цифра → в хотбар.
	hud.inventory_panel.hovered_index = Inventory.HOTBAR + 20
	await tap(&"hotbar_5")
	check(inv.get_slot(4).get("id") == &"stick", "наведение + 5 — палки в 5-й ячейке хотбара")
	check(inv.selected == 0, "цифра в открытом рюкзаке не меняет выбранное")
	hud.inventory_panel.hovered_index = -1

	# Выбросить за край панели.
	var pick_before := get_tree().get_nodes_in_group(&"pickups").size()
	hud.inventory_panel._drop_data(Vector2.ZERO, {"inv_slot": 4})
	await wait(0.3)
	check(inv.get_slot(4).is_empty() and get_tree().get_nodes_in_group(&"pickups").size() == pick_before + 1, "перетащил за панель — выбросил мешком/предметом")

	await tap(&"pause")
	check(not hud.inventory_panel.visible and not p.ui_open and not get_tree().paused, "Esc закрывает рюкзак, а не ставит паузу")

	# --- крафт ---
	inv.clear()
	inv.add(&"fiber", 6)
	inv.add(&"stick", 3)
	inv.add(&"rock", 1)
	await tap(&"craft")
	await wait(0.6)
	var cp := hud.craft_panel
	check(cp.visible, "B — открылся крафт")
	cp.select_recipe(&"r_rope")
	check(cp.craft_selected() and inv.count(&"rope") >= 1 and inv.count(&"fiber") == 3, "сделал верёвку из волокна")
	cp.select_recipe(&"r_axe_crude")
	await wait(1.0)
	await shot("03_craft")
	check(cp.craft_selected() and inv.count(&"axe_crude") == 1, "сделал каменный топор")
	check(inv.count(&"rope") == 0 and inv.count(&"rock") == 0, "ресурсы списаны")
	cp.select_recipe(&"r_spear")
	check(not cp.craft_selected(), "копьё без верёвки не делается")
	check(PlayerItems.craft_block_reason(p, Items.recipes[&"r_spear"]) != "", "причина блокировки есть")
	# Рецепт у станции.
	Items.register_recipe(&"r_test_station", &"bandage", {&"stick": 1}, 1, &"test_bench")
	check(PlayerItems.craft_block_reason(p, Items.recipes[&"r_test_station"]).contains("станц"), "без станции — нельзя")
	var bench := Node3D.new()
	bench.add_to_group(&"test_bench")
	scene.add_child(bench)
	bench.global_position = p.global_position + Vector3(1, 0, 0)
	check(PlayerItems.craft_block_reason(p, Items.recipes[&"r_test_station"]) == "", "у станции — можно")
	Items.recipes.erase(&"r_test_station")
	bench.queue_free()
	await tap(&"craft")
	check(not cp.visible and not p.ui_open, "B закрывает крафт")

	# Топор в руке после крафта.
	var ax := -1
	for i in Inventory.SIZE:
		if inv.get_slot(i).get("id") == &"axe_crude":
			ax = i
	inv.select(ax)
	await wait(0.5)
	check(p.held_item() == &"axe_crude", "каменный топор в руке")
	p.set_look(0.4, deg_to_rad(-10.0))
	await wait(0.4)
	await shot("04_hud_crude_axe")

	# --- тосты/подсказка ---
	Events.toast.emit("Тестовое сообщение")
	await wait(0.2)
	check(hud._toasts.get_child_count() >= 1, "тост показан")

	# --- пауза и настройки ---
	await tap(&"pause")
	await wait(0.3)
	check(get_tree().paused and hud.pause_menu.visible, "Esc — меню паузы")
	await shot("05_pause")
	hud.pause_menu.show_settings()
	await wait(0.3)
	await shot("06_settings")
	var old_fov := Settings.fov
	Settings.fov = 90.0
	await tap(&"pause")
	check(get_tree().paused and hud.pause_menu.visible and not hud.pause_menu.settings.visible, "Esc в настройках — назад в паузу")
	Settings.fov = old_fov
	Settings.save_settings()
	hud.pause_menu.resume()
	await wait(0.2)
	check(not get_tree().paused and not hud.pause_menu.visible, "«Продолжить» снимает паузу")
	# Переназначение клавиши.
	Settings.rebind_key(&"drop", KEY_Q)
	check(UITheme.key_name(&"drop") == "Q", "переназначение: выбросить на Q")
	Settings.rebind_key(&"drop", KEY_G)

	# Урон — красная виньетка.
	p.apply_damage(30.0, null, &"melee")
	await wait(0.1)
	await shot("07_hud_damage")
	check(hud._flash.modulate.a > 0.2, "вспышка урона")
