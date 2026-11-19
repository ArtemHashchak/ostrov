class_name CoralPack
extends RefCounted
## Кораллы по референсу пользователя (docs/CORALS_REF.md): меши из assets/corals/corals.glb
## (генератор tools/model_gen/corals/gen.py — наша геометрия), материал coral_pack.gdshader.
## Используется рифами (SeaReefs при SeaReefs.use_pack_corals) и полигоном.
## Узлы в GLB: <тип>_v<вариант>_lod<0|1|2>. Карточки атласа (UV.x ≥ 4) — assets/corals/coral_cards.png.

const GLB := "res://assets/corals/corals.glb"
const SHADER := preload("res://scripts/sea/shaders/coral_pack.gdshader")
const CARDS := "res://assets/corals/coral_cards.png"
const IMP_SHADER := preload("res://scripts/sea/shaders/coral_impostor.gdshader")
const IMP_DIR := "res://assets/corals/impostors/"
const IMP_META := "res://assets/corals/impostors/impostor_meta.gd"
## Твёрдые кораллы без щупалец — у них есть импосторы («заранее снятые» снимки), см. bake_impostors.gd.
const HARD := [&"table", &"staghorn", &"corymbose", &"lobed", &"foliose", &"antler", &"mound", &"millepora"]

## Виды: варианты, вес, глубины, масштаб, оттенки (множитель к запечённому цвету), качание, узор.
const TYPES := {
	&"table": {"name": "Акропора столовая", "vars": 3, "w": 1.0, "dmin": 1.8, "dmax": 9.0, "smin": 0.55, "smax": 1.1,
		"tints": [Color(1, 1, 1), Color(1.0, 0.92, 0.86), Color(0.94, 0.98, 1.0), Color(1.05, 0.95, 0.8)], "sway": 0.0, "pattern": 0, "pscale": 70.0},
	&"staghorn": {"name": "Акропора кустовая", "vars": 2, "w": 1.6, "dmin": 0.8, "dmax": 7.0, "smin": 0.6, "smax": 1.2,
		"tints": [Color(1, 1, 1), Color(0.9, 0.82, 0.95), Color(1.05, 0.95, 0.88)], "sway": 0.0, "pattern": 0, "pscale": 110.0},
	&"corymbose": {"name": "Акропора пальчиковая", "vars": 2, "w": 2.2, "dmin": 0.8, "dmax": 7.5, "smin": 0.7, "smax": 1.5,
		"tints": [Color("#A6A060"), Color("#8C8A48"), Color("#B8A870"), Color("#C9A46A"), Color("#D48A60")], "sway": 0.0, "pattern": 0, "pscale": 120.0},
	&"lobed": {"name": "Лопастной", "vars": 4, "w": 1.4, "dmin": 0.9, "dmax": 8.0, "smin": 0.7, "smax": 1.6,
		"tints": [Color("#C84A4A"), Color("#D85A80"), Color("#8A58B8"), Color("#B8406A"), Color("#7448A0")], "sway": 0.0, "pattern": 1, "pscale": 60.0},
	&"foliose": {"name": "Листовой (розетка)", "vars": 2, "w": 0.8, "dmin": 1.5, "dmax": 9.0, "smin": 0.7, "smax": 1.4,
		"tints": [Color(1, 1, 1), Color(0.95, 1.0, 0.9)], "sway": 0.0, "pattern": 0, "pscale": 90.0},
	&"antler": {"name": "Акропора-деревце", "vars": 2, "w": 0.7, "dmin": 2.0, "dmax": 10.0, "smin": 0.9, "smax": 1.7,
		"tints": [Color(1, 1, 1), Color(0.95, 0.92, 1.0)], "sway": 0.0, "pattern": 0, "pscale": 100.0},
	&"softcoral": {"name": "Мягкий коралл", "vars": 2, "w": 0.7, "dmin": 2.0, "dmax": 11.0, "smin": 1.0, "smax": 1.8,
		"tints": [Color(1, 1, 1), Color(1.0, 0.92, 0.95)], "sway": 0.05, "pattern": 2, "pscale": 60.0},
	&"leather": {"name": "Кожистый с бахромой", "vars": 1, "w": 0.6, "dmin": 1.0, "dmax": 8.0, "smin": 0.7, "smax": 1.3,
		"tints": [Color(1, 1, 1), Color(0.95, 1.0, 0.92)], "sway": 0.06, "pattern": 2, "pscale": 80.0},
	&"anemone": {"name": "Актиния", "vars": 2, "w": 0.6, "dmin": 0.8, "dmax": 8.0, "smin": 0.8, "smax": 1.5,
		"tints": [Color(1, 1, 1), Color(1.0, 0.97, 0.9)], "sway": 0.1, "pattern": 2, "pscale": 60.0},
	&"bubble": {"name": "Пузырчатая актиния", "vars": 1, "w": 0.4, "dmin": 1.0, "dmax": 8.0, "smin": 0.8, "smax": 1.4,
		"tints": [Color(1, 1, 1), Color(1.0, 0.95, 0.85)], "sway": 0.06, "pattern": 2, "pscale": 60.0},
	&"crinoid": {"name": "Морская лилия", "vars": 2, "w": 0.4, "dmin": 1.5, "dmax": 11.0, "smin": 0.8, "smax": 1.4,
		"tints": [Color(1, 1, 1), Color(1.0, 0.9, 0.7), Color(0.95, 1.0, 0.85)], "sway": 0.08, "pattern": 2, "pscale": 60.0},
	&"millepora": {"name": "Огненный коралл", "vars": 2, "w": 0.6, "dmin": 0.8, "dmax": 8.0, "smin": 0.7, "smax": 1.4,
		"tints": [Color(1, 1, 1), Color(1.05, 0.98, 0.9)], "sway": 0.0, "pattern": 0, "pscale": 90.0},
	&"mound": {"name": "Корковый холмик", "vars": 2, "w": 1.0, "dmin": 0.6, "dmax": 10.0, "smin": 0.6, "smax": 1.8,
		"tints": [Color(1, 1, 1), Color(0.92, 0.95, 1.0), Color(1.05, 1.0, 0.9)], "sway": 0.0, "pattern": 1, "pscale": 50.0},
}

