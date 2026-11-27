extends SceneTree
## Ось кита: в whale_humpback.res длинная ось шла по Y (кит «вертикальный», носом вниз).
## Поворот (x,y,z) → (-x, z, y): голова (−Y) → −Z (вперёд, как "forward": "-z"), спина (+Z) → +Y. det = +1.
const P := "res://assets/user_pack/sea/whale_humpback.res"
func _r(p: Vector3) -> Vector3:
	return Vector3(-p.x, p.z, p.y)
func _init():
	var m: ArrayMesh = load(P)
	var out := ArrayMesh.new()
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		for i in v.size():
			v[i] = _r(v[i])
		a[Mesh.ARRAY_VERTEX] = v
		if a[Mesh.ARRAY_NORMAL] != null:
			var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			for i in n.size():
				n[i] = _r(n[i])
			a[Mesh.ARRAY_NORMAL] = n
		if a[Mesh.ARRAY_TANGENT] != null:
			var t: PackedFloat32Array = a[Mesh.ARRAY_TANGENT]
			for i in range(0, t.size(), 4):
				var r := _r(Vector3(t[i], t[i + 1], t[i + 2]))
				t[i] = r.x; t[i + 1] = r.y; t[i + 2] = r.z
			a[Mesh.ARRAY_TANGENT] = t
		out.add_surface_from_arrays(m.surface_get_primitive_type(s), a)
		out.surface_set_material(s, m.surface_get_material(s))
		out.surface_set_name(s, m.surface_get_name(s))
	print("before ", m.get_aabb(), " after ", out.get_aabb())
	ResourceSaver.save(out, P, ResourceSaver.FLAG_COMPRESS)
	quit()
