class_name ReefMeshes
extends RefCounted
## Процедурные меши живого рифа.
## Рыбы (reef_fish.gdshader): голова в -Z, хвост в +Z, длина 1 (масштаб — INSTANCE_CUSTOM.z).
##   UV.x — от носа к хвосту, COLOR.r — спинность, COLOR.g — глаз, COLOR.a — плавник.
## Ходоки (crawler.gdshader): COLOR.rgb — цвет, COLOR.a — нога, UV.x — фаза ноги, UV.y — высота усика.
## Декор (coral.gdshader): COLOR.rgb — цвет, UV.y — высота 0..1 (качание).

static var _cache: Dictionary = {}

static func clear_cache() -> void:
	_cache.clear()

static func cached(key: String, maker: Callable) -> ArrayMesh:
	if not _cache.has(key):
		_cache[key] = maker.call()
	return _cache[key]

# ============================ рыбы ============================

## Формы тела: prof — [u, полувысота, полуширина]; pu — хвостовой стебель;
## tail — [тип, полувысота]; fins — [u0, u1, высота, сторона(+1 спина/-1 брюхо), форма(0 ровный, 1 высокий спереди)].
const SHAPES := {
	&"disc": {"prof": [[0.0, 0.0, 0.0], [0.05, 0.12, 0.035], [0.15, 0.29, 0.06], [0.35, 0.35, 0.075], [0.55, 0.3, 0.065], [0.72, 0.14, 0.04], [0.8, 0.06, 0.022]],
		"pu": 0.8, "tail": [&"lunate", 0.19], "fins": [[0.2, 0.76, 0.1, 1, 0], [0.42, 0.76, 0.09, -1, 0]], "pec": 0.07},
	&"butterfly": {"prof": [[0.0, 0.0, 0.0], [0.06, 0.06, 0.03], [0.16, 0.25, 0.05], [0.38, 0.34, 0.065], [0.6, 0.3, 0.06], [0.76, 0.12, 0.035], [0.82, 0.06, 0.02]],
		"pu": 0.82, "tail": [&"square", 0.13], "fins": [[0.18, 0.8, 0.12, 1, 0], [0.38, 0.8, 0.1, -1, 0]], "pec": 0.06},
	&"idol": {"prof": [[0.0, 0.0, 0.0], [0.07, 0.07, 0.03], [0.18, 0.27, 0.055], [0.38, 0.32, 0.065], [0.58, 0.26, 0.055], [0.74, 0.1, 0.03], [0.8, 0.05, 0.02]],
		"pu": 0.8, "tail": [&"lunate", 0.15], "fins": [[0.2, 0.62, 0.62, 1, 1], [0.3, 0.68, 0.3, -1, 1]], "pec": 0.06},
	&"angel": {"prof": [[0.0, 0.0, 0.0], [0.05, 0.1, 0.035], [0.15, 0.26, 0.06], [0.38, 0.33, 0.075], [0.6, 0.28, 0.065], [0.76, 0.13, 0.04], [0.82, 0.07, 0.025]],
		"pu": 0.82, "tail": [&"round", 0.15], "fins": [[0.2, 0.84, 0.14, 1, 0], [0.36, 0.84, 0.13, -1, 0]], "pec": 0.07},
	&"oval": {"prof": [[0.0, 0.0, 0.0], [0.05, 0.07, 0.05], [0.2, 0.18, 0.09], [0.45, 0.2, 0.09], [0.7, 0.11, 0.06], [0.82, 0.05, 0.03]],
		"pu": 0.82, "tail": [&"fork", 0.16], "fins": [[0.25, 0.75, 0.08, 1, 0], [0.55, 0.76, 0.06, -1, 0]], "pec": 0.07},
	&"clown": {"prof": [[0.0, 0.0, 0.0], [0.05, 0.09, 0.06], [0.2, 0.19, 0.1], [0.45, 0.2, 0.1], [0.7, 0.12, 0.07], [0.8, 0.07, 0.04]],
		"pu": 0.8, "tail": [&"round", 0.14], "fins": [[0.25, 0.76, 0.09, 1, 0], [0.55, 0.76, 0.07, -1, 0]], "pec": 0.08},
	&"slim": {"prof": [[0.0, 0.0, 0.0], [0.05, 0.045, 0.035], [0.2, 0.11, 0.07], [0.5, 0.12, 0.07], [0.75, 0.06, 0.04], [0.84, 0.03, 0.02]],
		"pu": 0.84, "tail": [&"fork", 0.12], "fins": [[0.3, 0.55, 0.05, 1, 0], [0.6, 0.76, 0.04, -1, 0]], "pec": 0.05},
	&"parrot": {"prof": [[0.0, 0.0, 0.0], [0.04, 0.1, 0.08], [0.18, 0.2, 0.12], [0.45, 0.22, 0.12], [0.7, 0.13, 0.08], [0.82, 0.07, 0.04]],
		"pu": 0.82, "tail": [&"square", 0.15], "fins": [[0.2, 0.78, 0.06, 1, 0], [0.55, 0.78, 0.05, -1, 0]], "pec": 0.07},
	&"grouper": {"prof": [[0.0, 0.0, 0.0], [0.05, 0.12, 0.1], [0.2, 0.2, 0.15], [0.45, 0.21, 0.15], [0.72, 0.12, 0.09], [0.82, 0.07, 0.05]],
		"pu": 0.82, "tail": [&"round", 0.13], "fins": [[0.2, 0.75, 0.07, 1, 0], [0.55, 0.78, 0.06, -1, 0]], "pec": 0.08},
	&"barracuda": {"prof": [[0.0, 0.0, 0.0], [0.06, 0.035, 0.03], [0.25, 0.07, 0.06], [0.55, 0.075, 0.06], [0.82, 0.04, 0.03], [0.88, 0.02, 0.015]],
		"pu": 0.88, "tail": [&"fork", 0.1], "fins": [[0.35, 0.42, 0.05, 1, 1], [0.62, 0.7, 0.04, 1, 0], [0.64, 0.72, 0.04, -1, 0]], "pec": 0.04},
	&"jack": {"prof": [[0.0, 0.0, 0.0], [0.05, 0.12, 0.05], [0.2, 0.26, 0.08], [0.45, 0.25, 0.08], [0.72, 0.08, 0.04], [0.84, 0.03, 0.02]],
		"pu": 0.84, "tail": [&"lunate", 0.22], "fins": [[0.3, 0.7, 0.1, 1, 1], [0.5, 0.72, 0.08, -1, 1]], "pec": 0.06},
}

