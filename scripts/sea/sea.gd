class_name Sea
extends Node3D
## Модуль «Море»: заселяет воду акулами и стаями рыб, ищет им добычу, отвечает за
## укусы (общий лимит на цель — стая убивает пловца ~за 10 с), кровь и приманку,
## всплески. Узел в группе `sea`. Мир берётся из узла группы `world` (CONTRACT_G1),
## запасной вариант — любой узел сцены с height_at().
##
## API: sharks_near(pos, r), threat_at(pos), add_blood(pos, strength), add_bait(pos, sec),
## splash(pos, size), is_prey(node), water_y(), depth_at(x, z), floor_at(x, z).
## Сигналы: shark_bite(shark, target, damage), shark_died(shark, killer).

signal shark_bite(shark: Shark, target: Node, damage: float)
signal shark_died(shark: Shark, killer: Node)

const FRENZY_RADIUS := 110.0
const BITE_COOLDOWN := 0.55        # не чаще одного укуса по цели (вся стая)
const BLOOD_TIME := 9.0            # сколько живёт след крови
const DECK_LOW := 1.0              # настил ниже — акулы достают людей на нём
const LOD_NEAR := 140.0
const LOD_FAR := 280.0
const PACK_SKEL_DIST := 45.0        # дальше — акула из пака без скелета (VAT)
const SPLASH_SOUND := "res://assets/sounds/sfx-kit/props-splash.wav"
const SPLASH_STOP_WAIT_MS := 100

@export var density: float = 1.0
@export var auto_populate: bool = true
@export var fish_schools_per_island: int = 5
@export var underwater_fx: bool = true
@export var life_cells_enabled: bool = true
var life_cells: SeaLifeCells = null
@export var reefs_enabled: bool = true
@export var life_enabled: bool = true
@export var reef_life_enabled: bool = true   # фон: тропические рыбы, растительность, сценки охоты
var fx: SeaFX = null

var sharks: Array[Shark] = []
var schools: Array[FishSchool] = []
var world: Node = null

var _bite_next: Dictionary = {}     # instance_id → время следующего укуса
var _hurt_t: Dictionary = {}        # instance_id → время последнего ранения
var _blood: Array[Dictionary] = []  # {pos, t, s}
var _baits: Array[Dictionary] = []  # {pos, t}
var _in_water: Dictionary = {}      # instance_id → bool (для всплесков)
var _time: float = 0.0
var _far_acc: float = 0.0
var _sleep_acc: float = 0.0
var _rng := RandomNumberGenerator.new()
var _splash_players: Array[AudioStreamPlayer3D] = []
var _splash_i: int = 0
var _fallback_islands: Array[Dictionary] = []
var _straits: Array[Dictionary] = []
var _fish_stock: Dictionary = {}    # id острова (-1 — открытое море) → рыбы осталось
var _fish_stock0: Dictionary = {}
var _pickup_acc: float = 0.0
var _bump_acc: float = 0.0
var reefs: Node3D = null            # SeaReefs
var life: Node3D = null             # SeaLife
var reef_life: Node3D = null        # ReefLife (фон)
var scenes: SeaSceneDirector = null  # сцены морской жизни

func _ready() -> void:
	add_to_group(&"sea")
	_rng.seed = 7331
	SeaItems.register()
	UserSeaPack.register_items()   # пак пользователя: ракушка
	if Events.has_signal(&"character_damaged"):
		Events.character_damaged.connect(_on_character_damaged)
	for i in 4:
		var a := AudioStreamPlayer3D.new()
		if ResourceLoader.exists(SPLASH_SOUND):
			a.stream = load(SPLASH_SOUND)
		a.unit_size = 6.0
		a.max_distance = 80.0
		add_child(a)
		_splash_players.append(a)
	if underwater_fx:
		var ufx := UnderwaterFX.new()
		ufx.sea = self
		add_child(ufx)
		fx = SeaFX.new()
		fx.sea = self
		add_child(fx)
	# сцены морской жизни у игрока (scripts/sea/scenes): охота, укрытия, нерест, реакции
	scenes = SeaSceneDirector.new()
	scenes.sea = self
	add_child(scenes)
	if auto_populate:
		call_deferred(&"_auto_start")

func _auto_start() -> void:
	_find_world()
	if world and world.has_signal(&"world_ready") and world.has_method(&"islands") and (world.call(&"islands") as Array).is_empty():
		world.connect(&"world_ready", populate, CONNECT_ONE_SHOT)
	else:
		populate()

# ---------------- мир ----------------
func _find_world() -> void:
	world = get_tree().get_first_node_in_group(&"world")
	if world == null:
		world = _find_with_height(get_tree().current_scene)
	if world == null:
		world = _find_with_height(get_tree().root)

func _find_with_height(n: Node) -> Node:
	if n == null:
		return null
	if n.has_method(&"height_at") and n != self:
		return n
	for c in n.get_children():
		var r := _find_with_height(c)
		if r:
			return r
	return null

