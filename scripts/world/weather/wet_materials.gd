class_name WetMaterials
extends RefCounted
## Сырость для обычных материалов (StandardMaterial3D) — постройки, камни, предметы,
## модели паков (CONTRACT_WEATHER: weather_wetness). StandardMaterial3D не читает
## глобальные uniform, поэтому материалы регистрируются (база запоминается), а при
## изменении сырости на ≥0.02 им правится цвет/шероховатость/блеск.
## Регистрация: сами модули (register) + обход сцены по кусочкам (sweep_step).
## Шейдерные материалы (рельеф, листва, кора деревьев, фауна) мокнут сами.

const DARKEN := 0.3        # насколько темнеет альбедо мокрого материала
const WET_ROUGH := 0.28    # шероховатость полностью мокрой поверхности

static var _base: Dictionary = {}   # id материала -> [mat(weakref), albedo, roughness, specular]
static var _applied := 0.0
static var _queue: Array[int] = []   # instance id узлов (узел мог быть удалён)
static var _scan_t := 0.0

static func register(m: Material) -> void:
	if not (m is BaseMaterial3D):
		return
	var b := m as BaseMaterial3D
	var id := b.get_instance_id()
	if _base.has(id):
		return
	if b.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		return
	if b.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and b.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
		return
	if b.roughness < 0.2 or b.metallic > 0.5 or b.emission_enabled:
		return   # вода, стекло, металл, светящееся — не трогаем
	_base[id] = [weakref(b), b.albedo_color, b.roughness, b.metallic_specular, _is_wood(b)]
	_apply_one(_base[id], _applied)

## Древесина? (по имени материала/текстуры: wood, log, plank, bark, timber, дерев, брев, доск)
static func _is_wood(b: BaseMaterial3D) -> bool:
	var nm := b.resource_name.to_lower()
	if b.albedo_texture:
		nm += " " + b.albedo_texture.resource_path.get_file().to_lower() + " " + b.albedo_texture.resource_name.to_lower()
	for k in ["wood", "log", "plank", "bark", "timber", "дерев", "брев", "доск", "crate", "raft"]:
		if nm.contains(k):
			return true
	# тёплый бурый оттенок без текстуры — процедурное дерево построек
	var c := b.albedo_color
	return b.albedo_texture == null and c.r > c.g and c.g > c.b and c.r - c.b > 0.15 and c.v < 0.75

static func count() -> int:
	return _base.size()

static func _apply_one(e: Array, wet: float) -> void:
	var b := (e[0] as WeakRef).get_ref() as BaseMaterial3D
	if b == null:
		return
	var a: Color = e[1]
	# v5.2: мокрая древесина темнеет сильнее камня (впитывает воду): ×1.5
	var k := 1.0 - DARKEN * wet * (1.5 if e.size() > 4 and bool(e[4]) else 1.0)
	b.albedo_color = Color(a.r * k, a.g * k, a.b * k, a.a)
	b.roughness = lerpf(float(e[2]), WET_ROUGH, wet * 0.85)
	b.metallic_specular = lerpf(float(e[3]), 0.65, wet)

## Каждый кадр из SkyWeather. Пересчёт — только когда сырость заметно сменилась.
static func update(wet: float, dt: float, tree: SceneTree) -> void:
	if wet > 0.01 or _applied > 0.01:
		sweep_step(tree, dt)
	if absf(wet - _applied) < 0.02 and not (wet == 0.0 and _applied > 0.0):
		return
	_applied = wet
	var dead: Array = []
	for id in _base:
		var e: Array = _base[id]
		if (e[0] as WeakRef).get_ref() == null:
			dead.append(id)
			continue
		_apply_one(e, wet)
	for id in dead:
		_base.erase(id)

## Обход сцены кусками (≤0.4 мс за кадр); новый проход — раз в 10 с.
static func sweep_step(tree: SceneTree, dt: float) -> void:
	if tree == null:
		return
	if _queue.is_empty():
		_scan_t -= dt
		if _scan_t > 0.0:
			return
		_scan_t = 10.0
		for n in tree.root.find_children("*", "GeometryInstance3D", true, false):
			_queue.append(n.get_instance_id())
		return
	var t_end := Time.get_ticks_usec() + 400
	while not _queue.is_empty() and Time.get_ticks_usec() < t_end:
		var obj: Object = instance_from_id(_queue.pop_back())
		if obj == null or not is_instance_valid(obj) or not (obj is GeometryInstance3D):
			continue
		var gi := obj as GeometryInstance3D
		if not gi.is_inside_tree():
			continue
		if gi.global_position.y < -1.0:
			continue   # под водой (морская живность, дно) — не мокнет от дождя
		if gi.material_override:
			register(gi.material_override)
		var mesh: Mesh = null
		if gi is MeshInstance3D:
			mesh = (gi as MeshInstance3D).mesh
			for si in (gi as MeshInstance3D).get_surface_override_material_count():
				var om := (gi as MeshInstance3D).get_surface_override_material(si)
				if om:
					register(om)
		elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh:
			mesh = (gi as MultiMeshInstance3D).multimesh.mesh
		if mesh:
			for si in mesh.get_surface_count():
				var sm := mesh.surface_get_material(si)
				if sm:
					register(sm)
			if mesh is PrimitiveMesh and (mesh as PrimitiveMesh).material:
				register((mesh as PrimitiveMesh).material)

## Регистрация материалов одного узла сразу (модули и тесты; обход сцены дойдёт и сам).
static func register_node(n: Node) -> void:
	for gi in [n] + n.find_children("*", "GeometryInstance3D", true, false):
		if not (gi is GeometryInstance3D):
			continue
		if (gi as GeometryInstance3D).material_override:
			register((gi as GeometryInstance3D).material_override)
		if gi is MeshInstance3D and (gi as MeshInstance3D).mesh:
			var m: Mesh = (gi as MeshInstance3D).mesh
			for si in m.get_surface_count():
				if m.surface_get_material(si):
					register(m.surface_get_material(si))
			if m is PrimitiveMesh and (m as PrimitiveMesh).material:
				register((m as PrimitiveMesh).material)

## Сброс (выход из матча): вернуть базовые значения.
static func reset() -> void:
	for id in _base:
		var e: Array = _base[id]
		_apply_one(e, 0.0)
	_base.clear()
	_queue.clear()
	_applied = 0.0
	_scan_t = 0.0
