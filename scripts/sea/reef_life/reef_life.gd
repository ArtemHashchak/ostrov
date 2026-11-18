class_name ReefLife
extends Node3D
## Живой риф — фон, а не механика: тысячи ярких тропических рыб, морская трава,
## мягкие кораллы, губки, актинии с рыбами-клоунами, звёзды, ежи, тридакны, крабы
## и лангусты. Движение — в шейдерах (reef_fish/crawler/coral), процессор только
## ведёт общий час (global sea_time/sea_level), пугает стаи рядом с людьми/акулами
## и запускает сценки охоты (ReefScenes).
## Подгрузка клетками 32 м вокруг камеры (радиус STREAM_R): содержимое клетки
## детерминировано (сид по координатам) — вернёшься, всё на месте; дальние клетки
## удаляются. Плотность высокая везде, нагрузка постоянная. Новая клетка — не больше
## одной за кадр. Дальний план — рифы SeaReefs.

static var time: float = 0.0
static var level: float = 0.0

const CELL := 32.0
const SCARE_STEP := 0.25
const STREAM_R := 2          # клеток вокруг камеры (5×5 ≈ 160 м)
const DROP_R := 3            # дальше — удалить
const SAMPLE := 6            # проб глубины на сторону клетки

## Декор: меш, качание, глубины, масштаб, оттенки, где (reef/meadow/shore).
const DECOR := {
	&"seagrass": {"sway": 0.12, "s": [0.7, 1.4], "end": 45.0,
		"tints": [Color(1, 1, 1), Color(0.9, 1.0, 0.85), Color(1.05, 1.0, 0.8)]},
	&"soft_coral": {"sway": 0.05, "s": [0.6, 1.4], "end": 55.0,
		"tints": [Color(0.95, 0.55, 0.75), Color(0.8, 0.55, 0.95), Color(1.0, 0.75, 0.6), Color(0.95, 0.9, 0.7), Color(1.0, 0.5, 0.45)]},
	&"sea_whip": {"sway": 0.1, "s": [0.7, 1.3], "end": 50.0,
		"tints": [Color(0.95, 0.25, 0.2), Color(1.0, 0.75, 0.15), Color(0.9, 0.35, 0.7), Color(1.0, 0.5, 0.15)]},
	&"tube_sponge": {"sway": 0.0, "s": [0.7, 1.5], "end": 55.0,
		"tints": [Color(0.6, 0.3, 0.75), Color(1.0, 0.75, 0.2), Color(0.95, 0.45, 0.2), Color(0.45, 0.6, 0.9)]},
	&"barrel_sponge": {"sway": 0.0, "s": [0.7, 1.6], "end": 70.0,
		"tints": [Color(0.7, 0.4, 0.3), Color(0.6, 0.35, 0.4), Color(0.75, 0.55, 0.4)]},
	&"anemone": {"sway": 0.07, "s": [0.8, 1.5], "end": 45.0,
		"tints": [Color(1, 1, 1), Color(0.9, 0.7, 1.1), Color(1.1, 0.9, 0.7)]},
	&"clam": {"sway": 0.0, "s": [0.7, 1.3], "end": 35.0,
		"tints": [Color(1, 1, 1), Color(0.8, 1.0, 0.9), Color(1.1, 0.8, 1.2)]},
	&"starfish": {"sway": 0.0, "s": [0.7, 1.3], "end": 30.0,
		"tints": [Color(1.0, 0.45, 0.12), Color(0.2, 0.45, 1.0), Color(0.9, 0.2, 0.15), Color(1.0, 0.8, 0.3)]},
	&"urchin": {"sway": 0.0, "s": [0.7, 1.3], "end": 30.0, "tints": [Color(1, 1, 1), Color(1.3, 0.9, 1.3)]},
	&"cucumber": {"sway": 0.0, "s": [0.8, 1.4], "end": 30.0, "tints": [Color(1, 1, 1), Color(0.6, 0.6, 0.6), Color(1.2, 0.9, 0.7)]},
	&"algae_bush": {"sway": 0.06, "s": [0.7, 1.6], "end": 40.0, "tints": [Color(1, 1, 1), Color(0.85, 1.05, 0.8)]},
	&"brown_algae": {"sway": 0.13, "s": [0.7, 1.5], "end": 45.0, "tints": [Color(1, 1, 1), Color(1.1, 1.05, 0.8)]},
	# кораллы из SeaMeshes — ярче, чем у фоновых рифов
	&"coral_branch": {"sway": 0.0, "s": [0.6, 1.4], "end": 60.0,
		"tints": [Color(1.0, 0.7, 0.55), Color(0.75, 0.55, 1.0), Color(0.5, 0.75, 1.0), Color(0.65, 0.85, 0.45), Color(1.0, 0.55, 0.7), Color(1.0, 0.9, 0.5)]},
	&"coral_brain": {"sway": 0.0, "s": [0.6, 1.5], "end": 60.0,
		"tints": [Color(0.9, 0.8, 0.45), Color(0.6, 0.8, 0.5), Color(0.95, 0.65, 0.45), Color(0.75, 0.85, 0.7)]},
	&"coral_table": {"sway": 0.0, "s": [0.7, 1.6], "end": 65.0, "tints": [Color(0.75, 0.85, 0.6), Color(0.9, 0.85, 0.7), Color(0.6, 0.7, 0.9)]},
	&"coral_fan": {"sway": 0.06, "s": [0.7, 1.4], "end": 55.0,
		"tints": [Color(0.8, 0.3, 0.75), Color(1.0, 0.4, 0.25), Color(1.0, 0.8, 0.3), Color(0.65, 0.3, 0.9)]},
	&"sponge": {"sway": 0.0, "s": [0.7, 1.5], "end": 55.0, "tints": [Color(1.0, 0.55, 0.2), Color(0.6, 0.3, 0.7), Color(1.0, 0.85, 0.3), Color(0.85, 0.3, 0.25)]},
	&"reef_rock": {"sway": 0.0, "s": [1.2, 2.6], "end": 75.0, "tints": [Color(0.55, 0.52, 0.46), Color(0.6, 0.5, 0.55), Color(0.5, 0.55, 0.48)]},
}

