class_name CombatModels
extends RefCounted
## Процедурные модели оружия (вид от первого лица и предметы на земле).
## Соглашение HeldModels: корень — точка хвата правой руки, +Y вверх по рукояти, -Z вперёд.
## Детали — «лофт» (труба из эллиптических сечений вдоль кривой), PBR-текстуры:
## орех ложи (walnut_stock), воронёное железо (gun_iron), латунь (brass_old) —
## сгенерированы tools/gen_tex.py; дерево/кора/верёвка/ткань — из assets/textures (CC0).
## Маркеры: "Muzzle" (дуло/наконечник), "Sight" (целик — по нему выравнивается ПКМ).

static var _mats: Dictionary = {}

## Вызывается из HeldModels.build для неизвестных ему id. true — модель построена.
static func build_into(root: Node3D, id: StringName) -> bool:
	match id:
		&"club": _club(root)
		&"bow": _bow(root, true)
		&"crossbow": _crossbow(root)
		&"musket": _musket(root)
		&"pistol": _pistol(root)
		&"arrow": _arrow(root, false)
		&"arrow_fire": _arrow(root, true)
		&"bolt": _bolt(root)
		&"musket_ball": _balls(root)
		&"gunpowder": _powder_horn(root)
		&"molotov": _molotov(root)
		&"dynamite": _dynamite(root)
		&"spirit": _spirit(root)
		&"charcoal": _lumps(root, mat("charcoal"))
		&"saltpeter": _lumps(root, HeldModels.color_mat(Color(0.88, 0.87, 0.82), 0.9))
		&"lead": _lumps(root, mat("iron"))
		&"iron_parts": _iron_parts(root)
		_: return false
	return true

# ======================= материалы =======================

static func mat(kind: String) -> Material:
	if _mats.has(kind):
		return _mats[kind]
	var m: Material
	match kind:
		"walnut": m = HeldModels.pbr("walnut_stock", Vector3(1.0, 1.0, 1.0))
		"walnut_tip":
			var w := HeldModels.pbr("walnut_stock", Vector3(1.0, 2.0, 1.0)).duplicate() as StandardMaterial3D
			w.clearcoat_enabled = true
			w.clearcoat = 0.4
			w.clearcoat_roughness = 0.5
			m = w
		"iron":
			var i := HeldModels.pbr("gun_iron", Vector3(1.0, 1.0, 1.0)).duplicate() as StandardMaterial3D
			i.metallic = 0.85
			m = i
		"brass":
			var b := HeldModels.pbr("brass_old", Vector3(1.0, 1.0, 1.0)).duplicate() as StandardMaterial3D
			b.metallic = 0.95
			m = b
		"wood": m = HeldModels.pbr("rough_wood", Vector3(1.0, 3.0, 1.0), Color(0.85, 0.75, 0.65))
		"bark": m = HeldModels.pbr("bark_brown_02", Vector3(1.0, 2.0, 1.0))
		"rope": m = HeldModels.pbr("Rope001", Vector3(4.0, 1.0, 1.0))
		"cloth": m = HeldModels.pbr("Fabric004", Vector3(1.0, 1.0, 1.0), Color(0.8, 0.74, 0.62))
		"cloth_dark": m = HeldModels.pbr("Fabric004", Vector3(1.0, 1.0, 1.0), Color(0.45, 0.35, 0.25))
		"leather": m = HeldModels.pbr("Fabric004", Vector3(2.0, 2.0, 1.0), Color(0.35, 0.2, 0.1))
		"stone": m = HeldModels.pbr("dark_rock", Vector3(0.5, 0.5, 0.5))
		"string": m = HeldModels.color_mat(Color(0.78, 0.74, 0.62), 0.9)
		"feather":
			var f := HeldModels.color_mat(Color(0.82, 0.8, 0.76), 0.85)
			f.cull_mode = BaseMaterial3D.CULL_DISABLED
			m = f
		"feather_dark":
			var f2 := HeldModels.color_mat(Color(0.18, 0.16, 0.15), 0.85)
			f2.cull_mode = BaseMaterial3D.CULL_DISABLED
			m = f2
		"glass":
			var g := StandardMaterial3D.new()
			g.albedo_color = Color(0.32, 0.42, 0.25, 0.42)
			g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			g.roughness = 0.05
			g.metallic_specular = 0.9
			g.rim_enabled = true
			g.rim = 0.4
			g.cull_mode = BaseMaterial3D.CULL_BACK
			m = g
		"liquid":
			var l := StandardMaterial3D.new()
			l.albedo_color = Color(0.75, 0.55, 0.18, 0.75)
			l.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			l.roughness = 0.1
			m = l
		"paper_red": m = HeldModels.pbr("Fabric004", Vector3(0.5, 2.0, 1.0), Color(0.75, 0.16, 0.12))
		"tape": m = HeldModels.pbr("Fabric004", Vector3(2.0, 0.5, 1.0), Color(0.55, 0.5, 0.42))
		"fuse": m = HeldModels.pbr("Rope001", Vector3(1.0, 6.0, 1.0), Color(0.3, 0.27, 0.22))
		"charcoal": m = HeldModels.pbr("dark_rock", Vector3(0.3, 0.3, 0.3), Color(0.22, 0.22, 0.22))
		"horn":
			var h := HeldModels.color_mat(Color(0.72, 0.6, 0.42), 0.4)
			h.clearcoat_enabled = true
			m = h
		_: m = HeldModels.color_mat(Color.MAGENTA)
	_mats[kind] = m
	return m

