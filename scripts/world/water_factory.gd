class_name WaterFactory
extends RefCounted
## Океан: Forward+ — LesusX Gerstner (экранная глубина, каустика, пена у берега);
## gl_compatibility (тесты/слабые ПК) — antz foam water.

const ANTZ := "res://addons/ostrova_water/antz_foam_water/water_material.tres"
const LESUSX := "res://addons/ostrova_water/lesusx_gerstner/"

static func make(size: float = 1200.0, subdiv: int = 240) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Ocean"
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	pm.subdivide_width = subdiv
	pm.subdivide_depth = subdiv
	mi.mesh = pm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = _compat_material() if RenderProfile.is_compat() else _forward_material()
	return mi

static func _compat_material() -> Material:
	var m := (load(ANTZ) as Material).duplicate() as Material
	return m

static func _forward_material() -> Material:
	var m := ShaderMaterial.new()
	m.shader = load(LESUSX + "water_shader.gdshader") as Shader
	m.set_shader_parameter(&"base_water_color", Color(0.05, 0.32, 0.42))
	m.set_shader_parameter(&"fresnel_water_color", Color(0.25, 0.6, 0.7))
	m.set_shader_parameter(&"deep_water_color", Color(0.02, 0.12, 0.22, 1.0))
	m.set_shader_parameter(&"shallow_water_color", Color(0.15, 0.62, 0.62, 1.0))
	m.set_shader_parameter(&"edge_foam_texture", load(LESUSX + "textures/foam.jpg"))
	m.set_shader_parameter(&"foam_texture", load(LESUSX + "textures/foam.jpg"))
	m.set_shader_parameter(&"normalmap_a", load(LESUSX + "textures/Water 0339normal.jpg"))
	m.set_shader_parameter(&"normalmap_b", load(LESUSX + "textures/water 0342normal.jpg"))
	var nt := NoiseTexture2D.new()
	nt.seamless = true
	nt.noise = FastNoiseLite.new()
	m.set_shader_parameter(&"uv_sampler", nt)
	return m
