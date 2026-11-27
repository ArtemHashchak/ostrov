class_name FloraPack
extends RefCounted
## Растения из пака пользователя (MODELS/Tree, MODELS/Plants; импорт — tools/flora_pack_import.gd):
## кокосовая пальма v5, мангры v2, дерево с зонтичной кроной v5, растения джунглей A/B, кусты
## (иксора, куст с фиолетовыми цветами), папоротники, орхидеи, кокосы. Меши — assets/user_pack/flora/mesh
## (<id>_l1 — авторский LOD1, игровой ближний; <id>_l2 — авторский LOD2, дальний; в обоих запечены
## автоматические LOD движка). Материалы назначаются здесь по имени поверхности (= материал автора).
##
## Виды FLORA → модели пака: palm → пальма кокосовая (5), mangrove → мангры v2 (8),
## broadleaf → дерево с зонтичной кроной (5). Баньян пака не готов — остаётся процедурным.

const DIR := "res://assets/user_pack/flora/"
const TEX := DIR + "tex/"

## Порядок вариантов: вариант 0 — самый «типичный» (по нему рисуются дальние LOD всех деревьев вида).
const TREES := {
	&"palm": ["palm_03", "palm_02", "palm_01", "palm_04", "palm_05"],
	&"mangrove": ["mangrove_03", "mangrove_01", "mangrove_02", "mangrove_04", "mangrove_05", "mangrove_06", "mangrove_07", "mangrove_08"],
	&"broadleaf": ["umbrella_01", "umbrella_02", "umbrella_03", "umbrella_04", "umbrella_05"],
}

## Подлесок по биомам: вид (префикс id) → вес. В чанке 64 м берётся несколько видов (заросли пятнами).
const PALETTES := {
	&"jungle": {"alocasia_big": 3, "alocasia_young": 3, "alocasia_var": 2, "colocasia1": 2, "colocasia2": 2, "monstera": 3,
		"dieffenbachia": 2, "spathiphyllum": 2, "banana": 2, "palm_areca": 2, "palm_rhapis": 2, "palm_bush_stemless": 1,
		"palm_short_trunk": 1, "dracaena_branched": 1, "dracaena_fragrans": 2, "bamboo_small": 1, "sapling_umbrella": 2,
		"fern_asplenium": 2, "fern_nephrolepis": 2, "shrub_smallleaf": 1, "shrub_ixora": 1, "orchid_white": 1, "orchid_pink": 1},
	&"meadow": {"shrub_ixora": 3, "shrub_bluehibiscus": 3, "shrub_smallleaf": 3, "dracaena_fragrans": 1, "grass_curculigo": 2,
		"palm_bush_stemless": 1, "sapling_umbrella": 1, "fern_low": 1},
	&"beach": {"palm_bush_stemless": 3, "palm_short_trunk": 2, "grass_curculigo": 3, "shrub_smallleaf": 1},
	&"swamp": {"colocasia1": 3, "colocasia2": 3, "alocasia_big": 2, "spathiphyllum": 2, "fern_nephrolepis": 2, "banana": 1, "fern_sword": 2},
	&"rocky": {"shrub_smallleaf": 3, "grass_curculigo": 3, "fern_low": 1, "dracaena_fragrans": 1},
}
## Низкий покров (бывшие папоротники polyhaven): по биомам.
const GROUND := {
	&"jungle": ["fern_low_01", "fern_low_03", "fern_pinnate_small_01", "fern_pinnate_small_03", "fern_nest_02", "fern_sword_01", "fern_asplenium_02"],
	&"swamp": ["fern_nephrolepis_02", "fern_sword_02", "fern_low_02", "fern_nest_01"],
	&"meadow": ["fern_low_02", "fern_pinnate_small_02", "grass_curculigo_02", "grass_curculigo_01"],
}
const EPIPHYTES := ["orchid_white_05_epi", "orchid_pink_05_epi"]

static var enabled := true
static var _meta: Dictionary = {}
static var _loaded := false
static var _mats: Dictionary = {}
static var _meshes: Dictionary = {}
static var _variants: Dictionary = {}
static var _hulls: Dictionary = {}
static var _species: Dictionary = {}   # префикс → [id…]

