class_name SurvivalModels
extends RefCounted
## Модели и материалы SURVIVAL: ассеты (Poly Haven, Khronos) + процедурные меши.
## Всё кэшируется. Корень каждой модели стоит на земле (y=0).

const TEX := "res://assets/textures/"
const PH := "res://assets/models/polyhaven/"
const OBJ := "res://assets/models/polyhaven_obj/"
const OBJ_TRIS := 3500

static var _mats: Dictionary = {}
static var _meshes: Dictionary = {}
static var _scenes: Dictionary = {}

## Сбросить кэши материалов/мешей (при выходе — иначе движок пишет об утечках).
static func clear_cache() -> void:
	_mats.clear()
	_meshes.clear()
	_scenes.clear()

# ============================================================ материалы

static func pbr(set_name: String, uv: Vector3 = Vector3.ONE, tint: Color = Color.WHITE) -> StandardMaterial3D:
	var key := "pbr|%s|%s|%s" % [set_name, uv, tint]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	var a := _t(set_name, "albedo")
	if a:
		m.albedo_texture = a
	m.albedo_color = tint
	var n := _t(set_name, "normal")
	if n:
		m.normal_enabled = true
		m.normal_texture = n
	var r := _t(set_name, "roughness")
	if r:
		m.roughness_texture = r
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	var ao := _t(set_name, "ao")
	if ao:
		m.ao_enabled = true
		m.ao_texture = ao
	m.uv1_scale = uv
	_mats[key] = m
	return m

static func _t(set_name: String, kind: String) -> Texture2D:
	var p := "%s%s/%s_%s.png" % [TEX, set_name, set_name, kind]
	return load(p) as Texture2D if ResourceLoader.exists(p) else null

static func color(c: Color, rough: float = 0.8, metal: float = 0.0) -> StandardMaterial3D:
	var key := "col|%s|%s|%s" % [c, rough, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if c.a < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m

## Ржавая жесть: шум ржавчины поверх тёмного металла.
static func rust() -> StandardMaterial3D:
	if _mats.has("rust"):
		return _mats["rust"]
	var m := StandardMaterial3D.new()
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	var fn := FastNoiseLite.new()
	fn.frequency = 0.03
	fn.fractal_octaves = 5
	nt.noise = fn
	var g := Gradient.new()
	g.set_color(0, Color(0.22, 0.2, 0.19))
	g.set_color(1, Color(0.55, 0.26, 0.1))
	g.add_point(0.45, Color(0.33, 0.24, 0.18))
	g.add_point(0.62, Color(0.48, 0.22, 0.09))
	nt.color_ramp = g
	m.albedo_texture = nt
	var nn := NoiseTexture2D.new()
	nn.width = 256
	nn.height = 256
	nn.seamless = true
	nn.as_normal_map = true
	nn.bump_strength = 6.0
	nn.noise = fn
	m.normal_enabled = true
	m.normal_texture = nn
	m.metallic = 0.45
	m.roughness = 0.85
	m.uv1_scale = Vector3(2, 2, 2)
	_mats["rust"] = m
	return m

static func glass(tint: Color = Color(0.72, 0.86, 0.85, 0.42)) -> StandardMaterial3D:
	var key := "glass|%s" % tint
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	m.metallic_specular = 0.9
	m.rim_enabled = true
	m.rim = 0.4
	_mats[key] = m
	return m

static func water(fresh: bool = true) -> StandardMaterial3D:
	var key := "water|%s" % fresh
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.3, 0.3, 0.78) if fresh else Color(0.12, 0.28, 0.32, 0.8)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.04
	m.metallic_specular = 1.0
	var nn := NoiseTexture2D.new()
	nn.seamless = true
	nn.as_normal_map = true
	nn.bump_strength = 2.0
	var fn := FastNoiseLite.new()
	fn.frequency = 0.08
	nn.noise = fn
	m.normal_enabled = true
	m.normal_texture = nn
	m.normal_scale = 0.25
	_mats[key] = m
	return m

