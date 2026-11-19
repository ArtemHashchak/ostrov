class_name SeaSceneDirector
extends Node3D
## Режиссёр сцен моря: ставит у игрока маленькие «спектакли» морской жизни
## (SeaScenesLib.CATALOG — 34 сцены) по среде (глубина в точке), времени суток и погоде;
## реагирует на события: кровь в воде → акулы, шторм → муть и рыба ко дну, ночь → искры
## планктона вокруг пловца. Сцены живут только рядом с камерой (пузырь живности) и убираются,
## когда игрок уплыл или сцена кончилась. Цена — тики нескольких особей, без физики.

const MAX_BY_Q: Array[int] = [1, 2, 2, 3]     # одновременно сцен по пресету графики
const AUTO_EVERY := 6.0                        # как часто пробовать новую сцену, сек
const SPAWN_MIN := 9.0
const SPAWN_MAX := 22.0
const KEEP := 70.0                             # дальше — убрать сцену
const FAR_TICK := 0.25                         # вдали (> 35 м) — тик реже

var sea: Object = null           # water_y / floor_at / depth_at; у настоящего моря — Sea
var world: Node = null
var auto := true                 # сам ставит сцены у игрока
var forced_time := ""            # "", "day", "dusk", "night" — полигон/тест
var forced_storm := -1.0         # <0 — по погоде мира
var active: Array[SeaScene] = []
var started_total := 0
var _acc := 0.0
var _rng := RandomNumberGenerator.new()
var _seed := 1000
var _blood_cd := 0.0
var _storm_cd := 0.0
var _plankton_acc := 0.0
var _last_swim := Vector3.INF
var _far_acc := 0.0
var _recent: Array[String] = []

static func instance() -> SeaSceneDirector:
	var ml := Engine.get_main_loop() as SceneTree
	return ml.get_first_node_in_group(&"sea_scenes") as SeaSceneDirector if ml else null

func _ready() -> void:
	name = "SeaSceneDirector"
	add_to_group(&"sea_scenes")
	_rng.seed = 777
	if world == null:
		world = get_tree().get_first_node_in_group(&"world")

func _exit_tree() -> void:
	for s in active:
		if is_instance_valid(s):
			s.cleanup()
	active.clear()
	SeaCritter.clear_cache()
	SeaSchool.clear_cache()
	SeaProxyMeshes.clear_cache()
	SeaSceneFx.clear_cache()

# --- среда ------------------------------------------------------------------------

func water_y() -> float:
	return float(sea.call(&"water_y")) if sea else 0.0

func depth_at(x: float, z: float) -> float:
	return float(sea.call(&"depth_at", x, z)) if sea else 5.0

func hour() -> float:
	match forced_time:
		"day":
			return 12.0
		"dusk":
			return 18.6
		"night":
			return 23.5
	if world and world.has_method(&"time_of_day"):
		return float(world.call(&"time_of_day"))
	return 12.0

func is_night() -> bool:
	if forced_time != "":
		return forced_time == "night"
	if world and world.has_method(&"is_night"):
		return bool(world.call(&"is_night"))
	return false

func is_dusk() -> bool:
	var h := hour()
	return (h > 17.5 and h < 19.8) or (h > 5.3 and h < 6.8)

func storm() -> float:
	if forced_storm >= 0.0:
		return forced_storm
	if world and world.has_method(&"storm_intensity"):
		return float(world.call(&"storm_intensity"))
	return 0.0

func wind_dir() -> Vector2:
	if world and world.has_method(&"wind_dir"):
		return world.call(&"wind_dir")
	return Vector2(1, 0)

func _time_ok(t: String) -> bool:
	match t:
		"day":
			return not is_night()
		"night":
			return is_night()
		"dusk":
			return is_dusk()
	return true

func _weather_ok(w: String) -> bool:
	match w:
		"calm":
			return storm() < 0.35
		"storm":
			return storm() >= 0.45
	return true

# --- запуск -----------------------------------------------------------------------

