class_name PolygonExhibits
extends RefCounted
## Список экспонатов нового полигона (версия 5): ВСЕ модели игры, собранные
## динамически — каталог ассетов (assets/catalog/*.json, AssetCatalog) + реестры игры,
## которых ещё нет в каталоге (CreatureSpawner: фауна, птицы, море, деревья, ресурсы;
## Items — предметы и оружие; BuildDefs — постройки). Новая модель в каталоге или
## реестре появляется на полигоне сама, без правки этого файла.
##
## Экспонат: {id, name, section, src: "catalog"|"spawner"|"item"|"build", size: Vector3,
##   live: bool (есть «живая» версия в вольере/грядке), entry: Dictionary (запись источника)}

## Разделы (порядок = порядок полос музея с севера на юг; «море» — всегда у берега).
const SECTIONS: Array[Dictionary] = [
	{"id": &"animals", "name": "Животные"},
	{"id": &"birds", "name": "Птицы"},
	{"id": &"small", "name": "Рептилии, амфибии, насекомые"},
	{"id": &"plants", "name": "Растения"},
	{"id": &"trees", "name": "Деревья"},
	{"id": &"rocks", "name": "Камни и грунт"},
	{"id": &"items", "name": "Предметы, еда, транспорт"},
	{"id": &"characters", "name": "Персонажи"},
	{"id": &"weapons", "name": "Оружие и стрельбище"},
	{"id": &"buildings", "name": "Постройки"},
	{"id": &"sea", "name": "Море"},
]

## Категория каталога → раздел.
const CAT_SECTION := {
	"plant": &"plants", "tree": &"trees", "rock": &"rocks", "ground": &"rocks",
	"creature": &"animals", "bird": &"birds", "insect": &"small", "sea": &"sea",
	"item": &"items", "food": &"items", "vehicle": &"items", "weapon": &"weapons", "character": &"characters",
}

## Слова в id/названии, по которым животное уходит в «мелкие» (террариумы).
const SMALL_KEYS := ["snake", "змея", "python", "питон", "viper", "куфия", "lizard", "ящер", "iguana", "игуана",
	"varan", "варан", "komodo", "spider", "паук", "tarantula", "scorpion", "скорпион", "centipede", "сколопендр",
	"frog", "лягушк", "квакша", "древолаз", "salamander", "саламандр", "gecko", "геккон", "insect", "насеком",
	"butterfly", "бабочк", "crab", "краб", "hermit", "отшельник", "turtle", "черепах", "beetle", "жук"]

## Размеры по умолчанию (м), если в источнике их нет.
const DEFAULT_SIZE := {
	&"animals": Vector3(1.6, 1.2, 2.2), &"birds": Vector3(0.6, 0.5, 0.7), &"small": Vector3(0.6, 0.3, 1.0),
	&"plants": Vector3(1.4, 1.4, 1.4), &"trees": Vector3(6.0, 10.0, 6.0), &"rocks": Vector3(1.6, 1.0, 1.6),
	&"items": Vector3(0.6, 0.4, 0.6), &"characters": Vector3(0.7, 1.85, 0.5), &"weapons": Vector3(0.9, 0.3, 0.3),
	&"buildings": Vector3(3.5, 3.0, 3.5), &"sea": Vector3(1.2, 0.6, 1.8),
}

static var _cache: Array = []
static var _cached := false

static func reset() -> void:
	_cached = false
	_cache.clear()

static func section_name(id: StringName) -> String:
	for s in SECTIONS:
		if s.id == id:
			return String(s.name)
	return String(id)

static func catalog_script() -> Script:
	const P := "res://scripts/core/asset_catalog.gd"
	return load(P) as Script if ResourceLoader.exists(P) else null

## Все экспонаты (кэш на запуск игры; reset() — пересобрать).
static func all() -> Array:
	if _cached:
		return _cache
	_cached = true
	_cache = collect()
	return _cache

static func of_section(sec: StringName) -> Array:
	return all().filter(func(e: Dictionary) -> bool: return e.section == sec)

static func collect() -> Array:
	var out: Array = []
	var seen := {}
	# 1. каталог ассетов (A12) — главный источник
	var cs := catalog_script()
	if cs:
		for e: Dictionary in cs.call(&"entries"):
			var cat := String(e.get("category", ""))
			if not CAT_SECTION.has(cat):
				continue
			var sec: StringName = CAT_SECTION[cat]
			if cat == "creature" and _is_small(String(e.id), String(e.get("name", ""))):
				sec = &"small"
			var sz := _size(e.get("size_m", null), sec)
			out.append({"id": String(e.id), "name": String(e.get("name", e.id)), "section": sec, "src": "catalog",
				"size": sz, "live": sec in [&"animals", &"birds", &"small", &"sea", &"plants", &"trees", &"rocks"],
				"entry": e, "ground": cat == "ground"})
			seen[String(e.id)] = true
	# 2. реестр существ и растений игры (CreatureSpawner) — всё, чего нет в каталоге
	for d: Dictionary in CreatureSpawner.all_species():
		var id := String(d.id)
		if seen.has(id):
			continue
		var sec := _spawner_section(d)
		if sec == &"":
			continue
		out.append({"id": id, "name": String(d.name), "section": sec, "src": "spawner",
			"size": DEFAULT_SIZE[sec], "live": true, "entry": d})
		seen[id] = true
	# 3. предметы и оружие (Items): на столах (их можно брать). Посылки спонсоров
	# регистрируются модулем Supply — на полигоне нужны все, поэтому регистрируем сразу.
	SupplyItems.register()
	for id: StringName in Items.items:
		var it := Items.get_item(id)
		if it == null or id == &"flag" or seen.has(String(id)):
			continue
		var weapon := it.kind == &"weapon" or it.kind == &"ammo" or Combat.is_weapon(id)
		out.append({"id": String(id), "name": Items.item_name(id), "section": &"weapons" if weapon else &"items",
			"src": "item", "size": DEFAULT_SIZE[&"items"], "live": false, "entry": {"kind": String(it.kind)}})
		seen[String(id)] = true
	# 4. постройки
	for bid: StringName in BuildDefs.ORDER:
		var info: Dictionary = BuildDefs.INFO.get(bid, {})
		out.append({"id": "build_" + String(bid), "name": String(info.get("name", bid)), "section": &"buildings",
			"src": "build", "size": DEFAULT_SIZE[&"buildings"], "live": false, "entry": {"def": bid}})
	return out

static func _is_small(id: String, nm: String) -> bool:
	var s := (id + " " + nm).to_lower()
	for k: String in SMALL_KEYS:
		if s.contains(k):
			return true
	return false

static func _spawner_section(d: Dictionary) -> StringName:
	var cat := String(d.get("cat", ""))
	var src := String(d.get("src", ""))
	match cat:
		"animals":
			return &"small" if _is_small(String(d.id), String(d.name)) else &"animals"
		"birds":
			return &"birds"
		"sea":
			return &"sea"
		"plants":
			match src:
				"tree":
					return &"trees"
				"rock":
					return &"rocks"
				"sea_plant":
					return &"sea"
				_:
					return &"plants"
	return &""

static func _size(v: Variant, sec: StringName) -> Vector3:
	if v is Array and (v as Array).size() >= 3:
		var a: Array = v
		return Vector3(maxf(0.05, float(a[0])), maxf(0.05, float(a[1])), maxf(0.05, float(a[2])))
	return DEFAULT_SIZE[sec]
