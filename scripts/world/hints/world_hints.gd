class_name WorldHints
extends Node3D
## Подсказки через мир (v5.2, агент L): то, по чему внимательный игрок читает остров.
##   27 — гуано на птичьих карнизах: залежи GuanoDeposit (E — соскрести), гуано → селитра у костра;
##   28 — падальщики кружат высоко над тушей (видно издалека), мухи над тушей и над
##        испорченной едой — на земле и в сундуках (выдают тайник);
##   29 — комары в манграх ночью: рой вокруг игрока и укусы; дым костра (в 7 м) их отгоняет;
##   33 — фаза луны → сила прилива (сизигийный/квадратурный); полоса выброса водорослей
##        после шторма; перья после гибели птицы; муравьиная дорожка к брошенной еде;
##        следы черепахи от воды к гнезду; «зелёная полоса» и лягушки у родников и ручьёв.
## Остальные подсказки из списка: звериная тропа к воде — TrailNet (агент C); цвет воды по
## глубине — шейдер океана; чайки над косяком и крабы на отливе — сценки LandDirector.

const SCAN_EVERY := 1.5
const CARRION_DELAY := 12.0      # через сколько после смерти слетаются падальщики
const CARRION_MIN_LEN := 0.5     # м — тушки меньше не интересны
const FLY_FOOD_AGE := 35.0       # с — еда на земле, над которой появляются мухи
const ANT_FOOD_AGE := 25.0
const MOSQUITO_DPS_EVERY := 7.0
const SMOKE_R := 7.0
const MAX_FLIES := 14
const MAX_ANTS := 6
const WRACK_LIFE := 900.0        # с — полоса выброса держится ~15 мин
const FEATHER_LIFE := 400.0
const SPOILING := [&"meat_raw", &"fish_raw", &"meat_cooked", &"fish_cooked", &"crab_meat"]

var world: Node = null
## false — ничего не делает сам (тесты); функции add_*/spawn_*/seep/feathers работают всегда.
var active := true
var tide_factor := 1.0
var base_tide := -1.0
var stats := {"guano": 0, "carrion": 0, "flies": 0, "ants": 0, "turtle_tracks": 0, "wrack": 0, "feathers": 0, "seeps": 0, "bites": 0}
var carrion := {}        # instance_id тушки → {corpse, flock, birds:[], flies}
var flies := {}          # instance_id источника → FlySwarm
var ants := {}           # instance_id еды → AntTrail(Node3D)
var pickup_seen := {}    # instance_id → время появления
var mosquitoes: FlySwarm = null
var _bite_t := 0.0
var _mosq_warned := false
var _acc := 0.0
var _moon_acc := 0.0
var _rng := RandomNumberGenerator.new()
var _last_weather := &""
var _storm_peak := 0.0
var _guano_done := false
var _seeps_done := {}
var _feathered := {}
var _clock := 0.0
var _wrack_nodes: Array[Node3D] = []

static func instance() -> WorldHints:
	var ml := Engine.get_main_loop() as SceneTree
	return ml.get_first_node_in_group(&"world_hints") as WorldHints if ml else null

## Предметы/рецепты подсказок (гуано → селитра). Можно звать много раз.
static func ensure_items() -> void:
	var ml := Engine.get_main_loop() as SceneTree
	var items: Node = ml.root.get_node_or_null(^"/root/Items") if ml else null
	if items == null:
		return
	if items.call(&"get_item", &"guano") == null:
		items.call(&"register_item", &"guano", "Гуано (птичий помёт)", &"resource", 30, 0.3, {"color": Color(0.92, 0.91, 0.84)})
	if not (items.get(&"recipes") as Dictionary).has(&"r_saltpeter_guano"):
		items.call(&"register_recipe", &"r_saltpeter_guano", &"saltpeter", {&"guano": 3}, 2, &"campfire")

func _ready() -> void:
	name = "WorldHints"
	add_to_group(&"world_hints")
	_rng.randomize()
	ensure_items()
	if world == null:
		world = get_tree().get_first_node_in_group(&"world")

