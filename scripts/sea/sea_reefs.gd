class_name SeaReefs
extends Node3D
## Коралловые рифы и подводные луга по всему архипелагу. Пятна рифа — по шуму, у
## атоллов и общих островов гуще, у болот нет (мутно). Каждый вид — MultiMesh в ячейках 32 м
## с двумя уровнями детализации (visibility range): вблизи подробные, дальше
## упрощённые, ещё дальше — ничего. API: zones() — пятна рифа для ботов/рыбалки.

const CELL := 64.0
const HI_END := 70.0
const LO_END := 160.0
const GRASS_END := 60.0

## Насколько густой риф у острова по типу.
const KIND_DENSITY := {
	&"atoll": 1.0, &"shared": 0.8, &"wreck": 0.6, &"spring": 0.5, &"home": 0.35,
	&"rocky": 0.3, &"center": 0.25, &"swamp": 0.0,
}
## Виды: меш (hi/lo), качание, глубины, масштаб, оттенки.
const TYPES := {
	&"branch": {"sway": 0.0, "dmin": 0.8, "dmax": 7.0, "smin": 0.5, "smax": 1.3, "w": 3.0, "lo": true,
		"tints": [Color(0.86, 0.76, 0.6), Color(0.72, 0.58, 0.82), Color(0.58, 0.72, 0.86), Color(0.62, 0.72, 0.46), Color(0.95, 0.62, 0.66)]},
	&"brain": {"sway": 0.0, "dmin": 0.9, "dmax": 8.0, "smin": 0.5, "smax": 1.6, "w": 2.0, "lo": true,
		"tints": [Color(0.78, 0.72, 0.46), Color(0.56, 0.66, 0.46), Color(0.82, 0.62, 0.46), Color(0.7, 0.68, 0.6)]},
	&"table": {"sway": 0.0, "dmin": 1.8, "dmax": 8.0, "smin": 0.8, "smax": 2.2, "w": 1.0, "lo": true,
		"tints": [Color(0.72, 0.77, 0.6), Color(0.86, 0.8, 0.66), Color(0.62, 0.68, 0.82)]},
	&"fan": {"sway": 0.06, "dmin": 2.5, "dmax": 10.0, "smin": 0.6, "smax": 1.5, "w": 1.2, "lo": false,
		"tints": [Color(0.66, 0.3, 0.62), Color(0.86, 0.36, 0.22), Color(0.9, 0.74, 0.3), Color(0.55, 0.25, 0.4)]},
	&"sponge": {"sway": 0.0, "dmin": 2.5, "dmax": 10.0, "smin": 0.6, "smax": 1.6, "w": 1.0, "lo": false,
		"tints": [Color(0.92, 0.52, 0.2), Color(0.56, 0.3, 0.62), Color(0.9, 0.8, 0.32), Color(0.76, 0.26, 0.2)]},
	&"rock": {"sway": 0.0, "dmin": 0.6, "dmax": 12.0, "smin": 0.6, "smax": 2.4, "w": 1.6, "lo": true,
		"tints": [Color(0.46, 0.44, 0.4), Color(0.56, 0.46, 0.52), Color(0.5, 0.48, 0.42)]},
	&"grass": {"sway": 0.14, "dmin": 0.5, "dmax": 4.5, "smin": 0.35, "smax": 0.9, "w": 0.0, "lo": false,
		"tints": [Color(0.36, 0.52, 0.26), Color(0.42, 0.56, 0.3), Color(0.5, 0.56, 0.32)]},
}

## Кораллы по референсу пользователя (CoralPack, docs/CORALS_REF.md); false — старые процедурные.
static var use_pack_corals := true

var sea: Node = null
var density: float = 1.0
var _zones: Array[Dictionary] = []
var _cells: Dictionary = {}     # "type|cx|cz" → {xf: Array[Transform3D], col: PackedColorArray}
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _gnoise := FastNoiseLite.new()
var instances: int = 0
var _pack := false

func _ready() -> void:
	add_to_group(&"sea_reefs")

func zones() -> Array[Dictionary]:
	return _zones

