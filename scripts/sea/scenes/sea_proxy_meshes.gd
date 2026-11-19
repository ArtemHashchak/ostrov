class_name SeaProxyMeshes
extends RefCounted
## Простые меши-«дублёры» для видов океанского состава, у которых ещё нет модели
## (assets/sea_scenes/ocean_roster.json → stand_in.proxy). Это временные силуэты:
## когда придёт настоящая модель, её путь пишется в «model» вида, а этот код не нужен.
## Цвета — в вершинах (COLOR.rgb), COLOR.a — «вес изгиба» (0 у основания/головы … 1 на конце):
## шейдер sea_proxy.gdshader по нему гнёт тело/стебель.
## Все меши смотрят «вперёд» в −Z; длина/высота ≈ 1 м (масштаб — у узла).

static var _cache: Dictionary = {}

static func get_mesh(kind: String, colors: Array) -> Mesh:
	var key := kind + "|" + str(colors)
	if _cache.has(key):
		return _cache[key]
	var a := Color(String(colors[0])) if colors.size() > 0 else Color(0.6, 0.6, 0.6)
	var b := Color(String(colors[colors.size() - 1])) if colors.size() > 1 else a.darkened(0.3)
	var m: Mesh = null
	match kind:
		"eel":
			m = _eel(a, b)
		"ray":
			m = _recolor(SeaMeshes.ray_mesh(), a, b)
		"turtle":
			m = SeaMeshes.turtle_mesh()
		"jelly":
			m = _recolor(SeaMeshes.jelly_mesh(), a, b)
		"star":
			m = _star(a, b)
		"urchin":
			m = _urchin(a, b)
		"seahorse":
			m = _seahorse(a, b)
		"shrimp":
			m = _shrimp(a, b)
		"kelp":
			m = _kelp(a, b)
		"sargassum":
			m = _sargassum(a, b)
		"grass":
			m = _grass(a, b)
		"halimeda":
			m = _halimeda(a, b)
		"caulerpa":
			m = _caulerpa(a, b)
		"red_algae":
			m = _red_algae(a, b)
		"tube_sponge":
			m = _tube_sponge(a, b)
		"sponge":
			m = _recolor(SeaMeshes.sponge(), a, b)
		"anemone":
			m = _anemone(a, b)
		_:
			m = FishSchool.make_fish_mesh(1.0)
	_cache[key] = m
	return m

static func clear_cache() -> void:
	_cache.clear()

# --- помощники ---------------------------------------------------------------

static func _st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

static func _end(st: SurfaceTool) -> ArrayMesh:
	st.generate_normals()
	return st.commit()

static func _v(st: SurfaceTool, p: Vector3, c: Color, w: float) -> void:
	st.set_color(Color(c.r, c.g, c.b, clampf(w, 0.0, 1.0)))
	st.add_vertex(p)

static func _tri(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, c0: Color, c1: Color, c2: Color, w0: float, w1: float, w2: float) -> void:
	_v(st, p0, c0, w0)
	_v(st, p1, c1, w1)
	_v(st, p2, c2, w2)

