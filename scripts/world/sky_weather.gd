class_name SkyWeather
extends Node3D
## Небо и смена дня/ночи (Sky3D — работает и в Forward+, и в gl_compatibility),
## погода (ясно / облачно / дождь / туман / шторм) с плавными переходами,
## дождь вокруг камеры, молнии с громом, туман по погоде и времени суток,
## подводный вид.

signal weather_changed(w: StringName)

const MINUTES_PER_DAY := 24.0     # реальных минут на игровые сутки
## Смена погоды идёт плавно ~2 минуты: шторм «объявляет себя» темнеющим небом заранее.
const BLEND_TIME := 120.0
## wind — скорость облаков Sky3D; wspd — ветер у земли/моря, м/с; storm — сила шторма 0..1.
const WEATHERS: Dictionary = {
	&"clear": {"cov": 0.38, "cirrus": 0.5, "fog": 0.0011, "rain": 0.0, "waves": 1.0, "sun": 1.0, "wind": 1.0, "wspd": 3.0, "storm": 0.0},
	&"cloudy": {"cov": 0.78, "cirrus": 1.0, "fog": 0.0018, "rain": 0.0, "waves": 1.25, "sun": 0.7, "wind": 2.0, "wspd": 6.0, "storm": 0.1},
	&"rain": {"cov": 0.95, "cirrus": 1.4, "fog": 0.0045, "rain": 0.7, "waves": 1.6, "sun": 0.42, "wind": 3.5, "wspd": 10.0, "storm": 0.35},
	&"fog": {"cov": 0.7, "cirrus": 0.8, "fog": 0.05, "rain": 0.0, "waves": 0.8, "sun": 0.55, "wind": 0.6, "wspd": 1.5, "storm": 0.0},
	&"storm": {"cov": 1.0, "cirrus": 2.0, "fog": 0.0065, "rain": 1.0, "waves": 3.0, "sun": 0.25, "wind": 9.0, "wspd": 23.0, "storm": 1.0},
}
## Длительность погоды в авто-режиме, с (мин..макс): цикл на матч 3–4 ч.
const DURATION: Dictionary = {
	&"clear": Vector2(900.0, 1800.0), &"cloudy": Vector2(480.0, 900.0), &"rain": Vector2(360.0, 720.0),
	&"fog": Vector2(240.0, 480.0), &"storm": Vector2(300.0, 600.0),
}

var sky3d: Sky3D
var weather: StringName = &"clear"
var _cur: Dictionary = {}
var _from: Dictionary = {}
var _blend := 1.0
var _left := 420.0
var _auto := true
var rain_fx: RainFx
var lightning: LightningFx
var _rain_snd: AudioStreamPlayer
var _rain_in_snd: AudioStreamPlayer
var _wind_snd: AudioStreamPlayer
var _seed := 4242
var _rng := RandomNumberGenerator.new()
var _lightning_t := 10.0
var _flash := 0.0
## Вспышка молнии освещает сцену сама (ночью солнца нет): свет сверху без теней.
var _flash_light: DirectionalLight3D
var _underwater := false
var _env: Environment
var _cloud_t := 0.0
# ветер и сырость (см. CONTRACT_WEATHER.md)
var _wclock := 0.0
var _n_dir := FastNoiseLite.new()
var _n_gust := FastNoiseLite.new()
var _dir_base := 0.0
var _wind_dir := Vector2.RIGHT
var _wind_speed := 3.0
var _gust := 0.0
var _wetness := 0.0

