class_name ShowDrones
extends Node3D
## Лор шоу (docs/LORE.md): дроны-камеры телеканала висят над участниками и снимают их.
## Один дрон всегда «ведёт» игрока, остальные (до MAX-1) — ближайших к камере живых
## участников (боты, союзники). Дрон держится сзади-сверху цели, медленно облетает её,
## объектив смотрит на цель, мигает красный огонёк «в эфире». Без коллизий: чистый декор.
## Перераспределение целей — раз в RETARGET с; дальше FAR м от камеры — дрон скрыт.
##
## Возрождение подаётся как «дрон-медик»: при повторном появлении участника над ним
## спускается дрон с красным крестом, вспышка — и он улетает (medic_count — для тестов).
##
## API: ShowDrones.instance(), drones (Array[Node3D]), drone_for(ch) -> Node3D, target_of(drone)

const MAX := 4
const RETARGET := 2.0
const FAR := 140.0
const HEIGHT := 4.5
const RADIUS := 6.5
const SPEED := 3.5        # сглаживание следования (1/с)

var drones: Array[Node3D] = []
var _targets: Dictionary = {}   # drone instance_id -> Node3D
var _phase: Dictionary = {}     # drone instance_id -> float
var _retarget_t := 0.0
var _t := 0.0
var _seen: Dictionary = {}      # instance_id участников, уже появлявшихся (повтор = возрождение)
var medic_count := 0

static func instance() -> ShowDrones:
	var t := Engine.get_main_loop() as SceneTree
	return t.get_first_node_in_group(&"show_drones") as ShowDrones if t else null

func _ready() -> void:
	name = "ShowDrones"
	add_to_group(&"show_drones")
	for i in MAX:
		var d := build_drone()
		d.name = "Drone%d" % i
		d.visible = false
		add_child(d)
		drones.append(d)
		_phase[d.get_instance_id()] = TAU * float(i) / MAX
	for ch in get_tree().get_nodes_in_group(&"characters"):
		_seen[ch.get_instance_id()] = true
	Events.character_spawned.connect(_on_spawned)

func _on_spawned(ch: Node) -> void:
	var id := ch.get_instance_id()
	if not _seen.has(id):
		_seen[id] = true
		return
	if ch is Node3D:
		medic_drop((ch as Node3D).global_position)

