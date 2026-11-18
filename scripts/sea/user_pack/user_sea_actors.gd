class_name UserSeaActors
extends Node3D
## Живность из пака пользователя ВБЛИЗИ: несколько особей с поведением и процедурной
## анимацией (UserSeaActor) вокруг камеры, когда она в воде или над мелководьем.
## Вдали те же виды — группы MultiMesh (SeaLifeCells). Особи появляются в 10–28 м от камеры
## в подходящих местах (глубина и биом вида), исчезают дальше 42 м.
## Тикает менеджер: ближние (до NEAR_ANIM м) с анимацией каждый кадр, дальние реже и без анимации.

const SPAWN_MIN := 10.0
const SPAWN_MAX := 28.0
const DESPAWN := 42.0
const NEAR_ANIM := 30.0
## Сколько особей вида держать рядом — по пресету (низкое…ультра).
const CAP_BY_Q: Array[float] = [0.4, 0.7, 1.0, 1.4]
const CAP := {"octopus": 2, "squid": 4, "fish": 4}

var sea: Object = null
## false — только закреплённые особи (полигон): без автоспавна вокруг камеры.
var auto_spawn := true
var actors: Array[UserSeaActor] = []
var _species: Array = []
var _acc := 0.0
var _far_acc := 0.0
var _rng := RandomNumberGenerator.new()
var _seed := 1

func _ready() -> void:
	name = "UserSeaActors"
	add_to_group(&"user_sea_actors")
	_rng.seed = 90127
	for d: Dictionary in UserSeaPack.species_list():
		if UserSeaPack.species_mesh(d) != null:
			_species.append(d)

func _exit_tree() -> void:
	UserSeaActor.clear_cache()

func _process(delta: float) -> void:
	var __pt := PerfStats.begin()
	var cam := get_viewport().get_camera_3d()
	if cam == null or sea == null or (actors.is_empty() and not auto_spawn):
		PerfStats.end(&"sea_actors", __pt)
		return
	var eye := cam.global_position
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	_acc += delta
	if _acc >= 1.0:
		_acc = 0.0
		_refresh(eye)
	_far_acc += delta
	var far_step := _far_acc >= 0.2
	for a in actors:
		var d := a.global_position.distance_to(eye)
		if d < NEAR_ANIM:
			a.tick(delta, eye, player, true)
		elif far_step:
			a.tick(_far_acc, eye, player, false)
	if far_step:
		_far_acc = 0.0
	PerfStats.end(&"sea_actors", __pt)

## Камера в воде или низко над водой (с берега видно мелководье).
func _active(eye: Vector3) -> bool:
	var wy: float = sea.call(&"water_y")
	return eye.y < wy + 6.0

func _refresh(eye: Vector3) -> void:
	# убрать дальние
	for i in range(actors.size() - 1, -1, -1):
		var a := actors[i]
		if is_instance_valid(a) and a.pinned:
			continue
		if not is_instance_valid(a) or a.global_position.distance_to(eye) > DESPAWN:
			if is_instance_valid(a):
				a.queue_free()
			actors.remove_at(i)
	if not auto_spawn or not _active(eye):
		return
	var q := clampi(Settings.graphics_quality, 0, 3)
	var count := {}
	for a in actors:
		if a.pinned:
			continue
		count[a.data.get("id", "")] = int(count.get(a.data.get("id", ""), 0)) + 1
	var cells := get_tree().get_first_node_in_group(&"sea_life_cells") as SeaLifeCells
	for d: Dictionary in _species:
		if q < int(d.get("min_quality", 0)):
			continue
		var kind := UserSeaActor._kind_of(d)
		var cap := int(round(float(CAP[kind]) * CAP_BY_Q[q]))
		var have := int(count.get(d.get("id", ""), 0))
		if have >= cap:
			continue
		# одна попытка в секунду на вид — особи появляются постепенно
		var pos: Variant = _find_spot(d, eye, cells)
		if pos == null:
			continue
		var n := 1
		if kind == "squid":
			n = mini(cap - have, 3)
		for k in n:
			var a := UserSeaActor.new()
			_seed += 1
			var off := Vector3(_rng.randf_range(-1.5, 1.5), _rng.randf_range(-0.6, 0.6), _rng.randf_range(-1.5, 1.5)) if k > 0 else Vector3.ZERO
			a.setup(d, sea, (pos as Vector3) + off, _seed * 7919)
			add_child(a)
			actors.append(a)

func _find_spot(d: Dictionary, eye: Vector3, cells: SeaLifeCells) -> Variant:
	var dr: Array = d.get("depth", [1.0, 30.0])
	var biomes: Array = d.get("biome", [])
	var wy: float = sea.call(&"water_y")
	for i in 6:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(SPAWN_MIN, SPAWN_MAX)
		var x := eye.x + cos(a) * r
		var z := eye.z + sin(a) * r
		var dep: float = sea.call(&"depth_at", x, z)
		if dep < float(dr[0]) or dep > float(dr[1]) * 1.3:
			continue
		if cells and not biomes.is_empty() and not biomes.has(cells.biome_at(x, z, dep)):
			continue
		var fl: float = sea.call(&"floor_at", x, z)
		var y := fl + 0.02
		if UserSeaActor._kind_of(d) != "octopus":
			y = clampf(wy - _rng.randf_range(float(dr[0]) * 0.7, minf(float(dr[1]), dep) * 0.8), fl + 0.5, wy - 0.5)
		return Vector3(x, y, z)
	return null

## Счётчик для F3.
func perf_text() -> String:
	return "вблизи %d" % actors.size()

## Полигон/тест: особь вида на месте (без менеджера-спавна, тик — тот же).
func spawn_at(d: Dictionary, pos: Vector3, yaw: float = 0.0) -> UserSeaActor:
	## (особь закреплена; pos — локальная позиция в узле менеджера)
	var a := UserSeaActor.new()
	_seed += 1
	a.setup(d, sea, pos, _seed * 7919)
	a.yaw = yaw
	a.pinned = true
	add_child(a)
	actors.append(a)
	return a
