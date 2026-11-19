class_name Flora
extends Node3D
## Модуль FLORA: растительность и природные ресурсы всего архипелага.
## Подключение (WORLD/match): узел со скриптом Flora — сам дождётся `world_ready`.
## Без узла `world` берёт высоты у текущей сцены (test_island: height_at).
##
## G2: рассадка по биомам и типам островов (home/center/shared/spring/swamp/rocky/atoll/wreck/…):
## пальмовые пляжи, джунгли (лиственные, баньяны, лианы), луга (дикие культуры, хлопок),
## мангры (болота, мелководье у берега), скалы (валуны, редкие жилы железа и серы).
## Всё невосстанавливаемо: срубленное/собранное исчезает навсегда (пни, голые кусты).
##
## Производительность: деревья — записи + MultiMesh по чанкам 192 м (LOD0 ≤ 120 м, LOD1 ≤ 650 м)
## и дешёвые коллизии стволов; в настоящий ChoppableTree дерево «просыпается» в 26 м от
## персонажа (игрок/боты/животные) или при ударе/запросе API и засыпает обратно нетронутым.
## Трава/папоротники — стрим по чанкам 32 м вокруг камеры; узлы-ресурсы, палки, камни,
## валуны — стрим узлов в 80–120 м от камеры/персонажей.
##
## API: Flora.instance(), nodes_near(pos, r, kind), materialize(entry), trees_near(pos, r, kind),
## promote(rec). kind — вид узла (&"palm", &"liana", &"iron_ore"…), группа (&"tree", &"crop",
## &"ore") или id предмета (&"fiber", &"food", &"seed_taro"…) — см. ITEM_SOURCES.

signal flora_ready

const TREE_VIS_RANGE := 280.0   # ChoppableTree (проснувшиеся)
const LOD_DIST := 140.0   # с TCHUNK 96: ближайший LOD1 ~72 м от камеры (как было при 64/120)
const TREE_FAR := 650.0
## Дальность видимости считается от центра AABB всей группы MultiMesh, поэтому детальный (LOD0)
## и упрощённый (LOD1) уровни делят одинаковые мелкие чанки — иначе у камеры вместо деревьев
## остаются «болванки». LOD2 — тот же меш, что LOD1, крупными чанками для дальних деревьев;
## перекрытие LOD1/LOD2 безвредно (одинаковая геометрия), поэтому диапазоны с запасом.
const TCHUNK := 96.0           # LOD0 (полные меши вариантов); 96 м — вдвое меньше MultiMesh-групп, чем 64
const FAR_CHUNK := 144.0
const SCHUNK := 192.0          # теневые двойники деревьев (лёгкий меш, только в карту теней)
const LOD1_END := 400.0  # перекрытие с LOD2 ≥ разницы центров чанков
const LOD2_BEGIN := 250.0
const CCHUNK := 192.0          # чанк коллизий стволов
const PROMOTE_R := 26.0
const DEMOTE_R := 40.0
const GRASS_RANGE := 42.0
const FERN_RANGE := 70.0
const BUSH_RANGE := 150.0
const CHUNK := 32.0             # чанк травы/папоротника
const DECOR_STREAM := 80.0
const BUSH_CHUNK := 128.0
const NODE_STREAM := 85.0
const ROCK_STREAM := 125.0
const CELL := 4.0               # шаг сетки рассадки
const HCELL := 16.0             # пространственный хэш записей
const TICK := 0.25

enum { T_TREE, T_NODE, T_ROCK, T_PICKUP }

const TREE_KINDS: Array[StringName] = [&"palm", &"broadleaf", &"mangrove", &"banyan"]
const VARIANTS := {&"palm": 5, &"broadleaf": 4, &"mangrove": 3, &"banyan": 2}
const CROPS: Array[StringName] = [&"wild_taro", &"wild_maize", &"wild_melon"]

## Предмет / группа → виды узлов, из которых его добыть (для ботов).
const ITEM_SOURCES := {
	&"tree": [&"palm", &"broadleaf", &"mangrove", &"banyan"],
	&"log": [&"broadleaf", &"palm", &"mangrove", &"banyan"],
	&"wood": [&"broadleaf", &"palm", &"mangrove", &"banyan"],
	&"leaf": [&"broadleaf", &"palm", &"mangrove", &"banyan"],
	&"coconut": [&"palm"],
	&"rock": [&"boulder", &"stone"],
	&"stone": [&"stone", &"boulder"],
	&"ore": [&"iron_ore", &"sulfur"],
	&"stick": [&"stick"],
	&"fiber": [&"liana"],
	&"rope": [&"liana"],
	&"taro": [&"wild_taro"], &"seed_taro": [&"wild_taro"],
	&"maize": [&"wild_maize"], &"seed_maize": [&"wild_maize"],
	&"melon": [&"wild_melon"], &"seed_melon": [&"wild_melon"],
	&"seed_berry": [&"berries"],
	&"crop": [&"wild_taro", &"wild_maize", &"wild_melon"],
	&"seed": [&"wild_taro", &"wild_maize", &"wild_melon", &"berries"],
	&"food": [&"berries", &"wild_taro", &"wild_maize", &"wild_melon", &"palm"],
}

## Профили типов островов: множители категорий рассадки.
const PROFILES := {
	&"home": {"tree": 1.0, "palm": 1.0, "rock": 1.0, "res": 1.0, "ore": 0.3, "mangrove": 0.6},
	&"shared": {"tree": 1.0, "palm": 1.0, "rock": 1.0, "res": 1.25, "ore": 0.7, "mangrove": 0.7},
	&"center": {"tree": 1.1, "palm": 0.9, "rock": 1.2, "res": 1.4, "ore": 1.2, "mangrove": 0.4},
	&"spring": {"tree": 1.3, "palm": 0.8, "rock": 0.6, "res": 1.5, "ore": 0.2, "mangrove": 0.5, "herb": 2.2},
	&"swamp": {"tree": 0.9, "palm": 0.35, "rock": 0.3, "res": 1.2, "ore": 0.0, "mangrove": 2.6, "herb": 1.6},
	&"rocky": {"tree": 0.35, "palm": 0.5, "rock": 2.2, "res": 0.5, "ore": 3.2, "mangrove": 0.0, "bush": 0.5},
	&"volcanic": {"tree": 0.4, "palm": 0.5, "rock": 2.0, "res": 0.5, "ore": 1.5, "sulfur": 4.0, "mangrove": 0.0},
	&"atoll": {"tree": 0.1, "palm": 1.7, "rock": 0.15, "res": 0.4, "ore": 0.0, "mangrove": 0.4, "bush": 0.6},
	&"wreck": {"tree": 0.5, "palm": 0.8, "rock": 0.6, "res": 0.7, "ore": 0.2, "mangrove": 0.3, "stick": 2.5},
}

