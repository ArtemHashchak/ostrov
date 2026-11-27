class_name DamageMask
extends RefCounted
## Маска повреждений существа в пространстве UV (v5.1, агент I) — стандартный приём «кровь в маске».
## На первое попадание у меша существа заводится картинка (512/1024 px, RGBA8):
##   R — кровь (мокрая), G — глубина раны (тёмная середина), B — вывернутая мякоть (рваный край), A — потемнение кожи вокруг (синяк).
## Попадание → луч по треугольникам меша в позе покоя (точка переводится в позу покоя через кость:
## global_rest · global_pose⁻¹) → треугольник и барицентрические → UV; туда рисуется рана.
## Подтёки ползут ПО КОЖЕ: шаг вдоль проекции силы тяжести на поверхность, следующая точка снова
## проецируется на ближайший треугольник (сетка ячеек), UV → капля в маске; 2–5 с, по чуть-чуть каждый кадр.
## Материал меша получает next_pass с шейдером blood_overlay.gdshader (цвет крови, потемнение, мокрость,
## рельеф из маски); туша — uniform spread/dry: кровь расползается и буреет. Текстура обновляется только
## при изменениях (не чаще ~12 раз в секунду). Работает и в gl_compatibility, и в Forward+.

const OVERLAY := preload("res://scripts/fauna/shaders/blood_overlay.gdshader")

static var _mesh_cache: Dictionary = {}   # id меша → данные (позиции покоя, UV, треугольники, сетка)

var mi: MeshInstance3D
var sk: Skeleton3D
var data: Dictionary
var size := 512
var img: Image
var tex: ImageTexture
var mat: ShaderMaterial
var dirty := false
var _upd_t := 0.0
var drip_dist := 0.0                 # сколько всего протекли подтёки (м мира) — для тестов
var seeps: Array[Dictionary] = []   # туша: кровь из раны медленно расползается (3D-пятно растёт)
var drips: Array[Dictionary] = []   # {p: Vector3 (поза покоя), g: Vector3, left: float, w: float, k: float}
var spread := 0.0
var wind := 1.0                     # знак нормали треугольника (порядок вершин меша) → наружу
var dry := 0.0

# ============================== создание ==============================

## Маска для меша существа (создаётся один раз; null — меш без UV/треугольников).
static func of(m: MeshInstance3D, s: Skeleton3D, big: bool) -> DamageMask:
	if m == null or m.mesh == null:
		return null
	if m.has_meta(&"damage_mask"):
		return m.get_meta(&"damage_mask")
	var d := _mesh_data(m, s)
	if d.is_empty():
		return null
	var dm := DamageMask.new()
	dm.mi = m
	dm.sk = s
	dm.data = d
	dm.size = 1024 if big else 512
	dm.img = Image.create(dm.size, dm.size, false, Image.FORMAT_RGBA8)
	dm.img.fill(Color(0, 0, 0, 0))
	dm.tex = ImageTexture.create_from_image(dm.img)
	dm.mat = ShaderMaterial.new()
	dm.mat.shader = OVERLAY
	dm.mat.set_shader_parameter(&"mask", dm.tex)
	dm.mat.set_shader_parameter(&"texel", 1.0 / dm.size)
	dm.mat.set_shader_parameter(&"push", 0.0015 / maxf(dm.world_scale(), 1e-4))
	dm.mat.render_priority = 1
	# своя копия материалов поверхностей + next_pass с кровью (у других особей того же вида — без крови)
	for si in m.mesh.get_surface_count():
		var base := m.get_active_material(si)
		var dup: Material = base.duplicate() if base else StandardMaterial3D.new()
		var tail: Material = dup
		while tail.next_pass != null:
			tail.next_pass = tail.next_pass.duplicate()
			tail = tail.next_pass
		tail.next_pass = dm.mat
		m.set_surface_override_material(si, dup)
	m.set_meta(&"damage_mask", dm)
	return dm

