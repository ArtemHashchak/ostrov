extends SceneTree
## Зонд: настоящая длина скинованного меша (кости × bind) против габарита узлов.
func _init() -> void:
	var ps := load("res://assets/user_pack/sea_skel/animal_fish_tuna.glb") as PackedScene
	var root := ps.instantiate()
	get_root().add_child(root)
	await process_frame
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var sk := mi.get_node_or_null(mi.skeleton) as Skeleton3D
		var arr := mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var nb := bones.size() / verts.size()
		var lo := Vector3.INF
		var hi := -Vector3.INF
		for i in range(0, verts.size(), 7):
			var acc := Vector3.ZERO
			for k in nb:
				var w := wts[i * nb + k]
				if w <= 0.0:
					continue
				var b := bones[i * nb + k]
				var bi := b
				if mi.skin:
					bi = sk.find_bone(mi.skin.get_bind_name(b)) if mi.skin.get_bind_name(b) != &"" else mi.skin.get_bind_bone(b)
					acc += w * (sk.global_transform * sk.get_bone_global_pose(bi) * mi.skin.get_bind_pose(b) * verts[i])
			lo = lo.min(acc)
			hi = hi.max(acc)
		print("skinned size ", hi - lo, "  node aabb ", (mi.global_transform * mi.get_aabb()).size, " mi.scale ", mi.global_transform.basis.get_scale(), " sk.scale ", sk.global_transform.basis.get_scale())
	quit()