## Поставить сцену id в точке pos (INF — подобрать место у камеры по глубине).
func play(id: String, pos: Vector3 = Vector3.INF) -> SeaScene:
	var info: Dictionary = SeaScenesLib.CATALOG.get(id, {})
	if info.is_empty():
		return null
	if pos == Vector3.INF:
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return null
		var spot: Variant = find_spot(info, cam.global_position, -cam.global_transform.basis.z)
		if spot == null:
			return null
		pos = spot
	var s := SeaScenesLib.make(id)
	if s == null:
		return null
	add_child(s)
	_seed += 1
	s.start(self, sea, pos, _seed * 131)
	active.append(s)
	started_total += 1
	_recent.push_front(id)
	if _recent.size() > 6:
		_recent.pop_back()
	return s

## Место для сцены: дно на нужной глубине в кольце вокруг камеры, лучше — впереди.
func find_spot(info: Dictionary, eye: Vector3, fwd: Vector3) -> Variant:
	var dr: Array = info.get("depth", [1.0, 20.0])
	var far := bool(info.get("far", false))
	var rmin := SPAWN_MIN if not far else 120.0
	var rmax := SPAWN_MAX if not far else 260.0
	var f2 := Vector2(fwd.x, fwd.z).normalized()
	var base := atan2(f2.y, f2.x) if f2.length() > 0.1 else 0.0
	for i in 16:
		var a := base + _rng.randf_range(-1.2, 1.2) * (1.0 if i < 10 else 2.6)
		var r := _rng.randf_range(rmin, rmax)
		var x := eye.x + cos(a) * r
		var z := eye.z + sin(a) * r
		var d := depth_at(x, z)
		if d >= float(dr[0]) and d <= float(dr[1]):
			var fl := water_y() - d
			return Vector3(x, fl, z)
	return null

## Место по глубине в кольцах вокруг center до r_max (полигон: сцена «где подходит»).
func find_spot_around(info: Dictionary, center: Vector3, r_max: float = 160.0) -> Variant:
	var dr: Array = info.get("depth", [1.0, 20.0])
	var r := 6.0
	while r <= r_max:
		var n := int(clampf(r * 0.5, 8.0, 48.0))
		var a0 := _rng.randf() * TAU
		for i in n:
			var a := a0 + TAU * i / n
			var x := center.x + cos(a) * r
			var z := center.z + sin(a) * r
			var d := depth_at(x, z)
			if d >= float(dr[0]) and d <= float(dr[1]):
				return Vector3(x, water_y() - d, z)
		r += 6.0
	return null

## Кораллы рифа рядом (укрытия, станции чистки): точки на верхушках кораллов.
func coral_spots(c: Vector3, r: float, k: int) -> Array:
	var out: Array = []
	var reefs: Object = sea.get(&"reefs") if sea is Object and sea.get(&"reefs") != null else null
	if reefs == null:
		return out
	var cells: Variant = reefs.get(&"_cells")
	if not (cells is Dictionary):
		return out
	var cell := 64.0
	var cx := int(floor(c.x / cell))
	var cz := int(floor(c.z / cell))
	var cand: Array = []
	for key: String in (cells as Dictionary).keys():
		var parts := key.split("|")
		if parts.size() < 3:
			continue
		var t := parts[0]
		if t == "grass" or t == "rock":
			continue
		if absi(int(parts[1]) - cx) > 1 or absi(int(parts[2]) - cz) > 1:
			continue
		for xf: Variant in ((cells as Dictionary)[key] as Dictionary).get("xf", []):
			var o := (xf as Transform3D).origin
			if o.distance_to(c) < r:
				cand.append(o + Vector3(0, (xf as Transform3D).basis.get_scale().y * 0.35, 0))
	cand.shuffle()
	for i in mini(k, cand.size()):
		out.append(cand[i])
	return out

# --- тик -----------------------------------------------------------------------------

