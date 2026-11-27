class_name SeaLifeCells
extends Node3D
## Живность по реестру SeaSpecies в «пузыре» вокруг игроков. Море поделено на
## ячейки CELL×CELL м; заселены только ячейки рядом с камерой и пловцами (радиус по
## пресету), дальние освобождаются. Группа вида = один MultiMeshInstance3D из пула,
## всё движение и анимация — в шейдере sea_species (процессор не трогает особей).
## Состав ячейки детерминирован (сид от координат) — вернулся, а рыбы те же.
## Видимость — по дальности (visibility_range) и подводному туману.

const CELL := 64.0
const RADIUS_BY_Q: Array[int] = [1, 1, 1, 2]      # ячеек вокруг центра (1 → 3×3)
const DENSITY_BY_Q: Array[float] = [0.45, 0.7, 1.0, 1.25]
const VIS_END := 75.0
const PROBES := 12                              # дальше группы не рисуются
const PROBES_ZONED := 20                        # мир с картой зон: больше проб на ячейку
const ZONE_DENSITY := 1.6                       # и гуще (× оживлённость места)
const SHADER := preload("res://scripts/sea/shaders/sea_species.gdshader")

var sea: Node = null
var groups_active := 0
var instances_active := 0
var _cells: Dictionary = {}        # Vector2i -> Array[MultiMeshInstance3D]
var _pool: Dictionary = {}         # id вида -> Array[MultiMeshInstance3D]
var _mesh_cache: Dictionary = {}   # id -> {mesh, mat}
var _acc := 0.0
var _quality := -1
var _vat_cache: Dictionary = {}

func _ready() -> void:
	name = "LifeCells"
	add_to_group(&"sea_life_cells")

func _process(delta: float) -> void:
	var __pt := PerfStats.begin()
	_acc += delta
	if _acc >= 0.5:      # пересчёт пузыря дважды в секунду — ячейка 64 м
		_acc = 0.0
		refresh()
	PerfStats.end(&"sea_cells", __pt)

## Центры пузырей: камера и персонажи в воде.
func _centers() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var cam := get_viewport().get_camera_3d()
	if cam:
		out.append(Vector2(cam.global_position.x, cam.global_position.z))
	for n in get_tree().get_nodes_in_group(&"characters"):
		if n is Node3D and n.has_method(&"is_in_water") and bool(n.call(&"is_in_water")) \
				and n.has_method(&"is_dead") and not bool(n.call(&"is_dead")) and n.is_in_group(&"player"):
			var p := (n as Node3D).global_position
			out.append(Vector2(p.x, p.z))
	return out

func refresh() -> void:
	if sea == null:
		return
	var q := clampi(Settings.graphics_quality, 0, 3)
	if q != _quality:
		_quality = q
		clear()
	var want := {}
	var r := RADIUS_BY_Q[q]
	for c in _centers():
		var cc := Vector2i(floori(c.x / CELL), floori(c.y / CELL))
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				want[cc + Vector2i(dx, dz)] = true
	for k: Vector2i in _cells.keys():
		if not want.has(k):
			_release(k)
	for k: Vector2i in want.keys():
		if not _cells.has(k):
			_populate(k, q)

func clear() -> void:
	for k: Vector2i in _cells.keys():
		_release(k)

func _release(k: Vector2i) -> void:
	for mi: MultiMeshInstance3D in _cells[k]:
		mi.visible = false
		var id := String(mi.get_meta(&"species"))
		if not _pool.has(id):
			_pool[id] = []
		(_pool[id] as Array).append(mi)
		groups_active -= 1
		instances_active -= mi.multimesh.visible_instance_count
	_cells.erase(k)