static func fish(shape: StringName) -> ArrayMesh:
	return cached("fish_" + String(shape), func() -> ArrayMesh: return _build_fish(SHAPES[shape]))

static func _prof_at(prof: Array, u: float) -> Vector2:
	for i in range(1, prof.size()):
		var a: Array = prof[i - 1]
		var b: Array = prof[i]
		if u <= float(b[0]):
			var k := inverse_lerp(float(a[0]), float(b[0]), u)
			return Vector2(lerpf(a[1], b[1], k), lerpf(a[2], b[2], k))
	var l: Array = prof[prof.size() - 1]
	return Vector2(l[1], l[2])

static func _build_fish(cfg: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prof: Array = cfg["prof"]
	var pu: float = cfg["pu"]
	const R := 10
	const NR := 12
	var rings: Array = []
	for i in NR:
		var u := lerpf(0.03, pu, float(i) / float(NR - 1))
		var hw := _prof_at(prof, u)
		var ring: Array = []
		for j in R:
			var a := TAU * j / R
			var p := Vector3(sin(a) * hw.y, cos(a) * hw.x, u - 0.5)
			var n := Vector3(sin(a) / maxf(hw.y, 0.001), cos(a) / maxf(hw.x, 0.001), 0.0).normalized()
			ring.append([p, n, (cos(a) + 1.0) * 0.5, u])
		rings.append(ring)
	# нос
	var nose := Vector3(0, 0, -0.5)
	for j in R:
		var a: Array = rings[0][j]
		var b: Array = rings[0][(j + 1) % R]
		_fv(st, nose, Vector3(0, 0, -1), 0.5, 0.0, 0.0)
		_fv(st, b[0], b[1], b[2], b[3], 0.0)
		_fv(st, a[0], a[1], a[2], a[3], 0.0)
	for i in range(1, NR):
		for j in R:
			var a: Array = rings[i - 1][j]
			var b: Array = rings[i - 1][(j + 1) % R]
			var c: Array = rings[i][j]
			var d: Array = rings[i][(j + 1) % R]
			_fv(st, a[0], a[1], a[2], a[3], 0.0)
			_fv(st, b[0], b[1], b[2], b[3], 0.0)
			_fv(st, c[0], c[1], c[2], c[3], 0.0)
			_fv(st, b[0], b[1], b[2], b[3], 0.0)
			_fv(st, d[0], d[1], d[2], d[3], 0.0)
			_fv(st, c[0], c[1], c[2], c[3], 0.0)
	var tip := Vector3(0, 0, pu - 0.5 + 0.02)
	for j in R:
		var a: Array = rings[NR - 1][j]
		var b: Array = rings[NR - 1][(j + 1) % R]
		_fv(st, a[0], a[1], a[2], a[3], 0.0)
		_fv(st, b[0], b[1], b[2], b[3], 0.0)
		_fv(st, tip, Vector3(0, 0, 1), 0.5, pu, 0.0)
	# хвост
	var hp := _prof_at(prof, pu).x
	var tail: Array = cfg["tail"]
	var th: float = tail[1]
	var z0 := pu - 0.5 - 0.01
	var pts: Array[Vector2] = [Vector2(z0, hp)]
	match tail[0]:
		&"fork":
			pts.append_array([Vector2(0.5, th), Vector2(0.37, th * 0.25), Vector2(0.33, 0.0), Vector2(0.37, -th * 0.25), Vector2(0.5, -th)])
		&"lunate":
			pts.append_array([Vector2(0.5, th), Vector2(0.42, th * 0.45), Vector2(0.38, 0.0), Vector2(0.42, -th * 0.45), Vector2(0.5, -th)])
		&"round":
			pts.append_array([Vector2(0.42, th * 0.95), Vector2(0.48, th * 0.6), Vector2(0.5, 0.0), Vector2(0.48, -th * 0.6), Vector2(0.42, -th * 0.95)])
		_:
			pts.append_array([Vector2(0.48, th), Vector2(0.5, th * 0.5), Vector2(0.5, 0.0), Vector2(0.5, -th * 0.5), Vector2(0.48, -th)])
	pts.append(Vector2(z0, -hp))
	var root := Vector2(z0, 0.0)
	for i in range(1, pts.size()):
		_fin_tri(st, root, pts[i - 1], pts[i])
	# спинные/анальные плавники
	for f: Array in cfg["fins"]:
		var u0: float = f[0]
		var u1: float = f[1]
		var hh: float = f[2]
		var side: float = f[3]
		var kind: int = f[4]
		const K := 6
		var prev_b := Vector2.ZERO
		var prev_t := Vector2.ZERO
		for k in K + 1:
			var s := float(k) / K
			var u := lerpf(u0, u1, s)
			var h := _prof_at(prof, u).x * 0.92
			var amp := 0.0
			if kind == 1:
				amp = 1.0 - s * 0.85
			else:
				amp = (s / 0.18) if s < 0.18 else (1.0 - 0.45 * (s - 0.18) / 0.82)
			if k == K:
				amp *= 0.25
			var bp := Vector2(u - 0.5, side * h)
			var tp := Vector2(u - 0.5 + hh * 0.35, side * (h + hh * amp))
			if k > 0:
				_fin_tri(st, prev_b, prev_t, tp)
				_fin_tri(st, prev_b, tp, bp)
			prev_b = bp
			prev_t = tp
	# грудные плавники
	var pec: float = cfg.get("pec", 0.0)
	if pec > 0.0:
		var hw := _prof_at(prof, 0.26)
		for sx: float in [-1.0, 1.0]:
			var a := Vector3(sx * hw.y * 0.95, -hw.x * 0.15, 0.26 - 0.5)
			var b := a + Vector3(sx * pec * 0.7, -pec * 0.25, pec * 1.1)
			var c := a + Vector3(sx * pec * 0.3, -pec * 0.6, pec * 0.6)
			for p: Vector3 in [a, b, c]:
				st.set_color(Color(0.4, 0.0, 0.0, 1.0))
				st.set_uv(Vector2(0.26, 0.0))
				st.set_normal(Vector3(0, 1, 0))
				st.add_vertex(p)
	# глаза
	var ue := 0.1
	var he := _prof_at(prof, ue)
	var er := clampf(he.x * 0.22, 0.016, 0.03)
	for sx: float in [-1.0, 1.0]:
		var c := Vector3(sx * he.y * 0.85, he.x * 0.3, ue - 0.5)
		_eye(st, c, er, sx)
	return st.commit()

static func _fv(st: SurfaceTool, p: Vector3, n: Vector3, dors: float, u: float, fin: float) -> void:
	st.set_color(Color(dors, 0.0, 0.0, fin))
	st.set_uv(Vector2(u, 0.0))
	st.set_normal(n)
	st.add_vertex(p)

## Треугольник плавника в плоскости X=0 (точки — (z, y)).
static func _fin_tri(st: SurfaceTool, a: Vector2, b: Vector2, c: Vector2) -> void:
	for p: Vector2 in [a, b, c]:
		st.set_color(Color(1.0 if p.y > 0.0 else 0.0, 0.0, 0.0, 1.0))
		st.set_uv(Vector2(p.x + 0.5, 0.0))
		st.set_normal(Vector3(1, 0, 0))
		st.add_vertex(Vector3(0.0, p.y, p.x))

static func _eye(st: SurfaceTool, c: Vector3, r: float, sx: float) -> void:
	const N := 6
	var pts: Array[Vector3] = []
	for i in N:
		var a := TAU * i / N
		pts.append(c + Vector3(0.0, cos(a) * r, sin(a) * r))
	var front := c + Vector3(sx * r * 0.45, 0, 0)
	for i in N:
		for p: Vector3 in [front, pts[i], pts[(i + 1) % N]]:
			st.set_color(Color(0.6, 1.0, 0.0, 0.0))
			st.set_uv(Vector2(0.1, 0.0))
			st.set_normal(Vector3(sx, 0, 0))
			st.add_vertex(p)

# ============================ общие помощники ============================

static func _v(st: SurfaceTool, p: Vector3, n: Vector3, c: Color, uv: Vector2) -> void:
	st.set_color(c)
	st.set_uv(uv)
	st.set_normal(n)
	st.add_vertex(p)

## Трубка a→b, цвет ca→cb, UV.y = ha→hb (высота для качания), UV.x = ux.
static func tube(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, seg: int,
		ca: Color, cb: Color, ha: float, hb: float, ux: float = 0.0, cap: bool = false) -> void:
	var ax := (b - a).normalized()
	var up := Vector3.UP if absf(ax.y) < 0.95 else Vector3.RIGHT
	var x := ax.cross(up).normalized()
	var y := x.cross(ax).normalized()
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var n0 := x * cos(a0) + y * sin(a0)
		var n1 := x * cos(a1) + y * sin(a1)
		var p0 := a + n0 * ra
		var p1 := a + n1 * ra
		var q0 := b + n0 * rb
		var q1 := b + n1 * rb
		_v(st, p0, n0, ca, Vector2(ux, ha))
		_v(st, p1, n1, ca, Vector2(ux, ha))
		_v(st, q0, n0, cb, Vector2(ux, hb))
		_v(st, p1, n1, ca, Vector2(ux, ha))
		_v(st, q1, n1, cb, Vector2(ux, hb))
		_v(st, q0, n0, cb, Vector2(ux, hb))
		if cap:
			_v(st, q0, ax, cb, Vector2(ux, hb))
			_v(st, q1, ax, cb, Vector2(ux, hb))
			_v(st, b, ax, cb, Vector2(ux, hb))

static func ellipsoid(st: SurfaceTool, c: Vector3, r: Vector3, seg: int, col: Color, uv: Vector2,
		col_bottom: Variant = null) -> void:
	var rows := maxi(seg / 2, 3)
	for i in rows:
		var t0 := PI * i / rows
		var t1 := PI * (i + 1) / rows
		for j in seg:
			var p0 := TAU * j / seg
			var p1 := TAU * (j + 1) / seg
			var q: Array[Vector3] = [
				Vector3(sin(t0) * cos(p0), cos(t0), sin(t0) * sin(p0)),
				Vector3(sin(t0) * cos(p1), cos(t0), sin(t0) * sin(p1)),
				Vector3(sin(t1) * cos(p0), cos(t1), sin(t1) * sin(p0)),
				Vector3(sin(t1) * cos(p1), cos(t1), sin(t1) * sin(p1))]
			for k: int in [0, 1, 2, 1, 3, 2]:
				var d := q[k]
				var cc := col
				if col_bottom != null and d.y < -0.2:
					cc = col_bottom
				_v(st, c + d * r, (d / r).normalized(), cc, uv)

static func _commit(st: SurfaceTool) -> ArrayMesh:
	return st.commit()

static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

# ============================ донные ходоки ============================

## Краб ~0.25 м в размахе, бежит вдоль X.
static func crab() -> ArrayMesh:
	return cached("crab", func() -> ArrayMesh:
		var st := _begin()
		var shell := Color(0.85, 0.42, 0.2, 0.0)
		var belly := Color(0.95, 0.78, 0.6, 0.0)
		ellipsoid(st, Vector3(0, 0.06, 0), Vector3(0.075, 0.032, 0.058), 10, shell, Vector2.ZERO, belly)
		# глаза на стебельках
		for sx: float in [-1.0, 1.0]:
			tube(st, Vector3(sx * 0.02, 0.08, -0.045), Vector3(sx * 0.026, 0.11, -0.05), 0.005, 0.004, 4, shell, shell, 0, 0)
			ellipsoid(st, Vector3(sx * 0.026, 0.113, -0.05), Vector3(0.008, 0.008, 0.008), 6, Color(0.05, 0.05, 0.05, 0.0), Vector2.ZERO)
		# ноги: 4 пары
		for k in 4:
			var z := -0.025 + k * 0.022
			for sx: float in [-1.0, 1.0]:
				var a := Vector3(sx * 0.06, 0.055, z)
				var m := Vector3(sx * 0.12, 0.08, z + 0.01 * (k - 1.5))
				var e := Vector3(sx * 0.16, 0.0, z + 0.02 * (k - 1.5))
				var ph := float(k * 2 + (0 if sx < 0 else 1)) / 8.0
				var lc := Color(0.82, 0.4, 0.2, 1.0)
				tube(st, a, m, 0.009, 0.007, 4, lc, lc, 0, 0, ph)
				tube(st, m, e, 0.007, 0.003, 4, lc, lc, 0, 0, ph)
		# клешни
		for sx: float in [-1.0, 1.0]:
			var a := Vector3(sx * 0.05, 0.06, -0.05)
			var m := Vector3(sx * 0.09, 0.07, -0.085)
			var cc := Color(0.9, 0.45, 0.22, 0.4)
			tube(st, a, m, 0.011, 0.01, 5, cc, cc, 0, 0, 0.3)
			ellipsoid(st, m + Vector3(sx * 0.01, 0.0, -0.025), Vector3(0.018, 0.016, 0.03), 7, Color(0.92, 0.5, 0.25, 0.4), Vector2(0.3, 0), Color(0.98, 0.9, 0.8, 0.4))
		return _commit(st))

## Лангуст ~0.45 м с усами, ползёт вдоль Z.
static func lobster() -> ArrayMesh:
	return cached("lobster", func() -> ArrayMesh:
		var st := _begin()
		var body := Color(0.62, 0.32, 0.18, 0.0)
		var spot := Color(0.95, 0.85, 0.6, 0.0)
		var under := Color(0.85, 0.6, 0.4, 0.0)
		ellipsoid(st, Vector3(0, 0.06, -0.07), Vector3(0.045, 0.04, 0.09), 10, body, Vector2.ZERO, under)
		for k in 5:
			var z := 0.03 + k * 0.035
			var r := 0.042 - k * 0.005
			ellipsoid(st, Vector3(0, 0.055 - k * 0.004, z), Vector3(r, r * 0.75, 0.024), 8, spot if k % 2 == 0 else body, Vector2.ZERO, under)
		# хвостовой веер
		for sx: float in [-1.0, 0.0, 1.0]:
			tube(st, Vector3(sx * 0.008, 0.04, 0.2), Vector3(sx * 0.03, 0.035, 0.25), 0.012, 0.004, 4, body, spot, 0, 0)
		# усы — длинные, качаются
		for sx: float in [-1.0, 1.0]:
			var a := Vector3(sx * 0.02, 0.08, -0.15)
			var b := Vector3(sx * 0.12, 0.16, -0.38)
			var c := Vector3(sx * 0.2, 0.12, -0.55)
			tube(st, a, b, 0.012, 0.006, 5, body, spot, 0.0, 0.5)
			tube(st, b, c, 0.006, 0.002, 4, spot, body, 0.5, 1.0)
			tube(st, Vector3(sx * 0.01, 0.07, -0.15), Vector3(sx * 0.04, 0.09, -0.22), 0.004, 0.002, 3, spot, spot, 0.0, 0.3)
		# ноги
		for k in 5:
			var z := -0.11 + k * 0.03
			for sx: float in [-1.0, 1.0]:
				var a := Vector3(sx * 0.035, 0.04, z)
				var m := Vector3(sx * 0.08, 0.055, z + 0.01)
				var e := Vector3(sx * 0.1, 0.0, z + 0.02)
				var ph := float(k * 2 + (0 if sx < 0 else 1)) / 10.0
				var lc := Color(0.75, 0.45, 0.28, 1.0)
				tube(st, a, m, 0.006, 0.005, 4, lc, lc, 0, 0, ph)
				tube(st, m, e, 0.005, 0.002, 4, lc, lc, 0, 0, ph)
		return _commit(st))

# ============================ декор (coral.gdshader) ============================

## Густой пучок морской травы (черепашья трава): 16 лент до ~0.6 м.
static func seagrass() -> ArrayMesh:
	return cached("seagrass", func() -> ArrayMesh:
		var st := _begin()
		var rng := RandomNumberGenerator.new()
		rng.seed = 77
		for b in 16:
			var a := rng.randf() * TAU
			var r := rng.randf() * 0.18
			var base := Vector3(cos(a) * r, 0, sin(a) * r)
			var h := rng.randf_range(0.3, 0.65)
			var w := rng.randf_range(0.012, 0.02)
			var lean := Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12))
			var side := Vector3(cos(a + 1.3), 0, sin(a + 1.3)) * w
			var c0 := Color(0.25, 0.42, 0.16)
			var c1 := Color(0.45, 0.62, 0.26).lerp(Color(0.6, 0.6, 0.3), rng.randf() * 0.5)
			const S := 4
			for s in S:
				var t0 := float(s) / S
				var t1 := float(s + 1) / S
				var p0 := base + Vector3(0, h * t0, 0) + lean * t0 * t0
				var p1 := base + Vector3(0, h * t1, 0) + lean * t1 * t1
				var n := side.cross(Vector3.UP).normalized()
				var ca := c0.lerp(c1, t0)
				var cb := c0.lerp(c1, t1)
				var w1 := 1.0 - t1 * 0.4
				var w0 := 1.0 - t0 * 0.4
				_v(st, p0 - side * w0, n, ca, Vector2(0, t0))
				_v(st, p0 + side * w0, n, ca, Vector2(0, t0))
				_v(st, p1 + side * w1, n, cb, Vector2(0, t1))
				_v(st, p0 - side * w0, n, ca, Vector2(0, t0))
				_v(st, p1 + side * w1, n, cb, Vector2(0, t1))
				_v(st, p1 - side * w1, n, cb, Vector2(0, t1))
		return _commit(st))