static func plastic() -> StandardMaterial3D:
	if _mats.has("plastic"):
		return _mats["plastic"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.86, 0.9, 0.92, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.18
	m.metallic_specular = 0.8
	_mats["plastic"] = m
	return m

static func soil(wet: float) -> StandardMaterial3D:
	var k := "soil|%d" % int(round(wet * 4.0))
	if _mats.has(k):
		return _mats[k]
	var m := pbr("brown_mud_leaves_01", Vector3(1.5, 1.5, 1.0)).duplicate() as StandardMaterial3D
	var w := roundf(wet * 4.0) / 4.0
	m.albedo_color = Color(1.0, 0.95, 0.9).lerp(Color(0.48, 0.4, 0.34), w)
	m.roughness_texture = null
	m.roughness = lerpf(0.95, 0.45, w)
	_mats[k] = m
	return m

## Лист с альфой (Leaf001/002), двусторонний.
static func leaf(set_name: String = "Leaf001", tint: Color = Color.WHITE) -> StandardMaterial3D:
	var key := "leaf|%s|%s" % [set_name, tint]
	if _mats.has(key):
		return _mats[key]
	var m := pbr(set_name, Vector3.ONE, tint).duplicate() as StandardMaterial3D
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.45
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.ao_enabled = false
	_mats[key] = m
	return m

## Лист-полоса злаков (кукуруза): непрозрачный, двусторонний, с лёгким блеском.
static func blade(c: Color) -> StandardMaterial3D:
	var key := "blade|%s" % c
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.7
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.backlight_enabled = true
	m.backlight = Color(0.12, 0.17, 0.05)
	_mats[key] = m
	return m

## Рыболовная сеть: альбедо Net001A + альфа из opacity.
static func net() -> StandardMaterial3D:
	if _mats.has("net"):
		return _mats["net"]
	var m := StandardMaterial3D.new()
	var a := _t("Net001A", "albedo")
	var o := _t("Net001A", "opacity")
	if a and o:
		var ia := a.get_image()
		var io := o.get_image()
		if ia and io:
			if ia.is_compressed():
				ia.decompress()
			if io.is_compressed():
				io.decompress()
			ia.convert(Image.FORMAT_RGBA8)
			io.convert(Image.FORMAT_RGBA8)
			if io.get_size() != ia.get_size():
				io.resize(ia.get_width(), ia.get_height())
			for y in ia.get_height():
				for x in ia.get_width():
					var c := ia.get_pixel(x, y)
					c.a = io.get_pixel(x, y).r
					ia.set_pixel(x, y, c)
			m.albedo_texture = ImageTexture.create_from_image(ia)
	m.albedo_color = Color(0.62, 0.66, 0.6)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.4
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.uv1_scale = Vector3(3, 3, 1)
	m.roughness = 0.9
	_mats["net"] = m
	return m

static func flame_mat(c: Color) -> StandardMaterial3D:
	var key := "flame|%s" % c
	if _mats.has(key):
		return _mats[key]
	var f := StandardMaterial3D.new()
	f.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	f.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	f.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if c.a > 0.5 else BaseMaterial3D.BLEND_MODE_MIX
	f.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	f.vertex_color_use_as_albedo = true
	f.albedo_texture = _soft_dot()
	f.albedo_color = c
	f.disable_receive_shadows = true
	_mats[key] = f
	return f

static func _soft_dot() -> Texture2D:
	if _mats.has("dot"):
		return _mats["dot"]
	var gt := GradientTexture2D.new()
	gt.width = 64
	gt.height = 64
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	gt.gradient = g
	_mats["dot"] = gt
	return gt

# ============================================================ ассеты

## Экземпляр glb (или null, если файла нет).
static func glb(file: String) -> Node3D:
	var p := file if file.begins_with("res://") else PH + file
	if not ResourceLoader.exists(p):
		return null
	if not _scenes.has(p):
		_scenes[p] = load(p)
	var ps := _scenes[p] as PackedScene
	return ps.instantiate() as Node3D if ps else null

## Меш OBJ из polyhaven_obj/<name>/ с PBR из соседних карт (альфа — ножницы).
static func obj(name: String, cutout: bool = false) -> MeshInstance3D:
	var p := "%s%s/%s.obj" % [OBJ, name, name]
	if not ResourceLoader.exists(p):
		return null
	var key := "obj|" + name
	if not _meshes.has(key):
		# OBJ импортируется без LOD и кусками по 5–20 поверхностей с одним
		# материалом: сливаем в одну поверхность и строим LOD один раз.
		# сканы полихейвен тяжёлые (таро-калатея 16.7k треуг. на куст 1 м) — базовый уровень
		# не больше OBJ_TRIS, дальше автоматические LOD
		_meshes[key] = MeshOptimizer.decimated(key, load(p) as Mesh, OBJ_TRIS)
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[key] as Mesh
	var mk := "objmat|%s" % name
	if not _mats.has(mk):
		var m := StandardMaterial3D.new()
		for ext in ["png", "jpg"]:
			var ap := "%s%s/%s_Albedo.%s" % [OBJ, name, name, ext]
			if ResourceLoader.exists(ap):
				m.albedo_texture = load(ap) as Texture2D
				break
		var np := "%s%s/%s_Normal.jpg" % [OBJ, name, name]
		if ResourceLoader.exists(np):
			m.normal_enabled = true
			m.normal_texture = load(np) as Texture2D
		m.roughness = 0.75
		if cutout:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m.alpha_scissor_threshold = 0.4
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats[mk] = m
	mi.material_override = _mats[mk]
	return mi

## AABB всех мешей поддерева в координатах root.
static func aabb_of(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n := stack.pop_back() as Node
		if n is MeshInstance3D and (n as MeshInstance3D).mesh:
			var mi := n as MeshInstance3D
			var xf := _rel_xform(root, mi)
			var b := xf * mi.mesh.get_aabb()
			out = b if first else out.merge(b)
			first = false
		for c in n.get_children():
			stack.append(c)
	return out

static func _rel_xform(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf

## Обернуть модель: масштаб под высоту h (или размер по наибольшей оси), низ — на y=0.
static func fit(model: Node3D, h: float, by_max: bool = false) -> Node3D:
	var wrap := Node3D.new()
	wrap.add_child(model)
	var b := aabb_of(wrap)
	var size := maxf(b.size.x, maxf(b.size.y, b.size.z)) if by_max else b.size.y
	if size > 0.0001:
		var s := h / size
		model.scale *= s
		b = aabb_of(wrap)
		model.position -= Vector3(b.get_center().x, b.position.y, b.get_center().z)
	return wrap

# ============================================================ примитивы

static func mesh_inst(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO,
		rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi

static func cyl(r_top: float, r_bot: float, h: float, seg: int = 10) -> CylinderMesh:
	var key := "cyl|%s|%s|%s|%d" % [r_top, r_bot, h, seg]
	if _meshes.has(key):
		return _meshes[key]
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bot
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	_meshes[key] = m
	return m

static func box(s: Vector3) -> BoxMesh:
	var key := "box|%s" % s
	if _meshes.has(key):
		return _meshes[key]
	var m := BoxMesh.new()
	m.size = s
	_meshes[key] = m
	return m

static func sphere(r: float, h: float = -1.0, seg: int = 12) -> SphereMesh:
	var key := "sph|%s|%s|%d" % [r, h, seg]
	if _meshes.has(key):
		return _meshes[key]
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0 if h < 0.0 else h
	m.radial_segments = seg
	m.rings = maxi(4, seg / 2)
	_meshes[key] = m
	return m

## Палка (кора) между двумя точками.
static func stick(parent: Node3D, a: Vector3, b: Vector3, r: float = 0.025) -> MeshInstance3D:
	var d := b - a
	var mi := mesh_inst(parent, cyl(r * 0.85, r, d.length(), 7), pbr("bark_brown_02", Vector3(1, 3, 1), Color(1.3, 1.15, 1.0)))
	mi.position = (a + b) * 0.5
	var up := d.normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	mi.basis = Basis(side, up, side.cross(up)).orthonormalized()
	return mi

## Верёвочная обмотка (тор) в точке.
static func lashing(parent: Node3D, at: Vector3, r: float = 0.035, axis: Vector3 = Vector3.UP) -> void:
	var tm := TorusMesh.new()
	tm.inner_radius = r
	tm.outer_radius = r + 0.018
	tm.rings = 10
	tm.ring_segments = 6
	var mi := mesh_inst(parent, tm, pbr("Rope001", Vector3(4, 1, 1)), at)
	if absf(axis.normalized().dot(Vector3.UP)) < 0.99:
		mi.basis = Basis(Quaternion(Vector3.UP, axis.normalized()))

## Плоский «лист» из двух треугольников со смещённым центром (лист растения).
static func leaf_mesh(w: float, l: float, bend: float = 0.15) -> ArrayMesh:
	var key := "leafm|%s|%s|%s" % [w, l, bend]
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := 4
	for i in rows:
		var t0 := float(i) / rows
		var t1 := float(i + 1) / rows
		var z0 := -l * t0
		var z1 := -l * t1
		var y0 := -bend * t0 * t0 * l
		var y1 := -bend * t1 * t1 * l
		for side in [-1.0, 1.0]:
			var a := Vector3(0, y0 + 0.02 * t0, z0)
			var b := Vector3(side * w * 0.5, y0, z0)
			var c := Vector3(side * w * 0.5, y1, z1)
			var d := Vector3(0, y1 + 0.02 * t1, z1)
			var ua := Vector2(0.5, 1.0 - t0)
			var ub := Vector2(0.5 + side * 0.5, 1.0 - t0)
			var uc := Vector2(0.5 + side * 0.5, 1.0 - t1)
			var ud := Vector2(0.5, 1.0 - t1)
			for v in [[a, ua], [b, ub], [c, uc], [a, ua], [c, uc], [d, ud]]:
				st.set_normal(Vector3.UP)
				st.set_uv(v[1])
				st.add_vertex(v[0])
	st.generate_tangents()
	var m := st.commit()
	_meshes[key] = m
	return m

## Неровный камень/кусок (икосфера с шумом).
static func lump(r: float, seed_v: int, squash: float = 0.6) -> ArrayMesh:
	var key := "lump|%s|%d|%s" % [r, seed_v, squash]
	if _meshes.has(key):
		return _meshes[key]
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 10
	sm.rings = 6
	var arr := sm.get_mesh_arrays()
	var verts := arr[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var fn := FastNoiseLite.new()
	fn.seed = seed_v
	fn.frequency = 2.2
	for i in verts.size():
		var v := verts[i]
		var k := 1.0 + fn.get_noise_3dv(v / r) * 0.35
		v *= k
		v.y *= squash
		verts[i] = v
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = null
	arr[Mesh.ARRAY_TANGENT] = null
	var st := SurfaceTool.new()
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	st.create_from(am, 0)
	st.generate_normals()
	st.generate_tangents()
	var m := st.commit()
	_meshes[key] = m
	return m

## Гнутый лист жести.
static func sheet(w: float, l: float, curl: float, seed_v: int) -> ArrayMesh:
	var key := "sheet|%s|%s|%s|%d" % [w, l, curl, seed_v]
	if _meshes.has(key):
		return _meshes[key]
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, l)
	pm.subdivide_width = 6
	pm.subdivide_depth = 6
	var arr := pm.get_mesh_arrays()
	var verts := arr[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var fn := FastNoiseLite.new()
	fn.seed = seed_v
	fn.frequency = 3.0
	for i in verts.size():
		var v := verts[i]
		v.y += curl * (v.x / w) * (v.x / w) * 2.0 + fn.get_noise_2d(v.x, v.z) * 0.03
		verts[i] = v
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = null
	arr[Mesh.ARRAY_TANGENT] = null
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var st := SurfaceTool.new()
	st.create_from(am, 0)
	st.generate_normals()
	st.generate_tangents()
	var m := st.commit()
	_meshes[key] = m
	return m

# ============================================================ огонь и дым

## Огонь: языки, искры, дым, свет. Вернёт узел; видимость = горит.
static func fire(parent: Node3D, size: float = 1.0, pos: Vector3 = Vector3.ZERO) -> Node3D:
	var root := Node3D.new()
	root.name = "Fire"
	root.position = pos
	parent.add_child(root)
	var flames := CPUParticles3D.new()
	flames.name = "Flames"
	flames.amount = int(26 * size) + 6
	flames.lifetime = 0.75
	flames.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2(0.32, 0.42) * size
	q.material = flame_mat(Color(1.0, 0.55, 0.16, 0.9))
	flames.mesh = q
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flames.emission_sphere_radius = 0.16 * size
	flames.direction = Vector3.UP
	flames.spread = 12.0
	flames.gravity = Vector3(0, 1.4, 0)
	flames.initial_velocity_min = 0.3
	flames.initial_velocity_max = 0.7
	flames.scale_amount_min = 0.6
	flames.scale_amount_max = 1.2
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.6))
	sc.add_point(Vector2(0.3, 1.0))
	sc.add_point(Vector2(1, 0.0))
	flames.scale_amount_curve = sc
	var cr := Gradient.new()
	cr.set_color(0, Color(1.0, 0.85, 0.45, 1))
	cr.add_point(0.5, Color(1.0, 0.45, 0.1, 0.9))
	cr.set_color(cr.get_point_count() - 1, Color(0.6, 0.1, 0.02, 0))
	flames.color_ramp = cr
	root.add_child(flames)
	var smoke := CPUParticles3D.new()
	smoke.name = "Smoke"
	smoke.amount = int(14 * size) + 4
	smoke.lifetime = 3.0   # > 3 с — чёрные клубы в Compatibility
	smoke.local_coords = false
	var sq := QuadMesh.new()
	sq.size = Vector2(0.6, 0.6) * size
	sq.material = flame_mat(Color(0.3, 0.29, 0.28, 0.32))
	smoke.mesh = sq
	smoke.position = Vector3(0, 0.45 * size, 0)
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = 0.1 * size
	smoke.direction = Vector3.UP
	smoke.spread = 18.0
	smoke.gravity = Vector3(0.25, 0.5, 0)
	smoke.initial_velocity_min = 0.4
	smoke.initial_velocity_max = 0.8
	smoke.scale_amount_min = 0.8
	smoke.scale_amount_max = 2.0
	var ss := Curve.new()
	ss.add_point(Vector2(0, 0.4))
	ss.add_point(Vector2(1, 1.6))
	smoke.scale_amount_curve = ss
	var sg := Gradient.new()
	sg.set_color(0, Color(1, 1, 1, 0.0))
	sg.add_point(0.15, Color(1, 1, 1, 0.8))
	sg.set_color(sg.get_point_count() - 1, Color(1, 1, 1, 0))
	smoke.color_ramp = sg
	root.add_child(smoke)
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = Color(1.0, 0.62, 0.3)
	light.light_energy = 2.2 * size
	light.omni_range = 7.0 * size
	light.position = Vector3(0, 0.45, 0)
	light.shadow_enabled = false
	light.distance_fade_enabled = true # дальние костры не считают свет
	light.distance_fade_begin = 45.0
	light.distance_fade_length = 15.0
	root.add_child(light)
	# угли
	var em := StandardMaterial3D.new()
	em.albedo_color = Color(0.1, 0.05, 0.03)
	em.emission_enabled = true
	em.emission = Color(1.0, 0.32, 0.06)
	em.emission_energy_multiplier = 1.6
	for i in 6:
		var a := TAU * i / 6.0
		mesh_inst(root, lump(0.05 * size, 300 + i, 0.6), em, Vector3(cos(a), 0.0, sin(a)) * 0.1 * size)
	return root

## Только дым (коптильня, кипящий котелок — пар).
static func smoke_only(parent: Node3D, pos: Vector3, tint: Color, amount: int = 10, size: float = 0.6) -> CPUParticles3D:
	var smoke := CPUParticles3D.new()
	smoke.amount = amount
	smoke.lifetime = 2.6
	smoke.local_coords = false
	var sq := QuadMesh.new()
	sq.size = Vector2(size, size)
	sq.material = flame_mat(tint)
	smoke.mesh = sq
	smoke.position = pos
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = 0.12
	smoke.direction = Vector3.UP
	smoke.spread = 15.0
	smoke.gravity = Vector3(0.2, 0.45, 0)
	smoke.initial_velocity_min = 0.25
	smoke.initial_velocity_max = 0.55
	var ss := Curve.new()
	ss.add_point(Vector2(0, 0.5))
	ss.add_point(Vector2(1, 1.8))
	smoke.scale_amount_curve = ss
	var sg := Gradient.new()
	sg.set_color(0, Color(1, 1, 1, 0.0))
	sg.add_point(0.2, Color(1, 1, 1, 0.75))
	sg.set_color(sg.get_point_count() - 1, Color(1, 1, 1, 0))
	smoke.color_ramp = sg
	parent.add_child(smoke)
	return smoke

# ============================================================ постройки

## Каменное кольцо очага + поленья.
static func campfire(root: Node3D) -> void:
	var stone_m := pbr("mossy_rock", Vector3(1, 1, 1), Color(0.95, 0.92, 0.88))
	for i in 9:
		var a := TAU * i / 9.0 + 0.2
		mesh_inst(root, lump(0.13, 40 + i, 0.55), stone_m, Vector3(cos(a) * 0.48, 0.05, sin(a) * 0.48), Vector3(0, a, 0))
	# пепел
	mesh_inst(root, cyl(0.36, 0.38, 0.02, 14), color(Color(0.17, 0.16, 0.15), 1.0), Vector3(0, 0.01, 0))
	for i in 5:
		var a := TAU * i / 5.0 + 0.3
		var top := Vector3(0, 0.38, 0)
		var bot := Vector3(cos(a) * 0.3, 0.02, sin(a) * 0.3)
		stick(root, bot, top, 0.03)
	# рогатины и вертел над огнём
	for s in [-1.0, 1.0]:
		stick(root, Vector3(s * 0.62, 0.0, -0.05), Vector3(s * 0.6, 0.78, 0.0), 0.022)
		stick(root, Vector3(s * 0.6, 0.62, 0.0), Vector3(s * 0.66, 0.84, 0.0), 0.016)
	stick(root, Vector3(-0.72, 0.74, 0.0), Vector3(0.72, 0.74, 0.0), 0.014)

## Решётка-гриль над огнём (для BUILD-очага).
static func grill(root: Node3D, y: float) -> void:
	for s in [-1.0, 1.0]:
		stick(root, Vector3(s * 0.62, 0.0, -0.05), Vector3(s * 0.6, y + 0.1, 0.0), 0.022)
	stick(root, Vector3(-0.72, y, 0.0), Vector3(0.72, y, 0.0), 0.014)

## Котелок над огнём.
static func pot_model(fill: float) -> Node3D:
	var root := Node3D.new()
	var m := obj("brass_pot_01")
	if m:
		var w := fit(m, 0.22, true)
		root.add_child(w)
	else:
		mesh_inst(root, cyl(0.12, 0.1, 0.16, 14), rust(), Vector3(0, 0.08, 0))
	if fill > 0.0:
		mesh_inst(root, cyl(0.095, 0.095, 0.01, 14), water(true), Vector3(0, 0.12, 0))
	return root

## Сушилка-коптильня: рама из жердей, навес из листьев, решётка, тлеющий огонь.
static func smoker(root: Node3D) -> void:
	var w := 0.75
	var d := 0.55
	var h := 1.35
	for x in [-w, w]:
		for z in [-d, d]:
			stick(root, Vector3(x, -0.05, z), Vector3(x * 0.92, h, z * 0.92), 0.03)
	for z in [-d * 0.92, d * 0.92]:
		stick(root, Vector3(-w * 0.95, h - 0.05, z), Vector3(w * 0.95, h - 0.05, z), 0.022)
		lashing(root, Vector3(-w * 0.92, h - 0.05, z), 0.03)
		lashing(root, Vector3(w * 0.92, h - 0.05, z), 0.03)
	# поперечины-вешала
	for i in 5:
		var x := -w * 0.75 + i * w * 0.375
		stick(root, Vector3(x, h - 0.02, -d * 0.95), Vector3(x, h - 0.02, d * 0.95), 0.012)
	# навес из пальмовых листьев (соломенная кровля)
	var roof := pbr("ThatchedRoof001A", Vector3(2, 2, 1))
	roof.cull_mode = BaseMaterial3D.CULL_DISABLED
	for s in [-1.0, 1.0]:
		var mi := mesh_inst(root, box(Vector3(w * 2.3, 0.04, d * 1.3)), roof,
			Vector3(0, h + 0.28, s * d * 0.55), Vector3(s * 0.55, 0, 0))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# нижняя решётка над огнём
	for i in 7:
		var z := -d * 0.8 + i * d * 0.8 / 3.0
		stick(root, Vector3(-w * 0.85, 0.55, z), Vector3(w * 0.85, 0.55, z), 0.01)
	# очаг под ней
	var stone_m := pbr("mossy_rock")
	for i in 7:
		var a := TAU * i / 7.0
		mesh_inst(root, lump(0.1, 70 + i, 0.55), stone_m, Vector3(cos(a) * 0.35, 0.04, sin(a) * 0.3))

## Полоска вяленого мяса/рыбы на вешале.
static func strip(kind: StringName, done: float) -> MeshInstance3D:
	var raw := Color(0.72, 0.28, 0.26) if kind == &"meat" else Color(0.66, 0.7, 0.72)
	var dried := Color(0.33, 0.15, 0.1) if kind == &"meat" else Color(0.55, 0.38, 0.2)
	var mi := MeshInstance3D.new()
	mi.mesh = box(Vector3(0.05, 0.28, 0.012)) if kind == &"meat" else lump(0.06, 7, 0.5)
	if kind != &"meat":
		mi.scale = Vector3(0.6, 2.4, 1.0)
	mi.material_override = color(raw.lerp(dried, clampf(done, 0.0, 1.0)), 0.6)
	return mi

## Еда на гриле (кусок мяса, рыба, клубень, початок).
static func grill_food(id: StringName, done: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var raw := Color(0.75, 0.32, 0.32)
	var cooked := Color(0.42, 0.22, 0.12)
	match id:
		&"fish_raw":
			mi.mesh = lump(0.07, 11, 0.45)
			mi.scale = Vector3(2.6, 1.0, 1.0)
			raw = Color(0.6, 0.66, 0.7)
			cooked = Color(0.7, 0.5, 0.28)
		&"taro":
			mi.mesh = lump(0.06, 12, 0.85)
			raw = Color(0.55, 0.42, 0.45)
			cooked = Color(0.4, 0.3, 0.24)
		&"maize":
			mi.mesh = cyl(0.03, 0.035, 0.18, 8)
			mi.rotation = Vector3(0, 0, PI * 0.5)
			raw = Color(0.95, 0.82, 0.32)
			cooked = Color(0.75, 0.5, 0.2)
		_:
			mi.mesh = lump(0.075, 13, 0.55)
	mi.material_override = color(raw.lerp(cooked, clampf(done, 0.0, 1.0)), lerpf(0.5, 0.75, done))
	return mi

## Солнечный опреснитель: яма-ёмкость с морской водой, плёнка конусом, камешек, бутылка.
static func still(root: Node3D) -> Dictionary:
	var sand := pbr("coast_sand_01", Vector3(1, 1, 1))
	mesh_inst(root, cyl(0.62, 0.7, 0.12, 18), sand, Vector3(0, 0.03, 0))
	var basin := mesh_inst(root, cyl(0.52, 0.5, 0.02, 18), water(false), Vector3(0, 0.1, 0))
	# плёнка — пологий конус
	var cone := CylinderMesh.new()
	cone.top_radius = 0.02
	cone.bottom_radius = 0.58
	cone.height = 0.24
	cone.radial_segments = 18
	cone.cap_top = false
	cone.cap_bottom = false
	mesh_inst(root, cone, plastic(), Vector3(0, 0.22, 0), Vector3(PI, 0, 0))
	# камешек в центре и придавленные края
	mesh_inst(root, lump(0.05, 21, 0.7), pbr("mossy_rock"), Vector3(0, 0.12, 0))
	for i in 8:
		var a := TAU * i / 8.0
		mesh_inst(root, lump(0.08, 22 + i, 0.5), pbr("mossy_rock"), Vector3(cos(a) * 0.6, 0.1, sin(a) * 0.6))
	# сосуд под капелью
	var cup := MeshInstance3D.new()
	cup.mesh = cyl(0.06, 0.05, 0.1, 10)
	cup.material_override = glass()
	cup.position = Vector3(0, 0.06, 0)
	root.add_child(cup)
	var lvl := mesh_inst(root, cyl(0.05, 0.05, 0.01, 10), water(true), Vector3(0, 0.02, 0))
	return {"basin": basin, "level": lvl}

## Бочка для дождя (ассет), открытый верх с водой.
static func rain_barrel(root: Node3D) -> MeshInstance3D:
	var m := glb("wooden_barrels_01_barrel01.glb")
	if m == null:
		m = glb("wine_barrel_01.glb")
	if m:
		root.add_child(fit(m, 0.95))
	else:
		mesh_inst(root, cyl(0.3, 0.27, 0.95, 16), pbr("weathered_planks"), Vector3(0, 0.47, 0))
	# воронка из листьев сверху
	var lm := leaf("Leaf002", Color(0.85, 0.95, 0.75))
	for i in 6:
		var a := TAU * i / 6.0
		var mi := mesh_inst(root, leaf_mesh(0.22, 0.42, -0.25), lm, Vector3(cos(a) * 0.12, 0.98, sin(a) * 0.12))
		mi.rotation = Vector3(-0.35, -a + PI * 0.5, 0)
	return mesh_inst(root, cyl(0.25, 0.25, 0.01, 16), water(true), Vector3(0, 0.3, 0))

## Тент: полотно на 4 жердях, провис к центру, ведро под стоком.
static func tarp(root: Node3D) -> MeshInstance3D:
	var hw := 1.0
	var hd := 0.85
	var hs := [1.25, 1.1, 1.25, 1.1]
	var corners := [Vector3(-hw, 0, -hd), Vector3(hw, 0, -hd), Vector3(hw, 0, hd), Vector3(-hw, 0, hd)]
	for i in 4:
		var c: Vector3 = corners[i]
		stick(root, c - Vector3(0, 0.1, 0), c + Vector3(0, hs[i], 0), 0.028)
		lashing(root, c + Vector3(0, hs[i] - 0.04, 0), 0.032)
	# провисшее полотно
	var pm := PlaneMesh.new()
	pm.size = Vector2(hw * 2.0, hd * 2.0)
	pm.subdivide_width = 8
	pm.subdivide_depth = 8
	var arr := pm.get_mesh_arrays()
	var verts := arr[Mesh.ARRAY_VERTEX] as PackedVector3Array
	for i in verts.size():
		var v := verts[i]
		var u := absf(v.x) / hw
		var w := absf(v.z) / hd
		v.y = 1.18 - (1.0 - u * u) * (1.0 - w * w) * 0.38
		verts[i] = v
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = null
	arr[Mesh.ARRAY_TANGENT] = null
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var st := SurfaceTool.new()
	st.create_from(am, 0)
	st.generate_normals()
	st.generate_tangents()
	var cloth := pbr("Fabric004", Vector3(2, 2, 1), Color(0.86, 0.8, 0.62)).duplicate() as StandardMaterial3D
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_inst(root, st.commit(), cloth)
	# дырка-сток и ведро
	var b := glb("wooden_bucket_01.glb")
	if b:
		root.add_child(fit(b, 0.4))
	else:
		mesh_inst(root, cyl(0.17, 0.14, 0.38, 14), pbr("weathered_planks"), Vector3(0, 0.19, 0))
	return mesh_inst(root, cyl(0.14, 0.14, 0.01, 14), water(true), Vector3(0, 0.12, 0))

## Грядка: бортик из жердей + вскопанная земля.
static func garden_bed(root: Node3D) -> MeshInstance3D:
	var hw := 0.95
	var hd := 0.6
	var bed := mesh_inst(root, box(Vector3(hw * 2.0 - 0.06, 0.16, hd * 2.0 - 0.06)), soil(0.0), Vector3(0, 0.05, 0))
	bed.set_meta(&"soil", true)
	# борозды
	for i in 3:
		var z := -hd * 0.6 + i * hd * 0.6
		mesh_inst(root, cyl(0.07, 0.09, hw * 1.8, 8), soil(0.0), Vector3(0, 0.14, z), Vector3(0, 0, PI * 0.5), Vector3(1, 1, 0.55)).set_meta(&"soil", true)
	for y in [0.06, 0.15]:
		stick(root, Vector3(-hw, y, -hd), Vector3(hw, y, -hd), 0.035)
		stick(root, Vector3(-hw, y, hd), Vector3(hw, y, hd), 0.035)
		stick(root, Vector3(-hw, y, -hd), Vector3(-hw, y, hd), 0.035)
		stick(root, Vector3(hw, y, -hd), Vector3(hw, y, hd), 0.035)
	for c in [Vector3(-hw, 0, -hd), Vector3(hw, 0, -hd), Vector3(hw, 0, hd), Vector3(-hw, 0, hd)]:
		stick(root, c - Vector3(0, 0.12, 0), c + Vector3(0, 0.26, 0), 0.03)
	return bed

## Родник: каменная чаша с водой и бьющей струйкой.
static func spring(root: Node3D) -> void:
	for i in 10:
		var a := TAU * i / 10.0
		var rk := glb("rock_moss_set_01_rock0%d.glb" % (1 + i % 6))
		if rk:
			var w := fit(rk, 0.45 + 0.2 * float(i % 3), true)
			w.position = Vector3(cos(a) * 1.15, -0.05, sin(a) * 1.0)
			w.rotation.y = a * 2.3
			root.add_child(w)
		else:
			mesh_inst(root, lump(0.3, 90 + i, 0.6), pbr("mossy_rock"), Vector3(cos(a) * 1.15, 0.05, sin(a) * 1.0))
	mesh_inst(root, cyl(1.05, 0.9, 0.3, 20), pbr("damp_sand", Vector3(1, 1, 1), Color(0.5, 0.45, 0.4)), Vector3(0, -0.12, 0))
	mesh_inst(root, cyl(0.98, 0.98, 0.01, 22), water(true), Vector3(0, 0.08, 0))
	# пузырьки — тонкие капли
	var drops := CPUParticles3D.new()
	drops.amount = 16
	drops.lifetime = 0.9
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06)
	q.material = flame_mat(Color(0.85, 0.92, 1.0, 0.5))
	drops.mesh = q
	drops.position = Vector3(0, 0.1, 0)
	drops.direction = Vector3.UP
	drops.spread = 25.0
	drops.initial_velocity_min = 0.6
	drops.initial_velocity_max = 1.0
	drops.gravity = Vector3(0, -3.0, 0)
	root.add_child(drops)

# ============================================================ растения

## Растение огорода на стадии 0..4 (0 — росток, 4 — с плодами). wilt 0..1 — увядание.
static func plant(kind: StringName, stage: int, wilt: float, seed_v: int) -> Node3D:
	var root := Node3D.new()
	var g := clampf(float(stage) / 4.0, 0.08, 1.0)
	var tint := Color(0.9, 1.0, 0.85).lerp(Color(0.85, 0.7, 0.35), wilt)
	var droop := 0.15 + wilt * 0.6
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	match kind:
		&"taro":
			var c := obj("calathea_orbifolia_01", true) if stage >= 2 else null
			if c:
				var w := fit(c, 0.35 + 0.45 * g)
				root.add_child(w)
				if wilt > 0.3:
					w.scale.y = 1.0 - wilt * 0.45
			else:
				for i in 2 + stage:
					var a := TAU * i / (2.0 + stage) + rng.randf() * 0.5
					stick(root, Vector3.ZERO, Vector3(cos(a) * 0.05, 0.12 + 0.3 * g, sin(a) * 0.05), 0.008)
					var lf := mesh_inst(root, leaf_mesh(0.14 + 0.2 * g, 0.18 + 0.28 * g, droop), leaf("Leaf001", tint),
						Vector3(cos(a) * 0.05, 0.12 + 0.3 * g, sin(a) * 0.05))
					lf.rotation = Vector3(-0.2, -a + PI * 0.5, 0)
			if stage >= 4:
				for i in 3:
					var a := TAU * i / 3.0
					mesh_inst(root, lump(0.06, 400 + i, 0.8), color(Color(0.5, 0.38, 0.4)), Vector3(cos(a) * 0.12, 0.02, sin(a) * 0.12))
		&"maize":
			var h := 0.2 + 1.5 * g
			stick(root, Vector3.ZERO, Vector3(0, h, 0), 0.016 + 0.016 * g).material_override = color(tint * Color(0.36, 0.5, 0.22), 0.7)
			var n := 3 + stage * 2
			var bm := blade(tint * Color(0.27, 0.42, 0.17))
			for i in n:
				var y := h * (0.08 + 0.82 * float(i) / n)
				var a := float(i) * 2.4 + rng.randf_range(-0.3, 0.3)
				var ln := (0.22 + 0.5 * g) * (1.15 - 0.45 * float(i) / n) # нижние длиннее
				var lf := mesh_inst(root, leaf_mesh(0.07 + 0.05 * g, ln, droop + 0.25), bm, Vector3(0, y, 0))
				lf.rotation = Vector3(-0.95 + wilt * 0.6, a, 0)
			if stage >= 3:
				for k in 2:
					var cob := mesh_inst(root, cyl(0.03, 0.04, 0.2, 8),
						color(Color(0.55, 0.7, 0.35) if stage == 3 else Color(0.92, 0.8, 0.35), 0.6),
						Vector3(0.05, h * (0.45 + 0.15 * k), 0.0), Vector3(0, k * PI, -0.35))
					cob.rotation.y = k * PI
			if stage >= 4:
				for k in 6:
					mesh_inst(root, cyl(0.002, 0.002, 0.12, 3), color(Color(0.7, 0.45, 0.25)), Vector3(0, h + 0.05, 0),
						Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5)))
		&"melon":
			var n := 3 + stage * 2
			for i in n:
				var a := TAU * i / n + rng.randf() * 0.4
				var r := 0.05 + 0.4 * g * rng.randf_range(0.5, 1.0)
				var lf := mesh_inst(root, leaf_mesh(0.18 * (0.5 + g * 0.5), 0.2 * (0.5 + g * 0.5), 0.05 + wilt * 0.3),
					leaf("Leaf001", tint), Vector3(cos(a) * r, 0.04 + 0.05 * g, sin(a) * r))
				lf.rotation = Vector3(0.1, -a, 0)
			if stage >= 3:
				var mm := StandardMaterial3D.new()
				var stripes := GradientTexture2D.new()
				var sg := Gradient.new()
				sg.set_color(0, Color(0.25, 0.42, 0.15))
				sg.set_color(1, Color(0.62, 0.72, 0.38) if stage >= 4 else Color(0.35, 0.55, 0.2))
				sg.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
				sg.add_point(0.5, Color(0.48, 0.62, 0.28) if stage >= 4 else Color(0.3, 0.5, 0.18))
				stripes.gradient = sg
				stripes.width = 16
				stripes.height = 4
				mm.albedo_texture = stripes
				mm.uv1_scale = Vector3(6, 1, 1)
				mm.roughness = 0.45
				for k in 2:
					var a := k * PI + 0.6
					mesh_inst(root, sphere(0.12 if stage >= 4 else 0.07, -1.0, 14), mm,
						Vector3(cos(a) * 0.25, 0.08 if stage >= 4 else 0.05, sin(a) * 0.25), Vector3.ZERO, Vector3(1.25, 1.0, 1.0))
		_: # berry
			var sh := glb("shrub_02_a.glb")
			if sh and stage >= 2:
				var w := fit(sh, 0.3 + 0.55 * g)
				root.add_child(w)
			else:
				for i in 3 + stage:
					var a := TAU * i / (3.0 + stage)
					stick(root, Vector3.ZERO, Vector3(cos(a) * 0.08, 0.15 + 0.25 * g, sin(a) * 0.08), 0.007)
					var lf := mesh_inst(root, leaf_mesh(0.08, 0.12, droop), leaf("Leaf002", tint),
						Vector3(cos(a) * 0.08, 0.15 + 0.25 * g, sin(a) * 0.08))
					lf.rotation.y = -a
			if stage >= 3:
				var bm := color(Color(0.72, 0.08, 0.2) if stage >= 4 else Color(0.5, 0.65, 0.25), 0.35)
				for i in (14 if stage >= 4 else 7):
					var a := rng.randf() * TAU
					var r := rng.randf_range(0.08, 0.26 + 0.1 * g)
					mesh_inst(root, sphere(0.022, -1.0, 6), bm, Vector3(cos(a) * r, rng.randf_range(0.25, 0.6) * (0.4 + g * 0.8), sin(a) * r))
	if wilt > 0.05:
		root.rotation.x = wilt * 0.12
	return root

## Дикое растение (таро, ягодник, лечебная трава) — крупнее и гуще.
static func wild_plant(kind: StringName, seed_v: int) -> Node3D:
	match kind:
		&"herb":
			var root := Node3D.new()
			var m := obj("shrub_sorrel_01", true)
			if m:
				root.add_child(fit(m, 0.45))
			else:
				root.add_child(plant(&"berry", 2, 0.0, seed_v))
			# мелкие белые цветки — чтобы отличать от сорняков
			var fm := color(Color(0.95, 0.95, 0.88), 0.5)
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_v
			for i in 9:
				var a := rng.randf() * TAU
				var r := rng.randf_range(0.05, 0.22)
				mesh_inst(root, sphere(0.018, -1.0, 6), fm, Vector3(cos(a) * r, rng.randf_range(0.28, 0.45), sin(a) * r))
			return root
		&"taro":
			var root := Node3D.new()
			var c := obj("calathea_orbifolia_01", true)
			if c:
				var w := fit(c, 0.95)
				root.add_child(w)
			else:
				root.add_child(plant(&"taro", 4, 0.0, seed_v))
			return root
		_:
			return plant(kind, 4, 0.0, seed_v)

# ============================================================ мусор с берега

static func debris(kind: StringName, seed_v: int) -> Node3D:
	var root := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	match kind:
		&"barrel":
			var m := glb("wooden_barrels_01_barrel0%d.glb" % (1 + seed_v % 2))
			if m == null:
				m = glb("wine_barrel_01.glb")
			var w := fit(m, 0.9) if m else null
			if w:
				# лежит на боку, наполовину в песке
				w.rotation = Vector3(0, rng.randf() * TAU, PI * 0.5)
				w.position = Vector3(0, 0.34, 0)
				root.add_child(w)
			# водоросли на боку
			var wm := leaf("Leaf002", Color(0.35, 0.4, 0.2))
			for i in 4:
				var lf := mesh_inst(root, leaf_mesh(0.08, 0.35, 0.6), wm, Vector3(rng.randf_range(-0.3, 0.3), 0.55, rng.randf_range(-0.2, 0.2)))
				lf.rotation = Vector3(0.6, rng.randf() * TAU, 0)
		&"crate":
			var m := glb("wooden_crate_0%d.glb" % (1 + seed_v % 2))
			if m:
				var w := fit(m, 0.65, true)
				w.rotation = Vector3(rng.randf_range(-0.15, 0.15), rng.randf() * TAU, rng.randf_range(-0.2, 0.2))
				w.position.y = -0.1
				root.add_child(w)
			else:
				mesh_inst(root, box(Vector3(0.6, 0.5, 0.5)), pbr("weathered_planks"), Vector3(0, 0.2, 0))
		&"bottles":
			for i in 3 + seed_v % 3:
				var b := glb("res://assets/models/khronos/WaterBottle.glb")
				var w := fit(b, 0.26) if b else null
				if w == null:
					w = Node3D.new()
					mesh_inst(w, cyl(0.035, 0.04, 0.26, 10), glass(), Vector3(0, 0.13, 0))
				var a := rng.randf() * TAU
				var r := rng.randf_range(0.0, 0.45)
				w.position = Vector3(cos(a) * r, 0.04, sin(a) * r)
				w.rotation = Vector3(0, rng.randf() * TAU, PI * 0.5 + rng.randf_range(-0.2, 0.2))
				root.add_child(w)
			for i in 2:
				var mi := mesh_inst(root, sheet(0.6, 0.45, 0.06, seed_v + i), plastic(),
					Vector3(rng.randf_range(-0.3, 0.3), 0.03 + i * 0.03, rng.randf_range(-0.3, 0.3)), Vector3(0, rng.randf() * TAU, 0))
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		&"net":
			# ком сети, путаница верёвок и поплавки
			for i in 3:
				var mi := mesh_inst(root, lump(0.45 - i * 0.08, seed_v * 3 + i, 0.4), net(),
					Vector3(rng.randf_range(-0.3, 0.3), 0.08 + i * 0.05, rng.randf_range(-0.3, 0.3)), Vector3(0, rng.randf() * TAU, 0))
				mi.scale = Vector3(1.4, 1.0, 1.0)
			var rope := pbr("Rope001", Vector3(8, 1, 1), Color(0.85, 0.82, 0.75))
			for i in 2:
				var tm := TorusMesh.new()
				tm.inner_radius = 0.16 + i * 0.05
				tm.outer_radius = tm.inner_radius + 0.035
				tm.rings = 18
				tm.ring_segments = 6
				mesh_inst(root, tm, rope, Vector3(0.45 - i * 0.9, 0.04, rng.randf_range(-0.3, 0.3)), Vector3(0.1, 0, 0.1))
			var fm := color(Color(0.85, 0.42, 0.12), 0.55)
			for i in 4:
				mesh_inst(root, sphere(0.06, -1.0, 8), fm, Vector3(rng.randf_range(-0.6, 0.6), 0.06, rng.randf_range(-0.5, 0.5)))
		&"scrap":
			if seed_v % 5 == 0:
				var c := glb("cannon_01.glb")
				if c:
					var w := fit(c, 1.7, true)
					w.rotation = Vector3(0.08, rng.randf() * TAU, 0.3)
					w.position.y = -0.15
					root.add_child(w)
					root.set_meta(&"cannon", true)
					return root
			for i in 4:
				mesh_inst(root, sheet(rng.randf_range(0.4, 0.8), rng.randf_range(0.3, 0.6), rng.randf_range(-0.1, 0.15), seed_v * 7 + i), rust(),
					Vector3(rng.randf_range(-0.35, 0.35), 0.03 + i * 0.04, rng.randf_range(-0.35, 0.35)),
					Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3)))
			# ржавая бочка-обрезок
			mesh_inst(root, cyl(0.2, 0.2, 0.35, 12), rust(), Vector3(0.3, 0.17, 0.2), Vector3(PI * 0.5, 0.4, 0))
	return root