static func available() -> bool:
	return enabled and not _load().is_empty()

static func _load() -> Dictionary:
	if not _loaded:
		_loaded = true
		var txt := FileAccess.get_file_as_string(DIR + "flora_pack.json")
		if txt != "":
			var d = JSON.parse_string(txt)
			if d is Dictionary:
				_meta = d
		for id in _meta:
			if String(_meta[id].get("group", "")) == "plant":
				var sp := _species_of(id)
				if not _species.has(sp):
					_species[sp] = []
				(_species[sp] as Array).append(id)
		for sp in _species:
			(_species[sp] as Array).sort()
	return _meta

static func _species_of(id: String) -> String:
	var parts := id.split("_")
	if parts.size() > 1 and parts[-1].is_valid_int():
		parts.remove_at(parts.size() - 1)
	elif parts.size() > 2 and parts[-1] == "epi":
		return "epi"
	return "_".join(parts)

static func info(id: String) -> Dictionary:
	return _load().get(id, {})

static func species(prefix: String) -> Array:
	_load()
	return _species.get(prefix, [])

static func has_tree(kind: StringName) -> bool:
	return available() and TREES.has(kind)

static func tree_id(kind: StringName, idx: int) -> String:
	var ids: Array = TREES[kind]
	return ids[posmod(idx, ids.size())]

static func tree_count(kind: StringName) -> int:
	return (TREES[kind] as Array).size()

# ---------------------------------------------------------------- меши и материалы

## Меш с материалами. lod: 1 — ближний (авторский LOD1), 2 — дальний (авторский LOD2).
static func mesh(id: String, lod: int = 1) -> ArrayMesh:
	var key := "%s_%d" % [id, lod]
	if _meshes.has(key):
		return _meshes[key]
	var path := DIR + "mesh/%s_l%d.res" % [id, clampi(lod, 1, 2)]
	var m: ArrayMesh = null
	if ResourceLoader.exists(path):
		m = (load(path) as ArrayMesh)
	if m == null:
		_meshes[key] = null
		return null
	m = m.duplicate() as ArrayMesh   # материалы назначаются копии: загруженный ресурс общий
	var grp := String(info(id).get("group", ""))
	for si in m.get_surface_count():
		m.surface_set_material(si, material(m.surface_get_name(si), grp))
	_meshes[key] = m
	return m

static func is_bark(surface_name: String) -> bool:
	return surface_name.to_lower().contains("bark")

## Материал по имени поверхности (материал автора): кора — pack_bark, остальное — pack_leaf.
static func material(surface_name: String, group: String = "plant") -> ShaderMaterial:
	var key := surface_name + "|" + group
	if _mats.has(key):
		return _mats[key]
	var tex := surface_name
	if group == "coconut" or surface_name.to_lower().contains("coconut"):
		tex = "Coconut"
	var bark := is_bark(surface_name)
	var m := ShaderMaterial.new()
	m.shader = load("res://scripts/world/flora/pack_bark.gdshader" if bark else "res://scripts/world/flora/pack_leaf.gdshader") as Shader
	m.set_shader_parameter(&"albedo_tex", _tex(tex + "_albedo"))
	m.set_shader_parameter(&"normal_tex", _tex(tex + "_normal"))
	m.set_shader_parameter(&"orm_tex", _tex(tex + "_orm"))
	match group:
		"tree":
			m.set_shader_parameter(&"wind_amp", 0.0 if bark else 0.09)
		"coconut":
			m.set_shader_parameter(&"wind_amp", 0.0)
			m.set_shader_parameter(&"translucency", 0.0)
		_:
			# кусты/травы: изгиб целиком слабее (низкие), листья колышутся заметнее
			m.set_shader_parameter(&"wind_amp", 0.05)
			m.set_shader_parameter(&"bend_k", 0.6)
			# касание игроком: куст отгибается целиком от основания (стебли вместе с листьями)
			m.set_shader_parameter(&"push_flex", 1.0)
	if surface_name.begins_with("Palm_Leaf"):
		m.set_shader_parameter(&"wind_amp", 0.14)
	_mats[key] = m
	return m