## Данные меша в позе покоя (кэш по мешу): позиции (пространство скелета или меша), UV, треугольники,
## нормали, главная кость треугольника, сетка ячеек → треугольники.
static func _mesh_data(m: MeshInstance3D, s: Skeleton3D) -> Dictionary:
	var key := str(m.mesh.get_rid().get_id())
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var pos := PackedVector3Array()
	var uv := PackedVector2Array()
	var tris := PackedInt32Array()
	var tbone := PackedInt32Array()
	var skin := m.skin
	for si in m.mesh.get_surface_count():
		var arr := m.mesh.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var t: Variant = arr[Mesh.ARRAY_TEX_UV]
		if v.is_empty() or not (t is PackedVector2Array):
			continue
		var base := pos.size()
		var bo: Variant = arr[Mesh.ARRAY_BONES]
		var we: Variant = arr[Mesh.ARRAY_WEIGHTS]
		var skinned := skin != null and s != null and bo is PackedInt32Array and we is PackedFloat32Array
		var bones: PackedInt32Array = bo if skinned else PackedInt32Array()
		var wts: PackedFloat32Array = we if skinned else PackedFloat32Array()
		var per := bones.size() / v.size() if skinned else 0
		var bind_xf: Array[Transform3D] = []
		var bind_bone := PackedInt32Array()
		if skinned:
			for bi in skin.get_bind_count():
				var bn := skin.get_bind_bone(bi)
				if bn < 0:
					bn = s.find_bone(skin.get_bind_name(bi))
				bind_bone.append(bn)
				bind_xf.append(s.get_bone_global_rest(maxi(bn, 0)) * skin.get_bind_pose(bi))
		var vbone := PackedInt32Array()
		vbone.resize(v.size())
		for i in v.size():
			if skinned:
				var p := Vector3.ZERO
				var bw := -1.0
				var bb := -1
				for k in per:
					var w := wts[i * per + k]
					if w <= 0.0:
						continue
					var bix := bones[i * per + k]
					p += (bind_xf[bix] * v[i]) * w
					if w > bw:
						bw = w
						bb = bind_bone[bix]
				pos.append(p)
				vbone[i] = bb
			else:
				pos.append(v[i])
				vbone[i] = -1
		uv.append_array(t as PackedVector2Array)
		var ntri_before := tris.size() / 3
		var ix: Variant = arr[Mesh.ARRAY_INDEX]
		if ix is PackedInt32Array and (ix as PackedInt32Array).size() > 0:
			for i in (ix as PackedInt32Array).size():
				tris.append(base + (ix as PackedInt32Array)[i])
		else:
			for i in v.size():
				tris.append(base + i)
		# главная кость треугольника — по первой вершине
		for ti in range(ntri_before, tris.size() / 3):
			tbone.append(vbone[tris[ti * 3] - base] if tris[ti * 3] - base < vbone.size() else -1)
	if tris.is_empty():
		_mesh_cache[key] = {}
		return {}
	var bb := AABB(pos[0], Vector3.ZERO)
	for pp in pos:
		bb = bb.expand(pp)
	var cs := clampf(bb.get_longest_axis_size() / 70.0, 0.005, 1.0)
	var grid := {}
	var nt := tris.size() / 3
	for ti in nt:
		var a := pos[tris[ti * 3]]
		var b := pos[tris[ti * 3 + 1]]
		var c := pos[tris[ti * 3 + 2]]
		var lo := Vector3i((a.min(b).min(c) / cs).floor())
		var hi := Vector3i((a.max(b).max(c) / cs).floor())
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				for z in range(lo.z, hi.z + 1):
					var cell := Vector3i(x, y, z)
					if not grid.has(cell):
						grid[cell] = PackedInt32Array()
					var arr2: PackedInt32Array = grid[cell]
					arr2.append(ti)
					grid[cell] = arr2
	var d := {"pos": pos, "uv": uv, "tris": tris, "tbone": tbone, "grid": grid, "cell": cs, "skinned": skin != null and s != null}
	_mesh_cache[key] = d
	return d

# ============================== пространства ==============================

## Мир → поза покоя меша (через кость bone для скелетных; иначе — пространство меша).
func to_rest(p: Vector3, bone: int) -> Vector3:
	if data.skinned and sk:
		var ps := sk.global_transform.affine_inverse() * p
		if bone < 0:
			return ps
		return sk.get_bone_global_rest(bone) * (sk.get_bone_global_pose(bone).affine_inverse() * ps)
	return mi.global_transform.affine_inverse() * p

