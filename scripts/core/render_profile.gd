class_name RenderProfile
extends RefCounted
## Настройка окружения: в Forward+ (ПК игрока) — полный набор (SDFGI, SSAO,
## SSIL, объёмный туман, свечение); в gl_compatibility (тесты, слабые ПК) —
## только поддерживаемое, без предупреждений.

static func is_compat() -> bool:
	return RenderingServer.get_rendering_device() == null # у OpenGL (gl_compatibility) нет RenderingDevice

## Небо, туман, тонмаппинг. sun — направленный свет (цвет неба согласуем).
const DEFAULT_HDRI := "res://assets/hdri/kloofendal_48d_partly_cloudy_puresky.hdr"

static func make_environment(hdri_path: String = DEFAULT_HDRI) -> Environment:
	var env := Environment.new()
	var sky := Sky.new()
	if hdri_path != "" and ResourceLoader.exists(hdri_path):
		var pm := PanoramaSkyMaterial.new()
		pm.panorama = load(hdri_path) as Texture2D
		pm.energy_multiplier = 1.0
		sky.sky_material = pm
	else:
		sky.sky_material = _procedural_sky()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	return _finish_environment(env)

static func _procedural_sky() -> ProceduralSkyMaterial:
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.32, 0.55, 0.82)
	sm.sky_horizon_color = Color(0.72, 0.82, 0.88)
	sm.ground_horizon_color = Color(0.72, 0.82, 0.88)
	sm.ground_bottom_color = Color(0.20, 0.30, 0.36)
	sm.sun_angle_max = 30.0
	sm.sun_curve = 0.12
	return sm

static func _finish_environment(env: Environment) -> Environment:
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	# Туман дымки — важен для «лесной» атмосферы.
	env.fog_enabled = true
	env.fog_light_color = Color(0.70, 0.78, 0.82)
	env.fog_density = 0.0035
	env.fog_aerial_perspective = 0.4
	env.fog_sky_affect = 0.25
	if is_compat():
		return env
	# --- только Forward+ ---
	# Какие эффекты включены — решает пресет (GraphicsQuality).
	env.ssao_radius = 1.4
	env.ssao_intensity = 2.0
	env.glow_intensity = 0.4
	env.glow_bloom = 0.05
	env.volumetric_fog_density = 0.008
	env.volumetric_fog_albedo = Color(0.85, 0.9, 0.92)
	env.volumetric_fog_anisotropy = 0.6
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.05
	GraphicsQuality.apply_environment(env)
	return env

static func make_sun() -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48.0, 35.0, 0.0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	GraphicsQuality.apply_sun(sun)
	if not is_compat():
		sun.light_volumetric_fog_energy = 1.0
	return sun
