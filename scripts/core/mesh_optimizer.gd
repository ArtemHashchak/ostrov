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

static func clear_cache() -> void:
	_cache.clear()