## Базовые вероятности на ячейку 4×4 м по биому: [что, вероятность, категория профиля].
const TABLES := {
	&"beach": [[&"palm", 0.10, "palm"], [&"mangrove_z", 0.10, "mangrove"], [&"bush", 0.03, "bush"], [&"stick", 0.04, "stick"],
		[&"stone", 0.02, "rock"], [&"cotton", 0.004, "res"], [&"boulder", 0.004, "rock"]],
	&"jungle": [[&"broadleaf", 0.075, "tree"], [&"banyan", 0.003, "tree"], [&"palm", 0.022, "palm"], [&"bush", 0.20, "bush"],
		[&"herb", 0.010, "herb"], [&"wild_taro", 0.006, "res"], [&"berries", 0.010, "res"], [&"wild_melon", 0.002, "res"],
		[&"stick", 0.03, "stick"], [&"stone", 0.012, "rock"], [&"boulder", 0.010, "rock"]],
	&"meadow": [[&"broadleaf", 0.016, "tree"], [&"palm", 0.02, "palm"], [&"bush", 0.08, "bush"], [&"herb", 0.012, "herb"],
		[&"wild_maize", 0.010, "res"], [&"wild_melon", 0.006, "res"], [&"cotton", 0.010, "res"], [&"berries", 0.008, "res"],
		[&"stick", 0.02, "stick"], [&"stone", 0.015, "rock"], [&"boulder", 0.008, "rock"]],
	&"swamp": [[&"mangrove_s", 0.07, "mangrove"], [&"broadleaf", 0.03, "tree"], [&"bush", 0.06, "bush"], [&"herb", 0.015, "herb"],
		[&"wild_taro", 0.015, "res"], [&"stick", 0.02, "stick"]],
	&"rocky": [[&"boulder", 0.07, "rock"], [&"stone", 0.04, "rock"], [&"iron_ore", 0.006, "ore"], [&"sulfur", 0.004, "sulfur"],
		[&"palm", 0.01, "palm"], [&"bush", 0.02, "bush"], [&"herb", 0.004, "herb"]],
}

const BOULDERS := ["boulder_01", "boulder_02", "rock_07", "rock_moss_set_01_rock03", "rock_moss_set_02_rock09"]

@export var seed: int = 1
@export var density: float = 1.0
## Зоны без растительности: Array of [Vector3 center, float radius] (спавн, база).
var clear_zones: Array = []

var world: Node = null
## Проснувшиеся деревья (ChoppableTree), включая пни.
var trees: Array[ChoppableTree] = []
var stats: Dictionary = {}
var populated: bool = false

var _tree_recs: Array = []
var _grid: Dictionary = {}        # Vector2i -> Array[rec]
var _tgroups: Dictionary = {}     # LOD0: "kind_idx|cx|cz" -> {v, mm: MultiMesh, xf: Array}
var _fgroups: Dictionary = {}     # LOD1: "kind|cx|cz" -> {v (вариант 0), mm, xf} — один меш на вид, масштаб по высоте
var _sgroups: Dictionary = {}     # тень ближних деревьев: "kind_idx|cx|cz" (SCHUNK) -> {v, mm, xf}
var _ggroups: Dictionary = {}     # LOD2: то же, крупные чанки FAR_CHUNK
var _colliders: Dictionary = {}   # Vector2i -> FloraColliders
var _shapes: Dictionary = {}
var _bush: Dictionary = {}        # "idx|cx|cz" -> Array[Transform3D]
var _live: Array = []             # записи с живыми узлами (не деревья)
var _promoted: Array = []         # записи проснувшихся нетронутых деревьев
var _decor: Dictionary = {}       # Vector2i -> Array[MultiMeshInstance3D]
var _zone := FastNoiseLite.new()
var _land_min := 0.4
var _tick_t := 0.0
var _now := 0.0
var _island_list: Array = []

static var _fallback_scene: Node = null
static var _inst: Flora = null

static func instance() -> Flora:
	return _inst if is_instance_valid(_inst) else null

func _enter_tree() -> void:
	_inst = self

func _exit_tree() -> void:
	stop_all_sfx()

func _ready() -> void:
	name = "Flora"
	add_to_group(&"flora")
	_register_items()
	set_process(false)
	if not Settings.graphics_changed.is_connected(_on_graphics_changed):
		Settings.graphics_changed.connect(_on_graphics_changed)
	world = get_tree().get_first_node_in_group(&"world")
	if world == null or not world.has_method(&"height_at"):
		world = null
		_fallback_scene = _find_height_source()
	elif world.has_signal(&"world_ready") and world.get(&"is_ready") == false:
		await world.world_ready
	populate()

## Дальность мелкой растительности × пресет графики (GraphicsQuality.detail).
func _detail_range(gi: GeometryInstance3D, base: float) -> void:
	gi.set_meta(&"detail_base", base)
	gi.visibility_range_end = base * GraphicsQuality.detail()
	gi.add_to_group(&"flora_detail")

func _on_graphics_changed() -> void:
	if not is_inside_tree():
		return
	var k := GraphicsQuality.detail()
	for n in get_tree().get_nodes_in_group(&"flora_detail"):
		var gi := n as GeometryInstance3D
		if gi:
			gi.visibility_range_end = float(gi.get_meta(&"detail_base", gi.visibility_range_end)) * k

func _find_height_source() -> Node:
	var n: Node = get_parent()
	while n:
		if n.has_method(&"height_at"):
			return n
		n = n.get_parent()
	for c in get_tree().root.get_children():
		if c.has_method(&"height_at"):
			return c
	return get_tree().current_scene

static func _reg(id: StringName, nm: String, kind: StringName, stack: int, w: float, data: Dictionary = {}) -> void:
	if Items.get_item(id) == null:
		Items.register_item(id, nm, kind, stack, w, data)

