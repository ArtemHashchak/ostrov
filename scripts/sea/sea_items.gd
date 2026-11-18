class_name SeaItems
extends RefCounted
## Предметы моря: акулье мясо и зубы, верша (ловушка для рыбы).
## Как у других модулей: чужие регистрации не перезаписываем, только дополняем ключи.

static var _done := false

## Что годится в приманку (бросить в воду — G/бросок): секунд приманки за штуку.
const BAIT := {
	&"fish_raw": 22.0, &"meat_raw": 26.0, &"crab_meat": 16.0, &"shark_meat": 30.0,
	&"rotten_food": 18.0, &"turtle_egg": 8.0,
}

static func register() -> void:
	if _done:
		return
	_done = true
	_item(&"shark_meat", "Акулье мясо", &"food", 10, 0.6,
		{"hunger": 14.0, "raw_risk": 0.3, "cook": &"meat_cooked", "smoke": &"smoked_meat",
		"color": Color(0.82, 0.62, 0.6), "desc": "Жёсткое, пахнет аммиаком. Лучше жарить. Отличная приманка."})
	_item(&"shark_tooth", "Акулий зуб", &"resource", 30, 0.02,
		{"color": Color(0.95, 0.94, 0.88), "desc": "Острый, как бритва. Для наконечников и ножей."})
	_item(&"fish_trap", "Верша", &"tool", 4, 1.2,
		{"color": Color(0.62, 0.5, 0.3),
		"desc": "Плетёная ловушка для рыбы. Брось (G) в воду глубиной 0.6–5 м — со временем наловит рыбы, пока в округе она не кончится."})
	if Items.recipes.get(&"r_fish_trap") == null:
		Items.register_recipe(&"r_fish_trap", &"fish_trap", {&"stick": 4, &"rope": 3}, 1)

static func _item(id: StringName, nm: String, kind: StringName, stack: int, weight: float, data: Dictionary) -> void:
	var d := Items.get_item(id)
	if d == null:
		Items.register_item(id, nm, kind, stack, weight, data)
	else:
		for k in data.keys():
			if not d.data.has(k):
				d.data[k] = data[k]
