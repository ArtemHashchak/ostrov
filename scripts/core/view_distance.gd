class_name ViewDistance
extends RefCounted
## «Дальность видимости» — сколько метров вокруг себя видит игрок (настройка
## Settings.view_distance). Одна цифра согласованно управляет всем дальним:
##   • рельеф: дальние блоки суши и дно (TerrainChunks, группа vd_terrain);
##   • деревья: дальний LOD2 и «снимки»-импосторы (Flora, группы vd_tree_lod2/vd_tree_imp);
##   • предметы/постройки/звери без своей дальности (AutoLOD — не дальше этой границы);
##   • туман: на границе видимости он густеет до 100 % (глубинный режим), поэтому
##     обрез не читается «цилиндром» — дальние острова и море уходят в дымку.
## Камера по-прежнему видит до 20 км: небо и море до горизонта, просто дымка
## закрывает всё, что дальше выбранной дальности. Тени — отдельно, по пресету.
## «Дальность растений» (Settings.flora_distance) — множитель к GraphicsQuality.detail():
## трава, кусты, папоротник, ресурсы, мелкие предметы.

const MIN := 500.0
const SLIDER_MAX := 3500.0
## «Максимум»: дальние блоки рельефа и деревья-снимки без ограничения (до 6 км),
## туман — только погодный (как без этой настройки).
const MAXIMUM := 6000.0
## Значение слайдера ниже MIN — «авто» (по пресету графики), выше SLIDER_MAX — «Максимум».
const SLIDER_AUTO := 250.0
const SLIDER_MAXIMUM := 3750.0
## Значения «авто» по пресетам (низкое, среднее, высокое, ультра).
const PRESET_DEFAULT: Array[float] = [1000.0, 1800.0, 2800.0, 3500.0]

const G_TERRAIN := &"vd_terrain"
const G_TREE_LOD2 := &"vd_tree_lod2"
const G_TREE_IMP := &"vd_tree_imp"
const META_END := &"vd_end"     # «родная» дальность узла (без ограничения)

## Текущая дальность в метрах.
static func meters() -> float:
	var v := float(Settings.view_distance) if Settings else 0.0
	if v < MIN:
		return PRESET_DEFAULT[clampi(Settings.graphics_quality if Settings else 2, 0, 3)]
	if v > SLIDER_MAX + 1.0:
		return MAXIMUM
	return clampf(v, MIN, SLIDER_MAX)

static func is_max() -> bool:
	return meters() >= MAXIMUM - 1.0

## Подпись значения слайдера (SLIDER_AUTO … SLIDER_MAXIMUM).
static func slider_label(x: float) -> String:
	if x < MIN:
		return "авто · %d м" % int(PRESET_DEFAULT[clampi(Settings.graphics_quality, 0, 3)])
	if x > SLIDER_MAX + 1.0:
		return "Максимум"
	return "%d м" % int(round(x))

## Значение настройки → позиция слайдера.
static func to_slider(v: float) -> float:
	if v < MIN:
		return SLIDER_AUTO
	if v > SLIDER_MAX + 1.0:
		return SLIDER_MAXIMUM
	return v

## Грубая оценка нагрузки для подсказки у слайдера.
static func cost_hint(m: float = -1.0) -> String:
	if m < 0.0:
		m = meters()
	if m <= 1200.0:
		return "нагрузка: низкая"
	if m <= 2400.0:
		return "нагрузка: средняя"
	return "нагрузка: высокая"

static func flora_k() -> float:
	return clampf(float(Settings.flora_distance) if Settings else 1.0, 0.5, 2.0)

## Ограничить дальность узла выбранной дальностью видимости (с запасом margin),
## запомнив «родное» значение — повторные вызовы не накапливают обрезку.
static func cap(gi: GeometryInstance3D, native_end: float, group: StringName) -> void:
	gi.set_meta(META_END, native_end)
	gi.add_to_group(group)
	_apply_one(gi, group, meters())

