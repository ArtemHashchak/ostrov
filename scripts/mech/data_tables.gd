class_name DataTables
## Таблицы баланса и свойств вне кода (A15): assets/data/*.json, кэш. Правка JSON — без
## перекомпиляции; DataTables.reload() — перечитать (консоль/тесты).
##   DataTables.get_value("balance", "temperature/noon_heat", 0.5)
##   DataTables.table("materials") -> Dictionary

const DIR := "res://assets/data/"
static var _cache: Dictionary = {}

static func table(name: String) -> Dictionary:
	if _cache.has(name):
		return _cache[name]
	var d := {}
	var path := DIR + name + ".json"
	if FileAccess.file_exists(path):
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if j is Dictionary:
			d = j
		else:
			push_warning("DataTables: не разобран %s" % path)
	_cache[name] = d
	return d

## Значение по пути «a/b/c» в таблице name.
static func get_value(name: String, key_path: String, default: Variant = null) -> Variant:
	var cur: Variant = table(name)
	for k in key_path.split("/"):
		if cur is Dictionary and (cur as Dictionary).has(k):
			cur = (cur as Dictionary)[k]
		else:
			return default
	return cur

static func f(name: String, key_path: String, default: float = 0.0) -> float:
	return float(get_value(name, key_path, default))

static func reload() -> void:
	_cache.clear()
	Materials.clear_cache()
