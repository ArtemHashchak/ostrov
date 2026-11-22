class_name CreatureSpawner
extends Node3D
## Призыв существ и растений «по требованию» — для консоли разработчика (DevConsole) и
## «Каталога существ» полигона. Список видов собирается ЖИВЬЁМ из реестров игры, поэтому
## новые модели (их добавляют в реестры) появляются здесь сами:
##   animals / birds — Animal.SPECIES (fly = птица);
##   sea            — OceanRoster (сцены моря: модели пака, дублёры, акулы с ИИ) + виды пака
##                    пользователя (UserSeaPack), не занятые составом;
##   plants         — деревья Flora.VARIANTS, ресурсы ResourceNode.INFO, валуны, растения моря;
##   плюс файлы res://assets/**/creature_catalog*.json — [{id, name, cat, scene}] —
##   и CreatureSpawner.register(id, info) из кода.
## API: CreatureSpawner.spawn(id, pos, n, radius) → сколько поставлено в очередь;
##      CreatureSpawner.all_species() → [{id, name, cat, src, ...}].
## Ставит партиями (BATCH за кадр), лимиты: MAX_PER_CMD за команду и MAX_TOTAL всего.
## Морские существа — настоящие особи с поведением (SeaCritter/UserSeaActor/акулы), не клетки.

const BATCH := 25
const MAX_PER_CMD := 500
const MAX_TOTAL := 2500
const CATS := {"animals": "Животные", "birds": "Птицы", "sea": "Море", "plants": "Растения"}
const CAT_ALIASES := {"животные": "animals", "звери": "animals", "animals": "animals", "animal": "animals",
	"птицы": "birds", "birds": "birds", "bird": "birds", "море": "sea", "морские": "sea", "sea": "sea",
	"рыбы": "sea", "fish": "sea", "растения": "plants", "plants": "plants", "plant": "plants",
	"все": "all", "всё": "all", "all": "all"}
const SHARK_IDS := {"reef": "Рифовая акула", "tiger": "Тигровая акула", "white": "Большая белая акула"}

static var _extra: Dictionary = {}       # id → info (register())
static var _cache: Array[Dictionary] = []
static var _cache_t := -100000

## Учёт созданного: [{node, id, cat}]
var spawned: Array[Dictionary] = []
var _queue: Array[Dictionary] = []      # [{info, pos, radius, left, done}]
var _sea_stage: SeaScene = null
var _rng := RandomNumberGenerator.new()
var _seed := 5000

signal spawned_batch(id: String, n: int)

# ============================== синглтон ==============================

static func instance() -> CreatureSpawner:
	var ml := Engine.get_main_loop() as SceneTree
	if ml == null:
		return null
	var cs := ml.get_first_node_in_group(&"creature_spawner") as CreatureSpawner
	if cs:
		return cs
	var w := ml.get_first_node_in_group(&"world")
	var host: Node = w.get_parent() if w and w.get_parent() else ml.current_scene
	if host == null:
		return null
	cs = CreatureSpawner.new()
	host.add_child(cs)
	return cs

func _ready() -> void:
	name = "CreatureSpawner"
	add_to_group(&"creature_spawner")
	_rng.randomize()

## Добавить вид из кода (например, импорт новой модели): info = {name, cat, scene|spawn: Callable}.
static func register(id: String, info: Dictionary) -> void:
	var d := info.duplicate()
	d["id"] = id
	d["src"] = String(d.get("src", "scene" if d.has("scene") else "callable"))
	_extra[id] = d
	_cache_t = -100000

# ============================== каталог ==============================

## Все виды, которые можно призвать (кэш на 2 с — список живой).
static func all_species(cat: String = "all") -> Array[Dictionary]:
	var now := Time.get_ticks_msec()
	if now - _cache_t > 2000 or _cache.is_empty():
		_cache = _collect()
		_cache_t = now
	if cat == "all" or cat == "":
		return _cache
	var out: Array[Dictionary] = []
	for d in _cache:
		if d.cat == cat:
			out.append(d)
	return out

