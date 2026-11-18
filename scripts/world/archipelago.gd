class_name Archipelago
extends RefCounted
## Полный архипелаг (25 островов) и аналитическая функция высот H(x, z).
## Раскладка (всё детерминировано от seed):
##   центр — вулкан с кратером;
##   внутреннее кольцо (≈292–300 м): 4 родниковых острова (пресное озеро) напротив
##     домашних и 4 острова на диагоналях (2 скальных, 2 мангровых);
##   внешнее кольцо (≈525 м): 4 домашних (команды 0–3, через 90°) и 4 общих (на 45°);
##   между домашним и общим (≈560 м, ±24°): атолл с одной стороны, кладбище
##     кораблей с другой — у каждой команды одинаковый набор соседей.
## Проливы между соседями 40–110 м; в проливах — песчаные косы от берегов
## (открываются в отлив), рифы и скальный островок посередине (опоры мостов).
## Пространственная сетка ускоряет height() (каждая точка проверяет 1–3 острова).
## Все функции чтения потокобезопасны (рельеф строится в WorkerThreadPool).

const SEA_FLOOR := -15.0
const BEACH_H := 1.35          # высота пляжа у края травы
const BEACH_W := 0.11          # ширина пляжа (доля радиуса)
const CELL := 64.0

const D_OUT := 525.0           # кольцо домашних и общих
const D_MID := 560.0           # атоллы и кладбища кораблей
const D_IN_A := 292.0          # родниковые
const D_IN_B := 296.0          # скальные / мангровые
const D_SHARED := 505.0        # общие острова

const KIND_NAMES := {
	&"home": "Домашний остров", &"center": "Вулкан", &"shared": "Общий остров",
	&"spring": "Родниковый остров", &"swamp": "Мангровое болото", &"rocky": "Скалистый остров",
	&"atoll": "Атолл", &"wreck": "Кладбище кораблей",
}

var islands: Array[Dictionary] = []   # {id, kind, team, center: Vector2, radius, max_h, cliff_dir, lagoon_dir, name, beach_w}
var bars: Array[Dictionary] = []      # песчаные косы: {pts: PackedVector2Array, width, top, bmin, bmax}
var islets: Array[Dictionary] = []    # скальные островки: {center: Vector2, radius, top}
var lakes: Array[Dictionary] = []     # пресные озёра/родники: {center: Vector2, radius, level, island, kind}
var routes: Array[Dictionary] = []    # {a: id, b: id, gap}
var wreck_spots: Array[Dictionary] = []   # {pos: Vector2, yaw, sink, island}
var bounds := Rect2()

var _grid: Dictionary = {}            # Vector2i → {"i": PackedInt32Array, "b": PackedInt32Array, "l": PackedInt32Array}

var _n_coast := FastNoiseLite.new()
var _n_hills := FastNoiseLite.new()
var _n_ridge := FastNoiseLite.new()
var _n_detail := FastNoiseLite.new()
var _n_dune := FastNoiseLite.new()
var _n_reef := FastNoiseLite.new()
var _n_floor := FastNoiseLite.new()
var _n_moist := FastNoiseLite.new()
var _n_chan := FastNoiseLite.new()

func _init(seed_value: int = 2026) -> void:
	var i := 0
	for n: FastNoiseLite in [_n_coast, _n_hills, _n_ridge, _n_detail, _n_dune, _n_reef, _n_floor, _n_moist, _n_chan]:
		n.seed = seed_value + i * 7919
		i += 1
	_n_coast.frequency = 0.02
	_n_coast.fractal_octaves = 3
	_n_hills.frequency = 0.012
	_n_hills.fractal_octaves = 4
	_n_ridge.frequency = 0.02
	_n_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_n_ridge.fractal_octaves = 3
	_n_detail.frequency = 0.09
	_n_detail.fractal_octaves = 3
	_n_dune.frequency = 0.05
	_n_dune.fractal_octaves = 2
	_n_reef.frequency = 0.035
	_n_reef.fractal_octaves = 3
	_n_floor.frequency = 0.006
	_n_floor.fractal_octaves = 3
	_n_moist.frequency = 0.012
	_n_moist.fractal_octaves = 3
	_n_chan.frequency = 0.03
	_n_chan.fractal_octaves = 2
	_layout(seed_value)
	_build_grid()
	finalize_ponds()

# ---------------------------------------------------------------- раскладка