## Мир с картой зон: биом — по зоне (риф/лагуна/мангры/океан); вне открытого моря — "".
func _zone_biome(zm: ZoneMap, x: float, z: float, depth: float) -> String:
	if not zm.is_sea(x, z):
		return ""
	match zm.zone_at(x, z):
		ZoneMap.Z_REEF_CREST, ZoneMap.Z_REEF_FLAT, ZoneMap.Z_REEF_SLOPE:
			return "reef"
		ZoneMap.Z_MANGROVE_WATER:
			return "mangrove"
		ZoneMap.Z_LAGOON, ZoneMap.Z_SHALLOWS:
			return "lagoon"
		ZoneMap.Z_DEEP_OCEAN:
			return "deep"
	return "deep" if depth > 9.0 else "lagoon"

var _live_noise: FastNoiseLite
## «Оживлённость» места 0.15..2.2: живность скоплениями — богатые и пустые места.
func liveliness(x: float, z: float) -> float:
	if _live_noise == null:
		_live_noise = FastNoiseLite.new()
		_live_noise.seed = 6151
		_live_noise.frequency = 0.008
		_live_noise.fractal_octaves = 2
	var n := _live_noise.get_noise_2d(x, z) * 0.5 + 0.5
	return lerpf(0.15, 2.2, smoothstep(0.2, 0.8, n))

func _zm() -> ZoneMap:
	var w: Node = sea.get(&"world") if sea else null
	return w.get(&"zones") if w else null

## Биом точки: по глубине дна, рифам и болотам.
func biome_at(x: float, z: float, depth: float) -> String:
	var zm := _zm()
	if zm != null:
		return _zone_biome(zm, x, z, depth)
	if sea and sea.has_method(&"reef_zones"):
		for zn: Dictionary in sea.call(&"reef_zones"):
			var c: Variant = zn.center
			var c2 := Vector2(c.x, c.z) if c is Vector3 else c as Vector2
			if c2.distance_to(Vector2(x, z)) < float(zn.radius):
				return "reef"
	var w: Node = sea.get(&"world") if sea else null
	if w and w.has_method(&"swamps"):
		for s: Variant in w.call(&"swamps"):
			if s is Dictionary and s.has("center"):
				var sc: Variant = s.center
				var s2 := Vector2(sc.x, sc.z) if sc is Vector3 else sc as Vector2
				if s2.distance_to(Vector2(x, z)) < float(s.get("radius", 40.0)) + 40.0:
					return "mangrove"
	if depth < 3.5:
		return "lagoon"
	return "deep" if depth > 9.0 else "lagoon"