func setup(start_hour: float = 8.5, seed_value: int = 4242) -> void:
	_rng.seed = seed_value
	_seed = seed_value
	_init_wind(seed_value)
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
	rain_fx = RainFx.new()
	add_child(rain_fx)
	_flash_light = DirectionalLight3D.new()
	_flash_light.name = "LightningLight"
	_flash_light.light_color = Color(0.78, 0.84, 1.0)
	_flash_light.shadow_enabled = false
	_flash_light.light_energy = 0.0
	_flash_light.visible = false
	_flash_light.rotation = Vector3(deg_to_rad(-62.0), deg_to_rad(25.0), 0.0)
	add_child(_flash_light)
	lightning = LightningFx.new()
	lightning.name = "Lightning"
	add_child(lightning)
	lightning.setup(_seed, _find_sound("thunder"))
	_rain_snd = _loop_player("RAINVege_ForestRain")
	_rain_in_snd = _loop_player("RAINInt_ForestCabinRain")
	_wind_snd = _loop_player("WINDVege_WindTrees")
	_apply_quality()
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

## Зацикленный фоновый звук (дождь/ветер); громкость правится в _update_sounds.
func _loop_player(key: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = "Snd_" + key
	var st := _find_sound(key)
	if st:
		st = st.duplicate()
		if st is AudioStreamOggVorbis:
			(st as AudioStreamOggVorbis).loop = true
		elif st is AudioStreamWAV:
			(st as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		p.stream = st
	p.volume_db = -80.0
	add_child(p)
	return p

func _set_loop(p: AudioStreamPlayer, vol: float) -> void:
	if p == null or p.stream == null:
		return
	if vol < 0.02:
		if p.playing:
			p.stop()
		return
	p.volume_db = linear_to_db(vol)
	if not p.playing:
		p.play(randf() * 4.0)

func _update_sounds(_dt: float) -> void:
	var rain := float(_cur.get("rain", 0.0))
	var cov := rain_fx != null and rain_fx.covered
	var u := 0.0 if _underwater else 1.0
	_set_loop(_rain_snd, rain * 0.75 * u * (0.35 if cov else 1.0))
	_set_loop(_rain_in_snd, rain * 0.8 * u * (1.0 if cov else 0.0))
	var wv := clampf((_wind_speed - 5.0) / 20.0, 0.0, 1.0)
	_set_loop(_wind_snd, wv * 0.8 * u * (0.75 + 0.5 * _gust))

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
	var changed := w != weather
	weather = w
	_blend = 1.0 if instant else 0.0
	var dur: Vector2 = DURATION.get(w, Vector2(300.0, 600.0))
	_left = _rng.randf_range(dur.x, dur.y)
	if instant:
		_cur = (WEATHERS[w] as Dictionary).duplicate()
		_wetness = float(_cur.rain) * 0.9
		_update_wind(0.0)
	_apply(1.0)
	if changed or instant:
		weather_changed.emit(w)

func wave_scale() -> float:
	return float(_cur.get("waves", 1.0))

func rain_factor() -> float:
	return float(_cur.get("rain", 0.0))

func wind_strength() -> float:
	return float(_cur.get("wind", 1.0))

# ------------------------------------------------------------ ветер и сырость

func _init_wind(seed_value: int) -> void:
	for n in [_n_dir, _n_gust]:
		var fn := n as FastNoiseLite
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fn.frequency = 1.0
		fn.fractal_type = FastNoiseLite.FRACTAL_NONE
	_n_dir.seed = seed_value * 31 + 7
	_n_gust.seed = seed_value * 17 + 3
	var r := RandomNumberGenerator.new()
	r.seed = seed_value + 99
	_dir_base = r.randf() * TAU
	_wclock = r.randf_range(0.0, 5000.0)
	_update_wind(0.0)

## Направление медленно «гуляет» (десятки минут), порывы — шум 0.1–0.2 Гц, сила — по погоде.
## Никаких скачков: всё — гладкий шум и плавный переход погоды.
func _update_wind(dt: float) -> void:
	_wclock += dt
	var storm := float(_cur.get("storm", 0.0))
	var ang := _dir_base + _n_dir.get_noise_1d(_wclock / 1200.0) * 2.4 + _n_dir.get_noise_1d(_wclock / 97.0 + 300.0) * 0.12 * (1.0 + storm)
	_wind_dir = Vector2(cos(ang), sin(ang))
	var g := 0.5 + 0.5 * _n_gust.get_noise_1d(_wclock * (0.09 + 0.08 * storm))
	g = 0.65 * g + 0.35 * (0.5 + 0.5 * _n_gust.get_noise_1d(_wclock * 0.43 + 77.0))
	_gust = smoothstep(0.42, 0.9, g)
	_wind_speed = float(_cur.get("wspd", 3.0)) * (0.82 + (0.3 + 0.35 * storm) * _gust)
	var rain := float(_cur.get("rain", 0.0))
	if rain > _wetness:
		_wetness = minf(rain, _wetness + dt / 45.0)
	else:
		_wetness = maxf(rain, _wetness - dt / 420.0)
	RenderingServer.global_shader_parameter_set(&"wind_dir", _wind_dir)
	RenderingServer.global_shader_parameter_set(&"wind_speed", _wind_speed)
	RenderingServer.global_shader_parameter_set(&"wind_gust", _gust)
	RenderingServer.global_shader_parameter_set(&"weather_rain", rain)
	RenderingServer.global_shader_parameter_set(&"weather_storm", storm)
	RenderingServer.global_shader_parameter_set(&"weather_wetness", _wetness)

func wind_dir() -> Vector2:
	return _wind_dir

func wind_speed() -> float:
	return _wind_speed

func gust() -> float:
	return _gust

func storm_intensity() -> float:
	return float(_cur.get("storm", 0.0))

func rain_intensity() -> float:
	return float(_cur.get("rain", 0.0))

func wetness() -> float:
	return _wetness

# ------------------------------------------------------------ обновление

func update(dt: float, cam: Camera3D, water_surface_at_cam: float) -> void:
	WetMaterials.update(wetness(), dt, get_tree())
	if _auto:
		_left -= dt
		if _left <= 0.0:
			set_weather(_pick_next())
	if _blend < 1.0:
		_blend = minf(1.0, _blend + dt / BLEND_TIME)
		var target: Dictionary = WEATHERS[weather]
		for k in target:
			_cur[k] = lerpf(float(_from.get(k, target[k])), float(target[k]), _blend)
	_update_wind(dt)
	_apply(dt)
	_cloud_t += dt
	if _cloud_t >= 0.1 and sky3d and sky3d.sky:
		sky3d.sky.process_tick(_cloud_t)
		_cloud_t = 0.0
	if cam:
		_update_underwater(cam.global_position.y < water_surface_at_cam - 0.05)
		var cp := cam.global_position
		var w := get_parent()
		var gh := water_surface_at_cam
		var sea := water_surface_at_cam
		if w and w.has_method(&"height_at"):
			gh = maxf(float(w.call(&"height_at", cp.x, cp.z)), water_surface_at_cam)
			sea = float(w.call(&"water_level")) if w.has_method(&"water_level") else water_surface_at_cam
		var near_shore := gh - sea < 3.0
		var light := clampf(0.25 + daylight() * 0.75, 0.2, 1.0) + _flash * 0.8
		rain_fx.update(dt, cam, float(_cur.rain), float(_cur.storm), _wind_dir, _wind_speed, light,
				_underwater, gh, sea, near_shore)
	_update_lightning(dt, cam)
	_update_sounds(dt)

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
		# шторм: небо и тучи заметно темнее (меняется только во время перехода погоды)
		var st0 := float(_cur.get("storm", 0.0))
		var rn0 := float(_cur.get("rain", 0.0))
		var sky_exp := 1.0 - 0.22 * st0 - 0.08 * rn0
		if absf(sky3d.sky.exposure - sky_exp) > 0.004:
			sky3d.sky.exposure = sky_exp
		var cint := 0.6 * (1.0 - 0.15 * st0)
		if absf(sky3d.sky.cumulus_intensity - cint) > 0.004:
			sky3d.sky.cumulus_intensity = cint
		var cabs := 2.0 + 1.2 * st0 + 0.6 * rn0
		if absf(sky3d.sky.cumulus_absorption - cabs) > 0.02:
			sky3d.sky.cumulus_absorption = cabs
	var se := float(_cur.sun) + _flash * 1.4
	if absf(sky3d.sun_energy - se) > 0.003:
		sky3d.sun_energy = se
	# в дождь тени солнца почти исчезают (сплошная облачность)
	if sky3d.sun:
		var so := clampf(1.0 - 0.9 * float(_cur.rain) - 0.3 * maxf(0.0, float(_cur.cov) - 0.6), 0.08, 1.0)
		if absf(sky3d.sun.shadow_opacity - so) > 0.01:
			sky3d.sun.shadow_opacity = so
	var rain := float(_cur.rain)
	var storm := float(_cur.get("storm", 0.0))
	if _env and not _underwater:
		var dl := daylight()
		var fog_day := Color(0.72, 0.8, 0.84).lerp(Color(0.55, 0.6, 0.64), clampf(rain, 0.0, 1.0))
		fog_day = fog_day.lerp(Color(0.36, 0.4, 0.45), smoothstep(0.4, 1.0, storm))
		# цветокоррекция: в шторм темнее, холоднее, менее насыщенно
		_env.adjustment_enabled = storm > 0.02 or rain > 0.02
		_env.adjustment_brightness = 1.0 - 0.1 * storm - 0.03 * rain + _flash * 0.12
		_env.adjustment_contrast = 1.0 + 0.06 * storm
		_env.adjustment_saturation = 1.0 - 0.32 * storm - 0.1 * rain
		# ночь под тучами: луна рассеивается в облаках — тусклый сине-серый минимум, чтобы
		# силуэты волн и островов читались и без молнии (молния — по-прежнему главный «показ»)
		var overcast := clampf(maxf(maxf(storm, rain * 0.8), (float(_cur.cov) - 0.6) * 1.5), 0.0, 1.0)
		var nk := (1.0 - dl) * overcast
		var fog_night := Color(0.05, 0.07, 0.1).lerp(Color(0.12, 0.14, 0.19), overcast)
		_env.fog_light_color = fog_night.lerp(fog_day, dl)
		# небо ночью почти чёрное → рассеянный свет берём частично из «облачного» цвета
		_env.ambient_light_color = Color(0.16, 0.19, 0.25)
		_env.ambient_light_sky_contribution = 1.0 - 0.55 * nk
		_env.fog_density = float(_cur.fog)
		# в дождь/шторм небо затянуто: дымка заметно перекрывает небо (серое, а не чёрное)
		_env.fog_sky_affect = clampf(0.15 + float(_cur.fog) * 14.0 + 0.45 * storm + 0.25 * rain, 0.15, 0.9)
		_env.fog_light_energy = 1.0 + _flash * 1.0

func _update_lightning(dt: float, cam: Camera3D) -> void:
	lightning.update(dt)
	_flash = lightning.flash
	_update_flash_light()
	var storm := float(_cur.get("storm", 0.0))
	if storm < 0.6 or _underwater:
		return
	_lightning_t -= dt
	if _lightning_t <= 0.0:
		# чем сильнее шторм, тем чаще (раз в 5–25 с)
		_lightning_t = _rng.randf_range(5.0, 14.0) * lerpf(1.8, 1.0, (storm - 0.6) / 0.4)
		lightning.do_strike(cam.global_position if cam else Vector3.ZERO, get_parent())

## Принудительная молния (тесты, кат-сцены).
func force_lightning(cam_pos: Vector3, close: bool = false) -> void:
	lightning.do_strike(cam_pos, get_parent(), 1.0 if close else 0.0)
	_flash = lightning.flash
	_update_flash_light()

func _update_flash_light() -> void:
	if _flash_light == null:
		return
	var on := _flash > 0.01 and not _underwater
	_flash_light.visible = on
	# ночью вспышка заметнее (относительно темноты), днём — лёгкий всполох
	_flash_light.light_energy = _flash * lerpf(1.6, 0.7, daylight()) if on else 0.0

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

func _exit_tree() -> void:
	# мокрые StandardMaterial3D общие (кэши модулей) — вернуть сухими при выходе из матча
	WetMaterials.reset()
