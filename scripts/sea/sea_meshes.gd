class_name SeaMeshes
extends RefCounted
## Процедурные меши моря: кораллы (ветвистые, мозговики, столовые, веера, губки),
## водоросли, рифовые камни, скат, черепаха, медуза, верша. Вершинный цвет; UV.y —
## высота над основанием (для покачивания в coral.gdshader). Всё кэшируется.

const CORAL_SHADER := preload("res://scripts/sea/shaders/coral.gdshader")
const CREATURE_SHADER := preload("res://scripts/sea/shaders/creature.gdshader")
const JELLY_SHADER := preload("res://scripts/sea/shaders/jelly.gdshader")

static var _cache: Dictionary = {}

static func clear_cache() -> void:
	_cache.clear()

static func mat_vc(rough: float = 0.8) -> StandardMaterial3D:
	var key := "vc%.2f" % rough
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache[key] = m
	return m

static func coral_material(sway: float, water_level: float, rough: float = 0.78) -> ShaderMaterial:
	var key := "coral%.2f_%.2f_%.2f" % [sway, water_level, rough]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = CORAL_SHADER
	m.set_shader_parameter(&"sway", sway)
	m.set_shader_parameter(&"water_level", water_level)
	m.set_shader_parameter(&"rough", rough)
	if sway > 0.0:
		SeaPush.register(m)
	_cache[key] = m
	return m

# ------------------------------------------------------------ примитивы

## Конус-труба a→b, радиусы ra/rb, цвета ca/cb, высоты (UV.y) ha/hb.
static func _tube(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, seg: int,
		ca: Color, cb: Color, ha: float, hb: float, cap: bool = true) -> void:
	var ax := (b - a).normalized()
	var ref := Vector3.UP if absf(ax.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var u := ax.cross(ref).normalized()
	var v := ax.cross(u).normalized()
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var d0 := u * cos(a0) + v * sin(a0)
		var d1 := u * cos(a1) + v * sin(a1)
		var p00 := a + d0 * ra
		var p01 := a + d1 * ra
		var p10 := b + d0 * rb
		var p11 := b + d1 * rb
		_v(st, p00, d0, ca, ha)
		_v(st, p10, d0, cb, hb)
		_v(st, p11, d1, cb, hb)
		_v(st, p00, d0, ca, ha)
		_v(st, p11, d1, cb, hb)
		_v(st, p01, d1, ca, ha)
		if cap and rb > 0.004:
			_v(st, b, ax, cb, hb)
			_v(st, p11, ax, cb, hb)
			_v(st, p10, ax, cb, hb)

static func _v(st: SurfaceTool, p: Vector3, n: Vector3, c: Color, h: float) -> void:
	st.set_color(c)
	st.set_uv(Vector2(0.0, h))
	st.set_normal(n)
	st.add_vertex(p)

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, ha: float, hb: float, hc: float) -> void:
	var n := (b - a).cross(c - a).normalized()
	_v(st, a, n, ca, ha)
	_v(st, b, n, cb, hb)
	_v(st, c, n, cc, hc)

static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

static func _end(st: SurfaceTool, smooth: bool = false) -> ArrayMesh:
	if smooth:
		st.index()
		st.generate_normals()
	return st.commit()

# ------------------------------------------------------------ кораллы