# ======================= лофт =======================

## Труба по точкам pts с полуосями rad[i] = (по "ref"-оси, поперёк). Сечения — эллипсы.
static func loft(pts: PackedVector3Array, rad: Array, ref: Vector3 = Vector3.UP, segs: int = 12, uv_len: float = 1.0, caps: bool = true) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := pts.size()
	var rings: Array[PackedVector3Array] = []
	var vcoord: Array[float] = []
	var acc := 0.0
	for i in n:
		var t: Vector3
		if i == 0:
			t = pts[1] - pts[0]
		elif i == n - 1:
			t = pts[n - 1] - pts[n - 2]
		else:
			t = pts[i + 1] - pts[i - 1]
		t = t.normalized()
		var a := ref - t * ref.dot(t)
		if a.length() < 0.001:
			a = Vector3.FORWARD - t * Vector3.FORWARD.dot(t)
		a = a.normalized()
		var b := t.cross(a).normalized()
		var r: Vector2 = rad[i]
		var ring := PackedVector3Array()
		for s in segs + 1:
			var ang := TAU * float(s) / float(segs)
			ring.append(pts[i] + a * cos(ang) * r.x + b * sin(ang) * r.y)
		rings.append(ring)
		if i > 0:
			acc += pts[i].distance_to(pts[i - 1])
		vcoord.append(acc)
	for i in n - 1:
		for s in segs:
			var u0 := float(s) / segs
			var u1 := float(s + 1) / segs
			var v0 := vcoord[i] * uv_len
			var v1 := vcoord[i + 1] * uv_len
			var p00 := rings[i][s]
			var p01 := rings[i][s + 1]
			var p10 := rings[i + 1][s]
			var p11 := rings[i + 1][s + 1]
			st.set_uv(Vector2(u0, v0)); st.add_vertex(p00)
			st.set_uv(Vector2(u1, v0)); st.add_vertex(p01)
			st.set_uv(Vector2(u1, v1)); st.add_vertex(p11)
			st.set_uv(Vector2(u0, v0)); st.add_vertex(p00)
			st.set_uv(Vector2(u1, v1)); st.add_vertex(p11)
			st.set_uv(Vector2(u0, v1)); st.add_vertex(p10)
	if caps:
		for e in [0, n - 1]:
			var c := pts[e]
			for s in segs:
				var q0 := rings[e][s]
				var q1 := rings[e][s + 1]
				st.set_uv(Vector2(0.5, 0.5))
				if e == 0:
					st.add_vertex(c); st.set_uv(Vector2(0.5 + 0.5 * cos(TAU * (s + 1) / segs), 0.5)); st.add_vertex(q1)
					st.set_uv(Vector2(0.5 + 0.5 * cos(TAU * s / segs), 0.5)); st.add_vertex(q0)
				else:
					st.add_vertex(c); st.set_uv(Vector2(0.5 + 0.5 * cos(TAU * s / segs), 0.5)); st.add_vertex(q0)
					st.set_uv(Vector2(0.5 + 0.5 * cos(TAU * (s + 1) / segs), 0.5)); st.add_vertex(q1)
	st.generate_normals()
	st.generate_tangents()
	return st.commit()

