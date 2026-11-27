class_name AnimalModels
extends RefCounted
## Процедурные реалистичные модели животных. Нос смотрит в -Z, спина — +Y.
## Тело — лофт по эллиптическим сечениям (гладкие нормали), лапы/клешни/крылья — на шарнирах
## (Node3D-пивоты), чтобы скрипт животного мог анимировать походку и взмахи.
## COLOR вершин для fauna_skin: r — спина, g — деталь (светлая/цветная зона), b — изгиб к хвосту, a — крыло.
## build(species) -> Node3D; meta: "legs" (Array[Node3D] пивоты, чётные — левые), "wings" (Array[Node3D]),
## "head" (Node3D), "body" (MeshInstance3D), "mat" (ShaderMaterial), "tail" (Node3D|null), "jaw" (Node3D|null).

const SKIN := preload("res://scripts/fauna/shaders/fauna_skin.gdshader")

## Внешний вид видов (размеры в метрах).
const LOOK := {
	&"boar": {"back": Color(0.24, 0.19, 0.15), "belly": Color(0.42, 0.34, 0.27), "pat": Color(0.13, 0.1, 0.08),
		"detail": Color(0.86, 0.82, 0.72), "pk": 5.0, "ps": 7.0, "pa": 0.6, "rough": 0.92, "sheen": 0.6},
	&"crab": {"back": Color(0.78, 0.3, 0.12), "belly": Color(0.95, 0.75, 0.55), "pat": Color(0.55, 0.16, 0.06),
		"detail": Color(0.08, 0.06, 0.05), "pk": 1.0, "ps": 18.0, "pa": 0.5, "rough": 0.45, "wet": 0.5},
	&"coconut_crab": {"back": Color(0.36, 0.22, 0.32), "belly": Color(0.75, 0.55, 0.45), "pat": Color(0.2, 0.12, 0.2),
		"detail": Color(0.08, 0.06, 0.05), "pk": 1.0, "ps": 14.0, "pa": 0.5, "rough": 0.55, "wet": 0.2},
	&"snake": {"back": Color(0.36, 0.33, 0.18), "belly": Color(0.82, 0.76, 0.52), "pat": Color(0.12, 0.1, 0.06),
		"detail": Color(0.85, 0.7, 0.3), "pk": 3.0, "ps": 7.0, "pa": 0.85, "rough": 0.38, "wet": 0.2},
	&"croc": {"back": Color(0.23, 0.26, 0.17), "belly": Color(0.7, 0.67, 0.5), "pat": Color(0.12, 0.13, 0.09),
		"detail": Color(0.85, 0.82, 0.7), "pk": 4.0, "ps": 4.5, "pa": 0.55, "rough": 0.55, "wet": 0.35},
	&"monkey": {"back": Color(0.36, 0.26, 0.17), "belly": Color(0.62, 0.5, 0.38), "pat": Color(0.2, 0.14, 0.09),
		"detail": Color(0.78, 0.6, 0.5), "pk": 5.0, "ps": 9.0, "pa": 0.5, "rough": 0.95, "sheen": 0.8},
	&"iguana": {"back": Color(0.32, 0.5, 0.22), "belly": Color(0.62, 0.7, 0.42), "pat": Color(0.2, 0.3, 0.14),
		"detail": Color(0.75, 0.65, 0.35), "pk": 2.0, "ps": 5.0, "pa": 0.55, "rough": 0.5},
	&"monitor": {"back": Color(0.27, 0.26, 0.2), "belly": Color(0.55, 0.5, 0.38), "pat": Color(0.62, 0.56, 0.36),
		"detail": Color(0.45, 0.2, 0.25), "pk": 1.0, "ps": 10.0, "pa": 0.65, "rough": 0.55},
	&"scorpion": {"back": Color(0.16, 0.12, 0.08), "belly": Color(0.32, 0.25, 0.16), "pat": Color(0.06, 0.05, 0.04),
		"detail": Color(0.55, 0.38, 0.18), "pk": 2.0, "ps": 25.0, "pa": 0.4, "rough": 0.3, "wet": 0.3},
	&"spider": {"back": Color(0.1, 0.08, 0.07), "belly": Color(0.2, 0.15, 0.12), "pat": Color(0.55, 0.32, 0.12),
		"detail": Color(0.6, 0.35, 0.15), "pk": 5.0, "ps": 30.0, "pa": 0.6, "rough": 0.95, "sheen": 0.5},
	&"parrot": {"back": Color(0.8, 0.1, 0.08), "belly": Color(0.86, 0.15, 0.1), "pat": Color(0.1, 0.3, 0.75),
		"detail": Color(0.95, 0.78, 0.15), "pk": 0.0, "ps": 1.0, "pa": 0.0, "rough": 0.7, "sheen": 0.4},
	&"gull": {"back": Color(0.62, 0.65, 0.68), "belly": Color(0.96, 0.96, 0.95), "pat": Color(0.1, 0.1, 0.1),
		"detail": Color(0.95, 0.75, 0.2), "pk": 0.0, "ps": 1.0, "pa": 0.0, "rough": 0.75, "sheen": 0.3},
	&"bat": {"back": Color(0.16, 0.13, 0.11), "belly": Color(0.24, 0.19, 0.15), "pat": Color(0.08, 0.06, 0.05),
		"detail": Color(0.3, 0.22, 0.2), "pk": 5.0, "ps": 20.0, "pa": 0.4, "rough": 0.9, "sheen": 0.4},
	&"turtle": {"back": Color(0.3, 0.27, 0.17), "belly": Color(0.8, 0.72, 0.5), "pat": Color(0.16, 0.13, 0.08),
		"detail": Color(0.48, 0.45, 0.32), "pk": 4.0, "ps": 3.0, "pa": 0.75, "rough": 0.45, "wet": 0.3},
}