func _add_island(kind: StringName, team: int, ang_deg: float, dist: float, radius: float, max_h: float,
		cliff_dir: float = -1.0, lagoon_dir: float = -1.0, beach_w: float = BEACH_W) -> Dictionary:
	var a := deg_to_rad(ang_deg)
	var I := {
		"id": islands.size(), "kind": kind, "team": team, "center": Vector2(cos(a), sin(a)) * dist,
		"radius": radius, "max_h": max_h, "cliff_dir": cliff_dir, "lagoon_dir": lagoon_dir,
		"beach_w": beach_w, "name": String(KIND_NAMES.get(kind, "Остров")), "angle": a,
	}
	if kind == &"home":
		I.name = "Домашний остров — %s" % _team_name(team)
	islands.append(I)
	return I

static func _team_name(t: int) -> String:
	return ["Красные", "Синие", "Зелёные", "Жёлтые"][clampi(t, 0, 3)]

func _layout(seed_value: int) -> void:
	islands.clear()
	bars.clear()
	islets.clear()
	lakes.clear()
	routes.clear()
	wreck_spots.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 31 + 7
	# 0: вулкан
	var center := _add_island(&"center", -1, 0.0, 0.0, 145.0, 48.0)
	var homes: Array[Dictionary] = []
	var shared: Array[Dictionary] = []
	var springs: Array[Dictionary] = []
	var diag: Array[Dictionary] = []
	for t in 4:
		var ang := t * 90.0
		# утёс смотрит в открытое море (наружу), лагуна — сбоку
		# соседи домашнего: родник (внутрь), атолл (~+90°), кладбище (~−90°) —
		# утёс и лагуна смотрят в стороны между ними, чтобы не перекрывать проливы
		var home := _add_island(&"home", t, ang, D_OUT, 112.0, 17.0, deg_to_rad(ang - 28.0 + rng.randf_range(-12.0, 12.0)),
				deg_to_rad(ang + 48.0 + rng.randf_range(-10.0, 10.0)))
		homes.append(home)
	for t in 4:
		shared.append(_add_island(&"shared", -1, 45.0 + t * 90.0, D_SHARED, 60.0, 10.0, -1.0, -1.0, 0.14))
	for t in 4:
		springs.append(_add_island(&"spring", -1, t * 90.0 + rng.randf_range(-4.0, 4.0), D_IN_A, 54.0, 15.0,
				deg_to_rad(t * 90.0 + 180.0 + rng.randf_range(-30.0, 30.0))))
	for t in 4:
		var kind := &"rocky" if t % 2 == 0 else &"swamp"
		var mh := 23.0 if kind == &"rocky" else 1.4
		diag.append(_add_island(kind, -1, 45.0 + t * 90.0, D_IN_B, 56.0, mh, -2.0 if kind == &"rocky" else -1.0, -1.0,
				0.08 if kind == &"rocky" else 0.05))
	var atolls: Array[Dictionary] = []
	var wrecks: Array[Dictionary] = []
	for t in 4:
		atolls.append(_add_island(&"atoll", -1, t * 90.0 + 24.0, D_MID, 46.0, 2.1, -1.0, -1.0, 0.3))
		wrecks.append(_add_island(&"wreck", -1, t * 90.0 - 24.0, D_MID, 44.0, 5.5, -1.0, -1.0, 0.22))
	# маршруты (проливы с косами и островками): сначала подгоняем положения
	# не-домашних островов так, чтобы реальные проливы (с учётом изрезанности
	# берега) были 55–100 м, потом строим косы/островки
	var pairs: Array = []
	for t in 4:
		pairs.append_array([[center, springs[t]], [center, diag[t]], [springs[t], homes[t]], [diag[t], shared[t]],
				[homes[t], atolls[t]], [atolls[t], shared[t]], [homes[t], wrecks[t]], [wrecks[t], shared[(t + 3) % 4]]])
	_relax(pairs)
	for pr in pairs:
		_add_route(pr[0], pr[1], rng)
	# пресная вода: озеро на каждом родниковом, крохотный родник-пруд на скальных
	for I in springs:
		var c: Vector2 = I.center
		var to_center := (-c).normalized()
		var lc := c + to_center.rotated(rng.randf_range(-0.6, 0.6)) * float(I.radius) * 0.12
		lakes.append({"center": lc, "radius": float(I.radius) * 0.3, "level": 3.8, "island": I.id, "kind": &"lake"})
	for I in diag:
		if I.kind == &"rocky":
			var c: Vector2 = I.center
			var off := Vector2.from_angle(rng.randf() * TAU) * float(I.radius) * 0.25
			lakes.append({"center": c + off, "radius": 6.5, "level": 0.0, "island": I.id, "kind": &"pond"})
	# остовы кораблей: на кладбищах — 2 (пляж и мелководье), на одном атолле — 1
	for I in wrecks:
		var c: Vector2 = I.center
		var base := rng.randf() * TAU
		for k in 2:
			var a := base + k * PI * rng.randf_range(0.7, 1.1)
			var d := 0.92 if k == 0 else 1.08
			wreck_spots.append({"pos": c + Vector2.from_angle(a) * float(I.radius) * d,
					"yaw": a + PI * 0.5 + rng.randf_range(-0.5, 0.5), "sink": 1.2 if k == 0 else 3.2, "island": I.id})
	var a0: Dictionary = atolls[0]
	wreck_spots.append({"pos": (a0.center as Vector2) + Vector2(1, 0.4).normalized() * float(a0.radius) * 1.15,
			"yaw": 0.6, "sink": 4.0, "island": a0.id})
	# границы карты
	var bb := Rect2(center.center, Vector2.ZERO)
	for I in islands:
		var r := float(I.radius) * 1.6
		bb = bb.merge(Rect2((I.center as Vector2) - Vector2(r, r), Vector2(r, r) * 2.0))
	bounds = bb.grow(20.0)

