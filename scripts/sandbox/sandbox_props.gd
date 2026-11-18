class_name SandboxProps
extends RefCounted
## Простые постройки «Полигона»: таблички, подписи, столы, загоны, пирс.
## Всё из дерева (текстуры проекта), с коллизией.

const SIGN_COLOR := Color(1.0, 0.93, 0.78)

static func _wood() -> Material:
	return HeldModels.pbr("weathered_planks", Vector3(1.0, 1.0, 1.0), Color(0.92, 0.84, 0.74))

static func _post_mat() -> Material:
	return HeldModels.pbr("rough_wood", Vector3(1.0, 3.0, 1.0), Color(0.8, 0.7, 0.6))

static func _bark() -> Material:
	return HeldModels.pbr("bark_brown_02", Vector3(1.0, 2.0, 1.0))

static func ground(x: float, z: float) -> float:
	var w := Engine.get_main_loop() as SceneTree
	var wn := w.get_first_node_in_group(&"world") if w else null
	return float(wn.call(&"height_at", x, z)) if wn else 0.0

static func label(parent: Node, pos: Vector3, text: String, size: int = 40, color: Color = SIGN_COLOR,
		range_end: float = 0.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = UITheme.font(true)
	l.font_size = size
	l.pixel_size = 0.0045
	l.outline_size = maxi(6, size / 5)
	l.outline_modulate = Color(0.05, 0.04, 0.03, 0.9)
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	l.double_sided = true
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	if range_end > 0.0:
		l.visibility_range_end = range_end
		l.visibility_range_end_margin = 4.0
	parent.add_child(l)
	l.global_position = pos
	return l

## Подпись у предмета/постройки: на высоте h над землёй.
static func tag(parent: Node, x: float, z: float, text: String, h: float = 1.6, range_end: float = 28.0) -> Label3D:
	return label(parent, Vector3(x, ground(x, z) + h, z), text, 34, SIGN_COLOR, range_end)

## Табличка зоны: столб с доской и крупная надпись.
static func signpost(parent: Node, x: float, z: float, title: String, sub: String = "") -> Node3D:
	var root := StaticBody3D.new()
	root.name = "Sign"
	parent.add_child(root)
	var g := ground(x, z)
	root.global_position = Vector3(x, g, z)
	var post := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.07
	cm.bottom_radius = 0.09
	cm.height = 3.0
	post.mesh = cm
	post.material_override = _post_mat()
	post.position = Vector3(0, 1.4, 0)
	root.add_child(post)
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.6, 0.6, 0.06)
	board.mesh = bm
	board.material_override = _wood()
	board.position = Vector3(0, 2.55, 0.1)
	root.add_child(board)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.12
	sh.height = 3.0
	cs.shape = sh
	cs.position = Vector3(0, 1.4, 0)
	root.add_child(cs)
	var t := label(root, Vector3(x, g + 3.05, z), title, 96, Color(1.0, 0.88, 0.6))
	t.pixel_size = 0.006
	if sub != "":
		var s := label(root, Vector3(x, g + 3.0, z), sub, 40, SIGN_COLOR)
		s.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	return root

static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

static func _shape(body: Node3D, size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	body.add_child(cs)

## Стол из досок: верх на высоте 0.85 м, длина len вдоль локальной X.
static func table(parent: Node, x: float, z: float, length: float = 4.0, yaw: float = 0.0, depth: float = 1.0) -> StaticBody3D:
	var t := StaticBody3D.new()
	t.name = "Table"
	parent.add_child(t)
	var g := ground(x, z)
	t.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(x, g, z))
	var top_h := 0.85
	_box(t, Vector3(length, 0.07, depth), Vector3(0, top_h, 0), _wood())
	_shape(t, Vector3(length, 0.07, depth), Vector3(0, top_h, 0))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var lx: float = sx * (length * 0.5 - 0.12)
			var lz: float = sz * (depth * 0.5 - 0.1)
			# ножка до земли (рельеф под столом может быть неровным)
			var w := t.global_transform * Vector3(lx, 0, lz)
			var lg := ground(w.x, w.z) - g
			var hh := top_h - lg + 0.15
			_box(t, Vector3(0.09, hh, 0.09), Vector3(lx, lg - 0.15 + hh * 0.5, lz), _post_mat())
	return t

