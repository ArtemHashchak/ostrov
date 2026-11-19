class_name MeshOptimizer
extends RefCounted
## Подготовка тяжёлых мешей во время игры: слияние поверхностей с одним
## материалом в одну (меньше вызовов отрисовки) и автоматические LOD
## (ImporterMesh.generate_lods) — для мешей, импортированных без них (OBJ).
## Результат кэшируется по ключу.

static var _cache: Dictionary = {}

## Все поверхности → одна (материал задаётся material_override), плюс LOD.
static func merged_with_lods(key: String, mesh: Mesh) -> Mesh:
	if mesh == null:
		return null
	if _cache.has(key):
		return _cache[key]
	var out: Mesh = mesh
	var st := SurfaceTool.new()
	var ok := false
	for s in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			ok = false
			break
		st.append_from(mesh, s, Transform3D.IDENTITY)
		ok = true
	if ok:
		st.index()
		var arrays := st.commit_to_arrays()
		var im := ImporterMesh.new()
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
		im.generate_lods(60.0, 25.0, [])
		var am := im.get_mesh()
		if am and am.get_surface_count() == 1:
			out = am
	_cache[key] = out
	return out

## Как merged_with_lods, но базовый (ближний) уровень не тяжелее max_tris:
## берётся первый автоматический LOD, уложившийся в бюджет, и на нём заново строятся LOD.
## Для тяжёлых сканов (полихейвен ~15–30k треуг.), которые в игре — мелкий реквизит.
static func decimated(key: String, mesh: Mesh, max_tris: int) -> Mesh:
	var ck := "%s|dec%d" % [key, max_tris]
	if _cache.has(ck):
		return _cache[ck]
	var merged := merged_with_lods(key, mesh)
	var out: Mesh = merged
	if merged is ArrayMesh and merged.get_surface_count() == 1:
		var arrays := (merged as ArrayMesh).surface_get_arrays(0)
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.size() / 3 > max_tris:
			var im := ImporterMesh.new()
			im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
			im.generate_lods(25.0, 60.0, [])
			var best := PackedInt32Array()
			for l in im.get_surface_lod_count(0):
				var li := im.get_surface_lod_indices(0, l)
				best = li
				if li.size() / 3 <= max_tris:
					break
			if best.size() >= 3 and best.size() < idx.size():
				var a2 := arrays.duplicate()
				a2[Mesh.ARRAY_INDEX] = best
				var im2 := ImporterMesh.new()
				im2.add_surface(Mesh.PRIMITIVE_TRIANGLES, a2)
				im2.generate_lods(60.0, 25.0, [])
				var am := im2.get_mesh()
				if am and am.get_surface_count() == 1:
					out = am
	_cache[ck] = out
	return out

static func clear_cache() -> void:
	_cache.clear()