## Трубка по точкам (кольца радиусов r[i]); w[i] — вес изгиба; цвет по длине a→b.
static func _tube(st: SurfaceTool, pts: Array, rad: Array, w: Array, a: Color, b: Color, seg: int = 6, cap: bool = true) -> void:
	var n := pts.size()
	var rings: Array = []
	for i in n:
		var p: Vector3 = pts[i]
		var d: Vector3 = ((pts[mini(i + 1, n - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)).normalized()
		var up := Vector3.UP if absf(d.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
		var x := d.cross(up).normalized()
		var y := x.cross(d).normalized()
		var ring: Array = []
		for k in seg:
			var t := TAU * k / seg
			ring.append(p + (x * cos(t) + y * sin(t)) * float(rad[i]))
		rings.append(ring)
	for i in n - 1:
		var ca := a.lerp(b, float(i) / maxf(n - 1, 1))
		var cb := a.lerp(b, float(i + 1) / maxf(n - 1, 1))
		for k in seg:
			var k2 := (k + 1) % seg
			_tri(st, rings[i][k], rings[i + 1][k], rings[i + 1][k2], ca, cb, cb, w[i], w[i + 1], w[i + 1])
			_tri(st, rings[i][k], rings[i + 1][k2], rings[i][k2], ca, cb, ca, w[i], w[i + 1], w[i])
	if cap and n > 1:
		var e: Vector3 = pts[n - 1]
		for k in seg:
			_tri(st, rings[n - 1][k], e, rings[n - 1][(k + 1) % seg], b, b, b, w[n - 1], w[n - 1], w[n - 1])

## Плоская лента (лист): точки стебля, ширина, нормаль ленты.
static func _ribbon(st: SurfaceTool, pts: Array, width: Array, side: Vector3, w: Array, a: Color, b: Color) -> void:
	var n := pts.size()
	for i in n - 1:
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[i + 1]
		var s0 := side * float(width[i]) * 0.5
		var s1 := side * float(width[i + 1]) * 0.5
		var c0 := a.lerp(b, float(i) / maxf(n - 1, 1))
		var c1 := a.lerp(b, float(i + 1) / maxf(n - 1, 1))
		_tri(st, p0 - s0, p1 - s1, p1 + s1, c0, c1, c1, w[i], w[i + 1], w[i + 1])
		_tri(st, p0 - s0, p1 + s1, p0 + s0, c0, c1, c0, w[i], w[i + 1], w[i])

static func _recolor(src: Mesh, a: Color, b: Color) -> Mesh:
	if src == null:
		return null
	var st := SurfaceTool.new()
	st.create_from(src, 0)
	var arr := st.commit_to_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cols := PackedColorArray()
	cols.resize(verts.size())
	var aabb := src.get_aabb()
	var old: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	for i in verts.size():
		var v := verts[i]
		var top := clampf((v.y - aabb.position.y) / maxf(aabb.size.y, 0.001), 0.0, 1.0)
		var c := b.lerp(a, top)
		if old.size() == verts.size():
			var l := (old[i].r + old[i].g + old[i].b) / 3.0
			c = c * (0.65 + 0.7 * l)
		var w := clampf(absf(v.x) / maxf(aabb.size.x * 0.5, 0.001), 0.0, 1.0)
		cols[i] = Color(c.r, c.g, c.b, w)
	arr[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

# --- животные ------------------------------------------------------------------

## Мурена: длинная трубка, голова в −Z, сжатая с боков, спинной плавник-гребень.
static func _eel(a: Color, b: Color) -> ArrayMesh:
	var st := _st()
	var pts: Array = []
	var rad: Array = []
	var w: Array = []
	var n := 14
	for i in n:
		var t := float(i) / (n - 1)
		pts.append(Vector3(0.0, 0.0, -0.5 + t))
		rad.append(0.05 * (1.0 - pow(t, 3.0)) + 0.006 if t > 0.06 else 0.035 + t * 0.25)
		w.append(t)
	_tube(st, pts, rad, w, a, b, 7)
	# гребень-плавник по спине
	for i in n - 2:
		var t0 := float(i + 1) / (n - 1)
		var t1 := float(i + 2) / (n - 1)
		var h0 := 0.05 * (1.0 - t0 * 0.5)
		var h1 := 0.05 * (1.0 - t1 * 0.5)
		_tri(st, pts[i + 1] + Vector3(0, rad[i + 1], 0), pts[i + 2] + Vector3(0, rad[i + 2], 0), pts[i + 2] + Vector3(0, rad[i + 2] + h1, 0), b, b, b, t0, t1, t1)
		_tri(st, pts[i + 1] + Vector3(0, rad[i + 1], 0), pts[i + 2] + Vector3(0, rad[i + 2] + h1, 0), pts[i + 1] + Vector3(0, rad[i + 1] + h0, 0), b, b, b, t0, t1, t0)
	return _end(st)

## Морская звезда: 5 лучей, плоская, бугорки.
static func _star(a: Color, b: Color) -> ArrayMesh:
	var st := _st()
	var c := Vector3(0, 0.05, 0)
	for k in 5:
		var ang := TAU * k / 5.0
		var d := Vector3(cos(ang), 0, sin(ang))
		var s := Vector3(-d.z, 0, d.x)
		var ang2 := ang + TAU / 10.0
		var mid := Vector3(cos(ang2), 0, sin(ang2)) * 0.16
		var mid0 := Vector3(cos(ang - TAU / 10.0), 0, sin(ang - TAU / 10.0)) * 0.16
		var tip := d * 0.5 + Vector3(0, 0.01, 0)
		var ridge := d * 0.25 + Vector3(0, 0.06, 0)
		_tri(st, c, mid0, ridge, a, b, a, 0.0, 0.3, 0.5)
		_tri(st, ridge, mid0, tip, a, b, b, 0.5, 0.3, 1.0)
		_tri(st, c, ridge, mid, a, a, b, 0.0, 0.5, 0.3)
		_tri(st, ridge, tip, mid, a, b, b, 0.5, 1.0, 0.3)
		_tri(st, mid0, Vector3(0, 0, 0), tip, b, b, b, 0.3, 0.0, 1.0)
		_tri(st, Vector3(0, 0, 0), mid, tip, b, b, b, 0.0, 0.3, 1.0)
		var _u := s
	return _end(st)

## Морской ёж: тёмный шар с иглами.
static func _urchin(a: Color, b: Color) -> ArrayMesh:
	var st := _st()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var R := 0.22
	var rings := 6
	var seg := 10
	var pts: Array = []
	for i in rings + 1:
		var phi := PI * 0.5 * float(i) / rings
		var row: Array = []
		for k in seg:
			var th := TAU * k / seg
			row.append(Vector3(cos(th) * cos(phi) * R, sin(phi) * R * 0.8 + 0.02, sin(th) * cos(phi) * R))
		pts.append(row)
	for i in rings:
		for k in seg:
			var k2 := (k + 1) % seg
			_tri(st, pts[i][k], pts[i + 1][k], pts[i + 1][k2], b, b, b, 0, 0, 0)
			_tri(st, pts[i][k], pts[i + 1][k2], pts[i][k2], b, b, b, 0, 0, 0)
	for n in 70:
		var th := rng.randf() * TAU
		var phi := rng.randf_range(0.05, 1.45)
		var d := Vector3(cos(th) * cos(phi), sin(phi) * 0.85, sin(th) * cos(phi)).normalized()
		var base := d * R * 0.95 + Vector3(0, 0.02, 0)
		var tip := base + d * rng.randf_range(0.25, 0.4)
		var side := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized() * 0.012
		_tri(st, base - side, tip, base + side, a, a, a, 0.0, 1.0, 0.0)
		var side2 := d.cross(side).normalized() * 0.012
		_tri(st, base - side2, tip, base + side2, a, a, a, 0.0, 1.0, 0.0)
	return _end(st)

## Морской конёк: вертикальная S-трубка, голова с рыльцем, хвост-завиток.
static func _seahorse(a: Color, b: Color) -> ArrayMesh:
	var st := _st()
	var pts: Array = []
	var rad: Array = []
	var w: Array = []
	var n := 16
	for i in n:
		var t := float(i) / (n - 1)
		# сверху (голова) вниз к хвосту-завитку
		var y := 0.5 - t * 0.85
		var z := sin(t * PI * 1.2) * 0.08 - (0.12 * smoothstep(0.75, 1.0, t))
		var x := 0.0
		if t > 0.75:
			var u := (t - 0.75) / 0.25
			z = -0.04 + sin(u * PI * 1.4) * 0.09
			y = -0.2 - (1.0 - cos(u * PI * 1.4)) * 0.06
		pts.append(Vector3(x, y, z))
		rad.append(lerpf(0.06, 0.012, t) * (1.0 + 0.4 * sin(t * PI)))
		w.append(t)
	_tube(st, pts, rad, w, a, b, 6)
	# рыльце
	_tube(st, [pts[1], (pts[1] as Vector3) + Vector3(0, -0.02, -0.14)], [0.025, 0.012], [0.0, 0.0], a, a, 5)
	return _end(st)

## Креветка: изогнутое тельце, полосы, усики.
static func _shrimp(a: Color, b: Color) -> ArrayMesh:
	var st := _st()
	var pts: Array = []
	var rad: Array = []
	var w: Array = []
	var cols_a := a
	for i in 9:
		var t := float(i) / 8.0
		pts.append(Vector3(0, sin(t * PI) * 0.12, -0.5 + t))
		rad.append(0.09 * (1.0 - t * 0.7))
		w.append(t)
	_tube(st, pts, rad, w, cols_a, b, 6)
	for s in [-1.0, 1.0]:
		var base := Vector3(0.02 * s, 0.04, -0.5)
		_tri(st, base, base + Vector3(0.25 * s, 0.25, -0.5), base + Vector3(0.01 * s, 0.0, -0.02), b, b, b, 0.0, 1.0, 0.0)
	return _end(st)

# --- растения ------------------------------------------------------------------

static func _kelp(a: Color, b: Color) -> ArrayMesh:
	var st := _st()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for s in 4:
		var ang := rng.randf() * TAU
		var lean := Vector3(cos(ang), 0, sin(ang)) * rng.randf_range(0.02, 0.08)
		var pts: Array = []
		var wid: Array = []
		var w: Array = []
		var n := 12
		for i in n:
			var t := float(i) / (n - 1)
			pts.append(Vector3(sin(t * 7.0 + s) * 0.04, t, 0.0) + lean * t * 4.0)
			wid.append(lerpf(0.03, 0.16, smoothstep(0.0, 0.25, t)) * (1.0 - t * 0.35))
			w.append(t)
		var side := Vector3(cos(ang + PI * 0.5), 0, sin(ang + PI * 0.5))
		_ribbon(st, pts, wid, side, w, b, a)
		# воздушные пузыри у листьев
		for i in range(3, n, 3):
			var p: Vector3 = pts[i]
			_tube(st, [p, p + Vector3(0, 0.03, 0)], [0.02, 0.0], [w[i], w[i]], a, a, 5, false)
	return _end(st)

static func _sargassum(a: Color, b: Color) -> ArrayMesh:
	var st := _st()
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for k in 26:
		var p := Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.12, 0.05), rng.randf_range(-0.5, 0.5))
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 0.3), rng.randf_range(-1, 1)).normalized() * rng.randf_range(0.1, 0.2)
		var side := d.cross(Vector3.UP).normalized() * 0.03
		var wt := clampf(p.length(), 0.0, 1.0)
		_tri(st, p - side, p + d, p + side, b, a, b, wt, 1.0, wt)
		# пузырьки-поплавки
		var q := p + d * 0.5
		_tube(st, [q, q + Vector3(0, 0.025, 0)], [0.018, 0.0], [wt, wt], a.lightened(0.2), a.lightened(0.2), 5, false)
	return _end(st)