static func _tex(name: String) -> Texture2D:
	var p := TEX + name + ".png"
	return load(p) as Texture2D if ResourceLoader.exists(p) else null

## Кора пака как StandardMaterial3D — для процедурных частей ствола (зарубка, пень, брёвна).
static func bark_std(surface_name: String) -> StandardMaterial3D:
	var key := "std|" + surface_name
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex(surface_name + "_albedo")
	m.normal_enabled = true
	m.normal_texture = _tex(surface_name + "_normal")
	var orm := _tex(surface_name + "_orm")
	m.roughness_texture = orm
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.ao_enabled = true
	m.ao_texture = orm
	m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[key] = m
	return m

## Копии материалов меша для одного дерева: срез коры ниже bark_lo, всего выше hi и полоса коры
## hole (её рисует процедурная зарубка/срез).
static func clip(mi: MeshInstance3D, bark_lo: float = -1000.0, hi: float = 1000.0, hole := Vector2.ZERO) -> void:
	if mi == null or mi.mesh == null:
		return
	for si in mi.mesh.get_surface_count():
		var src := mi.mesh.surface_get_material(si) as ShaderMaterial
		if src == null:
			continue
		var m := mi.get_surface_override_material(si) as ShaderMaterial
		if m == null:
			m = src.duplicate() as ShaderMaterial
			mi.set_surface_override_material(si, m)
		var bark := is_bark(mi.mesh.surface_get_name(si))
		m.set_shader_parameter(&"clip_lo", bark_lo if bark else -1000.0)
		m.set_shader_parameter(&"clip_hi", hi)
		m.set_shader_parameter(&"hole", hole)

## Выпуклые коллайдеры автора (ствол; без корней мангров).
static func hulls(id: String) -> Array:
	if _hulls.has(id):
		return _hulls[id]
	var out: Array = []
	for flat in info(id).get("cols", []):
		var pts := PackedVector3Array()
		var a: Array = flat
		for i in range(0, a.size() - 2, 3):
			pts.append(Vector3(a[i], a[i + 1], a[i + 2]))
		if pts.size() >= 4:
			var sh := ConvexPolygonShape3D.new()
			sh.points = pts
			out.append(sh)
	_hulls[id] = out
	return out

# ---------------------------------------------------------------- деревья: вариант для FloraLib

## Вариант дерева в формате FloraLib (H — длина оси ствола до кроны; ось и радиус — по замерам
## импорта, trunk_point/trunk_radius берут их отсюда) + "pack" — id модели.
static func tree_variant(kind: StringName, idx: int) -> Dictionary:
	var key := "%s_%d" % [kind, idx]
	if _variants.has(key):
		return _variants[key]
	var id := tree_id(kind, idx)
	var inf := info(id)
	var v := {"kind": kind, "idx": idx, "pack": id}
	var axis := PackedVector3Array()
	for a in inf.get("axis", [[0, 0, 0], [0, 1, 0]]):
		axis.append(Vector3(a[0], a[1], a[2]))
	var rad := PackedFloat32Array()
	for r in inf.get("radius", [0.2]):
		rad.append(float(r))
	v["axis"] = axis
	v["radius"] = rad
	v["H"] = maxf(float(inf.get("H", 2.0)), 0.8)
	v["r0"] = rad[0] if rad.size() > 0 else 0.2
	v["lean"] = 0.0
	v["bend"] = 0.0
	v["crown_y"] = float(inf.get("crown_y", axis[-1].y))
	var la: Array = inf.get("leaf_aabb", inf.get("aabb", [0, 0, 0, 1, 1, 1]))
	v["crown_c"] = Vector3(la[0] + la[3] * 0.5, la[1] + la[4] * 0.5, la[2] + la[5] * 0.5)
	v["crown_r"] = maxf(la[3], la[5]) * 0.5
	var ab: Array = inf.get("aabb", la)
	v["height"] = float(ab[1]) + float(ab[4])
	v["bark"] = "pack:" + _bark_name(kind)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	if kind == &"palm":
		v["coconuts"] = rng.randi_range(3, 6)
	v["seed"] = rng.randi()
	_variants[key] = v
	return v

