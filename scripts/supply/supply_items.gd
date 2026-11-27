class_name SupplyItems
extends RefCounted
## Предметы «из внешнего мира» (только из ящиков спонсоров, не крафтятся) и таблицы лута.
## Оружие — записи Combat.WEAPONS (rifle, shotgun, flare_gun, grenade, machete);
## инструменты и снаряжение работают через SupplyController (горелка, пила, бинокль,
## фонарик, рация, ласты, бронежилет); еда и аптечка — через Player.consume/Survival.

const GAS_PER_CAN := 75.0     # сек горения горелки на баллон
const FUEL_PER_CAN := 45.0    # сек работы пилы на канистру
const ARMOR_HP := 160.0       # сколько урона пуль/осколков поглощает бронежилет

## Таблицы: [[ [id, n], … ], вес]. Наборы выдаются целиком (оружие + немного патронов).
const LOOT_COMMON := [
	[[[&"canned_food", 2]], 3.0],
	[[[&"water_bottle", 2]], 3.0],
	[[[&"bandage", 2]], 2.0],
	[[[&"rope", 3]], 2.0],
	[[[&"flashlight", 1]], 1.4],
	[[[&"gas_torch", 1], [&"gas_can", 1]], 1.4],
	[[[&"binoculars", 1]], 1.1],
	[[[&"radio", 1]], 1.0],
	[[[&"fins", 1]], 1.0],
	[[[&"machete", 1]], 1.2],
	[[[&"axe_modern", 1]], 0.9],
	[[[&"medkit", 1]], 0.9],
	[[[&"pot", 1]], 0.6],
	[[[&"gas_can", 2]], 0.6],
	[[[&"shotgun_shell", 4]], 0.6],
	[[[&"ammo_9mm", 15]], 0.7],
]
const LOOT_RARE := [
	[[[&"shotgun", 1], [&"shotgun_shell", 6]], 2.0],
	[[[&"flare_gun", 1], [&"flare", 3]], 2.0],
	[[[&"medkit", 2]], 1.8],
	[[[&"armor_vest", 1]], 1.4],
	[[[&"chainsaw", 1], [&"fuel_can", 2]], 1.4],
	[[[&"grenade", 1]], 1.4],
	[[[&"rifle_ammo", 15]], 0.7],
	[[[&"pistol_9mm", 1], [&"ammo_9mm", 30]], 1.8],
	[[[&"dynamite", 1]], 0.7],
]
const LOOT_LEGENDARY := [
	[[[&"rifle", 1], [&"rifle_ammo", 30]], 3.0],
	[[[&"pistol_9mm", 1], [&"ammo_9mm", 45]], 0.8],
	[[[&"grenade", 2]], 1.6],
	[[[&"armor_vest", 1], [&"medkit", 1]], 1.0],
	[[[&"shotgun", 1], [&"shotgun_shell", 10]], 0.8],
]

static var _done := false