static func _collect() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	# --- фауна суши и птицы
	for sp: StringName in Animal.SPECIES.keys():
		var cfg: Dictionary = Animal.SPECIES[sp]
		var d := {"id": String(sp), "name": String(cfg.get("name", sp)), "src": "fauna",
			"cat": "birds" if bool(cfg.get("fly", false)) else "animals"}
		out.append(d)
		seen[d.id] = true
	# --- акулы с ИИ
	for k: String in SHARK_IDS:
		var id := "shark_" + k
		out.append({"id": id, "name": SHARK_IDS[k], "src": "shark", "shark": k, "cat": "sea"})
		seen[id] = true
	# --- состав океана (сцены моря)
	var shark_names := {}
	for d: Dictionary in OceanRoster.all_species():
		var id := String(d.get("id", ""))
		if id == "" or seen.has(id):
			continue
		var vis := OceanRoster.visual(d)
		var kind := String(vis.get("kind", "proxy"))
		match kind:
			"bird":
				continue                         # птицы фауны уже в списке
			"crab":
				if id == "crab":
					continue
			"shark_ai":
				var sk := String(vis.get("species", "reef"))
				if shark_names.has(sk) or seen.has("shark_" + sk):
					continue
		out.append({"id": id, "name": String(d.get("name", id)), "src": "roster", "kind": kind, "cat": "sea"})
		seen[id] = true
	# --- виды пака пользователя, не занятые составом
	var used := {}
	for d: Dictionary in OceanRoster.all_species():
		used[String(d.get("model", ""))] = true
		used[String((d.get("stand_in", {}) as Dictionary).get("pack", ""))] = true
	for d: Dictionary in UserSeaPack.species_list():
		var id := String(d.get("id", ""))
		if id == "" or seen.has(id) or used.has(id):
			continue
		out.append({"id": id, "name": String(d.get("name", id)), "src": "pack", "cat": "sea"})
		seen[id] = true
	# --- растения: деревья, ресурсы, валуны, растения моря
	const TREE_NAMES := {&"palm": "Кокосовая пальма", &"broadleaf": "Лиственное дерево", &"mangrove": "Мангр", &"banyan": "Баньян"}
	for k: StringName in Flora.VARIANTS.keys():
		out.append({"id": String(k), "name": String(TREE_NAMES.get(k, k)), "src": "tree", "cat": "plants",
			"variants": int(Flora.VARIANTS[k])})
		seen[String(k)] = true
	for k: StringName in ResourceNode.INFO.keys():
		if seen.has(String(k)):
			continue
		var t := String((ResourceNode.INFO[k] as Dictionary).get("title", k))
		out.append({"id": String(k), "name": t.substr(0, 1).to_upper() + t.substr(1), "src": "resource", "cat": "plants"})
		seen[String(k)] = true
	out.append({"id": "boulder", "name": "Валун", "src": "rock", "cat": "plants"})
	for d: Dictionary in OceanRoster.all_plants():
		var id := String(d.get("id", ""))
		if id == "" or seen.has(id):
			continue
		out.append({"id": id, "name": String(d.get("name", id)), "src": "sea_plant", "cat": "plants"})
		seen[id] = true
	# --- каталоги из файлов и register()
	for d: Dictionary in _file_entries():
		if not seen.has(String(d.id)):
			out.append(d)
			seen[String(d.id)] = true
	for id: String in _extra:
		var d: Dictionary = _extra[id]
		if seen.has(id):
			for i in out.size():
				if out[i].id == id:
					out[i] = d
		else:
			out.append(d)
	return out

## res://assets/**/creature_catalog*.json: [{id, name, cat, scene, scale?, height?}]
static func _file_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var paths: Array[String] = []
	_scan("res://assets", paths, 0)
	for p in paths:
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
		if v is Array:
			for e: Variant in v:
				if e is Dictionary and (e as Dictionary).has("id") and (e as Dictionary).has("scene"):
					var d := (e as Dictionary).duplicate()
					d["id"] = String(d.id)
					d["src"] = "scene"
					d["cat"] = String(d.get("cat", "animals"))
					d["name"] = String(d.get("name", d.id))
					out.append(d)
	return out