## Состав рифа: вид → вес (для групп у рифа) и стаи.
const REEF_GROUPS := {&"yellow_tang": 3.0, &"blue_tang": 2.0, &"butterfly": 3.0, &"moorish_idol": 1.5, &"emperor_angel": 1.0,
	&"parrotfish": 2.0, &"wrasse": 2.0, &"grouper": 0.7, &"damsel": 2.5}
const SWARMS := [&"chromis", &"anthias", &"damsel"]
const SCHOOLS := [&"snapper", &"fusilier"]
const KIND_RICH := {&"atoll": 1.0, &"shared": 0.85, &"wreck": 0.7, &"spring": 0.6, &"home": 0.5, &"rocky": 0.45, &"center": 0.35, &"swamp": 0.0}

var sea: Node = null
var density: float = 1.0
var schools: Array[ReefSchool] = []
var scenes: Node = null           # ReefScenes
var bait_balls: Array[ReefSchool] = []
var anemones: Array[Vector3] = []
var fish_count: int = 0
var decor_count: int = 0
var crawler_count: int = 0
var heads_count: int = 0
var cells_built: int = 0
var _cells: Dictionary = {}       # Vector2i → Node3D (клетка)
var _cell_schools: Dictionary = {} # Vector2i → Array[ReefSchool]
var _grid: Dictionary = {}        # Vector2i → Array[ReefSchool] (по центрам)
var _decor: Dictionary = {}       # тип → {xf, col} (собирается для текущей клетки)
var _crawl: Dictionary = {}
var _cur: Node3D = null           # клетка, которая сейчас строится
var _cur_key := Vector2i.ZERO
var _rng := RandomNumberGenerator.new()
var _scare_acc := 0.0
var _noise := FastNoiseLite.new()
var _mats: Dictionary = {}
var _crawl_mats: Dictionary = {}
var _islands: Array = []
var _zones: Array = []

