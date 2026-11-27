class_name UserSeaActors
extends Node3D
## Живность из пака пользователя ВБЛИЗИ: несколько особей с поведением и процедурной
## анимацией (UserSeaActor) вокруг камеры, когда она в воде или над мелководьем.
## Вдали те же виды — группы MultiMesh (SeaLifeCells). Особи появляются в 10–28 м от камеры
## в подходящих местах (глубина и биом вида), исчезают дальше 42 м.
## Тикает менеджер: ближние (до NEAR_ANIM м) с анимацией каждый кадр, дальние реже и без анимации.
## Модели со скелетом (SeaSkel: рифовые рыбы, барракуда, групер, мурена, скаты, черепахи, дельфин,
## кальмар, лобстер, креветка, звёзды, голотурии) — тоже здесь: SeaCritter с рефлексами по заданиям
## автора (испуг, угроза мурены, скат в песке, вдох черепахи, кормёжка манты…), виды — из
## океанского состава (OceanRoster, слот «skel:»), место — по глубине и среде вида.

const SPAWN_MIN := 10.0
const SPAWN_MAX := 28.0
const DESPAWN := 42.0
const NEAR_ANIM := 30.0
## Сколько особей вида держать рядом — по пресету (низкое…ультра).
const CAP_BY_Q: Array[float] = [0.4, 0.7, 1.0, 1.4]
const CAP := {"octopus": 2, "squid": 4, "fish": 4}
## Длина (м), с которой вид — «гигант» (кит): рядом с камерой не появляется.
const GIANT_LEN := 6.0
## Особей, убранных проверкой «на суше / на мели» (для тестов).
var removed_dry := 0

var sea: Object = null
## false — только закреплённые особи (полигон): без автоспавна вокруг камеры.
var auto_spawn := true
var actors: Array[UserSeaActor] = []
var critters: Array[SeaCritter] = []
var _skel_species: Array = []
## Особей вида со скелетом рядом (по пресету умножается на CAP_BY_Q).
const SKEL_CAP := {"reef_fish": 2, "pelagic": 1, "ray": 1, "turtle": 1, "mammal": 2, "cephalopod": 3,
	"crustacean": 2, "echinoderm": 3}
## Среда вида → биомы SeaLifeCells.
const HABITAT_BIOME := {"reef": ["reef"], "anemone": ["reef"], "crevice": ["reef"], "rubble": ["reef"],
	"reef_edge": ["reef", "lagoon"], "sand": ["lagoon", "reef"], "seagrass": ["lagoon"], "shallows": ["lagoon"],
	"open": ["deep", "lagoon"], "mangrove": ["mangrove"], "roots": ["mangrove"], "rock": ["reef", "lagoon"]}
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
		# кальмар-светлячок пака уступил место красному кальмару со скелетом и клипами автора
		if String(d.get("id", "")) == "squid_user" and SeaSkel.has("squid_red"):
			continue
		if UserSeaPack.species_mesh(d) != null:
			_species.append(d)
	for sp: Dictionary in OceanRoster.all_species():
		if String(OceanRoster.visual(sp).get("kind", "")) != "skel" or not SKEL_CAP.has(String(sp.get("group", ""))):
			continue
		var bi := {}
		for h: Variant in sp.get("habitat", []):
			for b: String in HABITAT_BIOME.get(String(h), []):
				bi[b] = true
		if bi.is_empty():
			continue                     # пресноводные (дискус, аулонокара) — не в море
		var e := sp.duplicate()
		e["_biomes"] = bi.keys()
		_skel_species.append(e)

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
		if not is_instance_valid(a):
			continue
		var d := a.global_position.distance_to(eye)
		if d < NEAR_ANIM:
			a.tick(delta, eye, player, true)
		elif far_step:
			a.tick(_far_acc, eye, player, false)
	for c in critters:
		if not is_instance_valid(c):
			continue
		if c.global_position.distance_to(eye) < NEAR_ANIM:
			c.tick(delta)
		elif far_step:
			c.tick(_far_acc)
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
	for i in range(critters.size() - 1, -1, -1):
		var c := critters[i]
		if not is_instance_valid(c) or c.global_position.distance_to(eye) > DESPAWN:
			if is_instance_valid(c):
				c.queue_free()
			critters.remove_at(i)
	_validate()
	if not auto_spawn or not _active(eye):
		return
	var q := clampi(Settings.graphics_quality, 0, 3)
	_refresh_skel(eye, q)
	var count := {}
	for a in actors:
		if a.pinned:
			continue
		count[a.data.get("id", "")] = int(count.get(a.data.get("id", ""), 0)) + 1
	var cells := get_tree().get_first_node_in_group(&"sea_life_cells") as SeaLifeCells
	for d: Dictionary in _species:
		if q < int(d.get("min_quality", 0)):
			continue
		# гиганты (кит) рядом с камерой не появляются — только редкими группами в открытом океане (SeaLifeCells)
		if float(d.get("length", 1.0)) >= GIANT_LEN:
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
			a.add_hitbox()
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
		var L := float(d.get("length", 0.5))
		# v5.1: только море (маска), глубина при отливе — на тело и вокруг (петля маршрута)
		var need := maxf(SeaBounds.need_depth(L), float(dr[0]) * 0.5)
		var rr := clampf(float(d.get("roam", 6.0)), 2.0, 14.0) * 0.6
		if not SeaBounds.ring_ok(sea, Vector3(x, 0, z), rr, rr, need, 8):
			continue
		if cells and not biomes.is_empty() and not biomes.has(cells.biome_at(x, z, dep)):
			continue
		var fl: float = sea.call(&"floor_at", x, z)
		var y := fl + 0.02
		if UserSeaActor._kind_of(d) != "octopus":
			y = clampf(wy - _rng.randf_range(float(dr[0]) * 0.7, minf(float(dr[1]), dep) * 0.8), fl + 0.5, wy - 0.5)
		return Vector3(x, y, z)
	return null