static func _scan(dir_path: String, out: Array[String], depth: int) -> void:
	if depth > 3:
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for f in dir.get_files():
		if f.begins_with("creature_catalog") and f.ends_with(".json"):
			out.append(dir_path.path_join(f))
	for sub in dir.get_directories():
		if not sub.begins_with(".") and not sub.begins_with("_"):
			_scan(dir_path.path_join(sub), out, depth + 1)

## Найти вид по id или по названию (без регистра; точное → начало → вхождение).
static func find(q: String) -> Dictionary:
	var s := q.strip_edges().to_lower().replace("ё", "е")
	if s == "":
		return {}
	var list := all_species()
	for d in list:
		if String(d.id).to_lower() == s or String(d.name).to_lower().replace("ё", "е") == s:
			return d
	for d in list:
		if String(d.id).to_lower().begins_with(s) or String(d.name).to_lower().replace("ё", "е").begins_with(s):
			return d
	for d in list:
		if String(d.name).to_lower().replace("ё", "е").contains(s) or String(d.id).to_lower().contains(s):
			return d
	return {}

static func cat_of(q: String) -> String:
	return String(CAT_ALIASES.get(q.strip_edges().to_lower(), ""))

# ============================== призыв ==============================

## Поставить в очередь n особей вида id вокруг pos. Возвращает сколько поставлено
## (с учётом лимитов), -1 — вид не найден.
static func spawn(id: String, pos: Vector3, n: int = 1, radius: float = -1.0) -> int:
	var cs := instance()
	if cs == null:
		return -1
	return cs.request(id, pos, n, radius)

func request(id: String, pos: Vector3, n: int = 1, radius: float = -1.0) -> int:
	var info := find(id)
	if info.is_empty():
		return -1
	n = clampi(n, 1, MAX_PER_CMD)
	var room := MAX_TOTAL - live_count() - queued()
	n = mini(n, maxi(room, 0))
	if n <= 0:
		return 0
	if radius < 0.0:
		radius = clampf(sqrt(float(n)) * (2.4 if info.cat == "sea" else 1.4), 1.5, 45.0)
		if info.src == "tree":
			radius = clampf(sqrt(float(n)) * 5.0, 3.0, 80.0)
	_queue.append({"info": info, "pos": pos, "radius": radius, "left": n, "done": 0})
	return n

func queued() -> int:
	var k := 0
	for q in _queue:
		k += int(q.left)
	return k

func _process(delta: float) -> void:
	if _sea_stage and is_instance_valid(_sea_stage):
		_sea_stage.tick(delta)
	if _queue.is_empty():
		return
	var budget := BATCH
	while budget > 0 and not _queue.is_empty():
		var q: Dictionary = _queue[0]
		var k := mini(budget, int(q.left))
		var made := _spawn_some(q.info, q.pos, q.radius, k)
		q.left = int(q.left) - k
		q.done = int(q.done) + made
		budget -= k
		if int(q.left) <= 0:
			_queue.pop_front()
			spawned_batch.emit(String((q.info as Dictionary).id), int(q.done))

## Сразу (без очереди) — для тестов и каталога.
func spawn_now(id: String, pos: Vector3, n: int = 1, radius: float = -1.0) -> int:
	var info := find(id)
	if info.is_empty():
		return -1
	if radius < 0.0:
		radius = clampf(sqrt(float(n)) * 1.4, 1.5, 45.0)
	return _spawn_some(info, pos, radius, clampi(n, 1, MAX_PER_CMD))

func _spawn_some(info: Dictionary, c: Vector3, r: float, n: int) -> int:
	var made := 0
	var src := String(info.src)
	if src == "fauna" and info.cat == "birds":
		var fa := Fauna.instance()
		if fa == null:
			return 0
		var left := n
		while left > 0:
			var k := mini(left, 8)
			for a in fa.spawn_flock(StringName(info.id), _disc(c, r), k, 12.0):
				_track(a, info)
				made += 1
			left -= k
		return made
	for i in n:
		var node := _spawn_one(info, _disc(c, r), r)
		if node:
			_track(node, info)
			made += 1
	return made