## Ветвистый коралл (акропора/олений рог), ~1 м, основание в 0.
static func coral_branch(lod: int = 0) -> ArrayMesh:
	var key := "branch%d" % lod
	if _cache.has(key):
		return _cache[key]
	var st := _begin()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var seg := 5 if lod == 0 else 3
	var base := Color(0.62, 0.6, 0.55)
	var tip := Color(1.0, 0.98, 0.95)
	var mains := 6 if lod == 0 else 4
	for i in mains:
		var a := TAU * i / mains + rng.randf_range(-0.3, 0.3)
		var lean := rng.randf_range(0.35, 0.8)
		var p0 := Vector3(cos(a) * 0.05, 0.0, sin(a) * 0.05)
		var dir := Vector3(cos(a) * lean, 1.0, sin(a) * lean).normalized()
		var l := rng.randf_range(0.45, 0.7)
		var p1 := p0 + dir * l
		_tube(st, p0, p1, 0.07, 0.045, seg, base, base.lerp(tip, 0.5), 0.0, p1.y, false)
		var subs := 3 if lod == 0 else 1
		for k in subs:
			var t := rng.randf_range(0.45, 1.0)
			var q0 := p0.lerp(p1, t)
			var b := a + rng.randf_range(-1.1, 1.1)
			var d2 := Vector3(cos(b) * 0.6, 1.0, sin(b) * 0.6).normalized()
			var q1 := q0 + d2 * rng.randf_range(0.2, 0.4)
			_tube(st, q0, q1, 0.04, 0.016, seg, base.lerp(tip, 0.5), tip, q0.y, q1.y)
		var p2 := p1 + (dir + Vector3(0, 0.6, 0)).normalized() * rng.randf_range(0.15, 0.3)
		_tube(st, p1, p2, 0.045, 0.018, seg, base.lerp(tip, 0.5), tip, p1.y, p2.y)
	var m := _end(st, true)
	_cache[key] = m
	return m

## Коралл-мозговик: приплюснутый купол с извилинами.
static func coral_brain(lod: int = 0) -> ArrayMesh:
	var key := "brain%d" % lod
	if _cache.has(key):
		return _cache[key]
	var st := _begin()
	var nl := 9 if lod == 0 else 5
	var nr := 16 if lod == 0 else 8
	var pts: Array = []
	for i in nl + 1:
		var row: Array = []
		var lat := (PI * 0.5) * float(i) / nl   # 0 — верх, pi/2 — экватор
		for j in nr + 1:
			var lon := TAU * float(j % nr) / nr
			var ridge := 1.0 + (0.07 * sin(lat * 18.0 + sin(lon * 5.0) * 2.0) * sin(lon * 11.0 + lat * 6.0) if lod == 0 else 0.0)
			var r := 0.5 * ridge
			var p := Vector3(sin(lat) * cos(lon) * r, cos(lat) * r * 0.62 - 0.04, sin(lat) * sin(lon) * r)
			row.append(p)
		pts.append(row)
	for i in nl:
		for j in nr:
			var a: Vector3 = pts[i][j]
			var b: Vector3 = pts[i + 1][j]
			var c: Vector3 = pts[i + 1][j + 1]
			var d: Vector3 = pts[i][j + 1]
			var ca := _brain_col(a)
			var cb := _brain_col(b)
			var cc := _brain_col(c)
			var cd := _brain_col(d)
			_tri(st, a, b, c, ca, cb, cc, a.y, b.y, c.y)
			_tri(st, a, c, d, ca, cc, cd, a.y, c.y, d.y)
	var m := _end(st, true)
	_cache[key] = m
	return m

static func _brain_col(p: Vector3) -> Color:
	var g := 0.78 + 0.22 * sin(p.x * 40.0 + p.z * 31.0) * sin(p.y * 50.0)
	return Color(g, g * 0.97, g * 0.9)

## Столовый коралл: ножка и неровная плоская «столешница».
static func coral_table(lod: int = 0) -> ArrayMesh:
	var key := "table%d" % lod
	if _cache.has(key):
		return _cache[key]
	var st := _begin()
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var c0 := Color(0.6, 0.58, 0.52)
	var c1 := Color(0.95, 0.93, 0.88)
	_tube(st, Vector3.ZERO, Vector3(0.0, 0.32, 0.0), 0.09, 0.06, 6 if lod == 0 else 4, c0, c0, 0.0, 0.3, false)
	var n := 14 if lod == 0 else 8
	var rim: Array[Vector3] = []
	for i in n:
		var a := TAU * i / n
		var r := rng.randf_range(0.42, 0.58)
		rim.append(Vector3(cos(a) * r, 0.36 + rng.randf_range(-0.03, 0.04), sin(a) * r))
	var top := Vector3(0.0, 0.38, 0.0)
	var under := Vector3(0.0, 0.32, 0.0)
	for i in n:
		var a := rim[i]
		var b := rim[(i + 1) % n]
		_tri(st, top, b, a, c1, c1, c1, 0.4, 0.4, 0.4)
		var a2 := a - Vector3(0, 0.04, 0)
		var b2 := b - Vector3(0, 0.04, 0)
		_tri(st, under, a2, b2, c0, c0, c0, 0.35, 0.35, 0.35)
		_tri(st, a, b, b2, c1, c1, c0, 0.4, 0.4, 0.35)
		_tri(st, a, b2, a2, c1, c0, c0, 0.4, 0.35, 0.35)
	var m := _end(st, false)
	_cache[key] = m
	return m