static func _movable(I: Dictionary) -> bool:
	return I.kind != &"home" and I.kind != &"center"

## Ширина пролива по линии центров с учётом изрезанности берегов.
func strait_gap(a: Dictionary, b: Dictionary) -> float:
	var ca: Vector2 = a.center
	var cb: Vector2 = b.center
	var ang := (cb - ca).angle()
	return ca.distance_to(cb) - _coast_r(a, ang) - _coast_r(b, ang + PI)

func _relax(pairs: Array) -> void:
	for it in 60:
		for pr in pairs:
			var a: Dictionary = pr[0]
			var b: Dictionary = pr[1]
			var g := strait_gap(a, b)
			var delta := 0.0
			if g > 98.0:
				delta = g - 92.0
			elif g < 52.0:
				delta = g - 58.0
			else:
				continue
			var ma := _movable(a)
			var mb := _movable(b)
			if not ma and not mb:
				continue
			var dir := ((b.center as Vector2) - (a.center as Vector2)).normalized()
			var k := 0.5 if ma and mb else 1.0
			if ma:
				a.center = (a.center as Vector2) + dir * delta * k * 0.5
			if mb:
				b.center = (b.center as Vector2) - dir * delta * k * 0.5

## Пролив: песчаные косы от обоих берегов (не сходятся — нужен мост) и скальный
## островок у середины. Иногда (≈1/4) коса сплошная и открывается в отлив.
func _add_route(a: Dictionary, b: Dictionary, rng: RandomNumberGenerator) -> void:
	var ca: Vector2 = a.center
	var cb: Vector2 = b.center
	var dir := (cb - ca).normalized()
	var side := Vector2(-dir.y, dir.x)
	var p0 := ca + dir * (float(a.radius) * 0.97)
	var p1 := cb - dir * (float(b.radius) * 0.97)
	var gap := p0.distance_to(p1)
	routes.append({"a": a.id, "b": b.id, "gap": gap})
	var bend := rng.randf_range(-1.0, 1.0)
	var full := rng.randf() < 0.25
	var spans: Array = [[0.0, 1.0]] if full else [[0.0, rng.randf_range(0.22, 0.34)], [rng.randf_range(0.66, 0.78), 1.0]]
	for sp in spans:
		var pts := PackedVector2Array()
		for k in 7:
			var t := lerpf(float(sp[0]), float(sp[1]), float(k) / 6.0)
			pts.append(p0.lerp(p1, t) + side * sin(t * PI) * 9.0 * bend)
		var top := -0.3 if full else rng.randf_range(-0.85, -0.35)
		_add_bar(pts, rng.randf_range(8.0, 12.0), top)
	if gap > 55.0:
		var mid := p0.lerp(p1, rng.randf_range(0.42, 0.58)) + side * (9.0 * bend + 14.0 * signf(bend + 0.01))
		islets.append({"center": mid, "radius": rng.randf_range(5.5, 8.5), "top": rng.randf_range(3.0, 5.5)})