func build() -> void:
	for c in get_children():
		c.queue_free()
	_cells.clear()
	_zones.clear()
	instances = 0
	_rng.seed = 4242
	_noise.seed = 913
	_noise.frequency = 0.035
	_noise.fractal_octaves = 3
	_gnoise.seed = 517
	_gnoise.frequency = 0.05
	_pack = use_pack_corals and CoralPack.available()
	if sea == null:
		return
	var w: Node = sea.get(&"world")
	var zm: ZoneMap = w.get(&"zones") if w else null
	if zm != null:
		_from_zones(zm)
	else:
		for I in sea.call(&"islands"):
			_island(I)
	_emit()

## Мир с картой зон: кораллы — только на барьерном и окаймляющих рифах (зоны
## reef_crest/flat/slope) и всегда ниже самого низкого отлива; пятнами (живые и
## пустые места); в лагунах — луга морской травы, у мангров — ничего.
const ZONE_CORAL := {ZoneMap.Z_REEF_CREST: 1.5, ZoneMap.Z_REEF_FLAT: 1.15, ZoneMap.Z_REEF_SLOPE: 0.9}
func _from_zones(zm: ZoneMap) -> void:
	var low := ZoneMap.LOW_TIDE
	var st := ZoneMap.STEP
	var patch := {}    # Vector2i(64 м) → [Σx, Σz, n, island]
	for j in zm.nz:
		for i in zm.nx:
			var k := j * zm.nx + i
			if zm.sea[k] != 1:
				continue
			var zt := int(zm.zone[k])
			var x0 := zm.origin.x + i * st
			var z0 := zm.origin.y + j * st
			if ZONE_CORAL.has(zt):
				var rf := float(zm.reef[k]) / 255.0
				var lively := _noise.get_noise_2d(x0, z0) * 0.5 + 0.5
				var tries := int(round(float(ZONE_CORAL[zt]) * density * rf * smoothstep(0.3, 0.7, lively) * 3.0))
				for t in tries:
					var x := x0 + _rng.randf_range(-st * 0.5, st * 0.5)
					var z := z0 + _rng.randf_range(-st * 0.5, st * 0.5)
					var fy: float = sea.call(&"floor_at", x, z)
					var dl := low - fy            # глубина при самом низком отливе
					if dl < 0.45:
						continue
					var ct := _pick_type(dl)
					if ct == &"":
						continue
					var hmax := float(_tdesc(ct)["smax"]) * 0.9
					if dl < hmax * 0.6 + 0.25:
						continue          # верх колонии не выходит из воды в отлив
					_add(ct, Vector3(x, fy, z))
					for kk in (4 if lively > 0.62 else 2):
						var ox := x + _rng.randf_range(-2.4, 2.4)
						var oz := z + _rng.randf_range(-2.4, 2.4)
						var fy2: float = sea.call(&"floor_at", ox, oz)
						var t2 := _pick_type(low - fy2)
						if t2 != &"" and low - fy2 > 0.6:
							_add(t2, Vector3(ox, fy2, oz))
					var pk := Vector2i(floori(x / 64.0), floori(z / 64.0))
					var pe: Array = patch.get(pk, [0.0, 0.0, 0])
					pe[0] += x
					pe[1] += z
					pe[2] += 1
					patch[pk] = pe
			elif zt == ZoneMap.Z_LAGOON or zt == ZoneMap.Z_SHALLOWS or zt == ZoneMap.Z_REEF_FLAT:
				var g := _gnoise.get_noise_2d(x0, z0) * 0.5 + 0.5
				if g > 0.55 and _rng.randf() < 0.6:
					for kk in 4:
						var gx := x0 + _rng.randf_range(-st * 0.5, st * 0.5)
						var gz := z0 + _rng.randf_range(-st * 0.5, st * 0.5)
						var gy: float = sea.call(&"floor_at", gx, gz)
						if low - gy > 0.5 and low - gy < 6.0:
							_add(&"grass", Vector3(gx, gy, gz))
				elif _rng.randf() < 0.02:
					var ry: float = sea.call(&"floor_at", x0, z0)
					if low - ry > 1.0:
						_add(&"rock", Vector3(x0, ry, z0))
	for pk: Vector2i in patch:
		var pe: Array = patch[pk]
		if int(pe[2]) >= 6:
			var cc := Vector2(float(pe[0]) / pe[2], float(pe[1]) / pe[2])
			var ia: Dictionary = sea.get(&"world").call(&"island_at", cc.x, cc.y) if sea.get(&"world") else {}
			_zones.append({"center": cc, "island": int(ia.get("id", -1)), "kind": StringName(ia.get("kind", &"reef")),
				"radius": 40.0, "corals": int(pe[2])})