func dir_to_rest(d: Vector3, bone: int) -> Vector3:
	if data.skinned and sk:
		var ds := sk.global_transform.basis.inverse() * d
		if bone < 0:
			return ds.normalized()
		return (sk.get_bone_global_rest(bone).basis * (sk.get_bone_global_pose(bone).basis.inverse() * ds)).normalized()
	return (mi.global_transform.basis.inverse() * d).normalized()

## Масштаб «мир → поза покоя» (м мира на единицу покоя).
func world_scale() -> float:
	return (sk.global_transform.basis.get_scale().x if data.skinned and sk else mi.global_transform.basis.get_scale().x)

# ============================== поиск по треугольникам ==============================

## Луч в позе покоя → {t, tri, bary} или {}.
func raycast(o: Vector3, dir: Vector3, max_d: float) -> Dictionary:
	var pos: PackedVector3Array = data.pos
	var tris: PackedInt32Array = data.tris
	var grid: Dictionary = data.grid
	var seen := {}
	var best := {}
	var bt := INF
	var cell_s: float = data.cell
	var step := cell_s * 0.5
	var t := 0.0
	while t <= max_d:
		var c := Vector3i(((o + dir * t) / cell_s).floor())
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					var cell := c + Vector3i(dx, dy, dz)
					if seen.has(cell) or not grid.has(cell):
						continue
					seen[cell] = true
					for ti: int in grid[cell]:
						var a := pos[tris[ti * 3]]
						var b := pos[tris[ti * 3 + 1]]
						var cc := pos[tris[ti * 3 + 2]]
						var hit: Variant = Geometry3D.ray_intersects_triangle(o, dir, a, b, cc)
						if hit != null:
							var tt := ((hit as Vector3) - o).dot(dir)
							if tt >= 0.0 and tt < bt:
								bt = tt
								best = {"t": tt, "tri": ti, "p": hit, "bary": _bary(hit as Vector3, a, b, cc)}
		if not best.is_empty() and bt < t - cell_s:
			break
		t += step
	return best

## Ближайшая точка поверхности к q (поза покоя) → {p, tri, bary, n} или {}.
func closest(q: Vector3) -> Dictionary:
	var cs: float = data.cell
	var c := Vector3i((q / cs).floor())
	var best := _closest_in(q, [c])
	# точка у края ячейки — ближайший треугольник может быть в соседней
	var lo := q - Vector3(c) * cs
	var edge := minf(minf(minf(lo.x, cs - lo.x), minf(lo.y, cs - lo.y)), minf(lo.z, cs - lo.z))
	if best.is_empty() or float(best.d) > edge:
		var cells: Array = []
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					if dx != 0 or dy != 0 or dz != 0:
						cells.append(c + Vector3i(dx, dy, dz))
		var b2 := _closest_in(q, cells)
		if not b2.is_empty() and (best.is_empty() or float(b2.d) < float(best.d)):
			best = b2
	return best

func _closest_in(q: Vector3, cells: Array) -> Dictionary:
	var pos: PackedVector3Array = data.pos
	var tris: PackedInt32Array = data.tris
	var grid: Dictionary = data.grid
	var best := {}
	var bd := INF
	for cell: Vector3i in cells:
		if not grid.has(cell):
			continue
		for ti: int in grid[cell]:
			var a := pos[tris[ti * 3]]
			var b := pos[tris[ti * 3 + 1]]
			var cc := pos[tris[ti * 3 + 2]]
			var p := _closest_on_tri(q, a, b, cc)
			var d := p.distance_squared_to(q)
			if d < bd:
				bd = d
				best = {"p": p, "tri": ti, "bary": _bary(p, a, b, cc), "n": (b - a).cross(cc - a).normalized() * wind, "d": sqrt(d)}
	return best

