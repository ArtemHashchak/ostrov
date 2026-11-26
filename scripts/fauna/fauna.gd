class_name Fauna
extends Node3D
## Менеджер животных: спавн по островам/биомам, LOD-тик, стаи птиц, яд, приручение,
## разведение, гнёзда черепах. Подключается match.gd в слот Fauna (scenes/fauna/fauna.tscn).
## Дикие НЕ восстанавливаются: начальная популяция создаётся один раз; новые животные
## появляются только от разведения приручённых и вылупления черепашат.

const AnimalScript := preload("res://scripts/fauna/animal.gd")
const NestScript := preload("res://scripts/fauna/turtle_nest.gd")

@export var auto_populate: bool = true
@export var density: float = 1.0          # множитель численности
@export var max_animals: int = 170
@export var seed_value: int = 7331

var world: Node = null
var clock: float = 0.0
var grow_seconds: float = 240.0           # рост детёныша до взрослого
var breed_seconds: float = 60.0           # беременность
var breed_cd_seconds: float = 480.0
var fed_window: float = 180.0             # «сытость» после кормления, нужна для разведения
var force_nesting: bool = false           # тесты: черепахи кладут яйца днём
var force_night_birds: bool = false       # тесты: летучие мыши видимы днём
var force_night: bool = false
var populated: bool = false

var animals: Array[Animal] = []
var flocks: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _frame: int = 0
var _breed_t: float = 0.0

static var _inst: Fauna = null

static func instance() -> Fauna:
	return _inst if _inst and is_instance_valid(_inst) else null

func _ready() -> void:
	_inst = self
	add_to_group(&"fauna")
	FaunaItems.register()
	_rng.seed = seed_value
	_find_world.call_deferred()

func _exit_tree() -> void:
	if _inst == self:
		_inst = null

func _find_world() -> void:
	world = get_tree().get_first_node_in_group(&"world")
	if world == null:
		# тестовый остров: ищем предка/сцену с height_at
		var n: Node = get_parent()
		while n and not n.has_method(&"height_at"):
			n = n.get_parent()
		if n == null:
			var cs := get_tree().current_scene
			if cs and cs.has_method(&"height_at"):
				n = cs
		world = n
	if not auto_populate:
		return
	if world and world.has_signal(&"world_ready") and not bool(world.get(&"is_ready")):
		world.connect(&"world_ready", populate, CONNECT_ONE_SHOT)
	else:
		populate.call_deferred()

# ============================== мир (статические помощники) ==============================

static func _world_of(_n: Node) -> Node:
	var f := instance()
	return f.world if f else null

static func ground_y_at(n: Node, x: float, z: float) -> float:
	var w := _world_of(n)
	if w and w.has_method(&"height_at"):
		return float(w.call(&"height_at", x, z))
	return 0.0

static func water_y(n: Node) -> float:
	var w := _world_of(n)
	if w and w.has_method(&"water_level"):
		return float(w.call(&"water_level"))
	return 0.0

static func is_night_now(n: Node) -> bool:
	var f := instance()
	if f and f.force_night:
		return true
	var w := _world_of(n)
	if w and w.has_method(&"is_night"):
		return bool(w.call(&"is_night"))
	return false

static func biome_of(n: Node, x: float, z: float) -> StringName:
	var w := _world_of(n)
	if w and w.has_method(&"biome_at"):
		return w.call(&"biome_at", x, z)
	var g := ground_y_at(n, x, z)
	var wl := water_y(n)
	if g < wl:
		return &"water"
	if g < wl + 1.3:
		return &"beach"
	var gx := ground_y_at(n, x + 1.0, z) - g
	var gz := ground_y_at(n, x, z + 1.0) - g
	if Vector2(gx, gz).length() > 0.75:
		return &"rocky"
	return &"jungle" if sin(x * 0.07) * cos(z * 0.06) > -0.3 else &"meadow"

