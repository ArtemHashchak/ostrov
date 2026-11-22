extends SceneTree
## Импорт растений из пака пользователя (MODELS/Tree, MODELS/Plants) в игровые меши FLORA.
## Запуск (исходники распакованы во временную папку, в репозиторий не попадают):
##   godot --headless --path . -s res://tools/flora_pack_import.gd -- <manifest.json>
## manifest: [{group: "tree"|"plant"|"coconut", id, files: [lod_a, lod_b]}] — пути к .gltf/.glb.
## Результат: assets/user_pack/flora/mesh/<id>_l<k>.res (поверхности сгруппированы по материалу,
## имя поверхности = имя материала пака; материалы назначает FloraPack по имени) и
## assets/user_pack/flora/flora_pack.json — размеры, ось ствола, точка вершины ствола.
## Узлы-коллайдеры автора (*convcolonly) в меш не идут. Пальмы поворачиваются так, чтобы
## наклон ствола шёл вдоль +X (как у процедурных: Flora клонит их к морю поворотом по Y).

const OUT := "res://assets/user_pack/flora/"

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var man: Array = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "mesh"))
	var meta := {}
	var old := FileAccess.get_file_as_string(OUT + "flora_pack.json")
	if old != "":
		meta = JSON.parse_string(old)
	for e in man:
		var id: String = e["id"]
		var files: Array = e["files"]
		var info := {"group": e["group"], "lods": files.size()}
		var yaw := 0.0
		for k in files.size():
			var parts := _load(files[k])
			if parts.is_empty():
				push_error("пусто: " + files[k])
				continue
			if k == 0 and e["group"] == "tree" and id.begins_with("palm"):
				yaw = _lean_yaw(parts)
			var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO)
			var mesh := _merge(parts, xf)
			var path := OUT + "mesh/%s_l%d.res" % [id, k + 1]
			var err := ResourceSaver.save(mesh, path, ResourceSaver.FLAG_COMPRESS)
			if err != OK:
				push_error("save %s: %d" % [path, err])
			var tris := 0
			for si in mesh.get_surface_count():
				tris += mesh.surface_get_array_index_len(si) / 3
			info["tris_l%d" % (k + 1)] = tris
			if k == 0:
				var cols: Array = []
				for p in parts:
					if p[3]:
						var pts := PackedVector3Array()
						var m: Mesh = p[0]
						for si in m.get_surface_count():
							for q in (m.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
								pts.append(xf * (p[1] as Transform3D) * q)
						cols.append([p[2], _hull(pts)])
				_measure(info, mesh, cols, id.begins_with("palm"))
		meta[id] = info
		print(id, " ", info)
	var f := FileAccess.open(OUT + "flora_pack.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t", true))
	f.close()
	quit()

## [[Mesh, Transform3D (глобальный), имя узла]] без коллайдеров.
func _load(path: String) -> Array:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(path, st) != OK:
		return []
	var root := doc.generate_scene(st)
	var out: Array = []
	_collect(root, Transform3D.IDENTITY, out)
	root.free()
	return out

func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	var x := xf
	if n is Node3D:
		x = xf * (n as Node3D).transform
	if n is MeshInstance3D:
		var col := String(n.name).contains("convcolonly")
		out.append([(n as MeshInstance3D).mesh, x, String(n.name), col])
	for c in n.get_children():
		_collect(c, x, out)

## Направление наклона ствола (вершина ствола относительно основания) → угол поворота к +X.
func _lean_yaw(parts: Array) -> float:
	var top := Vector3.ZERO
	var best := -1e9
	for p in parts:
		if p[3]:
			continue
		var m: Mesh = p[0]
		for si in m.get_surface_count():
			if not _mat_name(m, si).to_lower().contains("bark"):
				continue
			var vs: PackedVector3Array = m.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			for v in vs:
				var w: Vector3 = p[1] * v
				if w.y > best:
					best = w.y
					top = w
	return atan2(top.z, top.x)   # Basis(UP, a): (cos a, 0, -sin a) → +X

func _mat_name(m: Mesh, si: int) -> String:
	var mt := m.surface_get_material(si)
	var nm := mt.resource_name if mt else ""
	if nm == "" and m is ArrayMesh:
		nm = (m as ArrayMesh).surface_get_name(si)
	return nm

func _merge(parts: Array, rot: Transform3D) -> ArrayMesh:
	var groups := {}   # имя материала -> SurfaceTool
	for p in parts:
		if p[3]:
			continue
		var m: Mesh = p[0]
		for si in m.get_surface_count():
			var nm := _mat_name(m, si)
			if nm == "":
				nm = "Leaf"
			if not groups.has(nm):
				var st0 := SurfaceTool.new()
				groups[nm] = st0
			(groups[nm] as SurfaceTool).append_from(m, si, rot * (p[1] as Transform3D))
	var out := ArrayMesh.new()
	var names := groups.keys()
	names.sort()
	# кора первой: тень/LOD-логика FloraPack опирается на порядок (кора, листва)
	names.sort_custom(func(a, b): return int(String(a).to_lower().contains("bark")) > int(String(b).to_lower().contains("bark")))
	# автоматические LOD движка (meshoptimizer) запекаются здесь: в игре меш выбирает
	# упрощённые индексы по экранной ошибке (дальние чанки MultiMesh), без работы при загрузке
	var im := ImporterMesh.new()
	for nm in names:
		var st: SurfaceTool = groups[nm]
		st.index()
		st.generate_tangents()
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays(), [], {}, null, nm, Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
	im.generate_lods(25.0, 60.0, [])
	out = im.get_mesh()
	for si in out.get_surface_count():
		out.surface_set_name(si, names[si])
	return out