## Загон: кольцо столбов с двумя жердями и сплошной коллизией по периметру.
static func pen(parent: Node, x: float, z: float, r: float, h: float = 1.15) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Pen"
	parent.add_child(body)
	var g := ground(x, z)
	body.global_position = Vector3(x, g, z)
	var n := maxi(8, int(TAU * r / 1.3))
	var bark := _bark()
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p0 := Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, 0, sin(a1) * r)
		var g0 := ground(x + p0.x, z + p0.z) - g
		var g1 := ground(x + p1.x, z + p1.z) - g
		p0.y = g0
		p1.y = g1
		var post := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.06
		cm.bottom_radius = 0.07
		cm.height = h + 0.3
		cm.radial_segments = 8
		post.mesh = cm
		post.material_override = bark
		post.position = p0 + Vector3(0, (h + 0.3) * 0.5 - 0.2, 0)
		body.add_child(post)
		var mid := (p0 + p1) * 0.5
		var seg := p1 - p0
		var yaw := atan2(seg.x, seg.z)
		for rh in [0.45, h - 0.08]:
			var rail := MeshInstance3D.new()
			var rm := CylinderMesh.new()
			rm.top_radius = 0.04
			rm.bottom_radius = 0.04
			rm.height = seg.length() + 0.1
			rm.radial_segments = 6
			rail.mesh = rm
			rail.material_override = bark
			rail.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5)
			rail.position = mid + Vector3(0, rh, 0)
			body.add_child(rail)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.2, h + 0.6, seg.length() + 0.15)
		cs.shape = bs
		cs.basis = Basis(Vector3.UP, yaw)
		cs.position = mid + Vector3(0, (h + 0.6) * 0.5 - 0.3, 0)
		body.add_child(cs)
	return body

## Пирс от точки start по направлению dir (XZ) длиной length; настил на высоте deck_y.
static func pier(parent: Node, start: Vector3, dir: Vector3, length: float, deck_y: float, width: float = 2.6) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Pier"
	parent.add_child(body)
	dir.y = 0.0
	dir = dir.normalized()
	var yaw := atan2(dir.x, dir.z)
	body.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(start.x, deck_y, start.z))
	var planks := HeldModels.pbr("weathered_planks", Vector3(1.0, 1.0, 1.0), Color(0.82, 0.74, 0.64))
	var n := int(length / 0.32)
	for i in n:
		var pl := _box(body, Vector3(width, 0.07, 0.28), Vector3(0, 0, 0.16 + i * 0.32), planks)
		pl.rotation.y = (float((i * 37) % 7) - 3.0) * 0.004
	_shape(body, Vector3(width, 0.12, length), Vector3(0, -0.02, length * 0.5))
	var k := 0.0
	while k <= length:
		for sx in [-1.0, 1.0]:
			var lp := Vector3(sx * (width * 0.5 - 0.1), 0, k)
			var w := body.global_transform * lp
			var depth := deck_y - ground(w.x, w.z)
			var pile := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.11
			cm.bottom_radius = 0.13
			cm.height = depth + 0.5
			cm.radial_segments = 8
			pile.mesh = cm
			pile.material_override = _bark()
			pile.position = lp + Vector3(0, 0.25 - (depth + 0.5) * 0.5, 0)
			body.add_child(pile)
		# перила
		for sx in [-1.0, 1.0]:
			_box(body, Vector3(0.07, 0.9, 0.07), Vector3(sx * (width * 0.5 - 0.05), 0.45, k), _post_mat())
		k += 3.0
	for sx in [-1.0, 1.0]:
		_box(body, Vector3(0.06, 0.06, length), Vector3(sx * (width * 0.5 - 0.05), 0.92, length * 0.5), _post_mat())
		_shape(body, Vector3(0.1, 1.0, length), Vector3(sx * (width * 0.5 - 0.05), 0.5, length * 0.5))
	return body

## Плоская площадка-арена: кольцо камней по краю (без коллизии) — разметка.
static func ring_marks(parent: Node, x: float, z: float, r: float) -> void:
	var n := int(TAU * r / 3.0)
	var stone := HeldModels.pbr("mossy_rock", Vector3(1.0, 1.0, 1.0))
	for i in n:
		var a := TAU * i / n
		var px := x + cos(a) * r
		var pz := z + sin(a) * r
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.35
		sm.height = 0.4
		sm.radial_segments = 8
		sm.rings = 4
		mi.mesh = sm
		mi.material_override = stone
		parent.add_child(mi)
		mi.global_position = Vector3(px, ground(px, pz) + 0.05, pz)
		mi.rotation.y = a
