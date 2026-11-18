class_name CombatTestCase
extends BuildTestCase
## Хелперы тестов COMBAT.

var combat: Combat

func setup_combat(with_build: bool = false) -> bool:
	if with_build:
		if not await setup_build():
			return false
	else:
		await wait(1.0)
		p = get_tree().get_first_node_in_group(&"player") as Player
		if p == null:
			check(false, "игрок создан")
			return false
	combat = (load("res://scenes/combat/combat.tscn") as PackedScene).instantiate() as Combat
	scene.add_child(combat)
	await wait_frames(3)
	check(p.get_node_or_null(^"CombatController") != null, "CombatController прицеплен к игроку")
	return true

func ctrl() -> CombatController:
	return p.get_node(^"CombatController") as CombatController

## Положить предмет и взять его в руку.
func equip(id: StringName) -> void:
	if p.inventory.count(id) == 0:
		p.inventory.add(id, 1)
	for i in Inventory.HOTBAR:
		if p.inventory.get_slot(i).get("id", &"") == id:
			p.inventory.select(i)
			break
	await wait(0.4)

func ground_y(x: float, z: float) -> float:
	return BuildEnv.height_at(x, z)