static var _meshes: Dictionary = {}     # "type_vN_lodK" → Mesh
static var _loaded := false
static var _mats: Dictionary = {}
static var _imp_meta: Dictionary = {}
static var _imp_meta_loaded := false
static var _imp_mesh: Dictionary = {}


static func available() -> bool:
	_load()
	return not _meshes.is_empty()


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if not ResourceLoader.exists(GLB):
		return
	var ps := load(GLB) as PackedScene
	if ps == null:
		return
	var root := ps.instantiate()
	_collect(root)
	root.free()


static func _collect(n: Node) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var nm := String(n.name)
		var mi := n as MeshInstance3D
		var m := mi.mesh
		# glTF: узел мог получить поворот/масштаб — запекаем в меш, если он не единичный
		if not mi.transform.is_equal_approx(Transform3D.IDENTITY):
			m = _baked(m, mi.transform)
		_meshes[nm] = m
	for c in n.get_children():
		_collect(c)


static func _baked(m: Mesh, xf: Transform3D) -> Mesh:
	var out := ArrayMesh.new()
	for s in m.get_surface_count():
		var st := SurfaceTool.new()
		st.create_from(m, s)
		var arr := st.commit_to_arrays()
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		for i in v.size():
			v[i] = xf * v[i]
		if nrm.size() == v.size():
			for i in nrm.size():
				nrm[i] = (xf.basis * nrm[i]).normalized()
			arr[Mesh.ARRAY_NORMAL] = nrm
		arr[Mesh.ARRAY_VERTEX] = v
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out


static func mesh(t: StringName, variant: int, lod: int) -> Mesh:
	_load()
	return _meshes.get("%s_v%d_lod%d" % [t, variant, lod])


static func variants(t: StringName) -> int:
	return int(TYPES.get(t, {}).get("vars", 1))