## Морской веер (горгонария): плоская сеть веточек в одной плоскости. Качается.
static func coral_fan() -> ArrayMesh:
	if _cache.has("fan"):
		return _cache["fan"]
	var st := _begin()
	var rng := RandomNumberGenerator.new()
	rng.seed = 37
	var c := Color(1, 1, 1)
	var stack: Array = [[Vector3.ZERO, Vector3.UP, 0.035, 0]]
	while not stack.is_empty():
		var it: Array = stack.pop_back()
		var p: Vector3 = it[0]
		var d: Vector3 = it[1]
		var r: float = it[2]
		var lvl: int = it[3]
		var l := 0.22 if lvl == 0 else rng.randf_range(0.13, 0.22)
		var q := p + d * l
		_tube(st, p, q, r, r * 0.75, 3, c, c, p.y, q.y)
		if lvl < 4:
			for s: float in [-1.0, 1.0]:
				var ang := s * rng.randf_range(0.25, 0.55)
				var nd := Vector3(d.x * cos(ang) - d.y * sin(ang), d.x * sin(ang) + d.y * cos(ang), 0.0).normalized()
				stack.append([q, nd, r * 0.72, lvl + 1])
	var m := _end(st, false)
	_cache["fan"] = m
	return m

## Губка-ваза: открытая расширяющаяся труба.
static func sponge() -> ArrayMesh:
	if _cache.has("sponge"):
		return _cache["sponge"]
	var st := _begin()
	var seg := 10
	var rings := [[0.0, 0.12], [0.18, 0.2], [0.42, 0.26], [0.6, 0.3]]
	var c0 := Color(0.7, 0.7, 0.7)
	var c1 := Color(1, 1, 1)
	for k in rings.size() - 1:
		var y0: float = rings[k][0]
		var y1: float = rings[k + 1][0]
		var r0: float = rings[k][1]
		var r1: float = rings[k + 1][1]
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			var p00 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var p01 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var p10 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var p11 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			var ca := c0.lerp(c1, y0 / 0.6)
			var cb := c0.lerp(c1, y1 / 0.6)
			_tri(st, p00, p10, p11, ca, cb, cb, y0, y1, y1)
			_tri(st, p00, p11, p01, ca, cb, ca, y0, y1, y0)
	# тёмное нутро
	var dark := Color(0.25, 0.2, 0.2)
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		_tri(st, Vector3(0, 0.25, 0), Vector3(cos(a1) * 0.22, 0.4, sin(a1) * 0.22), Vector3(cos(a0) * 0.22, 0.4, sin(a0) * 0.22),
			dark, dark, dark, 0.25, 0.4, 0.4)
	var m := _end(st, true)
	_cache["sponge"] = m
	return m

## Пучок морской травы/водорослей: узкие ленты, высота 1 (UV.y — доля высоты).
static func grass_clump(blades: int = 9) -> ArrayMesh:
	var key := "grass%d" % blades
	if _cache.has(key):
		return _cache[key]
	var st := _begin()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5 + blades
	var cb := Color(0.75, 0.82, 0.55)
	var ct := Color(1.0, 1.0, 0.8)
	for i in blades:
		var a := rng.randf() * TAU
		var base := Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.0, 0.18)
		var h := rng.randf_range(0.6, 1.0)
		var w := rng.randf_range(0.025, 0.045)
		var side := Vector3(-sin(a), 0.0, cos(a)) * w
		var lean := Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.05, 0.25)
		var segs := 3
		for s in segs:
			var t0 := float(s) / segs
			var t1 := float(s + 1) / segs
			var p0 := base + Vector3(0, h * t0, 0) + lean * t0 * t0
			var p1 := base + Vector3(0, h * t1, 0) + lean * t1 * t1
			var w0 := 1.0 - t0 * 0.6
			var w1 := 1.0 - t1 * 0.6
			var c0 := cb.lerp(ct, t0)
			var c1 := cb.lerp(ct, t1)
			_tri(st, p0 - side * w0, p1 - side * w1, p1 + side * w1, c0, c1, c1, t0, t1, t1)
			_tri(st, p0 - side * w0, p1 + side * w1, p0 + side * w0, c0, c1, c0, t0, t1, t0)
	var m := _end(st, false)
	_cache[key] = m
	return m

