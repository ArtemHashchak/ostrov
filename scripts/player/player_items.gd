class_name PlayerItems
extends RefCounted
## Предметы и рецепты, которые нужны игроку/интерфейсу (инструменты, оружие,
## еда, базовые ресурсы). Регистрируются один раз; чужие регистрации не
## перезаписываются (если модуль уже зарегистрировал id — оставляем его).
## data предмета:
##   tool: StringName  — тип удара ('axe','rock','spear','hand','stick')
##   damage: float     — урон удара
##   hunger/thirst/health: float — эффект при употреблении (еда/питьё)
##   raw_risk: float   — шанс отравиться сырым (урон 6..12)
##   color: Color      — цвет иконки

const ItemsScript := preload("res://scripts/core/items.gd")

static var _done := false

static func register() -> void:
	if _done:
		return
	_done = true
	_item(&"stick", "Палка", &"resource", 20, 0.5, {"tool": &"stick", "damage": 6.0, "color": Color(0.55, 0.4, 0.25)})
	_item(&"rock", "Камень", &"resource", 10, 1.5, {"tool": &"rock", "damage": 9.0, "color": Color(0.55, 0.55, 0.53)})
	_item(&"stone", "Камень", &"resource", 20, 1.5, {"tool": &"rock", "damage": 9.0, "color": Color(0.55, 0.55, 0.53)})
	_item(&"leaf", "Лист", &"resource", 30, 0.1, {"color": Color(0.35, 0.55, 0.25)})
	_item(&"fiber", "Волокно", &"resource", 30, 0.1, {"color": Color(0.6, 0.62, 0.38)})
	_item(&"rope", "Верёвка", &"resource", 20, 0.3, {"color": Color(0.7, 0.6, 0.42)})
	_item(&"cloth", "Ткань", &"resource", 20, 0.3, {"color": Color(0.82, 0.78, 0.68)})
	_item(&"axe_crude", "Каменный топор", &"tool", 1, 2.0,
		{"tool": &"axe", "damage": 14.0, "color": Color(0.5, 0.45, 0.38), "desc": "Самодельный. Рубит деревья, но медленно."})
	_item(&"axe_modern", "Топор", &"tool", 1, 2.5,
		{"tool": &"axe", "damage": 22.0, "color": Color(0.62, 0.64, 0.68), "desc": "Стальной топор. Рубит быстро."})
	_item(&"spear", "Копьё", &"weapon", 1, 1.5,
		{"tool": &"spear", "damage": 20.0, "reach": 2.8, "color": Color(0.6, 0.5, 0.35), "desc": "Длинный удар. Хорошо против зверей и акул."})
	_item(&"coconut", "Кокос", &"food", 10, 1.0,
		{"hunger": 10.0, "thirst": 15.0, "color": Color(0.36, 0.52, 0.2)})
	_item(&"coconut_peeled", "Очищенный кокос", &"food", 10, 0.8,
		{"hunger": 10.0, "thirst": 15.0, "color": Color(0.45, 0.3, 0.18)})
	_item(&"meat_raw", "Сырое мясо", &"food", 10, 0.5,
		{"hunger": 12.0, "raw_risk": 0.35, "color": Color(0.75, 0.32, 0.32)})
	_item(&"meat_cooked", "Жареное мясо", &"food", 10, 0.5,
		{"hunger": 35.0, "health": 5.0, "color": Color(0.5, 0.28, 0.16)})
	_item(&"fish_raw", "Сырая рыба", &"food", 10, 0.5,
		{"hunger": 10.0, "raw_risk": 0.3, "color": Color(0.55, 0.62, 0.68)})
	_item(&"water_bottle", "Бутылка воды", &"food", 5, 0.6,
		{"thirst": 40.0, "color": Color(0.45, 0.65, 0.85)})
	_item(&"bandage", "Бинт", &"food", 10, 0.1,
		{"health": 25.0, "color": Color(0.92, 0.9, 0.86)})
	# Рецепты в руках (станция ""), как «книга выживания»: простые и честные.
	_recipe(&"r_rope", &"rope", {&"fiber": 3}, 1)
	_recipe(&"r_axe_crude", &"axe_crude", {&"stick": 1, &"rock": 1, &"rope": 1}, 1)
	_recipe(&"r_spear", &"spear", {&"stick": 2, &"rope": 1}, 1)
	_recipe(&"r_bandage", &"bandage", {&"cloth": 1}, 1)

static func _item(id: StringName, nm: String, kind: StringName, stack: int, weight: float, data: Dictionary) -> void:
	if Items.get_item(id) == null:
		Items.register_item(id, nm, kind, stack, weight, data)
	else:
		# Дополняем данными, которых нет (иконка/урон), не трогая чужие.
		var d := Items.get_item(id)
		for k in data.keys():
			if not d.data.has(k):
				d.data[k] = data[k]

static func _recipe(id: StringName, out: StringName, needs: Dictionary, count: int, station: StringName = &"") -> void:
	if not Items.recipes.has(id):
		Items.register_recipe(id, out, needs, count, station)

static func data(id: StringName) -> Dictionary:
	var d := Items.get_item(id)
	return d.data if d else {}

static func color_of(id: StringName) -> Color:
	var dd := data(id)
	return dd.get("color", Color(0.6, 0.6, 0.6)) as Color

## Тип удара и урон для предмета в руке.
static func tool_of(id: StringName) -> StringName:
	if id == &"":
		return &"hand"
	return StringName(data(id).get("tool", &"hand"))

static func damage_of(id: StringName) -> float:
	if id == &"":
		return 4.0
	return float(data(id).get("damage", 4.0))

static func is_consumable(id: StringName) -> bool:
	var d := Items.get_item(id)
	if d == null:
		return false
	var dd := d.data
	return d.kind == &"food" or dd.has("hunger") or dd.has("thirst") or (dd.has("health") and d.kind != &"tool")

## Рецепт можно сделать сейчас? Возвращает "" или причину.
static func craft_block_reason(ch: Node, r: ItemsScript.RecipeDef) -> String:
	var inv := ch.get_node_or_null(^"Inventory") as Inventory
	if inv == null:
		return "Нет инвентаря"
	if r.station != &"" and not near_station(ch, r.station):
		return "Нужно быть у станции: %s" % station_name(r.station)
	if not inv.has(r.needs):
		return "Не хватает ресурсов"
	if inv.space_for(r.output) < r.count and not Inventory.is_heavy(r.output):
		return "Нет места"
	return ""

static func craft(ch: Node, r: ItemsScript.RecipeDef) -> bool:
	if craft_block_reason(ch, r) != "":
		return false
	var inv := ch.get_node(^"Inventory") as Inventory
	for k in r.needs.keys():
		inv.remove(StringName(k), int(r.needs[k]))
	inv.add(r.output, r.count)
	Events.item_crafted.emit(ch, r.output, r.count)
	return true

static func near_station(ch: Node, station: StringName) -> bool:
	var n3 := ch as Node3D
	if n3 == null:
		return false
	for s in n3.get_tree().get_nodes_in_group(station):
		var s3 := s as Node3D
		if s3 and s3.global_position.distance_to(n3.global_position) <= 3.5:
			return true
	return false

static func station_name(st: StringName) -> String:
	match st:
		&"workbench": return "верстак"
		&"campfire": return "костёр"
		_: return String(st)

static func needs_text(needs: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k in needs.keys():
		parts.append("%s ×%d" % [Items.item_name(StringName(k)), int(needs[k])])
	return ", ".join(parts)