## Мягкий коралл: ствол и пушистые ветви (~0.5 м).
static func soft_coral() -> ArrayMesh:
	return cached("soft_coral", func() -> ArrayMesh:
		var st := _begin()
		var rng := RandomNumberGenerator.new()
		rng.seed = 31
		var trunk := Color(0.92, 0.85, 0.82)
		tube(st, Vector3.ZERO, Vector3(0, 0.18, 0), 0.07, 0.05, 7, trunk, trunk, 0.0, 0.35)
		for i in 7:
			var a := TAU * i / 7.0 + rng.randf() * 0.4
			var m := Vector3(cos(a) * 0.12, 0.3 + rng.randf() * 0.1, sin(a) * 0.12)
			tube(st, Vector3(0, 0.15, 0), m, 0.035, 0.025, 5, trunk, trunk, 0.3, 0.6)
			for k in 3:
				var tip := m + Vector3(rng.randf_range(-0.08, 0.08), rng.randf_range(0.06, 0.16), rng.randf_range(-0.08, 0.08))
				ellipsoid(st, tip, Vector3(0.045, 0.04, 0.045), 6, Color(1, 1, 1), Vector2(0, 0.9))
		return _commit(st))

## Морская плеть (горгонария): 5 тонких изогнутых прутьев до 0.9 м.
static func sea_whip() -> ArrayMesh:
	return cached("sea_whip", func() -> ArrayMesh:
		var st := _begin()
		var rng := RandomNumberGenerator.new()
		rng.seed = 12
		for i in 5:
			var a := rng.randf() * TAU
			var p := Vector3(cos(a), 0, sin(a)) * 0.03
			var h := rng.randf_range(0.5, 0.95)
			var bend := Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
			const S := 4
			for s in S:
				var t0 := float(s) / S
				var t1 := float(s + 1) / S
				tube(st, p + Vector3(0, h * t0, 0) + bend * t0 * t0, p + Vector3(0, h * t1, 0) + bend * t1 * t1,
					0.012 * (1.0 - t0 * 0.6), 0.012 * (1.0 - t1 * 0.6), 4, Color(1, 1, 1), Color(1, 1, 1), t0, t1)
		return _commit(st))