func water_y() -> float:
	if world and world.has_method(&"water_level"):
		return float(world.call(&"water_level"))
	return 0.0

func floor_at(x: float, z: float) -> float:
	if world and world.has_method(&"height_at"):
		return float(world.call(&"height_at", x, z))
	return -12.0

## Глубина моря сейчас. Мир с картой зон: вне открытого моря (суша и отрезанные от моря
## низины) — отрицательная: морская живность туда не заплывает (v5.1).
func depth_at(x: float, z: float) -> float:
	var d := water_y() - floor_at(x, z)
	if world:
		var zm: Variant = world.get(&"zones")
		if zm is ZoneMap and not (zm as ZoneMap).is_sea(x, z):
			return minf(d, -0.05)
	return d

func islands() -> Array[Dictionary]:
	if world and world.has_method(&"islands"):
		var arr: Array = world.call(&"islands")
		if not arr.is_empty():
			var out: Array[Dictionary] = []
			for d in arr:
				out.append(d)
			return out
	if _fallback_islands.is_empty():
		_fallback_islands = _detect_islands()
	return _fallback_islands

## Запасной вариант: один остров в начале координат, радиус — где дно уходит ниже -1 м.
func _detect_islands() -> Array[Dictionary]:
	var r := 0.0
	for k in 8:
		var a := TAU * k / 8.0
		var d := 5.0
		while d < 400.0 and depth_at(cos(a) * d, sin(a) * d) < 1.0:
			d += 2.0
		r += d
	r /= 8.0
	return [{"id": 0, "kind": "home", "team": 0, "center": Vector2.ZERO, "radius": r}]

# ---------------- заселение ----------------
const MAX_SHARKS := 160
const REEF_KINDS := [&"atoll", &"shared", &"spring", &"wreck"]

func populate() -> void:
	for s in sharks:
		if is_instance_valid(s):
			s.queue_free()
	sharks.clear()
	for f in schools:
		if is_instance_valid(f):
			f.queue_free()
	schools.clear()
	var isl := islands()
	var seed_i := 100
	_init_fish_stock(isl)
	# проливы: глубокая вода между островами — больше и крупнее акулы
	for st in straits():
		var mid: Vector2 = st["mid"]
		var gap: float = st["gap"]
		var cnt := maxi(1, int(round((0.9 + gap / 90.0) * density)))
		for k in cnt:
			if sharks.size() >= MAX_SHARKS:
				break
			seed_i += 1
			spawn_shark(&"tiger" if _rng.randf() < 0.62 else &"white", mid, maxf(gap * 0.3, 14.0), seed_i)
	for d in isl:
		var c: Vector2 = d["center"]
		var r: float = d["radius"]
		var kind: StringName = StringName(d.get("kind", &"home"))
		var reefy := REEF_KINDS.has(kind)
		var circ := TAU * (r + 30.0)
		# над рифами и отмелями акул меньше и они мелкие; у больших островов — крупнее
		var per := 150.0 if reefy else 105.0
		var n := maxi(1 if reefy else 2, int(round(circ / per * density)))
		for i in n:
			if sharks.size() >= MAX_SHARKS:
				break
			var roll := _rng.randf()
			var sp: StringName = &"reef"
			if not reefy:
				sp = &"reef" if roll < 0.6 else (&"tiger" if roll < 0.92 else &"white")
			var ring := r + (_rng.randf_range(10.0, 30.0) if sp == &"reef" else _rng.randf_range(28.0, 60.0))
			seed_i += 1
			spawn_shark(sp, c, ring, seed_i)
		var ns := fish_schools_per_island + (3 if reefy else 0)
		for k in ns:
			var a := _rng.randf() * TAU
			var rr := r + _rng.randf_range(4.0, 26.0)
			var pos := Vector3(c.x + cos(a) * rr, 0.0, c.y + sin(a) * rr)
			if depth_at(pos.x, pos.z) < 1.2:
				continue
			_spawn_school(pos, k + (int(d.get("id", 0)) * 3))
	_build_reefs_and_life()
	UserSeaPack.scatter_shells(self)   # ракушки из пака на пляжах

func _build_reefs_and_life() -> void:
	if reefs_enabled:
		if reefs == null:
			reefs = SeaReefs.new()
			reefs.name = "Reefs"
			reefs.sea = self
			add_child(reefs)
		reefs.density = density
		reefs.build()
	if life_enabled:
		if life == null:
			life = SeaLife.new()
			life.name = "Life"
			life.sea = self
			add_child(life)
		life.density = density
		life.populate()
	if reef_life_enabled:
		if reef_life == null:
			reef_life = ReefLife.new()
			reef_life.name = "ReefLife"
			reef_life.set(&"sea", self)
			add_child(reef_life)
		reef_life.set(&"density", density)
		reef_life.call(&"build")
	if life_cells_enabled and life_cells == null:
		# живность по реестру SeaSpecies — только в ячейках вокруг игрока, всё в шейдере
		life_cells = SeaLifeCells.new()
		life_cells.sea = self
		add_child(life_cells)
	if life_cells_enabled and get_node_or_null(^"UserSeaActors") == null:
		# особи из пака пользователя вблизи камеры: поведение и анимация (UserSeaActor)
		var ua := UserSeaActors.new()
		ua.sea = self
		add_child(ua)