func _populate(k: Vector2i, q: int) -> void:
	var list: Array[MultiMeshInstance3D] = []
	_cells[k] = list
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(k) ^ 0x51ab
	var wy: float = sea.call(&"water_y")
	var dens := DENSITY_BY_Q[q]
	var zm := _zm()
	var probes := PROBES
	if zm != null:
		# мир с картой зон: живности больше, скоплениями; всё — ниже самого низкого отлива
		wy = ZoneMap.LOW_TIDE
		var cx := (k.x + 0.5) * CELL
		var cz := (k.y + 0.5) * CELL
		dens *= ZONE_DENSITY * liveliness(cx, cz)
		probes = PROBES_ZONED
	# редкие виды (кит): не больше «rare» групп на всю карту — только в своих ячейках открытого океана
	for rd: Dictionary in SeaSpecies.all():
		if int(rd.get("rare", 0)) <= 0 or int(rd.min_quality) > q:
			continue
		if not _rare_cells(rd).has(k):
			continue
		var rc := Vector3((k.x + 0.5) * CELL, 0.0, (k.y + 0.5) * CELL)
		var rdep := SeaBounds.depth(sea, rc.x, rc.z)
		var rL := float(rd.length)
		var ry := clampf(wy - rdep * 0.45, wy - rdep + rL * 0.4 + 1.0, wy - rL * 0.3 - 2.0)
		var rmi := _take(rd)
		_setup_group(rmi, rd, Vector3(rc.x, ry, rc.z), rng, rdep)
		list.append(rmi)
		groups_active += 1
		instances_active += rmi.multimesh.visible_instance_count
	# пробные точки на ячейку: каждая — шанс на группу подходящего вида
	# (в среднем Σgroups групп на водную ячейку подходящего биома)
	for i in probes:
		var x := (k.x + rng.randf()) * CELL
		var z := (k.y + rng.randf()) * CELL
		var depth: float = sea.call(&"depth_at", x, z)
		if zm != null:
			depth = zm.depth_low(x, z) if zm.is_sea(x, z) else -1.0
		if depth < 0.8:
			continue
		var biome := biome_at(x, z, depth)
		if biome == "":
			continue
		var cands: Array[Dictionary] = []
		var wsum := 0.0
		for d in SeaSpecies.all():
			if int(d.min_quality) > q or int(d.get("rare", 0)) > 0 or not SeaSpecies.fits(d, biome, depth):
				continue
			cands.append(d)
			wsum += float(d.groups)
		if cands.is_empty():
			continue
		var roll := rng.randf() * float(probes) / dens
		if roll > wsum:
			continue
		var acc := 0.0
		var pick: Dictionary = cands[0]
		for d in cands:
			acc += float(d.groups)
			if roll <= acc:
				pick = d
				break
		var floor_y := wy - depth
		var L := float(pick.length)
		# v5.1: вся петля маршрута группы (шейдер водит её по эллипсу roam) — в море нужной глубины
		if zm != null or sea.has_method(&"depth_at"):
			var sp_max := clampf(L * 2.0 * pow(float((pick.school as Array)[1]), 0.4), 0.3, 6.0)
			var ro := float(pick.roam)
			if not SeaBounds.ring_ok(sea, Vector3(x, 0, z), ro + sp_max + L * 0.6, ro * 0.75 + sp_max + L * 0.6,
					SeaBounds.need_depth(L), 12):
				continue
		var top := wy - 0.6 - L * 0.25
		var y := clampf(lerpf(floor_y + 0.8 + L * 0.2, top, rng.randf_range(0.15, 0.7)), floor_y + 0.5 + L * 0.2, top)
		if String(pick.anim) == "eel":
			y = floor_y + 0.25
		var mi := _take(pick)
		_setup_group(mi, pick, Vector3(x, y, z), rng, depth)
		list.append(mi)
		groups_active += 1
		instances_active += mi.multimesh.visible_instance_count

var _rare: Dictionary = {}     # id вида → {Vector2i: true} — ячейки, где он живёт

## Ячейки редкого вида: «rare» штук на всю карту, в открытом океане, где вся петля маршрута
## глубокая; детерминированно по виду (одни и те же ячейки весь матч).
func _rare_cells(d: Dictionary) -> Dictionary:
	var id := String(d.id)
	if _rare.has(id):
		return _rare[id]
	var out := {}
	var zm := _zm()
	var L := float(d.length)
	var ro := float(d.roam)
	var need := maxf(SeaBounds.need_depth(L), float((d.depth as Array)[0]))
	var cand: Array[Vector2i] = []
	if zm != null:
		var x0 := floori(zm.origin.x / CELL)
		var z0 := floori(zm.origin.y / CELL)
		var x1 := floori((zm.origin.x + zm.nx * ZoneMap.STEP) / CELL)
		var z1 := floori((zm.origin.y + zm.nz * ZoneMap.STEP) / CELL)
		for cz in range(z0 + 1, z1 - 1):
			for cx in range(x0 + 1, x1 - 1):
				var c := Vector3((cx + 0.5) * CELL, 0.0, (cz + 0.5) * CELL)
				if not SeaBounds.deep_ocean(sea, c.x, c.z):
					continue
				var ok := true
				for a in 8:
					var an := TAU * a / 8.0
					var px := c.x + cos(an) * (ro + L)
					var pz := c.z + sin(an) * (ro + L)
					if not SeaBounds.deep_ocean(sea, px, pz) or SeaBounds.depth(sea, px, pz) < need:
						ok = false
						break
				if ok:
					cand.append(Vector2i(cx, cz))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id) ^ 0x7a11
	var n := mini(int(d.get("rare", 1)), cand.size())
	for i in n:
		var j := rng.randi_range(0, cand.size() - 1)
		out[cand[j]] = true
		cand.remove_at(j)
	_rare[id] = out
	return out