static func mesh(parent: Node3D, m: Mesh, material: Material, nm: String = "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material
	if nm != "":
		mi.name = nm
	parent.add_child(mi)
	return mi

static func marker(parent: Node3D, nm: String, pos: Vector3) -> Marker3D:
	var mk := Marker3D.new()
	mk.name = nm
	mk.position = pos
	parent.add_child(mk)
	return mk

## Цилиндр между двумя точками.
static func rod(parent: Node3D, a: Vector3, b: Vector3, r: float, material: Material, segs: int = 8) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = a.distance_to(b)
	cm.radial_segments = segs
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = material
	parent.add_child(mi)
	place_rod(mi, a, b)
	return mi

static func place_rod(mi: Node3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.0001:
		return
	var y := d / len
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	mi.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)
	var cm := (mi as MeshInstance3D).mesh as CylinderMesh if mi is MeshInstance3D else null
	if cm and absf(cm.height - len) > 0.0005:
		cm.height = len

static func ring(parent: Node3D, center: Vector3, r: float, w: float, material: Material, axis_rot: Vector3 = Vector3(PI / 2, 0, 0)) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = w
	cm.radial_segments = 12
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = material
	mi.position = center
	mi.rotation = axis_rot
	parent.add_child(mi)

# ======================= оружие =======================

static func _club(root: Node3D) -> void:
	# толстая палица из комля: рукоять 3 см → навершие 7 см с наростами
	var pts := PackedVector3Array()
	var rad := []
	for i in 12:
		var t := float(i) / 11.0
		var y := lerpf(-0.12, 0.62, t)
		pts.append(Vector3(sin(t * 3.0) * 0.008, y, 0.0))
		var r := lerpf(0.016, 0.05, smoothstep(0.35, 0.95, t)) * (1.0 + 0.08 * sin(t * 17.0))
		if t > 0.96:
			r *= 0.7
		rad.append(Vector2(r, r * 0.92))
	mesh(root, loft(pts, rad, Vector3.FORWARD, 14, 2.0), mat("bark"))
	# сучки на навершии
	for k in 5:
		var a := k * 1.3
		var p := Vector3(cos(a) * 0.045, 0.42 + k * 0.04, sin(a) * 0.045)
		HeldModels._sphere(root, 0.014, mat("bark"), p, Vector3(1.0, 0.7, 1.0), 8)
	# обмотка рукояти
	var wrap := PackedVector3Array([Vector3(0, -0.11, 0), Vector3(0, 0.08, 0)])
	mesh(root, loft(wrap, [Vector2(0.018, 0.018), Vector2(0.018, 0.018)], Vector3.FORWARD, 12, 6.0), mat("leather"))

## Лук: корень — рукоять в ЛЕВОЙ руке. Плечи изогнуты вперёд (-Z). Тетива — узлы "StringTop"/"StringBot"
## (обновляются контроллером), концы плеч — маркеры "TipTop"/"TipBot", полка — "Rest".
static func _bow(root: Node3D, with_string: bool) -> void:
	var pts := PackedVector3Array()
	var rad := []
	var L := 0.66
	for i in 21:
		var t := float(i) / 20.0 * 2.0 - 1.0 # -1..1
		var at := absf(t)
		var z := -0.10 * at * at + 0.03 * smoothstep(0.85, 1.0, at) # изгиб вперёд + рекурв
		pts.append(Vector3(0.0, t * L, z + 0.02))
		var w := lerpf(0.017, 0.006, smoothstep(0.12, 1.0, at))
		var th := lerpf(0.016, 0.0055, smoothstep(0.12, 1.0, at))
		rad.append(Vector2(th, w))
	mesh(root, loft(pts, rad, Vector3.BACK, 10, 1.5), mat("walnut_tip"))
	# обмотка рукояти
	var gp := PackedVector3Array([Vector3(0, -0.07, 0.02), Vector3(0, 0.07, 0.02)])
	mesh(root, loft(gp, [Vector2(0.02, 0.021), Vector2(0.02, 0.021)], Vector3.BACK, 12, 8.0), mat("leather"))
	var tip_top := pts[20]
	var tip_bot := pts[0]
	marker(root, "TipTop", tip_top + Vector3(0, -0.01, 0.006))
	marker(root, "TipBot", tip_bot + Vector3(0, 0.01, 0.006))
	marker(root, "Rest", Vector3(-0.018, 0.08, 0.015))
	if with_string:
		var s1 := rod(root, tip_top, Vector3(0, 0, 0.09), 0.0016, mat("string"), 4)
		s1.name = "StringTop"
		var s2 := rod(root, tip_bot, Vector3(0, 0, 0.09), 0.0016, mat("string"), 4)
		s2.name = "StringBot"
	marker(root, "Sight", Vector3(-0.02, 0.09, 0.0))
	marker(root, "Muzzle", Vector3(-0.02, 0.08, -0.02))

## Стрела вдоль -Z, корень — хвостовик (ушко) у z=0.
static func _arrow(root: Node3D, fire: bool) -> void:
	var len := 0.74
	var sh := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0042
	cm.bottom_radius = 0.0042
	cm.height = len
	cm.radial_segments = 6
	sh.mesh = cm
	sh.material_override = mat("wood")
	sh.rotation = Vector3(PI / 2, 0, 0)
	sh.position = Vector3(0, 0, -len * 0.5)
	root.add_child(sh)
	# каменный наконечник
	var hp := PackedVector3Array([Vector3(0, 0, -len + 0.005), Vector3(0, 0, -len - 0.02), Vector3(0, 0, -len - 0.055)])
	mesh(root, loft(hp, [Vector2(0.004, 0.005), Vector2(0.0035, 0.011), Vector2(0.0004, 0.0008)], Vector3.UP, 6, 4.0), mat("stone"))
	# оперение — три пера
	for k in 3:
		var a := TAU * k / 3.0
		var f := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.016, 0.11)
		f.mesh = qm
		f.material_override = mat("feather_dark" if k == 0 else "feather")
		f.rotation = Vector3(PI / 2, 0, a)
		f.position = Vector3(cos(a + PI / 2) * 0.009, sin(a + PI / 2) * 0.009, -0.075)
		root.add_child(f)
	if fire:
		var wp := PackedVector3Array([Vector3(0, 0, -len + 0.01), Vector3(0, 0, -len + 0.07)])
		mesh(root, loft(wp, [Vector2(0.011, 0.011), Vector2(0.009, 0.009)], Vector3.UP, 8, 6.0), mat("cloth_dark"), "Rag")
	marker(root, "Tip", Vector3(0, 0, -len - 0.05))
	marker(root, "Flame", Vector3(0, 0, -len + 0.04))

