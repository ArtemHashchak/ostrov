class_name StaticBatch
## Слияние статичных мешей модели в один меш на материал (меньше вызовов отрисовки).
## Модели из примитивов (травы, ягодники, мусор) состоят из 5–15 мелких MeshInstance3D —
## после слияния это 1–3 вызова. Не-меш узлы (частицы, свет, звук) остаются как есть.
## Поддерживаются треугольные поверхности без скелета; иначе узел не трогаем.

const _KEEP := [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV]

## Сливает все MeshInstance3D-потомки root (кроме помеченных метой "no_batch") в
## общие меши, по одному на (материал, тени). Возвращает число убранных узлов.
static func bake(root: Node3D) -> int:
	var parts: Array[MeshInstance3D] = []
	_collect(root, parts)
	if parts.size() < 2:
		return 0
	var inv := root.global_transform.affine_inverse() if root.is_inside_tree() else Transform3D.IDENTITY
	var buckets := {}   # key -> {mat, shadow, v, n, t, c, uv, idx, has_c, has_t}
	for mi in parts:
		var xf := (inv * mi.global_transform) if root.is_inside_tree() else _rel(root, mi)
		var mesh := mi.mesh
		for s in mesh.get_surface_count():
			if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				return 0
			var mat: Material = mi.material_override
			if mat == null:
				mat = mi.get_surface_override_material(s)
			if mat == null:
				mat = mesh.surface_get_material(s)
			var key := "%d_%d" % [mat.get_instance_id() if mat else 0, mi.cast_shadow]
			if not buckets.has(key):
				buckets[key] = {"mat": mat, "shadow": mi.cast_shadow, "v": PackedVector3Array(), "n": PackedVector3Array(),
					"t": PackedFloat32Array(), "c": PackedColorArray(), "uv": PackedVector2Array(), "idx": PackedInt32Array()}
			var b: Dictionary = buckets[key]
			var a: Array = mesh.surface_get_arrays(s)
			if a[Mesh.ARRAY_BONES] != null or a[Mesh.ARRAY_VERTEX] == null:
				return 0
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var cnt := v.size()
			var base: int = (b.v as PackedVector3Array).size()
			var basis := xf.basis
			var nbasis := basis.inverse().transposed()
			for p in v:
				b.v.append(xf * p)
			var nrm = a[Mesh.ARRAY_NORMAL]
			for i in cnt:
				b.n.append((nbasis * (nrm[i] as Vector3)).normalized() if nrm != null else Vector3.UP)
			var tan = a[Mesh.ARRAY_TANGENT]
			for i in cnt:
				if tan != null:
					var tv := (basis * Vector3(tan[i * 4], tan[i * 4 + 1], tan[i * 4 + 2])).normalized()
					b.t.append_array(PackedFloat32Array([tv.x, tv.y, tv.z, tan[i * 4 + 3]]))
				else:
					b.t.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 1.0]))
			var col = a[Mesh.ARRAY_COLOR]
			for i in cnt:
				b.c.append(col[i] if col != null else Color.WHITE)
			var uv = a[Mesh.ARRAY_TEX_UV]
			for i in cnt:
				b.uv.append(uv[i] if uv != null else Vector2.ZERO)
			var idx = a[Mesh.ARRAY_INDEX]
			if idx != null:
				for i in idx:
					b.idx.append(base + int(i))
			else:
				for i in cnt:
					b.idx.append(base + i)
	# собираем: один MeshInstance3D на ведро
	var removed := 0
	for mi in parts:
		mi.get_parent().remove_child(mi)
		mi.queue_free()
		removed += 1
	for key in buckets:
		var b: Dictionary = buckets[key]
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = b.v
		arr[Mesh.ARRAY_NORMAL] = b.n
		arr[Mesh.ARRAY_TANGENT] = b.t
		arr[Mesh.ARRAY_COLOR] = b.c
		arr[Mesh.ARRAY_TEX_UV] = b.uv
		arr[Mesh.ARRAY_INDEX] = b.idx
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		if b.mat:
			am.surface_set_material(0, b.mat)
		var out := MeshInstance3D.new()
		out.name = "Batched"
		out.mesh = am
		out.cast_shadow = b.shadow
		root.add_child(out)
		removed -= 1
	return removed

static var _cache := {}

## Модель по ключу: строится builder'ом один раз, сливается и дальше отдаётся копией
## (копии делят ArrayMesh — память и время загрузки не растут с числом объектов).
static func cached(key: String, builder: Callable) -> Node3D:
	var tpl: Node3D = _cache.get(key)
	if tpl == null:
		tpl = builder.call()
		bake(tpl)
		_cache[key] = tpl
	return tpl.duplicate() as Node3D

static func clear_cache() -> void:
	for k in _cache:
		var n: Node3D = _cache[k]
		if is_instance_valid(n):
			n.free()
	_cache.clear()

static func _collect(n: Node, out: Array[MeshInstance3D]) -> void:
	for c in n.get_children():
		if c.has_meta(&"no_batch"):
			continue
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null \
				and c.get_child_count() == 0 and (c as MeshInstance3D).visible:
			out.append(c)
		else:
			_collect(c, out)

static func _rel(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf
