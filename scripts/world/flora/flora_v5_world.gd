class_name FloraV5World
## v5.2 (агент O): новые растения пользователя (assets/user_pack/flora_v5) — в генерации мира.
## Раньше они были только на полигоне. Рассадка по карте зон (World.zone_at) пятнами (шум),
## дальше — общий путь подлеска Flora: MultiMesh по чанкам BUSH_CHUNK (ключи _bush «v5:id|cx|cz»
## — рубятся мачете, «v5t:id|cx|cz» — деревья/пальмы и перекинутые лианы, мачете не рубит),
## коллизии solid/soft — только у игрока (индекс Flora._pcol_index по каталогу).
## Лианы: свисающие/вьющиеся — на стволах деревьев джунглей, перекинутые — между соседними
## высокими деревьями (растянуты по расстоянию); при рубке дерева гаснут вместе с ним (tree.epi).
## Травы набора пользователя — в слое декора (Flora._gen_decor), см. grass_for().

const PREFIX := "v5:"
const PREFIX_T := "v5t:"

## Вероятность на точку сетки STEP по зоне: [id-группа, вес]. Группы раскрываются в ids.
const STEP := 5.0
const ZONE_W := {
	&"jungle": [["fern", 0.16], ["strelitzia", 0.035], ["howea", 0.03], ["kingsville", 0.008], ["wall", 0.0025]],
	&"lowland_forest": [["fern", 0.10], ["strelitzia", 0.04], ["howea", 0.045], ["kingsville", 0.035]],
	&"meadow": [["strelitzia", 0.05], ["fern", 0.05], ["howea", 0.03], ["kingsville", 0.03], ["macrozamia", 0.03]],
	&"palm_belt": [["strelitzia", 0.02], ["howea", 0.02], ["macrozamia", 0.025]],
	&"dunes": [["macrozamia", 0.012]],
	&"volcanic": [["macrozamia", 0.01]],
	&"rocks": [["macrozamia", 0.015], ["kingsville", 0.008], ["wall", 0.002]],
	&"mangrove": [["fern", 0.05]],
}
const GROUPS := {
	"fern": ["flora_matteuccia_a", "flora_matteuccia_b", "flora_matteuccia_c"],
	"strelitzia": ["flora_strelitzia"],
	"howea": ["flora_howea_1", "flora_howea_2"],
	"kingsville": ["flora_kingsville_1", "flora_kingsville_2", "flora_kingsville_3", "flora_kingsville_4", "flora_kingsville_5"],
	"macrozamia": ["flora_macrozamia_1", "flora_macrozamia_2"],
	"wall": ["flora_liana_wall"],
}
const HANG := ["flora_liana_hang_curtain_05", "flora_liana_hang_ivy_06", "flora_liana_climb_07", "flora_liana_climb_thorn_08", "flora_liana_kit_09"]
const SPAN := ["flora_liana_span_01", "flora_liana_span_braid_02", "flora_liana_span_thorn_03", "flora_liana_span_leafy_04"]
## Травы набора по биому Flora (_biome: meadow/beach/rocky/jungle).
const GRASS := {
	&"meadow": ["flora_gs_grass1", "flora_gs_grass3", "flora_gs_grass4", "flora_gs_grass_5", "flora_gs_grass_dry_01",
		"flora_gs_grass_wild_clump_dry_01", "flora_gs_clovers_01", "flora_gs_clovers_03", "flora_gs_daisies", "flora_gs_dandelion_01",
		"flora_gs_weed_02_001", "flora_gs_medium_001", "flora_grass_clump_razw"],
	&"beach": ["flora_gs_grass_dry_01", "flora_gs_grass2", "flora_gs_wasteland_gravel_01_001", "flora_gs_wasteland_gravel_02_001", "flora_grass_clump_razw"],
	&"rocky": ["flora_gs_wasteland_grass_medium_001", "flora_gs_wasteland_gravel_02_001", "flora_gs_grass_dry_01"],
	&"jungle": ["flora_gs_leaves_01", "flora_gs_wasteland_branches_01_001", "flora_gs_nettle_02", "flora_gs_grass3"],
}
## Дальность видимости по группе (м).
const RANGE := {"fern": 75.0, "strelitzia": 110.0, "howea": 170.0, "kingsville": 240.0, "macrozamia": 170.0, "wall": 90.0,
	"hang": 130.0, "span": 150.0, "grass": 38.0}

static var _mesh_cache: Dictionary = {}
static var _group_of: Dictionary = {}

static func available() -> bool:
	return AssetCatalog.has("flora_strelitzia")

static func group_of(id: String) -> String:
	if _group_of.is_empty():
		for g in GROUPS:
			for i in GROUPS[g]:
				_group_of[i] = g
		for i in HANG:
			_group_of[i] = "hang"
		for i in SPAN:
			_group_of[i] = "span"
	return String(_group_of.get(id, "grass"))

static func range_of(id: String) -> float:
	return float(RANGE.get(group_of(id), 60.0))

## Ключ подлеска: рубится ли мачете (папоротники, стрелиция, свисающие лианы) или нет.
static func key_prefix(id: String) -> String:
	match group_of(id):
		"howea", "kingsville", "macrozamia", "span":
			return PREFIX_T
	return PREFIX

static func is_key(part: String) -> bool:
	return part.begins_with(PREFIX) or part.begins_with(PREFIX_T)

static func id_of_key(part: String) -> String:
	return part.substr(PREFIX_T.length()) if part.begins_with(PREFIX_T) else part.substr(PREFIX.length())

## Один меш на вид (LOD1, если есть): все MeshInstance3D модели запекаются в общий ArrayMesh с
## материалами шейдера листвы v5 (FloraV5Mat) — для MultiMesh.
static func mesh(id: String) -> Mesh:
	if _mesh_cache.has(id):
		return _mesh_cache[id]
	var e := AssetCatalog.get_entry(id)
	var lod := 1 if not (e.get("lod", []) as Array).is_empty() else 0
	var root := AssetCatalog.instantiate(id, lod)
	if root == null and lod == 1:
		root = AssetCatalog.instantiate(id, 0)
	var out: ArrayMesh = null
	if root:
		out = ArrayMesh.new()
		var stack: Array = [[root, Transform3D.IDENTITY]]
		while not stack.is_empty():
			var it: Array = stack.pop_back()
			var nd: Node = it[0]
			var xf: Transform3D = it[1]
			if nd is Node3D and nd != root:
				xf = xf * (nd as Node3D).transform
			for ch in nd.get_children():
				stack.append([ch, xf])
			var mi := nd as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			for si in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(si)
				var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var nrm = arr[Mesh.ARRAY_NORMAL]
				var tan = arr[Mesh.ARRAY_TANGENT]
				if xf != Transform3D.IDENTITY:
					for k in verts.size():
						verts[k] = xf * verts[k]
					arr[Mesh.ARRAY_VERTEX] = verts
					if nrm is PackedVector3Array:
						var nb := xf.basis.inverse().transposed()
						for k in (nrm as PackedVector3Array).size():
							nrm[k] = (nb * nrm[k]).normalized()
						arr[Mesh.ARRAY_NORMAL] = nrm
					if tan is PackedFloat32Array and (tan as PackedFloat32Array).size() == verts.size() * 4:
						for k in verts.size():
							var t := (xf.basis * Vector3(tan[k * 4], tan[k * 4 + 1], tan[k * 4 + 2])).normalized()
							tan[k * 4] = t.x; tan[k * 4 + 1] = t.y; tan[k * 4 + 2] = t.z
						arr[Mesh.ARRAY_TANGENT] = tan
				arr[Mesh.ARRAY_BONES] = null
				arr[Mesh.ARRAY_WEIGHTS] = null
				out.add_surface_from_arrays(mi.mesh.surface_get_primitive_type(si), arr)
				var mat := mi.get_surface_override_material(si)
				if mat == null:
					mat = mi.mesh.surface_get_material(si)
				out.surface_set_material(out.get_surface_count() - 1, mat)
		root.free()
		if out.get_surface_count() == 0:
			out = null
	_mesh_cache[id] = out
	return out

