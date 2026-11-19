class_name ShowProps
extends Node3D
## Лор шоу: декор телешоу на архипелаге (docs/LORE.md).
##  - мачты-громкоговорители: 4 по кругу на Вулкане (центральный остров) и по одной на
##    общих островах — решётчатая мачта ~9 м, рупоры, камера, красный огонь сверху;
##  - камеры наблюдения на столбиках у берега (по 2 на остров) — объектив смотрит на сушу
##    (камеры «на пальмах и скалах» из лора — на столбах: пальмы рубятся, камни добываются).
## Меши собраны один раз (SurfaceTool) и делятся между копиями; у мачт — коллизия.
##
## API: ShowProps.instance(), masts (Array[Node3D]), cams (Array[Node3D])

const MAST_H := 9.0
const MAST_VIS := 320.0
const CAM_VIS := 110.0

var masts: Array[Node3D] = []
var cams: Array[Node3D] = []
var _t := 0.0

static var _mast_mesh: ArrayMesh
static var _cam_mesh: ArrayMesh
static var _led_mat: StandardMaterial3D

static func instance() -> ShowProps:
	var t := Engine.get_main_loop() as SceneTree
	return t.get_first_node_in_group(&"show_props") as ShowProps if t else null

static func clear_caches() -> void:
	_mast_mesh = null
	_cam_mesh = null
	_led_mat = null

func _ready() -> void:
	name = "ShowProps"
	add_to_group(&"show_props")
	_place.call_deferred()

func _place() -> void:
	var w := get_tree().get_first_node_in_group(&"world")
	if w == null or not w.has_method(&"islands"):
		return
	var wl := BuildEnv.water_level()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for I: Dictionary in w.call(&"islands"):
		var c: Vector2 = I.center
		var R := float(I.radius)
		var kind := StringName(I.kind)
		if kind == &"center":
			for k in 4:
				var a := PI * 0.25 + PI * 0.5 * k
				var p := _land_toward(c, a, R * 0.62, R * 0.25, wl + 1.2)
				if p != Vector3.INF:
					add_mast(p, a)
		elif kind == &"shared":
			var a2 := rng.randf() * TAU
			var p2 := _land_toward(c, a2, R * 0.5, R * 0.2, wl + 1.0)
			if p2 != Vector3.INF:
				add_mast(p2, a2)
		# камеры у берега: смотрят на сушу
		var a0 := rng.randf() * TAU
		for k in 2:
			var a3 := a0 + PI * k + rng.randf_range(-0.4, 0.4)
			var p3 := _land_toward(c, a3, R * 0.85, R * 0.45, wl + 0.6)
			if p3 != Vector3.INF:
				add_cam(p3, Vector3(c.x, p3.y + 1.0, c.y))

## Суша на луче от центра острова: от r_out внутрь до r_in, первая точка выше min_h.
func _land_toward(c: Vector2, a: float, r_out: float, r_in: float, min_h: float) -> Vector3:
	var r := r_out
	while r >= r_in:
		var x := c.x + cos(a) * r
		var z := c.y + sin(a) * r
		var h := BuildEnv.height_at(x, z)
		if h > min_h:
			# не на круче: разброс высот вокруг ≤ 0.9 м на 1.5 м
			var flat := true
			for o: Vector2 in [Vector2(1.5, 0), Vector2(-1.5, 0), Vector2(0, 1.5), Vector2(0, -1.5)]:
				flat = flat and absf(BuildEnv.height_at(x + o.x, z + o.y) - h) < 0.9
			if flat:
				return Vector3(x, h, z)
		r -= 4.0
	return Vector3.INF

func add_mast(at: Vector3, face: float) -> Node3D:
	var body := StaticBody3D.new()
	body.name = "Mast%d" % masts.size()
	body.collision_layer = 1
	add_child(body)
	body.global_position = at + Vector3.DOWN * 0.3
	body.rotation.y = -face + PI * 0.5   # рупоры смотрят наружу от центра острова
	var mi := MeshInstance3D.new()
	mi.mesh = mast_mesh()
	mi.visibility_range_end = MAST_VIS
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.35
	sh.height = MAST_H
	cs.shape = sh
	cs.position = Vector3(0, MAST_H * 0.5, 0)
	body.add_child(cs)
	var led := MeshInstance3D.new()
	led.name = "Led"
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	sm.radial_segments = 8
	sm.rings = 4
	led.mesh = sm
	led.material_override = led_mat()
	led.position = Vector3(0, MAST_H + 0.35, 0)
	led.visibility_range_end = MAST_VIS
	body.add_child(led)
	masts.append(body)
	return body

func add_cam(at: Vector3, look: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = "Cam%d" % cams.size()
	add_child(n)
	n.global_position = at + Vector3.DOWN * 0.15
	var d := look - at
	n.rotation.y = atan2(-d.x, -d.z)
	var mi := MeshInstance3D.new()
	mi.mesh = cam_mesh()
	mi.visibility_range_end = CAM_VIS
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mi)
	cams.append(n)
	return n

func _process(delta: float) -> void:
	_t += delta
	# огни мачт мигают (общий материал — один параметр на все)
	if _led_mat:
		_led_mat.emission_energy_multiplier = 5.0 if fmod(_t, 1.6) < 0.8 else 0.4

# ------------------------------------------------------------ меши