func _island(I: Dictionary) -> void:
	var kind: StringName = StringName(I.get("kind", &"home"))
	var dens: float = float(KIND_DENSITY.get(kind, 0.3)) * density
	if dens <= 0.0:
		return
	var c: Vector2 = I["center"]
	var r: float = I["radius"]
	var inner := 0.0 if kind == &"atoll" else r * 0.7
	var outer := r * 1.5 + 12.0
	var area := PI * (outer * outer - inner * inner)
	var n := int(area / 22.0 * dens)
	var wy: float = sea.call(&"water_y")
	var placed := 0
	var zc := Vector2.ZERO
	for i in n:
		var a := _rng.randf() * TAU
		var rr := sqrt(_rng.randf_range(inner * inner, outer * outer))
		var x := c.x + cos(a) * rr
		var z := c.y + sin(a) * rr
		var fy: float = sea.call(&"floor_at", x, z)
		var depth := wy - fy
		if depth < 0.5 or depth > 12.0:
			continue
		var reef := _noise.get_noise_2d(x, z) * 0.5 + 0.5
		var g := _gnoise.get_noise_2d(x, z) * 0.5 + 0.5
		var t: StringName = &""
		if reef > 0.52:
			t = _pick_type(depth)
			if t != &"":
				# в пятне рифа кораллы гуще — куст соседей
				for k in (5 if reef > 0.66 else 3):
					var ox := x + _rng.randf_range(-2.4, 2.4)
					var oz := z + _rng.randf_range(-2.4, 2.4)
					var fy2: float = sea.call(&"floor_at", ox, oz)
					var t2 := _pick_type(wy - fy2)
					if t2 != &"":
						_add(t2, Vector3(ox, fy2, oz))
				zc += Vector2(x, z)
				placed += 1
		elif g > 0.58 and depth < 4.5 and depth > 0.5:
			t = &"grass"
			for k in 3:
				var gx := x + _rng.randf_range(-1.5, 1.5)
				var gz := z + _rng.randf_range(-1.5, 1.5)
				var gy: float = sea.call(&"floor_at", gx, gz)
				if wy - gy > 0.5:
					_add(&"grass", Vector3(gx, gy, gz))
		elif _rng.randf() < 0.04:
			t = &"rock"
		if t != &"":
			_add(t, Vector3(x, fy, z))
	if placed > 6:
		_zones.append({"center": zc / placed, "island": int(I.get("id", 0)), "kind": kind, "radius": outer, "corals": placed})

## Описание вида: кораллы пака или старые TYPES (камни и трава — всегда старые).
func _tdesc(t: StringName) -> Dictionary:
	if _pack and CoralPack.TYPES.has(t):
		return CoralPack.TYPES[t]
	return TYPES[t]

func _pick_type(depth: float) -> StringName:
	var total := 0.0
	var opts: Array = []
	var keys: Array = TYPES.keys()
	if _pack:
		keys = CoralPack.TYPES.keys() + [&"rock"]
	for k in keys:
		var d: Dictionary = _tdesc(k)
		if float(d["w"]) <= 0.0 or depth < float(d["dmin"]) or depth > float(d["dmax"]):
			continue
		total += float(d["w"])
		opts.append(k)
	if opts.is_empty():
		return &""
	var x := _rng.randf() * total
	for k in opts:
		x -= float(_tdesc(k)["w"])
		if x <= 0.0:
			return k
	return opts[-1]