## Пятна кораллового рифа: [{center: Vector2, island, kind, radius, corals}].
func reef_zones() -> Array[Dictionary]:
	if reefs:
		return (reefs as SeaReefs).zones()
	return []

## Строка для оверлея F3: океан и живность (счётчики; время — в PerfStats:
## ocean, ocean_wave_h, sea, sea_fx, sea_cells).
static func perf_line() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return ""
	var parts: PackedStringArray = []
	var w := tree.get_first_node_in_group(&"world")
	var oc: Ocean = w.get(&"ocean") if w else null
	if oc:
		parts.append("океан %d² %s, wave_h %d/кадр" % [oc.GRID, "FFT" if oc.use_fft else "Герстнер", oc.wave_calls_last])
	var cells := tree.get_first_node_in_group(&"sea_life_cells") as SeaLifeCells
	if cells:
		parts.append("живность %d гр./%d особ." % [cells.groups_active, cells.instances_active])
	var ua := tree.get_first_node_in_group(&"user_sea_actors") as UserSeaActors
	if ua:
		parts.append(ua.perf_text())
	var sd := SeaSceneDirector.instance()
	if sd:
		parts.append(sd.perf_text())
	var near := 0
	var far := 0
	for n in tree.get_nodes_in_group(&"sharks"):
		var sh := n as Shark
		if sh and sh.visible and sh.uses_pack_model():
			if sh._far:
				far += 1
			else:
				near += 1
	if near + far > 0:
		parts.append("акулы скелет %d / VAT %d" % [near, far])
	return "море: " + "  ".join(parts) if not parts.is_empty() else ""

func _exit_tree() -> void:
	# Всплеск, ещё звучащий при выходе, оставался в аудиосервере («1 resources still in
	# use at exit»: props-splash.wav). Останавливаем и даём аудиопотоку отпустить его.
	var playing := 0
	for a in _splash_players:
		if is_instance_valid(a) and a.playing:
			a.stop()
			playing += 1
	if playing > 0:
		OS.delay_msec(SPLASH_STOP_WAIT_MS)
	SeaMeshes.clear_cache()
	SharkModel.clear_cache()
	SeaPush.clear()
	SeaCreature.clear_cache()

## Проливы между соседними островами: [{a, b, mid: Vector2, gap: float}].
func straits() -> Array[Dictionary]:
	if not _straits.is_empty():
		return _straits
	var isl := islands()
	var by_id := {}
	for d in isl:
		by_id[int(d.get("id", 0))] = d
	var routes: Variant = null
	if world:
		var arch: Variant = world.get(&"arch")
		if arch is Object and "routes" in (arch as Object):
			routes = (arch as Object).get(&"routes")
	if routes is Array and not (routes as Array).is_empty():
		for rt in routes:
			var a: Dictionary = by_id.get(int(rt["a"]), {})
			var b: Dictionary = by_id.get(int(rt["b"]), {})
			if a.is_empty() or b.is_empty():
				continue
			_straits.append(_strait(a, b, float(rt.get("gap", 80.0))))
	else:
		for i in isl.size():
			for j in range(i + 1, isl.size()):
				var a: Vector2 = isl[i]["center"]
				var b: Vector2 = isl[j]["center"]
				var gap := a.distance_to(b) - float(isl[i]["radius"]) - float(isl[j]["radius"])
				if gap < 140.0:
					_straits.append(_strait(isl[i], isl[j], gap))
	return _straits

func _strait(a: Dictionary, b: Dictionary, gap: float) -> Dictionary:
	var ca: Vector2 = a["center"]
	var cb: Vector2 = b["center"]
	var dir := (cb - ca).normalized()
	var p0 := ca + dir * float(a["radius"])
	var p1 := cb - dir * float(b["radius"])
	return {"a": int(a.get("id", 0)), "b": int(b.get("id", 0)), "mid": (p0 + p1) * 0.5, "gap": maxf(gap, 10.0),
		"p0": p0, "p1": p1}

## Ближайшая точка моря глубже need (по спирали до max_r м); null — нет.
func nearest_deep(from: Vector2, need: float, max_r: float) -> Variant:
	if depth_at(from.x, from.y) >= need:
		return from
	var r := 4.0
	while r <= max_r:
		var n := maxi(8, int(TAU * r / 6.0))
		for i in n:
			var a := TAU * i / n
			var q := from + Vector2(cos(a), sin(a)) * r
			if depth_at(q.x, q.y) >= need:
				return q
		r += 6.0
	return null