static func _grass(a: Color, b: Color) -> ArrayMesh:
	var st := _st()
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	for k in 14:
		var p := Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
		var ang := rng.randf() * TAU
		var side := Vector3(cos(ang), 0, sin(ang))
		var h := rng.randf_range(0.6, 1.0)
		var lean := Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15))
		var pts := [p, p + Vector3(0, h * 0.5, 0) + lean * 0.4, p + Vector3(0, h, 0) + lean]
		_ribbon(st, pts, [0.035, 0.03, 0.01], side, [0.0, 0.5, 1.0], b, a)
	return _end(st)

static func _halimeda(a: Color, b: Color) -> ArrayMesh:
	var st := _st()
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for chain in 5:
		var p := Vector3(rng.randf_range(-0.1, 0.1), 0, rng.randf_range(-0.1, 0.1))
		var d := Vector3(rng.randf_range(-0.4, 0.4), 1.0, rng.randf_range(-0.4, 0.4)).normalized()
		for seg in 6:
			var t := float(seg) / 6.0
			var c := p + Vector3(0, 0.02, 0)
			var r := 0.06 * (1.0 - t * 0.3)
			var side := d.cross(Vector3.FORWARD).normalized()
			# диск-сегмент
			for k in 6:
				var a0 := TAU * k / 6.0
				var a1 := TAU * (k + 1) / 6.0
				var u0 := side * cos(a0) * r + d * sin(a0) * r * 0.7
				var u1 := side * cos(a1) * r + d * sin(a1) * r * 0.7
				_tri(st, c, c + u0, c + u1, a, b, b, t, t, t)
			p += d * 0.11
			d = (d + Vector3(rng.randf_range(-0.3, 0.3), 0.1, rng.randf_range(-0.3, 0.3))).normalized()
	return _end(st)