func _process(dt: float) -> void:
	_clock += dt
	if not active:
		return
	_tick_mosquitoes(dt)
	_moon_acc -= dt
	if _moon_acc <= 0.0:
		_moon_acc = 5.0
		_update_moon_tide()
		_watch_storm()
	_acc -= dt
	if _acc > 0.0:
		return
	_acc = SCAN_EVERY
	var pp := _player_pos()
	if not _guano_done:
		_spawn_guano()
	_scan_corpses(pp)
	_scan_food(pp)
	_scan_nests(pp)
	_scan_seeps(pp)
	_expire()

# ------------------------------------------------------------------ среда

func _player_pos() -> Vector3:
	var pl := get_tree().get_first_node_in_group(&"player") as Node3D
	if pl:
		return pl.global_position
	var c := get_viewport().get_camera_3d()
	return c.global_position if c else Vector3.ZERO

func _ground(x: float, z: float) -> float:
	if world and is_instance_valid(world) and world.has_method(&"height_at"):
		return float(world.call(&"height_at", x, z))
	return 0.0

func _water() -> float:
	if world and is_instance_valid(world) and world.has_method(&"water_level"):
		return float(world.call(&"water_level"))
	return 0.0

func _zones() -> ZoneMap:
	if world and is_instance_valid(world):
		var z: Variant = world.get(&"zones")
		if z is ZoneMap:
			return z
	return null

func _is_night() -> bool:
	if world and is_instance_valid(world) and world.has_method(&"is_night"):
		return bool(world.call(&"is_night"))
	return false

# ------------------------------------------------------------------ 33: луна → прилив

## Сизигийный прилив (новолуние/полнолуние) — полная амплитуда, квадратура (половина луны) —
## 0.7 от неё. Амплитуда не превышает базовую: самый низкий отлив тот же, что в ZoneMap
## (кораллы и рыбы рассчитаны на него).
static func moon_tide_factor(illum: float) -> float:
	return 0.7 + 0.3 * absf(2.0 * clampf(illum, 0.0, 1.0) - 1.0)

func _update_moon_tide() -> void:
	if world == null or not is_instance_valid(world) or world.get(&"tide_amplitude") == null:
		return
	if base_tide < 0.0:
		base_tide = float(world.get(&"tide_amplitude"))
	var sky: Variant = world.get(&"sky")
	if sky == null or not (sky as Object).has_method(&"moon_illumination"):
		return
	var f := moon_tide_factor(float((sky as Object).call(&"moon_illumination")))
	tide_factor = lerpf(tide_factor, f, 0.2)
	world.set(&"tide_amplitude", base_tide * tide_factor)

# ------------------------------------------------------------------ 27: гуано

func _spawn_guano() -> void:
	_guano_done = true
	if world == null or not is_instance_valid(world):
		return
	var found := world.find_children("Guano", "MultiMeshInstance3D", true, false)
	for n in found:
		var mmi := n as MultiMeshInstance3D
		var mm := mmi.multimesh
		if mm == null:
			continue
		var picked: Array[Vector3] = []
		var step := maxi(1, mm.instance_count / 40)
		for i in range(0, mm.instance_count, step):
			var p := mmi.global_transform * mm.get_instance_transform(i).origin
			var ok := true
			for q in picked:
				if q.distance_to(p) < 9.0:
					ok = false
					break
			if not ok:
				continue
			picked.append(p)
			if picked.size() >= 10:
				break
		for p in picked:
			add_guano(p)

func add_guano(p: Vector3) -> GuanoDeposit:
	var g := GuanoDeposit.new()
	add_child(g)
	g.global_position = p
	stats.guano += 1
	return g

# ------------------------------------------------------------------ 28: падальщики и мухи