func _ready() -> void:
	add_to_group(&"reef_life")

static func instance() -> ReefLife:
	var t := Engine.get_main_loop() as SceneTree
	return t.get_first_node_in_group(&"reef_life") as ReefLife if t else null

func _floor(x: float, z: float) -> float:
	return float(sea.call(&"floor_at", x, z))

func _depth(x: float, z: float) -> float:
	return float(sea.call(&"depth_at", x, z))

# =============================== постройка ===============================

## Подготовка (вызывает Sea после рифов). Клетки строятся вокруг камеры.
func build() -> void:
	for k in _cells.keys():
		_drop_cell(k)
	for c in get_children():
		c.queue_free()
	scenes = null
	schools.clear()
	bait_balls.clear()
	_grid.clear()
	fish_count = 0
	decor_count = 0
	crawler_count = 0
	heads_count = 0
	_noise.seed = 4242
	_noise.frequency = 0.045
	level = float(sea.call(&"water_y"))
	_islands = sea.call(&"islands")
	_zones = sea.call(&"reef_zones")
	scenes = ReefScenes.new()
	scenes.name = "Scenes"
	scenes.set(&"life", self)
	add_child(scenes)

## Сразу достроить все клетки вокруг точки (старт матча, тесты).
func stream_now(at: Vector3) -> void:
	var need := _wanted(at)
	for k: Vector2i in need:
		if not _cells.has(k):
			_build_cell(k)

func _wanted(at: Vector3) -> Array[Vector2i]:
	var c := Vector2i(floori(at.x / CELL), floori(at.z / CELL))
	var out: Array[Vector2i] = []
	for dx in range(-STREAM_R, STREAM_R + 1):
		for dz in range(-STREAM_R, STREAM_R + 1):
			out.append(c + Vector2i(dx, dz))
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a - c).length_squared() < (b - c).length_squared())
	return out

func _stream(at: Vector3) -> void:
	var c := Vector2i(floori(at.x / CELL), floori(at.z / CELL))
	for k: Vector2i in _cells.keys():
		if absi(k.x - c.x) > DROP_R or absi(k.y - c.y) > DROP_R:
			_drop_cell(k)
	if at.y > level + 70.0:
		return
	for k in _wanted(at):
		if not _cells.has(k):
			_build_cell(k)
			return   # одна клетка за кадр

func _drop_cell(k: Vector2i) -> void:
	for s: ReefSchool in _cell_schools.get(k, []):
		schools.erase(s)
		bait_balls.erase(s)
		fish_count -= s.count()
		var g := Vector2i(floori(s.center.x / CELL), floori(s.center.z / CELL))
		if _grid.has(g):
			(_grid[g] as Array).erase(s)
	_cell_schools.erase(k)
	var n: Node3D = _cells.get(k)
	if n and is_instance_valid(n):
		decor_count -= int(n.get_meta(&"decor", 0))
		crawler_count -= int(n.get_meta(&"crawl", 0))
		n.queue_free()
	_cells.erase(k)

## Богатство места: тип ближайшего острова + близость к пятну рифа + шум.
func _richness(x: float, z: float) -> float:
	var best := INF
	var kind: StringName = &""
	for I: Dictionary in _islands:
		var c: Vector2 = I["center"]
		var d := Vector2(x, z).distance_to(c) - float(I["radius"])
		if d < best:
			best = d
			kind = StringName(I.get("kind", &""))
	var r := float(KIND_RICH.get(kind, 0.5))
	if r <= 0.0:
		return 0.0
	for zn: Dictionary in _zones:
		var c: Vector2 = zn["center"]
		if Vector2(x, z).distance_to(c) < float(zn["radius"]) * 1.05:
			r += 0.35
			break
	r *= 0.75 + 0.5 * (_noise.get_noise_2d(x * 0.3, z * 0.3) * 0.5 + 0.5)
	return clampf(r * density, 0.0, 1.6)