func islands_list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if world and world.has_method(&"islands"):
		for d in world.call(&"islands"):
			out.append(d)
	if out.is_empty():
		var r := 10.0
		while r < 400.0 and ground_y_at(self, r, 0.0) > water_y(self):
			r += 4.0
		out.append({"id": 0, "kind": &"shared", "team": -1, "center": Vector2.ZERO, "radius": r, "name": "Остров"})
	return out

# ============================== спавн ==============================

func spawn(sp: StringName, pos: Vector3, home_r: float = 25.0) -> Animal:
	var a: Animal = AnimalScript.create(sp, pos, self)
	a.home_r = home_r
	add_child(a)
	a.global_position = pos
	a.add_to_group(&"wild_animals")
	a.died.connect(_on_died)
	animals.append(a)
	return a

## Стая птиц/летучих мышей вокруг центра. Возвращает созданных.
func spawn_flock(sp: StringName, center: Vector3, n: int, radius: float = 40.0) -> Array[Animal]:
	var g := ground_y_at(self, center.x, center.z)
	var fl := {"species": sp, "home": Vector3(center.x, g, center.z), "r": radius, "mode": &"fly",
		"pos": Vector3(center.x, g + 10.0, center.z), "target": Vector3(center.x, g + 10.0, center.z), "t": 0.0,
		"perch": Vector3.INF, "members": []}  # точку посадки выбирают на кроне (_find_perch)
	flocks.append(fl)
	var out: Array[Animal] = []
	for i in n:
		var off := Vector3(_rng.randf_range(-3, 3), _rng.randf_range(-1.2, 1.2), _rng.randf_range(-3, 3))
		if sp == &"bat":
			off *= 0.7
		var a := spawn(sp, fl["pos"] + off, radius)
		a.flock = fl
		a.flock_offset = off
		a.alt = 10.0
		(fl["members"] as Array).append(a)
		out.append(a)
	return out

func make_nest(pos: Vector3, eggs: int) -> Node3D:
	var nest: Node3D = NestScript.new()
	nest.set(&"eggs", eggs)
	nest.set(&"fauna", self)
	add_child(nest)
	nest.global_position = Vector3(pos.x, ground_y_at(self, pos.x, pos.z), pos.z)
	return nest

## Начальная популяция по островам и биомам (один раз).
func populate() -> void:
	if populated:
		return
	populated = true
	for isl in islands_list():
		_populate_island(isl)