func _scan_corpses(pp: Vector3) -> void:
	for a in get_tree().get_nodes_in_group(&"animals"):
		if not (a is Animal) or not is_instance_valid(a):
			continue
		var an := a as Animal
		if not an.dead:
			continue
		var id := an.get_instance_id()
		# перья — гибель птицы
		if an.cfg.get("fly", false):
			if not _feathered.has(id):
				_feathered[id] = true
				feathers(an.global_position, an.species)
			continue
		if carrion.has(id) or an.global_position.distance_to(pp) > 320.0:
			continue
		var box: Vector3 = an.cfg.get("box", Vector3.ONE)
		if maxf(box.x, box.z) * an.growth < CARRION_MIN_LEN:
			continue
		if float(an.get(&"_dead_t")) < CARRION_DELAY and not an.has_meta(&"carrion_now"):
			continue
		add_carrion(an)
	# тушки, которых больше нет
	for id in carrion.keys():
		var c: Dictionary = carrion[id]
		if not is_instance_valid(c.get("corpse")):
			_drop_carrion(id)

## Падальщики над тушей: стая чаек кружит на 28–38 м (их видно издалека), мухи у тушки.
func add_carrion(corpse: Node3D) -> Dictionary:
	var id := corpse.get_instance_id()
	if carrion.has(id):
		return carrion[id]
	var c := corpse.global_position
	var fl := {"species": &"gull", "home": c, "r": 30.0, "mode": &"fly", "pos": c + Vector3(0, 32, 0),
		"perch": Vector3.INF, "members": [], "t0": _clock}
	var birds: Array[Animal] = []
	for i in _rng.randi_range(3, 5):
		var off := Vector3(_rng.randf_range(-6, 6), _rng.randf_range(-2, 3), _rng.randf_range(-6, 6))
		var b := Animal.create(&"gull", c + Vector3(0, 30, 0) + off, Fauna.instance())
		b.cfg = (Animal.SPECIES[&"gull"] as Dictionary).duplicate(true)
		b.cfg["flee_r"] = 0.0          # высоко — игрока не боятся
		b.flock = fl
		b.flock_offset = off
		add_child(b)
		b.global_position = c + Vector3(0, 30, 0) + off
		b.alt = 30.0
		b.add_to_group(&"carrion_birds")
		birds.append(b)
		(fl.members as Array).append(b)
	var sw := FlySwarm.make(&"flies", 0.7, 30)
	sw.follow = corpse
	sw.follow_offset = Vector3(0, 0.45, 0)
	add_child(sw)
	var rec := {"corpse": corpse, "flock": fl, "birds": birds, "flies": sw}
	carrion[id] = rec
	stats.carrion += 1
	stats.flies += 1
	return rec

func _drop_carrion(id: int) -> void:
	var c: Dictionary = carrion[id]
	for b in c.birds:
		if is_instance_valid(b):
			(b as Node).queue_free()
	if is_instance_valid(c.flies):
		(c.flies as Node).queue_free()
	carrion.erase(id)

func _physics_process(dt: float) -> void:
	# падальщики: кружат над тушей, медленно снижаются кругами
	for id in carrion.keys():
		var c: Dictionary = carrion[id]
		if not is_instance_valid(c.corpse):
			continue
		var cp := (c.corpse as Node3D).global_position
		var fl: Dictionary = c.flock
		var age := _clock - float(fl.t0)
		var h := maxf(18.0, 36.0 - age * 0.08)
		fl.pos = Vector3(cp.x + cos(_clock * 0.35) * 14.0, cp.y + h, cp.z + sin(_clock * 0.35) * 14.0)
		for b in c.birds:
			if is_instance_valid(b):
				(b as Animal).tick(dt)