func _add_bar(pts: PackedVector2Array, width: float, top: float) -> void:
	var mn := pts[0]
	var mx := pts[0]
	for p in pts:
		mn = Vector2(minf(mn.x, p.x), minf(mn.y, p.y))
		mx = Vector2(maxf(mx.x, p.x), maxf(mx.y, p.y))
	var g := width * 2.3
	bars.append({"pts": pts, "width": width, "top": top, "bmin": mn - Vector2(g, g), "bmax": mx + Vector2(g, g)})

func _build_grid() -> void:
	_grid.clear()
	for idx in islands.size():
		var I: Dictionary = islands[idx]
		var r := float(I.radius) * 2.3
		_grid_add((I.center as Vector2) - Vector2(r, r), (I.center as Vector2) + Vector2(r, r), "i", idx)
	for idx in bars.size():
		_grid_add(bars[idx].bmin, bars[idx].bmax, "b", idx)
	for idx in islets.size():
		var il: Dictionary = islets[idx]
		var r := float(il.radius) * 3.0
		_grid_add((il.center as Vector2) - Vector2(r, r), (il.center as Vector2) + Vector2(r, r), "l", idx)
	for idx in lakes.size():
		var L: Dictionary = lakes[idx]
		var r := float(L.radius) * 1.8
		_grid_add((L.center as Vector2) - Vector2(r, r), (L.center as Vector2) + Vector2(r, r), "k", idx)

func _grid_add(mn: Vector2, mx: Vector2, key: String, idx: int) -> void:
	for cz in range(int(floor(mn.y / CELL)), int(floor(mx.y / CELL)) + 1):
		for cx in range(int(floor(mn.x / CELL)), int(floor(mx.x / CELL)) + 1):
			var k := Vector2i(cx, cz)
			if not _grid.has(k):
				_grid[k] = {"i": PackedInt32Array(), "b": PackedInt32Array(), "l": PackedInt32Array(), "k": PackedInt32Array()}
			var arr: PackedInt32Array = _grid[k][key]
			arr.append(idx)
			_grid[k][key] = arr

func _cell(x: float, z: float) -> Dictionary:
	return _grid.get(Vector2i(int(floor(x / CELL)), int(floor(z / CELL))), {})

# ---------------------------------------------------------------- высоты

## Высота рельефа (метры над средним уровнем моря).
func height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var h := SEA_FLOOR + _n_floor.get_noise_2d(x, z) * 2.0
	var cell := _cell(x, z)
	if cell.is_empty():
		return h
	for idx in cell.i:
		h = maxf(h, _island_h(islands[idx], p))
	for idx in cell.b:
		h = maxf(h, _bar_h(bars[idx], p))
	for idx in cell.l:
		h = maxf(h, _islet_h(islets[idx], p))
	for idx in cell.k:
		h = _lake_h(lakes[idx], p, h)
	return h

func _coast_r(I: Dictionary, ang: float) -> float:
	var id := float(I.id)
	var cn := _n_coast.get_noise_2d(cos(ang) * 70.0 + id * 1000.0, sin(ang) * 70.0)
	var amp := 0.17
	if I.kind == &"atoll" or I.kind == &"rocky":
		amp = 0.1
	return float(I.radius) * (1.0 + amp * cn)

static func _sector(ang: float, center: float, half_width: float) -> float:
	if center < -1.5:
		return 1.0      # утёсы по всему берегу
	if center < 0.0:
		return 0.0
	var d := absf(angle_difference(ang, center))
	return 1.0 - smoothstep(half_width * 0.5, half_width, d)