func spawn_shark(sp: StringName, center: Vector2, ring: float, seed_i: int) -> Shark:
	var s := Shark.new()
	s.setup(sp, self, center, ring, seed_i)
	add_child(s)
	var a := _rng.randf() * TAU
	var p := Vector3(center.x + cos(a) * ring, 0.0, center.y + sin(a) * ring)
	var tries := 0
	while depth_at(p.x, p.z) < 3.0 and tries < 12:
		ring += 6.0
		p = Vector3(center.x + cos(a) * ring, 0.0, center.y + sin(a) * ring)
		tries += 1
	if depth_at(p.x, p.z) < 3.0:
		# v5.1: кольцо целиком над сушей — ближайшая глубокая вода по спирали (иначе акула застревала на берегу)
		var q: Variant = nearest_deep(Vector2(p.x, p.z), 3.0, 260.0)
		if q != null:
			p = Vector3((q as Vector2).x, 0.0, (q as Vector2).y)
			ring = Vector2(p.x - center.x, p.z - center.y).length()
	s.home_r = ring
	p.y = water_y() - clampf(depth_at(p.x, p.z) * 0.45, 1.3, 4.5)
	s.global_position = p
	s.yaw = a + PI * 0.5 * s.orbit_dir
	sharks.append(s)
	return s

func _spawn_school(pos: Vector3, k: int) -> void:
	var f := FishSchool.new()
	f.count = 28 + (k * 7) % 24
	f.palette = k % FishSchool.PALETTES.size()
	f.radius = 1.6 + (k % 3) * 0.6
	f.fish_length = 0.22 + (k % 3) * 0.06
	f.water_level = water_y()
	var d := depth_at(pos.x, pos.z)
	pos.y = water_y() - clampf(d * 0.5, 1.0, 4.0)
	f.center = pos
	f.roam = 9.0
	f.floor_func = floor_at
	add_child(f)
	schools.append(f)

# ---------------- добыча ----------------
func is_prey(n: Node3D) -> bool:
	if not is_instance_valid(n) or not n.is_inside_tree():
		return false
	if n.has_method(&"is_dead") and n.call(&"is_dead"):
		return false
	if n is Shark:
		return false
	if n.has_method(&"is_in_water") and n.call(&"is_in_water"):
		return true
	return _on_low_deck(n)

func _on_low_deck(n: Node3D) -> bool:
	var p := n.global_position
	if p.y - water_y() > DECK_LOW + 1.0:
		return false
	for deck in get_tree().get_nodes_in_group(&"raft_deck"):
		var d3 := deck as Node3D
		if d3 == null or not deck.has_method(&"deck_height"):
			continue
		if float(deck.call(&"deck_height")) >= DECK_LOW:
			continue
		var q := d3.global_position
		if Vector2(p.x - q.x, p.z - q.z).length() < 2.6 and p.y - q.y < 2.2 and p.y - q.y > -0.6:
			return true
	return false

func is_bleeding(n: Node) -> bool:
	return _bleeding(n)

func _bleeding(n: Node) -> bool:
	var id := n.get_instance_id()
	if _hurt_t.has(id) and _time - float(_hurt_t[id]) < BLOOD_TIME:
		return true
	if "health" in n and "max_health" in n:
		return float(n.get("health")) < float(n.get("max_health")) * 0.6
	return false

## Лучшая цель для акулы: {node, kind, blood} или {}.
func find_prey(s: Shark) -> Dictionary:
	var best: Node3D = null
	var best_score := 0.0
	var kind := &"swim"
	var blood := false
	var sense: float = s.cfg["sense"]
	if s.bait_t > 0.0:
		sense *= 0.3   # кормится у приманки — люди интересны, только если совсем рядом
	for n in get_tree().get_nodes_in_group(&"characters"):
		var c := n as Node3D
		if c == null or not is_prey(c):
			continue
		var bl := _bleeding(c)
		var r := sense * (2.3 if bl else 1.0)
		var d := c.global_position.distance_to(s.global_position)
		if d > r:
			continue
		var score := (r - d) / r + (0.5 if bl else 0.0)
		var on_deck: bool = not (c.has_method(&"is_in_water") and bool(c.call(&"is_in_water")))
		if on_deck:
			score *= 0.7
		if score > best_score:
			best_score = score
			best = c
			kind = &"deck" if on_deck else &"swim"
			blood = bl
	if best == null:
		return {}
	return {"node": best, "kind": kind, "blood": blood}

