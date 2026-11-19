extends SceneTree
## Морская живность из пака → один меш с одной текстурой-атласом (для MultiMesh-групп реестра видов).
##   godot --headless --path <проект> -s res://tools/sea_atlas.gd -- <spec.json>
## spec.json — массив заданий:
##   {"src": "res://…/fish.glb", "out": "res://assets/user_pack/sea/fish.res",
##    "rotate_y": 135, "length": 0.22, "tex": 512, "tint": "#ffffff",
##    "drop": ["Material_011"], "colors": {"Material_009": "#141414"}}
## drop — материалы, выбрасываемые целиком (прозрачные/стеклянные в исходнике); colors — заменить
## текстуру материала ровным цветом; invert_alpha {"Material_014": "#e6d6c6"} — маска плавника
## в исходнике инвертирована (в Blender альфа шла через ColorRamp): альфа = 1 − альфа, цвет — заданный
## (остаются лучи, перепонка исчезает). Одинаковые текстуры делят одну ячейку атласа.
## Что делает: все поверхности всех мешей (в позе покоя, без костей) сливаются в одну;
## альбедо каждой поверхности ужимается в свою ячейку атласа (UV переносятся в ячейку, повтор UV
## сворачивается через fract); модель поворачивается лицом в −Z, центрируется и масштабируется так,
## чтобы самая длинная сторона была length. В атласе сохраняется альфа (плавники с прозрачностью).
## Результат — ArrayMesh (.res) с StandardMaterial3D (albedo = атлас) и метаданными
## before_tris/after_tris для подписей на полигоне.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var jobs: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var code := 0
	for j: Variant in jobs:
		if not _job(j as Dictionary):
			code = 1
	quit(code)