## Рифовый камень: бугристая полусфера (ниже 0 — в песке).
static func reef_rock(lod: int = 0) -> ArrayMesh:
	var key := "rock%d" % lod
	if _cache.has(key):
		return _cache[key]
	var st := _begin()
	var nl := 6 if lod == 0 else 4
	var nr := 10 if lod == 0 else 6
	var pts: Array = []
	for i in nl + 1:
		var row: Array = []
		var lat := PI * 0.62 * float(i) / nl
		for j in nr + 1:
			var lon := TAU * float(j % nr) / nr
			var n := 1.0 + 0.22 * sin(lon * 3.0 + 1.3) * cos(lat * 2.0) + 0.12 * sin(lon * 7.0 + lat * 5.0)
			var r := 0.5 * n
			row.append(Vector3(sin(lat) * cos(lon) * r, cos(lat) * r * 0.7 - 0.12, sin(lat) * sin(lon) * r * 0.85))
		pts.append(row)
	for i in nl:
		for j in nr:
			var a: Vector3 = pts[i][j]
			var b: Vector3 = pts[i + 1][j]
			var c: Vector3 = pts[i + 1][j + 1]
			var d: Vector3 = pts[i][j + 1]
			var g := 0.85 + 0.15 * sin(a.x * 13.0 + a.z * 9.0)
			var col := Color(g, g, g * 0.95)
			_tri(st, a, b, c, col, col, col, 0.0, 0.0, 0.0)
			_tri(st, a, c, d, col, col, col, 0.0, 0.0, 0.0)
	var m := _end(st, true)
	_cache[key] = m
	return m

# ------------------------------------------------------------ обитатели

## Скат: плоский ромб с толщиной, тёмная спина в пятнах, светлое брюхо, хвост-хлыст. Нос в -Z.
static func ray_mesh() -> ArrayMesh:
	if _cache.has("ray"):
		return _cache["ray"]
	var st := _begin()
	var nx := 10
	var nz := 8
	var top: Array = []
	var bot: Array = []
	for i in nz + 1:
		var z := lerpf(-0.6, 0.55, float(i) / nz)
		var half := 1.0 - absf(z + 0.05) / 0.62
		half = clampf(half, 0.0, 1.0) * 0.95
		var rt: Array = []
		var rb: Array = []
		for j in nx + 1:
			var x := lerpf(-half, half, float(j) / nx)
			var th := 0.09 * (1.0 - pow(absf(x) / maxf(half, 0.001), 2.0)) * (1.0 - absf(z) * 0.8)
			rt.append(Vector3(x, th, z))
			rb.append(Vector3(x, -th * 0.6, z))
		top.append(rt)
		bot.append(rb)
	for i in nz:
		for j in nx:
			var a: Vector3 = top[i][j]
			var b: Vector3 = top[i + 1][j]
			var c: Vector3 = top[i + 1][j + 1]
			var d: Vector3 = top[i][j + 1]
			var spot := (1.0 if sin(a.x * 23.0) * sin(a.z * 19.0) > 0.6 else 0.75)
			var ct := Color(0.24, 0.22, 0.2) * spot
			ct.a = 1.0
			_tri(st, a, c, b, ct, ct, ct, 0, 0, 0)
			_tri(st, a, d, c, ct, ct, ct, 0, 0, 0)
			var a2: Vector3 = bot[i][j]
			var b2: Vector3 = bot[i + 1][j]
			var c2: Vector3 = bot[i + 1][j + 1]
			var d2: Vector3 = bot[i][j + 1]
			var cw := Color(0.88, 0.86, 0.82)
			_tri(st, a2, b2, c2, cw, cw, cw, 0, 0, 0)
			_tri(st, a2, c2, d2, cw, cw, cw, 0, 0, 0)
	var tc := Color(0.2, 0.19, 0.18)
	_tube(st, Vector3(0, 0, 0.5), Vector3(0, 0.02, 1.5), 0.035, 0.006, 4, tc, tc, 0, 0)
	var m := _end(st, true)
	_cache["ray"] = m
	return m