func _build_cell(k: Vector2i) -> void:
	var cell := Node3D.new()
	cell.name = "Cell_%d_%d" % [k.x, k.y]
	add_child(cell)
	_cells[k] = cell
	_cell_schools[k] = []
	_cur = cell
	_cur_key = k
	cells_built += 1
	_rng.seed = hash(Vector2i(k.x * 7919 + 13, k.y * 104729 + 7))
	var x0 := k.x * CELL
	var z0 := k.y * CELL
	var rich := _richness(x0 + CELL * 0.5, z0 + CELL * 0.5)
	# пробы глубины
	var pts: Array[Vector3] = []
	var depths: PackedFloat32Array = PackedFloat32Array()
	var step := CELL / SAMPLE
	for i in SAMPLE:
		for j in SAMPLE:
			var x := x0 + (i + _rng.randf()) * step
			var z := z0 + (j + _rng.randf()) * step
			var f := _floor(x, z)
			pts.append(Vector3(x, f, z))
			depths.append(level - f)
	var d0 := decor_count
	var c0 := crawler_count
	if rich > 0.0:
		_fill_cell(pts, depths, rich)
	_flush_decor()
	_flush_crawlers()
	cell.set_meta(&"decor", decor_count - d0)
	cell.set_meta(&"crawl", crawler_count - c0)
	_cur = null

func _fill_cell(pts: Array[Vector3], depths: PackedFloat32Array, rich: float) -> void:
	var shallow: Array[int] = []
	var reefy: Array[int] = []
	var deep: Array[int] = []
	for i in pts.size():
		var d := depths[i]
		if d > 0.4 and d < 4.5:
			shallow.append(i)
		if d > 1.2 and d < 10.0:
			reefy.append(i)
		if d > 4.5 and d < 30.0:
			deep.append(i)
	# коралловые головы
	var heads := 0
	var want := rich * 1.5
	want = floorf(want) + (1.0 if _rng.randf() < want - floorf(want) else 0.0)
	var made: Array[Vector3] = []
	for h in int(want) * 3:
		if made.size() >= int(want) or reefy.is_empty():
			break
		var p := pts[reefy[_rng.randi() % reefy.size()]]
		var ok := true
		for q in made:
			if q.distance_to(p) < 10.0:
				ok = false
		if ok:
			made.append(p)
			_coral_head(p, _rng.randf_range(4.0, 7.5), rich)
	heads_count += made.size()
	# луга морской травы и мелочь на песке
	for i in shallow + reefy:
		var p := pts[i]
		var nv := _noise.get_noise_2d(p.x, p.z)
		if nv > -0.05:
			var n := 2 + int(nv * 8.0 * rich)
			for k in n:
				var q := p + Vector3(_rng.randf_range(-2.6, 2.6), 0, _rng.randf_range(-2.6, 2.6))
				var f := _floor(q.x, q.z)
				if level - f > 0.4:
					_add_decor(&"seagrass", Vector3(q.x, f, q.z))
		var roll := _rng.randf()
		if roll < 0.08 * rich:
			_add_decor(&"starfish", p)
		elif roll < 0.15 * rich:
			_add_decor(&"cucumber", p)
		elif roll < 0.25 * rich:
			_add_decor(&"urchin", p)
		elif roll < 0.33 * rich:
			_add_decor(&"brown_algae", p)
		elif roll < 0.4 * rich:
			_add_decor(&"algae_bush", p)
	# крабы на мелководье
	for i in shallow:
		if _rng.randf() < 0.18 * rich + 0.05:
			_add_crawler(&"crab", pts[i] + Vector3(_rng.randf_range(-2, 2), 0, _rng.randf_range(-2, 2)))
	# рыбы на песке/траве у берега
	if not shallow.is_empty():
		for g in int(rich * 1.5 + _rng.randf()):
			var p := pts[shallow[_rng.randi() % shallow.size()]]
			_reef_group([&"wrasse", &"damsel", &"parrotfish", &"butterfly"][_rng.randi() % 4], p)
	# стая в толще
	if not reefy.is_empty() and _rng.randf() < 0.45 * rich:
		var p := pts[reefy[_rng.randi() % reefy.size()]]
		if level - p.y > 2.6:
			_open_school(SCHOOLS[_rng.randi() % SCHOOLS.size()], p)
	# косяк сардин над глубиной (для чаек и хищников)
	if not deep.is_empty() and _rng.randf() < 0.3:
		var p := pts[deep[_rng.randi() % deep.size()]]
		bait_balls.append(_open_school(&"sardine", p))