## Размеры: AABB, крона (листва), ось ствола — трассировка трубы коры от основания шагом 0.4 м
## по длине дуги (наклонные и изогнутые пальмы тоже), профиль радиуса; трассировка
## останавливается на развилке (радиус «кольца» резко растёт) — это начало кроны: H = длина дуги.
## cols — выпуклые коллайдеры автора (точки) для ствола; корни (*rootscol*) не берём.
func _measure(info: Dictionary, mesh: ArrayMesh, cols: Array, tube: bool = false) -> void:
	info["aabb"] = _a(mesh.get_aabb())
	var bark := PackedVector3Array()
	var leaf := AABB()
	var has_leaf := false
	for si in mesh.get_surface_count():
		var vs: PackedVector3Array = mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
		if mesh.surface_get_name(si).to_lower().contains("bark"):
			bark.append_array(vs)
		else:
			for v in vs:
				if has_leaf:
					leaf = leaf.expand(v)
				else:
					leaf = AABB(v, Vector3.ZERO)
					has_leaf = true
	if has_leaf:
		info["leaf_aabb"] = _a(leaf)
	var hulls: Array = []
	for c in cols:
		if String(c[0]).contains("roots"):
			continue
		var flat: Array = []
		for q in (c[1] as PackedVector3Array):
			flat.append_array([snappedf(q.x, 0.01), snappedf(q.y, 0.01), snappedf(q.z, 0.01)])
		hulls.append(flat)
	info["cols"] = hulls
	if bark.is_empty():
		return
	# основание: кора ниже 0.5 м ближе 0.8 м к центру нижнего коллайдера (у мангров — ствол среди корней)
	var c0 := Vector3.ZERO
	var best := 1e9
	for c in cols:
		if String(c[0]).contains("roots"):
			continue
		var ab := AABB((c[1] as PackedVector3Array)[0], Vector3.ZERO)
		for q in (c[1] as PackedVector3Array):
			ab = ab.expand(q)
		if ab.position.y < 0.3 and ab.size.x * ab.size.z < best:
			best = ab.size.x * ab.size.z
			c0 = Vector3(ab.get_center().x, 0.0, ab.get_center().z)
	# центр коры у земли (около найденной точки): у пальм коллайдер наклонный — его центр в стороне
	var acc := Vector3.ZERO
	var n := 0
	for v in bark:
		if v.y < 0.35 and Vector2(v.x - c0.x, v.z - c0.z).length() < 0.9:
			acc += v
			n += 1
	if n == 0:
		for v in bark:
			if v.y < 0.35 and Vector2(v.x, v.z).length() < 0.9:
				acc += v
				n += 1
	if n > 0:
		c0 = Vector3(acc.x / n, 0.0, acc.z / n)
	var p := c0
	var dir := Vector3.UP
	var axis: Array = [[snappedf(p.x, 0.01), 0.0, snappedf(p.z, 0.01)]]
	var radius: Array = []
	var step := 0.4
	var r_ref := -1.0
	for it in 80:
		var q := p + dir * step
		var sel: Array = []
		for v in bark:
			var d := v - q
			var along := d.dot(dir)
			if absf(along) < step * 0.9 and (d - dir * along).length() < 0.9:
				sel.append(v - dir * along)
		if sel.size() < 4:
			break
		var cen := Vector3.ZERO
		for v in sel:
			cen += v
		cen /= float(sel.size())
		var rs: Array = sel.map(func(v): return (v as Vector3).distance_to(cen))
		rs.sort()
		var r: float = rs[rs.size() / 2]
		if r_ref < 0.0 and radius.size() >= 2:
			r_ref = radius[1]
		if r_ref > 0.0 and r > r_ref * (3.5 if tube else 2.2) and it > 2:
			break   # развилка / основание кроны
		var nd := (cen - p).normalized()
		if nd.dot(dir) < (-0.1 if tube else 0.3):
			break
		dir = (dir * (0.3 if tube else 1.0) + nd).normalized()
		# не пальма: ствол кончается у нижней листвы (выше — развилка; крона падает целиком)
		if not tube and has_leaf and cen.y > maxf(leaf.position.y + 0.3, 1.0):
			p = cen
			axis.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)])
			radius.append(snappedf(r, 0.01))
			break
		p = cen
		axis.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)])
		radius.append(snappedf(r, 0.01))
	radius.insert(0, radius[0] if radius.size() > 0 else 0.2)
	# хвост: листовые черешки/сапоги у макушки — радиус вне [0.5, 2.2] медианы
	var srt := radius.duplicate()
	srt.sort()
	var med: float = srt[srt.size() / 2]
	while axis.size() > 3 and (float(radius[-1]) < med * 0.5 or float(radius[-1]) > med * 2.2):
		axis.pop_back()
		radius.pop_back()
	info["axis"] = axis
	info["radius"] = radius
	info["H"] = snappedf(step * float(axis.size() - 1), 0.01)
	info["trunk_top"] = mesh.get_aabb().end.y
	info["crown_y"] = axis[-1][1]

## Точки выпуклой оболочки (ConvexPolygonShape3D сам строит оболочку; уменьшаем повторы).
func _hull(pts: PackedVector3Array) -> PackedVector3Array:
	var seen := {}
	var out := PackedVector3Array()
	for q in pts:
		var k := Vector3i(roundi(q.x * 50.0), roundi(q.y * 50.0), roundi(q.z * 50.0))
		if not seen.has(k):
			seen[k] = true
			out.append(q)
	return out

func _a(b: AABB) -> Array:
	return [b.position.x, b.position.y, b.position.z, b.size.x, b.size.y, b.size.z]