func _take(d: Dictionary) -> MultiMeshInstance3D:
	var id := String(d.id)
	var pool: Array = _pool.get(id, [])
	if not pool.is_empty():
		var mi: MultiMeshInstance3D = pool.pop_back()
		mi.visible = true
		return mi
	var mi := MultiMeshInstance3D.new()
	mi.set_meta(&"species", id)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = VIS_END
	mi.visibility_range_end_margin = 8.0
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var res := _resources(d)
	mm.mesh = res.mesh
	var smax: Array = d.school
	mm.instance_count = int(smax[1])
	mi.multimesh = mm
	mi.material_override = res.mat
	add_child(mi)
	return mi

func _setup_group(mi: MultiMeshInstance3D, d: Dictionary, pos: Vector3, rng: RandomNumberGenerator, _depth: float) -> void:
	var mm := mi.multimesh
	var sc: Array = d.school
	var n := rng.randi_range(int(sc[0]), int(sc[1]))
	mm.visible_instance_count = n
	var L := float(d.length)
	var spread := clampf(L * 2.0 * pow(float(n), 0.4), 0.3, 6.0)
	for i in n:
		var off := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.4, 0.4), rng.randf_range(-1, 1)) * spread
		if n == 1:
			off = Vector3.ZERO
		var s := rng.randf_range(0.85, 1.15)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * s), off))
		mm.set_instance_custom_data(i, Color(rng.randf() * 0.6, rng.randf(), rng.randf(), rng.randf()))
	var roam := float(d.roam)
	var bob := 0.5
	var ext := roam + spread + L * 2.0 + 3.0
	mm.custom_aabb = AABB(Vector3(-ext, -bob - spread - 2.0, -ext), Vector3(ext * 2.0, (bob + spread + 2.0) * 2.0, ext * 2.0))
	mi.global_position = pos
	# параметры маршрута общие для вида (один материал — лучше пакетирование);
	# группы различаются центром узла (фаза петли в шейдере берётся из него)

func _resources(d: Dictionary) -> Dictionary:
	var id := String(d.id)
	if _mesh_cache.has(id):
		return _mesh_cache[id]
	var L := float(d.length)
	var mesh: Mesh = null
	var tex: Texture2D = null
	var path := String(d.get("mesh", ""))
	if path != "" and ResourceLoader.exists(path):
		var found := _first_mesh(load(path))
		if not found.is_empty():
			mesh = found.mesh
			tex = found.tex
			# привести длину модели к length вида
			var aabb := mesh.get_aabb()
			var long := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
			if long > 0.0001 and absf(long - L) / L > 0.05:
				mesh = _scaled_mesh(mesh, L / long)
	if mesh == null:
		mesh = FishSchool.make_fish_mesh(L) if String(d.anim) != "eel" else _eel_mesh(L)
	var m := ShaderMaterial.new()
	m.shader = SHADER
	# свой шейдер вида (пак пользователя): "shader": "res://…gdshader" — те же параметры + свои
	var sh_path := String(d.get("shader", ""))
	if sh_path != "" and ResourceLoader.exists(sh_path):
		m.shader = load(sh_path)
	var cols: Array = d.colors
	m.set_shader_parameter(&"color_a", cols[0])
	m.set_shader_parameter(&"color_b", cols[cols.size() - 1])
	m.set_shader_parameter(&"body_len", L)
	m.set_shader_parameter(&"anim_mode", ["fish", "eel", "ray", "jelly", "static", "vat", "octopus"].find(String(d.anim)))
	m.set_shader_parameter(&"fwd_axis", maxi(0, ["-z", "+z", "+x", "-x"].find(String(d.get("forward", "-z")))))
	var spd := float(d.speed)
	m.set_shader_parameter(&"ang_speed", spd / maxf(float(d.roam), 1.0) * (1.0 if hash(id) % 2 == 0 else -1.0))
	m.set_shader_parameter(&"tail_speed", clampf(spd * 6.0 / maxf(L, 0.1), 4.0, 16.0))
	m.set_shader_parameter(&"wiggle", 0.07 if String(d.anim) != "eel" else 0.12)
	m.set_shader_parameter(&"roam", Vector2(float(d.roam), float(d.roam) * 0.75))
	m.set_shader_parameter(&"bob", minf(0.5, float(d.roam) * 0.08))
	m.set_shader_parameter(&"use_vertex_color", path == "" or tex == null)
	if tex:
		m.set_shader_parameter(&"use_tex", true)
		m.set_shader_parameter(&"albedo_tex", tex)
	var vat_path := String(d.get("vat", ""))
	if String(d.anim) == "vat" and vat_path != "" and ResourceLoader.exists(vat_path):
		# VAT: меш кадра 0 из запекания (порядок вершин = столбцы текстуры), длина — в шейдере
		var vm := load(vat_path) as Mesh
		if vm and vm.has_meta(&"vat_texture"):
			mesh = vm
			VatBaker.apply(vm, m)
			m.set_shader_parameter(&"anim_mode", 5)
			var long := VatBaker.model_length(vm)
			if long > 0.0001:
				m.set_shader_parameter(&"model_scale", L / long)
			m.set_shader_parameter(&"vat_speed", clampf(float(d.speed) / maxf(L * 0.3, 0.1), 0.5, 2.0))
			var src := vm.surface_get_material(0) as BaseMaterial3D
			if src and src.albedo_texture:
				m.set_shader_parameter(&"use_tex", true)
				m.set_shader_parameter(&"use_vertex_color", false)
				m.set_shader_parameter(&"albedo_tex", src.albedo_texture)
	# свои параметры шейдера вида: "params": {"glow": 1.5, "glow_color": "#33ddff", …}
	var extra: Dictionary = d.get("params", {})
	for k: Variant in extra:
		var val: Variant = extra[k]
		if val is String and String(val).begins_with("#"):
			val = Color(String(val))
		m.set_shader_parameter(StringName(String(k)), val)
	SeaPush.register(m)
	var r := {"mesh": mesh, "mat": m}
	_mesh_cache[id] = r
	return r