func _populate_island(isl: Dictionary) -> void:
	var c2: Vector2 = isl["center"]
	var R: float = isl["radius"]
	var kind := StringName(isl.get("kind", &"shared"))
	var area_k := clampf(pow(R / 45.0, 2.0), 0.35, 3.0) * density
	var danger := 0.45 if kind == &"home" else (1.35 if kind == &"center" else 1.0)
	var wl := water_y(self)
	var buckets := {}
	var shallow: Array[Vector3] = []
	for i in 360:
		var a := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * R * 1.25
		var x := c2.x + cos(a) * r
		var z := c2.y + sin(a) * r
		var g := ground_y_at(self, x, z)
		var p := Vector3(x, g, z)
		if g < wl - 0.35 and g > wl - 1.8 and r > R * 0.5:
			shallow.append(p)
			continue
		var b := biome_of(self, x, z)
		if not buckets.has(b):
			buckets[b] = []
		(buckets[b] as Array).append(p)
	var pick := func(kinds: Array) -> Variant:
		var pool: Array = []
		for k in kinds:
			pool.append_array(buckets.get(k, []))
		if pool.is_empty():
			return null
		return pool[_rng.randi() % pool.size()]
	var count := func(base: float) -> int:
		var v := base
		return int(floor(v)) + (1 if _rng.randf() < v - floor(v) else 0)
	# пляж: крабы группами, черепахи, чайки
	for i in count.call(3.0 * area_k):
		var p: Variant = pick.call([&"beach"])
		if p == null: break
		for k in _rng.randi_range(1, 3):
			_try_spawn(&"crab", p + Vector3(_rng.randf_range(-2, 2), 0, _rng.randf_range(-2, 2)), 10.0)
	if buckets.has(&"beach") and (kind != &"home" or _rng.randf() < 0.5):
		for i in 1 + (1 if kind == &"center" else 0):
			var p: Variant = pick.call([&"beach"])
			if p != null:
				_try_spawn(&"turtle", p, 20.0)
	# раки-отшельники — кучками у кромки пляжа (модели пака, 2026-11-22)
	for i in count.call(1.5 * area_k):
		var p: Variant = pick.call([&"beach"])
		if p == null: break
		for k in _rng.randi_range(2, 4):
			_try_spawn(&"hermit_crab", p + Vector3(_rng.randf_range(-1.5, 1.5), 0, _rng.randf_range(-1.5, 1.5)), 6.0)
	if buckets.has(&"beach") and _room(6):
		var p: Variant = pick.call([&"beach"])
		spawn_flock(&"gull", p, _rng.randi_range(4, 7), R * 0.9)
	# джунгли/луг: кабаны, обезьяны, змеи, пауки, попугаи, игуаны
	for i in count.call(1.6 * area_k):
		var p: Variant = pick.call([&"jungle", &"meadow"])
		if p == null: break
		_try_spawn(&"boar", p, 30.0)
		if _rng.randf() < 0.4:
			var piglet := _try_spawn(&"boar", p + Vector3(1.2, 0, 0.8), 30.0)
			if piglet: piglet.set_growth(0.55)
	if kind != &"home" or _rng.randf() < 0.4:
		var p: Variant = pick.call([&"jungle"])
		if p != null:
			for k in _rng.randi_range(2, 4):
				_try_spawn(&"monkey", p + Vector3(_rng.randf_range(-3, 3), 0, _rng.randf_range(-3, 3)), 30.0)
	for i in count.call(1.2 * area_k * danger):
		var p: Variant = pick.call([&"jungle", &"swamp", &"meadow"])
		if p == null: break
		_try_spawn(&"snake", p, 12.0)
	# питоны — джунгли и болото; сколопендры — подстилка джунглей и скалы; саламандры — сырые места
	for i in count.call(0.6 * area_k * danger):
		var p: Variant = pick.call([&"jungle", &"swamp"])
		if p == null: break
		_try_spawn(&"python", p, 14.0)
	for i in count.call(0.9 * area_k * danger):
		var p: Variant = pick.call([&"jungle", &"rocky"])
		if p == null: break
		_try_spawn(&"centipede", p, 6.0)
	for i in count.call(1.0 * area_k):
		var p: Variant = pick.call([&"swamp", &"jungle"])
		if p == null: break
		for k in _rng.randi_range(1, 2):
			_try_spawn(&"salamander", p + Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)), 5.0)
	for i in count.call(1.4 * area_k * danger):
		var p: Variant = pick.call([&"jungle"])
		if p == null: break
		_try_spawn(&"spider", p, 8.0)
	if buckets.has(&"jungle") and _room(8):
		var p: Variant = pick.call([&"jungle"])
		spawn_flock(&"parrot", p, _rng.randi_range(5, 8), R * 0.8)
	for i in count.call(1.0 * area_k):
		var p: Variant = pick.call([&"meadow", &"jungle", &"beach"])
		if p == null: break
		_try_spawn(&"iguana", p, 15.0)
	# скалы: вараны, скорпионы, летучие мыши
	for i in count.call(0.8 * area_k * danger):
		var p: Variant = pick.call([&"rocky", &"meadow"])
		if p == null: break
		_try_spawn(&"monitor", p, 20.0)
	for i in count.call(2.0 * area_k * danger):
		var p: Variant = pick.call([&"rocky", &"beach"])
		if p == null: break
		_try_spawn(&"scorpion", p, 6.0)
	if (buckets.has(&"rocky") or buckets.has(&"jungle")) and _room(8):
		var p: Variant = pick.call([&"rocky", &"jungle"])
		spawn_flock(&"bat", p, _rng.randi_range(5, 9), 25.0)
	# крокодилы — засада на мелководье/в болоте (не на домашних островах)
	if danger >= 1.0:
		var pool: Array = shallow.duplicate()
		for p in buckets.get(&"swamp", []):
			if ground_y_at(self, p.x, p.z) < wl + 0.3:
				pool.append(p)
		for i in count.call(0.9 * area_k * danger):
			if pool.is_empty(): break
			_try_spawn(&"croc", pool[_rng.randi() % pool.size()], 18.0)