## Трубчатые губки: 4 трубы, внутри темнее.
static func tube_sponge() -> ArrayMesh:
	return cached("tube_sponge", func() -> ArrayMesh:
		var st := _begin()
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		for i in 4:
			var a := TAU * i / 4.0 + rng.randf() * 0.5
			var b := Vector3(cos(a), 0, sin(a)) * 0.07
			var h := rng.randf_range(0.25, 0.55)
			var top := b + Vector3(cos(a) * 0.05, h, sin(a) * 0.05)
			var r := rng.randf_range(0.045, 0.065)
			tube(st, b, top, r * 0.8, r, 8, Color(0.85, 0.85, 0.85), Color(1, 1, 1), 0.0, 1.0)
			tube(st, top, top - Vector3(0, h * 0.6, 0), r * 0.85, r * 0.7, 8, Color(0.35, 0.3, 0.35), Color(0.2, 0.18, 0.2), 1.0, 0.5)
		return _commit(st))

## Бочкообразная губка (~0.6 м).
static func barrel_sponge() -> ArrayMesh:
	return cached("barrel_sponge", func() -> ArrayMesh:
		var st := _begin()
		var c := Color(0.85, 0.85, 0.85)
		tube(st, Vector3.ZERO, Vector3(0, 0.25, 0), 0.22, 0.3, 12, c, c, 0, 0)
		tube(st, Vector3(0, 0.25, 0), Vector3(0, 0.55, 0), 0.3, 0.34, 12, c, Color(1, 1, 1), 0, 0)
		tube(st, Vector3(0, 0.55, 0), Vector3(0, 0.2, 0), 0.3, 0.2, 12, Color(0.3, 0.25, 0.25), Color(0.15, 0.12, 0.12), 0, 0)
		# рёбра
		for i in 10:
			var a := TAU * i / 10.0
			var d := Vector3(cos(a), 0, sin(a))
			tube(st, d * 0.23, d * 0.33 + Vector3(0, 0.54, 0), 0.025, 0.02, 4, c, c, 0, 0)
		return _commit(st))