func _island_h(I: Dictionary, p: Vector2) -> float:
	var c: Vector2 = I.center
	var v := p - c
	var dist := v.length()
	if dist > float(I.radius) * 2.3:
		return -100.0
	var ang := atan2(v.y, v.x)
	var R := _coast_r(I, ang)
	var d := dist / R
	var kind: StringName = I.kind
	var cliff := _sector(ang, float(I.cliff_dir), deg_to_rad(55.0))
	if d >= 1.0:
		return _underwater_h(I, p, d, cliff)
	var inland := 1.0 - d
	match kind:
		&"center":
			return _volcano_h(I, p, d, inland)
		&"swamp":
			return _swamp_h(p, inland)
		&"atoll":
			return _atoll_h(p, d)
	var bw: float = I.beach_w
	var hb := BEACH_H * smoothstep(0.0, bw, inland)
	hb += 0.55 * maxf(0.0, _n_dune.get_noise_2d(p.x, p.y)) * _bump(inland, 0.03, bw + 0.05)
	var hn := _n_hills.get_noise_2d(p.x, p.y) * 0.5 + 0.5
	var rn := _n_ridge.get_noise_2d(p.x, p.y) * 0.5 + 0.5
	var core := pow(smoothstep(0.07, 0.95, inland), 1.25)
	var hi := BEACH_H + 0.3 + float(I.max_h) * core * (0.45 + 0.45 * hn + 0.35 * rn)
	if kind == &"rocky":
		# скальное плато: крутой подъём от воды и неровный верх
		hi = float(I.max_h) * (0.55 + 0.25 * hn + 0.35 * rn) * smoothstep(0.0, 0.14, inland) + 1.0
	var h := lerpf(hb, hi, smoothstep(bw - 0.02, bw + 0.1, inland))
	# утёсы: крутой подъём прямо от воды
	if cliff > 0.0 and kind != &"rocky":
		var hc := float(I.max_h) * 0.55 * smoothstep(0.0, 0.055, inland) + hi * 0.45
		h = lerpf(h, maxf(h, hc), cliff)
	elif kind == &"rocky":
		h = lerpf(hb, hi, smoothstep(0.0, 0.05, inland))
	# лагуна: чаша у берега, соединённая с морем протокой
	var ld := float(I.lagoon_dir)
	if ld >= 0.0:
		var dirv := Vector2(cos(ld), sin(ld))
		var Rl := _coast_r(I, ld)
		var lc := c + dirv * Rl * 0.7
		var lr := float(I.radius) * 0.21
		var dl := p.distance_to(lc) / lr
		if dl < 1.6:
			var floor_h := -1.6 + _n_detail.get_noise_2d(p.x * 0.5, p.y * 0.5) * 0.3
			var rim := lerpf(0.55, 1.4, smoothstep(1.0, 1.55, dl))
			var bowl := lerpf(floor_h, rim, smoothstep(0.55, 1.05, dl))
			h = minf(h, lerpf(bowl, h, smoothstep(1.3, 1.6, dl)))
		var pc := c + dirv * Rl
		var seg := _seg_dist(p, lc, pc)
		if seg < 9.0:
			h = minf(h, lerpf(-1.3, h, smoothstep(4.0, 9.0, seg)))
	h += _n_detail.get_noise_2d(p.x, p.y) * 0.22 * smoothstep(0.08, 0.3, inland)
	if kind == &"wreck":
		var rk := _wreck_rock(p, inland)
		if rk > 0.0:
			h += pow(rk, 0.7) * (2.6 + 1.4 * absf(_n_ridge.get_noise_2d(p.x * 2.5, p.y * 2.5))) + _n_detail.get_noise_2d(p.x * 3.0, p.y * 3.0) * 0.4 * rk
	return h

## Скальные гряды у берега кладбища кораблей (0..1).
func _wreck_rock(p: Vector2, inland: float) -> float:
	var n := _n_reef.get_noise_2d(p.x * 1.6 + 300.0, p.y * 1.6)
	return smoothstep(0.28, 0.5, n) * (1.0 - smoothstep(0.18, 0.4, inland)) * smoothstep(-0.04, 0.04, inland)

func _underwater_h(I: Dictionary, p: Vector2, d: float, cliff: float) -> float:
	var shelf := lerpf(0.0, -2.4, smoothstep(1.0, 1.12, d))
	var h := lerpf(shelf, SEA_FLOOR, smoothstep(1.12, 1.8, d))
	if I.kind == &"atoll":
		# широкий внешний риф атолла
		h = lerpf(lerpf(0.0, -1.2, smoothstep(1.0, 1.25, d)), SEA_FLOOR, smoothstep(1.25, 1.9, d))
	h = lerpf(h, minf(h, -6.0), cliff * smoothstep(1.0, 1.08, d)) # под утёсом — сразу глубоко
	if I.kind == &"wreck":
		var rk := smoothstep(0.28, 0.5, _n_reef.get_noise_2d(p.x * 1.6 + 300.0, p.y * 1.6)) * (1.0 - smoothstep(1.0, 1.35, d))
		h = maxf(h, lerpf(h, 1.2 + _n_detail.get_noise_2d(p.x, p.y), rk))
	var reef := smoothstep(0.18, 0.42, _n_reef.get_noise_2d(p.x, p.y)) * _bump(d, 1.02, 1.3) * (1.0 - cliff)
	if reef > 0.0:
		h = maxf(h, lerpf(h, -0.75 + _n_detail.get_noise_2d(p.x, p.y) * 0.35, reef))
	return h