## Еда: на земле (подобрать не успели) и в сундуках — мухи и муравьи.
func _scan_food(pp: Vector3) -> void:
	var live := {}
	for n in get_tree().get_nodes_in_group(&"pickups"):
		if not (n is ItemPickup) or not is_instance_valid(n):
			continue
		var ip := n as ItemPickup
		if ip.global_position.distance_to(pp) > 80.0:
			continue
		var id := ip.get_instance_id()
		live[id] = true
		if not pickup_seen.has(id):
			pickup_seen[id] = _clock
		var age := _clock - float(pickup_seen[id])
		var food := _has_spoiling(ip.stacks)
		if food and age > FLY_FOOD_AGE and not flies.has(id) and flies.size() < MAX_FLIES:
			add_flies(ip)
		if _is_food(ip.stacks) and age > ANT_FOOD_AGE and not ants.has(id) and ants.size() < MAX_ANTS and not _nature_ants():
			add_ants(ip)
	# сундуки с портящейся едой
	for n in get_tree().get_nodes_in_group(&"buildable"):
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var nd := n as Node3D
		if nd.global_position.distance_to(pp) > 60.0:
			continue
		var inv := _inventory_of(nd)
		if inv == null:
			continue
		var id := nd.get_instance_id()
		live[id] = true
		var has := false
		for s in inv.slots:
			if not s.is_empty() and StringName(s.get("id", &"")) in SPOILING:
				has = true
				break
		if has and not flies.has(id) and flies.size() < MAX_FLIES:
			add_flies(nd)
		elif not has and flies.has(id):
			(flies[id] as Node).queue_free()
			flies.erase(id)
	for id in flies.keys():
		var sw: Node = flies[id]
		if not is_instance_valid(sw) or (not live.has(id) and not _is_corpse_id(id)):
			if is_instance_valid(sw):
				sw.queue_free()
			flies.erase(id)
	for id in ants.keys():
		var at: Node = ants[id]
		if not is_instance_valid(at) or not live.has(id):
			if is_instance_valid(at):
				at.queue_free()
			ants.erase(id)
	for id in pickup_seen.keys():
		if not live.has(id):
			pickup_seen.erase(id)

## Агент N (NatureDetails) уже рисует муравьёв к еде — тогда свои не ставим (не дублировать).
var _nd_checked := false
var _nd_has := false
func _nature_ants() -> bool:
	if not _nd_checked:
		_nd_checked = true
		_nd_has = world != null and is_instance_valid(world) and world.find_child("NatureDetails", true, false) != null
	return _nd_has

func _is_corpse_id(id: int) -> bool:
	return carrion.has(id)

func _inventory_of(n: Node) -> Inventory:
	var v: Variant = n.get(&"inventory")
	if v is Inventory:
		return v
	for c in n.get_children():
		if c is Inventory:
			return c
	return null

func _has_spoiling(stacks: Array) -> bool:
	for s in stacks:
		if StringName(s.get("id", &"")) in SPOILING:
			return true
	return false

func _is_food(stacks: Array) -> bool:
	for s in stacks:
		var d := Items.get_item(StringName(s.get("id", &"")))
		if d != null and d.kind == &"food":
			return true
	return _has_spoiling(stacks)

func add_flies(src: Node3D) -> FlySwarm:
	var sw := FlySwarm.make(&"flies", 0.45, 20)
	sw.follow = src
	sw.follow_offset = Vector3(0, 0.35, 0)
	add_child(sw)
	flies[src.get_instance_id()] = sw
	stats.flies += 1
	return sw

# ------------------------------------------------------------------ 33: муравьи к еде

func add_ants(food: Node3D) -> Node3D:
	var at := AntTrail.new()
	at.food = food
	at.world = world
	add_child(at)
	ants[food.get_instance_id()] = at
	stats.ants += 1
	return at

# ------------------------------------------------------------------ 29: комары