func _process(delta: float) -> void:
	var pt := PerfStats.begin()
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam else Vector3.ZERO
	_far_acc += delta
	var far_step := _far_acc >= FAR_TICK
	for i in range(active.size() - 1, -1, -1):
		var s := active[i]
		if not is_instance_valid(s):
			active.remove_at(i)
			continue
		var d := s.at.distance_to(eye)
		if s.done or (auto and d > KEEP and not bool((SeaScenesLib.CATALOG.get(s.id, {}) as Dictionary).get("far", false))):
			s.cleanup()
			active.remove_at(i)
			continue
		if d < 35.0:
			s.tick(delta)
		elif far_step:
			s.tick(_far_acc)
	if far_step:
		_far_acc = 0.0
	if sea != null and cam != null:
		_reactions(delta, eye)
		if auto:
			_acc += delta
			if _acc >= AUTO_EVERY:
				_acc = 0.0
				_auto(eye, -cam.global_transform.basis.z)
	PerfStats.end(&"sea_scenes", pt)

## Сам ставит сцену у игрока, если он в воде или у берега и сцен меньше лимита.
func _auto(eye: Vector3, fwd: Vector3) -> void:
	var wy := water_y()
	var under := eye.y < wy
	var near_water := eye.y < wy + 12.0
	if not near_water:
		return
	var q := clampi(Settings.graphics_quality, 0, 3)
	if active.size() >= MAX_BY_Q[q]:
		return
	var pool: Array[String] = []
	for id: String in SeaScenesLib.CATALOG.keys():
		var info: Dictionary = SeaScenesLib.CATALOG[id]
		if bool(info.get("reaction", false)):
			continue
		if _recent.has(id):
			continue
		var view := String(info.get("view", "underwater"))
		if view == "underwater" and not under:
			continue
		if view == "surface" and under:
			continue
		if not _time_ok(String(info.get("time", "any"))) or not _weather_ok(String(info.get("weather", "any"))):
			continue
		pool.append(id)
	if pool.is_empty():
		return
	pool.shuffle()
	for id in pool:
		if play(id) != null:
			return

## Реакции моря: кровь → акулы, шторм → муть, ночь → искры планктона вокруг пловца.
func _reactions(dt: float, eye: Vector3) -> void:
	_blood_cd = maxf(_blood_cd - dt, 0.0)
	_storm_cd = maxf(_storm_cd - dt, 0.0)
	# кровь рядом (настоящее море ведёт список следов крови)
	if _blood_cd <= 0.0 and sea is Sea:
		for b: Dictionary in (sea as Sea)._blood:
			var p: Vector3 = b.get("pos", Vector3.INF)
			if p != Vector3.INF and p.distance_to(eye) < 40.0 and float(b.get("s", 0.0)) > 0.3:
				_blood_cd = 40.0
				var fl := water_y() - depth_at(p.x, p.z)
				play("blood_sharks", Vector3(p.x, fl, p.z))
				break
	if _storm_cd <= 0.0 and storm() >= 0.55 and eye.y < water_y():
		_storm_cd = 70.0
		play("storm_churn")
	# ночью пловец «зажигает» планктон
	_plankton_acc += dt
	if is_night() and _plankton_acc > 0.25:
		_plankton_acc = 0.0
		var pl := get_tree().get_first_node_in_group(&"player") as Node3D
		var sw := Vector3.INF
		if pl and pl.has_method(&"is_in_water") and bool(pl.call(&"is_in_water")):
			sw = pl.global_position + Vector3(0, 0.6, 0)
		elif eye.y < water_y():
			sw = eye
		if sw != Vector3.INF:
			var moved := _last_swim == Vector3.INF or sw.distance_to(_last_swim) > 0.15
			_last_swim = sw
			if moved:
				SeaSceneFx.sparkle(self, sw + Vector3(0, -0.2, 0), 0.6, 14)

## Строка для F3.
func perf_text() -> String:
	var us := 0.0
	for s in active:
		if is_instance_valid(s):
			us += s.cpu_us
	return "сцен %d · %.0f мкс" % [active.size(), us]

func stop_all() -> void:
	for s in active:
		if is_instance_valid(s):
			s.cleanup()
	active.clear()