static func _register_items() -> void:
	_reg(&"leaf", "Листья", &"resource", 40, 0.1)
	_reg(&"rock", "Камень", &"resource", 20, 1.5)
	_reg(&"coconut", "Кокос", &"food", 10, 1.2, {"hunger": 6.0, "thirst": 18.0})
	_reg(&"stick", "Палка", &"resource", 20, 0.5)
	_reg(&"liana", "Лиана", &"resource", 20, 0.4)
	_reg(&"fiber", "Волокно", &"resource", 40, 0.1)
	_reg(&"rope", "Верёвка", &"resource", 20, 0.3)
	_reg(&"herb", "Лечебная трава", &"medicine", 20, 0.1, {"heal": 8.0, "antidote": true})
	_reg(&"taro", "Клубень таро", &"food", 10, 0.6, {"hunger": 10.0, "raw_penalty": true})
	_reg(&"maize", "Початок кукурузы", &"food", 10, 0.4, {"hunger": 8.0})
	_reg(&"melon", "Дыня", &"food", 4, 2.0, {"hunger": 8.0, "thirst": 16.0})
	_reg(&"berries", "Ягоды", &"food", 30, 0.05, {"hunger": 2.5, "thirst": 1.5})
	_reg(&"seed_taro", "Росток таро", &"seed", 20, 0.1, {"plant": &"taro"})
	_reg(&"seed_maize", "Семена кукурузы", &"seed", 30, 0.02, {"plant": &"maize"})
	_reg(&"seed_melon", "Семена дыни", &"seed", 30, 0.02, {"plant": &"melon"})
	_reg(&"seed_berry", "Семена ягод", &"seed", 30, 0.02, {"plant": &"berries"})
	_reg(&"cotton", "Хлопок", &"resource", 30, 0.05)
	_reg(&"iron_ore", "Железная руда", &"resource", 20, 2.5)
	_reg(&"sulfur", "Сера", &"resource", 30, 0.5)
	if not Items.recipes.has(&"rope_from_liana"):
		Items.register_recipe(&"rope_from_liana", &"rope", {&"liana": 2}, 1)
	if not Items.recipes.has(&"fiber_from_liana"):
		Items.register_recipe(&"fiber_from_liana", &"fiber", {&"liana": 1}, 2)

# --------------------------------------------------------------- запросы к миру

func _h(x: float, z: float) -> float:
	if world:
		return float(world.call(&"height_at", x, z))
	var s := _fallback_scene if _fallback_scene else get_tree().current_scene
	if s and s.has_method(&"height_at"):
		return float(s.call(&"height_at", x, z))
	return 0.0

func _biome(x: float, z: float) -> StringName:
	if world and world.has_method(&"biome_at"):
		return world.call(&"biome_at", x, z)
	var h := _h(x, z)
	if h <= 0.35:
		return &"water"
	var slope := absf(_h(x + 1.0, z) - h) + absf(_h(x, z + 1.0) - h)
	if slope > 1.1:
		return &"rocky"
	if h < 1.45:
		return &"beach"
	return &"jungle"

func _islands() -> Array:
	if world and world.has_method(&"islands"):
		return world.call(&"islands")
	var r := 55.0
	var s := _fallback_scene if _fallback_scene else get_tree().current_scene
	if s and s.get(&"ISLAND_R") != null:
		r = float(s.get(&"ISLAND_R"))
	return [{"id": 0, "kind": &"home", "team": 0, "center": Vector2.ZERO, "radius": r * 1.2}]

func _cleared(p: Vector3) -> bool:
	for z in clear_zones:
		if p.distance_to(z[0]) < float(z[1]):
			return true
	return false

static func _cat(prof: Dictionary, cat: String) -> float:
	if cat == "sulfur":
		return float(prof.get("sulfur", prof.get("ore", 1.0)))
	return float(prof.get(cat, 1.0))

# --------------------------------------------------------------- рассадка

func populate() -> void:
	if populated:
		return
	var t0 := Time.get_ticks_msec()
	_land_min = 0.4
	if world and world.get(&"tide_amplitude") != null:
		_land_min = float(world.get(&"tide_amplitude")) + 0.12
	_island_list = _islands()
	if clear_zones.is_empty():
		if world and world.has_method(&"spawn_point"):
			var teams := {}
			for I in _island_list:
				if int(I.get("team", -1)) >= 0:
					teams[int(I["team"])] = true
			for t in teams:
				clear_zones.append([world.call(&"spawn_point", t), 7.0])
		else:
			clear_zones.append([Vector3.ZERO, 6.0])
	_zone.seed = seed
	_zone.frequency = 0.018
	stats = {"palm": 0, "broadleaf": 0, "mangrove": 0, "banyan": 0, "bush": 0, "grass": 0, "fern": 0, "rock": 0, "stick": 0,
		"stone": 0, "iron_ore": 0, "sulfur": 0, "liana": 0, "herb": 0, "wild_taro": 0, "wild_maize": 0, "wild_melon": 0,
		"berries": 0, "cotton": 0}
	var rng := RandomNumberGenerator.new()
	var visited: Dictionary = {}
	for I in _island_list:
		var c: Vector2 = I["center"]
		var R: float = float(I["radius"]) * 1.3 + 8.0
		var prof: Dictionary = PROFILES.get(StringName(I.get("kind", &"home")), PROFILES[&"home"])
		for j in range(int(floor((c.y - R) / CELL)), int(ceil((c.y + R) / CELL))):
			for i in range(int(floor((c.x - R) / CELL)), int(ceil((c.x + R) / CELL))):
				var key := Vector2i(i, j)
				if visited.has(key):
					continue
				visited[key] = true
				_cell(i, j, prof, c, rng)
	stats["cells"] = visited.size()
	_build_trees()
	_build_bushes()
	populated = true
	stats["ms_populate"] = Time.get_ticks_msec() - t0
	_tick(true)
	stats["ms"] = Time.get_ticks_msec() - t0
	print("[flora] populated ", stats)
	set_process(true)
	flora_ready.emit()

func _cell(i: int, j: int, prof: Dictionary, c: Vector2, rng: RandomNumberGenerator) -> void:
	rng.seed = hash(Vector3i(i, j, seed))
	var x := (float(i) + rng.randf()) * CELL
	var z := (float(j) + rng.randf()) * CELL
	var h := _h(x, z)
	var zone := _zone.get_noise_2d(x, z)
	if h <= _land_min:
		# мелководье у берега — мангровые заросли (пятнами по шуму, на болотных островах — сплошь)
		var mg := _cat(prof, "mangrove")
		if h > -0.85 and mg > 0.0 and (zone > 0.25 or mg >= 2.0):
			var toc := (c - Vector2(x, z)).normalized()
			if _h(x + toc.x * 7.0, z + toc.y * 7.0) > _land_min - 0.2 and rng.randf() < 0.16 * minf(mg, 2.6):
				_add_tree(&"mangrove", Vector3(x, h, z), rng, c)
		return
	var p := Vector3(x, h, z)
	if _cleared(p):
		return
	var b := _biome(x, z)
	if b == &"water":
		return
	var table: Array = TABLES.get(b, TABLES[&"meadow"])
	var r := rng.randf()
	var acc := 0.0
	for e in table:
		var f := _cat(prof, e[2])
		if e[2] == "tree" or e[2] == "palm" or e[2] == "mangrove":
			f *= density
		acc += float(e[1]) * f
		if r < acc:
			_place(e[0], p, rng, c, prof, b, zone)
			return

