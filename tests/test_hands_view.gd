extends TestCase
## Скриншоты рук с предметами (для доводки вида) и главного меню.

func _init() -> void:
	timeout_sec = 300.0

func run() -> void:
	await wait(1.0)
	var p := get_tree().get_first_node_in_group(&"player") as Player
	p.global_position = Vector3(-42.0, float(scene.call(&"height_at", -42.0, -12.0)) + 0.2, -12.0)
	p.set_look(deg_to_rad(70.0), deg_to_rad(-4.0))
	var inv := p.inventory
	inv.clear()
	for id: StringName in [&"axe_crude", &"axe_modern", &"spear", &"rock", &"stick", &"coconut", &"water_bottle"]:
		inv.add(id, 1)
	for i in [0, 1, 2, 5]:
		inv.select(i)
		await wait(0.7)
		var id := inv.selected_id()
		await shot("%d_%s" % [i, id if id != &"" else &"empty"])
		check(p.held_item() == id, "в руке %s" % id)
	inv.select(0)
	await wait(0.5)
	p.swing()
	await wait(0.22)
	await shot("8_swing")
	await wait(1.0)