func _room(n: int) -> bool:
	return animals.size() + n <= max_animals

func _try_spawn(sp: StringName, p: Vector3, home_r: float) -> Animal:
	if not _room(1):
		return null
	var g := ground_y_at(self, p.x, p.z)
	return spawn(sp, Vector3(p.x, g, p.z), home_r)

func _on_died(a: Animal, _killer: Node) -> void:
	# мёртвое тело остаётся (анимация/дроп), из учёта уходит при удалении
	pass

# ============================== API ==============================

func animals_near(pos: Vector3, r: float, sp: StringName = &"") -> Array[Animal]:
	var out: Array[Animal] = []
	for a in animals:
		if is_instance_valid(a) and not a.dead and (sp == &"" or a.species == sp) and a.global_position.distance_to(pos) <= r:
			out.append(a)
	return out

func tame(a: Animal, owner_: Node) -> void:
	if a and not a.dead:
		a.tame_by(owner_)

func living_count(sp: StringName = &"") -> int:
	var n := 0
	for a in animals:
		if is_instance_valid(a) and not a.dead and (sp == &"" or a.species == sp):
			n += 1
	return n

## Яд на персонажа: dps урона в секунду, sec — длительность. Хранится в ch.poison/ch.poison_time.
func apply_poison(ch: Node, dps: float, sec: float) -> void:
	if ch == null or not is_instance_valid(ch):
		return
	if not (&"poison" in ch) or not (&"poison_time" in ch):
		ch.set_meta(&"poison", maxf(float(ch.get_meta(&"poison", 0.0)), dps))
		ch.set_meta(&"poison_time", maxf(float(ch.get_meta(&"poison_time", 0.0)), sec))
		return
	ch.set(&"poison", maxf(float(ch.get(&"poison")), dps))
	ch.set(&"poison_time", maxf(float(ch.get(&"poison_time")), sec))

# ============================== тик ==============================

const _LOD_TAGS: Array[StringName] = [&"fauna_lod0", &"fauna_lod1", &"fauna_lod2", &"fauna_lod3", &"fauna_lod4"]

func _physics_process(dt: float) -> void:
	var __pt := PerfStats.begin()
	_perf_physics(dt)
	PerfStats.end(&"fauna", __pt)

func _perf_physics(dt: float) -> void:
	clock += dt
	_frame += 1
	var __p0 := PerfStats.begin()
	_tick_poison(dt)
	_tick_flocks(dt)
	PerfStats.end(&"fauna_misc", __p0)
	_breed_t += dt
	if _breed_t > 2.0:
		_tick_breeding(_breed_t)
		_breed_t = 0.0
	var cam := get_viewport().get_camera_3d()
	var cp := cam.global_position if cam else Vector3.ZERO
	var i := 0
	while i < animals.size():
		var a := animals[i]
		if not is_instance_valid(a):
			animals.remove_at(i)
			continue
		i += 1
		var d := a.global_position.distance_to(cp)
		var flyer: bool = a.cfg.get("fly", false)
		var vis_r := 260.0 if flyer else 150.0
		var vis := d < vis_r
		if a.species == &"bat":
			a.visible = a.visible and vis
		else:
			a.visible = vis
		if a.process_mode == Node.PROCESS_MODE_DISABLED and a.has_meta(&"polygon_stand"):
			continue   # стенд полигона: поза заморожена, мозг не тикает
		var step := 1
		if d < 35.0:
			a.lod = 0
		elif d < 70.0:
			a.lod = 1
			step = 2
		elif d < 130.0:
			a.lod = 2
			step = 4
		elif d < 260.0 or a.tamed:
			a.lod = 3
			step = 10
		else:
			a.lod = 4
			step = 0
		a._acc += dt
		if step == 0:
			a._acc = 0.0
			continue
		# фаза по хэшу id: id объектов идут с шагом, кратным 2/4, и без хэша
		# все звери одного уровня тикали в одном кадре (всплески по 8+ мс)
		if (_frame + (hash(a.get_instance_id()) & 1023)) % step == 0:
			var __p1 := PerfStats.begin()
			a.tick(minf(a._acc, 0.5))
			if __p1 != 0:
				PerfStats.end(_LOD_TAGS[clampi(a.lod, 0, 4)], __p1)
			a._acc = 0.0

