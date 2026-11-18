class_name SeaReefs
extends Node3D
## Коралловые рифы и подводные луга по всему архипелагу. Пятна рифа — по шуму, у
## атоллов и общих островов гуще, у болот нет (мутно). Каждый вид — MultiMesh в ячейках 32 м
## с двумя уровнями детализации (visibility range): вблизи подробные, дальше
## упрощённые, ещё дальше — ничего. API: zones() — пятна рифа для ботов/рыбалки.

const CELL := 32.0
const HI_END := 45.0
const LO_END := 130.0
const GRASS_END := 50.0

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

var sea: Node = null
var density: float = 1.0
var _zones: Array[Dictionary] = []
var _cells: Dictionary = {}     # "type|cx|cz" → {xf: Array[Transform3D], col: PackedColorArray}
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _gnoise := FastNoiseLite.new()
var instances: int = 0

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
	if sea == null:
		return
	for I in sea.call(&"islands"):
		_island(I)
	_emit()

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
		if reef > 0.56:
			t = _pick_type(depth)
			if t != &"":
				# в пятне рифа кораллы гуще — пара соседей
				for k in (2 if reef > 0.66 else 1):
					var ox := x + _rng.randf_range(-1.6, 1.6)
					var oz := z + _rng.randf_range(-1.6, 1.6)
					var fy2: float = sea.call(&"floor_at", ox, oz)
					var t2 := _pick_type(wy - fy2)
					if t2 != &"":
						_add(t2, Vector3(ox, fy2, oz))
				zc += Vector2(x, z)
				placed += 1
		elif g > 0.6 and depth < 4.5 and depth > 0.5:
			t = &"grass"
		elif _rng.randf() < 0.04:
			t = &"rock"
		if t != &"":
			_add(t, Vector3(x, fy, z))
	if placed > 6:
		_zones.append({"center": zc / placed, "island": int(I.get("id", 0)), "kind": kind, "radius": outer, "corals": placed})

func _pick_type(depth: float) -> StringName:
	var total := 0.0
	var opts: Array = []
	for k in TYPES.keys():
		var d: Dictionary = TYPES[k]
		if float(d["w"]) <= 0.0 or depth < float(d["dmin"]) or depth > float(d["dmax"]):
			continue
		total += float(d["w"])
		opts.append(k)
	if opts.is_empty():
		return &""
	var x := _rng.randf() * total
	for k in opts:
		x -= float(TYPES[k]["w"])
		if x <= 0.0:
			return k
	return opts[-1]

func _add(t: StringName, p: Vector3) -> void:
	var d: Dictionary = TYPES[t]
	var key := "%s|%d|%d" % [t, int(floor(p.x / CELL)), int(floor(p.z / CELL))]
	if not _cells.has(key):
		_cells[key] = {"xf": [], "col": PackedColorArray()}
	var s := _rng.randf_range(float(d["smin"]), float(d["smax"]))
	var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s)
	if t == &"branch" or t == &"brain" or t == &"rock":
		# чуть наклонить по склону
		b = Basis(Vector3(1, 0, 0), _rng.randf_range(-0.12, 0.12)) * b
	var sink := 0.05 * s if t != &"rock" else 0.12 * s
	(_cells[key]["xf"] as Array).append(Transform3D(b, p - Vector3(0, sink, 0)))
	var tints: Array = d["tints"]
	var tc: Color = tints[_rng.randi() % tints.size()]
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
		var d: Dictionary = TYPES[t]
		var xf: Array = _cells[key]["xf"]
		var col: PackedColorArray = _cells[key]["col"]
		instances += xf.size()
		var mat := SeaMeshes.coral_material(float(d["sway"]), wy, 0.9 if t == &"rock" else 0.78)
		var end_hi := GRASS_END if t == &"grass" else (LO_END if not bool(d["lo"]) else HI_END)
		if t == &"fan" or t == &"sponge":
			end_hi = 70.0
		_mm(t, 0, xf, col, mat, 0.0, end_hi, 1)
		if bool(d["lo"]):
			# дальний уровень: только крупные (каждый второй)
			_mm(t, 1, xf, col, mat, end_hi, LO_END, 2)

func _mm(t: StringName, lod: int, xf: Array, col: PackedColorArray, mat: Material, begin: float, end: float, step_n: int) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _mesh(t, lod)
	var cnt := int(ceil(xf.size() / float(step_n)))
	mm.instance_count = cnt
	var j := 0
	var center := Vector3.ZERO
	for i in range(0, xf.size(), step_n):
		var tr: Transform3D = xf[i]
		mm.set_instance_transform(j, tr)
		mm.set_instance_custom_data(j, col[i])
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