func _add(t: StringName, p: Vector3) -> void:
	var d: Dictionary = _tdesc(t)
	var cx := int(floor(p.x / CELL))
	var cz := int(floor(p.z / CELL))
	var key := "%s|%d|%d" % [t, cx, cz]
	if _pack and CoralPack.TYPES.has(t):
		# вариант формы — один на ячейку (один MultiMesh на вид и ячейку → вызовов отрисовки не больше)
		var v := absi(hash(Vector3i(cx, cz, String(t).hash()))) % CoralPack.variants(t)
		key = "%s|%d|%d|%d" % [t, cx, cz, v]
	if not _cells.has(key):
		_cells[key] = {"xf": [], "col": PackedColorArray()}
	var s := _rng.randf_range(float(d["smin"]), float(d["smax"]))
	var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s)
	if t == &"branch" or t == &"brain" or t == &"rock" or t == &"corymbose" or t == &"lobed" or t == &"mound":
		# чуть наклонить по склону
		b = Basis(Vector3(1, 0, 0), _rng.randf_range(-0.12, 0.12)) * b
	var sink := 0.05 * s if t != &"rock" else 0.12 * s
	(_cells[key]["xf"] as Array).append(Transform3D(b, p - Vector3(0, sink, 0)))
	var tc: Color
	if _pack and CoralPack.TYPES.has(t):
		tc = CoralPack.pick_tint(t, _rng)
	else:
		var tints: Array = d["tints"]
		tc = tints[_rng.randi() % tints.size()]
		tc = tc.lightened(_rng.randf_range(-0.08, 0.1))
		tc.a = _rng.randf()
	var cols: PackedColorArray = _cells[key]["col"]
	cols.append(tc)
	_cells[key]["col"] = cols

func _mesh(t: StringName, lod: int) -> Mesh:
	match t:
		&"branch": return SeaMeshes.coral_branch(lod)
		&"brain": return SeaMeshes.coral_brain(lod)
		&"table": return SeaMeshes.coral_table(lod)
		&"fan": return SeaMeshes.coral_fan()
		&"sponge": return SeaMeshes.sponge()
		&"rock": return SeaMeshes.reef_rock(lod)
		&"grass": return SeaMeshes.grass_clump(9 if lod == 0 else 4)
	return null

func _emit() -> void:
	var wy: float = sea.call(&"water_y")
	for key in _cells.keys():
		var parts: PackedStringArray = (key as String).split("|")
		var t := StringName(parts[0])
		var xf: Array = _cells[key]["xf"]
		var col: PackedColorArray = _cells[key]["col"]
		instances += xf.size()
		if parts.size() == 4:
			_emit_pack(t, int(parts[3]), xf, col, wy)
			continue
		var d: Dictionary = TYPES[t]
		var mat := SeaMeshes.coral_material(float(d["sway"]), wy, 0.9 if t == &"rock" else 0.78)
		var end_hi := GRASS_END if t == &"grass" else (LO_END if not bool(d["lo"]) else HI_END)
		if t == &"fan" or t == &"sponge":
			end_hi = 100.0
		_mm(t, 0, xf, col, mat, 0.0, end_hi, 1)
		if bool(d["lo"]):
			# дальний уровень: только крупные (каждый второй)
			_mm(t, 1, xf, col, mat, end_hi, LO_END, 2)

## Кораллы пака — цепочка уровней по расстоянию КАЖДОГО экземпляра (полоса в шейдере, края —
## дизеринг; вне полосы вершины схлопываются), MultiMesh собираются в под-ячейки, чтобы далёкие
## под-ячейки ближних уровней вообще не рисовались (visibility range по центру под-ячейки):
##   твёрдые (есть импостор): LOD0 0..9 м (ячейки 16 м) → LOD1 9..28 м (32 м) → импостор 28..160 м (64 м);
##   мягкие (щупальца, без импосторов): LOD0 0..12 м (32 м) → LOD1 12..30 м, каждый 2-й (64 м).
const PACK_HARD_L0 := 9.0
const PACK_HARD_L1 := 28.0
const PACK_SOFT_L0 := 12.0
const PACK_SOFT_L1 := 30.0
const PACK_FADE := 1.5
## Старые константы (на случай отсутствия импосторов).
const PACK_LOD0_END := 22.0
const PACK_LOD1_END := 65.0
const PACK_BIG := [&"table", &"staghorn", &"corymbose", &"lobed", &"mound", &"foliose"]

## Счётчики для тестов: экземпляры по уровням.
var pack_stats := {"lod0": 0, "lod1": 0, "lod2": 0, "imp": 0, "mm": 0}