## Вулкан: конус с кратером, радиальные овраги, чёрный пляж у подножия.
func _volcano_h(I: Dictionary, p: Vector2, d: float, inland: float) -> float:
	var mh: float = I.max_h
	var hb := BEACH_H * smoothstep(0.0, 0.06, inland)
	var c: Vector2 = I.center
	var ang := atan2(p.y - c.y, p.x - c.x)
	# неровный конус: вершина смещена, склоны с разной крутизной
	var lob := _n_coast.get_noise_2d(cos(ang) * 40.0 + 500.0, sin(ang) * 40.0) * 0.18
	var cone := pow(clampf(inland / (0.9 + lob * 0.4), 0.0, 1.0), 1.45 + lob * 2.0)
	var warp := _n_hills.get_noise_2d(p.x * 0.6, p.y * 0.6) * 4.0 + _n_detail.get_noise_2d(p.x * 0.2, p.y * 0.2) * 1.5
	var gully := absf(sin(ang * 7.0 + warp))
	var gdepth := 2.0 + 3.5 * (_n_ridge.get_noise_2d(cos(ang) * 30.0, sin(ang) * 30.0) * 0.5 + 0.5)
	var hc := BEACH_H + 0.3 + (mh - BEACH_H) * cone * (1.0 + _n_hills.get_noise_2d(p.x, p.y) * 0.12)
	hc -= pow(1.0 - gully, 2.0) * gdepth * smoothstep(0.12, 0.5, inland) * (1.0 - smoothstep(0.8, 0.9, inland))
	hc += _n_ridge.get_noise_2d(p.x, p.y) * 2.0 * smoothstep(0.1, 0.4, inland)
	# кратер
	var rc := 0.15
	var k := 1.0 - smoothstep(rc * 0.55, rc * 1.05, d)
	hc -= k * mh * 0.38
	var h := lerpf(hb, hc, smoothstep(0.04, 0.12, inland))
	return h + _n_detail.get_noise_2d(p.x, p.y) * 0.3

## Мангровое болото: низкая плоская суша, протоки и лужи с илом.
func _swamp_h(p: Vector2, inland: float) -> float:
	var base := 0.45 + 0.75 * smoothstep(0.0, 0.4, inland) + _n_hills.get_noise_2d(p.x, p.y) * 0.35
	var chan := absf(_n_chan.get_noise_2d(p.x, p.y))
	var cut := 1.0 - smoothstep(0.03, 0.17, chan)
	var h := lerpf(base, -0.55, cut * cut * (3.0 - 2.0 * cut))
	return h + _n_detail.get_noise_2d(p.x, p.y) * 0.15

## Атолл: узкое песчаное кольцо вокруг мелкой лагуны.
func _atoll_h(p: Vector2, d: float) -> float:
	var ring := _bump(d, 0.62, 1.0)
	var h_land := BEACH_H * 1.12 * ring + 0.4 * maxf(0.0, _n_dune.get_noise_2d(p.x, p.y)) * ring
	if d < 0.66:
		var lag := -2.6 + _n_detail.get_noise_2d(p.x * 0.4, p.y * 0.4) * 0.6
		return lerpf(lag, h_land, smoothstep(0.56, 0.66, d))
	# узкие протоки в кольце
	var chan := absf(_n_chan.get_noise_2d(p.x * 0.6, p.y * 0.6))
	if chan < 0.03:
		h_land = minf(h_land, lerpf(-0.9, h_land, chan / 0.03))
	return h_land - 0.35 + 0.35 * smoothstep(0.62, 0.7, d)