func _job(spec: Dictionary) -> bool:
	var res := load(String(spec.src))
	if res == null:
		push_error("sea_atlas: нет " + String(spec.src))
		return false
	var root: Node = (res as PackedScene).instantiate() if res is PackedScene else null
	var parts: Array = []   # [{arrays, xf, tex: Image}]
	if root:
		var stack: Array[Node] = [root]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			stack.append_array(n.get_children())
			if n is MeshInstance3D and (n as MeshInstance3D).mesh:
				var mi := n as MeshInstance3D
				var xf := _xf(mi, root)
				for s in mi.mesh.get_surface_count():
					var mat := mi.get_active_material(s)
					parts.append({"arrays": mi.mesh.surface_get_arrays(s), "xf": xf, "tex": _albedo(mat), "col": _color(mat), "name": _mname(mat)})
	elif res is Mesh:
		for s in (res as Mesh).get_surface_count():
			var mat2 := (res as Mesh).surface_get_material(s)
			parts.append({"arrays": (res as Mesh).surface_get_arrays(s), "xf": Transform3D.IDENTITY, "tex": _albedo(mat2), "col": _color(mat2), "name": _mname(mat2)})
	if parts.is_empty():
		push_error("sea_atlas: нет мешей в " + String(spec.src))
		return false
	# --- материалы: выброс (прозрачные/стеклянные в исходнике — Transparent/Glass BSDF, которые
	# glTF теряет и импорт делает белыми непрозрачными) и подмена цвета по имени материала
	var drop: Array = spec.get("drop", [])
	var recolor: Dictionary = spec.get("colors", {})
	var inv_alpha: Dictionary = spec.get("invert_alpha", {})
	var kept: Array = []
	for pt: Dictionary in parts:
		if drop.has(pt.name):
			print("sea_atlas: выброшен материал ", pt.name)
			continue
		if recolor.has(pt.name):
			pt.tex = null
			pt.col = Color(String(recolor[pt.name]))
		if inv_alpha.has(pt.name) and pt.tex != null:
			pt.tex = _invert_alpha(pt.tex, Color(String(inv_alpha[pt.name])))
		kept.append(pt)
	parts = kept
	# --- атлас: одинаковые текстуры (OBJ, где все материалы ссылаются на один файл) делят одну
	# ячейку — иначе текстура дублируется и каждая копия ужимается в разы (мыло на теле)
	var tex_max := int(spec.get("tex", 512))
	var n := parts.size()
	var cell_of: Array[int] = []
	var keys: Array = []
	var cell_src: Array = []   # [{tex|col}]
	for pt: Dictionary in parts:
		var key: Variant = _img_key(pt.tex) if pt.tex != null else str(pt.col)
		var ci := keys.find(key)
		if ci < 0:
			ci = keys.size()
			keys.append(key)
			cell_src.append(pt)
		cell_of.append(ci)
	var cells := keys.size()
	var cols := int(ceil(sqrt(float(cells))))
	var cell := maxi(16, tex_max / cols)
	var atlas := Image.create(cell * cols, cell * cols, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0.6, 0.6, 0.6, 1.0))
	for i in cells:
		var img: Image = cell_src[i].tex
		var c := Vector2i(i % cols, i / cols) * cell
		if img == null:
			var fill := Image.create(cell, cell, false, Image.FORMAT_RGBA8)
			fill.fill(cell_src[i].col)
			atlas.blit_rect(fill, Rect2i(Vector2i.ZERO, Vector2i(cell, cell)), c)
		else:
			var im := img.duplicate() as Image
			if im.is_compressed():
				im.decompress()
			im.convert(Image.FORMAT_RGBA8)
			im.resize(cell, cell, Image.INTERPOLATE_LANCZOS)
			atlas.blit_rect(im, Rect2i(Vector2i.ZERO, Vector2i(cell, cell)), c)
	# --- геометрия в одну поверхность
	var rot := Basis(Vector3.UP, deg_to_rad(float(spec.get("rotate_y", 0.0))))
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var before := 0
	var inset := 1.0 / float(cell)   # полпикселя от края ячейки
	for i in n:
		var a: Array = parts[i].arrays
		var xf: Transform3D = parts[i].xf
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var nr: PackedVector3Array = a[Mesh.ARRAY_NORMAL] if a[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV] if a[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if ix.is_empty():
			ix.resize(v.size())
			for k in v.size():
				ix[k] = k
		before += ix.size() / 3
		var base := verts.size()
		var org := Vector2(cell_of[i] % cols, cell_of[i] / cols) / float(cols)
		for k in v.size():
			verts.append(rot * (xf * v[k]))
			norms.append((rot * (xf.basis * (nr[k] if k < nr.size() else Vector3.UP))).normalized())
			var t := uv[k] if k < uv.size() else Vector2(0.5, 0.5)
			t = Vector2(fposmod(t.x, 1.0), fposmod(t.y, 1.0))
			t = t * (1.0 - 2.0 * inset) + Vector2(inset, inset)
			uvs.append(org + t / float(cols))
		for k in ix:
			idx.append(base + k)
	# центр и масштаб
	var aabb := AABB(verts[0], Vector3.ZERO)
	for p in verts:
		aabb = aabb.expand(p)
	var L := float(spec.get("length", 0.0))
	var sc := L / maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z)) if L > 0.0 else 1.0
	var ctr := aabb.get_center()
	for k in verts.size():
		verts[k] = (verts[k] - ctr) * sc
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	atlas.generate_mipmaps()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(atlas)
	mat.albedo_color = Color(String(spec.get("tint", "#ffffff")))
	mat.alpha_scissor_threshold = 0.4
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	mesh.set_meta(&"after_tris", idx.size() / 3)
	mesh.set_meta(&"atlas_cells", cells)
	mesh.set_meta(&"before_tris", int(spec.get("before_tris", before)))
	var err := ResourceSaver.save(mesh, String(spec.out), ResourceSaver.FLAG_COMPRESS)
	print("sea_atlas: %s → %s, %d треуг., атлас %d×%d (%d ячеек на %d частей), err=%d" % [spec.src, spec.out, idx.size() / 3, atlas.get_width(), atlas.get_height(), cells, n, err])
	if root:
		root.free()
	return err == OK


func _xf(n: Node, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur := n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	if root is Node3D:
		xf = (root as Node3D).transform * xf
	return xf


func _albedo(mat: Material) -> Image:
	if mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture:
		return (mat as BaseMaterial3D).albedo_texture.get_image()
	return null


func _color(mat: Material) -> Color:
	if mat is BaseMaterial3D:
		return (mat as BaseMaterial3D).albedo_color
	return Color(0.7, 0.7, 0.7)


func _mname(mat: Material) -> String:
	return mat.resource_name if mat else ""


## Ключ «одинаковости» текстуры: сравниваем уменьшенную несжатую копию (одна и та же картинка
## после импорта может прийти в разных форматах/с мипмапами).
func _img_key(img: Image) -> String:
	var im := img.duplicate() as Image
	if im.is_compressed():
		im.decompress()
	im.clear_mipmaps()
	im.convert(Image.FORMAT_RGBA8)
	im.resize(32, 32, Image.INTERPOLATE_BILINEAR)
	return "%dx%d:%s" % [img.get_width(), img.get_height(), im.get_data().hex_encode().md5_text()]


func _invert_alpha(src: Image, col: Color) -> Image:
	var im := src.duplicate() as Image
	if im.is_compressed():
		im.decompress()
	im.clear_mipmaps()
	im.convert(Image.FORMAT_RGBA8)
	for y in im.get_height():
		for x in im.get_width():
			var a := 1.0 - im.get_pixel(x, y).a
			im.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	return im