## Укус с общим ограничением частоты на цель. true — укус состоялся.
func try_bite(s: Shark, target: Node3D) -> bool:
	if not is_prey(target):
		return false
	var id := target.get_instance_id()
	if _bite_next.has(id) and _time < float(_bite_next[id]):
		return false
	_bite_next[id] = _time + BITE_COOLDOWN
	var dmg: float = s.cfg["bite"]
	var on_deck: bool = not (target.has_method(&"is_in_water") and bool(target.call(&"is_in_water")))
	if on_deck:
		if _rng.randf() < 0.35:
			return false   # промахнулась, прыгая на настил
		dmg = maxf(dmg * 0.8, 12.0)
	elif s.frenzy > 0.0:
		dmg *= 1.25   # стая в бешенстве рвёт сильнее
	if target.has_method(&"apply_damage"):
		target.call(&"apply_damage", dmg, s, &"bite")
	add_blood(target.global_position, dmg, true)
	splash(Vector3(target.global_position.x, water_y(), target.global_position.z), 1.2 if on_deck else 0.9)
	# стащить с настила в воду (если персонаж умеет)
	if on_deck and _rng.randf() < 0.25 and target.has_method(&"knock_into_water"):
		target.call(&"knock_into_water", s.global_position)
	# бешенство стаи: соседи бросаются на ту же жертву
	for o in sharks:
		if o != s and is_instance_valid(o) and o.global_position.distance_to(target.global_position) < FRENZY_RADIUS:
			o.alert(target, &"deck" if on_deck else &"swim")
	s.frenzy = 12.0
	shark_bite.emit(s, target, dmg)
	return true

func on_shark_died(s: Shark, killer: Node) -> void:
	sharks.erase(s)
	shark_died.emit(s, killer)

# ---------------- кровь, приманка, всплески ----------------
func _on_character_damaged(ch: Node, amount: float, _source: Node) -> void:
	if ch is Node3D and ch.has_method(&"is_in_water") and ch.call(&"is_in_water"):
		_hurt_t[ch.get_instance_id()] = _time
		add_blood((ch as Node3D).global_position, amount, true)

func add_blood(pos: Vector3, strength: float, visible_cloud: bool = true) -> void:
	_blood.append({"pos": pos, "t": _time, "s": strength})
	if _blood.size() > 40:
		_blood.pop_front()
	if visible_cloud and pos.y < water_y() + 0.5:
		_blood_cloud(pos, strength)

## Приманка в воде: акулы в радиусе бросают жертву (если та не в крови) и плывут
## кормиться на `seconds` секунд. Возвращает, сколько акул отвлеклось.
func add_bait(pos: Vector3, seconds: float = 40.0) -> int:
	seconds = clampf(seconds, 5.0, 120.0)
	_baits.append({"pos": pos, "t": _time + seconds})
	add_blood(pos, 6.0, true)
	var n := 0
	var r := 75.0
	for s in sharks:
		if not is_instance_valid(s) or s.is_dead():
			continue
		var d := s.global_position.distance_to(pos)
		if d > r:
			continue
		# ближние — почти всегда, дальние — с шансом
		if _rng.randf() < 1.0 - d / r * 0.6 and s.lure(pos, seconds * _rng.randf_range(0.7, 1.0)):
			n += 1
	return n

## Ближайшая точка интереса (кровь/приманка) в радиусе r или null.
func nearest_attractor(from: Vector3, r: float) -> Variant:
	var best: Variant = null
	var bd := r
	for b in _blood:
		if _time - float(b["t"]) > BLOOD_TIME:
			continue
		var d := from.distance_to(b["pos"])
		if d < bd:
			bd = d
			best = b["pos"]
	for b in _baits:
		var d := from.distance_to(b["pos"])
		if d < bd * 1.3:
			bd = d
			best = b["pos"]
	return best

func sharks_near(pos: Vector3, r: float) -> Array[Shark]:
	var out: Array[Shark] = []
	for s in sharks:
		if is_instance_valid(s) and not s.is_dead() and s.global_position.distance_to(pos) <= r:
			out.append(s)
	return out

## Опасность воды в точке 0..1 (для ботов и подсказок).
func threat_at(pos: Vector3) -> float:
	var t := 0.0
	for s in sharks:
		if not is_instance_valid(s) or s.is_dead():
			continue
		var d := Vector2(s.global_position.x - pos.x, s.global_position.z - pos.z).length()
		var r: float = s.cfg["sense"]
		if d < r * 1.5:
			t += (1.0 - d / (r * 1.5)) * (0.5 + float(s.cfg["bite"]) / 30.0)
	return clampf(t, 0.0, 1.0)


## Плотность акул по месту обитания (не текущие позиции) 0..1 — для планирования.
func shark_density_at(pos: Vector3) -> float:
	var t := 0.0
	var p2 := Vector2(pos.x, pos.z)
	for s in sharks:
		if not is_instance_valid(s) or s.is_dead():
			continue
		var dr := absf(p2.distance_to(s.home) - s.home_r)
		if dr < 40.0:
			t += (1.0 - dr / 40.0) * (0.25 + float(s.cfg["bite"]) / 60.0)
	return clampf(t, 0.0, 1.0)

