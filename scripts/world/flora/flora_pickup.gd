class_name FloraPickup
extends RigidBody3D
## Мелкий подбираемый предмет на земле: палка, камень, кокос. E — подобрать.

var item_id: StringName = &"stick"
var count: int = 1

## Падение «живого» предмета (кокос с пальмы и т.п.): медленно, без укатывания.
## Включается сам, если после появления тело разморожено (freeze = false).
const MAX_H_SPEED := 0.9 ## м/с — горизонтальная скорость при отрыве
const ROLL_LIMIT := {&"jungle": 1.5, &"meadow": 1.8, &"rocky": 2.5} ## м после касания
const SAND := [&"beach", &"swamp"]
enum { FALL, ROLL, FLOAT, REST }
var mode := REST
var landed_on: StringName = &""
var _r := 0.12
var _land_pos := Vector3.ZERO
var _t := 0.0
var _slow_t := 0.0
var _drift := Vector2.ZERO
var _float_t := 0.0
var _fpos := Vector3.ZERO ## позиция на плаву (global_position кинематического тела в этом кадре ненадёжна)
var _world: Node
var debug := false

static func _make(id: StringName, mesh: Mesh, shape: Shape3D, m: float) -> FloraPickup:
	var p := FloraPickup.new()
	p.item_id = id
	p.mass = m
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.visibility_range_end = 70.0
	mi.visibility_range_end_margin = 10.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	p.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	p.add_child(cs)
	p.freeze = true
	p.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	return p

static func make_coconut() -> FloraPickup:
	var s := SphereShape3D.new()
	s.radius = 0.12
	return _make(&"coconut", FloraLib.coconut_mesh(), s, 1.4)

static func make_stick(rng: RandomNumberGenerator = null) -> FloraPickup:
	var key := "stick_mesh"
	var mesh: Mesh = FloraLib._mesh_cache.get(key)
	if mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		FloraLib._tube(st, Vector3(-0.55, 0, 0), Vector3(0.55, 0.02, 0.03), 0.028, 0.018, 6)
		FloraLib._tube(st, Vector3(0.1, 0.0, 0.0), Vector3(0.32, 0.03, 0.18), 0.014, 0.008, 5)
		st.generate_tangents()
		mesh = st.commit()
		mesh.surface_set_material(0, FloraLib.bark_material("bark_brown_02"))
		FloraLib._mesh_cache[key] = mesh
	var b := BoxShape3D.new()
	b.size = Vector3(1.1, 0.08, 0.12)
	return _make(&"stick", mesh, b, 0.4)

static func make_rock() -> FloraPickup:
	var mesh := FloraLib.first_mesh("res://assets/models/polyhaven/stone_01.glb")
	var s := SphereShape3D.new()
	s.radius = 0.12
	var p := _make(&"rock", mesh, s, 1.5)
	if mesh:
		var aabb := mesh.get_aabb()
		var k := 0.26 / maxf(0.01, aabb.get_longest_axis_size())
		(p.get_child(0) as Node3D).scale = Vector3.ONE * k
		(p.get_child(0) as Node3D).position = -aabb.get_center() * k
	return p

func _ready() -> void:
	add_to_group(&"flora_pickups")   # v5.2: пальмовый вор ищет кокосы, спотыкание об кокос
	_check_dynamic.call_deferred()

## v5.2: падающий кокос бьёт того, кто под пальмой (голова — больно, зверю — тоже).
var _hit_done := false
var _fall_y0 := 0.0
const HEAD_HIT_DMG := 18.0

