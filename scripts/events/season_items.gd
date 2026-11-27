class_name SeasonItems
## Предметы событий сезона (v5.2): тест-полоска для воды (отравленный родник).

static var _done := false

static func register() -> void:
	if _done and Items.get_item(&"water_test_kit") != null:
		return
	_done = true
	if Items.get_item(&"water_test_kit") == null:
		Items.register_item(&"water_test_kit", "Тест-полоска для воды", &"tool", 5, 0.01,
			{"color": Color(0.95, 0.95, 0.85),
			 "desc": "Подарок спонсоров. Возьми в руку, посмотри на воду и нажми E — покажет, отравлена ли она."})
