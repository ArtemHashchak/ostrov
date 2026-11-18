class_name FloraLog
extends RigidBody3D
## Бревно (группа `log`): лежит физически, переносится на плече (как в The Forest).
## E — поднять; E при бревне на плече — взять второе (до 2), E в никуда — положить.
## Для стройки: `consume_one(player)` — снять одно несомое бревно (BUILD вызывает из accept_log).

const MAX_CARRY := 2

var length: float = 2.0
var radius: float = 0.2
var carrier: Node = null
var stack: Array[FloraLog] = []
var _mesh: Mesh = null
var _shape: Shape3D = null
var _shape_xform: Transform3D = Transform3D.IDENTITY
var _spawn_global: Transform3D = Transform3D.IDENTITY
var _has_spawn: bool = false

## Бревно из участка ствола [h0,h1] дерева variant; xform — глобальная трансформа ствола.
static func from_segment(v: Dictionary, h0: float, h1: float, xform: Transform3D) -> FloraLog:
	var lg := FloraLog.new()
	var a := FloraLib.trunk_point(v, h0)
	var b := FloraLib.trunk_point(v, h1)
	var mid := (a + b) * 0.5
	lg._mesh = FloraLib.trunk_mesh(v, h0, h1, 3, 12, mid)
	lg.radius = maxf(FloraLib.trunk_radius(v, h0), FloraLib.trunk_radius(v, h1)) # по толстому торцу — не тонет в земле
	lg.length = a.distance_to(b)
	var cap := CapsuleShape3D.new()
	cap.radius = lg.radius
	cap.height = maxf(lg.length + lg.radius * 0.5, lg.radius * 2.1)
	lg._shape = cap
	var y := (b - a).normalized()
	var x := y.cross(Vector3.FORWARD).normalized()
	if x.length() < 0.5:
		x = Vector3.RIGHT
	lg._shape_xform = Transform3D(Basis(x, y, x.cross(y).normalized()), Vector3.ZERO)
	lg._spawn_global = Transform3D(xform.basis, xform * mid)
	lg._has_spawn = true
	return lg

func _ready() -> void:
	add_to_group(&"log")
	if _has_spawn:
		global_transform = _spawn_global
	mass = 25.0 + 40.0 * length * radius
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.visibility_range_end = 180.0
	add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = _shape
	cs.transform = _shape_xform
	add_child(cs)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.95
	physics_material_override = pm
	angular_damp = 1.0
	can_sleep = true

func get_interact_text(player: Node) -> String:
	if carrier == player:
		return "E — положить брёвна (%d)" % carried_count() if stack.size() > 0 else "E — положить бревно"
	if carrier != null:
		return ""
	var carried: Node = player.get(&"carried_object")
	if bool(player.get(&"carrying_log")):
		if carried is FloraLog and (carried as FloraLog).carried_count() < MAX_CARRY:
			return "E — взять ещё бревно"
		return ""
	return "E — поднять бревно"

func interact(player: Node) -> void:
	if carrier == player:
		drop(player)
		return
	if carrier != null:
		return
	var carried: Node = player.get(&"carried_object")
	if bool(player.get(&"carrying_log")):
		if carried is FloraLog and (carried as FloraLog).carried_count() < MAX_CARRY:
			(carried as FloraLog)._stack_add(self)
		return
	carrier = player
	_hide()
	player.call(&"set_carrying_log", true, self)
	Flora.play_sfx(self, "WOODFric_LargeWoodMetalDrag_OS_01", global_position, -10.0, 1.4)

func _stack_add(l: FloraLog) -> void:
	l.carrier = carrier
	l._hide()
	stack.append(l)
	Events.toast.emit("Брёвен на плече: %d" % carried_count())

func carried_count() -> int:
	return 1 + stack.size()

func drop(player: Node) -> void:
	var p := player as Node3D
	var fwd: Vector3 = player.call(&"get_look_dir") if player.has_method(&"get_look_dir") else -p.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP)
	var all: Array[FloraLog] = [self]
	all.append_array(stack)
	var at := p.global_position + fwd * 1.7
	var ground := at.y
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3.0, at + Vector3.DOWN * 4.0)
	var ex: Array[RID] = []
	if p is CollisionObject3D:
		ex.append((p as CollisionObject3D).get_rid())
	for l2 in all:
		ex.append(l2.get_rid())
	q.exclude = ex
	var hit := p.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		ground = (hit["position"] as Vector3).y
	for i in all.size():
		var l := all[i]
		l.carrier = null
		l.global_transform = Transform3D(Basis.looking_at(side, Vector3.UP) * Basis(Vector3.RIGHT, PI / 2.0),
			Vector3(at.x, ground + l.radius + 0.12 + (l.radius * 2.0 + 0.05) * i, at.z))
		l._show()
	stack.clear()
	player.call(&"set_carrying_log", false)
	Flora.play_sfx(self, "WOODImpt_LargeWoodDrop_OS_01", global_position, -8.0, 1.2)

## Для стройки: снять одно несомое бревно. true — бревно израсходовано.
func consume_one(player: Node) -> bool:
	if carrier != player:
		return false
	if not stack.is_empty():
		var l: FloraLog = stack.pop_back()
		l.queue_free()
		return true
	carrier = null
	player.call(&"set_carrying_log", false)
	queue_free()
	return true

func _hide() -> void:
	visible = false
	freeze = true
	collision_layer = 0
	collision_mask = 0

func _show() -> void:
	visible = true
	collision_layer = 1
	collision_mask = 1
	freeze = false
	sleeping = false
