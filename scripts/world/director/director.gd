class_name LandDirector
extends Node3D
## Режиссёр сценок на суше (A7, v5.2): ставит маленькие «спектакли» живой природы ТОЛЬКО там,
## где их видит игрок — в поле зрения камеры, в 15–60 м, — по зоне острова (ZoneMap), времени
## суток, погоде и приливу. Сценка живёт десятки секунд и убирается, когда кончилась или игрок
## ушёл. Актёры — обычные Animal (модели и клипы пользователя/процедурные), «scripted»:
## своё мышление выключено, движением управляет сценка. Новых анимаций нет.
##
## Полигон: кнопки «Сценки режиссёра» (PolygonPanel) зовут статические scene_ids()/trigger().
## Консоль: scene <id>. Тест: tests/test_v52_director.gd.

const MAX_ACTIVE := 2
const AUTO_EVERY := 11.0        # как часто пробовать новую сценку, сек
const VIEW_MIN := 15.0
const VIEW_MAX := 60.0
const VIEW_HALF_ANGLE := 0.62   # рад (≈ ±35° от взгляда)
const KEEP := 95.0              # дальше — сценку убрать

## id → {title, zones, time, water}
##   zones — имена зон ZoneMap, где ставится центр сценки (пусто — любая суша);
##   time  — "day" (7–17.5), "morning" (6–11), "dusk" (17.5–20.5), "night" (20–5.5),
##           "night_dusk", "day_dusk", "not_night", "any";
##   water — центр сценки на воде у берега (глубина 2–15 м, до берега < 140 м).
const CATALOG := {
	"gull_crab_drop": {"title": "Чайка бросает краба на камни", "zones": [&"beach", &"rocks", &"dunes"], "time": "day"},
	"hatchlings": {"title": "Черепашата бегут к морю", "zones": [&"beach", &"dunes"], "time": "night_dusk"},
	"monitor_carcass": {"title": "Варан у туши", "zones": [&"lowland_forest", &"palm_belt", &"beach", &"meadow", &"jungle", &"dunes"], "time": "day"},
	"crab_march": {"title": "Ход крабов к морю", "zones": [&"beach", &"palm_belt", &"lowland_forest", &"dunes"], "time": "night_dusk"},
	"bat_emergence": {"title": "Летучие мыши вылетают на охоту", "zones": [&"rocks", &"jungle", &"lowland_forest", &"volcanic"], "time": "dusk"},
	"gulls_fight": {"title": "Чайки дерутся за рыбу", "zones": [&"beach", &"dunes"], "time": "day"},
	"iguanas_bask": {"title": "Игуаны греются на солнце", "zones": [&"rocks", &"beach", &"dunes", &"volcanic"], "time": "morning"},
	"parrots_flock": {"title": "Стая попугаев садится на крону", "zones": [&"jungle", &"lowland_forest", &"palm_belt"], "time": "day_dusk"},
	"boar_family": {"title": "Кабаны роют землю", "zones": [&"lowland_forest", &"jungle", &"meadow", &"palm_belt"], "time": "day"},
	"hermit_shell": {"title": "Раки-отшельники у пустой раковины", "zones": [&"beach", &"dunes"], "time": "day_dusk"},
	"snake_hunt": {"title": "Змея охотится на саламандру", "zones": [&"jungle", &"lowland_forest", &"freshwater", &"meadow"], "time": "not_night"},
	"turtle_nesting": {"title": "Черепаха откладывает яйца", "zones": [&"beach", &"dunes"], "time": "night"},
	"gulls_fish": {"title": "Чайки над косяком рыбы", "zones": [], "time": "day", "water": true},
	"air_chase": {"title": "Погоня в воздухе: чайку грабят на лету", "zones": [], "time": "day", "water": true},
	"monitor_shore": {"title": "Варан патрулирует берег", "zones": [&"beach", &"mangrove", &"palm_belt"], "time": "day"},
	"crabs_low_tide": {"title": "Крабы вышли на обнажившийся риф", "zones": [&"beach"], "time": "not_night", "low_tide": true},
}

var world: Node = null
var auto := true
var active: Array[LandScene] = []
var started_total := 0
var started_by_id := {}
## Мёртвые актёры остаются тушками (для падальщиков/мух/варана) — тикаем их, пока не исчезнут.
var leftovers: Array[Node3D] = []
var actors_root: Node3D
var forced_hour := -1.0          # тесты/полигон
var _acc := 3.0
var _rng := RandomNumberGenerator.new()
var _recent: Array[String] = []

static var _inst: LandDirector = null

static func instance() -> LandDirector:
	return _inst if _inst != null and is_instance_valid(_inst) else null

## Список сценок для полигона (кнопки). Возвращает id.
static func is_test_run() -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--test="):
			return true
	return false

static func scene_ids() -> Array:
	return CATALOG.keys()