static func _caulerpa(a: Color, b: Color) -> ArrayMesh:
	var st := _st()
	var rng := RandomNumberGenerator.new()
	rng.seed = 51
	# стелющийся побег с перистыми веточками
	var runner: Array = []
	for i in 8:
		runner.append(Vector3(-0.5 + i / 7.0, 0.01, sin(i * 0.9) * 0.08))
	_tube(st, runner, [0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01], [0, 0, 0, 0, 0, 0, 0, 0], b, b, 4, false)
	for i in range(1, 8):
		var base: Vector3 = runner[i]
		var h := rng.randf_range(0.5, 1.0)
		var top := base + Vector3(rng.randf_range(-0.05, 0.05), h, 0)
		_tube(st, [base, top], [0.008, 0.004], [0.0, 1.0], b, a, 4, false)
		for j in 6:
			var t := 0.3 + j * 0.12
			var p := base.lerp(top, t)
			for s in [-1.0, 1.0]:
				_tri(st, p, p + Vector3(0.07 * s, 0.05, 0.0), p + Vector3(0, 0.03, 0), a, a, a, t, t, t)
	return _end(st)

static func _red_algae(a: Color, b: Color) -> ArrayMesh:
	var st := _st()
	var rng := RandomNumberGenerator.new()
	rng.seed = 61
	for f in 7:
		var p := Vector3(rng.randf_range(-0.1, 0.1), 0, rng.randf_range(-0.1, 0.1))
		var ang := rng.randf() * TAU
		var side := Vector3(cos(ang), 0, sin(ang))
		var pts: Array = [p]
		var wid: Array = [0.02]
		var w: Array = [0.0]
		var d := Vector3(rng.randf_range(-0.3, 0.3), 1.0, rng.randf_range(-0.3, 0.3)).normalized()
		for i in 5:
			p += d * 0.18
			d = (d + Vector3(rng.randf_range(-0.4, 0.4), 0.0, rng.randf_range(-0.4, 0.4))).normalized()
			pts.append(p)
			wid.append(0.08 + 0.06 * sin(i * 1.3))
			w.append(float(i + 1) / 5.0)
		_ribbon(st, pts, wid, side, w, b, a)
	return _end(st)