func _check_hit() -> void:
	if _hit_done or item_id != &"coconut" or linear_velocity.y > -2.0:
		return
	var p := global_position
	for c in get_tree().get_nodes_in_group(&"characters"):
		var ch := c as Node3D
		if ch == null or not ch.has_method(&"apply_damage"):
			continue
		var d := ch.global_position
		var top := d.y + 1.85
		if Vector2(p.x - d.x, p.z - d.z).length() < 0.42 and p.y < top + 0.15 and p.y > d.y + 0.5:
			_hit_done = true
			var h := clampf(_fall_y0 - p.y, 2.0, 25.0)
			var head := p.y > top - 0.35
			var dmg := HEAD_HIT_DMG * (1.0 if head else 0.5) * clampf(h / 12.0, 0.4, 1.6)
			ch.call(&"apply_damage", dmg, self, &"fall")
			if ch.is_in_group(&"player"):
				Events.toast.emit("Кокос упал на голову!" if head else "По плечу ударил кокос")
			Flora.play_sfx(self, "FGHTImpt_PunchRegular_OS_01", p, 0.0, 0.8)
			linear_velocity = Vector3(linear_velocity.x * 0.3 + randf_range(-1, 1), 1.2, linear_velocity.z * 0.3 + randf_range(-1, 1))
			return
	if Fauna.instance():
		for a in Fauna.instance().animals_near(p, 1.5):
			if a.dead or a.cfg.get("fly", false):
				continue
			var box: Vector3 = a.cfg["box"]
			var ap := a.global_position
			if Vector2(p.x - ap.x, p.z - ap.z).length() < maxf(box.x, box.z) * 0.5 * a.growth + 0.1 \
					and p.y < ap.y + box.y * a.growth + 0.2 and p.y > ap.y:
				_hit_done = true
				a.apply_damage(HEAD_HIT_DMG * 0.6, self, &"fall")
				linear_velocity.y = 1.0
				return

func _check_dynamic() -> void:
	if freeze or not is_inside_tree():
		return
	_world = get_tree().get_first_node_in_group(&"world")
	var cs := get_child(1) as CollisionShape3D if get_child_count() > 1 else null
	if cs and cs.shape is SphereShape3D:
		_r = (cs.shape as SphereShape3D).radius
	var pm := PhysicsMaterial.new()
	pm.friction = 1.0
	pm.rough = true
	pm.bounce = 0.04
	physics_material_override = pm
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 2
	linear_damp = 0.15
	angular_damp = 2.5
	var hv := Vector2(linear_velocity.x, linear_velocity.z)
	if hv.length() > MAX_H_SPEED:
		hv = hv.normalized() * MAX_H_SPEED
	linear_velocity = Vector3(hv.x, minf(linear_velocity.y, 0.5), hv.y)
	angular_velocity = Vector3(randf_range(-2, 2), randf_range(-1, 1), randf_range(-2, 2))
	mode = FALL
	_t = 0.0
	_fall_y0 = global_position.y
	set_physics_process(true)

func _ground(x: float, z: float) -> float:
	if _world and _world.has_method(&"height_at"):
		return float(_world.call(&"height_at", x, z))
	return -INF

## Высота водной поверхности над точкой или −INF, если там суша.
func _water_surface(x: float, z: float) -> float:
	if _world == null or not _world.has_method(&"is_land"):
		return -INF
	if bool(_world.call(&"is_land", x, z)):
		return -INF
	var lake := float(_world.call(&"lake_level_at", x, z)) if _world.has_method(&"lake_level_at") else -INF
	if lake > -INF:
		return lake
	return float(_world.call(&"wave_height", x, z))

func _biome(x: float, z: float) -> StringName:
	if _world and _world.has_method(&"biome_at"):
		return _world.call(&"biome_at", x, z)
	return &"meadow"