static func scene_title(id: String) -> String:
	return String(CATALOG.get(id, {}).get("title", id))

## Запустить сценку id у точки pos (полигон/консоль). Режиссёр создаётся, если его нет.
static func trigger(id: String, pos: Variant = null) -> LandScene:
	var d := instance()
	if d == null:
		var ml := Engine.get_main_loop() as SceneTree
		if ml == null or ml.current_scene == null:
			return null
		d = LandDirector.new()
		d.auto = false
		ml.current_scene.add_child(d)
	var p: Vector3
	if pos is Vector3:
		p = pos
	else:
		p = d._view_point(25.0)
	return d.start(id, p, true)

func _enter_tree() -> void:
	_inst = self

func _ready() -> void:
	name = "LandDirector"
	add_to_group(&"land_director")
	_rng.randomize()
	actors_root = Node3D.new()
	actors_root.name = "Actors"
	add_child(actors_root)
	if world == null:
		world = get_tree().get_first_node_in_group(&"world")

func _exit_tree() -> void:
	if _inst == self:
		_inst = null

# --------------------------------------------------------------------- среда

func hour() -> float:
	if forced_hour >= 0.0:
		return forced_hour
	if world and is_instance_valid(world) and world.has_method(&"time_of_day"):
		return float(world.call(&"time_of_day"))
	return 12.0

func time_ok(t: String, h: float = -1.0) -> bool:
	if h < 0.0:
		h = hour()
	var day := h >= 7.0 and h < 17.5
	var morning := h >= 6.0 and h < 11.0
	var dusk := h >= 17.5 and h < 20.5
	var night := h >= 20.0 or h < 5.5
	match t:
		"day":
			return day
		"morning":
			return morning
		"dusk":
			return dusk
		"night":
			return night
		"night_dusk":
			return night or dusk
		"day_dusk":
			return day or dusk
		"not_night":
			return not night
	return true

func ground(x: float, z: float) -> float:
	if world and is_instance_valid(world) and world.has_method(&"height_at"):
		return float(world.call(&"height_at", x, z))
	return 0.0

func water_y() -> float:
	if world and is_instance_valid(world) and world.has_method(&"water_level"):
		return float(world.call(&"water_level"))
	return 0.0

func zones() -> ZoneMap:
	if world and is_instance_valid(world):
		var z: Variant = world.get(&"zones")
		if z is ZoneMap:
			return z
	return null

func zone_at(x: float, z: float) -> StringName:
	var zm := zones()
	if zm and zm.inside(x, z):
		return zm.zone_name_at(x, z)
	var g := ground(x, z)
	var wl := water_y()
	if g < wl:
		return &"ocean" if g < wl - 2.0 else &"shallows"
	return &"beach" if g < wl + 1.4 else &"lowland_forest"

func is_water(x: float, z: float) -> bool:
	return ground(x, z) < water_y() - 0.05

func storm() -> float:
	if world and is_instance_valid(world) and world.has_method(&"storm_intensity"):
		return float(world.call(&"storm_intensity"))
	return 0.0

func low_tide() -> bool:
	if world and is_instance_valid(world) and world.has_method(&"water_level"):
		var amp := float(world.get(&"tide_amplitude")) if world.get(&"tide_amplitude") != null else 0.8
		return float(world.call(&"water_level")) < -amp * 0.45
	return false

## Ближайшая к from точка воды (глубже 0.3 м) в радиусе r: 24 луча. INF — нет.
func find_water(from: Vector3, r: float = 45.0) -> Vector3:
	var best := Vector3.INF
	var best_d := INF
	for i in 24:
		var dir := Vector2.from_angle(TAU * i / 24.0)
		var d := 2.0
		while d <= r:
			var p := Vector2(from.x, from.z) + dir * d
			if ground(p.x, p.y) < water_y() - 0.3:
				if d < best_d:
					best_d = d
					best = Vector3(p.x, water_y(), p.y)
				break
			d += 2.0
	return best

## Ближайшая суша (выше воды на 0.4 м) от точки на воде.
func find_land(from: Vector3, r: float = 140.0) -> Vector3:
	var best := Vector3.INF
	var best_d := INF
	for i in 24:
		var dir := Vector2.from_angle(TAU * i / 24.0)
		var d := 3.0
		while d <= r:
			var p := Vector2(from.x, from.z) + dir * d
			var g := ground(p.x, p.y)
			if g > water_y() + 0.4:
				if d < best_d:
					best_d = d
					best = Vector3(p.x, g, p.y)
				break
			d += 3.0
	return best

func camera() -> Camera3D:
	return get_viewport().get_camera_3d() if is_inside_tree() else null

func player_pos() -> Vector3:
	var pl := get_tree().get_first_node_in_group(&"player") as Node3D
	if pl:
		return pl.global_position
	var c := camera()
	return c.global_position if c else Vector3.ZERO

