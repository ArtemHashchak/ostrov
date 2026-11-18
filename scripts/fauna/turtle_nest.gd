class_name TurtleNest
extends Node3D
## Гнездо морской черепахи: холмик песка с яйцами. E — собрать яйца (turtle_egg).
## Если не собрать за hatch_seconds — вылупляются черепашата и ползут к морю.

var eggs: int = 5
var fauna: Node = null
var hatch_seconds: float = 420.0
var _t: float = 0.0
var _eggs_root: Node3D

func _ready() -> void:
	add_to_group(&"turtle_nests")
	add_to_group(&"interactable")
	var mound := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.45
	sm.height = 0.3
	sm.radial_segments = 14
	sm.rings = 6
	mound.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.82, 0.74, 0.55)
	m.roughness = 1.0
	mound.material_override = m
	mound.position.y = -0.04
	mound.scale = Vector3(1.0, 0.6, 1.0)
	add_child(mound)
	_eggs_root = Node3D.new()
	add_child(_eggs_root)
	var em := SphereMesh.new()
	em.radius = 0.035
	em.height = 0.07
	em.radial_segments = 8
	em.rings = 5
	var emat := StandardMaterial3D.new()
	emat.albedo_color = Color(0.95, 0.93, 0.86)
	emat.roughness = 0.6
	for i in eggs:
		var e := MeshInstance3D.new()
		e.mesh = em
		e.material_override = emat
		var a := TAU * i / maxf(eggs, 1)
		e.position = Vector3(cos(a) * 0.09, 0.09, sin(a) * 0.09)
		_eggs_root.add_child(e)
	var area := Area3D.new()
	area.monitoring = false
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.9, 0.35, 0.9)
	cs.shape = bs
	cs.position.y = 0.1
	area.add_child(cs)
	add_child(area)

func get_interact_text(_by: Node) -> String:
	return "E — собрать черепашьи яйца (%d)" % eggs

func interact(by: Node) -> void:
	if eggs <= 0:
		return
	var inv: Variant = by.get(&"inventory")
	if inv == null:
		return
	var left: int = (inv as Inventory).add(&"turtle_egg", eggs)
	var taken := eggs - left
	if taken > 0:
		Events.toast.emit("Черепашьи яйца +%d" % taken)
	eggs = left
	_refresh()

func _refresh() -> void:
	for i in _eggs_root.get_child_count():
		(_eggs_root.get_child(i) as Node3D).visible = i < eggs
	if eggs <= 0:
		queue_free()

func _process(dt: float) -> void:
	_t += dt
	if _t >= hatch_seconds and eggs > 0:
		if fauna and fauna.has_method(&"spawn"):
			for i in mini(eggs, 4):
				var b: Animal = fauna.call(&"spawn", &"turtle", global_position + Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4)), 30.0)
				b.set_growth(0.3)
				b.set(&"_nest_done", true)
		eggs = 0
		queue_free()