func _physics_process(dt: float) -> void:
	if mode == REST:
		set_physics_process(false)
		return
	_t += dt
	var p := global_position
	if mode == FLOAT:
		_float_step(dt)
		return
	var surf := _water_surface(p.x, p.z)
	if surf > -INF and p.y <= surf + _r * 0.2:
		_start_float()
		return
	var g := _ground(p.x, p.z)
	if g > -INF and p.y < g + _r - 0.25:
		# провалился сквозь рельеф — поднимаем
		global_position.y = g + _r
		linear_velocity = Vector3.ZERO
	var near_ground := g > -INF and p.y - g < _r + 0.05
	if mode == FALL:
		_check_hit()
		if near_ground or (g == -INF and get_contact_count() > 0) or _t > 6.0:
			_land(p, g)
		elif get_contact_count() > 0 and absf(linear_velocity.y) < 0.4 and _t > 0.3:
			# лёг на постройку/камень над рельефом — остаётся там
			_rest(p.y - _r, 0.0)
		return
	# ROLL
	var lim: float = ROLL_LIMIT.get(landed_on, 1.5)
	var hv := Vector2(linear_velocity.x, linear_velocity.z).length()
	_slow_t = _slow_t + dt if hv < 0.15 else 0.0
	var dist := Vector2(p.x - _land_pos.x, p.z - _land_pos.z).length()
	if dist >= lim or _slow_t > 0.25 or _t > 4.0:
		_rest(g if g > -INF else p.y - _r, 0.0)

func _land(p: Vector3, g: float) -> void:
	if debug: print("[nut] land at ", p, " g=", g, " biome=", _biome(p.x, p.z))
	landed_on = _biome(p.x, p.z)
	_land_pos = p
	_t = 0.0
	if landed_on in SAND:
		# песок: втыкается сразу
		_rest(g if g > -INF else p.y - _r, randf_range(0.03, 0.06))
		if get_parent():
			Flora.chips(get_parent(), global_position, Color(0.78, 0.7, 0.52), 5)
		return
	mode = ROLL
	var hv := Vector2(linear_velocity.x, linear_velocity.z)
	if landed_on == &"rocky":
		linear_damp = 1.2
		angular_damp = 2.0
		hv = hv.limit_length(1.2)
		linear_velocity = Vector3(hv.x, absf(linear_velocity.y) * 0.25, hv.y) # небольшой отскок
	else:
		linear_damp = 3.5
		angular_damp = 5.0
		hv = hv.limit_length(0.7)
		linear_velocity = Vector3(hv.x, minf(linear_velocity.y, 0.0), hv.y)

func _rest(g: float, sink: float) -> void:
	if debug: print("[nut] rest at ", global_position, " g=", g, " mode=", mode, " t=", _t)
	var p := global_position if mode != FLOAT else _fpos
	mode = REST
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	if g > -INF:
		p.y = g + _r - sink
	global_position = p
	if sink > 0.0:
		rotation = Vector3(randf_range(-0.3, 0.3), randf() * TAU, randf_range(-0.3, 0.3))
	contact_monitor = false
	set_physics_process(false)

func _start_float() -> void:
	if debug: print("[nut] float at ", global_position, " t=", _t)
	_fpos = global_position
	mode = FLOAT
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	contact_monitor = false
	var a := randf() * TAU
	_drift = Vector2(cos(a), sin(a)) * 0.1
	_float_t = 0.0

func _float_step(dt: float) -> void:
	_float_t += dt
	var p := _fpos
	var d := _drift if _float_t < 45.0 else Vector2.ZERO
	var nx := p.x + d.x * dt
	var nz := p.z + d.y * dt
	var surf := _water_surface(nx, nz)
	if surf == -INF:
		# прибило к берегу — лежит на песке
		global_position = p
		_rest(_ground(p.x, p.z), randf_range(0.02, 0.04))
		return
	p = Vector3(nx, surf - _r * 0.35, nz)
	_fpos = p
	global_position = p
	rotation = Vector3(sin(_float_t * 1.3) * 0.15, rotation.y + dt * 0.05, cos(_float_t * 1.1) * 0.12)

func get_interact_text(_player: Node) -> String:
	return "E — подобрать: %s" % Items.item_name(item_id).to_lower()

func interact(player: Node) -> void:
	Flora.give(player, item_id, count)
	Flora.play_sfx(self, "OBJBag_KnapsackLeatherClose_OS_01", global_position, -8.0, 1.2)
	queue_free()