## Насколько безопасно переплыть/пройти по воде из a в b: 1 — безопасно, 0 — верная смерть.
## Учитывает текущих акул у линии, их места обитания и долю пути по глубокой воде.
func safe_crossing_score(a: Vector3, b: Vector3) -> float:
	var ln := Vector2(a.x - b.x, a.z - b.z).length()
	var steps := maxi(2, int(ln / 8.0))
	var worst := 0.0
	var dens := 0.0
	var wet := 0
	for i in steps + 1:
		var p := a.lerp(b, float(i) / steps)
		if depth_at(p.x, p.z) < 0.8:
			continue
		wet += 1
		worst = maxf(worst, threat_at(p))
		dens += shark_density_at(p)
	if wet == 0:
		return 1.0
	var wet_len := ln * float(wet) / float(steps + 1)
	var exposure := clampf(wet_len / 120.0, 0.0, 1.0)
	var danger := 0.55 * worst + 0.45 * clampf(dens / float(wet) * 1.5, 0.0, 1.0)
	return clampf(1.0 - danger * (0.5 + 0.5 * exposure), 0.0, 1.0)

# ---------------- рыба (конечный запас: мир не восстанавливается) ----------------
func _init_fish_stock(isl: Array[Dictionary]) -> void:
	_fish_stock.clear()
	for d in isl:
		var k: StringName = StringName(d.get("kind", &""))
		var n := 24
		match k:
			&"atoll": n = 70
			&"shared": n = 45
			&"spring", &"wreck": n = 40
			&"home": n = 30
			&"center": n = 50
		_fish_stock[int(d.get("id", 0))] = n
	_fish_stock[-1] = 60
	_fish_stock0 = _fish_stock.duplicate()

func _stock_key(pos: Vector3) -> int:
	var best := -1
	var bd := 1.45
	for d in islands():
		var c: Vector2 = d["center"]
		var k := Vector2(pos.x, pos.z).distance_to(c) / maxf(float(d["radius"]), 1.0)
		if k < bd:
			bd = k
			best = int(d.get("id", 0))
	return best

## Сколько рыбы осталось в этих водах (у ближайшего острова) и доля от начального.
func fish_stock_at(pos: Vector3) -> int:
	return int(_fish_stock.get(_stock_key(pos), 0))

func fish_stock_ratio(pos: Vector3) -> float:
	var k := _stock_key(pos)
	return float(_fish_stock.get(k, 0)) / maxf(float(_fish_stock0.get(k, 1)), 1.0)

## Забрать до n рыб из запаса у pos. Возвращает, сколько удалось.
func take_fish(pos: Vector3, n: int = 1) -> int:
	var k := _stock_key(pos)
	var have := int(_fish_stock.get(k, 0))
	var got := mini(have, n)
	_fish_stock[k] = have - got
	if got > 0:
		_update_school_density(k)
	return got

func _update_school_density(k: int) -> void:
	var ratio := float(_fish_stock.get(k, 0)) / maxf(float(_fish_stock0.get(k, 1)), 1.0)
	for f in schools:
		if is_instance_valid(f) and _stock_key(f.center) == k:
			f.set_density(ratio)

## Поставить вершу в воде (для ботов/UI; игрок — бросает предмет в воду).
func deploy_trap(pos: Vector3, owner: Node = null) -> Node3D:
	var tr := SeaTrap.new()
	tr.sea = self
	tr.owner_node = owner
	add_child(tr)
	var fy := floor_at(pos.x, pos.z)
	tr.global_position = Vector3(pos.x, fy, pos.z)
	tr.rotation.y = _rng.randf() * TAU
	traps.append(tr)
	return tr

var traps: Array[Node3D] = []

## Предметы, брошенные в воду (один стек, не добыча моря): еда → приманка, верша → на дно.
func _scan_pickups() -> void:
	var wy := water_y()
	for n in get_tree().get_nodes_in_group(&"pickups"):
		var p := n as Node3D
		if p == null or not ("stacks" in p) or p.is_queued_for_deletion() or p.has_meta(&"sea_loot"):
			continue
		var pos := p.global_position
		if pos.y > wy - 0.15 or depth_at(pos.x, pos.z) < 0.5:
			continue
		var stacks: Array = p.get(&"stacks")
		if stacks.size() != 1:
			continue   # мешок с вещами погибшего — не трогаем, только выброшенный стек
		var rest: Array[Dictionary] = []
		var bait_sec := 0.0
		var traps_n := 0
		for st in stacks:
			var id := StringName(st["id"])
			var cnt := int(st["n"])
			if SeaItems.BAIT.has(id):
				bait_sec += float(SeaItems.BAIT[id]) * cnt
			elif id == &"fish_trap":
				traps_n += cnt
			else:
				rest.append(st)
		if bait_sec <= 0.0 and traps_n == 0:
			continue
		if bait_sec > 0.0:
			add_bait(Vector3(pos.x, minf(pos.y, wy - 0.4), pos.z), bait_sec)
		var d := depth_at(pos.x, pos.z)
		for i in traps_n:
			if d >= 0.6 and d <= 5.0:
				deploy_trap(pos + Vector3(i * 1.2, 0.0, 0.0), null)
			else:
				rest.append({"id": &"fish_trap", "n": 1})
				Events.toast.emit("Верше нужна вода глубиной 0.6–5 м")
		if rest.is_empty():
			p.queue_free()
		else:
			p.set(&"stacks", rest)

