class_name Materials
## Материалы и свойства предметов (A4). Материал задаёт значения по умолчанию
## (assets/data/materials.json, полная схема), предмет может переопределить любое поле
## (assets/data/items_props.json). Поведение подключается постепенно; поля заведены все.
##   Materials.of(&"wood_dry") -> Dictionary всех полей материала
##   Materials.item(&"coconut") -> материал предмета + его переопределения (+ "material", "mass_kg"…)
##   Materials.prop(&"rifle", "glint", 0.0)
##   Materials.of_node(node) — по meta "material"/"item_id" узла или предка, иначе по группам

static var _items: Dictionary = {}

static func clear_cache() -> void:
	_items.clear()

static func of(mat_id: StringName) -> Dictionary:
	var t := DataTables.table("materials")
	var mats: Dictionary = t.get("materials", {})
	if mats.has(String(mat_id)):
		return mats[String(mat_id)]
	return t.get("defaults", {})

static func exists(mat_id: StringName) -> bool:
	return (DataTables.table("materials").get("materials", {}) as Dictionary).has(String(mat_id))

static func item(item_id: StringName) -> Dictionary:
	if _items.has(item_id):
		return _items[item_id]
	var ov: Dictionary = (DataTables.table("items_props").get("items", {}) as Dictionary).get(String(item_id), {})
	var mat := StringName(ov.get("material", _guess_material(item_id)))
	var r := of(mat).duplicate(true)
	r["material"] = String(mat)
	for k in ov.keys():
		r[k] = ov[k]
	if not r.has("mass_kg"):
		var d: Variant = Items.get_item(item_id) if Engine.get_main_loop() else null
		r["mass_kg"] = float(d.weight) if d else 1.0
	_items[item_id] = r
	return r

static func prop(item_id: StringName, key: String, default: Variant = null) -> Variant:
	return item(item_id).get(key, default)

## Материал предмета без записи в таблице — по виду предмета.
static func _guess_material(item_id: StringName) -> String:
	var s := String(item_id)
	if s.contains("meat"):
		return "meat"
	if s.contains("fish"):
		return "fish"
	if s.contains("wood") or s.contains("stick") or s.contains("log") or s.contains("plank"):
		return "wood_dry"
	if s.contains("stone") or s.contains("rock"):
		return "stone"
	if s.contains("rope") or s.contains("fiber"):
		return "rope_fiber"
	var d: Variant = Items.get_item(item_id) if Engine.get_main_loop() else null
	if d and d.kind == &"food":
		return "food_cooked"
	if d and (d.kind == &"weapon" or d.kind == &"tool"):
		return "metal_steel"
	return "wood_dry"

## Материал узла сцены: meta "material" / "item_id" у узла или предка; иначе по группам
## (как GunFx.surface_of).
static func of_node(n: Node) -> Dictionary:
	var cur := n
	for i in 6:
		if cur == null:
			break
		if cur.has_meta(&"material"):
			return of(StringName(cur.get_meta(&"material")))
		if cur.has_meta(&"item_id"):
			return item(StringName(cur.get_meta(&"item_id")))
		if cur.is_in_group(&"rocks") or cur.is_in_group(&"ore"):
			return of(&"stone")
		if cur.is_in_group(&"trees") or cur.is_in_group(&"log") or cur.is_in_group(&"buildable"):
			return of(&"wood_dry")
		if cur.is_in_group(&"wrecks") or cur.is_in_group(&"supply_crates"):
			return of(&"metal_steel")
		if cur.is_in_group(&"animals") or cur.is_in_group(&"characters") or cur.is_in_group(&"sharks"):
			return of(&"meat")
		cur = cur.get_parent()
	return of(&"wood_dry")

## Масса предмета с учётом намокания (wet 0..1).
static func mass(item_id: StringName, wet: float = 0.0) -> float:
	var it := item(item_id)
	return float(it.get("mass_kg", 1.0)) * lerpf(1.0, float(it.get("wet_weight_mul", 1.0)), clampf(wet, 0.0, 1.0))