## Актиния: основание и ~40 щупалец (сильно качаются).
static func anemone() -> ArrayMesh:
	return cached("anemone", func() -> ArrayMesh:
		var st := _begin()
		var rng := RandomNumberGenerator.new()
		rng.seed = 9
		var col := Color(0.75, 0.3, 0.55)
		tube(st, Vector3.ZERO, Vector3(0, 0.08, 0), 0.12, 0.14, 10, col, col, 0, 0.1)
		for i in 44:
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf()) * 0.13
			var b := Vector3(cos(a) * r, 0.08, sin(a) * r)
			var out := Vector3(cos(a), 0, sin(a)) * (0.04 + r * 0.5)
			var tip := b + out + Vector3(0, rng.randf_range(0.1, 0.18), 0)
			tube(st, b, tip, 0.012, 0.007, 4, Color(0.75, 0.82, 0.55), Color(0.95, 0.95, 0.75), 0.2, 1.0, 0, true)
		return _commit(st))

## Гигантская тридакна: две створки, яркая мантия.
static func clam() -> ArrayMesh:
	return cached("clam", func() -> ArrayMesh:
		var st := _begin()
		var shell := Color(0.82, 0.8, 0.72)
		ellipsoid(st, Vector3(-0.07, 0.06, 0), Vector3(0.07, 0.07, 0.17), 10, shell, Vector2.ZERO)
		ellipsoid(st, Vector3(0.07, 0.06, 0), Vector3(0.07, 0.07, 0.17), 10, shell, Vector2.ZERO)
		ellipsoid(st, Vector3(0, 0.11, 0), Vector3(0.05, 0.03, 0.15), 10, Color(0.25, 0.4, 0.95), Vector2(0, 0.2))
		return _commit(st))