func _bar_h(bar: Dictionary, p: Vector2) -> float:
	var mn: Vector2 = bar.bmin
	var mx: Vector2 = bar.bmax
	if p.x < mn.x or p.y < mn.y or p.x > mx.x or p.y > mx.y:
		return -100.0
	var pts: PackedVector2Array = bar.pts
	var best := 1e9
	var bt := 0.0
	for k in pts.size() - 1:
		var dd := _seg_dist(p, pts[k], pts[k + 1])
		if dd < best:
			best = dd
			bt = float(k) / float(pts.size() - 1)
	var w: float = bar.width
	if best > w * 2.2:
		return -100.0
	# коса понижается к свободному концу (не обрывается ступенькой)
	var top: float = float(bar.top) + _n_dune.get_noise_2d(p.x * 0.7, p.y * 0.7) * 0.35
	var t := best / w
	return top - t * t * 2.6

func _islet_h(il: Dictionary, p: Vector2) -> float:
	var c: Vector2 = il.center
	var v := p - c
	var r: float = il.radius * (1.0 + 0.3 * _n_coast.get_noise_2d(cos(v.angle()) * 25.0 + c.x, sin(v.angle()) * 25.0 + c.y))
	var d := v.length() / r
	if d > 3.0:
		return -100.0
	var rough := _n_detail.get_noise_2d(p.x * 1.3, p.y * 1.3) * 0.9 + _n_ridge.get_noise_2d(p.x * 3.0, p.y * 3.0) * 0.5
	if d < 1.0:
		# скала: крутые бока, бугристый верх с наклоном
		var tilt := v.dot(Vector2(0.6, 0.8)) / maxf(r, 1.0) * 0.8
		return float(il.top) * (1.0 - pow(d, 3.0)) * (1.0 + tilt * 0.4) + rough
	return -0.6 - (d - 1.0) * 4.5 + rough

## Озеро/пруд: чаша с пологим дном; вокруг озера рельеф опускается в
## котловину (не выше level+0.5+…), но берег везде выше воды (не «вытекает»).
func _lake_h(L: Dictionary, p: Vector2, h: float) -> float:
	var c: Vector2 = L.center
	var r: float = L.radius
	var v := p - c
	# неровный берег: радиус ±12 % по углу
	var wob := 1.0 + 0.12 * _n_coast.get_noise_2d(cos(v.angle()) * 30.0 + c.x, sin(v.angle()) * 30.0 + c.y)
	var dl := v.length() / (r * wob)
	var reach := 2.4 if L.kind == &"lake" else 1.8
	if dl > reach:
		return h
	var level: float = L.level
	var rim := level + 0.45 + _n_detail.get_noise_2d(p.x, p.y) * 0.12
	var hr := h
	if L.kind == &"lake":
		# котловина: потолок растёт от берега наружу
		var cap := rim + 9.0 * pow(smoothstep(1.0, reach, dl), 1.6) + _n_hills.get_noise_2d(p.x, p.y) * 0.6 * smoothstep(1.2, 1.8, dl)
		hr = minf(h, cap)
	hr = maxf(hr, lerpf(rim, hr, smoothstep(1.12, reach * 0.8, dl)))
	var bed := level - 0.35 - 2.4 * (1.0 - dl * dl) + _n_detail.get_noise_2d(p.x * 0.7, p.y * 0.7) * 0.25
	return lerpf(bed, hr, smoothstep(0.78, 1.1, dl))

## Пруд на скале: уровень чуть ниже рельефа в центре пруда.
func _pond_level(L: Dictionary) -> float:
	if L.has("_lv"):
		return float(L._lv)
	var c: Vector2 = L.center
	var hh := -100.0
	var cell := _cell(c.x, c.y)
	for idx in cell.get("i", PackedInt32Array()):
		hh = maxf(hh, _island_h(islands[idx], c))
	return maxf(hh - 0.8, 1.5)

func finalize_ponds() -> void:
	## Фиксирует уровни прудов (вызывать до многопоточной выборки).
	for L in lakes:
		if L.kind == &"pond":
			L._lv = _pond_level(L)
			L.level = L._lv

static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return p.distance_to(a + ab * t)

static func _bump(x: float, a: float, b: float) -> float:
	return smoothstep(a, lerpf(a, b, 0.35), x) * (1.0 - smoothstep(lerpf(a, b, 0.65), b, x))

# ---------------------------------------------------------------- биомы

