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
	check(true, "позы сняты")