## Трава набора для слоя декора: до 3 видов на чанк (меньше MultiMesh-вызовов).
static func grass_for(biome: StringName, chunk_rng: int) -> Array:
	var list: Array = GRASS.get(biome, [])
	if list.is_empty():
		return []
	var out: Array = []
	for k in 3:
		var id: String = list[posmod(chunk_rng + k * 7, list.size())]
		if not out.has(id) and AssetCatalog.has(id):
			out.append(id)
	return out

static func _pick(group: String, rng: RandomNumberGenerator) -> String:
	var ids: Array = GROUPS[group]
	return String(ids[rng.randi_range(0, ids.size() - 1)])

static func _put(flora, id: String, xf: Transform3D) -> Array:
	var bc := Vector2i(int(floor(xf.origin.x / flora.BUSH_CHUNK)), int(floor(xf.origin.z / flora.BUSH_CHUNK)))
	var key := "%s%s|%d|%d" % [key_prefix(id), id, bc.x, bc.y]
	if not flora._bush.has(key):
		flora._bush[key] = []
	var arr: Array = flora._bush[key]
	arr.append(xf)
	flora.stats["v5_" + group_of(id)] = int(flora.stats.get("v5_" + group_of(id), 0)) + 1
	return [key, arr.size() - 1]

## Рассадка по островам (после основной рассадки Flora, до _build_bushes).
static func populate(flora) -> void:
	if not available() or flora.world == null or not flora.world.has_method(&"zone_at"):
		return
	var w = flora.world
	var noise := FastNoiseLite.new()
	noise.seed = int(flora.seed) + 717
	noise.frequency = 0.045
	var rng := RandomNumberGenerator.new()
	var seen: Dictionary = {}
	for I in flora._island_list:
		var c: Vector2 = I["center"]
		var R: float = float(I["radius"]) * 1.3 + 8.0
		for j in range(int(floor((c.y - R) / STEP)), int(ceil((c.y + R) / STEP))):
			for i in range(int(floor((c.x - R) / STEP)), int(ceil((c.x + R) / STEP))):
				var key := Vector2i(i, j)
				if seen.has(key):
					continue
				seen[key] = true
				rng.seed = hash(Vector3i(i, j, int(flora.seed) + 909))
				var x := (i + rng.randf()) * STEP
				var z := (j + rng.randf()) * STEP
				var h: float = flora._h(x, z)
				if h <= flora._land_min + 0.1:
					continue
				var zn: StringName = w.call(&"zone_at", x, z)
				var table: Array = ZONE_W.get(zn, [])
				if table.is_empty():
					continue
				var p := Vector3(x, h, z)
				if flora._cleared(p):
					continue
				# пятна: в «пятне» вида в 2.6 раза гуще, между пятнами — реже
				var patch := clampf(0.35 + 1.6 * (noise.get_noise_2d(x, z) + 0.2), 0.15, 2.6)
				var jd := float(w.call(&"jungle_density", x, z)) if zn == &"jungle" else 0.0
				var td := float(w.call(&"trail_dist", x, z)) if w.has_method(&"trail_dist") else INF
				var r := rng.randf()
				var acc := 0.0
				for t in table:
					var g: String = t[0]
					var wgt := float(t[1]) * patch
					if g == "fern":
						wgt *= 1.0 + jd * 0.8
					acc += wgt
					if r < acc:
						var solid := g in ["howea", "kingsville", "macrozamia", "wall"]
						if td < 1.2 or (solid and td < 3.0):
							break
						var id := _pick(g, rng)
						var s := rng.randf_range(0.85, 1.2)
						var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), p + Vector3(0, -0.05, 0))
						_put(flora, id, xf)
						break
	_lianas(flora)