## Морская черепаха: панцирь-купол, брюхо, голова, 4 ласты (COLOR.a — маска гребка). Нос в -Z.
static func turtle_mesh() -> ArrayMesh:
	if _cache.has("turtle"):
		return _cache["turtle"]
	var st := _begin()
	var nl := 7
	var nr := 14
	for i in nl:
		for j in nr:
			var p := [_shell(i, j, nl, nr), _shell(i + 1, j, nl, nr), _shell(i + 1, j + 1, nl, nr), _shell(i, j + 1, nl, nr)]
			var col := _shell_col(p[0])
			_tri(st, p[0], p[1], p[2], col, col, col, 0, 0, 0)
			_tri(st, p[0], p[2], p[3], col, col, col, 0, 0, 0)
	# брюхо (пластрон)
	var bc := Color(0.86, 0.78, 0.55)
	for j in nr:
		var a := _shell(nl, j, nl, nr)
		var b := _shell(nl, j + 1, nl, nr)
		_tri(st, Vector3(0, -0.06, 0), b, a, bc, bc, bc, 0, 0, 0)
	var skin := Color(0.42, 0.4, 0.3)
	skin.a = 0.0
	# голова и шея
	_tube(st, Vector3(0, -0.01, -0.36), Vector3(0, 0.0, -0.5), 0.07, 0.065, 6, skin, skin, 0, 0, false)
	_tube(st, Vector3(0, 0.0, -0.5), Vector3(0, -0.01, -0.6), 0.065, 0.03, 6, skin, skin, 0, 0)
	# ласты: передние длинные, задние короткие
	for s: float in [-1.0, 1.0]:
		var cf := Color(0.38, 0.36, 0.27, 1.0)
		_flipper(st, Vector3(s * 0.2, -0.02, -0.18), Vector3(s * 0.62, -0.05, 0.02), 0.12, cf)
		var cr := Color(0.38, 0.36, 0.27, 0.5)
		_flipper(st, Vector3(s * 0.14, -0.03, 0.3), Vector3(s * 0.32, -0.05, 0.46), 0.07, cr)
	var m := _end(st, false)
	_cache["turtle"] = m
	return m

static func _shell(i: int, j: int, nl: int, nr: int) -> Vector3:
	var lat := (PI * 0.5) * float(i) / nl
	var lon := TAU * float(j % nr) / nr
	return Vector3(sin(lat) * cos(lon) * 0.3, cos(lat) * 0.13 - 0.02, sin(lat) * sin(lon) * 0.4)

static func _shell_col(p: Vector3) -> Color:
	var plate := 0.8 + 0.2 * sin(p.x * 30.0) * sin(p.z * 26.0)
	var c := Color(0.42, 0.32, 0.18).lerp(Color(0.58, 0.46, 0.26), plate - 0.6)
	c.a = 0.0
	return c

static func _flipper(st: SurfaceTool, root: Vector3, tip: Vector3, w: float, c: Color) -> void:
	var d := tip - root
	var side := Vector3(-d.z, 0.0, d.x).normalized() * w
	var mid := root.lerp(tip, 0.45)
	var pts := [root + side * 0.5, mid + side, tip, mid - side * 0.6, root - side * 0.5]
	var t := 0.015
	for k in pts.size() - 2:
		var a: Vector3 = pts[0]
		var b: Vector3 = pts[k + 1]
		var cc: Vector3 = pts[k + 2]
		_tri(st, a + Vector3(0, t, 0), b + Vector3(0, t, 0), cc + Vector3(0, t, 0), c, c, c, 0, 0, 0)
		_tri(st, a - Vector3(0, t, 0), cc - Vector3(0, t, 0), b - Vector3(0, t, 0), c, c, c, 0, 0, 0)

