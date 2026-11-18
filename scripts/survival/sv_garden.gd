class_name SvGarden
extends SvStation
## Грядка: единственная возобновляемая еда.
## Посадка (семена), полив (пресная вода из тары; дождь поливает сам; морская губит),
## удобрение (гниль → быстрее рост), рост со стадиями 0..4 и визуалом, увядание без воды,
## урожай (ягодник — многолетний, снова плодоносит).

const CROPS := {
	&"taro": {"name": "Таро", "grow": 22.0 * 60.0, "yield": {&"taro": 3, &"seed_taro": 1}},
	&"maize": {"name": "Кукуруза", "grow": 18.0 * 60.0, "yield": {&"maize": 4, &"seed_maize": 2}},
	&"melon": {"name": "Дыня", "grow": 20.0 * 60.0, "yield": {&"melon": 2, &"seed_melon": 2}},
	&"berry": {"name": "Ягодник", "grow": 16.0 * 60.0, "regrow": 8.0 * 60.0, "yield": {&"berries": 6, &"seed_berry": 1}},
}
const DRY_TIME := 14.0 * 60.0     # от полного полива до сухой земли
const WILT_TIME := 6.0 * 60.0     # сухая земля → растение погибло
const DRY_LEVEL := 0.15
const PLANTS := 3

var crop: StringName = &""
var growth := 0.0        # 0..1
var moisture := 0.35
var health := 1.0        # 0 — погибло
var fertile := 0.0       # секунд ускоренного роста (удобрение)
var harvests := 0
var soil_factor := 1.0   # песок — медленнее
var _bed: MeshInstance3D
var _plants: Node3D
var _vis_key := ""

func _ready() -> void:
	kind = &"garden"
	name = "SvGarden"
	max_hp = 40.0
	hp = max_hp
	salvage = {&"stick": 3}
	model = Node3D.new()
	add_child(model)
	_bed = SurvivalModels.garden_bed(model)
	_plants = Node3D.new()
	add_child(_plants)
	add_shape(Vector3(1.9, 0.3, 1.2))
	_refresh()

func stage() -> int:
	if crop == &"":
		return -1
	return 4 if growth >= 1.0 else int(floor(growth * 4.0))

func is_ready() -> bool:
	return crop != &"" and growth >= 1.0 and health > 0.0

func is_dead() -> bool:
	return crop != &"" and health <= 0.0

func wilt() -> float:
	return clampf(1.0 - health, 0.0, 1.0) if crop != &"" else 0.0

func tick(dt: float) -> void:
	var rain := Survival.rain()
	moisture = clampf(moisture - dt / DRY_TIME + rain * dt / 30.0, 0.0, 1.0)
	if crop != &"" and health > 0.0:
		if moisture > DRY_LEVEL:
			health = minf(1.0, health + dt / 120.0)
			if growth < 1.0:
				var g := float(CROPS[crop].grow) if harvests == 0 else float(CROPS[crop].get("regrow", CROPS[crop].grow))
				var mul := soil_factor * (1.6 if fertile > 0.0 else 1.0) * clampf(0.5 + moisture, 0.6, 1.2)
				growth = minf(1.0, growth + dt * mul / g)
				fertile = maxf(0.0, fertile - dt)
		else:
			health = maxf(0.0, health - dt / WILT_TIME)
	_refresh()

func _refresh() -> void:
	var pkey := "%s|%d|%d" % [crop, stage(), int(wilt() * 4.0)]
	var key := "%s|%d" % [pkey, int(moisture * 4.0)]
	if key == _vis_key:
		return
	var plants_changed := not _vis_key.begins_with(pkey + "|")
	_vis_key = key
	var sm := SurvivalModels.soil(moisture)
	for c in model.get_children():
		if c.has_meta(&"soil"):
			(c as MeshInstance3D).material_override = sm
	if not plants_changed:
		return
	for c in _plants.get_children():
		c.queue_free()
	if crop == &"":
		return
	for i in PLANTS:
		var p := SurvivalModels.plant(crop, stage(), wilt(), int(get_instance_id() % 1000) * 7 + i)
		p.position = Vector3(-0.6 + i * 0.6, 0.12, (0.12 if i % 2 == 0 else -0.12))
		p.rotation.y = float(i) * 2.1
		if is_dead():
			p.scale = Vector3(1.0, 0.55, 1.0)
		_plants.add_child(p)