## Существа со скелетом: одна попытка в секунду на вид, до SKEL_CAP × пресет.
func _refresh_skel(eye: Vector3, q: int) -> void:
	var count := {}
	for c in critters:
		if is_instance_valid(c):
			count[String(c.sp.get("id", ""))] = int(count.get(String(c.sp.get("id", "")), 0)) + 1
	var cells := get_tree().get_first_node_in_group(&"sea_life_cells") as SeaLifeCells
	for sp: Dictionary in _skel_species:
		var cap := maxi(int(round(float(SKEL_CAP[String(sp.group)]) * CAP_BY_Q[q])), 1)
		if int(count.get(String(sp.id), 0)) >= cap:
			continue
		var pos: Variant = _find_skel_spot(sp, eye, cells)
		if pos == null:
			continue
		spawn_critter(sp, pos as Vector3)

func _find_skel_spot(sp: Dictionary, eye: Vector3, cells: SeaLifeCells) -> Variant:
	var dr: Array = sp.get("depth", [1.0, 30.0])
	var wy: float = sea.call(&"water_y")
	var g := String(sp.get("group", ""))
	for i in 6:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(SPAWN_MIN, SPAWN_MAX)
		var x := eye.x + cos(a) * r
		var z := eye.z + sin(a) * r
		var dep: float = sea.call(&"depth_at", x, z)
		if dep < maxf(float(dr[0]), 0.6) or dep > float(dr[1]) * 1.3:
			continue
		var L2 := float(sp.get("length", 0.5))
		if L2 >= GIANT_LEN:
			return null                  # кит рядом с камерой — нет (редкие группы вдали)
		var rr2 := clampf(L2 * 8.0, 2.0, 14.0) * 0.6
		if not SeaBounds.ring_ok(sea, Vector3(x, 0, z), rr2, rr2, maxf(SeaBounds.need_depth(L2), float(dr[0]) * 0.5), 8):
			continue
		if cells and not (sp._biomes as Array).has(cells.biome_at(x, z, dep)):
			continue
		var fl: float = sea.call(&"floor_at", x, z)
		var y := clampf(wy - _rng.randf_range(float(dr[0]) * 0.7, minf(float(dr[1]), dep) * 0.8), fl + 0.6, wy - 0.6)
		if g in ["crustacean", "echinoderm"]:
			y = fl + 0.02
		elif String(sp.id) == "moray":
			y = fl + 0.12
		elif g == "ray" and String(sp.id) == "stingray":
			y = fl + 0.4
		return Vector3(x, y, z)
	return null

## Существо со скелетом вида sp (OceanRoster) в точке pos (мировые координаты), с поведением по виду.
func spawn_critter(sp: Dictionary, pos: Vector3) -> SeaCritter:
	_seed += 1
	var c := SeaCritter.make(sp, sea, pos, _seed * 7919)
	if c == null:
		return null
	add_child(c)
	c.global_position = pos
	critters.append(c)
	var id := String(sp.get("id", ""))
	match id:
		"moray":
			c.hold(pos, Vector3(cos(_seed), 0, sin(_seed)))      # сидит в расщелине
		"pistol_shrimp", "starfish", "sea_cucumber", "lobster":
			c.wander(pos, 1.5, c.cruise)
		"stingray":
			c.wander(pos, 8.0, c.cruise * 0.7)
		_:
			c.wander(pos, clampf(c.length * 8.0, 2.0, 14.0))
	return c

## Счётчик для F3.
func perf_text() -> String:
	return "вблизи %d + %d со скелетом" % [actors.size(), critters.size()]

## Полигон/тест: особь вида на месте (без менеджера-спавна, тик — тот же).
func spawn_at(d: Dictionary, pos: Vector3, yaw: float = 0.0) -> UserSeaActor:
	## (особь закреплена; pos — локальная позиция в узле менеджера)
	var a := UserSeaActor.new()
	_seed += 1
	a.setup(d, sea, pos, _seed * 7919)
	a.yaw = yaw
	a.pinned = true
	add_child(a)
	a.add_hitbox()
	actors.append(a)
	return a

## v5.1: проверка раз в секунду — особь вне моря (на суше, в отрезанной низине, на мели не по росту)
## убирается; новые появятся на подходящем месте. Закреплённые (полигон, бассейны) не трогаем.
func _validate() -> void:
	if sea == null:
		return
	for i in range(actors.size() - 1, -1, -1):
		var a := actors[i]
		if not is_instance_valid(a) or a.pinned or a.dead:
			continue
		var p := a.global_position
		if not SeaBounds.water_ok(sea, p.x, p.z, minf(SeaBounds.need_depth(a.body_len), 0.6)) \
				or p.y > float(sea.call(&"water_y")) + 0.05:
			a.queue_free()
			actors.remove_at(i)
			removed_dry += 1
	for i in range(critters.size() - 1, -1, -1):
		var c := critters[i]
		if not is_instance_valid(c) or c.dead:
			continue
		var p2 := c.global_position
		if c.mode == SeaCritter.M.BALLISTIC:
			continue                     # прыжок над водой (дельфин) — законно
		if not SeaBounds.water_ok(sea, p2.x, p2.z, minf(SeaBounds.need_depth(c.length), 0.6)) \
				or p2.y > float(sea.call(&"water_y")) + 0.1:
			c.queue_free()
			critters.remove_at(i)
			removed_dry += 1