static func _bary(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var v0 := b - a
	var v1 := c - a
	var v2 := p - a
	var d00 := v0.dot(v0)
	var d01 := v0.dot(v1)
	var d11 := v1.dot(v1)
	var d20 := v2.dot(v0)
	var d21 := v2.dot(v1)
	var den := d00 * d11 - d01 * d01
	if absf(den) < 1e-12:
		return Vector3(1, 0, 0)
	var v := (d11 * d20 - d01 * d21) / den
	var w := (d00 * d21 - d01 * d20) / den
	return Vector3(1.0 - v - w, v, w)

static func _closest_on_tri(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-14:
		return a
	n = n.normalized()
	var q := p - n * (p - a).dot(n)
	var bc := _bary(q, a, b, c)
	if bc.x >= 0.0 and bc.y >= 0.0 and bc.z >= 0.0:
		return q
	var e1 := Geometry3D.get_closest_point_to_segment(p, a, b)
	var e2 := Geometry3D.get_closest_point_to_segment(p, b, c)
	var e3 := Geometry3D.get_closest_point_to_segment(p, c, a)
	var r := e1
	if e2.distance_squared_to(p) < r.distance_squared_to(p):
		r = e2
	if e3.distance_squared_to(p) < r.distance_squared_to(p):
		r = e3
	return r

func uv_of(tri: int, bary: Vector3) -> Vector2:
	var uv: PackedVector2Array = data.uv
	var tris: PackedInt32Array = data.tris
	return uv[tris[tri * 3]] * bary.x + uv[tris[tri * 3 + 1]] * bary.y + uv[tris[tri * 3 + 2]] * bary.z

## Пикселей маски на метр позы покоя в треугольнике.
func px_per_unit(tri: int) -> float:
	var pos: PackedVector3Array = data.pos
	var uv: PackedVector2Array = data.uv
	var tris: PackedInt32Array = data.tris
	var a := pos[tris[tri * 3]]
	var b := pos[tris[tri * 3 + 1]]
	var c := pos[tris[tri * 3 + 2]]
	var wa := (b - a).cross(c - a).length()
	var ua := uv[tris[tri * 3]]
	var ub := uv[tris[tri * 3 + 1]]
	var uc := uv[tris[tri * 3 + 2]]
	var ar := absf((ub - ua).x * (uc - ua).y - (uc - ua).x * (ub - ua).y)
	if wa < 1e-12:
		return 400.0
	return sqrt(ar / wa) * size

# ============================== рисование ==============================

## Треугольники, пересекающие шар (c, rad) в позе покоя (без повторов).
func tris_near(c: Vector3, rad: float) -> PackedInt32Array:
	var cs: float = data.cell
	var grid: Dictionary = data.grid
	var lo := Vector3i(((c - Vector3.ONE * rad) / cs).floor())
	var hi := Vector3i(((c + Vector3.ONE * rad) / cs).floor())
	var seen := {}
	var out := PackedInt32Array()
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				var cell := Vector3i(x, y, z)
				if not grid.has(cell):
					continue
				for ti: int in grid[cell]:
					if not seen.has(ti):
						seen[ti] = true
						out.append(ti)
	return out

func tri_normal(ti: int) -> Vector3:
	var pos: PackedVector3Array = data.pos
	var tris: PackedInt32Array = data.tris
	var a := pos[tris[ti * 3]]
	return (pos[tris[ti * 3 + 1]] - a).cross(pos[tris[ti * 3 + 2]] - a).normalized() * wind

## Растеризация куска поверхности в маску: все пиксели UV треугольников рядом с c (в радиусе rad, поза
## покоя, только лицевая сторона по нормали n) → [пиксель, точка 3D]. Рисуем в 3D — швы UV не рвут рану.
func raster(c: Vector3, rad: float, n: Vector3) -> Array:
	var pos: PackedVector3Array = data.pos
	var uv: PackedVector2Array = data.uv
	var tris: PackedInt32Array = data.tris
	var out: Array = []
	var r2 := rad * rad
	for ti in tris_near(c, rad):
		var tn := tri_normal(ti)
		if tn.dot(n) < 0.05:
			continue
		var a := pos[tris[ti * 3]]
		var b := pos[tris[ti * 3 + 1]]
		var cc := pos[tris[ti * 3 + 2]]
		var ua := uv[tris[ti * 3]] * size
		var ub := uv[tris[ti * 3 + 1]] * size
		var uc := uv[tris[ti * 3 + 2]] * size
		var den := (ub.y - uc.y) * (ua.x - uc.x) + (uc.x - ub.x) * (ua.y - uc.y)
		if absf(den) < 1e-6:
			continue
		# поле на 1,5 px за край треугольника — без тёмных щелей у краёв островов UV
		var lng := maxf(maxf(ua.distance_to(ub), ub.distance_to(uc)), uc.distance_to(ua))
		var eps := 1.5 / maxf(lng * 0.5, 1.0)
		var mn := ua.min(ub).min(uc).floor() - Vector2.ONE * 2.0
		var mx := ua.max(ub).max(uc).ceil() + Vector2.ONE * 2.0
		for py in range(maxi(int(mn.y), 0), mini(int(mx.y), size - 1) + 1):
			for px in range(maxi(int(mn.x), 0), mini(int(mx.x), size - 1) + 1):
				var q := Vector2(px + 0.5, py + 0.5)
				var l1 := ((ub.y - uc.y) * (q.x - uc.x) + (uc.x - ub.x) * (q.y - uc.y)) / den
				var l2 := ((uc.y - ua.y) * (q.x - uc.x) + (ua.x - uc.x) * (q.y - uc.y)) / den
				var l3 := 1.0 - l1 - l2
				if l1 < -eps or l2 < -eps or l3 < -eps:
					continue
				var p3 := a * l1 + b * l2 + cc * l3
				if p3.distance_squared_to(c) > r2:
					continue
				out.append([Vector2i(px, py), p3])
	return out

func _put(px: Vector2i, r: float, g: float, b: float, a: float) -> void:
	var cur := img.get_pixel(px.x, px.y)
	cur.r = maxf(cur.r, r)
	cur.g = maxf(cur.g, g)
	cur.b = maxf(cur.b, b)
	cur.a = maxf(cur.a, a)
	img.set_pixel(px.x, px.y, cur)

## Рана в точке p0 (поза покоя) с нормалью n. kind: hole / exit / gash / bruise; r — радиус (м мира);
## cut — направление разреза, g — сила тяжести (поза покоя). Рисуется в 3D вокруг точки:
## тёмная середина, рваная вывернутая мякоть, мокрое кольцо крови, натёк вниз, брызги, потемнение кожи.
func paint_wound(p0: Vector3, n: Vector3, kind: StringName, r_world: float, cut: Vector3, g: Vector3) -> void:
	var ws := maxf(world_scale(), 1e-4)
	var r := r_world / ws
	n = n.normalized()
	var q0 := closest(p0)
	if not q0.is_empty() and (q0.n as Vector3).dot(n) < 0.0:
		wind = -wind
	var gt := g - n * g.dot(n)
	gt = gt.normalized() if gt.length() > 0.1 else (cut - n * cut.dot(n)).normalized()
	var ax := cut - n * cut.dot(n)
	ax = ax.normalized() if ax.length() > 0.05 else gt.cross(n).normalized()
	var ay := n.cross(ax).normalized()
	var gx := gt.cross(n).normalized()
	var noise := FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = 1.0 / maxf(r * 0.45, 1e-4)
	var noise2 := FastNoiseLite.new()
	noise2.seed = randi()
	noise2.frequency = 1.0 / maxf(r * 1.6, 1e-4)
	var gash := kind == &"gash"
	var elong := 3.6 if gash else 1.0
	var core := 0.42 if kind == &"exit" else 0.34
	var wet := 1.9 if kind != &"exit" else 1.8
	var reach := r * ((elong * 0.9 if gash else 1.3) * (wet + 0.8)) + r
	for e: Array in raster(p0, reach, n):
		var px: Vector2i = e[0]
		var o: Vector3 = (e[1] as Vector3) - p0
		var nz := noise.get_noise_3dv(e[1])
		var nb := noise2.get_noise_3dv(e[1])
		var u := o.dot(ax) / r
		var v := o.dot(ay) / r
		var down := o.dot(gt) / r          # > 0 — ниже раны
		var side := o.dot(gx) / r
		# натёк: кровь собирается ниже раны (капля вытянута вниз), сверху край ближе
		var dy := down * (0.55 if down > 0.0 else 1.25)
		var db := sqrt(side * side + dy * dy) * (1.0 / (elong * 0.6 + 0.4) if gash else 1.0)
		if gash:
			db = sqrt(pow(u / (elong * 0.85), 2.0) + pow(maxf(v * 0.9, -v) if down > 0.0 else v, 2.0))
			db = minf(db, sqrt(side * side + dy * dy * 0.6) / 1.4)
		db += nb * 0.55
		var blood := clampf((wet - db) / (wet * 0.35), 0.0, 1.0)
		var hole := 0.0
		var flesh := 0.0
		var bruise := clampf((wet * 1.6 - db) / (wet * 0.8), 0.0, 1.0) * 0.7
		if kind == &"bruise":
			blood *= 0.25
			bruise = clampf((1.8 - sqrt(u * u + v * v) - nb * 0.4) / 0.9, 0.0, 1.0)
		elif gash:
			# щель: ширина по длине (сходится к концам), рваные стенки, внутри тёмное мясо
			var t := clampf(absf(u) / elong, 0.0, 1.2)
			var w := pow(maxf(1.0 - t * t, 0.0), 0.6) * (0.55 + nz * 0.15)
			var dv := absf(v + nz * 0.18)
			hole = clampf((w * 0.22 - dv) / maxf(w * 0.15, 0.02), 0.0, 1.0) * 0.9
			var tear := clampf(noise.get_noise_3dv((e[1] as Vector3) * 2.3) * 2.0 + 0.6, 0.0, 1.0)
			flesh = clampf((w * (0.9 + 0.5 * tear) - dv) / maxf(w * 0.35, 0.03), 0.0, 1.0)
			blood = maxf(blood, clampf((w * 2.6 - dv) / maxf(w, 0.05), 0.0, 1.0))
		else:
			var d := sqrt(u * u + v * v) + nz * 0.22
			hole = clampf((core - d) / 0.1, 0.0, 1.0)
			var rim := 0.36 + nz * 0.2
			var tear := clampf(noise.get_noise_3dv((e[1] as Vector3) * 2.7) * 2.2 + 0.55, 0.0, 1.0)
			flesh = clampf(1.0 - absf(d - core - rim * 0.45) / (rim * 0.55), 0.0, 1.0) * tear
			blood = maxf(blood, clampf((core + rim * 1.6 - d) / 0.25, 0.0, 1.0))
		_put(px, blood, hole, flesh, bruise)
	# брызги: капельки вокруг, больше снизу по ходу пули
	if kind != &"bruise":
		for i in int(8 + (6 if kind == &"exit" else 0)):
			var ang := randf() * TAU
			var dd := r * randf_range(1.6, 3.6 if kind == &"exit" else 2.8)
			var q := closest(p0 + (ax * cos(ang) + ay * sin(ang)) * dd)
			if not q.is_empty():
				paint_blob(q.p, r * randf_range(0.08, 0.22), n, randf_range(0.6, 1.0))
	dirty = true

## Капля/пятнышко крови радиуса rad (поза покоя) вокруг точки поверхности.
func paint_blob(c: Vector3, rad: float, n: Vector3, amt: float) -> void:
	for e: Array in raster(c, rad, n):
		var d := (e[1] as Vector3).distance_to(c) / rad
		_put(e[0], amt * clampf((1.0 - d) * 2.5, 0.0, 1.0), 0.0, 0.0, 0.0)
	dirty = true

## Отрезок подтёка a→b толщиной w (поза покоя): плотная середина, мягкий край.
func paint_segment(a: Vector3, b: Vector3, w: float, n: Vector3, amt: float) -> void:
	var mid := (a + b) * 0.5
	for e: Array in raster(mid, a.distance_to(b) * 0.5 + w, n):
		var cp := Geometry3D.get_closest_point_to_segment(e[1], a, b)
		var d := (e[1] as Vector3).distance_to(cp) / w
		if d < 1.0:
			_put(e[0], amt * clampf((1.0 - d) * 3.0, 0.0, 1.0), 0.0, 0.0, 0.0)
	dirty = true

## Подтёк от точки (поза покоя) вниз по коже: длина len_w м мира за time с, толщина w_world.
func add_drip(p_rest: Vector3, g_rest: Vector3, len_w: float, time: float, w_world: float, delay := 0.0) -> void:
	var ws := maxf(world_scale(), 1e-4)
	drips.append({"p": p_rest, "g": g_rest.normalized(), "left": len_w / ws, "len": len_w / ws,
		"v": len_w / ws / maxf(time, 0.3), "w": w_world / ws, "amt": 1.0, "delay": delay,
		"seed": randf() * 100.0, "s": 0.0})

## Туша: из точки p (поза покоя) кровь расползается до радиуса r1 (м мира) за time с.
func add_seep(p: Vector3, n: Vector3, r1_world: float, time: float) -> void:
	var ws := maxf(world_scale(), 1e-4)
	seeps.append({"p": p, "n": n, "r": 0.0, "r1": r1_world / ws, "v": r1_world / ws / maxf(time, 1.0), "acc": 0.0,
		"nz": randi()})

func _tick_seeps(dt: float) -> void:
	for i in range(seeps.size() - 1, -1, -1):
		var e: Dictionary = seeps[i]
		e.r = minf(float(e.r) + float(e.v) * dt, float(e.r1))
		e.acc = float(e.acc) + dt
		if float(e.acc) < 0.6 and float(e.r) < float(e.r1):
			continue
		e.acc = 0.0
		var noise := FastNoiseLite.new()
		noise.seed = int(e.nz)
		noise.frequency = 1.0 / maxf(float(e.r1) * 0.35, 1e-4)
		var c: Vector3 = e.p
		var rr := float(e.r)
		for px: Array in raster(c, rr * 1.4, e.n):
			var q: Vector3 = px[1]
			var d := q.distance_to(c) / maxf(rr, 1e-5) + noise.get_noise_3dv(q) * 0.45
			_put(px[0], clampf((1.0 - d) * 3.0, 0.0, 0.85), 0.0, 0.0, 0.0)
		dirty = true
		if float(e.r) >= float(e.r1):
			seeps.remove_at(i)

## Шаг: ползут подтёки, обновляется текстура (только при изменениях).
func tick(dt: float) -> void:
	if not seeps.is_empty():
		_tick_seeps(dt)
	if not drips.is_empty():
		var ws := maxf(world_scale(), 1e-4)
		var step := 0.006 / ws
		for i in range(drips.size() - 1, -1, -1):
			var d: Dictionary = drips[i]
			if float(d.delay) > 0.0:
				d.delay = float(d.delay) - dt
				continue
			# медленнее к концу (кровь густеет), но не останавливается раньше времени
			var frac := 1.0 - float(d.left) / float(d.len)
			var adv := minf(float(d.v) * dt * lerpf(1.4, 0.6, frac), float(d.left))
			var sub := maxi(1, int(ceil(adv / step)))
			for k in sub:
				var q := closest(d.p)
				if q.is_empty():
					d.left = 0.0
					break
				var n: Vector3 = q.n
				var g: Vector3 = d.g
				var t := g - n * g.dot(n)
				if t.length() < 0.12:
					d.left = 0.0      # под брюхом — капля срывается
					break
				t = t.normalized()
				# виляет по чешуе: боковой снос по шуму вдоль пути
				var lat := n.cross(t).normalized()
				d.s = float(d.s) + adv / sub
				var wig := sin(float(d.s) * ws * 55.0 + float(d.seed)) * 0.18 + sin(float(d.s) * ws * 23.0 + float(d.seed) * 2.0) * 0.14
				var dir := (t + lat * wig).normalized()
				var np: Vector3 = (q.p as Vector3) + dir * (adv / sub)
				var wcur := float(d.w) * lerpf(1.0, 0.6, frac) * (1.0 + 0.15 * sin(float(d.s) * ws * 90.0 + float(d.seed)))
				paint_segment(q.p, np, wcur, n, float(d.amt))
				d.amt = maxf(float(d.amt) * 0.997, 0.7)
				d.p = np
				d.left = float(d.left) - adv / sub
				drip_dist += adv / sub * ws
				frac = 1.0 - float(d.left) / float(d.len)
			if float(d.left) <= 0.0:
				# капля на конце подтёка
				var q2 := closest(d.p)
				if not q2.is_empty():
					paint_blob(q2.p, float(d.w) * 1.5, q2.n, 1.0)
				drips.remove_at(i)
	_upd_t -= dt
	if dirty and _upd_t <= 0.0:
		tex.update(img)
		dirty = false
		_upd_t = 0.08

## Туша: кровь расползается и буреет (в шейдере, без перерисовки маски).
func set_corpse(sp: float, dr: float) -> void:
	spread = sp
	dry = dr
	mat.set_shader_parameter(&"spread", sp)
	mat.set_shader_parameter(&"dry", dr)
