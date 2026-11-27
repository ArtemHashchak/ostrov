class_name SurvivalItems
extends RefCounted
## Предметы и рецепты модуля SURVIVAL (вода, тара, еда, огород, травы, мусор).
## Регистрируются через Items; чужие предметы не перезаписываются — только
## дополняются недостающими ключами data (как PlayerItems._item).
##
## Ключи data, которые использует SURVIVAL:
##   hunger/thirst/health — эффект употребления (читает Player.consume)
##   raw_risk             — шанс «живот скрутило» (Player.consume)
##   spoil: float         — минут до порчи (свежесть в слоте: ключ "fr" 0..1)
##   sv: StringName       — особая обработка в Survival.on_consumed
##   returns: StringName  — что остаётся в руках после употребления (тара)
##   cook: StringName     — во что превращается на костре
##   smoke: StringName    — во что превращается в коптильне
##   boil: StringName     — во что превращается при кипячении в котелке
##   fill_fresh/fill_salt — пустая тара: чем становится, если набрать пресной/морской
##   kit: StringName      — набор для установки постройки SURVIVAL (ПКМ — поставить)
##   seed: StringName     — семя: что вырастет на грядке
##   held: Callable       — модель в руке (HeldModels._generic зовёт, если есть)

static var _done := false

## Минуты до порчи (реальное время матча 3–4 ч).
const SPOIL := {
	&"meat_raw": 10.0, &"fish_raw": 8.0,
	&"meat_cooked": 25.0, &"fish_cooked": 22.0,
	&"smoked_meat": 120.0, &"smoked_fish": 110.0,
	&"berries": 15.0, &"melon": 25.0, &"melon_slice": 12.0,
	&"taro": 40.0, &"taro_baked": 25.0, &"maize": 40.0, &"maize_roasted": 25.0,
	&"herb": 30.0,
}