## Одна коралловая голова: скалы, кораллы, губки, водоросли, актинии, вокруг — рыбы.
func _coral_head(p: Vector3, r: float, rich: float) -> void:
	var cc := Vector2(p.x, p.z)
	for i in _rng.randi_range(2, 4):
		var q: Variant = _spot(cc, 0.0, r * 0.45, 0.5, 12.0, 4)
		if q != null:
			_add_decor(&"reef_rock", q)
	var plan := {&"coral_branch": [6, 12], &"coral_brain": [3, 7], &"coral_table": [1, 3], &"coral_fan": [2, 5], &"sponge": [2, 4],
		&"soft_coral": [4, 9], &"sea_whip": [3, 7], &"tube_sponge": [2, 5], &"barrel_sponge": [0, 2], &"anemone": [1, 3],
		&"clam": [0, 2], &"urchin": [3, 7], &"algae_bush": [4, 9], &"brown_algae": [1, 4], &"starfish": [1, 3]}
	var k := clampf(rich * 1.1, 0.5, 1.5)
	for t: StringName in plan:
		var rng_n: Array = plan[t]
		var n := int(round(_rng.randi_range(rng_n[0], rng_n[1]) * k))
		for i in n:
			var q: Variant = _spot(cc, 0.0, r * (0.55 + 0.45 * _rng.randf()), 0.5, 12.0, 4)
			if q == null:
				continue
			_add_decor(t, q)
			if t == &"anemone" and _rng.randf() < 0.8:
				_clowns(q)
	for i in _rng.randi_range(1, 3):
		var q: Variant = _spot(cc, 0.0, r * 0.7, 0.8, 12.0, 4)
		if q != null:
			_add_crawler(&"lobster", q)
	for g in _rng.randi_range(2, 4) + int(rich):
		var q: Variant = _spot(cc, 0.0, r, 0.8, 12.0, 4)
		if q != null:
			_reef_group(_weighted(REEF_GROUPS), q)
	if _rng.randf() < 0.85:
		_reef_group(SWARMS[_rng.randi() % SWARMS.size()], p)

func _clowns(a: Vector3) -> void:
	anemones.append(a)
	if anemones.size() > 200:
		anemones.remove_at(0)
	var n := _rng.randi_range(2, 4)
	var hs := PackedVector3Array()
	for i in n:
		hs.append(a + Vector3(_rng.randf_range(-0.15, 0.15), 0.28 + _rng.randf() * 0.15, _rng.randf_range(-0.15, 0.15)))
	_add_school(&"clownfish", a + Vector3(0, 0.3, 0), hs, a.y)

## Точка на дне в круге/кольце с подходящей глубиной.
func _spot(c: Vector2, r_in: float, r_out: float, dmin: float, dmax: float, tries: int = 12) -> Variant:
	for k in tries:
		var a := _rng.randf() * TAU
		var r := sqrt(_rng.randf_range(r_in * r_in / maxf(r_out * r_out, 0.01), 1.0)) * r_out
		var x := c.x + cos(a) * r
		var z := c.y + sin(a) * r
		var f := _floor(x, z)
		var d := level - f
		if d >= dmin and d <= dmax:
			return Vector3(x, f, z)
	return null

func _weighted(w: Dictionary) -> StringName:
	var tot := 0.0
	for k: StringName in w:
		tot += float(w[k])
	var r := _rng.randf() * tot
	for k: StringName in w:
		r -= float(w[k])
		if r <= 0.0:
			return k
	return w.keys()[0]