static func register() -> void:
	if _done:
		return
	_done = true
	CombatItems.register()
	SurvivalItems.register()
	# --- оружие ---
	_item(&"rifle", "Автомат", &"weapon", 1, 3.6, {"tool": &"gun", "damage": 10.0, "ranged": true, "held": SupplyModels.held(&"rifle"),
		"color": Color(0.3, 0.26, 0.2), "desc": "Посылка спонсоров. Очередь — держи ЛКМ, V — одиночный/авто, ПКМ — прицел, магазин 30 (+1 в патроннике), R — перезарядка. Каждый 4-й — трассер."})
	_item(&"pistol_9mm", "Пистолет", &"weapon", 1, 0.9, {"tool": &"gun", "damage": 5.0, "ranged": true, "held": SupplyModels.held(&"pistol_9mm"),
		"color": Color(0.12, 0.12, 0.13), "desc": "Посылка спонсоров. Современный 9 мм, магазин 15 (+1 в патроннике). ПКМ — прицел, R — перезарядка."})
	_item(&"ammo_9mm", "Патроны 9 мм", &"ammo", 90, 0.012, {"held": SupplyModels.held(&"ammo_9mm"), "color": Color(0.75, 0.6, 0.3),
		"desc": "Для пистолета."})
	_item(&"rifle_ammo", "Патроны 7,62", &"ammo", 60, 0.02, {"held": SupplyModels.held(&"rifle_ammo"), "color": Color(0.7, 0.55, 0.25),
		"desc": "Для автомата. В ящиках спонсоров — горстями."})
	_item(&"shotgun", "Дробовик", &"weapon", 1, 3.2, {"tool": &"gun", "damage": 9.0, "ranged": true, "held": SupplyModels.held(&"shotgun"),
		"color": Color(0.15, 0.15, 0.15), "desc": "Помповый, 4 патрона. Страшен вблизи, бесполезен вдали."})
	_item(&"shotgun_shell", "Патроны 12 калибра", &"ammo", 24, 0.04, {"held": SupplyModels.held(&"shotgun_shell"), "color": Color(0.7, 0.15, 0.1)})
	_item(&"flare_gun", "Ракетница", &"weapon", 1, 0.9, {"tool": &"gun", "damage": 4.0, "ranged": true, "held": SupplyModels.held(&"flare_gun"),
		"color": Color(0.95, 0.45, 0.1), "desc": "Сигнальная ракета горит красным и поджигает дерево: мосты, стены, плоты."})
	_item(&"flare", "Сигнальная ракета", &"ammo", 6, 0.1, {"held": SupplyModels.held(&"flare"), "color": Color(0.9, 0.35, 0.1)})
	_item(&"grenade", "Граната", &"weapon", 3, 0.6, {"tool": &"bottle", "damage": 3.0, "throwable": true, "held": SupplyModels.held(&"grenade"),
		"color": Color(0.3, 0.33, 0.2), "desc": "Держи ЛКМ — замах, отпусти — бросок. Взрыв через 3,5 с."})
	_item(&"machete", "Мачете", &"weapon", 1, 0.8, {"tool": &"axe", "damage": 20.0, "held": SupplyModels.held(&"machete"),
		"color": Color(0.75, 0.76, 0.78), "desc": "Длинный стальной клинок: хорошее оружие, рубит кусты и тонкие деревья."})
	# --- инструменты ---
	_item(&"chainsaw", "Бензопила", &"tool", 1, 5.5, {"tool": &"hand", "damage": 4.0, "held": SupplyModels.held(&"chainsaw"),
		"color": Color(0.9, 0.45, 0.1), "desc": "Держи ЛКМ — пилит в разы быстрее топора. Жрёт бензин и ревёт на весь остров."})
	_item(&"fuel_can", "Канистра бензина", &"resource", 3, 1.2, {"held": SupplyModels.held(&"fuel_can"), "color": Color(0.75, 0.12, 0.1),
		"desc": "Топливо для бензопилы (%d с работы)." % int(FUEL_PER_CAN)})
	_item(&"gas_torch", "Газовая горелка", &"tool", 1, 0.8, {"tool": &"hand", "damage": 3.0, "held": SupplyModels.held(&"gas_torch"),
		"color": Color(0.2, 0.35, 0.75), "desc": "ПКМ — вскипятить воду (нужен котелок) или пожарить еду без костра. ЛКМ — факел: поджигает постройки и мосты."})
	_item(&"gas_can", "Газовый баллон", &"resource", 4, 0.4, {"held": SupplyModels.held(&"gas_can"), "color": Color(0.15, 0.3, 0.7),
		"desc": "Газ для горелки (%d с горения)." % int(GAS_PER_CAN)})
	_item(&"binoculars", "Бинокль", &"tool", 1, 0.7, {"tool": &"hand", "damage": 3.0, "held": SupplyModels.held(&"binoculars"),
		"color": Color(0.2, 0.24, 0.16), "desc": "Держи ПКМ — смотреть вдаль (×6)."})
	_item(&"flashlight", "Фонарик", &"tool", 1, 0.3, {"tool": &"hand", "damage": 3.0, "held": SupplyModels.held(&"flashlight"),
		"color": Color(0.1, 0.1, 0.1), "desc": "ПКМ — включить/выключить. Светит, пока в руке."})
	_item(&"radio", "Рация", &"tool", 1, 0.5, {"tool": &"hand", "damage": 3.0, "held": SupplyModels.held(&"radio"),
		"color": Color(0.12, 0.12, 0.12), "desc": "Ловит переговоры пилотов: следующий сброс заранее виден на карте. ПКМ — послушать эфир."})
	# --- снаряжение (работает из инвентаря) ---
	_item(&"fins", "Ласты", &"tool", 1, 1.0, {"tool": &"hand", "damage": 2.0, "held": SupplyModels.held(&"fins"),
		"color": Color(0.9, 0.75, 0.1), "desc": "В инвентаре — плаваешь в полтора раза быстрее и тратишь меньше сил."})
	_item(&"armor_vest", "Бронежилет", &"tool", 1, 4.5, {"tool": &"hand", "damage": 2.0, "held": SupplyModels.held(&"armor_vest"),
		"color": Color(0.27, 0.3, 0.2), "desc": "В инвентаре — гасит половину урона от пуль и осколков, пока не разобьют пластины (%d)." % int(ARMOR_HP)})
	# --- еда и медицина ---
	_item(&"medkit", "Аптечка", &"food", 3, 0.5, {"health": 60.0, "sv": &"cure", "held": SupplyModels.held(&"medkit"),
		"color": Color(0.8, 0.15, 0.12), "desc": "Бинты, антисептик, противоядие: +60 здоровья и снимает яд."})
	_item(&"canned_food", "Консервы", &"food", 6, 0.4, {"hunger": 40.0, "health": 3.0, "returns": &"scrap_metal", "held": SupplyModels.held(&"canned_food"),
		"color": Color(0.85, 0.65, 0.2), "desc": "Тушёнка: не портится. Пустая банка — жесть."})
	UserHeld.register_items()   # v5: боевой нож, зажигалка (модели пользователя)

