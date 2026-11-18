class_name ItemPickup
extends RigidBody3D
## Предмет(ы) на земле: выброшенный стек или мешок с вещами погибшего.
## E — подобрать (сколько влезет). Создать: ItemPickup.spawn(parent, pos, stacks).

var stacks: Array[Dictionary] = [] # [{id, n}]
var _mesh_root: Node3D

static func spawn(parent: Node, pos: Vector3, items: Array[Dictionary], impulse: Vector3 = Vector3.ZERO) -> ItemPickup:
	var p := ItemPickup.new()
	for s in items:
		if not s.is_empty() and int(s.n) > 0:
			p.stacks.append({"id": StringName(s.id), "n": int(s.n)})
	if p.stacks.is_empty():
		p.free()
		return null
	parent.add_child(p)
	p.global_position = pos
	if impulse != Vector3.ZERO:
		p.apply_central_impulse(impulse)
	return p

func _ready() -> void:
	add_to_group(&"pickups")
	add_to_group(&"interactable")
	mass = 1.5
	angular_damp = 2.0
	linear_damp = 0.4
	continuous_cd = true
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	_mesh_root = Node3D.new()
	add_child(_mesh_root)
	if stacks.size() == 1:
		bs.size = Vector3(0.22, 0.14, 0.22)
		var m := HeldModels.build(stacks[0].id)
		m.rotation = Vector3(PI / 2.0, 0.0, 0.0) if m.get_child_count() > 0 else Vector3.ZERO
		_mesh_root.add_child(m)
		_mesh_root.position.y = -0.03
	else:
		# Мешок с вещами.
		bs.size = Vector3(0.45, 0.4, 0.45)
		var bag := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.25
		sm.height = 0.42
		bag.mesh = sm
		bag.material_override = HeldModels.pbr("Fabric004", Vector3(1.5, 1.5, 1.5), Color(0.55, 0.47, 0.35))
		_mesh_root.add_child(bag)
		var tie := MeshInstance3D.new()
		var tm := CylinderMesh.new()
		tm.top_radius = 0.03
		tm.bottom_radius = 0.07
		tm.height = 0.12
		tie.mesh = tm
		tie.material_override = bag.material_override
		tie.position.y = 0.24
		_mesh_root.add_child(tie)
	cs.shape = bs
	add_child(cs)

func get_interact_text(_by: Node) -> String:
	if stacks.size() == 1:
		var s := stacks[0]
		return "E — подобрать: %s ×%d" % [Items.item_name(s.id), int(s.n)]
	return "E — обыскать мешок (%d)" % stacks.size()

func interact(by: Node) -> void:
	var inv := by.get_node_or_null(^"Inventory") as Inventory
	if inv == null:
		return
	var got := false
	for s in stacks:
		var left := inv.add(s.id, int(s.n))
		if left < int(s.n):
			got = true
		s.n = left
	var rest: Array[Dictionary] = []
	for s in stacks:
		if int(s.n) > 0:
			rest.append(s)
	stacks = rest
	if stacks.is_empty():
		queue_free()
	elif not got:
		Events.toast.emit("Нет места в инвентаре")