# ============================================================ в руке

## Бутылка (fill 0 — пустая; 0.8 — с водой). Корень — точка хвата.
static func held_bottle(fill: float) -> Node3D:
	var root := Node3D.new()
	var b := glb("res://assets/models/khronos/WaterBottle.glb")
	if b:
		var w := fit(b, 0.24)
		w.position = Vector3(0, -0.04, -0.02)
		root.add_child(w)
	else:
		mesh_inst(root, cyl(0.035, 0.035, 0.22, 10), glass(), Vector3(0, 0.07, -0.02))
	return root

## Половинка кокоса (fill: 0 — пустая, 1 — вода, 2 — отвар).
static func held_shell(fill: float) -> Node3D:
	var root := Node3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.075
	sm.height = 0.075
	sm.is_hemisphere = true
	sm.radial_segments = 14
	sm.rings = 6
	var shell := pbr("palm_bark", Vector3(1, 1, 1), Color(0.75, 0.55, 0.38))
	mesh_inst(root, sm, shell, Vector3(0, 0.07, -0.03), Vector3(PI, 0, 0))
	# белый край мякоти — кольцо, а не диск (иначе вода не видна)
	var rim := TorusMesh.new()
	rim.inner_radius = 0.062
	rim.outer_radius = 0.075
	rim.rings = 16
	rim.ring_segments = 6
	mesh_inst(root, rim, color(Color(0.95, 0.93, 0.88), 0.7), Vector3(0, 0.07, -0.03))
	if fill > 0.0:
		var c := Color(0.5, 0.38, 0.12) if fill > 1.5 else Color(0.18, 0.36, 0.42)
		var wm := color(c, 0.05)
		wm.metallic_specular = 0.9
		mesh_inst(root, cyl(0.063, 0.063, 0.004, 16), wm, Vector3(0, 0.067, -0.03))
	else:
		mesh_inst(root, cyl(0.063, 0.063, 0.004, 16), color(Color(0.86, 0.82, 0.74), 0.8), Vector3(0, 0.06, -0.03))
	return root

static func held_pot() -> Node3D:
	var root := Node3D.new()
	var p := pot_model(0.0)
	p.position = Vector3(0, 0.0, -0.06)
	root.add_child(p)
	return root

static func held_knife() -> Node3D:
	var root := Node3D.new()
	mesh_inst(root, cyl(0.014, 0.016, 0.11, 8), pbr("bark_brown_02", Vector3(1, 2, 1)), Vector3(0, 0.0, 0))
	lashing(root, Vector3(0, 0.05, 0), 0.016)
	var blade := mesh_inst(root, box(Vector3(0.004, 0.15, 0.03)), rust(), Vector3(0, 0.13, -0.005))
	blade.rotation.x = 0.04
	return root