static func _tube_sponge(a: Color, b: Color) -> ArrayMesh:
	var st := _st()
	var rng := RandomNumberGenerator.new()
	rng.seed = 71
	for k in 5:
		var p := Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15))
		var h := rng.randf_range(0.5, 1.0)
		var lean := Vector3(rng.randf_range(-0.1, 0.1), 0, rng.randf_range(-0.1, 0.1))
		var r := rng.randf_range(0.05, 0.09)
		var col := a if k % 2 == 0 else b
		_tube(st, [p, p + Vector3(0, h * 0.5, 0) + lean * 0.5, p + Vector3(0, h, 0) + lean], [r * 0.8, r, r * 1.1], [0.0, 0.0, 0.0], col.darkened(0.25), col, 8, false)
	return _end(st)

static func _anemone(a: Color, b: Color) -> ArrayMesh:
	var st := _st()
	var rng := RandomNumberGenerator.new()
	rng.seed = 81
	# ножка-диск
	_tube(st, [Vector3.ZERO, Vector3(0, 0.12, 0)], [0.16, 0.18], [0.0, 0.0], b, b, 10, false)
	for k in 90:
		var r := sqrt(rng.randf()) * 0.17
		var th := rng.randf() * TAU
		var p := Vector3(cos(th) * r, 0.12, sin(th) * r)
		var out := Vector3(cos(th), 0, sin(th))
		var h := rng.randf_range(0.18, 0.3)
		var pts: Array = []
		for i in 5:
			var t := float(i) / 4.0
			pts.append(p + Vector3(0, h * t, 0) + out * (r * 0.6 + 0.12) * t * t + Vector3(sin(t * 3.0 + k) * 0.015, 0, 0))
		_tube(st, pts, [0.012, 0.011, 0.01, 0.009, 0.007], [0.1, 0.35, 0.6, 0.85, 1.0], b, a, 4, true)
	return _end(st)
