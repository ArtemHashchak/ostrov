class_name SandboxRange
extends RefCounted
## Стрельбище для современного огнестрела (полигон и test_gunplay): линия огня со столом,
## дорожка на 10/25/50/100 м — на каждой дистанции бумажная мишень с кольцами (следы пуль
## остаются), гонг-плита (звенит и качается, считает попадания) и манекен. У 10 м — «образцы
## поверхностей»: камень, дерево, металл, мешки с песком (разные искры/щепки/пыль и следы).

const DISTANCES: Array[float] = [10.0, 25.0, 50.0, 100.0]

## origin — центр линии огня на земле, fwd — направление стрельбы (горизонтально),
## ground(x, z) -> float — высота рельефа. Возвращает {dummies, plates, papers, surfaces, stand, look}.
static func build(root: Node3D, origin: Vector3, fwd: Vector3, ground: Callable) -> Dictionary:
	fwd = Vector3(fwd.x, 0.0, fwd.z).normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	var out := {"dummies": [], "plates": [], "papers": [], "surfaces": [], "by_dist": {}}
	var wood := HeldModels.pbr("rough_wood", Vector3.ONE, Color(0.9, 0.85, 0.7))
	var at := func(d: float, side: float) -> Vector3:
		var q := origin + fwd * d + right * side
		q.y = float(ground.call(q.x, q.z))
		return q
	# линия огня: брус и стол-стойка
	var line := _box(root, Vector3(8.0, 0.06, 0.12), wood, at.call(0.0, 0.0) + Vector3.UP * 0.03, fwd)
	line.name = "FiringLine"
	_body(root, Vector3(1.6, 0.06, 0.6), wood, at.call(-0.6, -2.2) + Vector3.UP * 0.95, fwd, &"wood")
	for sx in [-0.7, 0.7]:
		for sz in [-0.25, 0.25]:
			_box(root, Vector3(0.06, 0.95, 0.06), wood, at.call(-0.6 + sz, -2.2 + sx) + Vector3.UP * 0.475, fwd)
	for d in DISTANCES:
		var k := 1.0 if d <= 25.0 else (1.5 if d <= 50.0 else 2.0)
		var row := {}
		# бумажная мишень на раме
		var pp: Vector3 = at.call(d, -1.6)
		var paper := _paper(root, pp, fwd, 0.55 * k)
		paper.name = "Paper_%dm" % int(d)
		out.papers.append(paper)
		row["paper"] = paper
		# гонг-плита
		var gp: Vector3 = at.call(d, 0.9)
		var plate := RangePlate.new()
		plate.radius = 0.2 * k
		root.add_child(plate)
		plate.global_transform = Transform3D(_face(fwd), gp + Vector3.UP * 1.25)
		plate.name = "Plate_%dm" % int(d)
		_post(root, gp, 1.25 + plate.radius, wood, fwd)
		out.plates.append(plate)
		row["plate"] = plate
		# манекен
		var dp: Vector3 = at.call(d, 3.2)
		var dm := TrainingDummy.new()
		root.add_child(dm)
		dm.global_position = dp - Vector3.UP * 0.02
		var face_to: Vector3 = at.call(0.0, 3.2)
		dm.look_at(Vector3(face_to.x, dm.global_position.y, face_to.z), Vector3.UP)
		dm.rotate_y(PI) # лицом (+Z) к линии огня
		dm.name = "Dummy_%dm" % int(d)
		out.dummies.append(dm)
		row["dummy"] = dm
		# табличка дистанции
		var sp: Vector3 = at.call(d - 0.5, -3.4)
		_sign(root, sp, fwd, "%d м" % int(d), wood)
		out.by_dist[int(d)] = row
	# образцы поверхностей у 10 м (левее дорожки)
	var sx0 := -7.0
	var mats := [
		[&"stone", HeldModels.pbr("seaside_rock", Vector3.ONE, Color(0.9, 0.88, 0.85)), Vector3(1.0, 1.2, 0.8)],
		[&"wood", HeldModels.pbr("weathered_planks", Vector3.ONE, Color(0.9, 0.8, 0.65)), Vector3(1.0, 1.0, 1.0)],
		[&"metal", HeldModels.color_mat(Color(0.35, 0.37, 0.38), 0.35, 0.9), Vector3(0.9, 1.3, 0.12)],
		[&"sand", HeldModels.pbr("coast_sand_01", Vector3.ONE, Color(0.95, 0.9, 0.8)), Vector3(1.2, 0.7, 0.6)],
	]
	for i in mats.size():
		var e: Array = mats[i]
		var sp2: Vector3 = at.call(11.0, sx0 - i * 1.6)
		var sz: Vector3 = e[2]
		var b := _body(root, sz, e[1], sp2 + Vector3.UP * sz.y * 0.5, fwd, e[0])
		b.name = "Surface_%s" % String(e[0])
		out.surfaces.append(b)
	out["stand"] = at.call(-1.0, 0.0) + Vector3.UP * 0.2
	out["look"] = at.call(25.0, 0.0) + Vector3.UP * 1.3
	return out

static func _face(fwd: Vector3) -> Basis:
	# +Z к стрелку (QuadMesh/лицевая сторона смотрит на линию огня)
	return Basis.looking_at(fwd, Vector3.UP)