func _place(what: StringName, p: Vector3, rng: RandomNumberGenerator, c: Vector2, prof: Dictionary, b: StringName, zone: float) -> void:
	match what:
		&"palm", &"broadleaf", &"banyan":
			var rec := _add_tree(what, p, rng, c)
			if what != &"palm" and b == &"jungle" and rng.randf() < (0.85 if what == &"banyan" else 0.33) * minf(_cat(prof, "res"), 1.5):
				_add_liana(rec, rng)
				if what == &"banyan":
					_add_liana(rec, rng)
		&"mangrove_z":
			if zone > 0.25:
				_add_tree(&"mangrove", p, rng, c)
		&"mangrove_s":
			_add_tree(&"mangrove" if p.y < 2.2 else &"broadleaf", p, rng, c)
		&"bush":
			var key := "%d|%d|%d" % [rng.randi_range(0, 3), int(floor(p.x / BUSH_CHUNK)), int(floor(p.z / BUSH_CHUNK))]
			if not _bush.has(key):
				_bush[key] = []
			var bs := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.3))
			(_bush[key] as Array).append(Transform3D(bs, p))
			stats["bush"] += 1
		&"stick", &"stone":
			_add_rec({"t": T_PICKUP, "kind": what, "idx": rng.randi_range(0, 99), "pos": p, "yaw": rng.randf() * TAU})
		&"boulder":
			var ore := &""
			if rng.randf() < 0.03 * _cat(prof, "ore"):
				ore = &"iron_ore" if rng.randf() < 0.65 else &"sulfur"
			_add_rock(p, rng, ore)
		&"iron_ore", &"sulfur":
			_add_rock(p, rng, what)
		_:
			_add_rec({"t": T_NODE, "kind": what, "idx": rng.randi_range(0, 5), "pos": p + Vector3(0, -0.05, 0), "yaw": rng.randf() * TAU})

func _add_rec(rec: Dictionary) -> Dictionary:
	rec["node"] = null
	rec["state"] = 0
	var p: Vector3 = rec["pos"]
	var key := Vector2i(int(floor(p.x / HCELL)), int(floor(p.z / HCELL)))
	if not _grid.has(key):
		_grid[key] = []
	(_grid[key] as Array).append(rec)
	var sk := String(rec["kind"])
	if rec["t"] == T_ROCK and rec.get("ore", &"") == &"":
		sk = "rock"
	stats[sk] = int(stats.get(sk, 0)) + 1
	return rec

func _add_rock(p: Vector3, rng: RandomNumberGenerator, ore: StringName) -> void:
	_add_rec({"t": T_ROCK, "kind": ore if ore != &"" else &"boulder", "ore": ore, "pos": p, "yaw": rng.randf() * TAU,
		"scene": BOULDERS[rng.randi_range(0, 1 if ore != &"" else BOULDERS.size() - 1)],
		"size": rng.randf_range(1.3, 1.9) if ore != &"" else rng.randf_range(0.9, 1.8),
		"units": rng.randi_range(3, 5) if ore != &"" else rng.randi_range(5, 9)})

func _add_tree(kind: StringName, p: Vector3, rng: RandomNumberGenerator, c: Vector2) -> Dictionary:
	var idx := rng.randi_range(0, int(VARIANTS[kind]) - 1)
	var yaw := rng.randf() * TAU
	if kind == &"palm":
		# пальмы клонятся к морю
		var out := Vector2(p.x, p.z) - c
		if out.length() > 1.0:
			yaw = atan2(-out.y, out.x) + rng.randf_range(-0.8, 0.8)
	var rec := _add_rec({"t": T_TREE, "kind": kind, "idx": idx, "pos": p + Vector3(0, -0.12, 0), "yaw": yaw, "lianas": []})
	_tree_recs.append(rec)
	return rec

func _add_liana(tree: Dictionary, rng: RandomNumberGenerator) -> void:
	var v := FloraLib.variant(tree["kind"], tree["idx"])
	var a := rng.randf() * TAU
	var off := Vector3(cos(a), 0, sin(a)) * ((v["r0"] as float) * 1.3 + 0.12)
	var rec := _add_rec({"t": T_NODE, "kind": &"liana", "idx": rng.randi_range(0, 5), "pos": (tree["pos"] as Vector3) + off + Vector3(0, 0.1, 0),
		"yaw": rng.randf() * TAU, "tree": tree})
	(tree["lianas"] as Array).append(rec)

# --------------------------------------------------------------- деревья: MultiMesh + коллизии

static func _xf(rec: Dictionary, hidden: bool = false, k: float = 1.0) -> Transform3D:
	var b := Basis(Vector3.UP, float(rec["yaw"])).scaled(Vector3.ONE * (0.0001 if hidden else k))
	return Transform3D(b, rec["pos"])

## Масштаб дальнего LOD (меш варианта 0) под высоту варианта дерева.
static func _far_k(rec: Dictionary) -> float:
	var v := FloraLib.variant(rec["kind"], rec["idx"])
	var v0 := FloraLib.variant(rec["kind"], 0)
	return (float(v["H"]) + float(v.get("crown_r", 0.0))) / (float(v0["H"]) + float(v0.get("crown_r", 0.0)))