## Дрон-медик: спуск сверху к точке возрождения, вспышка, подъём и исчезновение (~3.5 с).
func medic_drop(at: Vector3) -> void:
	medic_count += 1
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_to(at) > FAR:
		return
	var d := build_drone(true)
	d.name = "MedicDrone"
	add_child(d)
	d.global_position = at + Vector3.UP * 14.0
	var tw := d.create_tween()
	tw.tween_property(d, "global_position", at + Vector3.UP * 2.4, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_medic_flash.bind(d))
	tw.tween_interval(0.6)
	tw.tween_property(d, "global_position", at + Vector3(2.0, 26.0, 1.0), 1.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(d.queue_free)

func _medic_flash(d: Node3D) -> void:
	if not is_instance_valid(d) or not d.is_inside_tree():
		return
	var p := d.global_position
	CombatFx.flash_light(self, p + Vector3.DOWN * 0.8, Color(0.85, 0.95, 1.0), 6.0, 7.0, 0.5)
	CombatFx.particles(self, p + Vector3.DOWN * 1.6, 18, 1.2, "smoke", true,
		CombatFx._ramp([Color(0.8, 0.95, 1.0, 0.9), Color(0.6, 0.85, 1.0, 0.0)]), 0.25, 2.5, 180.0, Vector3.UP, Vector3(0, 0.6, 0))

func drone_for(ch: Node) -> Node3D:
	for d in drones:
		if _targets.get(d.get_instance_id()) == ch:
			return d
	return null

func target_of(d: Node3D) -> Node3D:
	var t: Variant = _targets.get(d.get_instance_id())
	return t as Node3D if t != null and is_instance_valid(t) else null

func _process(delta: float) -> void:
	var __pt := PerfStats.begin()
	_perf_process(delta)
	PerfStats.end(&"supply", __pt)

func _perf_process(delta: float) -> void:
	_t += delta
	_retarget_t -= delta
	if _retarget_t <= 0.0:
		_retarget_t = RETARGET
		_retarget()
	var cam := get_viewport().get_camera_3d()
	for d in drones:
		var tg := target_of(d)
		if tg == null:
			d.visible = false
			continue
		if not d.visible:
			d.visible = true
			d.global_position = _want(d, tg)
		var want := _want(d, tg)
		d.global_position = d.global_position.lerp(want, clampf(delta * SPEED, 0.0, 1.0))
		var far := cam != null and cam.global_position.distance_to(d.global_position) > FAR
		if far:
			d.visible = false
			continue
		_animate(d, tg, delta)

## Где должен висеть дрон: сзади-сверху цели, медленный облёт, лёгкое «дыхание» по высоте.
func _want(d: Node3D, tg: Node3D) -> Vector3:
	var ph := float(_phase.get(d.get_instance_id(), 0.0)) + _t * 0.12
	var back := -tg.global_transform.basis.z
	var base_a := atan2(back.x, back.z)
	var a := base_a + sin(ph) * 1.1
	var p := tg.global_position + Vector3(sin(a), 0.0, cos(a)) * RADIUS
	var ground := BuildEnv.height_at(p.x, p.z)
	var y := maxf(tg.global_position.y + HEIGHT, maxf(ground, BuildEnv.water_level()) + 3.0)
	return Vector3(p.x, y + sin(_t * 1.3 + ph) * 0.25, p.z)

func _animate(d: Node3D, tg: Node3D, delta: float) -> void:
	# корпус слегка разворачивается к цели, подвес с камерой смотрит прямо на неё
	var to := tg.global_position + Vector3.UP * 1.2 - d.global_position
	var yaw := atan2(-to.x, -to.z)
	d.rotation.y = lerp_angle(d.rotation.y, yaw, clampf(delta * 3.0, 0.0, 1.0))
	d.rotation.x = 0.0
	var gim := d.get_node_or_null(^"Gimbal") as Node3D
	if gim and to.length() > 0.5:
		gim.look_at(tg.global_position + Vector3.UP * 1.2, Vector3.UP)
	for i in 4:
		var r := d.get_node_or_null(NodePath("Rotor%d" % i)) as Node3D
		if r:
			r.rotate_y(delta * (38.0 if i % 2 == 0 else -38.0))
	var led := d.get_node_or_null(^"Led") as MeshInstance3D
	if led:
		led.visible = fmod(_t, 1.0) < 0.5

## Цели: игрок (если жив) + ближайшие к камере живые участники.
func _retarget() -> void:
	var cam := get_viewport().get_camera_3d()
	var from := cam.global_position if cam else Vector3.ZERO
	var cands: Array = []
	var player: Node3D = null
	for ch in get_tree().get_nodes_in_group(&"characters"):
		if not (ch is Node3D) or not Game.is_alive(ch):
			continue
		if ch.is_in_group(&"player") and player == null:
			player = ch
			continue
		var dist := (ch as Node3D).global_position.distance_to(from)
		if dist < FAR:
			cands.append([dist, ch])
	if player == null:
		var p := get_tree().get_first_node_in_group(&"player") as Node3D
		if p and Game.is_alive(p):
			player = p
	cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var want: Array = []
	if player:
		want.append(player)
	for c: Array in cands:
		if want.size() >= MAX:
			break
		want.append(c[1])
	# у кого цель осталась в списке — держим, остальных перераспределяем
	var free: Array[Node3D] = []
	for d in drones:
		var tg := target_of(d)
		if tg != null and want.has(tg):
			want.erase(tg)
		else:
			_targets.erase(d.get_instance_id())
			free.append(d)
	for d in free:
		if want.is_empty():
			break
		_targets[d.get_instance_id()] = want.pop_front()
		d.visible = false   # появится сразу на своём месте (без перелёта через карту)

# ------------------------------------------------------------ модель

static var _mats: Dictionary = {}

static func clear_caches() -> void:
	_mats.clear()

static func _mat(kind: String) -> StandardMaterial3D:
	if _mats.has(kind):
		return _mats[kind]
	var m := StandardMaterial3D.new()
	match kind:
		"body":
			m.albedo_color = Color(0.13, 0.135, 0.14)
			m.roughness = 0.45
			m.metallic = 0.3
		"arm":
			m.albedo_color = Color(0.07, 0.07, 0.075)
			m.roughness = 0.6
		"rotor":
			m.albedo_color = Color(0.1, 0.1, 0.1, 0.35)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.roughness = 0.5
		"lens":
			m.albedo_color = Color(0.02, 0.03, 0.05)
			m.roughness = 0.05
			m.metallic = 0.6
		"led":
			m.albedo_color = Color(1.0, 0.1, 0.05)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.08, 0.04)
			m.emission_energy_multiplier = 4.0
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		"stripe":
			m.albedo_color = Color(0.95, 0.42, 0.08)
			m.roughness = 0.5
		"medic":
			m.albedo_color = Color(0.92, 0.93, 0.9)
			m.roughness = 0.5
		"cross":
			m.albedo_color = Color(0.8, 0.06, 0.05)
			m.roughness = 0.5
	_mats[kind] = m
	return m

