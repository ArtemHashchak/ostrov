class_name MechItems
## Предметы и рецепты V5 (агент F): лестница ёмкостей для воды, трут и огниво, соль и
## солонина. Регистрируются из SurvivalItems.register() (схема SURVIVAL: fill_fresh/
## fill_salt/returns/thirst/boil/spoil). Объёмы и материалы — assets/data/items_props.json.
## Модели пока чужие (плошка/бутылка) — новые модели в docs/MODELS.md §7.

static var _done := false

static func register() -> void:
	if _done:
		return
	_done = true
	# ---------- ёмкости: пустая → пресная / морская ----------
	var cont := [
		# id, имя, вместимость (л), открытая, модель (shell/bottle)
		[&"bamboo_cup", "Колено бамбука", 0.8, true, "shell"],
		[&"turtle_shell", "Панцирь черепахи", 1.0, true, "shell"],
		[&"gourd", "Тыква-горлянка", 2.0, false, "bottle"],
	]
	for c: Array in cont:
		var id: StringName = c[0]
		var nm: String = c[1]
		var cap: float = c[2]
		var open_: bool = c[3]
		var held: Callable = SurvivalModels.held_shell if c[4] == "shell" else SurvivalModels.held_bottle
		var thirst := minf(48.0, cap * DataTables.f("balance", "water/thirst_per_l", 35.0))
		var w := Materials.mass(id)
		SurvivalItems._item(id, nm, &"resource", 5, w,
			{"fill_fresh": StringName(String(id) + "_water"), "fill_salt": StringName(String(id) + "_salt"),
			 "held": held.bind(0.0), "container_l": cap, "open": open_,
			 "desc": "Ёмкость %.1f л%s. Набери воды: смотри на воду и жми E." % [cap, " (открытая — расплёскивается на бегу)" if open_ else ""]})
		SurvivalItems._item(StringName(String(id) + "_water"), nm + " с водой", &"food", 5, w + cap,
			{"thirst": thirst, "returns": id, "held": held.bind(1.0), "container_l": cap, "open": open_, "liquid": &"fresh",
			 "color": Color(0.42, 0.62, 0.82)})
		SurvivalItems._item(StringName(String(id) + "_salt"), nm + " с морской водой", &"food", 5, w + cap,
			{"sv": &"salt_water", "returns": id, "boil": StringName(String(id) + "_water"), "held": held.bind(1.0),
			 "container_l": cap, "open": open_, "liquid": &"salt", "color": Color(0.33, 0.5, 0.55)})
	# старые ёмкости SURVIVAL: отметить объём и «открытость»
	for pair: Array in [[&"coconut_shell", 0.3, true], [&"shell_water", 0.3, true], [&"shell_salt", 0.3, true],
			[&"bottle_empty", 1.5, false], [&"water_bottle", 1.5, false], [&"water_salt", 1.5, false]]:
		var d := Items.get_item(pair[0])
		if d:
			d.data["container_l"] = pair[1]
			d.data["open"] = pair[2]
	# канистра (посылка/донат): хранит воду объёмом, наливает в мелкую тару
	SurvivalItems._item(&"canister", "Канистра 20 л", &"tool", 1, 1.2,
		{"container_l": 20.0, "open": false, "big_container": true, "held": SurvivalModels.held_bottle.bind(0.5),
		 "desc": "Хранит до 20 л. У воды/под дождём E — набрать; ПКМ — налить в пустую тару или отпить."})
	# ---------- огонь ----------
	SurvivalItems._item(&"coconut_husk", "Шелуха кокоса", &"resource", 20, 0.1,
		{"tinder": true, "color": Color(0.55, 0.4, 0.25), "desc": "Лучший трут. Мокрая — не загорится, суши на солнце."})
	SurvivalItems._item(&"fire_drill", "Лучковое сверло", &"tool", 1, 0.3,
		{"fire_starter": true, "color": Color(0.5, 0.36, 0.2), "desc": "Огонь трением: долго, и почти не работает, если сыро."})
	SurvivalItems._item(&"flint_steel", "Огниво", &"tool", 1, 0.2,
		{"fire_starter": true, "color": Color(0.35, 0.35, 0.38), "desc": "Искры на трут. Надёжнее трения."})
	if Items.get_item(&"lighter") == null:
		Items.register_item(&"lighter", "Зажигалка", &"tool", 1, 0.06, {"fire_starter": true, "desc": "Из посылки спонсоров. Почти всегда разжигает."})
	# ---------- соль и солонина ----------
	SurvivalItems._item(&"salt", "Соль", &"resource", 20, 0.1, {"color": Color(0.93, 0.93, 0.9), "desc": "Выпаренная морская вода. Сохраняет рыбу и мясо."})
	SurvivalItems._item(&"salted_fish", "Солёная рыба", &"food", 10, 0.35, {"hunger": 26.0, "thirst": -8.0, "spoil": 300.0, "color": Color(0.8, 0.78, 0.7)})
	SurvivalItems._item(&"salted_meat", "Солонина", &"food", 10, 0.35, {"hunger": 30.0, "thirst": -8.0, "spoil": 300.0, "color": Color(0.7, 0.45, 0.4)})
	SurvivalItems._recipe(&"v5_bamboo_cup", &"bamboo_cup", {&"stick": 2}, 1)
	SurvivalItems._recipe(&"v5_gourd", &"gourd", {&"melon": 1}, 1)
	SurvivalItems._recipe(&"v5_husk", &"coconut_husk", {&"coconut": 1}, 3)
	SurvivalItems._recipe(&"v5_fire_drill", &"fire_drill", {&"stick": 2, &"rope": 1}, 1)
	SurvivalItems._recipe(&"v5_salt", &"salt", {&"water_salt": 2}, 1, &"campfire")
	SurvivalItems._recipe(&"v5_salt_shell", &"salt", {&"shell_salt": 4}, 1, &"campfire")
	SurvivalItems._recipe(&"v5_salted_fish", &"salted_fish", {&"fish_raw": 1, &"salt": 1}, 1)
	SurvivalItems._recipe(&"v5_salted_meat", &"salted_meat", {&"meat_raw": 1, &"salt": 1}, 1)
