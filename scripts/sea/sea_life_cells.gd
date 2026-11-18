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

## Биом точки: по глубине дна, рифам и болотам.
func biome_at(x: float, z: float, depth: float) -> String:
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
	# пробные точки на ячейку: каждая — шанс на группу подходящего вида
	# (в среднем Σgroups групп на водную ячейку подходящего биома)
	for i in PROBES:
		var x := (k.x + rng.randf()) * CELL
		var z := (k.y + rng.randf()) * CELL
		var depth: float = sea.call(&"depth_at", x, z)
		if depth < 0.8:
			continue
		var biome := biome_at(x, z, depth)
		var cands: Array[Dictionary] = []
		var wsum := 0.0
		for d in SeaSpecies.all():
			if int(d.min_quality) > q or not SeaSpecies.fits(d, biome, depth):
				continue
			cands.append(d)
			wsum += float(d.groups)
		if cands.is_empty():
			continue
		var roll := rng.randf() * float(PROBES) / dens
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
		var top := wy - 0.6
		var y := clampf(lerpf(floor_y + 0.8, top, rng.randf_range(0.15, 0.7)), floor_y + 0.5, top)
		if String(pick.anim) == "eel":
			y = floor_y + 0.25
		var mi := _take(pick)
		_setup_group(mi, pick, Vector3(x, y, z), rng, depth)
		list.append(mi)
		groups_active += 1
		instances_active += mi.multimesh.visible_instance_count

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
	var cols: Array = d.colors
	m.set_shader_parameter(&"color_a", cols[0])
	m.set_shader_parameter(&"color_b", cols[cols.size() - 1])
	m.set_shader_parameter(&"body_len", L)
	m.set_shader_parameter(&"anim_mode", ["fish", "eel", "ray", "jelly", "static", "vat"].find(String(d.anim)))
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
		# VAT: меш из запекания (порядок вершин совпадает с текстурой), масштаб — в шейдере
		var vm := load(vat_path) as Mesh
		if vm:
			mesh = vm
			VatBaker.apply(vm, m)
			var a := vm.get_aabb()
			var long := maxf(a.size.x, maxf(a.size.y, a.size.z))
			if long > 0.0001:
				m.set_shader_parameter(&"vat_scale", Vector3.ONE * (L / long))
	SeaPush.register(m)
	var r := {"mesh": mesh, "mat": m}
	_mesh_cache[id] = r
	return r

static func _first_mesh(res: Resource) -> Dictionary:
	if res is Mesh:
		return {"mesh": res, "tex": null}
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
