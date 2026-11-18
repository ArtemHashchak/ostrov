extends BuildTestCase
## Флаг: из книги стройки (первый пункт, пока флаг не стоит), только на суше,
## Game.set_flag_placed, расход флага из инвентаря, урон — у Game.

func _init() -> void:
	timeout_sec = 150.0

func run() -> void:
	if not await setup_build():
		return
	var start := Vector3(-5.0, 0.0, 4.0)
	start.y = BuildEnv.height_at(start.x, start.z) + 0.1
	teleport(start)
	p.set_look(0.0, deg_to_rad(-35.0))
	await wait(0.5)
	check(p.inventory.count(&"flag") == 1, "в инвентаре 1 флаг")
	var bm := build_mode()
	await tap(&"build_menu")
	check(bm.entries.size() > 0 and bm.entries[0] == &"flag", "первый пункт — флаг команды")
	await tap(&"hotbar_1")
	await tap(&"attack")
	await wait(0.4)
	check(bm.state == BuildMode.State.PLACING and bm.ghost is TeamFlag, "призрак флага")
	check(bm.valid, "флаг можно ставить: %s" % bm.reason)
	await shot("01_ghost")
	await tap(&"attack")
	await wait_frames(3)
	var f := mod.flag_of(p.team)
	check(f != null, "флаг поставлен")
	check(Game.teams[p.team].flag_placed, "Game.teams[%d].flag_placed" % p.team)
	check(p.inventory.count(&"flag") == 0, "флаг израсходован из инвентаря")
	check(bm.state == BuildMode.State.NONE, "режим стройки закрыт")
	check(get_tree().get_nodes_in_group(&"flag").size() == 1, "флаг в группе flag")
	await tap(&"build_menu")
	check(not bm.entries.has(&"flag"), "второй флаг поставить нельзя")
	await tap(&"build_menu")
	if f == null:
		return
	# Вид.
	var view := f.global_position + Vector3(2.6, 0.0, 3.2)
	view.y = BuildEnv.height_at(view.x, view.z) + 0.1
	teleport(view)
	aim_at(f.global_position + Vector3.UP * 2.2)
	await wait(1.0)
	await shot("02_flag")
	# Урон: свой не бьёт, чужой — бьёт; через Game.
	var hp0 := f.health
	f.apply_damage(30.0, p, &"melee")
	check(is_equal_approx(f.health, hp0), "свой игрок не ранит свой флаг")
	f.apply_damage(30.0, null, &"axe")
	check(f.health < hp0, "флаг получает урон: %.0f → %.0f" % [hp0, f.health])
	check(is_equal_approx(Game.teams[p.team].flag_hp, f.health), "HP флага хранится в Game")
	f.apply_damage(9999.0, null, &"explosion")
	await wait(1.5)
	check(not Game.teams[p.team].flag_alive, "флаг уничтожен")
	check(f.fallen, "флаг упал")
	await shot("03_fallen")
	# Флаг в воде нельзя.
	Game.teams[2].flag_placed = false
	p.team = 2
	var d := 30.0
	while BuildEnv.height_at(d, 0.0) > 0.4 and d < 70.0:
		d += 0.5
	var shore := Vector3(d + 5.0, 0.0, 0.0)
	teleport(Vector3(d - 2.0, BuildEnv.height_at(d - 2.0, 0.0) + 0.1, 0.0))
	await tap(&"build_menu")
	await tap(&"hotbar_1")
	await tap(&"attack")
	aim_at(Vector3(shore.x, BuildEnv.water_level(), shore.z))
	await wait(0.4)
	check(not bm.valid, "в воде флаг не ставится: «%s»" % bm.reason)
	await tap(&"build_menu")