static func _bolt(root: Node3D) -> void:
	var len := 0.36
	rod(root, Vector3(0, 0, 0), Vector3(0, 0, -len), 0.0055, mat("wood"), 6)
	var hp := PackedVector3Array([Vector3(0, 0, -len), Vector3(0, 0, -len - 0.02), Vector3(0, 0, -len - 0.045)])
	mesh(root, loft(hp, [Vector2(0.006, 0.006), Vector2(0.007, 0.007), Vector2(0.0005, 0.0005)], Vector3.UP, 6, 4.0), mat("iron"))
	for k in 2:
		var f := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.018, 0.06)
		f.mesh = qm
		f.material_override = mat("feather")
		f.rotation = Vector3(PI / 2, 0, PI / 2 * k)
		f.position = Vector3(0, 0, -0.04)
		root.add_child(f)
	marker(root, "Tip", Vector3(0, 0, -len - 0.045))

## Арбалет: корень — пистолетный хват (правая рука) под ложей.
static func _crossbow(root: Node3D) -> void:
	var by := 0.075 # ось ложи над хватом
	var pts := PackedVector3Array([Vector3(0, by - 0.035, 0.34), Vector3(0, by - 0.02, 0.22), Vector3(0, by - 0.005, 0.1),
		Vector3(0, by, -0.05), Vector3(0, by, -0.3), Vector3(0, by + 0.002, -0.52), Vector3(0, by + 0.004, -0.58)])
	var rad := [Vector2(0.055, 0.022), Vector2(0.05, 0.022), Vector2(0.034, 0.02), Vector2(0.026, 0.022),
		Vector2(0.024, 0.022), Vector2(0.026, 0.024), Vector2(0.02, 0.02)]
	mesh(root, loft(pts, rad, Vector3.UP, 12, 2.0), mat("walnut_tip"))
	# пистолетная рукоять
	var gp := PackedVector3Array([Vector3(0, by - 0.01, 0.0), Vector3(0, 0.02, 0.025), Vector3(0, -0.06, 0.06)])
	mesh(root, loft(gp, [Vector2(0.02, 0.016), Vector2(0.022, 0.016), Vector2(0.024, 0.017)], Vector3.BACK, 10, 2.0), mat("walnut"))
	# дуга (стальной прод) с рекурвом
	var pz := -0.52
	var ap := PackedVector3Array()
	var ar := []
	for i in 15:
		var t := float(i) / 14.0 * 2.0 - 1.0
		ap.append(Vector3(t * 0.31, by + 0.012, pz - 0.05 * t * t + 0.02 * smoothstep(0.8, 1.0, absf(t))))
		var th := lerpf(0.009, 0.004, absf(t))
		ar.append(Vector2(th, lerpf(0.018, 0.008, absf(t))))
	mesh(root, loft(ap, ar, Vector3.UP, 8, 2.0), mat("iron"))
	# стремя
	var sp := PackedVector3Array()
	for i in 9:
		var a := PI * float(i) / 8.0
		sp.append(Vector3(cos(a) * 0.05, by - 0.01 - sin(a) * 0.0, pz - 0.09 - sin(a) * 0.06))
	mesh(root, loft(sp, [Vector2(0.004, 0.004), Vector2(0.004, 0.004), Vector2(0.004, 0.004), Vector2(0.004, 0.004), Vector2(0.004, 0.004),
		Vector2(0.004, 0.004), Vector2(0.004, 0.004), Vector2(0.004, 0.004), Vector2(0.004, 0.004)], Vector3.UP, 6, 1.0), mat("iron"))
	# орех (замок) и спуск
	HeldModels._box(root, Vector3(0.03, 0.02, 0.03), mat("iron"), Vector3(0, by + 0.022, -0.05))
	var tr := PackedVector3Array([Vector3(0, by - 0.02, -0.02), Vector3(0, by - 0.06, -0.0), Vector3(0, by - 0.1, 0.03)])
	mesh(root, loft(tr, [Vector2(0.004, 0.003), Vector2(0.004, 0.003), Vector2(0.003, 0.002)], Vector3.BACK, 6, 1.0), mat("iron"))
	# тетива (узлы обновляет контроллер: натянута на орех / спущена)
	var tip_l := ap[0] + Vector3(0.004, 0, 0.004)
	var tip_r := ap[14] + Vector3(-0.004, 0, 0.004)
	marker(root, "TipL", tip_l)
	marker(root, "TipR", tip_r)
	marker(root, "Nut", Vector3(0, by + 0.024, -0.06))
	marker(root, "Rest", Vector3(0, by + 0.024, pz + 0.02))
	rod(root, tip_l, Vector3(0, by + 0.024, -0.06), 0.0018, mat("string"), 4).name = "StringL"
	rod(root, tip_r, Vector3(0, by + 0.024, -0.06), 0.0018, mat("string"), 4).name = "StringR"
	var bolt := Node3D.new()
	bolt.name = "Bolt"
	bolt.position = Vector3(0, by + 0.03, -0.06)
	root.add_child(bolt)
	_bolt(bolt)
	# прицельная планка
	HeldModels._box(root, Vector3(0.004, 0.022, 0.006), mat("iron"), Vector3(0, by + 0.035, -0.11))
	marker(root, "Sight", Vector3(0, by + 0.047, 0.02))
	marker(root, "Muzzle", Vector3(0, by + 0.03, -0.6))
	marker(root, "Forend", Vector3(0, by - 0.02, -0.33))

