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
	_apply_user_ground(m)
	_apply_beach_sand(m)
	return m

## v5 (агент D): грунт пользователя (агент A, assets/user_pack/ground; каталог category=ground):
## луг — grass_02 (сочная тропическая трава), подстилка джунглей — grass_05 (корни, мох, листва),
## ил мангров — mud. Повтор ~2.2 м. Нет файлов — остаются прежние CC0-текстуры.
const USER_GROUND := "res://assets/user_pack/ground/"
static var use_user_ground := true

static func _ug(set_name: String, kind: String) -> Texture2D:
	var p := "%s%s/%s.jpg" % [USER_GROUND, set_name, kind]
	return load(p) as Texture2D if ResourceLoader.exists(p) else null

static func _apply_user_ground(m: ShaderMaterial) -> void:
	if not use_user_ground:
		return
	var g := _ug("grass_02", "albedo")
	var j := _ug("grass_05", "albedo")
	var mu := _ug("mud", "albedo")
	if g == null or j == null:
		return
	m.set_shader_parameter(&"grass_albedo", g)
	m.set_shader_parameter(&"grass_normal", _ug("grass_02", "normal"))
	m.set_shader_parameter(&"jungle_albedo", j)
	m.set_shader_parameter(&"jungle_normal", _ug("grass_05", "normal"))
	if mu:
		m.set_shader_parameter(&"mud_albedo", mu)
	m.set_shader_parameter(&"ground_tile", 0.45)

## Песок пользователя (Грунт/Песок): пляжный материал + утоптанный песок со следами.
static func _apply_beach_sand(m: ShaderMaterial) -> void:
	var alb := _t("beach_sand", "albedo")
	if alb == null:
		return
	m.set_shader_parameter(&"use_beach_sand", 1.0)
	m.set_shader_parameter(&"sand_albedo", alb)
	m.set_shader_parameter(&"sand_normal", _t("beach_sand", "normal"))
	m.set_shader_parameter(&"sand_height", _t("beach_sand", "height"))
	m.set_shader_parameter(&"sand_rough", _t("beach_sand", "roughness"))
	m.set_shader_parameter(&"tramp_albedo", _t("sand_trampled", "albedo"))
	m.set_shader_parameter(&"tramp_normal", _t("sand_trampled", "normal"))
	m.set_shader_parameter(&"tramp_height", _t("sand_trampled", "height"))
	# исходник тёплый (~#A28F6C); тропический пляж светлее — поднимаем яркость, чуть теплее
	m.set_shader_parameter(&"sand_tint", Color(1.22, 1.13, 0.98))
	# мшистая земля пользователя — пятнами в подлеске джунглей
	var ma := _t("mossy_ground", "albedo")
	if ma:
		m.set_shader_parameter(&"use_mossy", 1.0)
		m.set_shader_parameter(&"mossy_albedo", ma)
		m.set_shader_parameter(&"mossy_normal", _t("mossy_ground", "normal"))
		m.set_shader_parameter(&"mossy_rhm", _t("mossy_ground", "rhm"))

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