func _build_trees() -> void:
	for rec in _tree_recs:
		var p: Vector3 = rec["pos"]
		var ck := Vector2i(int(floor(p.x / TCHUNK)), int(floor(p.z / TCHUNK)))
		var gk := "%s_%d|%d|%d" % [rec["kind"], rec["idx"], ck.x, ck.y]
		if not _tgroups.has(gk):
			_tgroups[gk] = {"v": FloraLib.variant(rec["kind"], rec["idx"]), "xf": []}
		var g: Dictionary = _tgroups[gk]
		rec["g"] = gk
		rec["mi"] = (g["xf"] as Array).size()
		(g["xf"] as Array).append(_xf(rec))
		# LOD1 — та же сетка, что LOD0: переключение по центру чанка без дыр
		var fk := "%s|%d|%d" % [rec["kind"], ck.x, ck.y]
		if not _fgroups.has(fk):
			_fgroups[fk] = {"v": FloraLib.variant(rec["kind"], 0), "xf": []}
		rec["gf"] = fk
		rec["fi"] = (_fgroups[fk]["xf"] as Array).size()
		(_fgroups[fk]["xf"] as Array).append(_xf(rec, false, _far_k(rec)))
		var gck := Vector2i(int(floor(p.x / FAR_CHUNK)), int(floor(p.z / FAR_CHUNK)))
		var gk2 := "%s|%d|%d" % [rec["kind"], gck.x, gck.y]
		if not _ggroups.has(gk2):
			_ggroups[gk2] = {"v": FloraLib.variant(rec["kind"], 0), "xf": []}
		rec["gg"] = gk2
		rec["gi"] = (_ggroups[gk2]["xf"] as Array).size()
		(_ggroups[gk2]["xf"] as Array).append(_xf(rec, false, _far_k(rec)))
		# теневой двойник: лёгкий меш варианта, крупные чанки, только в карту теней
		var sck := Vector2i(int(floor(p.x / SCHUNK)), int(floor(p.z / SCHUNK)))
		var sk2 := "%s_%d|%d|%d" % [rec["kind"], rec["idx"], sck.x, sck.y]
		if not _sgroups.has(sk2):
			_sgroups[sk2] = {"v": FloraLib.variant(rec["kind"], rec["idx"]), "xf": []}
		rec["gs"] = sk2
		rec["si"] = (_sgroups[sk2]["xf"] as Array).size()
		(_sgroups[sk2]["xf"] as Array).append(_xf(rec))
		# коллизия ствола
		ck = Vector2i(int(floor(p.x / CCHUNK)), int(floor(p.z / CCHUNK)))
		if not _colliders.has(ck):
			var body := FloraColliders.new()
			body.name = "TreeColliders_%d_%d" % [ck.x, ck.y]
			body.flora = self
			add_child(body)
			_colliders[ck] = body
		var v: Dictionary = g["v"]
		var sk := "%s_%d" % [rec["kind"], rec["idx"]]
		if not _shapes.has(sk):
			var cyl := CylinderShape3D.new()
			cyl.radius = FloraLib.trunk_radius(v, 0.6) * 1.05
			cyl.height = minf(4.0, (v["H"] as float) * 0.5)
			_shapes[sk] = cyl
		var shape: CylinderShape3D = _shapes[sk]
		var cs := CollisionShape3D.new()
		cs.shape = shape
		var lx := FloraLib.trunk_point(v, shape.height * 0.5).x * 0.5
		cs.position = p + Basis(Vector3.UP, float(rec["yaw"])) * Vector3(lx, shape.height * 0.5, 0)
		var body2: FloraColliders = _colliders[ck]
		body2.add_child(cs)
		body2.recs[cs.get_instance_id()] = rec
		rec["cs"] = cs
	var mmis := 0
	for lod in 3:
		var groups: Dictionary = [_tgroups, _fgroups, _ggroups][lod]
		for gk in groups:
			var g: Dictionary = groups[gk]
			var xs: Array = g["xf"]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			# LOD2 (250–650 м) — лёгкий меш (~100 треуг. вместо 300–1150 у LOD1): вдали
			# разница не видна, а экземпляров там тысячи (было ≈240k примитивов на вид к центру)
			mm.mesh = FloraLib.shadow_tree_mesh(g["v"]) if lod == 2 else FloraLib.tree_mesh(g["v"], lod)
			mm.instance_count = xs.size()
			for k in xs.size():
				mm.set_instance_transform(k, xs[k])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Trees%d_%s" % [lod, String(gk).replace("|", "_")]
			mmi.multimesh = mm
			if lod == 0:
				mmi.visibility_range_end = LOD_DIST
				mmi.visibility_range_end_margin = 4.0
				# Тень ближних деревьев рисует дешёвый «теневой двойник» (LOD1, один меш на вид):
				# детальный LOD0 в карту теней не идёт (было ≈450k примитивов/240 вызовов со спавна).
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			elif lod == 1:
				mmi.visibility_range_begin = LOD_DIST
				mmi.visibility_range_begin_margin = 4.0
				mmi.visibility_range_end = LOD1_END
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			else:
				mmi.visibility_range_begin = LOD2_BEGIN
				mmi.visibility_range_end = TREE_FAR
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)
			g["mm"] = mm
			mmis += 1
	for sk3 in _sgroups:
		var sg: Dictionary = _sgroups[sk3]
		var sxs: Array = sg["xf"]
		var smm := MultiMesh.new()
		smm.transform_format = MultiMesh.TRANSFORM_3D
		smm.mesh = FloraLib.shadow_tree_mesh(sg["v"])
		smm.instance_count = sxs.size()
		for k in sxs.size():
			smm.set_instance_transform(k, sxs[k])
		var sh := MultiMeshInstance3D.new()
		sh.name = "TreesShadow_%s" % String(sk3).replace("|", "_")
		sh.multimesh = smm
		sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		# дальность — от центра чанка SCHUNK: деревья до LOD_DIST от камеры попадают целиком
		sh.visibility_range_end = LOD_DIST + SCHUNK * 0.35
		add_child(sh)
		sg["mm"] = smm
		mmis += 1
	stats["tree_mmi"] = mmis
	stats["tree_chunks"] = _colliders.size()

func _set_mm_visible(rec: Dictionary, vis: bool) -> void:
	var g: Dictionary = _tgroups.get(rec.get("g", ""), {})
	if g.is_empty():
		return
	(g["mm"] as MultiMesh).set_instance_transform(int(rec["mi"]), _xf(rec, not vis))
	var f: Dictionary = _fgroups[rec["gf"]]
	(f["mm"] as MultiMesh).set_instance_transform(int(rec["fi"]), _xf(rec, not vis, _far_k(rec)))
	var gs: Dictionary = _sgroups.get(rec.get("gs", ""), {})
	if not gs.is_empty():
		(gs["mm"] as MultiMesh).set_instance_transform(int(rec["si"]), _xf(rec, not vis))
	var g2: Dictionary = _ggroups.get(rec.get("gg", ""), {})
	if not g2.is_empty():
		(g2["mm"] as MultiMesh).set_instance_transform(int(rec["gi"]), _xf(rec, not vis, _far_k(rec)))

## Разбудить дерево: настоящий ChoppableTree вместо экземпляра MultiMesh. null — дерева уже нет.
func promote(rec: Dictionary) -> ChoppableTree:
	if rec.get("t", -1) != T_TREE:
		return null
	var n = rec["node"]
	if n != null and is_instance_valid(n):
		rec["pt"] = _now
		return n
	if int(rec["state"]) != 0:
		return null
	var t := ChoppableTree.new()
	t.setup(FloraLib.variant(rec["kind"], rec["idx"]))
	# детальная тень — только у деревьев рядом с игроком; разбуженные ботами — лёгкая
	t.shadow_proxy = true
	for pl in get_tree().get_nodes_in_group(&"player"):
		if pl is Node3D and (pl as Node3D).global_position.distance_to(rec["pos"]) < 45.0:
			t.shadow_proxy = false
			break
	t.position = rec["pos"]
	t.rotation.y = float(rec["yaw"])
	add_child(t)
	t.fell_down.connect(_on_tree_felled.bind(rec))
	rec["node"] = t
	rec["pt"] = _now
	_set_mm_visible(rec, false)
	if rec.has("cs"):
		(rec["cs"] as CollisionShape3D).disabled = true
	_promoted.append(rec)
	trees.append(t)
	return t