func _track(n: Node, info: Dictionary) -> void:
	spawned.append({"node": n, "id": String(info.id), "cat": String(info.cat), "src": String(info.src)})

func _disc(c: Vector3, r: float) -> Vector3:
	var a := _rng.randf() * TAU
	var rr := sqrt(_rng.randf()) * r
	return c + Vector3(cos(a) * rr, 0.0, sin(a) * rr)

func _world() -> Node:
	return get_tree().get_first_node_in_group(&"world")

func _sea() -> Sea:
	return get_tree().get_first_node_in_group(&"sea") as Sea

func _ground(x: float, z: float) -> float:
	var w := _world()
	return float(w.call(&"height_at", x, z)) if w else 0.0

func _water() -> float:
	var s := _sea()
	if s:
		return s.water_y()
	var w := _world()
	return float(w.call(&"water_level")) if w else 0.0

## Точка в воде у p: глубина ≥ 0.8 м; ищет кольцами до 40 м. null — воды нет.
func _water_point(p: Vector3, bottom: bool) -> Variant:
	var wy := _water()
	for ring in 9:
		for k in (1 if ring == 0 else 6):
			var a := _rng.randf() * TAU
			var q := p + Vector3(cos(a), 0, sin(a)) * float(ring) * 5.0
			var fl := _ground(q.x, q.z)
			var dep := wy - fl
			if dep >= 0.8:
				q.y = fl + 0.15 if bottom else _rng.randf_range(fl + 0.4, wy - 0.4)
				return q
	return null

func _spawn_one(info: Dictionary, p: Vector3, _r: float) -> Node:
	var src := String(info.src)
	_seed += 1
	match src:
		"fauna":
			var fa := Fauna.instance()
			if fa == null:
				return null
			var g := _ground(p.x, p.z)
			var a := fa.spawn(StringName(info.id), Vector3(p.x, maxf(g, _water() - 0.1 if info.id == "turtle" else g) + 0.05, p.z), 14.0)
			return a
		"shark":
			var s := _sea()
			if s == null:
				return null
			var sh := s.spawn_shark(StringName(info.shark), Vector2(p.x, p.z), 4.0 + _rng.randf() * 6.0, _seed * 101)
			return sh
		"roster":
			return _spawn_roster(info, p)
		"pack":
			return _spawn_pack(String(info.id), p)
		"tree":
			var t := ChoppableTree.new()
			t.setup(FloraLib.variant(StringName(info.id), _rng.randi_range(0, int(info.get("variants", 1)) - 1)))
			add_child(t)
			t.global_position = Vector3(p.x, _ground(p.x, p.z) - 0.12, p.z)
			t.rotation.y = _rng.randf() * TAU
			return t
		"resource":
			var rn := ResourceNode.new().setup(StringName(info.id), _rng.randi_range(0, 5))
			add_child(rn)
			rn.global_position = Vector3(p.x, _ground(p.x, p.z) - 0.05, p.z)
			rn.rotation.y = _rng.randf() * TAU
			return rn
		"rock":
			var rr := ResourceRock.new()
			rr.scene_path = UserRocks.path(_rng.randi_range(0, 5)) if UserRocks.available() \
				else "res://assets/models/polyhaven/%s.glb" % Flora.BOULDERS[0]
			rr.size = _rng.randf_range(0.9, 1.8)
			rr.units = 6
			add_child(rr)
			rr.global_position = Vector3(p.x, _ground(p.x, p.z), p.z)
			rr.rotation.y = _rng.randf() * TAU
			return rr
		"sea_plant":
			var q: Variant = _water_point(p, true)
			if q == null:
				return null
			var st := _stage()
			if st == null:
				return null
			return st.plant_patch(String(info.id), q as Vector3, 1.5, 6)
		"scene":
			var ps := load(String(info.scene)) as PackedScene
			if ps == null:
				return null
			var n := ps.instantiate() as Node3D
			add_child(n)
			var y := _ground(p.x, p.z)
			if info.cat == "sea":
				var q2: Variant = _water_point(p, false)
				if q2 != null:
					y = (q2 as Vector3).y
			elif info.cat == "birds":
				y += 8.0
			n.global_position = Vector3(p.x, y + float(info.get("height", 0.0)), p.z)
			n.rotation.y = _rng.randf() * TAU
			if info.has("scale"):
				n.scale = Vector3.ONE * float(info.scale)
			return n
		"callable":
			var cb: Callable = info.get("spawn", Callable())
			if cb.is_valid():
				return cb.call(p) as Node
	return null