## Группа у дна: дома рыб — у точки, на 0.4–2 м над дном.
func _reef_group(sp: StringName, p: Vector3) -> void:
	var d: Dictionary = ReefSpecies.FISH[sp]
	var n := _rng.randi_range(d["n"][0], d["n"][1])
	n = maxi(1, int(n * clampf(density, 0.3, 1.5)))
	var spread := 1.0 + n * 0.05
	var swarm := SWARMS.has(sp)
	var hs := PackedVector3Array()
	var fmin := p.y
	for i in n:
		var x := p.x + _rng.randf_range(-spread, spread)
		var z := p.z + _rng.randf_range(-spread, spread)
		var f := _floor(x, z)
		fmin = maxf(fmin, f) if i < 4 else fmin
		var hy := (0.6 + _rng.randf() * 1.6) if swarm else (0.35 + _rng.randf() * 1.1)
		if sp == &"grouper" or sp == &"parrotfish":
			hy = 0.3 + _rng.randf() * 0.5
		hs.append(Vector3(x, minf(f + hy, level - 0.5), z))
	_add_school(sp, p, hs, fmin)

## Стая в толще воды.
func _open_school(sp: StringName, p: Vector3) -> ReefSchool:
	var d: Dictionary = ReefSpecies.FISH[sp]
	var n := int(_rng.randi_range(d["n"][0], d["n"][1]) * clampf(density, 0.3, 1.5))
	var rad: float = d.get("radius", 2.0)
	var roam: Array = d["roam"]
	# дно под маршрутом — самое высокое из проб
	var fmax := -1000.0
	for k in 9:
		var a := TAU * k / 9.0
		fmax = maxf(fmax, _floor(p.x + cos(a) * float(roam[0]), p.z + sin(a) * float(roam[2])))
	fmax = maxf(fmax, _floor(p.x, p.z))
	var mid := clampf((fmax + level) * 0.5, fmax + 0.8, level - 0.8)
	var hs := PackedVector3Array()
	for i in n:
		var o := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.4, 0.4), _rng.randf_range(-1, 1))
		if o.length() > 1.0:
			o = o.normalized() * _rng.randf()
		hs.append(Vector3(p.x, mid, p.z) + o * Vector3(rad * 1.6, rad * 0.45, rad))
	return _add_school(sp, Vector3(p.x, mid, p.z), hs, fmax)

func _add_school(sp: StringName, at: Vector3, hs: PackedVector3Array, floor_min: float) -> ReefSchool:
	var s := ReefSchool.new()
	s.name = "%s_%d" % [sp, schools.size()]
	s.setup(sp, at, hs, _rng, floor_min)
	if _cur:
		_cur.add_child(s)
		(_cell_schools[_cur_key] as Array).append(s)
	else:
		add_child(s)
	schools.append(s)
	fish_count += hs.size()
	var key := Vector2i(floori(at.x / CELL), floori(at.z / CELL))
	if not _grid.has(key):
		_grid[key] = []
	(_grid[key] as Array).append(s)
	return s

# ---------------- декор и ходоки (MultiMesh в ячейках) ----------------

func _add_decor(t: StringName, p: Vector3) -> void:
	var d: Dictionary = DECOR[t]
	var key := String(t)
	if not _decor.has(key):
		_decor[key] = {"xf": [], "col": []}
	var s := _rng.randf_range(d["s"][0], d["s"][1])
	var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s)
	if t == &"brown_algae" or t == &"seagrass":
		b = b.scaled(Vector3(1.0, _rng.randf_range(0.8, 1.3), 1.0))
	var tints: Array = d["tints"]
	var tint: Color = tints[_rng.randi() % tints.size()]
	tint = tint * _rng.randf_range(0.85, 1.12)
	tint.a = _rng.randf()
	var sink := 0.03 + (0.3 * s if t == &"reef_rock" else 0.0)
	(_decor[key]["xf"] as Array).append(Transform3D(b, p - Vector3(0, sink, 0)))
	(_decor[key]["col"] as Array).append(tint)
	decor_count += 1

func _decor_material(t: StringName) -> ShaderMaterial:
	if not _mats.has(t):
		var d: Dictionary = DECOR[t]
		var m: ShaderMaterial = SeaMeshes.coral_material(float(d["sway"]), level, 0.7)
		_mats[t] = m
	return _mats[t]

