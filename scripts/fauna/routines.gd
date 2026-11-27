class_name Routines
extends RefCounted
## Распорядок дня видов (A13, v5.2). Данные — assets/data/routines.json.
##   Routines.mode(&"iguana", 8.0, true)  -> &"bask" | &"active" | &"rest" | &"hidden"
##   Routines.activity(&"shark", 18.5)    -> множитель активности (акулы на закате 1.5)
##   Routines.now(node)                   -> {hour, low_tide} текущего мира
## Вид без записи — всегда active.

## Тесты/консоль: принудительный час суток (−1 — по миру).
static var debug_hour: float = -1.0

static func _entry(sp: StringName) -> Dictionary:
	var t := DataTables.table("routines")
	var e: Variant = t.get(String(sp), {})
	return e if e is Dictionary else {}

static func _in(h: float, a: float, b: float) -> bool:
	return (h >= a and h < b) if a <= b else (h >= a or h < b)

static func _window(sp: StringName, hour: float, low_tide: bool) -> Dictionary:
	var e := _entry(sp)
	for w: Variant in e.get("windows", []):
		if not w is Dictionary:
			continue
		var tide := String((w as Dictionary).get("tide", "any"))
		if tide == "low" and not low_tide:
			continue
		if tide == "high" and low_tide:
			continue
		if _in(hour, float(w.get("from", 0.0)), float(w.get("to", 24.0))):
			return w
	return {}

static func mode(sp: StringName, hour: float, low_tide: bool) -> StringName:
	var w := _window(sp, hour, low_tide)
	if not w.is_empty():
		return StringName(String(w.get("mode", "active")))
	return StringName(String(_entry(sp).get("default", "active")))

static func activity(sp: StringName, hour: float, low_tide: bool = false) -> float:
	var w := _window(sp, hour, low_tide)
	if w.has("activity"):
		return float(w["activity"])
	match mode(sp, hour, low_tide):
		&"rest":
			return 0.7
		&"hidden":
			return 0.4
		&"bask":
			return 0.5
	return 1.0

## Час суток и отлив текущего мира (без мира — полдень, средний прилив).
static func now(n: Node) -> Dictionary:
	var w: Node = Fauna._world_of(n) if Fauna.instance() else null
	if w == null:
		w = BuildEnv.world()
	var hour := 12.0
	var low := false
	if w:
		if w.has_method(&"time_of_day"):
			hour = float(w.call(&"time_of_day"))
		if w.has_method(&"water_level"):
			var amp: Variant = w.get(&"tide_amplitude")
			var surge := float(w.call(&"storm_surge")) if w.has_method(&"storm_surge") else 0.0
			low = float(w.call(&"water_level")) - surge < -(float(amp) if amp != null else 0.8) * 0.2
	var f := Fauna.instance()
	if f and f.force_night:
		hour = 23.0
	if debug_hour >= 0.0:
		hour = debug_hour
	return {"hour": hour, "low_tide": low}

static func mode_now(sp: StringName, n: Node) -> StringName:
	var t := now(n)
	return mode(sp, t.hour, t.low_tide)