## Точка в поле зрения на расстоянии dist (по взгляду камеры, на земле).
func _view_point(dist: float) -> Vector3:
	var c := camera()
	if c == null:
		return Vector3(0, ground(0, 0), -dist)
	var f := -c.global_transform.basis.z
	f.y = 0.0
	f = f.normalized() if f.length() > 0.01 else Vector3.FORWARD
	var p := c.global_position + f * dist
	return Vector3(p.x, ground(p.x, p.z), p.z)

## Видна ли точка игроку: перед камерой, в конусе и в 15–60 м.
func in_view(p: Vector3, max_d: float = VIEW_MAX) -> bool:
	var c := camera()
	if c == null:
		return true
	var to := p - c.global_position
	var d := Vector2(to.x, to.z).length()
	if d < VIEW_MIN * 0.6 or d > max_d:
		return false
	var f := -c.global_transform.basis.z
	return f.normalized().dot(to.normalized()) > cos(VIEW_HALF_ANGLE + 0.25)

# --------------------------------------------------------------------- цикл

func _process(dt: float) -> void:
	for i in range(active.size() - 1, -1, -1):
		var s := active[i]
		if not is_instance_valid(s) or s.done:
			if is_instance_valid(s):
				s.cleanup()
			active.remove_at(i)
			continue
		if s.global_position.distance_to(player_pos()) > KEEP and not s.forced:
			s.cleanup()
			active.remove_at(i)
	for i in range(leftovers.size() - 1, -1, -1):
		var a := leftovers[i]
		if not is_instance_valid(a):
			leftovers.remove_at(i)
			continue
		if a is Animal:
			(a as Animal).tick(dt)
	if not auto:
		return
	_acc -= dt
	if _acc > 0.0:
		return
	_acc = AUTO_EVERY * _rng.randf_range(0.7, 1.3)
	if active.size() >= MAX_ACTIVE:
		return
	try_auto()

## Подобрать сценку под то, что видит игрок. Возвращает запущенную или null.
func try_auto() -> LandScene:
	if storm() > 0.55:
		return null                      # в шторм живность прячется
	for attempt in 6:
		var p := _view_point(_rng.randf_range(VIEW_MIN + 3.0, VIEW_MAX - 12.0))
		var c := camera()
		if c:
			var f := -c.global_transform.basis.z
			f.y = 0.0
			var a := _rng.randf_range(-VIEW_HALF_ANGLE, VIEW_HALF_ANGLE)
			var d := _rng.randf_range(VIEW_MIN + 3.0, VIEW_MAX - 12.0)
			var q := c.global_position + f.normalized().rotated(Vector3.UP, a) * d
			p = Vector3(q.x, ground(q.x, q.z), q.z)
		var cands := candidates_at(p)
		if cands.is_empty():
			continue
		var id: String = cands[_rng.randi() % cands.size()]
		return start(id, p, false)
	return null

## Сценки, которые можно поставить в точке p сейчас.
func candidates_at(p: Vector3) -> Array[String]:
	var out: Array[String] = []
	var water := is_water(p.x, p.z)
	var zn := zone_at(p.x, p.z)
	for id: String in CATALOG.keys():
		var e: Dictionary = CATALOG[id]
		if id in _recent:
			continue
		if not time_ok(String(e.time)):
			continue
		if e.get("low_tide", false) and not low_tide():
			continue
		if e.get("water", false):
			if not water:
				continue
			var depth := water_y() - ground(p.x, p.z)
			if depth < 2.0 or depth > 30.0:
				continue
			if find_land(p, 140.0) == Vector3.INF:
				continue
			out.append(id)
			continue
		if water:
			continue
		var zs: Array = e.zones
		if not zs.is_empty() and not (zn in zs):
			continue
		out.append(id)
	return out

## Запустить сценку. forced — из полигона/консоли (без проверок зоны/времени, не убирается вдали).
func start(id: String, p: Vector3, forced: bool = false) -> LandScene:
	if not CATALOG.has(id):
		push_warning("LandDirector: нет сценки %s" % id)
		return null
	var s := LandScene.new()
	s.kind = id
	s.director = self
	s.forced = forced
	s.seed_value = _rng.randi()
	add_child(s)
	s.global_position = Vector3(p.x, ground(p.x, p.z), p.z)
	if not s.setup():
		s.cleanup()
		return null
	active.append(s)
	started_total += 1
	started_by_id[id] = int(started_by_id.get(id, 0)) + 1
	_recent.append(id)
	if _recent.size() > 4:
		_recent.pop_front()
	return s

func stop_all() -> void:
	for s in active:
		if is_instance_valid(s):
			s.cleanup()
	active.clear()

func keep_corpse(a: Node3D) -> void:
	if a and is_instance_valid(a) and not (a in leftovers):
		leftovers.append(a)