## Кремнёвый мушкет. Корень — шейка приклада (правая рука).
static func _musket(root: Node3D) -> void:
	var by := 0.062
	# приклад + шейка + цевьё одной ложей
	var pts := PackedVector3Array([
		Vector3(0, -0.075, 0.46), Vector3(0, -0.06, 0.4), Vector3(0, -0.035, 0.28), Vector3(0, -0.005, 0.15),
		Vector3(0, 0.025, 0.05), Vector3(0, by - 0.022, -0.06), Vector3(0, by - 0.012, -0.2),
		Vector3(0, by - 0.01, -0.6), Vector3(0, by - 0.008, -0.92), Vector3(0, by - 0.006, -0.95)])
	var rad := [Vector2(0.068, 0.021), Vector2(0.066, 0.021), Vector2(0.055, 0.02), Vector2(0.036, 0.017),
		Vector2(0.024, 0.016), Vector2(0.026, 0.019), Vector2(0.021, 0.017),
		Vector2(0.019, 0.016), Vector2(0.017, 0.015), Vector2(0.012, 0.012)]
	mesh(root, loft(pts, rad, Vector3.UP, 14, 1.6), mat("walnut_tip"), "Stock")
	# ствол — граненый у казны, круглый дальше
	var bp := PackedVector3Array([Vector3(0, by, -0.02), Vector3(0, by, -0.2), Vector3(0, by, -0.6), Vector3(0, by, -1.08)])
	mesh(root, loft(bp, [Vector2(0.0145, 0.0145), Vector2(0.0128, 0.0128), Vector2(0.0115, 0.0115), Vector2(0.0105, 0.0105)], Vector3.UP, 12, 1.0, true), mat("iron"), "Barrel")
	HeldModels._box(root, Vector3(0.026, 0.03, 0.05), mat("iron"), Vector3(0, by - 0.002, -0.035)) # казённик
	# латунные кольца ствола, накладка приклада, спусковая скоба
	for z in [-0.42, -0.72, -0.9]:
		ring(root, Vector3(0, by - 0.006, z), 0.02, 0.012, mat("brass"))
	var butt := PackedVector3Array([Vector3(0, -0.076, 0.462), Vector3(0, -0.076, 0.47)])
	mesh(root, loft(butt, [Vector2(0.069, 0.022), Vector2(0.067, 0.021)], Vector3.UP, 14, 1.0), mat("brass"))
	var tg := PackedVector3Array()
	for i in 9:
		var a := PI * float(i) / 8.0
		tg.append(Vector3(0, 0.03 - sin(a) * 0.032, -0.01 + cos(a) * 0.04))
	var tgr := []
	for i in 9:
		tgr.append(Vector2(0.0035, 0.005))
	mesh(root, loft(tg, tgr, Vector3.RIGHT, 6, 1.0, false), mat("brass"))
	rod(root, Vector3(0, 0.03, 0.0), Vector3(0, 0.005, 0.01), 0.0028, mat("iron"), 6) # спуск
	# замок (правый борт): доска, курок с кремнём, огниво, полка
	var lx := 0.02
	HeldModels._box(root, Vector3(0.004, 0.026, 0.12), mat("iron"), Vector3(lx, by - 0.012, -0.03))
	var cock := Node3D.new()
	cock.name = "Cock"
	cock.position = Vector3(lx + 0.006, by - 0.004, 0.01)
	root.add_child(cock)
	var cp := PackedVector3Array([Vector3(0, -0.006, 0.0), Vector3(0, 0.012, -0.006), Vector3(0, 0.03, -0.004), Vector3(0, 0.036, -0.016)])
	mesh(cock, loft(cp, [Vector2(0.004, 0.003), Vector2(0.004, 0.003), Vector2(0.0045, 0.0035), Vector2(0.004, 0.003)], Vector3.BACK, 6, 1.0), mat("iron"))
	HeldModels._box(cock, Vector3(0.008, 0.006, 0.012), HeldModels.color_mat(Color(0.25, 0.25, 0.27), 0.4), Vector3(0, 0.036, -0.024))
	HeldModels._box(root, Vector3(0.006, 0.03, 0.012), mat("iron"), Vector3(lx + 0.004, by + 0.008, -0.045)) # огниво
	HeldModels._box(root, Vector3(0.014, 0.004, 0.02), mat("iron"), Vector3(lx + 0.002, by - 0.006, -0.045)) # полка
	# шомпол под стволом
	rod(root, Vector3(0, by - 0.026, -0.2), Vector3(0, by - 0.022, -1.06), 0.0035, mat("iron"), 6).name = "Ramrod"
	# мушка
	HeldModels._box(root, Vector3(0.003, 0.007, 0.006), mat("brass"), Vector3(0, by + 0.013, -1.05))
	marker(root, "Sight", Vector3(0, by + 0.017, -0.07))
	marker(root, "FrontSight", Vector3(0, by + 0.016, -1.05))
	marker(root, "Muzzle", Vector3(0, by, -1.09))
	marker(root, "Forend", Vector3(0, by - 0.03, -0.42))

