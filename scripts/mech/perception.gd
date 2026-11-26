extends Node
## Восприятие (A2) — автозагрузка Perception. Каждое действие создаёт «раздражитель» с
## радиусом и силой; животные и боты реагируют на раздражители, а не на прямую дистанцию.
##   Perception.emit(kind, pos, radius, strength=1, source=null) -> Dictionary
##   Perception.shot(pos, source)          — выстрел: первый на участке пугает на сотни метров
##   Perception.step(actor, pos, loud01)    — шаг (громкость по поверхности: Surfaces.loud_at)
##   Perception.blood(pos, strength)        — кровь (в воде — для акул: Sea.add_blood)
##   Perception.light(pos, radius) / smoke(pos, amount) — костры, фонари (видимость для ботов)
## Подписчики: сигнал stimulus или узлы группы &"perceiver" с методом on_stimulus(st).
## Встроенные реакции: стаи птиц (Fauna.flocks) улетают от выстрела/крика; крабы и пугливые
## животные (Animal, temper timid/_crab) — от громких шагов и выстрелов.
## Радиусы — assets/data/balance.json, раздел perception.

signal stimulus(st: Dictionary)

## Последние выстрелы по участкам: ключ клетки → время (с) — повторные выстрелы на участке
## не пугают так далеко (птицы уже улетели).
var _shot_cells: Dictionary = {}
var last: Array[Dictionary] = []
var _light_t := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

func bal(key: String, d: float) -> float:
	return DataTables.f("balance", "perception/" + key, d)

func _now() -> float:
	return Time.get_ticks_msec() * 0.001

func emit(kind: StringName, pos: Vector3, radius: float, strength: float = 1.0, source: Node = null) -> Dictionary:
	var st := {"kind": kind, "pos": pos, "radius": radius, "strength": strength,
		"source": source, "t": _now()}
	last.append(st)
	if last.size() > 64:
		last.pop_front()
	stimulus.emit(st)
	var tree := get_tree()
	if tree:
		for n in tree.get_nodes_in_group(&"perceiver"):
			if n is Node3D and n != source and n.has_method(&"on_stimulus") \
					and (n as Node3D).global_position.distance_to(pos) <= radius:
				n.call(&"on_stimulus", st)
	_react_builtin(st)
	return st

## Выстрел. Первый на участке (клетка shot_area_cell м) за shot_area_memory_s — радиус
## shot_radius (птицы взлетают на сотни метров), повторные — shot_repeat_radius.
func shot(pos: Vector3, source: Node = null, loud: float = 1.0) -> Dictionary:
	var cell := bal("shot_area_cell", 160.0)
	var key := Vector2i(floori(pos.x / cell), floori(pos.z / cell))
	var mem := bal("shot_area_memory_s", 90.0)
	var first := not _shot_cells.has(key) or _now() - float(_shot_cells[key]) > mem
	_shot_cells[key] = _now()
	var r := (bal("shot_radius", 450.0) if first else bal("shot_repeat_radius", 140.0)) * loud
	var st := emit(&"shot", pos, r, loud, source)
	st["first"] = first
	return st

func step(actor: Node, pos: Vector3, loud: float, mul: float = 1.0) -> Dictionary:
	return emit(&"step", pos, bal("step_radius", 22.0) * loud * mul, loud * mul, actor)

func blood(pos: Vector3, strength: float = 5.0, source: Node = null) -> Dictionary:
	var in_water := pos.y < BuildEnv.water_level()
	var r := bal("blood_water_radius", 90.0) if in_water else bal("blood_land_radius", 35.0)
	if in_water:
		var sea := get_tree().get_first_node_in_group(&"sea") if get_tree() else null
		if sea and sea.has_method(&"add_blood"):
			sea.call(&"add_blood", pos, strength, false)
	return emit(&"blood", pos, r * clampf(strength / 5.0, 0.5, 2.0), strength, source)

func light(pos: Vector3, radius: float, source: Node = null) -> Dictionary:
	return emit(&"light", pos, radius, 1.0, source)