func _decor_mesh(t: StringName) -> ArrayMesh:
	match t:
		&"seagrass": return ReefMeshes.seagrass()
		&"soft_coral": return ReefMeshes.soft_coral()
		&"sea_whip": return ReefMeshes.sea_whip()
		&"tube_sponge": return ReefMeshes.tube_sponge()
		&"barrel_sponge": return ReefMeshes.barrel_sponge()
		&"anemone": return ReefMeshes.anemone()
		&"clam": return ReefMeshes.clam()
		&"starfish": return ReefMeshes.starfish()
		&"urchin": return ReefMeshes.urchin()
		&"cucumber": return ReefMeshes.cucumber()
		&"algae_bush": return ReefMeshes.algae_bush()
		&"coral_branch": return SeaMeshes.coral_branch(0)
		&"coral_brain": return SeaMeshes.coral_brain(0)
		&"coral_table": return SeaMeshes.coral_table(0)
		&"coral_fan": return SeaMeshes.coral_fan()
		&"sponge": return SeaMeshes.sponge()
		&"reef_rock": return SeaMeshes.reef_rock(0)
		_: return ReefMeshes.brown_algae()

func _flush_decor() -> void:
	for key: String in _decor:
		var t := StringName(key)
		var e: Dictionary = _decor[key]
		var xf: Array = e["xf"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.use_colors = true
		mm.mesh = _decor_mesh(t)
		mm.instance_count = xf.size()
		for i in xf.size():
			mm.set_instance_transform(i, xf[i])
			mm.set_instance_custom_data(i, e["col"][i])
			mm.set_instance_color(i, Color(1, 1, 1, 1))
		var mi := MultiMeshInstance3D.new()
		mi.name = "D_" + key
		mi.multimesh = mm
		mi.material_override = _decor_material(t)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = float(DECOR[t]["end"])
		mi.visibility_range_end_margin = 5.0
		(_cur if _cur else self).add_child(mi)
	_decor.clear()

func _add_crawler(t: StringName, p: Vector3) -> void:
	var key := String(t)
	if not _crawl.has(key):
		_crawl[key] = {"xf": [], "col": []}
	var L := _rng.randf_range(0.6, 1.8) if t == &"crab" else _rng.randf_range(0.3, 0.9)
	var yaw := _rng.randf() * TAU
	var b := Basis(Vector3.UP, yaw)
	# дно по направлению хода — наклон по двум концам пути
	var ax := b.x if t == &"crab" else b.z
	var p0 := p - ax * L * 0.5
	var p1 := p + ax * L * 0.5
	var y0 := _floor(p0.x, p0.z)
	var y1 := _floor(p1.x, p1.z)
	if absf(y1 - y0) > L * 0.6:
		return
	var tilt := atan2(y1 - y0, L)
	var axis_side := b.z if t == &"crab" else b.x
	b = Basis(axis_side, -tilt if t == &"crab" else tilt) * b
	var s := _rng.randf_range(0.8, 1.5) if t == &"crab" else _rng.randf_range(0.8, 1.3)
	b = b.scaled(Vector3.ONE * s)
	var mid := Vector3(p.x, (y0 + y1) * 0.5, p.z)
	(_crawl[key]["xf"] as Array).append(Transform3D(b, mid))
	(_crawl[key]["col"] as Array).append(Color(_rng.randf(), L, _rng.randf_range(0.12, 0.3) if t == &"crab" else _rng.randf_range(0.04, 0.09), _rng.randf()))
	crawler_count += 1

const CRAWLER_SHADER := preload("res://scripts/sea/shaders/crawler.gdshader")

func _crawler_material(t: StringName) -> ShaderMaterial:
	if not _crawl_mats.has(t):
		var m := ShaderMaterial.new()
		m.shader = CRAWLER_SHADER
		if t == &"crab":
			m.set_shader_parameter(&"axis", Vector3(1, 0, 0))
			m.set_shader_parameter(&"tint_a", Color(1.0, 0.95, 0.9))
			m.set_shader_parameter(&"tint_b", Color(0.75, 0.85, 0.7))
		else:
			m.set_shader_parameter(&"axis", Vector3(0, 0, 1))
			m.set_shader_parameter(&"tint_a", Color(1.0, 1.0, 1.0))
			m.set_shader_parameter(&"tint_b", Color(0.75, 0.6, 1.0))
			m.set_shader_parameter(&"antenna_sway", 0.06)
		_crawl_mats[t] = m
	return _crawl_mats[t]

func _flush_crawlers() -> void:
	for key: String in _crawl:
		var t := StringName(key)
		var e: Dictionary = _crawl[key]
		var xf: Array = e["xf"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.use_colors = true
		mm.mesh = ReefMeshes.crab() if t == &"crab" else ReefMeshes.lobster()
		mm.instance_count = xf.size()
		for i in xf.size():
			mm.set_instance_transform(i, xf[i])
			mm.set_instance_custom_data(i, e["col"][i])
			mm.set_instance_color(i, Color(1, 1, 1, 1))
		var mi := MultiMeshInstance3D.new()
		mi.name = "C_" + key
		mi.multimesh = mm
		mi.material_override = _crawler_material(t)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 32.0
		mi.visibility_range_end_margin = 4.0
		mi.extra_cull_margin = 2.0
		(_cur if _cur else self).add_child(mi)
	_crawl.clear()

# =============================== жизнь ===============================

func _process(delta: float) -> void:
	time += delta
	if sea:
		level = float(sea.call(&"water_y"))
	var cam0 := get_viewport().get_camera_3d()
	if cam0 and sea:
		_stream(cam0.global_position)
	RenderingServer.global_shader_parameter_set(&"sea_time", time)
	RenderingServer.global_shader_parameter_set(&"sea_level", level)
	_scare_acc += delta
	if _scare_acc >= SCARE_STEP:
		_scare_acc = 0.0
		_scare_near_threats()

## Группы в радиусе r от точки (по сетке).
func schools_near(p: Vector3, r: float) -> Array[ReefSchool]:
	var out: Array[ReefSchool] = []
	var c0 := Vector2i(floori((p.x - r) / CELL), floori((p.z - r) / CELL))
	var c1 := Vector2i(floori((p.x + r) / CELL), floori((p.z + r) / CELL))
	for cx in range(c0.x - 1, c1.x + 2):
		for cz in range(c0.y - 1, c1.y + 2):
			var arr: Variant = _grid.get(Vector2i(cx, cz))
			if arr == null:
				continue
			for s: ReefSchool in arr:
				if is_instance_valid(s) and s.center.distance_to(p) < r + s.radius + s.roam.x:
					out.append(s)
	return out

## Пловцы и акулы рядом с группой — она разлетается (только около камеры).
func _scare_near_threats() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	var near := schools_near(cp, 60.0)
	if near.is_empty():
		return
	var threats: Array[Vector3] = []
	for ch in get_tree().get_nodes_in_group(&"characters"):
		var n := ch as Node3D
		if n == null or not n.has_method(&"is_in_water"):
			continue
		if n.global_position.distance_to(cp) < 70.0 and bool(n.call(&"is_in_water")):
			threats.append(n.global_position)
	if sea:
		for s: Node3D in sea.call(&"sharks_near", cp, 70.0):
			threats.append(s.global_position)
	if scenes:
		threats.append_array(scenes.call(&"predator_positions"))
	for s in near:
		s.tick()
		if s.is_scared():
			continue
		var c := s.current_center()
		for t in threats:
			var r := 3.5 + s.radius * 0.6 + (2.0 if s.mode == 0 else 0.0)
			if t.distance_to(c) < r:
				s.scare(t)
				break

## Внешний испуг (всплеск, взрыв, выстрел).
func scare_at(p: Vector3, r: float = 12.0) -> void:
	for s in schools_near(p, r):
		if s.current_center().distance_to(p) < r:
			s.scare(p)