static var _cache: Dictionary = {}

static func make_material(species: StringName, body_len: float) -> ShaderMaterial:
	var L: Dictionary = LOOK[species]
	var m := ShaderMaterial.new()
	m.shader = SKIN
	m.set_shader_parameter(&"back_color", L["back"])
	m.set_shader_parameter(&"belly_color", L["belly"])
	m.set_shader_parameter(&"pattern_color", L["pat"])
	m.set_shader_parameter(&"detail_color", L["detail"])
	m.set_shader_parameter(&"pattern_kind", L["pk"])
	m.set_shader_parameter(&"pattern_scale", L["ps"])
	m.set_shader_parameter(&"pattern_amount", L["pa"])
	m.set_shader_parameter(&"roughness_base", L.get("rough", 0.7))
	m.set_shader_parameter(&"wetness", L.get("wet", 0.0))
	m.set_shader_parameter(&"sheen", L.get("sheen", 0.0))
	m.set_shader_parameter(&"body_length", body_len)
	return m

static func _plain(c: Color, rough: float = 0.6, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

static func eye_material() -> StandardMaterial3D:
	var m := _plain(Color(0.02, 0.018, 0.015), 0.05)
	m.metallic_specular = 1.0
	return m

# ============================ геометрия ============================

## Кольцо сечения: {z, y, w (полуширина), h (полувысота), x? , flat? (0..1 — плоское брюхо)}.
## Лофт по кольцам с гладкими нормалями и крышками. bend0/bend1 — z начала/конца хвоста для COLOR.b.
static func loft(st: SurfaceTool, rings: Array, radial: int, bend0: float, bend1: float,
		detail_fn: Callable = Callable(), wing: float = 0.0) -> void:
	var base := 0
	var verts: Array[Vector3] = []
	var cols: Array[Color] = []
	for ri in rings.size():
		var R: Dictionary = rings[ri]
		var z: float = R["z"]
		var cy: float = R.get("y", 0.0)
		var cx: float = R.get("x", 0.0)
		var w: float = maxf(R["w"], 0.0005)
		var h: float = maxf(R["h"], 0.0005)
		var flat: float = R.get("flat", 0.3)
		for k in radial:
			var a := float(k) / radial * TAU
			var s := sin(a)
			var c := cos(a)
			var yy := s * h
			if yy < 0.0:
				yy *= (1.0 - flat * 0.5)
			var p := Vector3(cx + c * w, cy + yy, z)
			verts.append(p)
			var back := clampf(0.5 + s * 0.9, 0.0, 1.0)
			var bend := clampf((z - bend0) / maxf(bend1 - bend0, 0.001), 0.0, 1.0)
			var g := 0.0
			if detail_fn.is_valid():
				g = float(detail_fn.call(p, s, c, ri))
			cols.append(Color(back, g, bend, wing))
	for ri in rings.size() - 1:
		for k in radial:
			var k2 := (k + 1) % radial
			var a0 := base + ri * radial + k
			var a1 := base + ri * radial + k2
			var b0 := base + (ri + 1) * radial + k
			var b1 := base + (ri + 1) * radial + k2
			_tri(st, verts, cols, a0, b0, a1)
			_tri(st, verts, cols, a1, b0, b1)
	# крышки
	var n := rings.size()
	var c0 := Vector3.ZERO
	var c1 := Vector3.ZERO
	for k in radial:
		c0 += verts[k]
		c1 += verts[(n - 1) * radial + k]
	c0 /= radial
	c1 /= radial
	for k in radial:
		var k2 := (k + 1) % radial
		st.set_color(cols[k]); st.add_vertex(c0)
		st.set_color(cols[k]); st.add_vertex(verts[k])
		st.set_color(cols[k2]); st.add_vertex(verts[k2])
		var o := (n - 1) * radial
		st.set_color(cols[o + k]); st.add_vertex(c1)
		st.set_color(cols[o + k2]); st.add_vertex(verts[o + k2])
		st.set_color(cols[o + k]); st.add_vertex(verts[o + k])

static func _tri(st: SurfaceTool, v: Array[Vector3], c: Array[Color], i0: int, i1: int, i2: int) -> void:
	st.set_color(c[i0]); st.add_vertex(v[i0])
	st.set_color(c[i1]); st.add_vertex(v[i1])
	st.set_color(c[i2]); st.add_vertex(v[i2])

static func commit(st: SurfaceTool) -> ArrayMesh:
	st.index()
	st.generate_normals()
	return st.commit()

static func begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

## Конический сегмент (лапа, палец, коготь) от a до b с радиусами r0→r1.
static func tube(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float, radial: int = 7,
		col: Color = Color(0.5, 0.0, 0.0, 0.0), caps: bool = false) -> void:
	var dir := (b - a)
	var L := dir.length()
	if L < 0.0001:
		return
	dir /= L
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var u := dir.cross(up).normalized()
	var v := dir.cross(u).normalized()
	var ring0: Array[Vector3] = []
	var ring1: Array[Vector3] = []
	for k in radial:
		var ang := float(k) / radial * TAU
		var off := u * cos(ang) + v * sin(ang)
		ring0.append(a + off * r0)
		ring1.append(b + off * r1)
	for k in radial:
		var k2 := (k + 1) % radial
		for p in [ring0[k], ring1[k], ring0[k2], ring0[k2], ring1[k], ring1[k2]]:
			st.set_color(col)
			st.add_vertex(p)
		if caps:
			for p in [a, ring0[k2], ring0[k], b, ring1[k], ring1[k2]]:
				st.set_color(col)
				st.add_vertex(p)

## Эллипсоид.
static func ellipsoid(st: SurfaceTool, c: Vector3, r: Vector3, seg: int = 10, col: Color = Color(0.6, 0.0, 0.0, 0.0),
		back_fn: bool = true) -> void:
	var rings := seg / 2 + 1
	var pts: Array = []
	for i in rings:
		var phi := PI * float(i) / (rings - 1)
		var row: Array = []
		for k in seg + 1:
			var th := TAU * float(k) / seg
			row.append(c + Vector3(sin(phi) * cos(th) * r.x, cos(phi) * r.y, sin(phi) * sin(th) * r.z))
		pts.append(row)
	for i in rings - 1:
		for k in seg:
			var q := [pts[i][k], pts[i + 1][k], pts[i][k + 1], pts[i][k + 1], pts[i + 1][k], pts[i + 1][k + 1]]
			for p: Vector3 in q:
				var cc := col
				if back_fn:
					cc.r = clampf(0.5 + (p.y - c.y) / maxf(r.y, 0.001) * 0.9, 0.0, 1.0)
				st.set_color(cc)
				st.add_vertex(p)

## Плоская перепонка/крыло: многоугольник-веер от корня по точкам контура (двусторонний).
static func membrane(st: SurfaceTool, root: Vector3, outline: Array, col: Color) -> void:
	for i in outline.size() - 1:
		var a: Vector3 = outline[i]
		var b: Vector3 = outline[i + 1]
		for tri in [[root, a, b], [root, b, a]]:
			for p: Vector3 in tri:
				var cc := col
				cc.a = clampf(absf(p.x) / 0.05, 0.0, 1.0) * col.a
				st.set_color(cc)
				st.add_vertex(p)

static func mesh_node(mesh: Mesh, mat: Material, name_: String = "Part") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name_
	mi.mesh = mesh
	mi.material_override = mat
	return mi

static func _pivot(parent: Node3D, name_: String, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.name = name_
	p.position = pos
	parent.add_child(p)
	return p

static func _eyes(parent: Node3D, positions: Array, r: float) -> void:
	var em := SphereMesh.new()
	em.radius = r
	em.height = r * 2.0
	em.radial_segments = 10
	em.rings = 6
	var mat := eye_material()
	for p: Vector3 in positions:
		var e := MeshInstance3D.new()
		e.mesh = em
		e.material_override = mat
		e.position = p
		parent.add_child(e)

## Кэш мешей по ключу.
static func cached(key: String, maker: Callable) -> ArrayMesh:
	if _cache.has(key):
		return _cache[key]
	var m: ArrayMesh = maker.call()
	_cache[key] = m
	return m

# ============================ сборка видов ============================

static func build(species: StringName) -> Node3D:
	var rig := FaunaAnim.build_model(species)
	if rig != null:
		return rig
	match species:
		&"boar": return _boar()
		&"crab": return _crab()
		&"coconut_crab": return _coconut_crab()
		&"snake": return _snake()
		&"croc": return _croc()
		&"monkey": return _monkey()
		&"iguana": return _lizard(&"iguana", 1.25)
		&"monitor": return _lizard(&"monitor", 1.7)
		&"scorpion": return _scorpion()
		&"spider": return _spider()
		&"parrot": return _bird(&"parrot")
		&"gull": return _bird(&"gull")
		&"bat": return _bat()
		&"turtle": return _turtle()
	return _boar()

static func _root(species: StringName, body_len: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Model_" + String(species)
	var mat := make_material(species, body_len)
	root.set_meta(&"mat", mat)
	root.set_meta(&"legs", [])
	root.set_meta(&"wings", [])
	root.set_meta(&"tail", null)
	root.set_meta(&"jaw", null)
	return root

static func _add_leg(root: Node3D, mat: Material, mesh: Mesh, pos: Vector3, side: float) -> Node3D:
	var piv := _pivot(root, "Leg", pos)
	var mi := mesh_node(mesh, mat, "LegMesh")
	mi.scale.x = side
	piv.add_child(mi)
	var legs: Array = root.get_meta(&"legs")
	legs.append(piv)
	return piv

# ---------------------------- кабан ----------------------------
static func _boar() -> Node3D:
	var L := 1.4
	var root := _root(&"boar", L)
	var mat: ShaderMaterial = root.get_meta(&"mat")
	var body := cached("boar_body", func() -> ArrayMesh:
		var st := begin()
		# клиновидная голова, мощная холка, туловище сужается к крупу
		var prof := [
			[-0.8, 0.41, 0.04, 0.04], [-0.78, 0.41, 0.055, 0.052], [-0.72, 0.43, 0.065, 0.065], [-0.62, 0.46, 0.085, 0.09],
			[-0.5, 0.52, 0.12, 0.14], [-0.38, 0.57, 0.165, 0.2], [-0.24, 0.61, 0.21, 0.26], [-0.08, 0.62, 0.225, 0.27],
			[0.1, 0.6, 0.215, 0.25], [0.28, 0.6, 0.2, 0.23], [0.43, 0.6, 0.165, 0.2], [0.54, 0.6, 0.1, 0.13], [0.6, 0.6, 0.02, 0.03]]
		var rings: Array = []
		for p in prof:
			rings.append({"z": p[0], "y": p[1], "w": p[2], "h": p[3], "flat": 0.35})
		loft(st, rings, 18, 2.0, 3.0, func(_p: Vector3, _s: float, _c: float, ri: int) -> float:
			return 0.8 if ri <= 1 else 0.0) # пятачок
		# грива — щетина по хребту
		for i in 12:
			var z := -0.42 + i * 0.065
			var top := 0.86 - absf(z + 0.1) * 0.12
			tube(st, Vector3(0, top - 0.03, z), Vector3(0, top + 0.07 - i * 0.004, z + 0.05), 0.035, 0.004, 5, Color(1, 0, 0, 0))
		# клыки
		for sx: float in [-1.0, 1.0]:
			tube(st, Vector3(sx * 0.055, 0.41, -0.66), Vector3(sx * 0.09, 0.49, -0.7), 0.012, 0.003, 5, Color(0.5, 1.0, 0.0, 0.0), true)
		# уши
		for sx: float in [-1.0, 1.0]:
			tube(st, Vector3(sx * 0.08, 0.64, -0.43), Vector3(sx * 0.13, 0.74, -0.37), 0.035, 0.008, 5, Color(1, 0, 0, 0), true)
		# хвостик с кисточкой
		tube(st, Vector3(0, 0.66, 0.58), Vector3(0, 0.5, 0.66), 0.014, 0.008, 5, Color(1, 0, 0, 0), true)
		return commit(st))
	root.add_child(mesh_node(body, mat, "Body"))
	var leg := cached("boar_leg", func() -> ArrayMesh:
		var st := begin()
		tube(st, Vector3(0, 0.08, 0), Vector3(0, -0.22, 0.02), 0.085, 0.055, 9, Color(0.65, 0, 0, 0))
		tube(st, Vector3(0, -0.22, 0.02), Vector3(0, -0.42, -0.01), 0.05, 0.033, 8, Color(0.85, 0, 0, 0))
		tube(st, Vector3(0, -0.42, -0.01), Vector3(0, -0.48, -0.04), 0.034, 0.03, 7, Color(1.0, 0.0, 0, 0), true) # копыто (тёмное)
		return commit(st))
	for p in [[-0.12, 0.48, -0.22], [0.12, 0.48, -0.22], [-0.13, 0.48, 0.36], [0.13, 0.48, 0.36]]:
		_add_leg(root, mat, leg, Vector3(p[0], p[1], p[2]), 1.0)
	_eyes(root, [Vector3(-0.112, 0.58, -0.49), Vector3(0.112, 0.58, -0.49)], 0.015)
	root.set_meta(&"length", L)
	return root

# ---------------------------- краб ----------------------------
static func _crab() -> Node3D:
	var root := _root(&"crab", 0.3)
	if UserCrabRig.available():
		UserCrabRig.make_model(root)     # модель из пака пользователя (скелет + IK)
	else:
		ArthropodRig.build_crab(root, root.get_meta(&"mat"))
	root.set_meta(&"length", 0.3)
	return root

## Пальмовый вор (v5.2): своей модели пока нет (в списке моделей) — модель краба пользователя
## ×1.9 внутри обёртки (Animal ставит масштаб корня = рост, поэтому масштаб — у вложенного узла).
static func _coconut_crab() -> Node3D:
	var inner := _crab()
	inner.scale = Vector3.ONE * 1.9
	var root := Node3D.new()
	root.name = "CoconutCrab"
	root.add_child(inner)
	for k in inner.get_meta_list():
		root.set_meta(k, inner.get_meta(k))
	root.set_meta(&"length", 0.55)
	root.set_meta(&"display_name", "Пальмовый вор")
	return root

# ---------------------------- змея ----------------------------
static func _snake() -> Node3D:
	var L := 1.6
	var root := _root(&"snake", L)
	var mat: ShaderMaterial = root.get_meta(&"mat")
	var body := cached("snake_body", func() -> ArrayMesh:
		var st := begin()
		var rings: Array = []
		var n := 40
		for i in n + 1:
			var t := float(i) / n
			var z := lerpf(-L * 0.5, L * 0.5, t)
			var w := 0.034
			if t < 0.04:
				w = lerpf(0.012, 0.03, t / 0.04)        # кончик морды
			elif t < 0.09:
				w = lerpf(0.03, 0.036, (t - 0.04) / 0.05) # голова шире
			elif t < 0.12:
				w = lerpf(0.036, 0.024, (t - 0.09) / 0.03) # шея
			elif t < 0.3:
				w = lerpf(0.024, 0.036, (t - 0.12) / 0.18)
			elif t > 0.75:
				w = lerpf(0.034, 0.003, (t - 0.75) / 0.25)
			var h := w * (0.72 if t < 0.09 else 0.85)
			rings.append({"z": z, "y": h * 0.95, "w": w, "h": h, "flat": 0.7})
		loft(st, rings, 10, -L * 0.42, L * 0.5, func(p: Vector3, s: float, c: float, ri: int) -> float:
			return 0.35 if ri < 4 and s > 0.0 else 0.0)
		# язык
		tube(st, Vector3(0, 0.02, -L * 0.5), Vector3(0, 0.018, -L * 0.5 - 0.05), 0.002, 0.001, 4, Color(0.5, 0, 0, 0))
		return commit(st))
	var mi := mesh_node(body, mat, "Body")
	root.add_child(mi)
	mat.set_shader_parameter(&"bend_amp", 0.06)
	mat.set_shader_parameter(&"bend_freq", 1.6)
	mat.set_shader_parameter(&"bend_speed", 4.0)
	_eyes(root, [Vector3(-0.022, 0.035, -L * 0.5 + 0.045), Vector3(0.022, 0.035, -L * 0.5 + 0.045)], 0.006)
	root.set_meta(&"length", L)
	root.set_meta(&"anim", ReptileAnim.new())
	return root

# ---------------------------- крокодил ----------------------------
static func _croc() -> Node3D:
	var L := 3.4
	var root := _root(&"croc", L)
	var mat: ShaderMaterial = root.get_meta(&"mat")
	var body := cached("croc_body", func() -> ArrayMesh:
		var st := begin()
		var rings: Array = []
		var prof := [
			[-1.7, 0.03, 0.015], [-1.66, 0.07, 0.035], [-1.5, 0.085, 0.045], [-1.3, 0.11, 0.06],
			[-1.12, 0.15, 0.09], [-1.0, 0.19, 0.11], [-0.85, 0.2, 0.12], [-0.7, 0.24, 0.15],
			[-0.4, 0.33, 0.18], [-0.1, 0.36, 0.19], [0.15, 0.33, 0.18], [0.35, 0.24, 0.16],
			[0.6, 0.16, 0.14], [0.9, 0.11, 0.12], [1.2, 0.07, 0.09], [1.5, 0.035, 0.06], [1.7, 0.008, 0.02]]
		for p in prof:
			var z: float = p[0]
			rings.append({"z": z, "y": 0.22 + (0.0 if z > -1.1 else (z + 1.1) * 0.05), "w": p[1], "h": p[2], "flat": 0.85})
		loft(st, rings, 14, -0.2, 1.7, func(p: Vector3, s: float, c: float, ri: int) -> float:
			return 0.0)
		# гребень из щитков по спине и хвосту
		for i in 26:
			var z := -0.65 + i * 0.09
			var half := 0.12 * (1.0 - float(i) / 26.0) + 0.02
			for sx: float in ([-1.0, 1.0] if i < 14 else [0.0]):
				var x := sx * half * 0.6
				var y := 0.22 + 0.17 * (1.0 - clampf((z - 0.0) / 1.7, 0.0, 1.0))
				if z < 0.0: y = 0.22 + 0.18
				tube(st, Vector3(x, y - 0.01, z), Vector3(x, y + 0.045, z + 0.02), 0.022, 0.004, 4,
					Color(1.0, 0.0, clampf((z + 0.2) / 1.9, 0.0, 1.0), 0.0))
		# ноздри и бугры глаз
		for sx: float in [-1.0, 1.0]:
			ellipsoid(st, Vector3(sx * 0.075, 0.33, -0.98), Vector3(0.035, 0.03, 0.045), 8, Color(0.9, 0, 0, 0), false)
			ellipsoid(st, Vector3(sx * 0.02, 0.22, -1.62), Vector3(0.016, 0.012, 0.018), 6, Color(0.9, 0, 0, 0), false)
		# зубы вдоль пасти
		for i in 12:
			var z := -1.62 + i * 0.05
			for sx: float in [-1.0, 1.0]:
				var w := 0.068 + i * 0.006
				var ty := 0.2 + (z + 1.1) * 0.05
				tube(st, Vector3(sx * w, ty, z), Vector3(sx * w, ty - 0.03, z), 0.006, 0.001, 4, Color(0.5, 1.0, 0, 0), true)
		return commit(st))
	root.add_child(mesh_node(body, mat, "Body"))
	mat.set_shader_parameter(&"bend_amp", 0.025)
	mat.set_shader_parameter(&"bend_freq", 0.7)
	mat.set_shader_parameter(&"bend_speed", 2.0)
	var leg := cached("croc_leg", func() -> ArrayMesh:
		var st := begin()
		tube(st, Vector3(-0.04, 0.02, 0), Vector3(0.2, -0.02, 0.03), 0.07, 0.05, 8, Color(0.8, 0, 0, 0))
		tube(st, Vector3(0.2, -0.02, 0.03), Vector3(0.25, -0.17, -0.01), 0.05, 0.035, 8, Color(0.6, 0, 0, 0))
		ellipsoid(st, Vector3(0.26, -0.18, -0.05), Vector3(0.05, 0.02, 0.06), 8, Color(0.5, 0, 0, 0))
		for k in 4:
			tube(st, Vector3(0.26, -0.18, -0.05), Vector3(0.26 + (k - 1.5) * 0.035, -0.19, -0.13), 0.012, 0.003, 4, Color(0.4, 0, 0, 0), true)
		return commit(st))
	for p in [[-0.2, 0.2, -0.62], [0.2, 0.2, -0.62], [-0.27, 0.2, 0.12], [0.27, 0.2, 0.12]]:
		_add_leg(root, mat, leg, Vector3(p[0], p[1], p[2]), signf(p[0]))
	_eyes(root, [Vector3(-0.085, 0.35, -1.0), Vector3(0.085, 0.35, -1.0)], 0.017)
	root.set_meta(&"length", L)
	root.set_meta(&"anim", ReptileAnim.new())
	return root

# ---------------------------- обезьяна ----------------------------
static func _monkey() -> Node3D:
	var root := _root(&"monkey", 0.9)
	var mat: ShaderMaterial = root.get_meta(&"mat")
	var body := cached("monkey_body", func() -> ArrayMesh:
		var st := begin()
		# туловище наклонено вперёд (на четвереньках голова выше)
		var rings: Array = []
		var prof := [[-0.22, 0.48, 0.03, 0.03], [-0.18, 0.47, 0.1, 0.1], [-0.08, 0.46, 0.13, 0.13], [0.04, 0.44, 0.12, 0.12],
			[0.14, 0.42, 0.11, 0.11], [0.2, 0.41, 0.07, 0.07], [0.23, 0.41, 0.02, 0.02]]
		for p in prof:
			rings.append({"z": p[0], "y": p[1], "w": p[2], "h": p[3], "flat": 0.2})
		loft(st, rings, 14, 0.2, 0.25)
		# голова
		ellipsoid(st, Vector3(0, 0.6, -0.28), Vector3(0.085, 0.09, 0.085), 12, Color(0.8, 0, 0, 0))
		# лицо (светлая маска) и морда
		ellipsoid(st, Vector3(0, 0.58, -0.35), Vector3(0.06, 0.055, 0.035), 10, Color(0.3, 1.0, 0, 0), false)
		# уши
		for sx: float in [-1.0, 1.0]:
			ellipsoid(st, Vector3(sx * 0.085, 0.62, -0.27), Vector3(0.015, 0.028, 0.022), 6, Color(0.4, 1.0, 0, 0), false)
		# хвост дугой
		var prev := Vector3(0, 0.45, 0.22)
		for i in 10:
			var t := float(i + 1) / 10.0
			var p := Vector3(0, 0.45 + sin(t * 2.6) * 0.35, 0.22 + t * 0.35 - t * t * 0.2)
			tube(st, prev, p, 0.022 - t * 0.012, 0.02 - t * 0.012, 6, Color(0.9, 0, t, 0), false)
			prev = p
		return commit(st))
	root.add_child(mesh_node(body, mat, "Body"))
	var arm := cached("monkey_arm", func() -> ArrayMesh:
		var st := begin()
		tube(st, Vector3(0, 0, 0), Vector3(0, -0.2, -0.03), 0.035, 0.025, 7, Color(0.6, 0, 0, 0))
		tube(st, Vector3(0, -0.2, -0.03), Vector3(0, -0.4, 0.0), 0.025, 0.02, 7, Color(0.5, 0, 0, 0))
		ellipsoid(st, Vector3(0, -0.41, -0.015), Vector3(0.025, 0.012, 0.035), 6, Color(0.2, 1.0, 0, 0), false)
		return commit(st))
	for p in [[-0.1, 0.44, -0.14], [0.1, 0.44, -0.14], [-0.1, 0.42, 0.14], [0.1, 0.42, 0.14]]:
		_add_leg(root, mat, arm, Vector3(p[0], p[1], p[2]), 1.0)
	_eyes(root, [Vector3(-0.028, 0.615, -0.355), Vector3(0.028, 0.615, -0.355)], 0.011)
	root.set_meta(&"length", 0.6)
	return root

# ---------------------------- игуана / варан ----------------------------
static func _lizard(species: StringName, L: float) -> Node3D:
	if UserLizardRig.available():
		return UserLizardRig.make_model(species, L)   # ящерица из пака пользователя (скелет)
	var root := _root(species, L)
	var mat: ShaderMaterial = root.get_meta(&"mat")
	var is_monitor := species == &"monitor"
	var body := cached("lizard_" + String(species), func() -> ArrayMesh:
		var st := begin()
		var rings: Array = []
		# голова ~12%, тело ~33%, хвост ~55%
		var pts := [[0.0, 0.006], [0.02, 0.025], [0.07, 0.042], [0.11, 0.04], [0.14, 0.032], [0.18, 0.055],
			[0.26, 0.075], [0.36, 0.075], [0.44, 0.06], [0.5, 0.045], [0.6, 0.034], [0.72, 0.024], [0.86, 0.013], [1.0, 0.002]]
		var sc := L / 1.25
		for p in pts:
			var z: float = (p[0] - 0.45) * L
			var w: float = p[1] * sc * (1.0 if not is_monitor else 1.05)
			rings.append({"z": z, "y": 0.08 * sc, "w": w, "h": w * (0.75 if p[0] > 0.12 else 0.6), "flat": 0.6})
		loft(st, rings, 12, -0.0, L * 0.55, func(p: Vector3, s: float, c: float, ri: int) -> float:
			return 0.0)
		if not is_monitor:
			# гребень игуаны
			for i in 22:
				var z := (-0.3 + i * 0.03) * L
				var hgt := 0.05 * sc * (1.0 - absf(i - 6.0) / 22.0)
				# основание шипа — на верхней линии спины (сужается к хвосту)
				var tt := z / L + 0.45
				var ww := 0.002
				for q in pts.size() - 1:
					if tt >= float(pts[q][0]) and tt <= float(pts[q + 1][0]):
						ww = lerpf(float(pts[q][1]), float(pts[q + 1][1]), (tt - float(pts[q][0])) / (float(pts[q + 1][0]) - float(pts[q][0])))
				var by := 0.08 * sc + ww * sc * 0.7
				tube(st, Vector3(0, by, z), Vector3(0, by + hgt, z + 0.012), 0.006, 0.001, 4,
					Color(1, 0.6, clampf((z) / (L * 0.55), 0.0, 1.0), 0))
			# горловой мешок
			ellipsoid(st, Vector3(0, 0.05 * sc, -0.355 * L), Vector3(0.007 * sc, 0.03 * sc, 0.045 * sc), 8, Color(0.2, 0.25, 0, 0), false)
		else:
			# раздвоенный язык
			tube(st, Vector3(0, 0.07 * sc, -0.45 * L), Vector3(0, 0.07 * sc, -0.45 * L - 0.08), 0.003, 0.0015, 4, Color(0.5, 1.0, 0, 0))
		return commit(st))
	root.add_child(mesh_node(body, mat, "Body"))
	mat.set_shader_parameter(&"bend_amp", 0.035)
	mat.set_shader_parameter(&"bend_freq", 1.0)
	mat.set_shader_parameter(&"bend_speed", 0.0)
	var sc := L / 1.25
	var leg := cached("lizard_leg_" + String(species), func() -> ArrayMesh:
		var st := begin()
		# ящеричная постановка: плечо в сторону, предплечье вниз-наружу, растопыренные пальцы
		tube(st, Vector3(0, 0, 0), Vector3(0.1 * sc, 0.012 * sc, 0.0), 0.024 * sc, 0.017 * sc, 7, Color(0.75, 0, 0, 0))
		tube(st, Vector3(0.1 * sc, 0.012 * sc, 0.0), Vector3(0.125 * sc, -0.07 * sc, -0.01), 0.017 * sc, 0.011 * sc, 6, Color(0.6, 0, 0, 0))
		for k in 5:
			tube(st, Vector3(0.125 * sc, -0.07 * sc, -0.01), Vector3(0.125 * sc + (k - 2) * 0.016 * sc, -0.076 * sc, -0.05 * sc + absf(k - 2.0) * 0.01 * sc), 0.0045 * sc, 0.0015, 4, Color(0.5, 0, 0, 0))
		return commit(st))
	for p in [[-0.04, -0.22], [0.04, -0.22], [-0.045, 0.04], [0.045, 0.04]]:
		_add_leg(root, mat, leg, Vector3(p[0] * sc, 0.075 * sc, p[1] * L), signf(p[0]))
	_eyes(root, [Vector3(-0.026 * sc, 0.095 * sc, -0.4 * L), Vector3(0.026 * sc, 0.095 * sc, -0.4 * L)], 0.007 * sc)
	root.set_meta(&"length", L)
	root.set_meta(&"anim", ReptileAnim.new())
	return root

# ---------------------------- скорпион ----------------------------
static func _scorpion() -> Node3D:
	var root := _root(&"scorpion", 0.2)
	ArthropodRig.build_scorpion(root, root.get_meta(&"mat"))
	root.set_meta(&"length", 0.2)
	return root

# ---------------------------- паук (птицеед) ----------------------------
static func _spider() -> Node3D:
	if UserSpiderRig.spider_available():
		var ur := _root(&"spider", 0.22)
		UserSpiderRig.make_spider(ur)     # паук-птицеед пользователя (скелет автора + IK)
		ur.set_meta(&"length", 0.22)
		return ur
	var root := _root(&"spider", 0.15)
	ArthropodRig.build_spider(root, root.get_meta(&"mat"))
	root.set_meta(&"length", 0.15)
	return root

# ---------------------------- птицы ----------------------------
static func _bird(species: StringName) -> Node3D:
	var parrot := species == &"parrot"
	var L := 0.85 if parrot else 0.5
	var root := _root(species, L)
	var mat: ShaderMaterial = root.get_meta(&"mat")
	var body := cached("bird_body_" + String(species), func() -> ArrayMesh:
		var st := begin()
		var rings: Array = []
		var prof := [[-0.13, 0.01], [-0.11, 0.035], [-0.07, 0.05], [0.0, 0.058], [0.06, 0.048], [0.11, 0.03], [0.14, 0.012]]
		for p in prof:
			rings.append({"z": p[0], "y": 0.0, "w": p[1], "h": p[1] * 1.05, "flat": 0.1})
		loft(st, rings, 12, 0.0, 0.2)
		# голова
		ellipsoid(st, Vector3(0, 0.035, -0.15), Vector3(0.038, 0.04, 0.042), 10, Color(0.7, 0.0, 0, 0))
		if parrot:
			# жёлто-синие крылья/щека: детали
			ellipsoid(st, Vector3(0, 0.03, -0.172), Vector3(0.025, 0.022, 0.02), 8, Color(0.2, 1.0, 0, 0), false)
			# клюв изогнутый (тёмный)
			tube(st, Vector3(0, 0.04, -0.185), Vector3(0, 0.0, -0.215), 0.016, 0.003, 6, Color(0.0, 0.0, 0, 0))
			# длинный хвост
			tube(st, Vector3(0, 0.0, 0.12), Vector3(0, -0.04, 0.48), 0.025, 0.006, 6, Color(1.0, 0.0, 0, 0))
		else:
			tube(st, Vector3(0, 0.03, -0.185), Vector3(0, 0.02, -0.235), 0.009, 0.003, 5, Color(0.5, 1.0, 0, 0))
			tube(st, Vector3(0, 0.0, 0.12), Vector3(0, 0.0, 0.2), 0.03, 0.02, 6, Color(1.0, 0.0, 0, 0))
		# лапки
		for sx: float in [-1.0, 1.0]:
			tube(st, Vector3(sx * 0.02, -0.04, 0.0), Vector3(sx * 0.02, -0.09, 0.01), 0.005, 0.004, 4, Color(0.0, 0.0, 0, 0))
		return commit(st))
	root.add_child(mesh_node(body, mat, "Body"))
	# крылья — отдельный меш с маской a (взмах в шейдере)
	var span := 0.55 if parrot else 0.6
	var wings := cached("bird_wings_" + String(species), func() -> ArrayMesh:
		var st := begin()
		for sx: float in [-1.0, 1.0]:
			var outline := [Vector3(sx * 0.04, 0.02, -0.07), Vector3(sx * span * 0.45, 0.025, -0.06),
				Vector3(sx * span * 0.85, 0.01, -0.01), Vector3(sx * span, 0.0, 0.05), Vector3(sx * span * 0.7, 0.0, 0.09),
				Vector3(sx * span * 0.35, 0.01, 0.1), Vector3(sx * 0.04, 0.02, 0.07)]
			membrane(st, Vector3(sx * 0.03, 0.02, 0.0), outline, Color(1.0, 0.0 if not parrot else 0.0, 0, 1.0))
		return commit(st))
	var wm := mat.duplicate() as ShaderMaterial
	if parrot:
		wm.set_shader_parameter(&"back_color", Color(0.12, 0.32, 0.8))
		wm.set_shader_parameter(&"belly_color", Color(0.9, 0.75, 0.15))
	else:
		wm.set_shader_parameter(&"back_color", Color(0.55, 0.58, 0.62))
	wm.set_shader_parameter(&"wing_span", span)
	var wmi := mesh_node(wings, wm, "Wings")
	wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	root.add_child(wmi)
	(root.get_meta(&"wings") as Array).append(wmi)
	_eyes(root, [Vector3(-0.03, 0.05, -0.165), Vector3(0.03, 0.05, -0.165)], 0.006)
	root.set_meta(&"length", L)
	return root

static func _bat() -> Node3D:
	var root := _root(&"bat", 0.12)
	var mat: ShaderMaterial = root.get_meta(&"mat")
	var body := cached("bat_body", func() -> ArrayMesh:
		var st := begin()
		ellipsoid(st, Vector3(0, 0, 0), Vector3(0.028, 0.03, 0.05), 10, Color(0.6, 0, 0, 0))
		ellipsoid(st, Vector3(0, 0.01, -0.055), Vector3(0.02, 0.02, 0.022), 8, Color(0.6, 0, 0, 0))
		for sx: float in [-1.0, 1.0]:
			tube(st, Vector3(sx * 0.01, 0.025, -0.06), Vector3(sx * 0.018, 0.055, -0.058), 0.008, 0.002, 4, Color(0.5, 0, 0, 0))
		return commit(st))
	root.add_child(mesh_node(body, mat, "Body"))
	var wings := cached("bat_wings", func() -> ArrayMesh:
		var st := begin()
		for sx: float in [-1.0, 1.0]:
			var outline := [Vector3(sx * 0.02, 0.0, -0.03), Vector3(sx * 0.12, 0.02, -0.05), Vector3(sx * 0.25, 0.0, -0.02),
				Vector3(sx * 0.2, 0.0, 0.03), Vector3(sx * 0.15, 0.0, 0.02), Vector3(sx * 0.1, 0.0, 0.05), Vector3(sx * 0.02, 0.0, 0.04)]
			membrane(st, Vector3(sx * 0.02, 0.0, 0.0), outline, Color(0.8, 0.0, 0, 1.0))
		return commit(st))
	var wm := mat.duplicate() as ShaderMaterial
	wm.set_shader_parameter(&"back_color", Color(0.12, 0.09, 0.08))
	wm.set_shader_parameter(&"belly_color", Color(0.18, 0.13, 0.11))
	wm.set_shader_parameter(&"pattern_kind", 0.0)
	var wmi := mesh_node(wings, wm, "Wings")
	root.add_child(wmi)
	(root.get_meta(&"wings") as Array).append(wmi)
	root.set_meta(&"length", 0.12)
	return root

# ---------------------------- черепаха ----------------------------
static func _turtle() -> Node3D:
	var root := _root(&"turtle", 1.0)
	var mat: ShaderMaterial = root.get_meta(&"mat")
	var body := cached("turtle_body", func() -> ArrayMesh:
		var st := begin()
		var rings: Array = []
		var prof := [[-0.46, 0.06, 0.02], [-0.42, 0.25, 0.09], [-0.3, 0.38, 0.16], [-0.1, 0.44, 0.2], [0.1, 0.43, 0.19],
			[0.28, 0.36, 0.14], [0.4, 0.22, 0.08], [0.46, 0.05, 0.02]]
		for p in prof:
			rings.append({"z": p[0], "y": 0.16, "w": p[1], "h": p[2], "flat": 0.95})
		loft(st, rings, 18, 1.0, 2.0)
		# голова и шея (кожа, светлая деталь)
		tube(st, Vector3(0, 0.15, -0.42), Vector3(0, 0.17, -0.58), 0.065, 0.055, 8, Color(0.6, 0.6, 0, 0))
		ellipsoid(st, Vector3(0, 0.18, -0.63), Vector3(0.065, 0.055, 0.08), 10, Color(0.6, 0.6, 0, 0))
		# хвостик
		tube(st, Vector3(0, 0.12, 0.45), Vector3(0, 0.1, 0.55), 0.03, 0.008, 5, Color(0.6, 0.6, 0, 0))
		return commit(st))
	root.add_child(mesh_node(body, mat, "Body"))
	var flipper := cached("turtle_flipper", func() -> ArrayMesh:
		var st := begin()
		# плоский ласт: широкая лопасть, сужающаяся к кончику
		ellipsoid(st, Vector3(0.06, 0.0, 0.0), Vector3(0.08, 0.03, 0.05), 8, Color(0.6, 0.6, 0, 0))
		ellipsoid(st, Vector3(0.22, -0.005, -0.035), Vector3(0.2, 0.02, 0.07), 10, Color(0.6, 0.6, 0, 0))
		ellipsoid(st, Vector3(0.4, -0.012, -0.05), Vector3(0.07, 0.012, 0.035), 6, Color(0.6, 0.6, 0, 0))
		return commit(st))
	for p in [[-0.3, 0.12, -0.25, 0.7], [0.3, 0.12, -0.25, 0.7], [-0.28, 0.12, 0.3, 0.45], [0.28, 0.12, 0.3, 0.45]]:
		var piv := _pivot(root, "Leg", Vector3(p[0], p[1], p[2]))
		var mi := mesh_node(flipper, mat, "LegMesh")
		mi.scale = Vector3(signf(p[0]) * p[3], p[3], p[3])
		piv.add_child(mi)
		(root.get_meta(&"legs") as Array).append(piv)
	_eyes(root, [Vector3(-0.05, 0.2, -0.67), Vector3(0.05, 0.2, -0.67)], 0.012)
	root.set_meta(&"length", 1.0)
	root.set_meta(&"anim", ReptileAnim.new())
	return root
