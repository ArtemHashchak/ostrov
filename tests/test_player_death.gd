extends TestCase
## Здоровье, смерть, мешок с вещами, возрождение у флага, выбывание без флага,
## голод/жажда, еда.

func _init() -> void:
	timeout_sec = 400.0

func run() -> void:
	await wait(1.0)
	var p := get_tree().get_first_node_in_group(&"player") as Player
	check(p != null, "игрок есть")
	if p == null:
		return
	var inv := p.inventory
	inv.clear()
	inv.add(&"axe_crude", 1)
	inv.add(&"stick", 8)
	inv.add(&"coconut_peeled", 2)
	inv.add(&"flag", 1)

	# Еда.
	p.hunger = 50.0
	var ci := -1
	for i in Inventory.SIZE:
		if inv.get_slot(i).get("id") == &"coconut_peeled":
			ci = i
	inv.select(ci)
	await wait(0.3)
	p.use_selected()
	await until(func() -> bool: return p.hunger > 50.0, 8.0)
	check(p.hunger > 50.0 and inv.count(&"coconut_peeled") == 1, "съел кокос: сытость %.0f" % p.hunger)

	# Голод/жажда убывают.
	var h0 := p.hunger
	var th0 := p.thirst
	await until(func() -> bool: return p.hunger < h0 and p.thirst < th0, 10.0)
	check(p.hunger < h0 and p.thirst < th0, "голод и жажда убывают")
	# На нуле — урон.
	p.thirst = 0.0
	var hp := p.health
	await until(func() -> bool: return p.health < hp, 10.0)
	check(p.health < hp, "жажда на нуле — теряет здоровье")
	p.thirst = 100.0

	# Флаг команды.
	var flag_pos := Vector3(8.0, float(scene.call(&"height_at", 8.0, 8.0)), 8.0)
	Game.set_flag_placed(p.team, flag_pos)
	var spawned := [false]
	var died := [false]
	Events.character_spawned.connect(func(c: Node) -> void: if c == p: spawned[0] = true)
	Events.character_died.connect(func(c: Node, _k: Node) -> void: if c == p: died[0] = true)

	# Урон через on-hit контракт (apply_damage).
	p.global_position = Vector3(-6.0, float(scene.call(&"height_at", -6.0, -6.0)) + 0.3, -6.0)
	await wait(0.5)
	p.apply_damage(40.0, null, &"melee")
	check(is_equal_approx(p.health, p.max_health - 40.0) or p.health < p.max_health - 39.0, "урон 40: здоровье %.0f" % p.health)
	check(not p.is_dead(), "жив")
	var picks0 := get_tree().get_nodes_in_group(&"pickups").size()
	p.apply_damage(500.0, null, &"bite")
	check(p.is_dead() and died[0], "погиб, Events.character_died")
	await wait(0.3)
	check(get_tree().get_nodes_in_group(&"pickups").size() == picks0 + 1, "выпал мешок с вещами")
	check(inv.count(&"stick") == 0 and inv.count(&"axe_crude") == 1 and inv.count(&"flag") == 1, "ресурсы выпали, инструмент и флаг остались")
	await wait(1.2)
	await shot("01_dead")
	check((p.hud as HUD)._death.visible, "экран гибели")
	var t := 0.0
	while not spawned[0] and t < 30.0:
		await wait(0.5)
		t += 0.5
	check(spawned[0] and p.alive, "возродился через ~%.1f с" % (t + 1.5))
	check(p.global_position.distance_to(flag_pos) < 4.0, "возрождение у флага (%.1f м)" % p.global_position.distance_to(flag_pos))
	check(is_equal_approx(p.health, p.max_health), "здоровье восстановлено")
	await wait(0.5)
	await shot("02_respawned")

	# Подобрать мешок.
	var bag := get_tree().get_nodes_in_group(&"pickups").back() as ItemPickup
	if bag:
		bag.interact(p)
		await wait(0.2)
		check(inv.count(&"stick") == 8, "подобрал мешок: палок %d" % inv.count(&"stick"))

	# Флаг уничтожен → выбыл.
	Game.damage_flag(p.team, Game.FLAG_MAX_HP + 1.0)
	check(not Game.can_respawn(p.team), "флаг уничтожен")
	spawned[0] = false
	p.apply_damage(500.0, null, &"melee")
	await until(func() -> bool: return p.eliminated, 10.0)
	await wait(Game.RESPAWN_TIME + 1.5)
	check(p.eliminated and not p.alive and not spawned[0], "без флага — выбыл, не возрождается")
	await shot("03_eliminated")

func until(cond: Callable, max_sec: float) -> void:
	var t := 0.0
	while not bool(cond.call()) and t < max_sec:
		await wait(0.1)
		t += 0.1