## Кремнёвый пистоль. Корень — рукоять.
static func _pistol(root: Node3D) -> void:
	var by := 0.045
	# рукоять с яблоком: вниз-назад
	var gp := PackedVector3Array([Vector3(0, by - 0.005, -0.03), Vector3(0, by - 0.015, 0.0), Vector3(0, 0.0, 0.03),
		Vector3(0, -0.05, 0.06), Vector3(0, -0.085, 0.078), Vector3(0, -0.095, 0.085)])
	var gr := [Vector2(0.017, 0.013), Vector2(0.02, 0.014), Vector2(0.021, 0.015), Vector2(0.023, 0.016), Vector2(0.026, 0.018), Vector2(0.018, 0.013)]
	mesh(root, loft(gp, gr, Vector3.BACK, 12, 2.0), mat("walnut_tip"))
	HeldModels._sphere(root, 0.024, mat("brass"), Vector3(0, -0.092, 0.084), Vector3(1.0, 0.75, 1.0), 10)
	# ложа под стволом
	var sp := PackedVector3Array([Vector3(0, by - 0.012, -0.03), Vector3(0, by - 0.01, -0.2), Vector3(0, by - 0.009, -0.22)])
	mesh(root, loft(sp, [Vector2(0.014, 0.012), Vector2(0.012, 0.011), Vector2(0.008, 0.008)], Vector3.UP, 10, 2.0), mat("walnut"))
	var bp := PackedVector3Array([Vector3(0, by, -0.0), Vector3(0, by, -0.24)])
	mesh(root, loft(bp, [Vector2(0.0115, 0.0115), Vector2(0.0098, 0.0098)], Vector3.UP, 12, 1.0), mat("iron"), "Barrel")
	ring(root, Vector3(0, by, -0.235), 0.0112, 0.01, mat("brass"))
	# замок и курок
	HeldModels._box(root, Vector3(0.004, 0.02, 0.075), mat("iron"), Vector3(0.016, by - 0.008, -0.01))
	var cock := Node3D.new()
	cock.name = "Cock"
	cock.position = Vector3(0.021, by - 0.004, 0.012)
	root.add_child(cock)
	var cp := PackedVector3Array([Vector3(0, -0.004, 0.0), Vector3(0, 0.01, -0.004), Vector3(0, 0.024, -0.003), Vector3(0, 0.028, -0.012)])
	mesh(cock, loft(cp, [Vector2(0.003, 0.0025), Vector2(0.003, 0.0025), Vector2(0.0035, 0.003), Vector2(0.003, 0.0025)], Vector3.BACK, 6, 1.0), mat("iron"))
	HeldModels._box(root, Vector3(0.005, 0.022, 0.009), mat("iron"), Vector3(0.019, by + 0.006, -0.018))
	# скоба и спуск
	var tg := PackedVector3Array()
	var tgr := []
	for i in 9:
		var a := PI * float(i) / 8.0
		tg.append(Vector3(0, by - 0.018 - sin(a) * 0.024, -0.02 + cos(a) * 0.028))
		tgr.append(Vector2(0.003, 0.004))
	mesh(root, loft(tg, tgr, Vector3.RIGHT, 6, 1.0, false), mat("brass"))
	rod(root, Vector3(0, by - 0.018, -0.012), Vector3(0, by - 0.036, -0.004), 0.0024, mat("iron"), 6)
	HeldModels._box(root, Vector3(0.0025, 0.006, 0.005), mat("brass"), Vector3(0, by + 0.013, -0.225))
	marker(root, "Sight", Vector3(0, by + 0.014, 0.0))
	marker(root, "Muzzle", Vector3(0, by, -0.25))