## Ближайший остров и нормированное расстояние до берега (d<1 — суша).
func island_at(p: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var bd := 1e9
	var cell := _cell(p.x, p.y)
	var cand: PackedInt32Array = cell.get("i", PackedInt32Array())
	for idx in cand:
		var I: Dictionary = islands[idx]
		var c: Vector2 = I.center
		var v := p - c
		var d := v.length() / _coast_r(I, atan2(v.y, v.x))
		if d < bd:
			bd = d
			best = I
	return {"island": best, "d": bd}

## Веса биомов для покраски: r — джунгли, g — болото/мангры, b — утёсы/скалы,
## a — вулканическая порода (тёмный камень, пепел).
func biome_weights(x: float, z: float, h: float) -> Color:
	var p := Vector2(x, z)
	var cell := _cell(x, z)
	for idx in cell.get("l", PackedInt32Array()):
		var il: Dictionary = islets[idx]
		if p.distance_to(il.center) < float(il.radius) * 1.5:
			return Color(0.0, 0.0, 0.0, 1.0)
	var ia := island_at(p)
	var I: Dictionary = ia.island
	var d: float = ia.d
	if I.is_empty() or d > 1.12:
		return Color(0, 0, 0, 0)
	var c: Vector2 = I.center
	var v := p - c
	var ang := atan2(v.y, v.x)
	var inland := 1.0 - d
	var moist := _n_moist.get_noise_2d(x, z) * 0.5 + 0.5
	var kind: StringName = I.kind
	match kind:
		&"center":
			var volc := smoothstep(5.0, 14.0, h)
			var jl := smoothstep(0.35, 0.55, moist) * smoothstep(0.08, 0.2, inland) * (1.0 - volc)
			return Color(jl, 0.0, smoothstep(14.0, 26.0, h) * 0.6, maxf(volc, 1.0 - smoothstep(0.03, 0.1, inland)))
		&"rocky":
			return Color(0.15 * smoothstep(0.5, 0.7, moist), 0.0, smoothstep(2.0, 4.0, h), 0.0)
		&"swamp":
			return Color(0.35 + 0.3 * moist, 1.0 - smoothstep(1.4, 2.4, h), 0.0, 0.0)
		&"atoll":
			return Color(0.0, 0.0, 0.0, 0.0)
		&"wreck":
			var rk := _wreck_rock(p, inland) if inland > 0.0 else smoothstep(0.28, 0.5, _n_reef.get_noise_2d(p.x * 1.6 + 300.0, p.y * 1.6))
			return Color(0.25 * smoothstep(0.5, 0.65, moist) * smoothstep(0.25, 0.4, inland), 0.0, 0.0, smoothstep(0.1, 0.4, rk))
		&"spring":
			moist = clampf(moist + 0.25, 0.0, 1.0)
	var cliff := _sector(ang, float(I.cliff_dir), deg_to_rad(55.0)) * smoothstep(2.5, 5.0, h)
	var jungle := smoothstep(0.42, 0.6, moist) * smoothstep(0.14, 0.26, inland) * (1.0 - cliff)
	var swamp := 0.0
	var ld := float(I.lagoon_dir)
	if ld >= 0.0:
		var dirv := Vector2(cos(ld), sin(ld))
		var lc := c + dirv * _coast_r(I, ld) * 0.7
		var dl := p.distance_to(lc) / (float(I.radius) * 0.21)
		swamp = (1.0 - smoothstep(1.2, 1.9, dl)) * (1.0 - smoothstep(1.6, 2.6, h))
	return Color(jungle, swamp, cliff, 0.0)

# ---------------------------------------------------------------- вода и места

## Пресная вода в точке (озёра на родниковых островах, пруды на скальных).
func fresh_water_at(pos: Vector3) -> bool:
	var p := Vector2(pos.x, pos.z)
	var cell := _cell(p.x, p.y)
	for idx in cell.get("k", PackedInt32Array()):
		var L: Dictionary = lakes[idx]
		var c: Vector2 = L.center
		if p.distance_to(c) < float(L.radius) * 1.3 and pos.y < float(L.level) + 0.6 and pos.y > float(L.level) - 3.5 \
				and height(p.x, p.y) < float(L.level) - 0.05:
			return true
	return false

## Остров по id.
func island_by_id(id: int) -> Dictionary:
	return islands[id] if id >= 0 and id < islands.size() else {}

## Точка на пляже острова под углом a (между водой и травой).
func beach_point(I: Dictionary, a: float) -> Vector2:
	var R := _coast_r(I, a)
	var c: Vector2 = I.center
	var d := 0.95
	if I.kind == &"atoll":
		d = 0.82
	return c + Vector2.from_angle(a) * R * d