# ----------------------------------------------------- действия

func get_interact_text(ch: Node) -> String:
	var h := held(ch)
	var info := "Грядка"
	if crop != &"":
		info = "%s (%s, рост %d%%, влага %d%%)" % [info, CROPS[crop].name, int(growth * 100.0), int(moisture * 100.0)]
	else:
		info += " (пусто, влага %d%%)" % int(moisture * 100.0)
	if is_dead():
		return info + " — засохло. E: убрать"
	if is_ready():
		return info + " — E: собрать урожай"
	if Survival.data(h).has("thirst") and Survival.data(h).has("returns"):
		return info + " — E: полить из «%s»" % iname(h)
	if h == &"rotten_food":
		return info + " — E: удобрить гнилью"
	if crop == &"":
		var s := _first_seed(ch)
		return info + (" — E: посадить «%s»" % iname(s) if s != &"" else " — нужны семена")
	if moisture <= DRY_LEVEL:
		return info + " — сохнет! Полей пресной водой"
	return info

func _first_seed(ch: Node) -> StringName:
	var h := held(ch)
	if Survival.data(h).has("seed"):
		return h
	var inv := Survival.inv(ch)
	if inv:
		for s in inv.slots:
			if not s.is_empty() and Survival.data(StringName(s.id)).has("seed"):
				return StringName(s.id)
	return &""

func interact(ch: Node) -> void:
	var h := held(ch)
	if is_dead():
		clear()
		toast(ch, "Грядка расчищена")
		return
	if is_ready():
		harvest(ch)
		return
	if Survival.data(h).has("thirst") and Survival.data(h).has("returns"):
		water(ch, h)
		return
	if h == &"rotten_food":
		fertilize(ch)
		return
	if crop == &"":
		var s := _first_seed(ch)
		if s != &"":
			plant(ch, s)
		else:
			toast(ch, "Нужны семена: дикие растения, ящики с берега, урожай")

func plant(ch: Node, seed_id: StringName) -> bool:
	if crop != &"":
		return false
	var c := StringName(Survival.data(seed_id).get("seed", &""))
	if c == &"" or not CROPS.has(c):
		return false
	if ch and not Survival.take(ch, seed_id, 1):
		return false
	crop = c
	growth = 0.0
	health = 1.0
	harvests = 0
	_vis_key = ""
	_refresh()
	toast(ch, "Посажено: %s" % CROPS[c].name)
	return true

## Полить из тары (пресная — +влага; морская — губит растение).
func water(ch: Node, id: StringName) -> bool:
	var dd := Survival.data(id)
	if not dd.has("returns") or not Survival.take(ch, id, 1):
		return false
	Survival.give(ch, StringName(dd.returns), 1)
	if StringName(dd.get("sv", &"")) == &"salt_water":
		moisture = minf(1.0, moisture + 0.3)
		if crop != &"":
			health = maxf(0.0, health - 0.5)
		toast(ch, "Солёная вода губит растения!")
	else:
		moisture = 1.0
		toast(ch, "Полито")
	Survival.sfx(global_position, "res://assets/sounds/sfx-kit/props-splash.wav")
	_refresh()
	return true

func fertilize(ch: Node) -> bool:
	if not Survival.take(ch, &"rotten_food", 1):
		return false
	fertile += 6.0 * 60.0
	toast(ch, "Удобрено — растёт быстрее")
	return true

func harvest(ch: Node) -> Dictionary:
	if not is_ready():
		return {}
	var y: Dictionary = CROPS[crop].yield
	for id in y.keys():
		Survival.give(ch, StringName(id), int(y[id]), global_position + Vector3.UP * 0.5)
	harvests += 1
	if crop == &"berry":
		growth = 0.55 # куст остаётся, ягоды отрастут
	else:
		clear()
	_vis_key = ""
	_refresh()
	return y

func clear() -> void:
	crop = &""
	growth = 0.0
	health = 1.0
	harvests = 0
	_vis_key = ""
	_refresh()