static func _mat(c: Color, rough: float, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

static func led_mat() -> StandardMaterial3D:
	if _led_mat == null:
		_led_mat = StandardMaterial3D.new()
		_led_mat.albedo_color = Color(1.0, 0.12, 0.06)
		_led_mat.emission_enabled = true
		_led_mat.emission = Color(1.0, 0.1, 0.05)
		_led_mat.emission_energy_multiplier = 5.0
	return _led_mat

static func _add(st: SurfaceTool, m: Mesh, xf: Transform3D) -> void:
	st.append_from(m, 0, xf)

static func _box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b

static func _cyl(rt: float, rb: float, h: float, seg: int = 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c

static func _xf(pos: Vector3, rot: Vector3 = Vector3.ZERO) -> Transform3D:
	return Transform3D(Basis.from_euler(rot), pos)

## Решётчатая мачта: 3 стойки, распорки, площадка, 3 рупора, камера.
static func mast_mesh() -> ArrayMesh:
	if _mast_mesh:
		return _mast_mesh
	var steel := _mat(Color(0.42, 0.42, 0.4), 0.55, 0.7)
	var dark := _mat(Color(0.12, 0.12, 0.13), 0.5, 0.3)
	var paint := _mat(Color(0.95, 0.42, 0.08), 0.5)
	var mesh := ArrayMesh.new()
	# сталь
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leg := _cyl(0.035, 0.05, MAST_H, 6)
	var legs: Array[Vector3] = []
	for k in 3:
		var a := TAU * k / 3.0
		var p := Vector3(cos(a), 0, sin(a)) * 0.28
		legs.append(p)
		_add(st, leg, _xf(p + Vector3.UP * MAST_H * 0.5))
	var y := 0.6
	while y < MAST_H:
		for k in 3:
			var p0 := legs[k] + Vector3.UP * y
			var p1 := legs[(k + 1) % 3] + Vector3.UP * (y + 0.6)
			var mid := (p0 + p1) * 0.5
			var dir := (p1 - p0)
			var bar := _cyl(0.015, 0.015, dir.length(), 4)
			var b := Basis.looking_at(dir.normalized(), Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.RIGHT)
			_add(st, bar, Transform3D(b * Basis.from_euler(Vector3(PI * 0.5, 0, 0)), mid))
		y += 1.2
	_add(st, _cyl(0.5, 0.5, 0.06, 10), _xf(Vector3.UP * (MAST_H - 0.6)))
	_add(st, _cyl(0.03, 0.03, 0.7, 6), _xf(Vector3.UP * (MAST_H + 0.0)))
	st.generate_normals()
	st.set_material(steel)
	st.commit(mesh)
	# рупоры и камера (тёмные)
	var sd := SurfaceTool.new()
	sd.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var a := TAU * k / 3.0 + PI / 3.0
		var dir := Vector3(cos(a), -0.15, sin(a)).normalized()
		var b := Basis.looking_at(dir, Vector3.UP) * Basis.from_euler(Vector3(-PI * 0.5, 0, 0))
		_add(sd, _cyl(0.32, 0.08, 0.6, 10), Transform3D(b, Vector3.UP * (MAST_H - 1.1) + dir * 0.55))
	_add(sd, _box(Vector3(0.22, 0.2, 0.34)), _xf(Vector3(0, MAST_H - 2.2, -0.42)))
	_add(sd, _cyl(0.06, 0.07, 0.08, 10), _xf(Vector3(0, MAST_H - 2.2, -0.62), Vector3(PI * 0.5, 0, 0)))
	sd.generate_normals()
	sd.set_material(dark)
	sd.commit(mesh)
	# оранжевые полосы шоу
	var sp := SurfaceTool.new()
	sp.begin(Mesh.PRIMITIVE_TRIANGLES)
	for h: float in [2.0, 5.0]:
		_add(sp, _cyl(0.36, 0.36, 0.25, 10), _xf(Vector3.UP * h))
	sp.generate_normals()
	sp.set_material(paint)
	sp.commit(mesh)
	_mast_mesh = mesh
	return mesh

## Камера на столбике ~1.7 м: корпус, козырёк, объектив (−Z).
static func cam_mesh() -> ArrayMesh:
	if _cam_mesh:
		return _cam_mesh
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add(st, _cyl(0.035, 0.045, 1.7, 6), _xf(Vector3.UP * 0.85))
	_add(st, _box(Vector3(0.16, 0.14, 0.3)), _xf(Vector3(0, 1.78, -0.05), Vector3(-0.12, 0, 0)))
	_add(st, _box(Vector3(0.2, 0.02, 0.36)), _xf(Vector3(0, 1.87, -0.07), Vector3(-0.12, 0, 0)))
	st.generate_normals()
	st.set_material(_mat(Color(0.2, 0.21, 0.2), 0.6, 0.3))
	st.commit(mesh)
	var sl := SurfaceTool.new()
	sl.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add(sl, _cyl(0.045, 0.05, 0.05, 10), _xf(Vector3(0, 1.76, -0.22), Vector3(PI * 0.5 - 0.12, 0, 0)))
	sl.generate_normals()
	sl.set_material(_mat(Color(0.02, 0.03, 0.05), 0.05, 0.6))
	sl.commit(mesh)
	_cam_mesh = mesh
	return mesh
