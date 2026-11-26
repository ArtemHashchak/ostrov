class_name UserHeld
extends RefCounted
## Модели пользователя для предметов в руке и на земле (v5, агент B): АК-47, мачете, топор, нож,
## фонарик, бутылка воды, зажигалка, жареное мясо на шпажке. Подменяют процедурные модели тех же
## предметов (id предметов не меняются): SupplyModels._build и HeldModels.build сначала спрашивают
## UserHeld.build(id). Файлы — assets/user_pack/{weapons,items}; импорт — tools/import_v5/*.
## Правило осей (HeldModels): начало — точка хвата, +Y — вдоль рукояти, −Z — вперёд.
## АК: узлы BoltCarrier / Trigger / Selector / Magazine + маркеры muzzle / ejection_port / ads_anchor
## (контракт docs/V5_AGENTS.md №3); детали двигает модуль COMBAT (агент F).

const DIR := "res://assets/user_pack/"
## id предмета → {file, pos, rot (градусы), scale}
const MODELS := {
	&"rifle": {"file": "weapons/ak47/weapon_ak47.glb"},
	&"machete": {"file": "weapons/melee/weapon_machete.glb"},
	&"axe_modern": {"file": "weapons/melee/weapon_axe.glb"},
	&"knife_combat": {"file": "weapons/melee/weapon_knife.glb"},
	&"flashlight": {"file": "items/item_flashlight.glb", "lens": Vector3(0, 0, -0.105)},
	&"water_bottle": {"file": "items/item_water_bottle.glb", "pos": Vector3(0, 0.02, 0)},
	&"bottle_empty": {"file": "items/item_water_bottle.glb", "pos": Vector3(0, 0.02, 0)},
	&"lighter": {"file": "items/item_lighter.glb", "scale": 1.3},
	&"meat_cooked": {"file": "items/item_meat_skewer.glb", "pos": Vector3(-0.055, -0.02, 0.0), "scale": 1.2},
}

## Выключатель (тесты «до/после», сравнение с процедурными моделями).
static var enabled := true
static var _scenes: Dictionary = {}

static func has(id: StringName) -> bool:
	if not enabled or not MODELS.has(id):
		return false
	return ResourceLoader.exists(DIR + String(MODELS[id]["file"]))

## Модель предмета (или null — тогда строится процедурная).
static func build(id: StringName) -> Node3D:
	if not has(id):
		return null
	var d: Dictionary = MODELS[id]
	var path := DIR + String(d["file"])
	if not _scenes.has(path):
		_scenes[path] = load(path) as PackedScene
	var ps: PackedScene = _scenes[path]
	if ps == null:
		return null
	var inst := ps.instantiate() as Node3D
	var root := Node3D.new()
	root.name = "User_" + String(id)
	root.add_child(inst)
	inst.position = d.get("pos", Vector3.ZERO)
	var r: Vector3 = d.get("rot", Vector3.ZERO)
	inst.rotation = Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z))
	inst.scale = Vector3.ONE * float(d.get("scale", 1.0))
	# сокеты прямо под корнем, как у процедурных (CombatModels.marker): ищутся find_child
	if d.has("lens"):
		var l := Marker3D.new()
		l.name = "Lens"
		l.position = d["lens"]
		root.add_child(l)
	root.set_meta(&"user_model", true)
	return root

## Предметы, которых раньше не было (модели пользователя без пары в игре): боевой нож, зажигалка.
static func register_items() -> void:
	if Items.get_item(&"knife_combat") == null and has(&"knife_combat"):
		Items.register_item(&"knife_combat", "Нож", &"weapon", 1, 0.25,
			{"tool": &"knife", "damage": 16.0, "held": Callable(UserHeld, "_held").bind(&"knife_combat"),
			"color": Color(0.35, 0.36, 0.38), "desc": "Нож из посылки спонсоров: режет, колет, разделывает."})
	if Items.get_item(&"lighter") == null and has(&"lighter"):
		Items.register_item(&"lighter", "Зажигалка", &"tool", 1, 0.06,
			{"tool": &"hand", "damage": 1.0, "held": Callable(UserHeld, "_held").bind(&"lighter"),
			"color": Color(0.2, 0.2, 0.22), "desc": "Бензиновая зажигалка: огонь с первого раза, если не намокла."})

static func _held(id: StringName) -> Node3D:
	return build(id)