func _tick_mosquitoes(dt: float) -> void:
	var pl := get_tree().get_first_node_in_group(&"player") as Node3D
	var want := false
	if pl and _is_night():
		var zm := _zones()
		if zm and zm.inside(pl.global_position.x, pl.global_position.z):
			var zn := zm.zone_name_at(pl.global_position.x, pl.global_position.z)
			want = zn in [&"mangrove", &"mangrove_water"] or (zn == &"freshwater" and zm.wetness(pl.global_position.x, pl.global_position.z) > 0.6)
	var smoke := pl != null and _smoke_near(pl.global_position)
	if want and not smoke:
		if mosquitoes == null or not is_instance_valid(mosquitoes):
			mosquitoes = FlySwarm.make(&"mosquito", 0.9, 40)
			mosquitoes.follow = pl
			mosquitoes.follow_offset = Vector3(0, 1.5, 0)
			add_child(mosquitoes)
			if not _mosq_warned:
				_mosq_warned = true
				Events.toast.emit("Комары! Дым костра их отгоняет.")
		_bite_t -= dt
		if _bite_t <= 0.0:
			_bite_t = MOSQUITO_DPS_EVERY
			if pl.has_method(&"apply_damage"):
				pl.call(&"apply_damage", 0.5, null, &"insect")
				stats.bites += 1
	elif mosquitoes and is_instance_valid(mosquitoes):
		mosquitoes.queue_free()
		mosquitoes = null

func _smoke_near(p: Vector3) -> bool:
	for f in get_tree().get_nodes_in_group(&"campfire"):
		if f is Node3D and (f as Node3D).global_position.distance_to(p) < SMOKE_R:
			return true
	return false

## Для тестов/полигона: включён ли сейчас рой комаров у игрока.
func mosquitoes_active() -> bool:
	return mosquitoes != null and is_instance_valid(mosquitoes)

# ------------------------------------------------------------------ 33: полоса выброса после шторма

func _watch_storm() -> void:
	if world == null or not is_instance_valid(world) or not world.has_method(&"storm_intensity"):
		return
	var s := float(world.call(&"storm_intensity"))
	_storm_peak = maxf(_storm_peak, s)
	if _storm_peak > 0.6 and s < 0.2:
		_storm_peak = 0.0
		spawn_wrack(_player_pos(), 220.0)

## Полоса выброса: водоросли и плавник по линии высокой воды на пляжах вокруг center.
func spawn_wrack(center: Vector3, radius: float) -> int:
	var zm := _zones()
	var pts: Array[Vector3] = []
	var hi := 0.8 + 0.5           # высокая вода + нагон шторма
	var step := 2.0
	var x := center.x - radius
	while x <= center.x + radius:
		var z := center.z - radius
		while z <= center.z + radius:
			var jx := x + _rng.randf_range(-step, step) * 0.5
			var jz := z + _rng.randf_range(-step, step) * 0.5
			var h := _ground(jx, jz)
			if absf(h - hi) < 0.22:
				var ok := true
				if zm and zm.inside(jx, jz):
					ok = zm.zone_name_at(jx, jz) in [&"beach", &"dunes", &"mangrove"]
				if ok:
					pts.append(Vector3(jx, h, jz))
			z += step
		x += step
	if pts.is_empty():
		return 0
	var root := Node3D.new()
	root.name = "WrackLine"
	root.set_meta(&"t0", _clock)
	add_child(root)
	root.add_child(_wrack_mm(pts, false))
	var wood: Array[Vector3] = []
	for p in pts:
		if _rng.randf() < 0.07:
			wood.append(p)
	if not wood.is_empty():
		root.add_child(_wrack_mm(wood, true))
	_wrack_nodes.append(root)
	stats.wrack += pts.size()
	return pts.size()

func _wrack_mm(pts: Array[Vector3], wood: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var m: Mesh
	if wood:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = 0.07
		cm.height = 1.0
		cm.radial_segments = 6
		m = cm
	else:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.12, 0.025, 0.7)
		m = bm
	mm.mesh = m
	var per := 1 if wood else 4
	mm.instance_count = pts.size() * per
	var k := 0
	for p in pts:
		for j in per:
			var b := Basis(Vector3.UP, _rng.randf() * TAU)
			var s := _rng.randf_range(0.6, 1.4)
			if wood:
				b = b * Basis(Vector3.RIGHT, PI * 0.5)
				b = b.scaled(Vector3(1, _rng.randf_range(0.6, 1.8), 1))
			else:
				b = b.scaled(Vector3(s, 1, s))
			var o := p + Vector3(_rng.randf_range(-0.9, 0.9), 0.02, _rng.randf_range(-0.9, 0.9))
			mm.set_instance_transform(k, Transform3D(b, o))
			var col := Color(0.55, 0.47, 0.36) if wood else Color(0.2, 0.22, 0.1).lerp(Color(0.32, 0.24, 0.12), _rng.randf())
			mm.set_instance_color(k, col)
			k += 1
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9 if wood else 0.45      # водоросли мокрые, блестят
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 260.0
	return mi

