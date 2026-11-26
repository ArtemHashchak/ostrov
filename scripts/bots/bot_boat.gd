class_name BotBoat
extends StaticBody3D
## Лодка для переправы между островами (мир v5, острова в 250–700 м друг от друга).
## Модель — деревянная лодка пользователя (каталог vehicle_wooden_boat). Бот «собирает»
## её на берегу (BUILD_TIME с), садится, гребёт по прямой со скоростью плота
## (≈1,9 м/с — 3–6 минут на пролив), у чужого берега вытаскивает на мель и сходит.
## Лодка остаётся на берегу: её видно, её может взять любой бот (угнать) и её можно
## потопить (урон → тонет и исчезает). В сильный шторм бот не выходит в море.

const SPEED := 1.9
const BUILD_TIME := 20.0
const MAX_HP := 160.0
const SEAT := Vector3(0.0, 0.28, 0.6)     # стоит на палубе (ступни), чуть ближе к корме
const MODEL := "res://assets/user_pack/vehicles/vehicle_wooden_boat.glb"
const STORM_MAX := 0.55          # сильнее — переправу не начинаем
const BEACH_DRAFT := 0.35        # мель: глубже не подходим

var hp := MAX_HP
var team := -1
var rider: Node3D = null
var target := Vector3.INF        # куда плывём (точка у чужого берега, в воде)
var sinking := false
var _world: Node = null
var _model: Node3D = null
var _sink_t := 0.0
var _bob_t := 0.0
var _yaw := 0.0

static func spawn(parent: Node, at: Vector3, yaw: float, team_id: int) -> BotBoat:
	var b := BotBoat.new()
	b.team = team_id
	b._yaw = yaw
	parent.add_child(b)
	b.global_position = at
	b.rotation.y = yaw
	return b

func _ready() -> void:
	add_to_group(&"boat")
	collision_layer = 1
	collision_mask = 0
	_world = get_tree().get_first_node_in_group(&"world")
	var ps := load(MODEL) as PackedScene if ResourceLoader.exists(MODEL) else null
	if ps:
		_model = ps.instantiate() as Node3D
		add_child(_model)
		# модель 3,9×2,9×6,6 м — лодка ~1,6×0,7×4,4 м, нос по −Z
		var aabb := _aabb_of(_model)
		var k := 4.4 / maxf(maxf(aabb.size.x, aabb.size.z), 0.01)
		_model.scale = Vector3.ONE * k
		if aabb.size.x > aabb.size.z:
			_model.rotation.y = PI * 0.5
		# низ корпуса — на 0,15 м под водой (осадка), палуба ~0,25 м над водой
		var c := aabb.get_center()
		if aabb.size.x > aabb.size.z:
			c = Vector3(c.z, c.y, -c.x)   # поворот модели на +90° вокруг Y
		_model.position = Vector3(-c.x * k, -aabb.position.y * k - 0.15, -c.z * k)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.5, 0.6, 4.2)
	cs.shape = sh
	cs.position.y = 0.1
	add_child(cs)

static func _aabb_of(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		# трансформ относительно n через всю цепочку родителей (узлы GLB вложены, у них свой масштаб)
		var t := Transform3D.IDENTITY
		var q: Node = mi
		while q != null and q != n:
			if q is Node3D:
				t = (q as Node3D).transform * t
			q = q.get_parent()
		var a := t * mi.get_aabb()
		out = a if first else out.merge(a)
		first = false
	return out

## Свободна ли лодка (не плывёт, не тонет).
func free_for_ride() -> bool:
	return rider == null and not sinking and is_instance_valid(self)

static func storm_ok(w: Node) -> bool:
	return w == null or not w.has_method(&"storm_intensity") or float(w.call(&"storm_intensity")) < STORM_MAX

func board(who: Node3D, to: Vector3) -> void:
	rider = who
	target = to

func leave() -> void:
	rider = null
	target = Vector3.INF

## Посадка: позиция для сидящего.
func seat_pos() -> Vector3:
	return global_transform * SEAT

## Доплыли до мели у цели.
func arrived() -> bool:
	if target == Vector3.INF:
		return true
	var d := Vector2(target.x - global_position.x, target.z - global_position.z).length()
	return d < 2.5 or _shallow_ahead()

func _shallow_ahead() -> bool:
	if _world == null:
		return false
	var nose := global_transform * Vector3(0, 0, -2.6)
	var wl := float(_world.call(&"water_level"))
	return float(_world.call(&"height_at", nose.x, nose.z)) > wl - BEACH_DRAFT

func apply_damage(amount: float, _source: Node = null, _kind: StringName = &"melee") -> void:
	if sinking:
		return
	hp -= amount
	if hp <= 0.0:
		sinking = true
		_sink_t = 0.0
		if rider and rider.has_method(&"on_boat_sunk"):
			rider.call(&"on_boat_sunk", self)
		rider = null

func _physics_process(delta: float) -> void:
	if _world == null:
		_world = get_tree().get_first_node_in_group(&"world")
		if _world == null:
			return
	var p := global_position
	if sinking:
		_sink_t += delta
		global_position.y -= delta * 0.6
		rotation.z = minf(rotation.z + delta * 0.25, 0.6)
		if _sink_t > 8.0:
			queue_free()
		return
	_bob_t += delta
	var wl := float(_world.call(&"wave_height", p.x, p.z))
	var gh := float(_world.call(&"height_at", p.x, p.z))
	var floating := gh < wl - BEACH_DRAFT * 0.5
	if rider and target != Vector3.INF and not arrived():
		var to := Vector2(target.x - p.x, target.z - p.z)
		var dir := to.normalized()
		_yaw = lerp_angle(_yaw, atan2(-dir.x, -dir.y), clampf(delta * 1.2, 0.0, 1.0))
		var fwd := Vector2(-sin(_yaw), -cos(_yaw))
		p.x += fwd.x * SPEED * delta
		p.z += fwd.y * SPEED * delta
	var y := (wl - 0.05) if floating else maxf(gh, wl - 0.05) - 0.1
	p.y = lerpf(p.y, y, clampf(delta * 3.0, 0.0, 1.0))
	global_position = p
	var roll := sin(_bob_t * 1.3) * 0.04 if floating else 0.0
	var pitch := sin(_bob_t * 0.9 + 1.0) * 0.03 if floating else 0.02
	rotation = Vector3(pitch, _yaw, roll)