## Морская звезда (~0.25 м).
static func starfish() -> ArrayMesh:
	return cached("starfish", func() -> ArrayMesh:
		var st := _begin()
		var c := Color(1, 1, 1)
		for i in 5:
			var a := TAU * i / 5.0
			var d := Vector3(cos(a), 0, sin(a))
			tube(st, Vector3(0, 0.02, 0), d * 0.12 + Vector3(0, 0.012, 0), 0.028, 0.008, 5, c, c.darkened(0.15), 0, 0, 0, true)
		ellipsoid(st, Vector3(0, 0.02, 0), Vector3(0.035, 0.018, 0.035), 6, c, Vector2.ZERO)
		return _commit(st))

## Морской ёж: шар с иглами.
static func urchin() -> ArrayMesh:
	return cached("urchin", func() -> ArrayMesh:
		var st := _begin()
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		var c := Color(0.12, 0.08, 0.14)
		ellipsoid(st, Vector3(0, 0.04, 0), Vector3(0.05, 0.04, 0.05), 8, c, Vector2.ZERO)
		for i in 34:
			var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 1), rng.randf_range(-1, 1)).normalized()
			var b := Vector3(0, 0.04, 0) + d * 0.045
			tube(st, b, b + d * rng.randf_range(0.1, 0.17), 0.006, 0.001, 3, c, Color(0.3, 0.2, 0.35), 0, 0.3)
		return _commit(st))