# ------------------------------------------------------------------ 33: перья

func feathers(p: Vector3, sp: StringName) -> Node3D:
	var root := Node3D.new()
	root.name = "Feathers"
	root.set_meta(&"t0", _clock)
	add_child(root)
	var g := _ground(p.x, p.z)
	root.global_position = Vector3(p.x, g, p.z)
	var col := Color(0.92, 0.92, 0.9) if sp == &"gull" else (Color(0.2, 0.6, 0.25) if sp == &"parrot" else Color(0.3, 0.25, 0.2))
	# облачко перьев в момент гибели
	var ps := CPUParticles3D.new()
	ps.one_shot = true
	ps.explosiveness = 0.9
	ps.amount = 16
	ps.lifetime = 3.5
	ps.direction = Vector3.UP
	ps.spread = 80.0
	ps.initial_velocity_min = 0.8
	ps.initial_velocity_max = 2.2
	ps.gravity = Vector3(0, -0.8, 0)
	ps.damping_min = 0.8
	ps.damping_max = 1.6
	ps.angular_velocity_min = -180.0
	ps.angular_velocity_max = 180.0
	ps.scale_amount_min = 0.05
	ps.scale_amount_max = 0.09
	var qm := QuadMesh.new()
	qm.size = Vector2(0.4, 1.0)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = col
	pm.cull_mode = BaseMaterial3D.CULL_DISABLED
	qm.material = pm
	ps.mesh = qm
	root.add_child(ps)
	ps.global_position = p
	ps.emitting = true
	# перья на земле — остаются
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var q2 := QuadMesh.new()
	q2.size = Vector2(0.025, 0.09)
	q2.orientation = PlaneMesh.FACE_Y
	mm.mesh = q2
	mm.instance_count = 18
	for i in 18:
		var a := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * 1.3
		var o := Vector3(cos(a) * r, 0.0, sin(a) * r)
		var gy := _ground(p.x + o.x, p.z + o.z) - g + 0.015
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), Vector3(o.x, gy, o.z)))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = col
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = fm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	stats.feathers += 1
	return root

# ------------------------------------------------------------------ 33: следы черепахи к гнезду

func _scan_nests(pp: Vector3) -> void:
	for n in get_tree().get_nodes_in_group(&"turtle_nests"):
		if not (n is Node3D) or not is_instance_valid(n) or n.has_meta(&"tracks_done"):
			continue
		if (n as Node3D).global_position.distance_to(pp) > 200.0:
			continue
		turtle_tracks(n as Node3D)