## Акулы толкают низкие плоты-мосты: брызги, качка. Мосты не ломают.
signal raft_bumped(deck: Node, shark: Shark)

func _bump_rafts() -> void:
	var wy := water_y()
	for deck in get_tree().get_nodes_in_group(&"raft_deck"):
		var d3 := deck as Node3D
		if d3 == null or not d3.is_inside_tree():
			continue
		var q := d3.global_position
		if q.y - wy > DECK_LOW + 1.5:
			continue
		for s in sharks:
			if not is_instance_valid(s) or not s.can_bump():
				continue
			if absf(s.global_position.x - q.x) > 4.0 or absf(s.global_position.z - q.z) > 4.0:
				continue
			if _rng.randf() > 0.35:
				continue
			s.did_bump()
			splash(Vector3(s.global_position.x, wy, s.global_position.z), 0.8)
			if deck.has_method(&"bump"):
				deck.call(&"bump", (q - s.global_position).normalized(), 0.6)
			raft_bumped.emit(deck, s)
			break

static var _soft_tex: GradientTexture2D = null

## Мягкий круглый «клуб» для частиц (billboard).
static func soft_material(col: Color, unshaded: bool = true) -> StandardMaterial3D:
	if _soft_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.55))
		_soft_tex = GradientTexture2D.new()
		_soft_tex.gradient = g
		_soft_tex.fill = GradientTexture2D.FILL_RADIAL
		_soft_tex.fill_from = Vector2(0.5, 0.5)
		_soft_tex.fill_to = Vector2(1.0, 0.5)
		_soft_tex.width = 64
		_soft_tex.height = 64
	var m := StandardMaterial3D.new()
	m.albedo_texture = _soft_tex
	m.albedo_color = col
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_fog = true
	return m

func splash(pos: Vector3, size: float = 1.0) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = int(24 * size) + 8
	p.lifetime = 0.9
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 35.0
	p.initial_velocity_min = 2.5 * size
	p.initial_velocity_max = 5.0 * size
	p.gravity = Vector3(0, -12.0, 0)
	p.scale_amount_min = 0.06 * size
	p.scale_amount_max = 0.16 * size
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1, 1)
	mesh.material = soft_material(Color(0.95, 0.98, 1.0, 0.9))
	p.mesh = mesh
	p.scale_amount_min = 0.12 * size
	p.scale_amount_max = 0.35 * size
	add_child(p)
	p.global_position = pos
	p.emitting = true
	_foam_ring(pos, size)
	var a := _splash_players[_splash_i % _splash_players.size()]
	_splash_i += 1
	if a.stream:
		a.global_position = pos
		a.pitch_scale = _rng.randf_range(0.85, 1.15) / maxf(size, 0.5)
		a.play()
	for f in schools:
		if is_instance_valid(f) and f.center.distance_to(pos) < 18.0:
			f.scare(pos, 1.0)
	if reef_life:
		reef_life.call(&"scare_at", pos, 14.0 * size)
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)

func _foam_ring(pos: Vector3, size: float) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.35 * size
	tm.outer_radius = 0.6 * size
	tm.rings = 16
	tm.ring_segments = 6
	mi.mesh = tm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.95, 0.97, 1.0, 0.75)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = Vector3(pos.x, water_y() + 0.03, pos.z)
	mi.scale = Vector3(1.0, 0.08, 1.0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(3.2, 0.05, 3.2), 1.6)
	tw.tween_property(m, "albedo_color:a", 0.0, 1.6)
	tw.chain().tween_callback(mi.queue_free)

func _blood_cloud(pos: Vector3, strength: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 14 + int(strength * 0.6)
	p.lifetime = 3.0   # > 3 с — чёрные клубы в Compatibility
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.9
	p.gravity = Vector3(0, 0.05, 0)
	p.damping_min = 0.5
	p.damping_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = curve
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1, 1)
	mesh.material = soft_material(Color(0.45, 0.02, 0.03, 0.42))
	p.mesh = mesh
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.0))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	grad.add_point(0.15, Color(1, 1, 1, 1.0))
	grad.add_point(0.6, Color(1, 1, 1, 0.6))
	p.color_ramp = grad
	add_child(p)
	p.global_position = Vector3(pos.x, minf(pos.y, water_y() - 0.15), pos.z)
	p.emitting = true
	get_tree().create_timer(4.5).timeout.connect(p.queue_free)