## Сцена-контейнер для морских существ консоли (тикает сам spawner; бессрочная).
func _stage() -> SeaScene:
	if _sea_stage and is_instance_valid(_sea_stage):
		return _sea_stage
	var s := _sea()
	var sea_obj: Object = s if s else self
	_sea_stage = SeaScene.new()
	_sea_stage.name = "ConsoleSeaStage"
	_sea_stage.duration = -1.0
	add_child(_sea_stage)
	_sea_stage.sea = sea_obj
	_sea_stage.rng.seed = 424242
	return _sea_stage

## Заглушка моря (если модуля моря нет): вода — уровень мира, дно — рельеф.
func water_y() -> float:
	return _water()

func floor_at(x: float, z: float) -> float:
	return _ground(x, z)

func depth_at(x: float, z: float) -> float:
	return _water() - _ground(x, z)

func _spawn_roster(info: Dictionary, p: Vector3) -> Node:
	var sp := OceanRoster.species(String(info.id))
	var vis := OceanRoster.visual(sp)
	var st := _stage()
	match String(vis.get("kind", "proxy")):
		"crab":
			var fa := Fauna.instance()
			if fa == null:
				return null
			var a := fa.spawn(&"crab", Vector3(p.x, _ground(p.x, p.z) + 0.05, p.z), 10.0)
			if a:
				a.scale = Vector3.ONE * float(vis.get("scale", 1.0))
			return a
		"shark_ai":
			var s := _sea()
			return s.spawn_shark(StringName(vis.get("species", "reef")), Vector2(p.x, p.z), 6.0, _seed * 101) if s else null
		"school_mesh":
			var q: Variant = _water_point(p, false)
			if q == null:
				return null
			return st.school(String(info.id), 24, q as Vector3, 3.0)
	var bottom := String(sp.get("group", "")) in ["echinoderm", "crustacean", "mollusc"]
	var q3: Variant = _water_point(p, bottom)
	if q3 == null:
		return null
	var c := st.critter(String(info.id), q3 as Vector3)
	if c:
		c.wander(q3 as Vector3, clampf(float(sp.get("roam", 6.0)), 2.0, 12.0))
	return c

func _spawn_pack(id: String, p: Vector3) -> Node:
	var d := {}
	for e: Dictionary in UserSeaPack.species_list():
		if String(e.get("id", "")) == id:
			d = e
			break
	if d.is_empty():
		return null
	var mgr := get_tree().get_first_node_in_group(&"user_sea_actors") as UserSeaActors
	var q: Variant = _water_point(p, UserSeaActor._kind_of(d) == "octopus")
	if mgr == null or q == null:
		return null
	return mgr.spawn_at(d, mgr.to_local(q as Vector3), _rng.randf() * TAU)

# ============================== учёт, убрать, приручить ==============================

func _prune() -> void:
	var keep: Array[Dictionary] = []
	for e in spawned:
		var n: Variant = e.node
		if n != null and is_instance_valid(n) and not (n as Node).is_queued_for_deletion():
			keep.append(e)
	spawned = keep

static func _is_dead(n: Node) -> bool:
	if n is Animal:
		return (n as Animal).dead
	var dv: Variant = n.get(&"dead")
	if dv is bool and dv:
		return true
	if n is Shark:
		return (n as Shark).state == Shark.State.DEAD
	return false

