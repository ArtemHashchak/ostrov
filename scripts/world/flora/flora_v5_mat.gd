class_name FloraV5Mat
## Новые растения пользователя (assets/user_pack/flora_v5, GLTF со StandardMaterial3D) получают
## общий шейдер листвы flora_v5_leaf.gdshader: ветер, изгиб дерева, касание игроком (отгибание
## от основания и покачивание после прохода), сырость. Вызывается из AssetCatalog.instantiate.
## Материалы кешируются по исходному материалу и параметрам — экземпляры делят один ShaderMaterial.

const SHADER := preload("res://scripts/world/flora/flora_v5_leaf.gdshader")
static var _cache: Dictionary = {}

static func is_v5(path: String) -> bool:
	return path.contains("/flora_v5/")

## Параметры по записи каталога: высота, гибкость при касании, амплитуда ветра.
static func params_for(entry: Dictionary) -> Dictionary:
	var sz: Array = entry.get("size_m", [1.0, 1.0, 1.0])
	var h := float(sz[1]) if sz.size() > 1 else 1.0
	var wdt := maxf(float(sz[0]), float(sz[2]) if sz.size() > 2 else float(sz[0]))
	var col := String(entry.get("collision", "none"))
	var tags: Array = entry.get("tags", [])
	var cat := String(entry.get("category", "plant"))
	var hanging := false
	for t in tags:
		if String(t).begins_with("liana"):
			hanging = true
	var flex := 0.0
	if cat == "plant" and not hanging:
		flex = 1.0 if col != "solid" else 0.25
	return {
		"h": maxf(h, 0.1),
		"flex": flex,
		"reach": clampf(wdt * 0.45, 0.25, 1.6),
		"wind": clampf(0.03 + h * 0.025, 0.04, 0.22) if cat == "plant" else clampf(h * 0.012, 0.05, 0.25),
		"bend": 1.0 if cat == "tree" else 0.0,
		"hanging": hanging,
	}

## Заменить все StandardMaterial3D в поддереве на шейдер листвы v5.
static func convert(root: Node, entry: Dictionary) -> int:
	if root == null:
		return 0
	var prm := params_for(entry)
	var n := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		for ch in nd.get_children():
			stack.append(ch)
		var mi := nd as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var src := mi.get_surface_override_material(si)
			if src == null:
				src = mi.mesh.surface_get_material(si)
			var sm := src as StandardMaterial3D
			if sm == null:
				continue
			mi.set_surface_override_material(si, _make(sm, prm))
			n += 1
	return n

static func _make(sm: StandardMaterial3D, prm: Dictionary) -> ShaderMaterial:
	var key := "%d|%s" % [sm.get_instance_id(), str(prm)]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("albedo_tex", sm.albedo_texture)
	m.set_shader_parameter("tint", sm.albedo_color)
	var cut := 0.5
	if sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
		cut = sm.alpha_scissor_threshold
	elif sm.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
		cut = 0.0
	m.set_shader_parameter("alpha_cut", cut)
	if sm.normal_enabled and sm.normal_texture:
		m.set_shader_parameter("normal_tex", sm.normal_texture)
		m.set_shader_parameter("has_normal", true)
	if sm.roughness_texture:
		m.set_shader_parameter("orm_tex", sm.roughness_texture)
		m.set_shader_parameter("has_rough", true)
		m.set_shader_parameter("rough_channel", int(sm.roughness_texture_channel))
	m.set_shader_parameter("rough_value", sm.roughness)
	m.set_shader_parameter("metal_value", sm.metallic if sm.metallic_texture == null else 0.0)
	m.set_shader_parameter("model_height", prm.h)
	m.set_shader_parameter("push_flex", prm.flex)
	m.set_shader_parameter("push_reach", prm.reach)
	m.set_shader_parameter("wind_amp", prm.wind)
	m.set_shader_parameter("bend_k", prm.bend)
	m.set_shader_parameter("hanging", prm.hanging)
	m.set_shader_parameter("translucency", 0.3)
	_cache[key] = m
	return m
