class_name TrailNet
extends RefCounted
## Звериные тропы в джунглях: узкие (≈0,5 м) и низкие (полог ≈1,1–1,2 м — идти
## пригнувшись), ведут от мест кормёжки в глубине острова к воде (берег моря или
## пресное озеро) и сливаются в сеть. Растения на тропе не растут (Flora спрашивает
## dist()), по краям — гуще. Строится по карте зон один раз, детерминированно.
## Прорубленные игроком проходы — отдельные записи cut (навсегда, через add_cut()).

const WIDTH := 0.5            # ширина тропы, м
const CLEAR := 0.9            # радиус, где растения не ставятся
const CANOPY := 1.2           # высота полога над тропой (коллизия «сверху»)
const STEP := 3.0
const HCELL := 16.0
const MIN_JUNGLE := 0.25      # тропы — только там, где джунгли

var trails: Array[PackedVector2Array] = []   # ломаные
var kinds: Array[StringName] = []            # &"animal" | &"cut"
var _hash: Dictionary = {}                   # Vector2i → PackedInt32Array (индекс сегмента = trail << 16 | seg)
var stats := {}

func build(zm: ZoneMap, arch: Archipelago, seed_value: int) -> void:
	var t0 := Time.get_ticks_msec()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 3571 + 9
	var noise := FastNoiseLite.new()
	noise.seed = seed_value + 77
	noise.frequency = 0.03
	for I in arch.islands:
		var c: Vector2 = I.center
		var R := float(I.radius) * 1.1
		# кандидаты — ячейки джунглей острова
		var cand: Array[Vector2] = []
		var x := c.x - R
		while x <= c.x + R:
			var z := c.y - R
			while z <= c.y + R:
				if zm.land_ok(x, z) and zm.jungle_density(x, z) > 0.45:
					cand.append(Vector2(x, z))
				z += ZoneMap.STEP * 2.0
			x += ZoneMap.STEP * 2.0
		if cand.size() < 6:
			continue
		var lakes: Array[Vector2] = []
		for L in arch.lakes:
			if int(L.island) == int(I.id):
				lakes.append(L.center)
		var n := clampi(cand.size() / 40, 2, 14)
		for k in n:
			var s: Vector2 = cand[rng.randi_range(0, cand.size() - 1)]
			var target_lake := not lakes.is_empty() and rng.randf() < 0.35
			_walk(zm, s, lakes[rng.randi_range(0, lakes.size() - 1)] if target_lake else Vector2.INF, noise, rng)
	stats = {"trails": trails.size(), "km": total_length() / 1000.0, "ms": Time.get_ticks_msec() - t0}

## Путь от места кормёжки к воде: вниз по «расстоянию до берега» (или к озеру),
## с меандрами; упирается в существующую тропу — сливается с ней.
func _walk(zm: ZoneMap, start: Vector2, lake: Vector2, noise: FastNoiseLite, rng: RandomNumberGenerator) -> void:
	var pts := PackedVector2Array([start])
	var p := start
	var heading := rng.randf() * TAU
	for it in 260:
		var want: Vector2
		if lake != Vector2.INF:
			want = (lake - p).normalized()
			if p.distance_to(lake) < 8.0:
				break
		else:
			var e := ZoneMap.STEP
			var g := Vector2(zm.dist_to_coast(p.x + e, p.y) - zm.dist_to_coast(p.x - e, p.y),
					zm.dist_to_coast(p.x, p.y + e) - zm.dist_to_coast(p.x, p.y - e))
			want = -g.normalized() if g.length() > 0.01 else Vector2.from_angle(heading)
		var mea := noise.get_noise_2d(p.x, p.y) * 1.3
		var dir := Vector2.from_angle(heading).lerp(want.rotated(mea), 0.35).normalized()
		heading = dir.angle()
		var q := p + dir * STEP
		if not zm.land_ok(q.x, q.y):
			break
		var zn := zm.zone_at(q.x, q.y)
		if zn == ZoneMap.Z_ROCKS:
			heading += rng.randf_range(-1.2, 1.2)
			continue
		pts.append(q)
		p = q
		if zn == ZoneMap.Z_BEACH or zn == ZoneMap.Z_DUNES or zn == ZoneMap.Z_FRESHWATER:
			break
		if pts.size() > 4 and dist(q.x, q.y) < 2.5:
			break   # влились в другую тропу
	if pts.size() >= 6:
		_add(pts, &"animal")

func _add(pts: PackedVector2Array, kind: StringName) -> int:
	var ti := trails.size()
	trails.append(pts)
	kinds.append(kind)
	for si in pts.size() - 1:
		var a := pts[si]
		var b := pts[si + 1]
		var mn := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(CLEAR, CLEAR)
		var mx := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(CLEAR, CLEAR)
		for cz in range(int(floor(mn.y / HCELL)), int(floor(mx.y / HCELL)) + 1):
			for cx in range(int(floor(mn.x / HCELL)), int(floor(mx.x / HCELL)) + 1):
				var key := Vector2i(cx, cz)
				var arr: PackedInt32Array = _hash.get(key, PackedInt32Array())
				arr.append((ti << 16) | si)
				_hash[key] = arr
	return ti

## Прорубленный проход (навсегда): ломаная по точкам игрока.
func add_cut(pts: PackedVector2Array) -> int:
	return _add(pts, &"cut")

## Расстояние до ближайшей тропы (м); далеко — INF.
func dist(x: float, z: float) -> float:
	var arr: PackedInt32Array = _hash.get(Vector2i(int(floor(x / HCELL)), int(floor(z / HCELL))), PackedInt32Array())
	var best := INF
	var p := Vector2(x, z)
	for code in arr:
		var t: PackedVector2Array = trails[int(code) >> 16]
		var si: int = int(code) & 0xFFFF
		best = minf(best, Archipelago._seg_dist(p, t[si], t[si + 1]))
	return best

## Направление тропы в точке (единичный вектор) или ZERO.
func direction(x: float, z: float) -> Vector2:
	var arr: PackedInt32Array = _hash.get(Vector2i(int(floor(x / HCELL)), int(floor(z / HCELL))), PackedInt32Array())
	var best := INF
	var d := Vector2.ZERO
	var p := Vector2(x, z)
	for code in arr:
		var t: PackedVector2Array = trails[int(code) >> 16]
		var si: int = int(code) & 0xFFFF
		var s := Archipelago._seg_dist(p, t[si], t[si + 1])
		if s < best:
			best = s
			d = (t[si + 1] - t[si]).normalized()
	return d

## Сегменты троп в радиусе r: [[a: Vector2, b: Vector2, kind]].
func segments_near(c: Vector2, r: float) -> Array:
	var out: Array = []
	var seen := {}
	for cz in range(int(floor((c.y - r) / HCELL)), int(floor((c.y + r) / HCELL)) + 1):
		for cx in range(int(floor((c.x - r) / HCELL)), int(floor((c.x + r) / HCELL)) + 1):
			for code in _hash.get(Vector2i(cx, cz), PackedInt32Array()):
				if seen.has(code):
					continue
				seen[code] = true
				var t: PackedVector2Array = trails[int(code) >> 16]
				var si: int = int(code) & 0xFFFF
				if Archipelago._seg_dist(c, t[si], t[si + 1]) < r:
					out.append([t[si], t[si + 1], kinds[int(code) >> 16]])
	return out

func total_length() -> float:
	var s := 0.0
	for t in trails:
		for i in t.size() - 1:
			s += t[i].distance_to(t[i + 1])
	return s