func _demote(rec: Dictionary) -> void:
	var t: ChoppableTree = rec["node"]
	trees.erase(t)
	t.queue_free()
	rec["node"] = null
	_set_mm_visible(rec, true)
	if rec.has("cs"):
		(rec["cs"] as CollisionShape3D).disabled = false

func _on_tree_felled(_t: ChoppableTree, rec: Dictionary) -> void:
	rec["state"] = 1 # пень навсегда (узел остаётся)
	_promoted.erase(rec)
	for l in rec.get("lianas", []):
		if int(l["state"]) == 0:
			l["state"] = 2
			var n = l["node"]
			if n != null and is_instance_valid(n):
				l["_out"] = true
				(n as Node).queue_free()
			l["node"] = null

func _build_bushes() -> void:
	for key in _bush:
		var parts := String(key).split("|")
		var xs: Array = _bush[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = FloraLib.bush_mesh(int(parts[0]))
		mm.instance_count = xs.size()
		for i in xs.size():
			mm.set_instance_transform(i, xs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Bush_" + String(key).replace("|", "_")
		mmi.multimesh = mm
		_detail_range(mmi, BUSH_RANGE)
		add_child(mmi)
	stats["bush_mmi"] = _bush.size()

# --------------------------------------------------------------- стриминг

func _process(delta: float) -> void:
	var __pt := PerfStats.begin()
	_perf_process(delta)
	PerfStats.end(&"flora", __pt)

func _perf_process(delta: float) -> void:
	_now += delta
	_tick_t += delta
	if _tick_t >= TICK:
		_tick_t = 0.0
		_tick(false)

func _actors() -> Array:
	# Звери не будят деревья и не стримят узлы — в список не входят.
	var seen := {}
	var out: Array = []
	for g in [&"player", &"characters", &"bots"]:
		for n in get_tree().get_nodes_in_group(g):
			if n is Node3D and not seen.has(n) and not (n as Node).is_in_group(&"animals"):
				seen[n] = true
				out.append(n)
	return out

var _last_scan: Array[Vector3] = []
var _cull_t := 0.0

func _tick(sync: bool) -> void:
	var actors := _actors()
	# Стрим узлов — только вокруг камеры и персонажей (игроки/боты). Звери
	# (их сотни по всему архипелагу) центрами стрима не служат: иначе узлы
	# поднимаются по всей карте, а проход по записям занимает десятки мс.
	var centers: Array[Vector3] = []
	for a in actors:
		if not (a as Node).is_in_group(&"animals"):
			centers.append((a as Node3D).global_position)
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam:
		centers.append(cam.global_position)
	# центр, сдвинувшийся меньше чем на 6 м с прошлого прохода, не сканируем заново
	var scan: Array[Vector3] = []
	for c in centers:
		var moved := true
		for q: Vector3 in _last_scan:
			if q.distance_squared_to(c) < 36.0:
				moved = false
				break
		if moved or sync:
			scan.append(c)
	# 1) деревья у персонажей просыпаются (камера не будит — вид одинаковый)
	for a in actors:
		if (a as Node).is_in_group(&"animals"):
			continue
		var ap: Vector3 = (a as Node3D).global_position
		for rec in _recs_in(ap, PROMOTE_R):
			if rec["t"] == T_TREE and int(rec["state"]) == 0 and rec["node"] == null:
				promote(rec)
	# 2) нетронутые деревья вдали засыпают; к разбуженным ботом подошёл игрок — полная детализация
	var players := get_tree().get_nodes_in_group(&"player")
	for rec in _promoted.duplicate():
		var t = rec["node"]
		if t == null or not is_instance_valid(t):
			_promoted.erase(rec)
			continue
		if (t as ChoppableTree).shadow_proxy:
			for pl in players:
				if pl is Node3D and (pl as Node3D).global_position.distance_to(rec["pos"]) < 40.0:
					(t as ChoppableTree).set_full_detail()
					break
		if not (t as ChoppableTree).is_pristine() or _now - float(rec.get("pt", 0.0)) < 8.0:
			continue
		var near := false
		for a in actors:
			if not (a as Node).is_in_group(&"animals") and (a as Node3D).global_position.distance_to(rec["pos"]) < DEMOTE_R:
				near = true
				break
		if not near:
			_promoted.erase(rec)
			_demote(rec)
	# 3) узлы-ресурсы, валуны, палки
	var spawned := 0
	var capped := false
	for c in scan:
		for rec in _recs_in(c, ROCK_STREAM):
			if rec["t"] == T_TREE or int(rec["state"]) == 2 or rec["node"] != null:
				continue
			var r := ROCK_STREAM if rec["t"] == T_ROCK else NODE_STREAM
			if c.distance_squared_to(rec["pos"]) < r * r:
				_spawn_node(rec)
				spawned += 1
				if not sync and spawned > 30:
					capped = true
					break
	if not capped:
		_last_scan = centers.duplicate()
	_cull_t += TICK
	if _cull_t < 1.0 and not sync:
		_tick_decor(cam, sync, centers)
		return
	_cull_t = 0.0
	for rec in _live.duplicate():
		var n = rec["node"]
		if n == null or not is_instance_valid(n):
			_live.erase(rec)
			continue
		if rec.get("keep", false):
			continue
		if (n as Node).has_method(&"is_pristine") and not bool((n as Node).call(&"is_pristine")):
			rec["keep"] = true # тронутое (выработанный валун, голый куст) остаётся навсегда
			continue
		var r := (ROCK_STREAM if rec["t"] == T_ROCK else NODE_STREAM) + 25.0
		var far := true
		for c in centers:
			if c.distance_squared_to(rec["pos"]) < r * r:
				far = false
				break
		if far:
			rec["_out"] = true
			(n as Node).queue_free()
			rec["node"] = null
			_live.erase(rec)
	_tick_decor(cam, sync, centers)

## 4) трава/папоротники вокруг камеры
func _tick_decor(cam: Camera3D, sync: bool, centers: Array[Vector3]) -> void:
	if cam:
		_stream_decor(cam.global_position, 1000 if sync else 3)
	elif sync and not centers.is_empty():
		_stream_decor(centers[0], 1000)

func _recs_in(p: Vector3, r: float) -> Array:
	var out: Array = []
	var x0 := int(floor((p.x - r) / HCELL))
	var x1 := int(floor((p.x + r) / HCELL))
	var z0 := int(floor((p.z - r) / HCELL))
	var z1 := int(floor((p.z + r) / HCELL))
	for j in range(z0, z1 + 1):
		for i in range(x0, x1 + 1):
			var a = _grid.get(Vector2i(i, j))
			if a != null:
				out.append_array(a)
	return out

func _spawn_node(rec: Dictionary) -> Node:
	var n: Node3D = null
	match int(rec["t"]):
		T_NODE:
			var rn := ResourceNode.new().setup(rec["kind"], int(rec["idx"]))
			rn.harvested.connect(_on_harvested.bind(rec))
			n = rn
		T_ROCK:
			var rr := ResourceRock.new()
			rr.scene_path = "res://assets/models/polyhaven/%s.glb" % rec["scene"]
			rr.size = float(rec["size"])
			rr.units = int(rec["units"])
			rr.ore = rec.get("ore", &"")
			rr.exhausted.connect(func(_r: ResourceRock) -> void: rec["state"] = 1)
			n = rr
		T_PICKUP:
			var rng := RandomNumberGenerator.new()
			rng.seed = int(rec["idx"])
			n = FloraPickup.make_stick(rng) if rec["kind"] == &"stick" else FloraPickup.make_rock()
			n.position.y += 0.05 if rec["kind"] == &"stick" else 0.08
	n.position += rec["pos"]
	n.rotation.y = float(rec["yaw"])
	add_child(n)
	n.tree_exiting.connect(_on_node_exit.bind(rec))
	rec["node"] = n
	_live.append(rec)
	return n

func _on_node_exit(rec: Dictionary) -> void:
	if rec.get("_out", false):
		rec["_out"] = false
		return
	if is_queued_for_deletion() or not is_inside_tree():
		return
	rec["state"] = 2 # подобрано / собрано — навсегда
	rec["node"] = null

func _on_harvested(_n: ResourceNode, removed: bool, rec: Dictionary) -> void:
	rec["state"] = 2 if removed else 1
	rec["keep"] = true

func _stream_decor(cp: Vector3, budget: int) -> void:
	var r := DECOR_STREAM
	var c0 := Vector2i(int(floor((cp.x - r) / CHUNK)), int(floor((cp.z - r) / CHUNK)))
	var c1 := Vector2i(int(floor((cp.x + r) / CHUNK)), int(floor((cp.z + r) / CHUNK)))
	var want: Array = []
	for j in range(c0.y, c1.y + 1):
		for i in range(c0.x, c1.x + 1):
			var k := Vector2i(i, j)
			if _decor.has(k):
				continue
			var cc := Vector2((i + 0.5) * CHUNK, (j + 0.5) * CHUNK)
			var d := cc.distance_to(Vector2(cp.x, cp.z))
			if d < r + CHUNK * 0.7:
				want.append([d, k])
	want.sort_custom(func(a, b) -> bool: return a[0] < b[0])
	for w in want.slice(0, budget):
		_decor[w[1]] = _gen_decor(w[1])
	for k in _decor.keys():
		var cc := Vector2((k.x + 0.5) * CHUNK, (k.y + 0.5) * CHUNK)
		if cc.distance_to(Vector2(cp.x, cp.z)) > r + CHUNK * 2.0:
			for mmi in _decor[k]:
				(mmi as Node).queue_free()
			_decor.erase(k)

func _gen_decor(k: Vector2i) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(k.x, k.y, seed + 101))
	var sets: Dictionary = {}
	var gstep := 1.7 / sqrt(density)
	var n := int(ceil(CHUNK / gstep))
	var ox := k.x * CHUNK
	var oz := k.y * CHUNK
	for j in n:
		for i in n:
			var x := ox + (i + rng.randf()) * gstep
			var z := oz + (j + rng.randf()) * gstep
			var r := rng.randf()
			var y := _h(x, z)
			if y <= _land_min:
				continue
			var b := _biome(x, z)
			var type := ""
			var s0 := 0.7
			var s1 := 1.35
			match b:
				&"jungle", &"swamp":
					if r < 0.42:
						type = "grass"
					elif r < 0.62:
						type = "fern%d" % rng.randi_range(0, 3)
						s0 = 0.8; s1 = 1.6
				&"meadow":
					if r < 0.7:
						type = "grass"
						s0 = 0.75; s1 = 1.45
					elif r < 0.74:
						type = "fern%d" % rng.randi_range(0, 3)
				&"beach":
					if y > 0.9 and r < 0.12:
						type = "grass"; s0 = 0.5; s1 = 0.9
				&"rocky":
					if r < 0.08:
						type = "grass"; s0 = 0.5; s1 = 0.9
				&"water":
					pass
				_:
					if r < 0.4:
						type = "grass"
			if type == "":
				continue
			if not sets.has(type):
				sets[type] = []
			var bs := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(s0, s1))
			(sets[type] as Array).append(Transform3D(bs, Vector3(x, y - 0.04, z)))
			stats["fern" if type.begins_with("fern") else "grass"] += 1
	var out: Array = []
	var ferns := ["fern_02_a", "fern_02_b", "fern_02_c", "fern_02_d"]
	for type in sets:
		var mesh: Mesh = FloraLib.grass_mesh() if type == "grass" else FloraLib.first_mesh("res://assets/models/polyhaven/%s.glb" % ferns[int(String(type).substr(4))])
		if mesh == null:
			continue
		var xs: Array = sets[type]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xs.size()
		for i in xs.size():
			mm.set_instance_transform(i, xs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Decor_%s_%d_%d" % [type, k.x, k.y]
		mmi.multimesh = mm
		_detail_range(mmi, GRASS_RANGE if type == "grass" else FERN_RANGE)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		out.append(mmi)
	return out

# --------------------------------------------------------------- API для ботов/модулей

func _kinds_for(kind: StringName) -> Array:
	if kind == &"":
		return []
	if ITEM_SOURCES.has(kind):
		return ITEM_SOURCES[kind]
	return [kind]

## Узлы-ресурсы рядом (по возрастанию расстояния): [{kind, position, node (может быть null — далеко,
## см. materialize), rec, distance}]. Срубленные/собранные/выработанные не возвращаются.
## kind: вид (&"palm", &"liana", &"boulder", &"iron_ore", &"stick"…), группа (&"tree", &"crop", &"ore")
## или id предмета (&"fiber", &"food", &"seed_maize"…); &"" — всё.
func nodes_near(pos: Vector3, r: float, kind: StringName = &"") -> Array[Dictionary]:
	var kinds := _kinds_for(kind)
	var out: Array[Dictionary] = []
	for rec in _recs_in(pos, r):
		if int(rec["state"]) != 0:
			continue
		if not kinds.is_empty() and not kinds.has(rec["kind"]):
			continue
		if kind == &"coconut" and rec["kind"] == &"palm":
			var t = rec["node"]
			if t != null and is_instance_valid(t) and (t as ChoppableTree).coconuts <= 0:
				continue
		var d := pos.distance_to(rec["pos"])
		if d > r:
			continue
		var n = rec["node"]
		out.append({"kind": rec["kind"], "position": rec["pos"], "node": n if n != null and is_instance_valid(n) else null, "rec": rec, "distance": d})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["distance"] < b["distance"])
	return out

