extends SceneTree
## Меш с разметкой для процедурной анимации вблизи: CUSTOM0/CUSTOM1 (RGBA float) из JSON
## tools/folder_anim/seg_rig.py. Запуск:
##   godot --headless --path . --script tools/folder_anim/build_rig_mesh.gd -- <src.res> <seg.json> <dst.res>
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var src: Mesh = load(a[0])
	var seg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(a[1]))
	var arr := src.surface_get_arrays(0)
	var n: int = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var c0 := PackedFloat32Array(); c0.resize(n * 4)
	var c1 := PackedFloat32Array(); c1.resize(n * 4)
	for i in n:
		for k in 4:
			c0[i * 4 + k] = float(seg.c0[i][k])
			c1[i * 4 + k] = float(seg.c1[i][k])
	arr[Mesh.ARRAY_CUSTOM0] = c0
	arr[Mesh.ARRAY_CUSTOM1] = c1
	var fmt := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, fmt)
	m.surface_set_material(0, src.surface_get_material(0))
	m.set_meta(&"rig", seg.get("report", {}))
	var err := ResourceSaver.save(m, a[2], ResourceSaver.FLAG_COMPRESS)
	print("saved ", a[2], " err=", err, " verts=", n)
	quit()