## Голотурия (морской огурец), лежит вдоль Z.
static func cucumber() -> ArrayMesh:
	return cached("cucumber", func() -> ArrayMesh:
		var st := _begin()
		var c := Color(0.3, 0.2, 0.14)
		ellipsoid(st, Vector3(0, 0.035, 0), Vector3(0.045, 0.035, 0.2), 10, c, Vector2.ZERO, Color(0.55, 0.45, 0.35))
		var rng := RandomNumberGenerator.new()
		rng.seed = 4
		for i in 14:
			var z := rng.randf_range(-0.16, 0.16)
			var a := rng.randf_range(-1.2, 1.2)
			var p := Vector3(sin(a) * 0.042, 0.035 + cos(a) * 0.033, z)
			ellipsoid(st, p, Vector3(0.012, 0.012, 0.012), 4, Color(0.6, 0.45, 0.25), Vector2.ZERO)
		return _commit(st))

## Кустик зелёных водорослей-«монеток» (халимеда), ~0.3 м.
static func algae_bush() -> ArrayMesh:
	return cached("algae_bush", func() -> ArrayMesh:
		var st := _begin()
		var rng := RandomNumberGenerator.new()
		rng.seed = 21
		for b in 6:
			var a := rng.randf() * TAU
			var p := Vector3(cos(a), 0, sin(a)) * rng.randf() * 0.06
			var dir := Vector3(rng.randf_range(-0.4, 0.4), 1.0, rng.randf_range(-0.4, 0.4)).normalized()
			for k in 6:
				var h := float(k + 1) / 6.0
				var q := p + dir * 0.05 * (k + 1)
				var n := Vector3(rng.randf_range(-1, 1), 0.3, rng.randf_range(-1, 1)).normalized()
				var t := n.cross(Vector3.UP).normalized() * 0.025
				var u := n.cross(t).normalized() * 0.022
				var col := Color(0.35, 0.62, 0.25).lerp(Color(0.55, 0.75, 0.35), h)
				for i in 6:
					var a0 := TAU * i / 6
					var a1 := TAU * (i + 1) / 6
					_v(st, q, n, col, Vector2(0, h))
					_v(st, q + t * cos(a0) + u * sin(a0), n, col, Vector2(0, h))
					_v(st, q + t * cos(a1) + u * sin(a1), n, col, Vector2(0, h))
		return _commit(st))