## Две борозды ласт и полоса пластрона от воды до гнезда — «дорожка», по которой находят кладку.
func turtle_tracks(nest: Node3D) -> MultiMeshInstance3D:
	nest.set_meta(&"tracks_done", true)
	var N := nest.global_position
	var W: Vector3 = nest.get_meta(&"from_water", Vector3.INF)
	if W == Vector3.INF:
		W = _find_water(N, 60.0)
	if W == Vector3.INF:
		W = N + Vector3(0, 0, -14)
	var d := Vector3(W.x - N.x, 0, W.z - N.z)
	var L := d.length()
	if L < 1.0:
		return null
	var dir := d / L
	var side := dir.rotated(Vector3.UP, PI * 0.5)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3(0.26, 0.02, 0.12)
	mm.mesh = bm
	var marks: Array[Transform3D] = []
	var s := 0.0
	var wob := _rng.randf() * TAU
	while s < L:
		var c := N + dir * s + side * sin(s * 0.35 + wob) * 0.25
		for k in [-1, 1]:
			var o: Vector3 = c + side * 0.38 * k
			var gy := _ground(o.x, o.z)
			if gy < _water() - 0.05:
				continue
			var b := Basis(Vector3.UP, atan2(-dir.x, -dir.z) + 0.5 * k)
			marks.append(Transform3D(b, Vector3(o.x, gy - 0.004, o.z)))
		var gc := _ground(c.x, c.z)
		if gc >= _water() - 0.05:
			var bc := Basis(Vector3.UP, atan2(-dir.x, -dir.z)).scaled(Vector3(1.8, 1, 2.6))
			marks.append(Transform3D(bc, Vector3(c.x, gc - 0.006, c.z)))
		s += 0.32
	mm.instance_count = marks.size()
	for i in marks.size():
		mm.set_instance_transform(i, marks[i])
	var mi := MultiMeshInstance3D.new()
	mi.name = "TurtleTracks"
	mi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.55, 0.42)
	mat.roughness = 1.0
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	nest.add_child(mi)
	mi.global_transform = Transform3D.IDENTITY
	stats.turtle_tracks += 1
	return mi

func _find_water(from: Vector3, r: float) -> Vector3:
	var best := Vector3.INF
	var bd := INF
	for i in 24:
		var dir := Vector2.from_angle(TAU * i / 24.0)
		var d := 2.0
		while d <= r:
			var p := Vector2(from.x, from.z) + dir * d
			if _ground(p.x, p.y) < _water() - 0.2:
				if d < bd:
					bd = d
					best = Vector3(p.x, _water(), p.y)
				break
			d += 2.0
	return best

# ------------------------------------------------------------------ 33: зелёная полоса и лягушки у пресной воды

func _scan_seeps(pp: Vector3) -> void:
	if world == null or not is_instance_valid(world):
		return
	var springs: Array[Vector3] = []
	if world.has_method(&"monuments"):
		for m: Dictionary in world.call(&"monuments"):
			if StringName(m.get("type", &"")) == &"spring":
				springs.append(m.pos)
	var zm := _zones()
	if zm and zm.inside(pp.x, pp.z):
		# ячейки пресной воды рядом с игроком (ручьи, озерца)
		var x := pp.x - 120.0
		while x <= pp.x + 120.0:
			var z := pp.z - 120.0
			while z <= pp.z + 120.0:
				if zm.zone_name_at(x, z) == &"freshwater":
					springs.append(Vector3(x, _ground(x, z), z))
				z += 24.0
			x += 24.0
	for s in springs:
		if s.distance_to(pp) > 160.0:
			continue
		var key := "%d_%d" % [int(s.x / 30.0), int(s.z / 30.0)]
		if _seeps_done.has(key):
			continue
		_seeps_done[key] = true
		seep(s)

## Сырая «зелёная полоса» от источника вниз по склону: сочная трава и лягушки.
func seep(src: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "FreshSeep"
	add_child(root)
	var pts: Array[Vector3] = []
	var p := src
	for i in 22:
		pts.append(Vector3(p.x, _ground(p.x, p.z), p.z))
		# вниз по склону
		var best := p
		var bh := _ground(p.x, p.z)
		for k in 8:
			var q := p + Vector3.FORWARD.rotated(Vector3.UP, TAU * k / 8.0) * 2.0
			var h := _ground(q.x, q.z)
			if h < bh - 0.02:
				bh = h
				best = q
		if best == p or bh < _water() + 0.3:
			break
		p = best
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var qm := QuadMesh.new()
	qm.size = Vector2(0.18, 0.55)
	qm.center_offset = Vector3(0, 0.27, 0)
	mm.mesh = qm
	var xf: Array[Transform3D] = []
	var cols: Array[Color] = []
	for c in pts:
		for j in 26:
			var o := c + Vector3(_rng.randf_range(-1.3, 1.3), 0, _rng.randf_range(-1.3, 1.3))
			var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.7, 1.5))
			xf.append(Transform3D(b, Vector3(o.x, _ground(o.x, o.z), o.z)))
			cols.append(Color(0.2, 0.55, 0.15).lerp(Color(0.35, 0.68, 0.2), _rng.randf()))
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_color(i, cols[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.6
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 180.0
	root.add_child(mi)
	# лягушки у воды
	if pts.size() > 2 and ClassDB.class_exists(&"Node"):
		for k in _rng.randi_range(2, 4):
			var fp: Vector3 = pts[_rng.randi() % pts.size()] + Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1))
			CreatureSpawner.spawn("frog_tree", Vector3(fp.x, _ground(fp.x, fp.z), fp.z), 1, 0.5)
	stats.seeps += 1
	return root