## Лианы на деревьях джунглей и между ними.
static func _lianas(flora) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(flora.seed) + 4242
	var trees: Array = []
	for rec in flora._tree_recs:
		var k: StringName = rec["kind"]
		if k == &"palm" or k == &"mangrove":
			continue
		var zn: StringName = flora.world.call(&"zone_at", (rec["pos"] as Vector3).x, (rec["pos"] as Vector3).z)
		if zn != &"jungle" and zn != &"lowland_forest":
			continue
		trees.append(rec)
	# хэш стволов для поиска соседей
	var grid: Dictionary = {}
	for rec in trees:
		var p: Vector3 = rec["pos"]
		var gk := Vector2i(int(floor(p.x / 12.0)), int(floor(p.z / 12.0)))
		if not grid.has(gk):
			grid[gk] = []
		(grid[gk] as Array).append(rec)
	for rec in trees:
		var v := FloraLib.variant(rec["kind"], rec["idx"])
		var H: float = v["H"]
		var tp: Vector3 = rec["pos"]
		if not rec.has("epi"):
			rec["epi"] = []
		# свисающие / вьющиеся по стволу
		if rng.randf() < (0.55 if rec["kind"] == &"banyan" else 0.28):
			var id: String = HANG[rng.randi_range(0, HANG.size() - 1)]
			var m := mesh(id)
			if m:
				var ab := m.get_aabb()
				var a := rng.randf() * TAU
				var out := Vector3(cos(a), 0, sin(a))
				var attach := clampf(H * rng.randf_range(0.55, 0.85), 2.5, 14.0)
				var s := clampf(attach / maxf(ab.size.y, 0.5), 0.6, 1.6)
				var lp := FloraLib.trunk_point(v, attach) + out * (FloraLib.trunk_radius(v, attach) * 0.9 + 0.05)
				var tb := Basis(Vector3.UP, float(rec["yaw"]))
				var wp: Vector3 = tp + tb * lp
				var bs := Basis(Vector3.UP, -a + PI * 0.5).scaled(Vector3.ONE * s)
				# верх модели — на точке крепления
				var org := wp - bs * Vector3(ab.get_center().x, ab.end.y, ab.get_center().z)
				(rec["epi"] as Array).append(_put(flora, id, Transform3D(bs, org)))
		# перекинутые между соседями
		if rng.randf() < 0.16 and H > 6.0:
			var gk := Vector2i(int(floor(tp.x / 12.0)), int(floor(tp.z / 12.0)))
			var best = null
			var bd := INF
			for dj in range(-1, 2):
				for di in range(-1, 2):
					for o in grid.get(gk + Vector2i(di, dj), []):
						if o == rec:
							continue
						var d := Vector2(tp.x, tp.z).distance_to(Vector2((o["pos"] as Vector3).x, (o["pos"] as Vector3).z))
						if d > 4.5 and d < 12.0 and d < bd:
							bd = d
							best = o
			if best != null:
				var id2: String = SPAN[rng.randi_range(0, SPAN.size() - 1)]
				var m2 := mesh(id2)
				if m2:
					var ab2 := m2.get_aabb()
					var op: Vector3 = best["pos"]
					var Hb: float = FloraLib.variant(best["kind"], best["idx"])["H"]
					var attach2 := clampf(minf(H, Hb) * rng.randf_range(0.5, 0.75), 3.0, 12.0)
					var dir := Vector3(op.x - tp.x, 0, op.z - tp.z)
					var sx := clampf(bd / maxf(ab2.size.x, 0.5), 0.5, 1.8)
					var yaw := atan2(-dir.z, dir.x)
					var bs2 := Basis(Vector3.UP, yaw) * Basis().scaled(Vector3(sx, 1.0, 1.0))
					var mid := (tp + op) * 0.5
					mid.y = minf(tp.y, op.y) + attach2
					var org2 := mid - bs2 * Vector3(ab2.get_center().x, ab2.end.y, ab2.get_center().z)
					(rec["epi"] as Array).append(_put(flora, id2, Transform3D(bs2, org2)))
