class_name SeaSpecies
extends RefCounted
## Реестр видов морской живности — данные, а не код. Каждый вид — словарь:
##   id            — уникальный ключ ("sardine")
##   name          — название по-русски
##   category      — "small" | "medium" | "large" (бюджеты: ≤1.5k / ≤5k / ≤12k треуг.)
##   biome         — массив из "reef", "lagoon", "deep", "mangrove", "any"
##   depth         — [мин, макс] глубина дна, м
##   school        — [мин, макс] особей в группе (1 — одиночка)
##   groups        — сколько групп в среднем на ячейку 64×64 м подходящего биома
##   anim          — "fish" | "eel" | "ray" | "jelly" | "static" | "vat" (анимация в шейдере)
##   mesh          — путь к .glb/.tscn/.res (пусто — процедурная рыбка)
##   length        — длина тела, м (масштаб модели приводится к ней)
##   speed         — скорость по маршруту, м/с
##   roam          — радиус маршрута группы, м
##   colors        — оттенки процедурной модели (если mesh пуст)
##   min_quality   — с какого пресета показывать (0 низкое … 3 ультра)
##   vat           — путь к .res с запечённой анимацией (anim = "vat")
##   forward       — ось «вперёд» модели: "-z" (по умолчанию, как в Godot) или "+z"/"+x"/"-x"
## Встроенные виды ниже; свои добавляются в res://assets/sea_species.json
## (массив таких же словарей) — код менять не нужно. Вид с тем же id заменяет встроенный.

const USER_FILE := "res://assets/sea_species.json"

const BUILTIN: Array[Dictionary] = [
	{"id": "sardine", "name": "Сардины", "category": "small", "biome": ["deep", "lagoon"],
		"depth": [4.0, 40.0], "school": [40, 90], "groups": 1.2, "anim": "fish", "mesh": "",
		"length": 0.2, "speed": 2.2, "roam": 14.0, "colors": [Color(0.78, 0.82, 0.86), Color(0.62, 0.68, 0.76)],
		"min_quality": 0},
	{"id": "surgeonfish", "name": "Рыба-хирург", "category": "small", "biome": ["reef"],
		"depth": [1.0, 10.0], "school": [6, 16], "groups": 3.0, "anim": "fish", "mesh": "",
		"length": 0.26, "speed": 0.9, "roam": 6.0, "colors": [Color(0.2, 0.45, 0.95), Color(0.95, 0.85, 0.2)],
		"min_quality": 0},
	{"id": "parrotfish", "name": "Рыба-попугай", "category": "small", "biome": ["reef"],
		"depth": [1.0, 12.0], "school": [1, 4], "groups": 2.0, "anim": "fish", "mesh": "",
		"length": 0.45, "speed": 0.6, "roam": 7.0, "colors": [Color(0.25, 0.8, 0.6), Color(0.85, 0.35, 0.55)],
		"min_quality": 1},
	{"id": "barracuda", "name": "Барракуда", "category": "medium", "biome": ["lagoon", "reef", "deep"],
		"depth": [3.0, 30.0], "school": [3, 9], "groups": 0.6, "anim": "fish", "mesh": "",
		"length": 1.1, "speed": 1.4, "roam": 18.0, "colors": [Color(0.7, 0.74, 0.78)],
		"min_quality": 1},
	{"id": "moray", "name": "Мурена", "category": "medium", "biome": ["reef"],
		"depth": [2.0, 15.0], "school": [1, 1], "groups": 1.0, "anim": "eel", "mesh": "",
		"length": 1.3, "speed": 0.35, "roam": 3.0, "colors": [Color(0.45, 0.42, 0.18)],
		"min_quality": 2},
]

static var _list: Array[Dictionary] = []
static var _by_id: Dictionary = {}

static func all() -> Array[Dictionary]:
	if _list.is_empty():
		reload()
	return _list

static func get_species(id: String) -> Dictionary:
	if _list.is_empty():
		reload()
	return _by_id.get(id, {})

static func reload() -> void:
	_list.clear()
	_by_id.clear()
	for d in BUILTIN:
		_add(d.duplicate(true))
	if FileAccess.file_exists(USER_FILE):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(USER_FILE))
		if data is Array:
			for d: Variant in data:
				if d is Dictionary and (d as Dictionary).has("id"):
					_add(_normalize(d as Dictionary))
		else:
			push_warning("SeaSpecies: %s — ожидался массив видов" % USER_FILE)

static func _add(d: Dictionary) -> void:
	var id := String(d.id)
	if _by_id.has(id):
		_list.erase(_by_id[id])
	_list.append(d)
	_by_id[id] = d

## Значения по умолчанию для видов из JSON (цвета — строки "#rrggbb").
static func _normalize(d: Dictionary) -> Dictionary:
	var r := {"name": d.get("id"), "category": "small", "biome": ["any"], "depth": [1.0, 40.0],
		"school": [1, 1], "groups": 0.5, "anim": "fish", "mesh": "", "length": 0.4, "speed": 1.0,
		"roam": 8.0, "colors": [Color(0.7, 0.7, 0.7)], "min_quality": 0, "vat": "", "forward": "-z"}
	r.merge(d, true)
	var cols: Array = []
	for c: Variant in r.colors:
		cols.append(Color(c) if c is String else c)
	r.colors = cols
	return r

## Подходит ли вид месту: биом и глубина дна.
static func fits(d: Dictionary, biome: String, depth: float) -> bool:
	var dep: Array = d.depth
	if depth < float(dep[0]) or depth > float(dep[1]):
		return false
	var b: Array = d.biome
	return b.has("any") or b.has(biome)