## Получить узел для записи из nodes_near (дерево — будит, остальное — создаёт). null — уже нет.
func materialize(entry: Dictionary) -> Node:
	var rec: Dictionary = entry.get("rec", entry)
	if int(rec.get("state", 2)) == 2:
		return null
	if rec["t"] == T_TREE:
		return promote(rec)
	var n = rec["node"]
	if n != null and is_instance_valid(n):
		return n
	return _spawn_node(rec)

## Сколько осталось (статистика/мини-карта): {kind: count} живых записей.
func remaining() -> Dictionary:
	var out := {}
	for k in _grid:
		for rec in _grid[k]:
			if int(rec["state"]) == 0:
				out[rec["kind"]] = int(out.get(rec["kind"], 0)) + 1
	return out

# --------------------------------------------------------------- общие помощники

## Инструмент удара: hit.tool → by.current_tool / by.get_tool() → игрок с топором → рука.
static func tool_of(by: Node, hit: Dictionary) -> StringName:
	if hit.has("tool"):
		return StringName(hit["tool"])
	if by:
		if by.has_method(&"get_tool"):
			return StringName(by.call(&"get_tool"))
		var ct = by.get(&"current_tool")
		if ct != null and String(ct) != "":
			return StringName(ct)
		if by.is_in_group(&"player"):
			return &"axe" # пока у игрока в руках только топор-заглушка
	return &"hand"