## Медуза: купол (UV.x 0..1, UV.y 0 — макушка, 1 — край) и щупальца (UV.x ≥ 2).
static func jelly_mesh() -> ArrayMesh:
	if _cache.has("jelly"):
		return _cache["jelly"]
	var st := _begin()
	var nl := 6
	var nr := 14
	var col := Color(1, 1, 1, 1)
	for i in nl:
		for j in nr:
			var e0 := float(i) / nl
			var e1 := float(i + 1) / nl
			var a := _bell(e0, j, nr)
			var b := _bell(e1, j, nr)
			var c := _bell(e1, j + 1, nr)
			var d := _bell(e0, j + 1, nr)
			for v in [[a, e0], [b, e1], [c, e1], [a, e0], [c, e1], [d, e0]]:
				st.set_color(col)
				st.set_uv(Vector2(float(j) / nr, float(v[1])))
				st.set_normal((v[0] as Vector3).normalized())
				st.add_vertex(v[0])
	# щупальца-ленты
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for k in 10:
		var a := TAU * k / 10.0 + rng.randf() * 0.3
		var r := 0.17 + rng.randf() * 0.05
		var ln := rng.randf_range(0.5, 0.95)
		var base := Vector3(cos(a) * r, -0.02, sin(a) * r)
		var side := Vector3(-sin(a), 0, cos(a)) * 0.012
		var segs := 5
		for s in segs:
			var y0 := -ln * s / segs
			var y1 := -ln * (s + 1) / segs
			var p0 := base + Vector3(0, y0, 0)
			var p1 := base + Vector3(0, y1, 0)
			var c0 := Color(1, 1, 1, 0.8 - 0.6 * s / segs)
			var c1 := Color(1, 1, 1, 0.8 - 0.6 * (s + 1) / segs)
			var uv := Vector2(2.0 + k, 0.0)
			for v in [[p0 - side, c0], [p1 - side, c1], [p1 + side, c1], [p0 - side, c0], [p1 + side, c1], [p0 + side, c0]]:
				st.set_color(v[1])
				st.set_uv(uv)
				st.set_normal(Vector3(cos(a), 0, sin(a)))
				st.add_vertex(v[0])
	var m := st.commit()
	_cache["jelly"] = m
	return m

static func _bell(e: float, j: int, nr: int) -> Vector3:
	var lon := TAU * float(j % nr) / nr
	var lat := e * PI * 0.5
	var r := sin(lat) * 0.24
	return Vector3(cos(lon) * r, cos(lat) * 0.17, sin(lon) * r)

## Верша: плетёный конус с горлом (лежит на боку после поворота).
static func trap_basket() -> ArrayMesh:
	if _cache.has("trap"):
		return _cache["trap"]
	var st := _begin()
	var seg := 8
	var c := Color(0.62, 0.5, 0.3)
	var cd := Color(0.45, 0.35, 0.2)
	# продольные прутья
	for i in seg:
		var a := TAU * i / seg
		var p0 := Vector3(cos(a) * 0.28, -0.4, sin(a) * 0.28)
		var p1 := Vector3(cos(a) * 0.18, 0.25, sin(a) * 0.18)
		var p2 := Vector3(cos(a) * 0.04, 0.42, sin(a) * 0.04)
		_tube(st, p0, p1, 0.012, 0.012, 3, c, c, 0, 0, false)
		_tube(st, p1, p2, 0.012, 0.01, 3, c, c, 0, 0, false)
	# обручи
	for y in [-0.4, -0.15, 0.1, 0.3]:
		var r := lerpf(0.28, 0.12, (y + 0.4) / 0.8)
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			_tube(st, Vector3(cos(a0) * r, y, sin(a0) * r), Vector3(cos(a1) * r, y, sin(a1) * r), 0.014, 0.014, 3, cd, cd, 0, 0, false)
	var m := _end(st, false)
	_cache["trap"] = m
	return m
