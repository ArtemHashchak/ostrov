class_name UserSeaPack
extends RefCounted
## Морской пак пользователя (assets/user_pack/sea, items): предметы, ракушки на пляжах,
## материалы для экспонатов полигона. Живность в море подключена данными —
## assets/user_pack/sea_species_user_sea.json (реестр SeaSpecies, группы — SeaLifeCells).

const SPECIES_SHADER := "res://scripts/sea/user_pack/user_species.gdshader"
const SHELL := "res://assets/user_pack/items/item_shell_junonia.glb"
const DRIED_FISH := "res://assets/user_pack/items/item_dried_fish.glb"
const MAX_SHELLS := 36

static var _shell_scene: PackedScene


## Предметы пака: «Ракушка» (модель из пака в руке и на земле).
static func register_items() -> void:
	if Items.get_item(&"seashell") == null:
		Items.register_item(&"seashell", "Ракушка", &"misc", 20, 0.05,
			{"held": Callable(UserSeaPack, "shell_model"), "color": Color(0.9, 0.82, 0.62)})


static func shell_model() -> Node3D:
	if _shell_scene == null and ResourceLoader.exists(SHELL):
		_shell_scene = load(SHELL) as PackedScene
	if _shell_scene == null:
		return null
	var n := _shell_scene.instantiate() as Node3D
	n.scale = Vector3.ONE * 1.4   # ракушка ~10 см — в руке чуть крупнее, чтобы было видно
	return n


## Ракушки на пляжах (мусорные и черепашьи берега): подбираемые предметы, не больше MAX_SHELLS.
static func scatter_shells(sea: Node, rng_seed: int = 4711) -> int:
	if not ResourceLoader.exists(SHELL):
		return 0
	var world := sea.get_tree().get_first_node_in_group(&"world")
	if world == null or not world.has_method(&"trash_beaches"):
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var spots: Array = []
	for b: Dictionary in world.call(&"trash_beaches"):
		spots.append(b)
	if world.has_method(&"turtle_beaches"):
		for b: Dictionary in world.call(&"turtle_beaches"):
			spots.append(b)
	var n := 0
	for b: Dictionary in spots:
		var p: Variant = b.get("pos", b.get("center", null))
		if p == null:
			continue
		var c := Vector2((p as Vector3).x, (p as Vector3).z) if p is Vector3 else p as Vector2
		for k in 2:
			if n >= MAX_SHELLS:
				return n
			var q := c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.0, 7.0)
			if not world.call(&"is_land", q.x, q.y):
				continue
			var h: float = world.call(&"height_at", q.x, q.y)
			var pk := ItemPickup.spawn(sea, Vector3(q.x, h + 0.15, q.y), [{"id": &"seashell", "n": 1}])
			if pk:
				pk.freeze = true   # лежит, не катается (дёшево для физики)
				n += 1
	return n


## Материал вида как в SeaLifeCells (для экспонатов полигона и тестов).
static func species_material(d: Dictionary, in_place: bool = false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(String(d.get("shader", SPECIES_SHADER)))
	var L := float(d.get("length", 0.4))
	m.set_shader_parameter(&"body_len", L)
	m.set_shader_parameter(&"anim_mode", ["fish", "eel", "ray", "jelly", "static", "vat", "octopus"].find(String(d.get("anim", "fish"))))
	var spd := float(d.get("speed", 1.0))
	m.set_shader_parameter(&"tail_speed", clampf(spd * 6.0 / maxf(L, 0.1), 4.0, 16.0))
	m.set_shader_parameter(&"wiggle", 0.07)
	m.set_shader_parameter(&"roam", Vector2.ZERO if in_place else Vector2(float(d.get("roam", 6.0)), float(d.get("roam", 6.0)) * 0.75))
	m.set_shader_parameter(&"bob", 0.0 if in_place else minf(0.5, float(d.get("roam", 6.0)) * 0.08))
	m.set_shader_parameter(&"in_place", in_place)
	var mesh := species_mesh(d)
	var tex: Texture2D = null
	if mesh and mesh.get_surface_count() > 0 and mesh.surface_get_material(0) is BaseMaterial3D:
		tex = (mesh.surface_get_material(0) as BaseMaterial3D).albedo_texture
	m.set_shader_parameter(&"use_vertex_color", tex == null)
	m.set_shader_parameter(&"use_tex", tex != null)
	if tex:
		m.set_shader_parameter(&"albedo_tex", tex)
	var extra: Dictionary = d.get("params", {})
	for k: Variant in extra:
		var val: Variant = extra[k]
		if val is String and String(val).begins_with("#"):
			val = Color(String(val))
		m.set_shader_parameter(StringName(String(k)), val)
	return m


static func species_mesh(d: Dictionary) -> Mesh:
	var p := String(d.get("mesh", ""))
	return load(p) as Mesh if p != "" and ResourceLoader.exists(p) else null


## Один экспонат (MultiMesh из 1 особи — тот же шейдер и анимация, что в море, но на месте).
static func exhibit(d: Dictionary) -> MultiMeshInstance3D:
	var mesh := species_mesh(d)
	if mesh == null:
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D.IDENTITY)
	mm.set_instance_custom_data(0, Color(0.0, 0.5, 0.5, 0.3))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = species_material(d, true)
	var L := float(d.get("length", 0.4))
	mi.custom_aabb = AABB(Vector3.ONE * -L * 1.5, Vector3.ONE * L * 3.0)
	return mi


## Записи видов пака (из JSON).
static func species_list() -> Array:
	var path := "res://assets/user_pack/sea_species_user_sea.json"
	if not FileAccess.file_exists(path):
		return []
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Array else []
