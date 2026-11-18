class_name SkyWeather
extends Node3D
## Небо и смена дня/ночи (Sky3D — работает и в Forward+, и в gl_compatibility),
## погода (ясно / облачно / дождь / туман / шторм) с плавными переходами,
## дождь вокруг камеры, молнии с громом, туман по погоде и времени суток,
## подводный вид.

const MINUTES_PER_DAY := 24.0     # реальных минут на игровые сутки
const BLEND_TIME := 40.0
const WEATHERS: Dictionary = {
	&"clear": {"cov": 0.38, "cirrus": 0.5, "fog": 0.0011, "rain": 0.0, "waves": 1.0, "sun": 1.0, "wind": 1.0},
	&"cloudy": {"cov": 0.78, "cirrus": 1.0, "fog": 0.0018, "rain": 0.0, "waves": 1.25, "sun": 0.7, "wind": 2.0},
	&"rain": {"cov": 0.95, "cirrus": 1.4, "fog": 0.0045, "rain": 0.7, "waves": 1.6, "sun": 0.42, "wind": 3.5},
	&"fog": {"cov": 0.7, "cirrus": 0.8, "fog": 0.05, "rain": 0.0, "waves": 0.8, "sun": 0.55, "wind": 0.6},
	&"storm": {"cov": 1.0, "cirrus": 2.0, "fog": 0.0065, "rain": 1.0, "waves": 3.0, "sun": 0.25, "wind": 9.0},
}

var sky3d: Sky3D
var weather: StringName = &"clear"
var _cur: Dictionary = {}
var _from: Dictionary = {}
var _blend := 1.0
var _left := 420.0
var _auto := true
var _rain: CPUParticles3D
var _rng := RandomNumberGenerator.new()
var _lightning_t := 10.0
var _flash := 0.0
var _thunder: AudioStreamPlayer
var _underwater := false
var _env: Environment
var _cloud_t := 0.0

func setup(start_hour: float = 8.5) -> void:
	_rng.seed = 4242
	sky3d = Sky3D.new()
	sky3d.name = "Sky3D"
	add_child(sky3d)
	sky3d.minutes_per_day = MINUTES_PER_DAY
	sky3d.current_time = start_hour
	sky3d.tonemap_exposure = 0.85
	# атмосферный туман Sky3D (экранный квад по глубине) в compat заливает кадр — только Forward+
	sky3d.fog_enabled = not RenderProfile.is_compat()
	# Положение солнца/луны и параметры неба — 4 раза в секунду (сутки идут
	# 24 мин: солнце сдвигается на ~0.06°), облака — вручную ~10 раз в секунду.
	# Каждое изменение материала неба заставляет пересчитывать отражения неба.
	sky3d.update_interval = 0.25
	if sky3d.sky:
		sky3d.sky.process_method = SkyDome.MANUAL
	_env = sky3d.environment
	if _env:
		_apply_render_profile(_env)
	_apply_quality()
	if not Settings.graphics_changed.is_connected(_apply_quality):
		Settings.graphics_changed.connect(_apply_quality)
	_cur = (WEATHERS[&"clear"] as Dictionary).duplicate()
	_from = _cur.duplicate()
	_make_rain()
	_thunder = AudioStreamPlayer.new()
	var th := _find_sound("thunder")
	if th:
		_thunder.stream = th
	add_child(_thunder)
	_apply(1.0)

## Окружение Sky3D + наши настройки рендера (SDFGI/SSAO/объёмный туман в Forward+).
func _apply_render_profile(env: Environment) -> void:
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_density = 0.0011
	env.fog_aerial_perspective = 0.5
	env.fog_sky_affect = 0.15
	if RenderProfile.is_compat():
		return
	env.ssao_radius = 1.4
	env.ssao_intensity = 2.0
	env.glow_intensity = 0.35
	env.volumetric_fog_density = 0.006
	env.volumetric_fog_anisotropy = 0.6
	GraphicsQuality.apply_environment(env)

## Пресет графики: эффекты окружения, тени солнца, туман Sky3D.
func _apply_quality() -> void:
	if sky3d == null:
		return
	if _env:
		GraphicsQuality.apply_environment(_env)
	if sky3d.sun:
		GraphicsQuality.apply_sun(sky3d.sun)
	if not RenderProfile.is_compat():
		sky3d.fog_enabled = bool(GraphicsQuality.preset().get("sky_fog", true))

func _find_sound(key: String) -> AudioStream:
	for dir_path in ["res://assets/sounds/", "res://assets/sounds/cc0/", "res://assets/sounds/oculus/"]:
		var d := DirAccess.open(dir_path)
		if d == null:
			continue
		for f in d.get_files():
			if f.to_lower().contains(key) and (f.ends_with(".ogg") or f.ends_with(".wav") or f.ends_with(".mp3")):
				return load(dir_path + f) as AudioStream
	return null

func _make_rain() -> void:
	_rain = CPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = 2600
	_rain.lifetime = 1.1
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(22.0, 0.5, 22.0)
	_rain.direction = Vector3(0.12, -1.0, 0.05)
	_rain.spread = 3.0
	_rain.gravity = Vector3(0.0, -9.8, 0.0)
	_rain.initial_velocity_min = 16.0
	_rain.initial_velocity_max = 20.0
	_rain.local_coords = false
	var qm := QuadMesh.new()
	qm.size = Vector2(0.018, 0.55)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.75, 0.82, 0.9, 0.35)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	qm.material = mat
	_rain.mesh = qm
	_rain.emitting = false
	add_child(_rain)