static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b

static func _mi(p: Node3D, mesh: Mesh, m: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, nm: String = "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if nm != "":
		mi.name = nm
	p.add_child(mi)
	return mi

## Квадрокоптер ~0.6 м: корпус, 4 луча с моторами и прозрачными дисками винтов,
## подвес с камерой (узел Gimbal, -Z — объектив), оранжевая полоса шоу, красный огонёк.
static func build_drone(medic: bool = false) -> Node3D:
	var d := Node3D.new()
	var body := BoxMesh.new()
	body.size = Vector3(0.22, 0.07, 0.3)
	_mi(d, body, _mat("body"), Vector3.ZERO)
	var top := BoxMesh.new()
	top.size = Vector3(0.16, 0.035, 0.2)
	_mi(d, top, _mat("body"), Vector3(0, 0.05, 0.02))
	var stripe := BoxMesh.new()
	stripe.size = Vector3(0.225, 0.02, 0.06)
	_mi(d, stripe, _mat("medic" if medic else "stripe"), Vector3(0, 0.01, -0.1))
	if medic:
		# красный крест сверху
		var c1 := BoxMesh.new()
		c1.size = Vector3(0.12, 0.012, 0.035)
		var c2 := BoxMesh.new()
		c2.size = Vector3(0.035, 0.012, 0.12)
		_mi(d, _box(Vector3(0.15, 0.008, 0.15)), _mat("medic"), Vector3(0, 0.072, 0.02))
		_mi(d, c1, _mat("cross"), Vector3(0, 0.078, 0.02))
		_mi(d, c2, _mat("cross"), Vector3(0, 0.078, 0.02))
		# и снизу — видно с земли
		_mi(d, _box(Vector3(0.2, 0.006, 0.2)), _mat("medic"), Vector3(0, -0.038, 0.06))
		_mi(d, c1, _mat("cross"), Vector3(0, -0.043, 0.06))
		_mi(d, c2, _mat("cross"), Vector3(0, -0.043, 0.06))
	var arm := BoxMesh.new()
	arm.size = Vector3(0.03, 0.025, 0.34)
	var motor := CylinderMesh.new()
	motor.top_radius = 0.028
	motor.bottom_radius = 0.032
	motor.height = 0.05
	motor.radial_segments = 10
	var disc := CylinderMesh.new()
	disc.top_radius = 0.15
	disc.bottom_radius = 0.15
	disc.height = 0.004
	disc.radial_segments = 16
	var blade := BoxMesh.new()
	blade.size = Vector3(0.29, 0.004, 0.025)
	for i in 4:
		var a := PI * 0.25 + PI * 0.5 * i
		var dir := Vector3(sin(a), 0.0, cos(a))
		_mi(d, arm, _mat("arm"), dir * 0.17, Vector3(0, a, 0))
		var tip := dir * 0.32
		_mi(d, motor, _mat("arm"), tip + Vector3(0, 0.02, 0))
		var rotor := Node3D.new()
		rotor.name = "Rotor%d" % i
		rotor.position = tip + Vector3(0, 0.05, 0)
		d.add_child(rotor)
		_mi(rotor, disc, _mat("rotor"), Vector3.ZERO)
		_mi(rotor, blade, _mat("arm"), Vector3(0, 0.003, 0))
	# подвес с камерой
	var gim := Node3D.new()
	gim.name = "Gimbal"
	gim.position = Vector3(0, -0.07, -0.08)
	d.add_child(gim)
	var cam_box := BoxMesh.new()
	cam_box.size = Vector3(0.09, 0.08, 0.1)
	_mi(gim, cam_box, _mat("body"), Vector3.ZERO)
	var lens := CylinderMesh.new()
	lens.top_radius = 0.03
	lens.bottom_radius = 0.034
	lens.height = 0.04
	lens.radial_segments = 14
	_mi(gim, lens, _mat("lens"), Vector3(0, 0, -0.065), Vector3(PI * 0.5, 0, 0), "Lens")
	var led := SphereMesh.new()
	led.radius = 0.016
	led.height = 0.032
	led.radial_segments = 8
	led.rings = 4
	_mi(d, led, _mat("led"), Vector3(0, 0.075, -0.06), Vector3.ZERO, "Led")
	return d