# ------------------------------------------------------------------ уборка

func _expire() -> void:
	for i in range(_wrack_nodes.size() - 1, -1, -1):
		var w := _wrack_nodes[i]
		if not is_instance_valid(w):
			_wrack_nodes.remove_at(i)
		elif _clock - float(w.get_meta(&"t0", _clock)) > WRACK_LIFE:
			w.queue_free()
			_wrack_nodes.remove_at(i)
	for c in get_children():
		if c.name.begins_with("Feathers") and _clock - float(c.get_meta(&"t0", _clock)) > FEATHER_LIFE:
			c.queue_free()


## Муравьиная дорожка: цепочка муравьёв от «муравейника» (3–6 м в стороне) к еде и обратно.
class AntTrail extends Node3D:
	var food: Node3D
	var world: Node
	var nest := Vector3.ZERO
	var _mm: MultiMesh
	var _n := 46
	var _t := 0.0
	var _path: Array[Vector3] = []

	func _ready() -> void:
		name = "AntTrail"
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var f := food.global_position
		var a := rng.randf() * TAU
		nest = f + Vector3(cos(a), 0, sin(a)) * rng.randf_range(3.0, 6.0)
		for i in 13:
			var k := i / 12.0
			var p := f.lerp(nest, k) + Vector3(cos(a + PI * 0.5), 0, sin(a + PI * 0.5)) * sin(k * PI * 2.3) * 0.35
			_path.append(Vector3(p.x, _g(p.x, p.z) + 0.006, p.z))
		_mm = MultiMesh.new()
		_mm.transform_format = MultiMesh.TRANSFORM_3D
		var bm := BoxMesh.new()
		bm.size = Vector3(0.004, 0.003, 0.011)
		_mm.mesh = bm
		_mm.instance_count = _n
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = _mm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.08, 0.04, 0.03)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 25.0
		mi.top_level = true
		add_child(mi)
		# муравейник — холмик земли
		var hill := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.16
		sm.height = 0.12
		hill.mesh = sm
		var hm := StandardMaterial3D.new()
		hm.albedo_color = Color(0.4, 0.3, 0.2)
		hm.roughness = 1.0
		hill.material_override = hm
		hill.top_level = true
		add_child(hill)
		hill.global_position = _path[_path.size() - 1]

	func _g(x: float, z: float) -> float:
		if world and is_instance_valid(world) and world.has_method(&"height_at"):
			return float(world.call(&"height_at", x, z))
		return 0.0

	func _process(dt: float) -> void:
		if not is_instance_valid(food):
			queue_free()
			return
		_t += dt
		var L := _path.size() - 1
		for i in _n:
			var ph := fposmod(_t * 0.035 + float(i) / _n, 1.0)
			var back := i % 2 == 0        # половина идёт к еде, половина — обратно
			var u := ph if back else 1.0 - ph
			var fi := u * L
			var k := mini(int(fi), L - 1)
			var p := _path[k].lerp(_path[k + 1], fi - k)
			var d := _path[k + 1] - _path[k]
			var yaw := atan2(-d.x, -d.z) + (PI if back else 0.0)
			_mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw), p + Vector3(0.012 * sin(i * 1.7), 0, 0.012 * cos(i * 2.3))))