# ------------------------------------------------------------ API

func time_of_day() -> float:
	return sky3d.current_time if sky3d else 12.0

func set_time_of_day(h: float) -> void:
	if sky3d:
		sky3d.current_time = fposmod(h, 24.0)
		if sky3d.tod:
			sky3d.tod.current_time = fposmod(h, 24.0)

func is_night() -> bool:
	return sun_elevation() < -0.1

## 0 — глубокая ночь, 1 — день.
## Высота солнца над горизонтом: sin угла (−1..1), по реальному положению солнца Sky3D.
func sun_elevation() -> float:
	if sky3d and sky3d.sun:
		return sky3d.sun.global_transform.basis.z.y
	var t := time_of_day()
	return sin((t - 6.0) / 12.0 * PI)

## 0 — ночь, 1 — день; плавно в сумерках.
func daylight() -> float:
	return smoothstep(-0.14, 0.12, sun_elevation())

func set_weather(w: StringName, instant: bool = false, auto: bool = true) -> void:
	if not WEATHERS.has(w):
		return
	_auto = auto
	_from = _cur.duplicate()
	weather = w
	_blend = 1.0 if instant else 0.0
	_left = _rng.randf_range(240.0, 600.0)
	if instant:
		_cur = (WEATHERS[w] as Dictionary).duplicate()
	_apply(1.0)

func wave_scale() -> float:
	return float(_cur.get("waves", 1.0))

func rain_factor() -> float:
	return float(_cur.get("rain", 0.0))

func wind_strength() -> float:
	return float(_cur.get("wind", 1.0))

# ------------------------------------------------------------ обновление

func update(dt: float, cam: Camera3D, water_surface_at_cam: float) -> void:
	if _auto:
		_left -= dt
		if _left <= 0.0:
			set_weather(_pick_next())
	if _blend < 1.0:
		_blend = minf(1.0, _blend + dt / BLEND_TIME)
		var target: Dictionary = WEATHERS[weather]
		for k in target:
			_cur[k] = lerpf(float(_from.get(k, target[k])), float(target[k]), _blend)
	_apply(dt)
	_cloud_t += dt
	if _cloud_t >= 0.1 and sky3d and sky3d.sky:
		sky3d.sky.process_tick(_cloud_t)
		_cloud_t = 0.0
	if cam:
		_rain.global_position = cam.global_position + Vector3(0.0, 14.0, 0.0)
		_update_underwater(cam.global_position.y < water_surface_at_cam - 0.05)
	_update_lightning(dt)

func _pick_next() -> StringName:
	var r := _rng.randf()
	match weather:
		&"clear":
			return &"cloudy" if r < 0.7 else &"fog"
		&"cloudy":
			return &"rain" if r < 0.45 else (&"clear" if r < 0.85 else &"storm")
		&"rain":
			return &"storm" if r < 0.3 else &"cloudy"
		&"fog":
			return &"clear"
		_:
			return &"rain" if r < 0.5 else &"cloudy"

func _apply(_dt: float) -> void:
	if sky3d == null:
		return
	if sky3d.sky:
		if absf(sky3d.sky.cumulus_coverage - float(_cur.cov)) > 0.002:
			sky3d.sky.cumulus_coverage = float(_cur.cov)
		if absf(sky3d.sky.cirrus_coverage - float(_cur.cirrus)) > 0.004:
			sky3d.sky.cirrus_coverage = float(_cur.cirrus)
		if absf(sky3d.sky.wind_speed - float(_cur.wind)) > 0.05:
			sky3d.sky.wind_speed = float(_cur.wind)
	var se := float(_cur.sun) + _flash * 4.0
	if absf(sky3d.sun_energy - se) > 0.003:
		sky3d.sun_energy = se
	var rain := float(_cur.rain)
	_rain.emitting = rain > 0.05 and not _underwater
	if _rain.emitting:
		_rain.speed_scale = 0.8 + 0.4 * clampf(rain, 0.0, 1.0)
	if _env and not _underwater:
		var dl := daylight()
		var fog_day := Color(0.72, 0.8, 0.84).lerp(Color(0.55, 0.6, 0.64), clampf(rain, 0.0, 1.0))
		var fog_night := Color(0.05, 0.07, 0.1)
		_env.fog_light_color = fog_night.lerp(fog_day, dl)
		_env.fog_density = float(_cur.fog)
		_env.fog_sky_affect = clampf(0.15 + float(_cur.fog) * 14.0, 0.15, 0.85)
		_env.fog_light_energy = 1.0 + _flash * 3.0

func _update_lightning(dt: float) -> void:
	_flash = maxf(0.0, _flash - dt * 6.0)
	if weather != &"storm" or _blend < 0.6:
		return
	_lightning_t -= dt
	if _lightning_t <= 0.0:
		_lightning_t = _rng.randf_range(6.0, 18.0)
		_flash = 1.0
		if _thunder.stream:
			_thunder.pitch_scale = _rng.randf_range(0.85, 1.1)
			_thunder.play()

func _update_underwater(under: bool) -> void:
	if under == _underwater or _env == null:
		return
	_underwater = under
	if under:
		_env.fog_light_color = Color(0.04, 0.28, 0.33)
		_env.fog_density = 0.09
		_env.fog_sky_affect = 1.0
	else:
		_env.fog_sky_affect = 0.15
		_apply(0.0)

func is_underwater_view() -> bool:
	return _underwater