func _emit_pack(t: StringName, v: int, xf: Array, col: PackedColorArray, wy: float) -> void:
	var m0 := CoralPack.mesh(t, v, 0)
	var m1 := CoralPack.mesh(t, v, 1)
	var m2 := CoralPack.mesh(t, v, 2)
	if m0 == null:
		return
	if CoralPack.has_impostor(t, v):
		_split(t, 0, xf, col, CoralPack.material_band(t, wy, 0, 0.0, PACK_HARD_L0), 16.0, PACK_HARD_L0 + PACK_FADE, 1, m0)
		if m1:
			_split(t, 1, xf, col, CoralPack.material_band(t, wy, 1, PACK_HARD_L0, PACK_HARD_L1), 32.0, PACK_HARD_L1 + PACK_FADE, 1, m1)
		_split(t, 3, xf, col, CoralPack.impostor_band(t, v, wy, PACK_HARD_L1, LO_END), CELL, LO_END + 3.0, 1, CoralPack.impostor_mesh(t, v))
		return
	if not (t in CoralPack.HARD):
		_split(t, 0, xf, col, CoralPack.material_band(t, wy, 0, 0.0, PACK_SOFT_L0), 32.0, PACK_SOFT_L0 + PACK_FADE, 1, m0)
		if m1:
			_split(t, 1, xf, col, CoralPack.material_band(t, wy, 1, PACK_SOFT_L0, PACK_SOFT_L1), 32.0, PACK_SOFT_L1 + PACK_FADE, 2, m1)
		return
	# твёрдый без импостора — прежняя схема
	var big := t in PACK_BIG
	_mm(t, 0, xf, col, CoralPack.material(t, wy, 0), 0.0, PACK_LOD0_END, 1, m0)
	if m1:
		_mm(t, 1, xf, col, CoralPack.material(t, wy, 1), PACK_LOD0_END, PACK_LOD1_END if big else 42.0, 2 if big else 3, m1)
	if big and m2:
		_mm(t, 2, xf, col, CoralPack.material(t, wy, 2), PACK_LOD1_END, LO_END, 4, m2)

## Разбить экземпляры ячейки на под-ячейки size м и выпустить по MultiMesh на каждую:
## visibility range под-ячейки = дальняя граница полосы + её полудиагональ (ближе неё экземпляры
## могут попасть в полосу), сама полоса отсекается в шейдере по каждому экземпляру.
func _split(t: StringName, lod: int, xf: Array, col: PackedColorArray, mat: Material, size: float, band_end: float, step_n: int, mesh: Mesh) -> void:
	if mat == null or mesh == null:
		return
	var groups := {}
	for i in range(0, xf.size(), step_n):
		var o: Vector3 = (xf[i] as Transform3D).origin
		var k := Vector2i(int(floor(o.x / size)), int(floor(o.z / size)))
		if not groups.has(k):
			groups[k] = [[], PackedColorArray()]
		(groups[k][0] as Array).append(xf[i])
		var pc: PackedColorArray = groups[k][1]
		pc.append(col[i])
		groups[k][1] = pc
	var half_diag := size * 0.7072
	for k in groups:
		var gx: Array = groups[k][0]
		var gc: PackedColorArray = groups[k][1]
		_mm(t, lod, gx, gc, mat, 0.0, band_end + half_diag, 1, mesh)
		pack_stats["mm"] = int(pack_stats["mm"]) + 1
		var key := "imp" if lod == 3 else "lod%d" % lod
		pack_stats[key] = int(pack_stats[key]) + gx.size()

func _mm(t: StringName, lod: int, xf: Array, col: PackedColorArray, mat: Material, begin: float, end: float, step_n: int, mesh_override: Mesh = null) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true   # без цветов экземпляров COLOR в шейдере обнуляется (gl_compatibility)
	mm.mesh = mesh_override if mesh_override else _mesh(t, lod)
	var cnt := int(ceil(xf.size() / float(step_n)))
	mm.instance_count = cnt
	var j := 0
	var center := Vector3.ZERO
	for i in range(0, xf.size(), step_n):
		var tr: Transform3D = xf[i]
		mm.set_instance_transform(j, tr)
		mm.set_instance_custom_data(j, col[i])
		mm.set_instance_color(j, Color(1, 1, 1, 1))
		center += tr.origin
		j += 1
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_begin = begin
	mi.visibility_range_end = end
	mi.visibility_range_end_margin = 6.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	mi.name = "%s_%d" % [t, lod]
	add_child(mi)