static func _first_mesh(res: Resource) -> Dictionary:
	if res is Mesh:
		var mt := (res as Mesh).surface_get_material(0) if (res as Mesh).get_surface_count() > 0 else null
		return {"mesh": res, "tex": (mt as BaseMaterial3D).albedo_texture if mt is BaseMaterial3D else null}
	if res is PackedScene:
		var root := (res as PackedScene).instantiate()
		var out := {}
		var stack: Array[Node] = [root]
		while not stack.is_empty() and out.is_empty():
			var n: Node = stack.pop_back()
			if n is MeshInstance3D and (n as MeshInstance3D).mesh:
				var me := (n as MeshInstance3D).mesh
				var tex: Texture2D = null
				var mat := me.surface_get_material(0)
				if mat is StandardMaterial3D:
					tex = (mat as StandardMaterial3D).albedo_texture
				out = {"mesh": me, "tex": tex}
			stack.append_array(n.get_children())
		root.free()
		return out
	return {}

static func _scaled_mesh(m: Mesh, k: float) -> Mesh:
	var out := ArrayMesh.new()
	for si in m.get_surface_count():
		var arr := m.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for i in v.size():
			v[i] *= k
		arr[Mesh.ARRAY_VERTEX] = v
		# кости/веса не нужны: анимация в шейдере
		arr[Mesh.ARRAY_BONES] = null
		arr[Mesh.ARRAY_WEIGHTS] = null
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out

## Угорь: вытянутое тело из рыбки (длина L, толщина ~L/14).
static func _eel_mesh(L: float) -> ArrayMesh:
	var base := FishSchool.make_fish_mesh(L)
	var out := ArrayMesh.new()
	for si in base.get_surface_count():
		var arr := base.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for i in v.size():
			v[i] = Vector3(v[i].x * 0.35, v[i].y * 0.4, v[i].z)
		arr[Mesh.ARRAY_VERTEX] = v
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out

func _exit_tree() -> void:
	_mesh_cache.clear()
	_pool.clear()