static func register() -> void:
	if _done:
		return
	_done = true
	# ---------- тара и вода ----------
	_item(&"bottle_empty", "Пустая бутылка", &"resource", 5, 0.2,
		{"fill_fresh": &"water_bottle", "fill_salt": &"water_salt", "color": Color(0.75, 0.85, 0.9),
		 "held": SurvivalModels.held_bottle.bind(0.0), "desc": "Набери воды: смотри на воду и жми E."})
	_item(&"water_bottle", "Бутылка воды", &"food", 5, 0.6,
		{"thirst": 40.0, "returns": &"bottle_empty", "color": Color(0.45, 0.65, 0.85),
		 "held": SurvivalModels.held_bottle.bind(0.8), "desc": "Пресная вода."})
	_item(&"water_salt", "Морская вода", &"food", 5, 0.6,
		{"sv": &"salt_water", "returns": &"bottle_empty", "boil": &"water_bottle", "color": Color(0.35, 0.55, 0.6),
		 "held": SurvivalModels.held_bottle.bind(0.8), "desc": "Солёная. Пить вредно — вскипяти в котелке на костре."})
	_item(&"coconut_shell", "Скорлупа кокоса", &"resource", 10, 0.2,
		{"fill_fresh": &"shell_water", "fill_salt": &"shell_salt", "color": Color(0.42, 0.28, 0.16),
		 "held": SurvivalModels.held_shell.bind(0.0), "desc": "Половинка кокоса — плошка для воды."})
	_item(&"shell_water", "Плошка воды", &"food", 10, 0.4,
		{"thirst": 22.0, "returns": &"coconut_shell", "color": Color(0.4, 0.6, 0.8), "held": SurvivalModels.held_shell.bind(1.0)})
	_item(&"shell_salt", "Плошка морской воды", &"food", 10, 0.4,
		{"sv": &"salt_water", "returns": &"coconut_shell", "boil": &"shell_water", "color": Color(0.33, 0.5, 0.55),
		 "held": SurvivalModels.held_shell.bind(1.0)})
	_item(&"pot", "Котелок", &"tool", 1, 1.2,
		{"tool": &"hand", "damage": 5.0, "color": Color(0.55, 0.45, 0.35), "held": SurvivalModels.held_pot,
		 "desc": "Носи с собой: у горящего костра кипятит морскую воду (E по костру)."})
	_item(&"knife", "Нож из жести", &"tool", 1, 0.4,
		{"tool": &"knife", "damage": 9.0, "color": Color(0.6, 0.58, 0.55), "held": SurvivalModels.held_knife,
		 "desc": "Колет кокосы, режет сети и лианы."})
	# ---------- еда ----------
	# v5.1: подобранный кокос — зелёный, в шелухе (та же модель, что на земле); пока его не очистят —
	# не пьётся. Очистить (ПКМ/E): нож, мачете, топор или камень → очищенный кокос + шелуха (растопка).
	_item(&"coconut", "Зелёный кокос", &"food", 10, 1.2,
		{"hunger": 8.0, "thirst": 18.0, "color": Color(0.36, 0.52, 0.2), "peel": &"coconut_peeled",
		 "desc": "Зелёный, в шелухе. Очистить (ПКМ/E): нож, мачете, топор или камень."})
	var cd := Items.get_item(&"coconut")
	if cd:
		cd.name = "Зелёный кокос"
		cd.data["color"] = Color(0.36, 0.52, 0.2)
		cd.data["peel"] = &"coconut_peeled"
		cd.data.erase("sv")
	_item(&"coconut_peeled", "Очищенный кокос", &"food", 10, 0.8,
		{"hunger": 8.0, "thirst": 18.0, "sv": &"coconut", "color": Color(0.45, 0.3, 0.18),
		 "desc": "Без шелухи. Пей и ешь — расколоть: камень, топор или нож в инвентаре."})
	_item(&"meat_raw", "Сырое мясо", &"food", 10, 0.5,
		{"hunger": 12.0, "raw_risk": 0.35, "cook": &"meat_cooked", "smoke": &"smoked_meat", "color": Color(0.75, 0.32, 0.32)})
	_item(&"meat_cooked", "Жареное мясо", &"food", 10, 0.5,
		{"hunger": 35.0, "health": 5.0, "color": Color(0.5, 0.28, 0.16)})
	_item(&"fish_raw", "Сырая рыба", &"food", 10, 0.5,
		{"hunger": 10.0, "raw_risk": 0.3, "cook": &"fish_cooked", "smoke": &"smoked_fish", "color": Color(0.55, 0.62, 0.68)})
	_item(&"fish_cooked", "Жареная рыба", &"food", 10, 0.5,
		{"hunger": 30.0, "health": 4.0, "color": Color(0.72, 0.55, 0.35)})
	_item(&"smoked_meat", "Вяленое мясо", &"food", 10, 0.3,
		{"hunger": 30.0, "thirst": -4.0, "color": Color(0.38, 0.18, 0.12), "desc": "Хранится долго."})
	_item(&"smoked_fish", "Копчёная рыба", &"food", 10, 0.3,
		{"hunger": 26.0, "thirst": -4.0, "color": Color(0.62, 0.42, 0.22), "desc": "Хранится долго."})
	_item(&"rotten_food", "Гниль", &"food", 10, 0.3,
		{"hunger": 3.0, "sv": &"rotten", "color": Color(0.35, 0.38, 0.2), "desc": "Испорченная еда. Есть опасно — лучше на грядку."})
	_item(&"berries", "Ягоды", &"food", 20, 0.1,
		{"hunger": 5.0, "thirst": 4.0, "color": Color(0.7, 0.12, 0.25)})
	_item(&"taro", "Клубень таро", &"food", 10, 0.4,
		{"hunger": 8.0, "raw_risk": 0.5, "cook": &"taro_baked", "color": Color(0.55, 0.42, 0.45), "desc": "Сырым жжёт горло — запеки."})
	_item(&"taro_baked", "Печёный таро", &"food", 10, 0.4,
		{"hunger": 28.0, "color": Color(0.62, 0.5, 0.42)})
	_item(&"maize", "Початок кукурузы", &"food", 10, 0.3,
		{"hunger": 9.0, "cook": &"maize_roasted", "color": Color(0.92, 0.78, 0.3)})
	_item(&"maize_roasted", "Жареная кукуруза", &"food", 10, 0.3,
		{"hunger": 22.0, "color": Color(0.85, 0.6, 0.25)})
	_item(&"melon", "Дыня", &"food", 4, 1.5,
		{"hunger": 12.0, "thirst": 25.0, "color": Color(0.55, 0.7, 0.3), "desc": "Сочная: утоляет жажду."})
	# ---------- огород ----------
	_item(&"seed_taro", "Отросток таро", &"resource", 10, 0.1,
		{"seed": &"taro", "color": Color(0.5, 0.4, 0.4), "desc": "Посади на грядке (E по грядке)."})
	_item(&"seed_maize", "Зёрна кукурузы", &"resource", 20, 0.05,
		{"seed": &"maize", "color": Color(0.95, 0.82, 0.35), "desc": "Посади на грядке (E по грядке)."})
	_item(&"seed_melon", "Семена дыни", &"resource", 20, 0.05,
		{"seed": &"melon", "color": Color(0.9, 0.85, 0.6), "desc": "Посади на грядке (E по грядке)."})
	_item(&"seed_berry", "Черенок ягодника", &"resource", 10, 0.1,
		{"seed": &"berry", "color": Color(0.45, 0.3, 0.25), "desc": "Многолетний: после сбора снова плодоносит."})
	# ---------- травы ----------
	_item(&"herb", "Лечебная трава", &"resource", 20, 0.05,
		{"color": Color(0.35, 0.6, 0.35), "desc": "Из неё — припарка и отвар."})
	_item(&"poultice", "Припарка", &"food", 5, 0.1,
		{"health": 12.0, "sv": &"cure", "color": Color(0.4, 0.55, 0.3), "desc": "Снимает яд, лечит."})
	_item(&"herbal_tea", "Травяной отвар", &"food", 5, 0.4,
		{"thirst": 18.0, "health": 18.0, "sv": &"cure", "returns": &"coconut_shell", "color": Color(0.55, 0.5, 0.25),
		 "held": SurvivalModels.held_shell.bind(2.0), "desc": "Снимает яд, лечит и поит."})
	# ---------- мусор с берега ----------
	_item(&"barrel", "Бочка", &"build", 1, 6.0,
		{"kit": &"rain_barrel", "color": Color(0.5, 0.35, 0.2), "desc": "ПКМ — поставить: собирает дождевую воду."})
	_item(&"scrap_metal", "Ржавая жесть", &"resource", 20, 0.8,
		{"color": Color(0.55, 0.32, 0.18), "desc": "Из неё — котелок и нож."})
	_item(&"plastic_sheet", "Кусок плёнки", &"resource", 10, 0.1,
		{"color": Color(0.85, 0.9, 0.92), "desc": "Для солнечного опреснителя и тента."})
	_item(&"glass_shard", "Осколок стекла", &"resource", 20, 0.1,
		{"tool": &"knife", "damage": 5.0, "color": Color(0.6, 0.8, 0.75), "desc": "Режет волокно; ценится для опреснителя."})
	_item(&"plank", "Доска", &"resource", 20, 0.8,
		{"color": Color(0.6, 0.48, 0.32)})
	# ---------- наборы построек SURVIVAL (ПКМ — поставить) ----------
	_item(&"campfire_kit", "Костёр", &"build", 3, 2.0,
		{"kit": &"campfire", "color": Color(0.6, 0.35, 0.15), "desc": "ПКМ — сложить костёр. Палки — топливо."})
	_item(&"smoker_kit", "Коптильня", &"build", 1, 3.0,
		{"kit": &"smoker", "color": Color(0.45, 0.32, 0.2), "desc": "Сушилка над дымом: мясо и рыба хранятся долго."})
	_item(&"still_kit", "Солнечный опреснитель", &"build", 1, 1.5,
		{"kit": &"still", "color": Color(0.8, 0.88, 0.92), "desc": "Днём на солнце делает пресную воду из морской."})
	_item(&"tarp_kit", "Дождевой тент", &"build", 1, 2.0,
		{"kit": &"tarp", "color": Color(0.7, 0.68, 0.55), "desc": "Собирает дождь быстрее бочки, но держит меньше."})
	_item(&"garden_kit", "Грядка", &"build", 3, 2.0,
		{"kit": &"garden", "color": Color(0.4, 0.3, 0.2), "desc": "Единственная возобновляемая еда. Нужны семена и полив."})

	# ---------- рецепты ----------
	_recipe(&"r_campfire_kit", &"campfire_kit", {&"stick": 4, &"rock": 3}, 1)
	_recipe(&"r_garden_kit", &"garden_kit", {&"stick": 6, &"rope": 1}, 1)
	_recipe(&"r_smoker_kit", &"smoker_kit", {&"stick": 8, &"rope": 2, &"leaf": 6}, 1)
	_recipe(&"r_still_kit", &"still_kit", {&"plastic_sheet": 1, &"bottle_empty": 1, &"stick": 2, &"rock": 1}, 1)
	_recipe(&"r_tarp_kit", &"tarp_kit", {&"cloth": 3, &"rope": 2, &"stick": 4}, 1)
	_recipe(&"r_tarp_kit_plastic", &"tarp_kit", {&"plastic_sheet": 2, &"rope": 2, &"stick": 4}, 1)
	_recipe(&"r_pot", &"pot", {&"scrap_metal": 3, &"rope": 1}, 1)
	_recipe(&"r_knife", &"knife", {&"scrap_metal": 1, &"stick": 1, &"rope": 1}, 1)
	_recipe(&"r_fiber_net", &"fiber", {&"rope": 1}, 3)
	_recipe(&"r_poultice", &"poultice", {&"herb": 2, &"leaf": 1}, 1)
	_recipe(&"r_herbal_tea", &"herbal_tea", {&"herb": 2, &"shell_water": 1}, 1, &"campfire")
	_recipe(&"r_seed_melon", &"seed_melon", {&"melon": 1}, 3)
	_recipe(&"r_seed_taro", &"seed_taro", {&"taro": 1}, 2)
	_recipe(&"r_seed_maize", &"seed_maize", {&"maize": 1}, 4)
	_recipe(&"r_planks", &"stick", {&"plank": 1}, 2)
	# V5 (агент F): ёмкости, трут/огниво, соль — scripts/mech/mech_items.gd
	MechItems.register()

static func _item(id: StringName, nm: String, kind: StringName, stack: int, weight: float, data: Dictionary) -> void:
	if SPOIL.has(id) and not data.has("spoil"):
		data["spoil"] = SPOIL[id]
	var d := Items.get_item(id)
	if d == null:
		Items.register_item(id, nm, kind, stack, weight, data)
	else:
		for k in data.keys():
			if not d.data.has(k):
				d.data[k] = data[k]
		# Порча/кулинария — ответственность SURVIVAL: ставим всегда.
		for k in ["spoil", "cook", "smoke", "boil", "sv", "returns", "held", "fill_fresh", "fill_salt"]:
			if data.has(k):
				d.data[k] = data[k]

static func _recipe(id: StringName, out: StringName, needs: Dictionary, count: int, station: StringName = &"") -> void:
	if not Items.recipes.has(id):
		Items.register_recipe(id, out, needs, count, station)

static func data(id: StringName) -> Dictionary:
	var d := Items.get_item(id)
	return d.data if d else {}

static func spoil_minutes(id: StringName) -> float:
	return float(data(id).get("spoil", 0.0))