# ---------------- цикл ----------------
## Камера над водой: подводная живность (стаи, рифовая жизнь, ячейки, особи пака)
## видна сквозь прозрачную воду только вблизи — дальность урезается до ABOVE_END,
## под водой восстанавливается. Было со спавна к центру ≈200 вызовов отрисовки
## на рыб, которых сверху не видно.
const ABOVE_END := 38.0
var _above_cull_acc := 1.0
var _above_cull_state := false

func _above_water_cull(above: bool) -> void:
	_above_cull_state = above
	var roots: Array[Node] = []
	for n in [life, reef_life, life_cells, get_node_or_null(^"UserSeaActors")]:
		if n != null and is_instance_valid(n):
			roots.append(n)
	for ch in get_children():
		if ch is FishSchool:
			roots.append(ch)
	var stack: Array[Node] = roots
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var gi := n as GeometryInstance3D
		if gi == null:
			continue
		if above:
			if not gi.has_meta(&"vr_water"):
				gi.set_meta(&"vr_water", gi.visibility_range_end)
			var full: float = gi.get_meta(&"vr_water")
			gi.visibility_range_end = ABOVE_END if full <= 0.0 else minf(full, ABOVE_END)
		elif gi.has_meta(&"vr_water"):
			gi.visibility_range_end = float(gi.get_meta(&"vr_water"))
			gi.remove_meta(&"vr_water")

func _physics_process(delta: float) -> void:
	var __pt := PerfStats.begin()
	_perf_physics(delta)
	PerfStats.end(&"sea", __pt)

var _wet: Array[Vector3] = []
var _lod_acc: Dictionary = {}

func _perf_physics(delta: float) -> void:
	_time += delta
	var cam := get_viewport().get_camera_3d()
	var cam_p := cam.global_position if cam else Vector3.ZERO
	_far_acc += delta
	_sleep_acc += delta
	var far_tick := _far_acc >= 0.25
	# персонажи в воде/у воды (боты далеко от камеры тоже должны встречать акул)
	if far_tick:
		_far_acc = 0.0
		_wet.clear()
		for n in get_tree().get_nodes_in_group(&"characters"):
			if n is Node3D and (n as Node3D).global_position.y < water_y() + 3.0:
				_wet.append((n as Node3D).global_position)
	var wy_now := water_y()
	var cam_above := cam_p.y > wy_now + 0.3
	_above_cull_acc += delta
	if _above_cull_acc >= 1.0 or cam_above != _above_cull_state:
		_above_cull_acc = 0.0
		_above_water_cull(cam_above)
	# Дальние акулы тикают реже, у каждой свой накопитель со случайной фазой —
	# иначе все 100+ дальних акул считались в одном кадре (всплеск).
	for s in sharks:
		if not is_instance_valid(s):
			continue
		var d := s.global_position.distance_to(cam_p)
		var near := d < LOD_NEAR or s.state == Shark.State.ATTACK or s.state == Shark.State.STALK
		# над водой глубокая акула не видна сквозь толщу — не рисуем (плавник у поверхности виден)
		s.visible = d < LOD_FAR and not (cam_above and d > 22.0 and s.global_position.y < wy_now - 1.6)
		# модель пака: скелет вблизи, VAT-меш дальше PACK_SKEL_DIST
		s.set_far(d > PACK_SKEL_DIST and s.state != Shark.State.ATTACK)
		var id := s.get_instance_id()
		if near:
			_lod_acc[id] = 0.0
			s.tick(delta, true)
			continue
		var acc: float = float(_lod_acc.get(id, randf() * 0.25)) + delta
		var period := 1.0
		if d < LOD_FAR * 1.4 or s.state != Shark.State.PATROL:
			period = 0.25
		else:
			for w in _wet:
				if w.distance_to(s.global_position) < 120.0:
					period = 0.25 # рядом кто-то у воды — просыпается
					break
		if acc >= period:
			s.tick(acc, period < 1.0 and d < LOD_FAR)
			acc = 0.0
		_lod_acc[id] = acc
	_pickup_acc += delta
	if _pickup_acc >= 0.5:
		_pickup_acc = 0.0
		_scan_pickups()
	_bump_acc += delta
	if _bump_acc >= 1.0:
		_bump_acc = 0.0
		_bump_rafts()
	# всплески при входе персонажей в воду; пловцы расталкивают водоросли
	var swimmers: Array[Vector3] = []
	for n in get_tree().get_nodes_in_group(&"characters"):
		if not (n is Node3D) or not n.has_method(&"is_in_water"):
			continue
		var id := n.get_instance_id()
		var w: bool = n.call(&"is_in_water")
		if w:
			swimmers.append((n as Node3D).global_position + Vector3(0, 0.5, 0))
		if w and not _in_water.get(id, false):
			var p := (n as Node3D).global_position
			splash(Vector3(p.x, water_y(), p.z), 1.0)
		_in_water[id] = w
	SeaPush.update(swimmers, cam_p)
	# протухание приманок
	for i in range(_baits.size() - 1, -1, -1):
		if _time > float(_baits[i]["t"]):
			_baits.remove_at(i)