static func _apply_one(gi: GeometryInstance3D, group: StringName, vd: float) -> void:
	var native := float(gi.get_meta(META_END, gi.visibility_range_end))
	match group:
		G_TERRAIN:
			# блоки/дно рисуются до vd (их «родная» дальность — Максимум)
			gi.visibility_range_end = minf(native, vd)
		G_TREE_LOD2:
			# дальний LOD деревьев (255–650 м): при короткой дальности растворяется к vd
			gi.visibility_range_end = minf(native, vd)
			gi.visibility_range_end_margin = 40.0 if vd < native else 0.0
		G_TREE_IMP:
			# снимки деревьев нужны только дальше LOD2; при vd ≤ начала снимков — выключены
			var begin := gi.visibility_range_begin
			var chunk := float(gi.get_meta(&"vd_chunk", 0.0))
			gi.visible = vd > begin + chunk * 0.72 + 40.0
			gi.visibility_range_end = minf(native, vd + chunk * 0.72)
			var m := gi.material_override as ShaderMaterial
			if m:
				# растворение снимков к границе видимости (дизер в шейдере)
				if vd >= MAXIMUM - 1.0:
					m.set_shader_parameter(&"fade_out", Vector2(1.0e8, 1.1e8))
				else:
					m.set_shader_parameter(&"fade_out", Vector2(vd * 0.86, vd))

## Пересчитать все зарегистрированные узлы (смена настройки — на лету).
static func apply(tree: SceneTree) -> void:
	if tree == null:
		return
	var vd := meters()
	for g in [G_TERRAIN, G_TREE_LOD2, G_TREE_IMP]:
		for n in tree.get_nodes_in_group(g):
			var gi := n as GeometryInstance3D
			if gi:
				_apply_one(gi, g, vd)

## Туман с учётом дальности видимости (вызывает SkyWeather вместо прямой записи
## fog_density). Погодный туман — экспоненциальный (fog_density). Если выбранная
## дальность ближе, чем «видимость» погоды (≈3/плотность), — глубинный режим: дымка
## доходит до 100 % ровно на границе дальности, так что обрез рельефа/деревьев не
## виден. Кривая плавно переходит от «экспоненты» (дальность ≈ погоде) к «чистый
## воздух вблизи, дымка у края» (дальность много короче погоды) — без скачка при смене погоды.
static var _sky_min := 0.0

## Минимальная доля тумана на небе для текущей дальности (SkyWeather берёт max с погодной).
static func sky_affect_min() -> float:
	return _sky_min

static func apply_fog(env: Environment, weather_density: float) -> void:
	if env == null:
		return
	var vd := meters()
	var wvis := 3.0 / maxf(weather_density, 1.0e-5)
	if is_max() or vd >= wvis * 1.25:
		env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		env.fog_density = weather_density
		env.fog_aerial_perspective = 0.5
		_sky_min = 0.0
		return
	var t := clampf((wvis / vd - 1.0) / 2.0, 0.0, 1.0)
	# короткая дальность: дымка берёт цвет неба у горизонта (aerial perspective) и
	# частично закрывает само небо — иначе на границе виден серый «забор» под ярким небом
	var near_k := clampf((2500.0 - vd) / 1900.0, 0.0, 1.0)
	env.fog_aerial_perspective = lerpf(0.5, 0.95, near_k)
	_sky_min = lerpf(0.15, 0.6, near_k)
	# цвет дымки — к голубому горизонту той же яркости (на случай, когда рендер не
	# окрашивает туман небом: Compatibility); ночью/в шторм яркость остаётся прежней
	var fc := env.fog_light_color
	var lum := fc.get_luminance()
	var horizon := Color(0.66, 0.78, 0.92)
	var hz := horizon * (lum / maxf(horizon.get_luminance(), 0.001))
	env.fog_light_color = fc.lerp(Color(hz.r, hz.g, hz.b, fc.a), 0.55 * near_k)
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_density = 1.0
	env.fog_depth_begin = 0.0
	env.fog_depth_end = minf(vd, wvis * 1.25)
	env.fog_depth_curve = lerpf(0.55, 1.8, t)

## Плотность тумана, эквивалентная текущему режиму (для отчётов/тестов).
static func describe(env: Environment) -> String:
	if env == null:
		return "-"
	if env.fog_mode == Environment.FOG_MODE_DEPTH:
		return "глубинный 0–%d м, кривая %.2f" % [int(env.fog_depth_end), env.fog_depth_curve]
	return "экспоненциальный %.4f" % env.fog_density
