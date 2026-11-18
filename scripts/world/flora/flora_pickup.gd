class_name FloraPickup
extends RigidBody3D
## Мелкий подбираемый предмет на земле: палка, камень, кокос. E — подобрать.

var item_id: StringName = &"stick"
var count: int = 1

static func _make(id: StringName, mesh: Mesh, shape: Shape3D, m: float) -> FloraPickup:
	var p := FloraPickup.new()
	p.item_id = id
	p.mass = m
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.visibility_range_end = 70.0
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

func get_interact_text(_player: Node) -> String:
	return "E — подобрать: %s" % Items.item_name(item_id).to_lower()

func interact(player: Node) -> void:
	Flora.give(player, item_id, count)
	Flora.play_sfx(self, "OBJBag_KnapsackLeatherClose_OS_01", global_position, -8.0, 1.2)
	queue_free()