# ======================= метательное и боеприпасы =======================

static func _molotov(root: Node3D) -> void:
	# бутылка (толстое стекло), внутри спирт, в горлышке тряпка
	var pts := PackedVector3Array()
	var rad := []
	var prof := [[-0.09, 0.033], [-0.085, 0.036], [0.03, 0.036], [0.055, 0.03], [0.075, 0.015], [0.12, 0.012], [0.128, 0.014], [0.132, 0.012]]
	for p in prof:
		pts.append(Vector3(0, p[0], 0))
		rad.append(Vector2(p[1], p[1]))
	mesh(root, loft(pts, rad, Vector3.FORWARD, 18, 1.0), mat("glass"))
	var lp := PackedVector3Array([Vector3(0, -0.084, 0), Vector3(0, 0.02, 0)])
	mesh(root, loft(lp, [Vector2(0.032, 0.032), Vector2(0.032, 0.032)], Vector3.FORWARD, 16, 1.0), mat("liquid"))
	var rp := PackedVector3Array([Vector3(0, 0.1, 0), Vector3(0, 0.135, 0.0), Vector3(0.006, 0.16, 0.004), Vector3(0.02, 0.175, 0.012), Vector3(0.03, 0.17, 0.02)])
	mesh(root, loft(rp, [Vector2(0.01, 0.01), Vector2(0.013, 0.012), Vector2(0.012, 0.009), Vector2(0.009, 0.006), Vector2(0.004, 0.003)], Vector3.FORWARD, 8, 3.0), mat("cloth"), "Rag")
	marker(root, "Flame", Vector3(0.012, 0.165, 0.006))

