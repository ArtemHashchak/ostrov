class_name SeaHoldfast
extends Node3D
## Стебель, за который держится хвостом морской конёк: лист морской травы, выгнутый дугой,
## или веточка коралла/горгонарии. Основание — в начале узла (на дне), стебель встаёт вверх
## и на высоте grip_h ложится поперёк (вдоль локальной X) — через завиток хвоста конька;
## дальше конец свисает. Узел покачивается от основания (течение); grip_point() — где завиток.

var grip_h := 0.3
var kind := "grass"          # grass | coral
var sway := 1.0
var _t := 0.0
var _ph := 0.0
var _base_rot := Vector3.ZERO
var _base_set := false

static var _mats: Dictionary = {}

## Стебель высотой захвата h (м) вида k; seed_f — фаза покачивания.
static func create(h: float, k: String = "grass", seed_f: float = 0.0) -> SeaHoldfast:
	var s := SeaHoldfast.new()
	s.grip_h = h
	s.kind = k
	s._ph = seed_f
	s.name = "Holdfast_" + k
	s._build()
	return s

func _build() -> void:
	var r0 := 0.006 if kind == "grass" else 0.009
	var r1 := 0.0035 if kind == "grass" else 0.004
	var h := grip_h
	# путь в локальных координатах: встаёт сбоку от завитка, ложится поперёк через (0, h, 0), конец свисает
	var pts: Array[Vector3] = [Vector3(-0.07, -0.02, 0.0), Vector3(-0.07, h * 0.45, 0.0), Vector3(-0.06, h * 0.85, 0.0),
		Vector3(-0.035, h + 0.012, 0.0), Vector3(0.0, h, 0.0), Vector3(0.035, h - 0.008, 0.0), Vector3(0.07, h - 0.035, 0.0),
		Vector3(0.09, h - 0.075, 0.003)]
	var mi := MeshInstance3D.new()
	mi.mesh = _tube(pts, r0, r1, 10, 7)
	mi.material_override = _mat(kind)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	if kind == "coral":
		# пара коротких веточек
		for b: Array in [[Vector3(-0.07, h * 0.5, 0.0), Vector3(-0.11, h * 0.75, 0.02), Vector3(-0.13, h * 0.95, 0.03)],
				[Vector3(-0.068, h * 0.3, 0.0), Vector3(-0.03, h * 0.45, -0.02), Vector3(-0.01, h * 0.6, -0.04)]]:
			var bm := MeshInstance3D.new()
			var bp: Array[Vector3] = []
			for v: Vector3 in b:
				bp.append(v)
			bm.mesh = _tube(bp, 0.006, 0.0025, 8, 6)
			bm.material_override = _mat(kind)
			bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(bm)

func _process(dt: float) -> void:
	if not _base_set:
		_base_rot = rotation          # поворот, заданный при постановке
		_base_set = true
	_t += dt
	rotation = _base_rot + Vector3(sin(_t * 0.7 + _ph) * 0.05, 0.0, cos(_t * 0.55 + _ph * 1.3) * 0.04) * sway

## Точка захвата (мир): середина поперечного участка — через неё проходит завиток хвоста.
func grip_point() -> Vector3:
	return global_transform * Vector3(0.0, grip_h, 0.0)

static func _mat(k: String) -> StandardMaterial3D:
	if _mats.has(k):
		return _mats[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.34, 0.46, 0.2) if k == "grass" else Color(0.62, 0.36, 0.3)
	m.roughness = 0.8
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[k] = m
	return m

## Трубка по ломаной (сглаженной Катмулл–Ромом), радиус от r0 к r1.
static func _tube(pts: Array[Vector3], r0: float, r1: float, sub: int, ring: int) -> ArrayMesh:
	var path: Array[Vector3] = []
	for i in pts.size() - 1:
		var p0 := pts[maxi(i - 1, 0)]
		var p1 := pts[i]
		var p2 := pts[i + 1]
		var p3 := pts[mini(i + 2, pts.size() - 1)]
		for s in sub:
			var t := float(s) / sub
			path.append(p1.cubic_interpolate(p2, p0, p3, t))
	path.append(pts[pts.size() - 1])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := path.size()
	var prev_side := Vector3(0, 0, 1)
	for i in n:
		var tg := (path[mini(i + 1, n - 1)] - path[maxi(i - 1, 0)]).normalized()
		var side := prev_side - tg * prev_side.dot(tg)
		if side.length() < 1e-4:
			side = tg.cross(Vector3.UP)
		side = side.normalized()
		prev_side = side
		var up := tg.cross(side).normalized()
		var r := lerpf(r0, r1, float(i) / float(n - 1))
		for k in ring + 1:
			var a := float(k) / ring * TAU
			var nrm := side * cos(a) + up * sin(a)
			st.set_normal(nrm)
			st.set_uv(Vector2(float(k) / ring, float(i) / (n - 1)))
			st.add_vertex(path[i] + nrm * r)
	for i in n - 1:
		for k in ring:
			var a := i * (ring + 1) + k
			var b := a + ring + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(b)
			st.add_index(b + 1)
	return st.commit()