static func _bark_name(kind: StringName) -> String:
	match kind:
		&"palm":
			return "Palm_Bark"
		&"mangrove":
			return "Mangrove_Bark"
	return "Umbrella_Bark"

## Точка оси по длине дуги s (ось — шаг 0.4 м от основания).
static func axis_point(v: Dictionary, s: float) -> Vector3:
	var ax: PackedVector3Array = v["axis"]
	if ax.size() < 2:
		return Vector3(0, s, 0)
	var f := maxf(s, 0.0) / 0.4
	var i := int(floor(f))
	if i >= ax.size() - 1:
		var d := (ax[-1] - ax[-2]).normalized()
		return ax[-1] + d * (s - 0.4 * float(ax.size() - 1))
	return ax[i].lerp(ax[i + 1], f - float(i))

static func axis_radius(v: Dictionary, s: float) -> float:
	var rad: PackedFloat32Array = v["radius"]
	if rad.is_empty():
		return 0.2
	var f := clampf(s / 0.4, 0.0, float(rad.size() - 1))
	var i := int(floor(f))
	if i >= rad.size() - 1:
		return rad[-1]
	return lerpf(rad[i], rad[i + 1], f - float(i))

## Точки на макушке пальмы, где сидят кокосы: в пазухах листьев у основания черешков, плотной
## гроздью (как просит Задание_кокосы: без «палки»-соцветия; только зелёные).
static func coconut_spots(v: Dictionary, n: int, rng: RandomNumberGenerator) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var H: float = v["H"]
	var top := axis_point(v, H)
	var d := (top - axis_point(v, H - 0.8)).normalized()
	var side := d.cross(Vector3.UP)
	if side.length() < 0.1:
		side = Vector3.RIGHT
	side = side.normalized()
	var fwd := side.cross(d).normalized()
	var r := axis_radius(v, H - 0.4) + 0.12
	var a0 := rng.randf() * TAU
	for i in n:
		var a := a0 + TAU * float(i) / float(maxi(n, 1)) * 0.75 + rng.randf_range(-0.25, 0.25)
		var down := rng.randf_range(0.15, 0.45)
		out.append(top - d * down + (side * cos(a) + fwd * sin(a)) * r)
	return out

# ---------------------------------------------------------------- подлесок

## Растение для куста в чанке: в каждом чанке — 4–6 видов палитры биома (пятнами), вариант — случайный.
static func pick_plant(biome: StringName, chunk: Vector2i, rng: RandomNumberGenerator) -> String:
	var pal: Dictionary = PALETTES.get(biome, PALETTES[&"meadow"])
	var crng := RandomNumberGenerator.new()
	crng.seed = hash(Vector3i(chunk.x, chunk.y, hash(biome)))
	var names: Array = pal.keys()
	var chosen: Array = []
	var wsum := 0.0
	for nm in names:
		wsum += float(pal[nm])
	var want := mini(names.size(), crng.randi_range(4, 6))
	var guard := 0
	while chosen.size() < want and guard < 64:
		guard += 1
		var r := crng.randf() * wsum
		for nm in names:
			r -= float(pal[nm])
			if r <= 0.0:
				if not chosen.has(nm):
					chosen.append(nm)
				break
	# в чанке у вида — 1–2 варианта (меньше вызовов отрисовки)
	var sp: String = chosen[rng.randi_range(0, chosen.size() - 1)]
	var ids := species(sp)
	if ids.is_empty():
		return ""
	var nv := mini(ids.size(), 2)
	var off := crng.randi_range(0, ids.size() - 1)
	return ids[(off + rng.randi_range(0, nv - 1)) % ids.size()]

static func ground_ids(biome: StringName) -> Array:
	return GROUND.get(biome, GROUND[&"meadow"])