static func tri_count(m: Mesh) -> int:
	if m == null:
		return 0
	var n := 0
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		var idx = a[Mesh.ARRAY_INDEX]
		if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
			n += (idx as PackedInt32Array).size() / 3
		else:
			n += (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


## Материал вида (кэш по виду, уровню воды и детализации).
static func material(t: StringName, water_level: float, lod: int = 0) -> ShaderMaterial:
	var key := "%s|%.2f|%d" % [t, water_level, lod]
	if _mats.has(key):
		return _mats[key]
	var d: Dictionary = TYPES.get(t, {})
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter(&"water_level", water_level)
	var sw := float(d.get("sway", 0.0))
	m.set_shader_parameter(&"sway", sw if lod == 0 else (sw * 0.6 if lod == 1 else 0.0))
	m.set_shader_parameter(&"pattern", int(d.get("pattern", 0)))
	m.set_shader_parameter(&"pattern_scale", float(d.get("pscale", 90.0)))
	m.set_shader_parameter(&"detail", 1.0 if lod == 0 else 0.0)
	if ResourceLoader.exists(CARDS):
		m.set_shader_parameter(&"cards", load(CARDS))
	if sw > 0.0 and lod == 0:
		SeaPush.register(m)
	_mats[key] = m
	return m


## Оттенок экземпляра в INSTANCE_CUSTOM (rgb — множитель, a — фаза).
static func pick_tint(t: StringName, rng: RandomNumberGenerator) -> Color:
	var tints: Array = TYPES.get(t, {}).get("tints", [Color(1, 1, 1)])
	var c: Color = (tints[rng.randi() % tints.size()] as Color).srgb_to_linear()   # палитра задана в sRGB
	var k := rng.randf_range(0.9, 1.08)
	return Color(c.r * k, c.g * k, c.b * k, rng.randf())


## Импостор варианта: {"center", "radius", "frames"} или пустой словарь, если не запечён.
static func impostor_info(t: StringName, variant: int) -> Dictionary:
	if not _imp_meta_loaded:
		_imp_meta_loaded = true
		if ResourceLoader.exists(IMP_META):
			var sc := load(IMP_META) as Script
			if sc:
				_imp_meta = sc.get_script_constant_map().get("DATA", {})
	var key := "%s_v%d" % [t, variant]
	if not _imp_meta.has(key):
		return {}
	if not ResourceLoader.exists(IMP_DIR + key + "_albedo.png"):
		return {}
	return _imp_meta[key]


static func has_impostor(t: StringName, variant: int) -> bool:
	return t in HARD and not impostor_info(t, variant).is_empty()


## Квадрат 2×2 (вершины ±1); вершинный шейдер разворачивает его к камере вокруг центра сферы.
static func impostor_mesh(t: StringName, variant: int) -> Mesh:
	var key := "%s_v%d" % [t, variant]
	if _imp_mesh.has(key):
		return _imp_mesh[key]
	var info := impostor_info(t, variant)
	if info.is_empty():
		return null
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	var c: Vector3 = info["center"]
	var r: float = info["radius"]
	q.custom_aabb = AABB(c - Vector3.ONE * r, Vector3.ONE * r * 2.0)
	_imp_mesh[key] = q
	return q


static func impostor_material(t: StringName, variant: int, water_level: float) -> ShaderMaterial:
	var key := "imp|%s|%d|%.2f" % [t, variant, water_level]
	if _mats.has(key):
		return _mats[key]
	var info := impostor_info(t, variant)
	if info.is_empty():
		return null
	var base := IMP_DIR + "%s_v%d" % [t, variant]
	var m := ShaderMaterial.new()
	m.shader = IMP_SHADER
	m.set_shader_parameter(&"imp_albedo", load(base + "_albedo.png"))
	m.set_shader_parameter(&"imp_normal", load(base + "_normal.png"))
	m.set_shader_parameter(&"frames", float(info["frames"]))
	m.set_shader_parameter(&"imp_center", info["center"])
	m.set_shader_parameter(&"imp_radius", float(info["radius"]))
	m.set_shader_parameter(&"water_level", water_level)
	_mats[key] = m
	return m


## Материал с полосой расстояний экземпляра (lod_begin..lod_end, м): вне полосы экземпляр не рисуется,
## на краях растворяется дизерингом. Отдельная копия на каждую полосу.
static func material_band(t: StringName, water_level: float, lod: int, begin: float, end: float) -> ShaderMaterial:
	var key := "%s|%.2f|%d|%.1f|%.1f" % [t, water_level, lod, begin, end]
	if _mats.has(key):
		return _mats[key]
	var m := material(t, water_level, lod).duplicate() as ShaderMaterial
	m.set_shader_parameter(&"lod_begin", begin)
	m.set_shader_parameter(&"lod_end", end)
	if float(m.get_shader_parameter(&"sway")) > 0.0 and lod == 0:
		SeaPush.register(m)
	_mats[key] = m
	return m


static func impostor_band(t: StringName, variant: int, water_level: float, begin: float, end: float) -> ShaderMaterial:
	var key := "impb|%s|%d|%.2f|%.1f|%.1f" % [t, variant, water_level, begin, end]
	if _mats.has(key):
		return _mats[key]
	var base := impostor_material(t, variant, water_level)
	if base == null:
		return null
	var m := base.duplicate() as ShaderMaterial
	m.set_shader_parameter(&"lod_begin", begin)
	m.set_shader_parameter(&"lod_end", end)
	_mats[key] = m
	return m