## Живые созданные консолью (вид "" — все; кат "" — все).
func live_count(id: String = "", cat: String = "") -> int:
	_prune()
	var k := 0
	for e in spawned:
		if (id == "" or e.id == id) and (cat == "" or e.cat == cat) and not _is_dead(e.node):
			k += 1
	return k

## По видам: {id: n} — живые созданные консолью.
func census() -> Dictionary:
	_prune()
	var out := {}
	for e in spawned:
		if not _is_dead(e.node):
			out[e.id] = int(out.get(e.id, 0)) + 1
	return out

## Убить живых вида id ("" — всех) в радиусе r от c (r<=0 — везде). Животные мира тоже.
func kill(id: String, c: Vector3, r: float) -> int:
	_prune()
	var k := 0
	var done := {}
	for e in spawned:
		var n: Node = e.node
		if (id == "" or e.id == id) and not _is_dead(n) and _in(n, c, r):
			k += _kill_node(n)
			done[n] = true
	var fa := Fauna.instance()
	if fa:
		for a in fa.animals:
			if is_instance_valid(a) and not a.dead and not done.has(a) and (id == "" or String(a.species) == id) and _in(a, c, r) and not a.tamed:
				a.die(null)
				k += 1
	if id == "" or id.begins_with("shark"):
		var s := _sea()
		if s:
			for sh: Shark in s.sharks.duplicate():
				if is_instance_valid(sh) and not done.has(sh) and _in(sh, c, r) and sh.state != Shark.State.DEAD:
					if id == "" or id == "shark_" + String(sh.get(&"species")):
						k += _kill_node(sh)
	return k

func _kill_node(n: Node) -> int:
	if n is Animal:
		(n as Animal).die(null)
		return 1
	if n.has_method(&"die"):
		n.call(&"die")
		return 1
	if n.has_method(&"apply_damage") and not (n is ChoppableTree):
		n.call(&"apply_damage", 99999.0, null, &"melee")
		return 1
	n.queue_free()
	return 1

func _in(n: Node, c: Vector3, r: float) -> bool:
	return r <= 0.0 or not (n is Node3D) or (n as Node3D).global_position.distance_to(c) <= r

## Убрать всё созданное консолью (и трупы) в радиусе r (r<=0 — всё). Возвращает сколько.
func clear(c: Vector3, r: float) -> int:
	_prune()
	var k := 0
	var keep: Array[Dictionary] = []
	var fa := Fauna.instance()
	var s := _sea()
	for e in spawned:
		var n: Node = e.node
		if _in(n, c, r):
			if n is Animal and fa:
				fa.animals.erase(n)
				if (n as Animal).flock is Dictionary and fa.flocks.has((n as Animal).flock):
					var mem: Array = ((n as Animal).flock as Dictionary).get("members", [])
					mem.erase(n)
					if mem.is_empty():
						fa.flocks.erase((n as Animal).flock)
			if n is Shark and s:
				s.sharks.erase(n)
			if _sea_stage and is_instance_valid(_sea_stage):
				if n is SeaCritter:
					_sea_stage.critters.erase(n)
				elif n is SeaSchool:
					_sea_stage.schools.erase(n)
				elif n is MultiMeshInstance3D:
					_sea_stage.plants.erase(n)
			var mgr := get_tree().get_first_node_in_group(&"user_sea_actors") as UserSeaActors
			if mgr and n is UserSeaActor:
				mgr.actors.erase(n)
			n.queue_free()
			k += 1
		else:
			keep.append(e)
	spawned = keep
	return k

## Приручить живых вида id в радиусе r. Возвращает сколько (только те, кто приручается).
func tame(id: String, owner_: Node, c: Vector3, r: float) -> int:
	var fa := Fauna.instance()
	if fa == null:
		return 0
	var k := 0
	for a in fa.animals:
		if is_instance_valid(a) and not a.dead and not a.tamed and String(a.species) == id and _in(a, c, r) \
				and bool(a.cfg.get("tame", false)):
			fa.tame(a, owner_)
			k += 1
	return k
