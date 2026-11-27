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
	&"clear": {"cov": 0.38, "cirrus": 0.5, "fog": 0.0007, "rain": 0.0, "waves": 1.0, "sun": 1.0, "wind": 1.0, "wspd": 3.0, "storm": 0.0},
	&"cloudy": {"cov": 0.78, "cirrus": 1.0, "fog": 0.0013, "rain": 0.0, "waves": 1.25, "sun": 0.7, "wind": 2.0, "wspd": 6.0, "storm": 0.1},
	&"rain": {"cov": 0.95, "cirrus": 1.4, "fog": 0.0045, "rain": 0.7, "waves": 1.6, "sun": 0.42, "wind": 3.5, "wspd": 10.0, "storm": 0.35},
	&"fog": {"cov": 0.7, "cirrus": 0.8, "fog": 0.05, "rain": 0.0, "waves": 0.8, "sun": 0.55, "wind": 0.6, "wspd": 1.5, "storm": 0.0},
	&"storm": {"cov": 1.0, "cirrus": 2.0, "fog": 0.0065, "rain": 1.0, "waves": 3.4, "sun": 0.25, "wind": 9.0, "wspd": 23.0, "storm": 1.0},
	# --- v5: промежуточные состояния для плавных сценариев (WEATHER_SCENARIOS) ---
	# дымка: перистые, влажно, мутноватый горизонт
	&"hazy": {"cov": 0.45, "cirrus": 1.3, "fog": 0.0022, "rain": 0.0, "waves": 1.05, "sun": 0.85, "wind": 1.3, "wspd": 4.0, "storm": 0.0},
	# кучевые и порывы, птицы летают ниже
	&"gusty": {"cov": 0.7, "cirrus": 1.1, "fog": 0.0014, "rain": 0.0, "waves": 1.45, "sun": 0.72, "wind": 3.0, "wspd": 11.0, "storm": 0.18},
	# зыбь пришла раньше шторма: небо ещё ясное, ветра почти нет, волны выше
	&"swell": {"cov": 0.35, "cirrus": 1.2, "fog": 0.0009, "rain": 0.0, "waves": 1.9, "sun": 0.95, "wind": 1.2, "wspd": 3.5, "storm": 0.05},
	# перистые затягивают небо, вечером — красное небо
	&"cirrus": {"cov": 0.5, "cirrus": 2.2, "fog": 0.0012, "rain": 0.0, "waves": 2.1, "sun": 0.82, "wind": 2.2, "wspd": 6.5, "storm": 0.1},
	# шквал: тёмная стена, резкий порыв, ливень
	&"squall": {"cov": 1.0, "cirrus": 2.0, "fog": 0.007, "rain": 0.9, "waves": 2.8, "sun": 0.22, "wind": 10.0, "wspd": 26.0, "storm": 0.85},
	# жаркий штиль: почти без ветра, вода зеркальная, марево
	&"calm": {"cov": 0.18, "cirrus": 0.3, "fog": 0.0006, "rain": 0.0, "waves": 0.7, "sun": 1.05, "wind": 0.4, "wspd": 0.8, "storm": 0.0},
	# башня облаков перед коротким ливнем
	&"tower": {"cov": 0.85, "cirrus": 0.8, "fog": 0.0015, "rain": 0.0, "waves": 1.1, "sun": 0.6, "wind": 2.5, "wspd": 5.0, "storm": 0.12},
	# короткий тропический ливень
	&"downpour": {"cov": 1.0, "cirrus": 1.2, "fog": 0.006, "rain": 1.0, "waves": 1.3, "sun": 0.35, "wind": 3.0, "wspd": 8.0, "storm": 0.25},
	# затяжная морось
	&"drizzle": {"cov": 0.96, "cirrus": 1.2, "fog": 0.004, "rain": 0.28, "waves": 1.15, "sun": 0.48, "wind": 1.6, "wspd": 4.5, "storm": 0.05},
}
## v5: сценарии погоды — цепочки состояний с плавными переходами. [состояние, длительность с, переход с].
## Расписание известно заранее (forecast()) → предвестники бесплатно: зыбь до шторма, перистые, порывы.
## 1 реальная секунда = 1 игровая минута (сутки 24 мин).
const WEATHER_SCENARIOS: Dictionary = {
	&"shower": [[&"hazy", 240.0, 160.0], [&"gusty", 180.0, 120.0], [&"rain", 300.0, 70.0], [&"cloudy", 220.0, 150.0], [&"clear", 900.0, 200.0]],
	&"storm_front": [[&"swell", 300.0, 300.0], [&"cirrus", 240.0, 200.0], [&"gusty", 200.0, 150.0], [&"squall", 90.0, 35.0],
			[&"storm", 420.0, 60.0], [&"rain", 240.0, 150.0], [&"cloudy", 300.0, 200.0], [&"clear", 900.0, 240.0]],
	&"heat_shower": [[&"calm", 420.0, 220.0], [&"tower", 160.0, 150.0], [&"downpour", 110.0, 30.0], [&"clear", 700.0, 200.0]],
	&"night_fog": [[&"calm", 300.0, 200.0], [&"fog", 300.0, 240.0], [&"clear", 900.0, 300.0]],
	&"drizzle": [[&"cloudy", 300.0, 200.0], [&"drizzle", 600.0, 180.0], [&"cloudy", 300.0, 200.0], [&"clear", 900.0, 220.0]],
}
## Базовая «семья» состояния (для интерфейса и старого кода, который сравнивает с пятью погодами).
const WEATHER_KIND: Dictionary = {
	&"hazy": &"clear", &"swell": &"clear", &"calm": &"clear", &"cirrus": &"cloudy", &"gusty": &"cloudy",
	&"tower": &"cloudy", &"squall": &"storm", &"downpour": &"rain", &"drizzle": &"rain",
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
var _star_light: DirectionalLight3D
var _cloud_off := Vector2.ZERO
var _wfx_t := 0.0
var screen_fx: ScreenFx
var _rain_recent := 0.0
var _stars_t := 0.0
var rock_spray: RockSpray
var storm_debris: StormDebris
var _push := {}          # id -> Vector3 (сглаженная позиция для раздвигания растений)
var _scenario: StringName = &""
var _stage := -1
var _stage_blend := BLEND_TIME
## Мутность воды после шторма 0..1 (тает за несколько игровых часов).
var turbidity := 0.0
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
const AMBIENT_BASE := 0.9   # как в RenderProfile
## v5 свет: AgX вместо Filmic (без «пересвета» и кислотного неба днём, мягкие света), экспозиция под AgX.
const TONEMAP_EXPOSURE := 1.0
## Под пологом джунглей (интеграция v5): прямое солнце закрыто кроной, а GI/автоэкспозиции
## в gl_compatibility нет — без подсветки чаща днём почти чёрная. Плавный «полог» 0..1 по
## густоте джунглей под камерой: поднимаем рассеянный свет (зеленоватый отражённый от листвы)
## и чуть экспозицию (глаз привыкает). Чаща остаётся темнее пляжа, но читается.
const CANOPY_AMBIENT := 0.6      # + к энергии рассеянного света при полном пологе днём
const CANOPY_EXPOSURE := 0.25   # + к экспозиции (gl_compatibility; в Forward+ — треть, есть автоэкспозиция)
const CANOPY_SHADOW_LIFT := 0.25  # насколько светлеет тень кроны (доля прямого солнца сквозь листву)
var _canopy := 0.0
## Луна на 25% меньше стандартной Sky3D (0.07): в небе выглядела слишком крупной.
const MOON_SIZE := 0.0525
## Фаза луны задаётся датой (Sky3D считает небо по-настоящему): от зерна мира — разная в разных
## матчах; за матч (5 игровых суток) меняется заметно. 2026-01-03 — полнолуние.
const FULL_MOON_DAY := 3

func setup(start_hour: float = 8.5, seed_value: int = 4242) -> void:
	_rng.seed = seed_value
	_seed = seed_value
	_init_wind(seed_value)
	sky3d = Sky3D.new()
	sky3d.name = "Sky3D"
	add_child(sky3d)
	sky3d.minutes_per_day = MINUTES_PER_DAY
	sky3d.current_time = start_hour
	if sky3d.tod:
		# дата → фаза луны: 0..28 дней от полнолуния 3 января
		var off := posmod(seed_value * 7 + 11, 29)
		sky3d.tod.month = 1
		sky3d.tod.day = 1 + posmod(FULL_MOON_DAY - 1 + off, 29)
	if sky3d.sky:
		sky3d.sky.moon_size = MOON_SIZE
	# рассеянный свет ведёт SkyWeather._apply (каждый кадр) — твины Sky3D не должны его перетягивать
	sky3d.contribution_tween_time = 0.0
	sky3d.tonemap_exposure = TONEMAP_EXPOSURE
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
		StyleGrade.apply(_env, sky3d)   # единая цветокоррекция и автоэкспозиция (единый визуальный ряд)
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
	# звёздный свет: тусклый холодный свет сверху без теней в безлунную ясную ночь (новолуние —
	# темно, но силуэты, пена и песок читаются). Работает в обоих рендерах (ambient неба в compat
	# ночью почти нулевой).
	_star_light = DirectionalLight3D.new()
	_star_light.name = "StarLight"
	_star_light.light_color = Color(0.55, 0.66, 0.92)
	_star_light.shadow_enabled = false
	_star_light.light_energy = 0.0
	_star_light.visible = false
	_star_light.rotation = Vector3(deg_to_rad(-78.0), deg_to_rad(-30.0), 0.0)
	add_child(_star_light)
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
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
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

## Освещённая доля диска луны 0 (новолуние) .. 1 (полнолуние) — по взаимному положению солнца и луны.
func moon_illumination() -> float:
	if sky3d == null or sky3d.sun == null or sky3d.moon == null:
		return 0.5
	var to_sun := sky3d.sun.global_basis.z.normalized()
	var to_moon := sky3d.moon.global_basis.z.normalized()
	return clampf((1.0 - to_sun.dot(to_moon)) * 0.5, 0.0, 1.0)

## Сколько света даёт луна сейчас 0..1: фаза × высота над горизонтом (ночью; днём 0).
func moon_light() -> float:
	if sky3d == null or sky3d.moon == null:
		return 0.0
	var alt := sky3d.moon.global_basis.z.normalized().y
	return moon_illumination() * smoothstep(-0.02, 0.25, alt) * (1.0 - daylight())

func set_weather(w: StringName, instant: bool = false, auto: bool = true) -> void:
	if not WEATHERS.has(w):
		return
	_auto = auto
	_scenario = &""
	_stage = -1
	_stage_blend = BLEND_TIME
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
	# тени облаков (terrain_tropic): облачность и снос облаков по ветру (~скорость ветра у земли × 2)
	_cloud_off += _wind_dir * (_wind_speed * 2.0 + 2.0) * dt * 0.0045
	RenderingServer.global_shader_parameter_set(&"cloud_cover", clampf((float(_cur.get("cov", 0.38)) - 0.25) / 0.75, 0.0, 1.0))
	RenderingServer.global_shader_parameter_set(&"cloud_offset", _cloud_off)
	RenderingServer.global_shader_parameter_set(&"sun_day", daylight())
	# марево: высокое солнце, ясно, слабый ветер, сухо
	var hh := smoothstep(0.55, 0.9, sun_elevation()) * (1.0 - smoothstep(0.5, 0.8, float(_cur.get("cov", 0.4)))) \
			* (1.0 - smoothstep(4.0, 9.0, _wind_speed)) * (1.0 - _wetness)
	RenderingServer.global_shader_parameter_set(&"heat_haze", hh)

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
			_next_stage()
	# мутность: шторм взмучивает воду, после — оседает за ~5 игровых часов
	turbidity = maxf(turbidity - dt / 300.0, maxf(float(_cur.get("storm", 0.0)), float(_cur.get("rain", 0.0)) * 0.35))
	RenderingServer.global_shader_parameter_set(&"sea_turbidity", turbidity)
	RenderingServer.global_shader_parameter_set(&"storm_after", maxf(turbidity - float(_cur.get("storm", 0.0)), 0.0))
	if _blend < 1.0:
		_blend = minf(1.0, _blend + dt / maxf(_stage_blend, 1.0))
		var target: Dictionary = WEATHERS[weather]
		for k in target:
			_cur[k] = lerpf(float(_from.get(k, target[k])), float(target[k]), _blend)
	_update_wind(dt)
	_update_canopy(dt, cam)
	_wfx_t += dt
	if _wfx_t >= 0.2:
		_wfx_t = 0.0
		WindFx.update_all(get_tree(), _wind_dir, _wind_speed, _gust, maxf(_wetness, float(_cur.get("rain", 0.0))))
	_apply(dt)
	_cloud_t += dt
	if _cloud_t >= 0.1 and sky3d and sky3d.sky:
		sky3d.sky.process_tick(_cloud_t)
		_cloud_t = 0.0
	if cam:
		_update_underwater(cam.global_position.y < water_surface_at_cam - 0.05)
		if _underwater:
			_underwater_fog(cam.global_position.y, water_surface_at_cam)
		_update_screen_fx(dt, cam)
		_update_plant_push(dt, cam)
		if rock_spray == null:
			rock_spray = RockSpray.new()
			rock_spray.name = "RockSpray"
			add_child(rock_spray)
		if not _underwater:
			rock_spray.update_spray(dt, get_parent(), cam, float(_cur.get("storm", 0.0)))
		if storm_debris == null:
			storm_debris = StormDebris.new()
			storm_debris.name = "StormDebrisRoot"
			add_child(storm_debris)
		storm_debris.update_debris(dt, get_parent(), cam, float(_cur.get("storm", 0.0)))
		WetBody.update(get_tree(), dt, float(_cur.get("rain", 0.0)), daylight() * clampf(float(_cur.get("sun", 1.0)), 0.0, 1.0), _wind_speed, cam)
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

## Следующий этап сценария; сценарий кончился — выбрать новый (ночью чаще туман к утру).
func _next_stage() -> void:
	if _scenario == &"" or _stage + 1 >= (WEATHER_SCENARIOS[_scenario] as Array).size():
		_scenario = _pick_scenario()
		_stage = -1
	_stage += 1
	var st: Array = WEATHER_SCENARIOS[_scenario][_stage]
	_go(StringName(st[0]), float(st[1]) * _rng.randf_range(0.8, 1.25), float(st[2]))

func _go(w: StringName, dur: float, blend: float) -> void:
	_from = _cur.duplicate()
	var changed := w != weather
	weather = w
	_blend = 0.0
	_stage_blend = blend
	_left = dur
	if changed:
		weather_changed.emit(w)

func _pick_scenario() -> StringName:
	var h := time_of_day()
	var r := _rng.randf()
	if (h > 21.0 or h < 3.0) and r < 0.45:
		return &"night_fog"
	if h > 9.0 and h < 15.0 and r < 0.3:
		return &"heat_shower"
	r = _rng.randf()
	if r < 0.32:
		return &"shower"
	if r < 0.52:
		return &"storm_front"
	if r < 0.72:
		return &"drizzle"
	if r < 0.86:
		return &"heat_shower"
	return &"night_fog"

## Включить сценарий погоды сразу (полигон, тесты, события).
func start_scenario(name: StringName) -> void:
	if not WEATHER_SCENARIOS.has(name):
		return
	_auto = true
	_scenario = name
	_stage = -1
	_next_stage()

func scenario() -> StringName:
	return _scenario

## Прогноз: [{w, in_s, dur_s}] — текущее и следующие этапы до конца сценария (+ один следующий).
func forecast(max_items: int = 6) -> Array:
	var out: Array = [{"w": weather, "in_s": 0.0, "dur_s": _left}]
	if not _auto or _scenario == &"":
		return out
	var t := _left
	var arr: Array = WEATHER_SCENARIOS[_scenario]
	for i in range(_stage + 1, arr.size()):
		if out.size() >= max_items:
			break
		out.append({"w": arr[i][0], "in_s": t, "dur_s": float(arr[i][1])})
		t += float(arr[i][1])
	return out

## Семья погоды из пяти основных (clear/cloudy/rain/fog/storm).
func weather_kind() -> StringName:
	return WEATHER_KIND.get(weather, weather)

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
		# под пологом: свет, рассеянный кроной, — тень полога не сплошная (без GI в gl_compatibility
		# иначе под деревьями почти чернота)
		so *= 1.0 - CANOPY_SHADOW_LIFT * _canopy * daylight()
		if absf(sky3d.sun.shadow_opacity - so) > 0.01:
			sky3d.sun.shadow_opacity = so
	# луна сквозь тучи тоже не даёт резких теней (иначе на песке чёрные «кляксы»)
	if sky3d.moon:
		var mo := clampf(1.0 - 0.95 * float(_cur.rain) - 0.9 * float(_cur.get("storm", 0.0))
				- 0.6 * maxf(0.0, float(_cur.cov) - 0.6), 0.05, 1.0)
		if absf(sky3d.moon.shadow_opacity - mo) > 0.01:
			sky3d.moon.shadow_opacity = mo
	var rain := float(_cur.rain)
	var storm := float(_cur.get("storm", 0.0))
	if _env and not _underwater:
		var dl := daylight()
		var fog_day := Color(0.72, 0.8, 0.84).lerp(Color(0.55, 0.6, 0.64), clampf(rain, 0.0, 1.0))
		fog_day = fog_day.lerp(Color(0.36, 0.4, 0.45), smoothstep(0.4, 1.0, storm))
		# цветокоррекция: в шторм темнее, холоднее, менее насыщенно
		_env.adjustment_enabled = storm > 0.02 or rain > 0.02 or StyleGrade.active(_env)
		_env.adjustment_brightness = 1.0 - 0.1 * storm - 0.03 * rain + _flash * 0.12
		_env.adjustment_contrast = 1.0 + 0.06 * storm
		_env.adjustment_saturation = 1.0 - 0.32 * storm - 0.1 * rain
		# ночь под тучами: луна рассеивается в облаках — тусклый сине-серый минимум, чтобы
		# силуэты волн и островов читались и без молнии (молния — по-прежнему главный «показ»)
		var overcast := clampf(maxf(maxf(storm, rain * 0.8), (float(_cur.cov) - 0.6) * 1.5), 0.0, 1.0)
		var nk := (1.0 - dl) * overcast
		# тучи ночью подсвечены рассеянной луной/далёкими огнями — сине-серая «крыша»,
		# на её фоне читаются силуэты островов (а не чёрное в чёрном)
		var fog_night := Color(0.05, 0.07, 0.1).lerp(Color(0.21, 0.25, 0.31), overcast)
		_env.fog_light_color = fog_night.lerp(fog_day, dl)
		# небо ночью почти чёрное → рассеянный свет берём из «облачного» цвета и поднимаем
		# его энергию в пасмурную ночь: волны, пена, песок и силуэты видны без молнии
		# сумерки (солнце чуть ниже/выше горизонта): тёплый рассеянный свет неба, а не чёрная земля
		var el := sun_elevation()
		var tw := clampf(1.0 - absf(el + 0.03) / 0.13, 0.0, 1.0) * (1.0 - overcast * 0.6)
		# ясная ночь: свет зависит от луны (полнолуние — читаемо, новолуние — темно)
		var ml := moon_light()
		var night_k := (1.0 - dl) * (1.0 - overcast)
		_env.ambient_light_color = Color(0.17, 0.2, 0.26).lerp(Color(0.5, 0.38, 0.33), tw)
		# безлунная ясная ночь — звёздный свет: небо чёрное, поэтому рассеянный свет берём из цвета,
		# а не из неба (иначе земля в новолуние — сплошная чернота); силуэты и пена читаются
		var starlit := night_k * (1.0 - ml)
		if _star_light:
			var sl := starlit * 0.16 + night_k * ml * 0.03
			_star_light.light_energy = sl
			_star_light.visible = sl > 0.004
		_env.ambient_light_sky_contribution = (1.0 - 0.75 * maxf(nk, starlit * 0.85)) * (1.0 - 0.5 * tw)
		_env.ambient_light_energy = (AMBIENT_BASE + 1.6 * nk + 0.9 * tw) * lerpf(1.0, lerpf(0.75, 1.1, ml), night_k)
		# под пологом днём: отражённый от листвы рассеянный свет (зеленоватый) + привыкание глаз
		var ck := _canopy * dl
		if ck > 0.001:
			_env.ambient_light_energy += CANOPY_AMBIENT * ck
			_env.ambient_light_sky_contribution *= 1.0 - 0.45 * ck
			_env.ambient_light_color = _env.ambient_light_color.lerp(Color(0.42, 0.5, 0.36), 0.6 * ck)
		var ex := TONEMAP_EXPOSURE * (1.0 + CANOPY_EXPOSURE * ck * (1.0 if GraphicsQuality.is_compat() else 0.35))
		if absf(sky3d.tonemap_exposure - ex) > 0.003:
			sky3d.tonemap_exposure = ex
		# грейд в шторм затемнял ещё и ночь — ночью под тучами его ослабляем
		_env.adjustment_brightness += 0.14 * storm * nk + 0.08 * nk
		# погодный туман + граница «Дальности видимости» (дымка густеет до 100 % на её краю)
		ViewDistance.apply_fog(_env, float(_cur.fog))
		# в дождь/шторм небо затянуто: дымка заметно перекрывает небо (серое, а не чёрное)
		_env.fog_sky_affect = maxf(clampf(0.15 + float(_cur.fog) * 14.0 + 0.45 * storm + 0.25 * rain, 0.15, 0.9), ViewDistance.sky_affect_min())
		_env.fog_light_energy = 1.0 + _flash * 1.0

## Полог джунглей над камерой (0..1), сглаженно (~1,5 с — привыкание глаз).
func _update_canopy(dt: float, cam: Camera3D) -> void:
	var target := 0.0
	var w := get_parent()
	if cam and w and not _underwater:
		var zm: Variant = w.get(&"zones")
		if zm is ZoneMap:
			var cp := cam.global_position
			var z := zm as ZoneMap
			if z.inside(cp.x, cp.z):
				var gh := z.height_at(cp.x, cp.z)
				var above := cp.y - gh
				if above < 12.0:
					var jd := z.jungle_density(cp.x, cp.z)
					var zt := z.zone_at(cp.x, cp.z)
					var forest := 1.0 if zt == ZoneMap.Z_JUNGLE else (0.6 if zt == ZoneMap.Z_LOWLAND_FOREST else (0.5 if zt == ZoneMap.Z_MANGROVE else 0.0))
					target = clampf(maxf(jd, forest * 0.7) * forest, 0.0, 1.0) * clampf((12.0 - above) / 6.0, 0.0, 1.0)
	_canopy = move_toward(_canopy, target, dt / 1.5)

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
		_env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		_env.fog_density = 0.09
		_env.fog_sky_affect = 1.0
	else:
		_env.fog_sky_affect = 0.15
		_apply(0.0)

## Касание растений: три ближайших к камере персонажа/зверя → plant_push_a/b/c (позиция ног
## с небольшим запаздыванием — куст «догоняет» движение) и plant_trail_a/b/c (позиция ~0,4 с
## назад + сила покачивания). Шейдер отгибает от основания только те растения, которых касаются,
## а после прохода они коротко качаются и выпрямляются (shaders/plant_push.gdshaderinc).
var _trail := {}         # id -> Vector3 (сильно запаздывающая позиция для покачивания после прохода)

func _update_plant_push(dt: float, cam: Camera3D) -> void:
	var cands: Array = []
	var cp := cam.global_position
	for grp in [&"characters", &"animals"]:
		for n in get_tree().get_nodes_in_group(grp):
			var nd := n as Node3D
			if nd == null or not is_instance_valid(nd):
				continue
			var dd := nd.global_position.distance_squared_to(cp)
			if dd < 1600.0:
				cands.append([dd, nd])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var names := [&"plant_push_a", &"plant_push_b", &"plant_push_c"]
	var tnames := [&"plant_trail_a", &"plant_trail_b", &"plant_trail_c"]
	var seen := {}
	for i in 3:
		var v := Vector4.ZERO
		var tv := Vector4.ZERO
		if i < cands.size():
			var nd: Node3D = cands[i][1]
			var id := nd.get_instance_id()
			seen[id] = true
			var tgt := nd.global_position
			var cur: Vector3 = _push.get(id, tgt)
			cur = cur.lerp(tgt, 1.0 - exp(-dt * 10.0))
			_push[id] = cur
			var tr: Vector3 = _trail.get(id, tgt)
			tr = tr.lerp(tgt, 1.0 - exp(-dt * 2.5))
			_trail[id] = tr
			var r := 0.35 if nd.is_in_group(&"characters") else clampf(float(nd.get_meta(&"push_radius", 0.4)), 0.15, 1.5)
			v = Vector4(cur.x, cur.y, cur.z, r)
			# сила покачивания: есть, пока «хвост» не догнал персонажа (только что прошёл сквозь куст)
			var lagd := Vector2(tgt.x - tr.x, tgt.z - tr.z).length()
			tv = Vector4(tr.x, tr.y, tr.z, clampf(lagd / 0.5, 0.0, 1.0))
		RenderingServer.global_shader_parameter_set(names[i], v)
		RenderingServer.global_shader_parameter_set(tnames[i], tv)
	for id in _push.keys():
		if not seen.has(id):
			_push.erase(id)
			_trail.erase(id)

## Лучи солнца, ослепление, радуга (ScreenFx на камере).
func _update_screen_fx(dt: float, cam: Camera3D) -> void:
	if screen_fx == null:
		screen_fx = ScreenFx.new()
		screen_fx.name = "ScreenFx"
		add_child(screen_fx)
	if sky3d == null or sky3d.sun == null:
		return
	var sun_dir := sky3d.sun.global_basis.z.normalized()
	var rain := float(_cur.get("rain", 0.0))
	var cov := float(_cur.get("cov", 0.4))
	var sun_on := smoothstep(-0.02, 0.08, sun_dir.y) * clampf(float(_cur.get("sun", 1.0)), 0.0, 1.0) \
			* (1.0 - smoothstep(0.85, 1.0, cov)) * (1.0 - rain)
	# радуга: дождь недавно был и кончается, солнце за спиной не выше 42°, небо открыто
	_rain_recent = maxf(rain, _rain_recent - dt / 240.0)
	var rb := smoothstep(0.25, 0.6, _rain_recent) * (1.0 - smoothstep(0.05, 0.3, rain)) \
			* smoothstep(0.02, 0.1, sun_dir.y) * (1.0 - smoothstep(0.55, 0.67, sun_dir.y)) * (1.0 - smoothstep(0.8, 0.95, cov))
	screen_fx.rainbow_k = rb
	var clear_night := (1.0 - daylight()) * (1.0 - smoothstep(0.5, 0.75, cov)) * (1.0 - rain)
	screen_fx.night_clear = clear_night
	# Млечный Путь ярче в ясную безлунную ночь (луна засвечивает небо)
	_stars_t += dt
	if _stars_t > 1.0 and sky3d.sky:
		_stars_t = 0.0
		var a := lerpf(0.55, 1.0, clear_night * (1.0 - moon_light()))
		sky3d.sky.starmap_color = Color(0.78, 0.8, 0.86, a)
	var aiming := clampf((70.0 - cam.fov) / 35.0, 0.0, 1.0)
	screen_fx.update_fx(cam, sun_dir, sun_on, _underwater, aiming)

## Под водой (v5): видимость по мутности (после шторма/в дождь — 3–5 м, в ясную воду — 15–25 м),
## цвет поглощения по глубине (глубже — синее и темнее), ночью толща не светится сама —
## свет только от солнца/луны.
func _underwater_fog(cam_y: float, surf: float) -> void:
	var depth := maxf(surf - cam_y, 0.0)
	var light := maxf(daylight() * float(_cur.get("sun", 1.0)), maxf(moon_light() * 0.25, 0.015)) + _flash * 0.3
	var clear_c := Color(0.05, 0.3, 0.36).lerp(Color(0.02, 0.12, 0.26), clampf(depth / 18.0, 0.0, 1.0))
	var murk_c := Color(0.13, 0.25, 0.2)
	# мутность по зоне: мангры и устья — ил (3–5 м), лагуна — кристально (до ~25 м)
	var zt := turbidity
	var w := get_parent()
	var cam := get_viewport().get_camera_3d()
	if w and cam and w.has_method(&"zone_at"):
		var z: StringName = w.call(&"zone_at", cam.global_position.x, cam.global_position.z)
		if z == &"mangrove_water" or z == &"mangrove":
			zt = maxf(zt, 0.8)
		elif z == &"lagoon":
			zt *= 0.6
	_env.fog_light_color = clear_c.lerp(murk_c, zt) * clampf(light, 0.0, 1.0)
	_env.fog_light_energy = 1.0
	# плотность: видимость ~ 3/density м → ясно ~0.12 (≈25 м), муть ~0.7 (≈4 м)
	_env.fog_density = lerpf(0.12, 0.7, zt) * (1.0 + 0.4 * float(_cur.get("rain", 0.0)))

func is_underwater_view() -> bool:
	return _underwater

func _exit_tree() -> void:
	# мокрые StandardMaterial3D общие (кэши модулей) — вернуть сухими при выходе из матча
	WetMaterials.reset()