## Выдать предмет персонажу: Items.give → узел Inventory → запасной словарь (meta).
static func give(ch: Node, id: StringName, n: int) -> void:
	if ch == null or n <= 0:
		return
	if Items.has_method(&"give"):
		Items.call(&"give", ch, id, n)
	elif ch.has_node(^"Inventory"):
		ch.get_node(^"Inventory").call(&"add", id, n)
	else:
		var inv: Dictionary = ch.get_meta(&"flora_inventory", {})
		inv[id] = int(inv.get(id, 0)) + n
		ch.set_meta(&"flora_inventory", inv)
		Events.inventory_changed.emit(ch)
	if ch.is_in_group(&"player"):
		Events.toast.emit("+%d %s" % [n, Items.item_name(id)])

## Сколько у персонажа предмета (для тестов и ботов при отсутствии Inventory).
static func count_of(ch: Node, id: StringName) -> int:
	if ch.has_node(^"Inventory"):
		return int(ch.get_node(^"Inventory").call(&"count", id))
	var inv: Dictionary = ch.get_meta(&"flora_inventory", {})
	return int(inv.get(id, 0))

static var _streams: Dictionary = {}
## Живые плееры play_sfx: при выходе из матча их останавливаем (см. _exit_tree).
static var _live_sfx: Array = []
## Записи-серии: WoodCutAxe — 18 с, ~30 ударов подряд; на один удар топора играем
## один удар серии (начала громких ударов, с), а не всю запись (было: 18 с рубки
## на каждый взмах, плееры копились, а при выходе — «resources still in use»).
const SFX_SLICES := {
	"WEAPAxe_WoodCutAxe_OS_01": {"starts": [0.03, 1.38, 4.56, 5.02, 11.82], "len": 0.4},
}

static func play_sfx(from: Node, sound: String, pos: Vector3, db: float = 0.0, pitch: float = 1.0) -> void:
	if from == null or not from.is_inside_tree():
		return
	# дальше слышимости (max_distance 90 м) — не создаём плеер (боты рубят далеко)
	var cam := from.get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_to(pos) > 90.0:
		return
	var path := "res://assets/sounds/oculus_pack/%s.ogg" % sound
	if not _streams.has(path):
		_streams[path] = load(path) if ResourceLoader.exists(path) else null
	var stream: AudioStream = _streams[path]
	if stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = db
	p.pitch_scale = pitch
	p.unit_size = 8.0
	p.max_distance = 90.0
	from.get_tree().current_scene.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	if _live_sfx.size() > 24:
		_live_sfx = _live_sfx.filter(func(x: Variant) -> bool: return is_instance_valid(x))
	_live_sfx.append(p)
	var sl: Dictionary = SFX_SLICES.get(sound, {})
	if sl.is_empty():
		p.play()
	else:
		var starts: Array = sl.starts
		p.play(float(starts[randi() % starts.size()]))
		from.get_tree().create_timer(float(sl.len) / maxf(pitch, 0.1), false).timeout.connect(p.queue_free)

## Выход из матча/игры: звуки, ещё играющие в этот момент, остаются в аудиосервере
## навсегда («N resources still in use at exit»), если остановленное воспроизведение
## не успел снять аудиопоток. Останавливаем и даём ему несколько тактов микширования.
## (Плееры к этому моменту уже могли выйти из дерева — тогда они на паузе, не «playing»,
## поэтому останавливаем все ещё не удалённые.)
static func stop_all_sfx() -> void:
	var n := 0
	for p in _live_sfx:
		if is_instance_valid(p):
			p.stop()
			n += 1
	_live_sfx.clear()
	_streams.clear()
	if n > 0:
		OS.delay_msec(STOP_WAIT_MS)

const STOP_WAIT_MS := 200

static var _chip_meshes: Dictionary = {}

## Меш щепки по цвету — общий (раньше на каждый удар создавались новые меш+материал;
## щепки, не успевшие исчезнуть к выходу из игры, давали «resources still in use»).
static func _chip_mesh(color: Color) -> BoxMesh:
	var key := color.to_html()
	if _chip_meshes.has(key):
		return _chip_meshes[key]
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.02, 0.03)
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	bm.material = m
	_chip_meshes[key] = bm
	return bm

## Щепки/листья/каменная крошка.
static func chips(parent: Node, pos: Vector3, color: Color, amount: int) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var cp := CPUParticles3D.new()
	cp.one_shot = true
	cp.explosiveness = 0.95
	cp.amount = amount
	cp.lifetime = 0.9
	cp.mesh = _chip_mesh(color)
	cp.direction = Vector3.UP
	cp.spread = 70.0
	cp.initial_velocity_min = 1.5
	cp.initial_velocity_max = 3.5
	cp.gravity = Vector3(0, -9.8, 0)
	cp.angular_velocity_min = -400.0
	cp.angular_velocity_max = 400.0
	parent.add_child(cp)
	cp.global_position = pos
	cp.emitting = true
	parent.get_tree().create_timer(1.5).timeout.connect(cp.queue_free)

## Ближайшие живые деревья (будит их): kind = &"" — любые.
func trees_near(pos: Vector3, radius: float, kind: StringName = &"") -> Array[ChoppableTree]:
	var out: Array[ChoppableTree] = []
	for e in nodes_near(pos, radius, kind if kind != &"" else &"tree"):
		var rec: Dictionary = e["rec"]
		if rec["t"] != T_TREE:
			continue
		var t := promote(rec)
		if t and not t.felled:
			out.append(t)
	return out
