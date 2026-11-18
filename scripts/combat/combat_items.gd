class_name CombatItems
extends RefCounted
## Предметы и рецепты COMBAT (через Items). Станции: workbench, campfire.

static func register() -> void:
	PlayerItems.register()
	# оружие ближнего боя
	_item(&"club", "Дубина", &"weapon", 1, 2.2, {"tool": &"club", "damage": 18.0, "reach": 2.3, "color": Color(0.45, 0.32, 0.2)})
	# стрелковое
	_item(&"bow", "Лук", &"weapon", 1, 1.0, {"tool": &"bow", "damage": 4.0, "color": Color(0.5, 0.36, 0.22), "ranged": true})
	_item(&"crossbow", "Арбалет", &"weapon", 1, 3.5, {"tool": &"crossbow", "damage": 7.0, "color": Color(0.42, 0.3, 0.2), "ranged": true})
	_item(&"musket", "Мушкет", &"weapon", 1, 4.5, {"tool": &"gun", "damage": 9.0, "color": Color(0.35, 0.27, 0.2), "ranged": true})
	_item(&"pistol", "Пистоль", &"weapon", 1, 1.4, {"tool": &"gun", "damage": 5.0, "color": Color(0.33, 0.26, 0.2), "ranged": true})
	# боеприпасы
	_item(&"arrow", "Стрела", &"ammo", 30, 0.05, {"color": Color(0.6, 0.48, 0.3)})
	_item(&"arrow_fire", "Огненная стрела", &"ammo", 20, 0.07, {"color": Color(0.85, 0.45, 0.15)})
	_item(&"bolt", "Арбалетный болт", &"ammo", 30, 0.08, {"color": Color(0.5, 0.42, 0.32)})
	_item(&"musket_ball", "Свинцовая пуля", &"ammo", 40, 0.03, {"color": Color(0.45, 0.46, 0.5)})
	_item(&"gunpowder", "Порох", &"resource", 40, 0.05, {"color": Color(0.16, 0.15, 0.14)})
	# метательное
	_item(&"molotov", "Коктейль Молотова", &"weapon", 5, 0.8, {"tool": &"bottle", "damage": 3.0, "color": Color(0.55, 0.42, 0.15), "throwable": true})
	_item(&"dynamite", "Динамит", &"weapon", 5, 0.4, {"tool": &"dynamite", "damage": 2.0, "color": Color(0.75, 0.2, 0.15), "throwable": true})
	# сырьё для крафта
	_item(&"charcoal", "Древесный уголь", &"resource", 30, 0.2, {"color": Color(0.1, 0.1, 0.1)})
	_item(&"saltpeter", "Селитра", &"resource", 30, 0.2, {"color": Color(0.9, 0.9, 0.85)})
	_item(&"spirit", "Кокосовый спирт", &"resource", 5, 0.6, {"color": Color(0.85, 0.8, 0.6)})
	_item(&"iron_parts", "Железные детали", &"resource", 20, 0.8, {"color": Color(0.4, 0.4, 0.42)})
	_item(&"lead", "Свинец", &"resource", 20, 0.8, {"color": Color(0.5, 0.5, 0.55)})

	_recipe(&"r_club", &"club", {&"log": 1}, 1)
	_recipe(&"r_bow", &"bow", {&"stick": 3, &"rope": 2}, 1)
	_recipe(&"r_arrow", &"arrow", {&"stick": 2, &"stone": 1, &"leaf": 2}, 4)
	_recipe(&"r_arrow_fire", &"arrow_fire", {&"arrow": 2, &"cloth": 1, &"spirit": 1}, 2)
	_recipe(&"r_bolt", &"bolt", {&"stick": 2, &"stone": 1}, 3, &"workbench")
	_recipe(&"r_crossbow", &"crossbow", {&"log": 1, &"stick": 3, &"rope": 3, &"iron_parts": 1}, 1, &"workbench")
	_recipe(&"r_charcoal", &"charcoal", {&"stick": 3}, 2, &"campfire")
	_recipe(&"r_saltpeter", &"saltpeter", {&"stone": 2, &"leaf": 3}, 1, &"campfire")
	_recipe(&"r_gunpowder", &"gunpowder", {&"charcoal": 1, &"saltpeter": 1, &"stone": 1}, 3, &"workbench")
	_recipe(&"r_spirit", &"spirit", {&"coconut": 3}, 1, &"campfire")
	_recipe(&"r_iron_parts", &"iron_parts", {&"stone": 4, &"charcoal": 2}, 1, &"campfire")
	_recipe(&"r_lead", &"lead", {&"stone": 3, &"charcoal": 1}, 1, &"campfire")
	_recipe(&"r_musket_ball", &"musket_ball", {&"lead": 1}, 6, &"campfire")
	_recipe(&"r_musket", &"musket", {&"log": 1, &"iron_parts": 4, &"rope": 1}, 1, &"workbench")
	_recipe(&"r_pistol", &"pistol", {&"stick": 2, &"iron_parts": 2}, 1, &"workbench")
	_recipe(&"r_molotov", &"molotov", {&"water_bottle": 1, &"spirit": 1, &"cloth": 1}, 1)
	_recipe(&"r_dynamite", &"dynamite", {&"gunpowder": 4, &"cloth": 1, &"rope": 1}, 1, &"workbench")

static func _item(id: StringName, nm: String, kind: StringName, stack: int, weight: float, data: Dictionary) -> void:
	if Items.get_item(id) == null:
		Items.register_item(id, nm, kind, stack, weight, data)
	else:
		var d := Items.get_item(id)
		for k in data.keys():
			if not d.data.has(k):
				d.data[k] = data[k]

static func _recipe(id: StringName, out: StringName, needs: Dictionary, count: int, station: StringName = &"") -> void:
	if not Items.recipes.has(id):
		Items.register_recipe(id, out, needs, count, station)