func _tick_poison(dt: float) -> void:
	for c in get_tree().get_nodes_in_group(&"characters"):
		var has_prop := &"poison_time" in c
		var t: float = float(c.get(&"poison_time")) if has_prop else float(c.get_meta(&"poison_time", 0.0))
		if t <= 0.0:
			continue
		if c.has_method(&"tick_poison"):
			continue # персонаж сам обрабатывает яд
		if c.has_method(&"is_dead") and bool(c.call(&"is_dead")):
			t = 0.0
		var dps: float = float(c.get(&"poison")) if has_prop else float(c.get_meta(&"poison", 0.0))
		var acc: float = float(c.get_meta(&"_poison_acc", 0.0)) + dps * dt
		t -= dt
		if acc >= 1.0 or t <= 0.0:
			if c.has_method(&"apply_damage") and acc > 0.0:
				c.call(&"apply_damage", acc, null, &"poison")
			acc = 0.0
		c.set_meta(&"_poison_acc", acc)
		if t <= 0.0:
			t = 0.0
			dps = 0.0
		if has_prop:
			c.set(&"poison_time", t)
			c.set(&"poison", dps)
		else:
			c.set_meta(&"poison_time", t)
			c.set_meta(&"poison", dps)

func _tick_flocks(dt: float) -> void:
	for fl in flocks:
		var members: Array = fl["members"]
		var alive := false
		for m in members:
			if is_instance_valid(m) and not (m as Animal).dead and not (m as Animal).tamed:
				alive = true
				break
		if not alive:
			continue
		var sp: StringName = fl["species"]
		var home_p: Vector3 = fl["home"]
		var R: float = fl["r"]
		fl["t"] = float(fl["t"]) - dt
		var mode: StringName = fl["mode"]
		if sp == &"bat" and not is_night_now(self) and not force_night_birds:
			continue
		if mode == &"perch":
			if float(fl["t"]) <= 0.0 and not (sp == &"parrot" and is_night_now(self)):
				fl["mode"] = &"fly"
				fl["t"] = 0.0
			continue
		var pos: Vector3 = fl["pos"]
		var tgt: Vector3 = fl["target"]
		var spd := 6.0 if sp != &"bat" else 5.0
		pos = pos.move_toward(tgt, spd * dt)
		fl["pos"] = pos
		if pos.distance_to(tgt) < 1.5 or float(fl["t"]) < -25.0:
			fl["t"] = 0.0
			var roll := _rng.randf()
			# садятся только после хотя бы одного перелёта (не прямо на месте появления)
			var legs := int(fl.get("legs", 0)) + 1
			fl["legs"] = legs
			if sp != &"bat" and roll < 0.3 and legs > 1:
				# днём попугаи садятся только на кроны: на землю — нет
				var perch := _find_perch(sp, home_p, R, sp != &"parrot")
				if perch != Vector3.INF:
					fl["perch"] = perch
					fl["mode"] = &"perch"
					fl["target"] = perch
					fl["t"] = _rng.randf_range(15.0, 40.0)
					continue
			var a := _rng.randf() * TAU
			var r := sqrt(_rng.randf()) * R
			var x := home_p.x + cos(a) * r
			var z := home_p.z + sin(a) * r
			var g := maxf(ground_y_at(self, x, z), water_y(self))
			var h := 9.0 + _rng.randf() * 8.0
			if sp == &"bat":
				h = 3.5 + _rng.randf() * 4.0
			elif sp == &"gull":
				h = 7.0 + _rng.randf() * 12.0
			fl["target"] = Vector3(x, g + h, z)