func smoke(pos: Vector3, amount: float, source: Node = null) -> Dictionary:
	return emit(&"smoke", pos, bal("smoke_radius", 600.0) * clampf(amount, 0.0, 1.5), amount, source)

## Костры: ночью — свет, днём — дым (раз в 2 с).
func _process(delta: float) -> void:
	_light_t += delta
	if _light_t < 2.0:
		return
	_light_t = 0.0
	var tree := get_tree()
	if tree == null:
		return
	var w := BuildEnv.world()
	var night := w != null and w.has_method(&"is_night") and bool(w.call(&"is_night"))
	for f in tree.get_nodes_in_group(&"campfire"):
		if f is Node3D and bool(f.get(&"lit")):
			if night:
				light((f as Node3D).global_position, bal("fire_light_radius", 200.0), f)
			else:
				smoke((f as Node3D).global_position, float(f.get_meta(&"smoke_amount", 1.0)), f)

# ---------------- встроенные реакции ----------------

func _react_builtin(st: Dictionary) -> void:
	match StringName(st.kind):
		&"shot":
			_scare_flocks(st)
			_scare_animals(st, 1.0)
		&"step":
			_scare_animals(st, 0.0)

## Стаи птиц в радиусе: взлёт и перелёт прочь от источника на 150–260 м (Fauna.flocks).
func _scare_flocks(st: Dictionary) -> void:
	var fauna := Fauna.instance()
	if fauna == null:
		return
	var p: Vector3 = st.pos
	var r: float = st.radius
	for fl: Dictionary in fauna.flocks:
		var fp: Vector3 = fl.get("pos", Vector3.INF)
		if fp == Vector3.INF or Vector2(fp.x - p.x, fp.z - p.z).length() > r:
			continue
		if _now() < float(fl.get("spooked_until", 0.0)) and not bool(st.get("first", false)):
			continue
		var away := Vector3(fp.x - p.x, 0.0, fp.z - p.z)
		if away.length() < 1.0:
			away = Vector3(randf() - 0.5, 0.0, randf() - 0.5)
		away = away.normalized().rotated(Vector3.UP, randf_range(-0.5, 0.5))
		var dist := randf_range(150.0, 260.0)
		var tgt := fp + away * dist
		tgt.y = maxf(fp.y, BuildEnv.water_level()) + randf_range(16.0, 28.0)
		fl["mode"] = &"fly"
		fl["target"] = tgt
		fl["t"] = 0.0
		fl["legs"] = 2
		fl["spooked_until"] = _now() + bal("bird_flee_s", 45.0)
		fl["spooked_by"] = st.kind
		# сидящие на земле/кроне птицы — тоже в воздух
		for m in fl.get("members", []):
			if is_instance_valid(m) and m.has_method(&"_set_state") and not bool(m.get(&"dead")):
				m.call(&"_set_state", &"fly")

## Пугливые животные и крабы: убегают/зарываются, если раздражитель громче их «порога»
## (радиус раздражителя больше дистанции до них и больше их обычного flee_r).
func _scare_animals(st: Dictionary, shot_k: float) -> void:
	var fauna := Fauna.instance()
	if fauna == null:
		return
	var p: Vector3 = st.pos
	var r: float = st.radius
	var src: Node = st.source
	for a in fauna.animals_near(p, r):
		if a.dead or a.tamed:
			continue
		var tmp := StringName(a.cfg.get("temper", &""))
		var fr := float(a.cfg.get("flee_r", 0.0))
		if fr <= 0.0 or tmp == &"bird":
			continue
		var d := a.global_position.distance_to(p)
		if d <= fr and shot_k == 0.0:
			continue # рядом — справится собственная логика животного
		if a.species == &"crab":
			a.target = src as Node3D if src is Node3D else null
			a.call(&"_set_state", &"burrow" if randf() < 0.5 else &"flee")
		elif tmp in [&"timid", &"thief", &"hermit"]:
			a.target = src as Node3D if src is Node3D else null
			if a.target:
				a.call(&"_set_state", &"flee")