static func _box(root: Node3D, size: Vector3, m: Material, pos: Vector3, fwd: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	root.add_child(mi)
	mi.global_transform = Transform3D(_face(fwd), pos)
	return mi

static func _body(root: Node3D, size: Vector3, m: Material, pos: Vector3, fwd: Vector3, surface: StringName) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.set_meta(&"surface", surface)
	root.add_child(b)
	b.global_transform = Transform3D(_face(fwd), pos)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	b.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	return b

static func _post(root: Node3D, base: Vector3, h: float, m: Material, fwd: Vector3) -> void:
	_box(root, Vector3(0.08, h, 0.08), m, base + Vector3.UP * h * 0.5 + fwd * 0.12, fwd)

static func _sign(root: Node3D, pos: Vector3, fwd: Vector3, text: String, m: Material) -> void:
	_box(root, Vector3(0.07, 1.3, 0.07), m, pos + Vector3.UP * 0.65, fwd)
	_box(root, Vector3(0.7, 0.36, 0.04), m, pos + Vector3.UP * 1.35, fwd)
	var l := Label3D.new()
	l.text = text
	l.font = UITheme.font(true)
	l.font_size = 64
	l.pixel_size = 0.004
	l.modulate = Color(0.12, 0.08, 0.05)
	l.outline_size = 0
	root.add_child(l)
	l.global_transform = Transform3D(_face(fwd), pos + Vector3.UP * 1.35 - fwd * 0.025)

## Бумажная мишень 1×1 (× s): деревянная рама на двух стойках, лист с кольцами.
static func _paper(root: Node3D, base: Vector3, fwd: Vector3, s: float) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.set_meta(&"surface", &"wood")
	root.add_child(b)
	var c := base + Vector3.UP * (0.9 + s)
	b.global_transform = Transform3D(_face(fwd), c)
	var wood := HeldModels.pbr("rough_wood", Vector3.ONE, Color(0.9, 0.85, 0.7))
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.0 * s, 2.0 * s, 0.03)
	board.mesh = bm
	board.material_override = wood
	b.add_child(board)
	var paper := HeldModels.color_mat(Color(0.93, 0.92, 0.86), 0.95)
	var ink := HeldModels.color_mat(Color(0.08, 0.08, 0.08), 0.9)
	var red := HeldModels.color_mat(Color(0.75, 0.12, 0.08), 0.8)
	var sheet := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.8, 1.8) * s
	sheet.mesh = qm
	sheet.material_override = paper
	sheet.position = Vector3(0, 0, 0.016) # +Z — к линии огня
	b.add_child(sheet)
	var radii := [0.85, 0.68, 0.51, 0.34, 0.17, 0.06]
	for i in radii.size():
		var ring := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = float(radii[i]) * s
		cm.bottom_radius = cm.top_radius
		cm.height = 0.001
		cm.radial_segments = 32
		cm.rings = 1
		ring.mesh = cm
		ring.material_override = (ink if i % 2 == 0 else paper) if i < radii.size() - 1 else red
		ring.rotation.x = PI / 2
		ring.position = Vector3(0, 0, 0.017 + i * 0.0007)
		b.add_child(ring)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(2.0 * s, 2.0 * s, 0.04)
	cs.shape = sh
	b.add_child(cs)
	for sx in [-0.9, 0.9]:
		_box(root, Vector3(0.07, 0.9 + s * 0.2, 0.07), wood, base + right_of(fwd) * sx * s + Vector3.UP * (0.9 + s * 0.2) * 0.5 + fwd * 0.05, fwd)
	return b

static func right_of(fwd: Vector3) -> Vector3:
	return fwd.cross(Vector3.UP).normalized()


## Гонг-плита: стальной диск на цепях — звенит, качается, считает попадания.
class RangePlate:
	extends StaticBody3D
	var radius := 0.2
	var hits := 0
	var total := 0.0
	var _disc: Node3D

	func _ready() -> void:
		set_meta(&"surface", &"metal")
		set_meta(&"decals_follow", true)
		_disc = Node3D.new()
		add_child(_disc)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = radius
		cm.bottom_radius = radius
		cm.height = 0.02
		cm.radial_segments = 28
		cm.rings = 1
		mi.mesh = cm
		mi.material_override = HeldModels.color_mat(Color(0.82, 0.84, 0.86), 0.45, 0.8)
		mi.rotation.x = PI / 2
		_disc.add_child(mi)
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = radius
		sh.height = 0.03
		cs.shape = sh
		cs.rotation.x = PI / 2
		add_child(cs)

	func apply_damage(amount: float, _source: Node = null, _kind: StringName = &"bullet") -> void:
		hits += 1
		total += amount
		rotation.x = 0.0
		var tw := create_tween()
		tw.tween_property(self, "rotation:x", deg_to_rad(-14.0), 0.06)
		tw.tween_property(self, "rotation:x", deg_to_rad(6.0), 0.25)
		tw.tween_property(self, "rotation:x", 0.0, 0.35)
		var a := CombatFx.sound_at(self, "hit_metal", global_position, 2.0, 160.0)
		if a:
			a.pitch_scale = randf_range(0.8, 0.9)
