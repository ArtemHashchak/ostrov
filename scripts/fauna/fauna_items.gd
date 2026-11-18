class_name FaunaItems
extends RefCounted
## Предметы от животных. Не перезаписывает чужие регистрации (как PlayerItems).

static var _done := false

static func register() -> void:
	if _done:
		return
	_done = true
	_item(&"hide", "Шкура", &"resource", 10, 1.0, {"color": Color(0.45, 0.33, 0.22), "desc": "Шкура зверя. Для одежды и снаряжения."})
	_item(&"feather", "Перо", &"resource", 30, 0.05, {"color": Color(0.85, 0.2, 0.15), "desc": "Перья — для стрел и украшений."})
	_item(&"crab_meat", "Крабовое мясо", &"food", 10, 0.3, {"hunger": 8.0, "raw_risk": 0.2, "color": Color(0.95, 0.6, 0.5)})
	_item(&"turtle_egg", "Черепашье яйцо", &"food", 12, 0.15, {"hunger": 9.0, "health": 2.0, "raw_risk": 0.1, "color": Color(0.93, 0.9, 0.82)})
	_item(&"meat_raw", "Сырое мясо", &"food", 10, 0.5, {"hunger": 12.0, "raw_risk": 0.35, "color": Color(0.75, 0.32, 0.32)})

static func _item(id: StringName, nm: String, kind: StringName, stack: int, weight: float, data: Dictionary) -> void:
	var d := Items.get_item(id)
	if d == null:
		Items.register_item(id, nm, kind, stack, weight, data)
	else:
		for k in data.keys():
			if not d.data.has(k):
				d.data[k] = data[k]