func _find_perch(sp: StringName, home_p: Vector3, R: float, allow_ground: bool = true) -> Vector3:
	if sp == &"gull":
		for i in 10:
			var p := home_p + Vector3(_rng.randf_range(-R, R), 0, _rng.randf_range(-R, R)) * 0.6
			if biome_of(self, p.x, p.z) == &"beach":
				return Vector3(p.x, ground_y_at(self, p.x, p.z) + 0.08, p.z)
		return Vector3.INF
	var best := Vector3.INF
	# деревья архипелага живут записями Flora (MultiMesh); узлы в группе trees — только разбуженные рядом
	var fl := Flora.instance()
	if fl:
		var near := fl.nodes_near(home_p, R * 2.0, &"tree")
		if not near.is_empty():
			var e: Dictionary = near[_rng.randi_range(0, mini(near.size(), 6) - 1)]
			var rec: Dictionary = e["rec"]
			var v := FloraLib.variant(rec["kind"], int(rec["idx"]))
			var xf := Transform3D(Basis(Vector3.UP, float(rec["yaw"])), rec["pos"])
			return xf * FloraLib.trunk_point(v, float(v["H"]) * 0.97) + Vector3.UP * 0.1
	var trees := get_tree().get_nodes_in_group(&"trees")
	if trees.is_empty():
		if not allow_ground:
			return Vector3.INF
		# нет деревьев — садятся на землю
		var p := home_p + Vector3(_rng.randf_range(-8, 8), 0, _rng.randf_range(-8, 8))
		return Vector3(p.x, ground_y_at(self, p.x, p.z) + 0.08, p.z)
	# ближайшее живое дерево к центру стаи (выборка — деревьев на острове сотни)
	var bd := INF
	var tries := mini(trees.size(), 32)
	for k in tries:
		var t := trees[_rng.randi() % trees.size()] as Node3D
		if t == null or not t.is_inside_tree() or bool(t.get(&"felled")):
			continue
		var d := Vector2(t.global_position.x - home_p.x, t.global_position.z - home_p.z).length()
		if d < bd and d < R * 3.0:
			bd = d
			best = _tree_top(t)
	return best

static func _tree_top(t: Node3D) -> Vector3:
	var v: Variant = t.get(&"variant")
	if v is Dictionary and (v as Dictionary).has("H"):
		var vd: Dictionary = v
		var H: float = vd["H"]
		return t.global_transform * FloraLib.trunk_point(vd, H * 0.97) + Vector3.UP * 0.1
	return t.global_position + Vector3.UP * 7.0

func _tick_breeding(dt: float) -> void:
	for a in animals:
		if not is_instance_valid(a) or a.dead or not a.tamed:
			continue
		if a.pregnant_t >= 0.0 and clock >= a.pregnant_t:
			a.pregnant_t = -1.0
			var baby := spawn(a.species, a.global_position + Vector3(0.8, 0, 0.6), a.home_r)
			baby.set_growth(0.45)
			baby.tame_by(a.owner_node)
			baby.follow = a.follow
			Events.toast.emit("Родился детёныш: %s" % a.display_name().to_lower())
	for a in animals:
		if not is_instance_valid(a) or not _can_breed(a):
			continue
		for b in animals:
			if b == a or not is_instance_valid(b) or not _can_breed(b) or b.species != a.species or b.team != a.team:
				continue
			if a.global_position.distance_to(b.global_position) > 7.0:
				continue
			a.pregnant_t = clock + breed_seconds
			a.breed_cd = breed_cd_seconds
			b.breed_cd = breed_cd_seconds
			Events.toast.emit("%s: скоро будет потомство" % a.display_name())
			break

func _can_breed(a: Animal) -> bool:
	return is_instance_valid(a) and not a.dead and a.tamed and a.growth >= 0.99 and a.breed_cd <= 0.0 \
		and a.pregnant_t < 0.0 and clock - a.fed_t < fed_window and a.cfg.get("tame", false)
