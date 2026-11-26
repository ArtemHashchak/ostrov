class_name TrailCanopy
extends Node3D
## Низкий полог над звериными тропами в густых джунглях: невидимые плиты-коллизии
## на высоте TrailNet.CANOPY над землёй — стоя под ними не пройти, пригнувшись
## (рост в приседе 1,15 м) — можно. Создаются только у игроков (≈30 м), пулом.
## Прорубленные проходы (kind &"cut") полога не имеют — там идёшь в полный рост.

const RADIUS := 30.0
const MIN_JUNGLE := 0.45
const TICK := 0.4

var net: TrailNet
var world: Node
var _pool: Array[StaticBody3D] = []
var _used := 0
var _t := 0.0

func setup(w: Node, n: TrailNet) -> void:
	world = w
	net = n
	name = "TrailCanopy"

func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0 or net == null:
		return
	_t = TICK
	_used = 0
	for pl in get_tree().get_nodes_in_group(&"player"):
		if pl is Node3D:
			var p := (pl as Node3D).global_position
			for seg in net.segments_near(Vector2(p.x, p.z), RADIUS):
				if seg[2] != &"animal":
					continue
				_place(seg[0], seg[1])
	for i in range(_used, _pool.size()):
		_pool[i].process_mode = Node.PROCESS_MODE_DISABLED
		(_pool[i].get_child(0) as CollisionShape3D).disabled = true

func _place(a: Vector2, b: Vector2) -> void:
	var m := (a + b) * 0.5
	if float(world.call(&"jungle_density", m.x, m.y)) < MIN_JUNGLE:
		return
	var body: StaticBody3D
	if _used < _pool.size():
		body = _pool[_used]
	else:
		body = StaticBody3D.new()
		body.name = "Canopy%d" % _pool.size()
		body.add_to_group(&"trail_canopy")
		var cs := CollisionShape3D.new()
		cs.shape = BoxShape3D.new()
		body.add_child(cs)
		add_child(body)
		_pool.append(body)
	_used += 1
	var cs := body.get_child(0) as CollisionShape3D
	cs.disabled = false
	body.process_mode = Node.PROCESS_MODE_INHERIT
	var len := a.distance_to(b) + 0.3
	(cs.shape as BoxShape3D).size = Vector3(1.6, 0.4, len)
	var ga := float(world.call(&"height_at", a.x, a.y))
	var gb := float(world.call(&"height_at", b.x, b.y))
	var y := maxf(ga, gb) + TrailNet.CANOPY + 0.2
	var dir := (b - a).normalized()
	body.global_transform = Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.y)), Vector3(m.x, y, m.y))
