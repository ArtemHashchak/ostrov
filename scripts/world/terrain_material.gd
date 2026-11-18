class_name TerrainMaterial
extends RefCounted
## Материал рельефа на PBR-текстурах из assets/textures (CC0).

const TEX := "res://assets/textures/"

static func make(water_level: float = 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://scripts/world/shaders/terrain_splat.gdshader") as Shader
	m.set_shader_parameter(&"sand_albedo", _t("coast_sand_01", "albedo"))
	m.set_shader_parameter(&"sand_normal", _t("coast_sand_01", "normal"))
	m.set_shader_parameter(&"wet_albedo", _t("damp_sand", "albedo"))
	m.set_shader_parameter(&"grass_albedo", _t("leafy_grass", "albedo"))
	m.set_shader_parameter(&"grass_normal", _t("leafy_grass", "normal"))
	m.set_shader_parameter(&"rock_albedo", _t("rocky_terrain_02", "albedo"))
	m.set_shader_parameter(&"rock_normal", _t("rocky_terrain_02", "normal"))
	m.set_shader_parameter(&"water_level", water_level)
	return m

## Тропический рельеф архипелага (веса биомов — в цвете вершин).
static func make_tropic(water_level: float = 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://scripts/world/shaders/terrain_tropic.gdshader") as Shader
	m.set_shader_parameter(&"sand_albedo", _t("coast_sand_01", "albedo"))
	m.set_shader_parameter(&"sand_normal", _t("coast_sand_01", "normal"))
	m.set_shader_parameter(&"wet_albedo", _t("damp_sand", "albedo"))
	m.set_shader_parameter(&"grass_albedo", _t("leafy_grass", "albedo"))
	m.set_shader_parameter(&"grass_normal", _t("leafy_grass", "normal"))
	m.set_shader_parameter(&"jungle_albedo", _t("forest_leaves_02", "albedo"))
	m.set_shader_parameter(&"jungle_normal", _t("forest_leaves_02", "normal"))
	m.set_shader_parameter(&"mud_albedo", _t("brown_mud_leaves_01", "albedo"))
	m.set_shader_parameter(&"rock_albedo", _t("cliff_side", "albedo"))
	m.set_shader_parameter(&"rock_normal", _t("cliff_side", "normal"))
	m.set_shader_parameter(&"seabed_albedo", _t("coral_gravel", "albedo"))
	m.set_shader_parameter(&"volc_albedo", _t("dark_rock", "albedo"))
	m.set_shader_parameter(&"volc_normal", _t("dark_rock", "normal"))
	m.set_shader_parameter(&"water_level", water_level)
	return m

## PBR-материал из набора (albedo/normal/roughness/ao).
static func pbr(set_name: String, uv_scale: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _t(set_name, "albedo")
	m.normal_enabled = true
	m.normal_texture = _t(set_name, "normal")
	m.roughness_texture = _t(set_name, "roughness")
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	var ao := _t(set_name, "ao")
	if ao:
		m.ao_enabled = true
		m.ao_texture = ao
	m.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	return m

static func _t(set_name: String, kind: String) -> Texture2D:
	var p := "%s%s/%s_%s.png" % [TEX, set_name, set_name, kind]
	return load(p) as Texture2D if ResourceLoader.exists(p) else null