static func _dynamite(root: Node3D) -> void:
	for k in 3:
		var x := (k - 1) * 0.027
		var z := 0.0 if k != 1 else -0.004
		var pts := PackedVector3Array([Vector3(x, -0.1, z), Vector3(x, 0.1, z)])
		mesh(root, loft(pts, [Vector2(0.0135, 0.0135), Vector2(0.0135, 0.0135)], Vector3.FORWARD, 12, 3.0), mat("paper_red"))
	for y in [-0.06, 0.06]:
		HeldModels._box(root, Vector3(0.088, 0.022, 0.03), mat("tape"), Vector3(0, y, -0.002))
	var fp := PackedVector3Array([Vector3(0, 0.1, -0.004), Vector3(0, 0.13, 0.0), Vector3(0.015, 0.16, 0.01), Vector3(0.03, 0.17, 0.02)])
	mesh(root, loft(fp, [Vector2(0.0025, 0.0025), Vector2(0.0025, 0.0025), Vector2(0.0025, 0.0025), Vector2(0.0022, 0.0022)], Vector3.FORWARD, 6, 4.0), mat("fuse"), "Fuse")
	marker(root, "Flame", Vector3(0.03, 0.17, 0.02))

static func _balls(root: Node3D) -> void:
	for k in 3:
		HeldModels._sphere(root, 0.0085, mat("iron"), Vector3((k - 1) * 0.018, 0.0, (k % 2) * 0.01), Vector3.ONE, 8)

static func _powder_horn(root: Node3D) -> void:
	var pts := PackedVector3Array()
	var rad := []
	for i in 9:
		var t := float(i) / 8.0
		pts.append(Vector3(0.0, -0.05 + t * 0.16, sin(t * 2.2) * 0.05))
		var r := lerpf(0.035, 0.008, t)
		rad.append(Vector2(r, r))
	mesh(root, loft(pts, rad, Vector3.FORWARD, 12, 1.0), mat("horn"))
	ring(root, pts[0] + Vector3(0, 0.005, 0), 0.036, 0.01, mat("brass"), Vector3.ZERO)
	ring(root, pts[8], 0.009, 0.012, mat("brass"), Vector3.ZERO)

static func _spirit(root: Node3D) -> void:
	_molotov(root)
	var r := root.get_node_or_null(^"Rag")
	if r:
		r.queue_free()
	HeldModels._cyl(root, 0.012, 0.012, 0.02, mat("wood"), Vector3(0, 0.135, 0))

static func _lumps(root: Node3D, m: Material) -> void:
	for k in 3:
		var mi := MeshInstance3D.new()
		mi.mesh = HeldModels.rough_stone_mesh(0.022, 11 + k)
		mi.material_override = m
		mi.position = Vector3((k - 1) * 0.03, 0, (k % 2) * 0.02)
		root.add_child(mi)

static func _iron_parts(root: Node3D) -> void:
	HeldModels._box(root, Vector3(0.12, 0.012, 0.03), mat("iron"), Vector3.ZERO, Vector3(0, 0.3, 0))
	rod(root, Vector3(-0.05, 0.01, 0.03), Vector3(0.06, 0.01, 0.02), 0.008, mat("iron"), 8)
	HeldModels._box(root, Vector3(0.03, 0.03, 0.01), mat("iron"), Vector3(0.0, 0.02, -0.02))

## Модель снаряда в полёте (стрела/болт — как предмет; пуля — маленький шарик).
static func projectile(ammo: StringName) -> Node3D:
	var r := Node3D.new()
	match ammo:
		&"arrow": _arrow(r, false)
		&"arrow_fire": _arrow(r, true)
		&"bolt": _bolt(r)
		&"spear":
			var s := HeldModels.build(&"spear")
			# копьё: +Y вдоль древка → -Z
			s.rotation = Vector3(-PI / 2, 0, 0)
			s.position = Vector3(0, 0, 0.6)
			r.add_child(s)
		&"molotov": _molotov(r)
		&"musket_ball": HeldModels._sphere(r, 0.009, mat("iron"), Vector3.ZERO, Vector3.ONE, 6)
		_:
			var m := HeldModels.build(ammo)
			r.add_child(m)
	HeldModels._no_shadows(r)
	return r