## Саргассум/бурые водоросли: кустистые ленты до 0.8 м (на камнях).
static func brown_algae() -> ArrayMesh:
	return cached("brown_algae", func() -> ArrayMesh:
		var st := _begin()
		var rng := RandomNumberGenerator.new()
		rng.seed = 41
		for b in 7:
			var a := rng.randf() * TAU
			var base := Vector3(cos(a), 0, sin(a)) * rng.randf() * 0.08
			var h := rng.randf_range(0.4, 0.8)
			var lean := Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
			const S := 5
			for s in S:
				var t0 := float(s) / S
				var t1 := float(s + 1) / S
				var p0 := base + Vector3(0, h * t0, 0) + lean * t0 * t0
				var p1 := base + Vector3(0, h * t1, 0) + lean * t1 * t1
				tube(st, p0, p1, 0.006, 0.005, 3, Color(0.45, 0.36, 0.14), Color(0.5, 0.4, 0.15), t0, t1)
				# листочки
				for l in 2:
					var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.1, 0.6), rng.randf_range(-1, 1)).normalized()
					var side := d.cross(Vector3.UP).normalized() * 0.018
					var tip := p1 + d * 0.07
					var n := side.cross(d).normalized()
					var lc := Color(0.55, 0.45, 0.16).lerp(Color(0.62, 0.55, 0.2), rng.randf())
					_v(st, p1 - side, n, lc, Vector2(0, t1))
					_v(st, p1 + side, n, lc, Vector2(0, t1))
					_v(st, tip, n, lc, Vector2(0, minf(t1 + 0.1, 1.0)))
		return _commit(st))