static func _item(id: StringName, nm: String, kind: StringName, stack: int, weight: float, data: Dictionary) -> void:
	if Items.get_item(id) == null:
		Items.register_item(id, nm, kind, stack, weight, data)
	else:
		var d := Items.get_item(id)
		for k in data.keys():
			if not d.data.has(k):
				d.data[k] = data[k]

static func _roll(table: Array, rng: RandomNumberGenerator) -> Array:
	var total := 0.0
	for e: Array in table:
		total += float(e[1])
	var r := rng.randf() * total
	for e: Array in table:
		r -= float(e[1])
		if r <= 0.0:
			return e[0]
	return (table[0] as Array)[0]

## Содержимое ящика: [{id, n}]. tier 0 — обычный (3 вещи), 1 — редкий (1 редкая + 2), 2 — легендарный (1+1+2).
static func roll_loot(tier: int, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var picks: Array = []
	if tier >= 2:
		picks.append(_roll(LOOT_LEGENDARY, rng))
	if tier >= 1:
		picks.append(_roll(LOOT_RARE, rng))
	for k in (3 if tier == 0 else 2):
		picks.append(_roll(LOOT_COMMON, rng))
	var out: Array[Dictionary] = []
	for set: Array in picks:
		for e: Array in set:
			var id: StringName = e[0]
			var n := int(e[1])
			var merged := false
			for o in out:
				if o.id == id and Inventory.stack_of(id) > 1:
					o.n = int(o.n) + n
					merged = true
			if not merged:
				out.append({"id": id, "n": n})
	return out
