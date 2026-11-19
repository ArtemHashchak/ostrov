class_name CutsceneOcean
## СНИМОК генератора волн (2026-11-19, c012a36) для кат-сцен с видом сверху.
## Не меняется вместе с игровым океаном. См. tools/cutscene_waves/README.md.
extends MeshInstance3D
## Океан: сетка, плотная у камеры и разреженная к горизонту (до 6 км), следует за
## камерой с привязкой к ШАГУ сетки (вершины всегда в одних и тех же точках мира —
## иначе волна «переливается» при каждом сдвиге камеры).
##
## Волны (как в GTA V: устойчивая зыбь + ветровая рябь, без «мигания»):
##  * зыбь — 4 длинные волны Герстнера (λ 60–160 м, периоды 6–10 с) с общим
##    направлением (разброс ±20°); две ближайшие по длине дают биения —
##    «сеты» более высоких волн примерно раз в минуту;
##  * ветровое волнение — до 4 коротких волн (λ 11–38 м) по направлению ветра;
##    те, что короче 5 шагов сетки, — только в нормалях (без алиасинга вершин);
##  * параметры (сила, направление) меняются ПЛАВНО: сглаживание 40–120 с;
##    фазы считаются на CPU в double и передаются в шейдер (нет потери
##    точности float со временем);
##  * высокое/ультра: поверх — запечённая FFT-рябь (λ 1.5–24 м), только в
##    нормалях фрагмента, повёрнута по ветру; мелкая рябь — карты нормалей.
##  * шторм: волны ×3–5, барашки по якобиану Герстнера, полосы пены по ветру,
##    тёмная вода; нагон воды (water_level поднимается в мире — World._surge).
## wave_height на CPU — та же аналитическая сумма (с поправкой на горизонтальное
## смещение Герстнера), что сдвигает вершины.

const GRID_BY_Q: Array[int] = [110, 140, 180, 220]
## Сколько волн по пресету (низкое — без коротких ветровых).
const COMP_BY_Q: Array[int] = [5, 6, 8, 8]
var GRID := 180
const INNER := 330.0        # ширина плотной части, м
const REACH := 6000.0

## Волны: x — угол от направления (град), y — длина λ (м), z — базовая амплитуда (м),
## w — 0 зыбь (направление зыби) / 1 ветровая (направление ветра).
const COMPONENTS: Array[Vector4] = [
	Vector4(0.0, 160.0, 0.18, 0.0),
	Vector4(7.0, 128.0, 0.15, 0.0),    # биения с первой: сеты ~раз в 70 с
	Vector4(-14.0, 92.0, 0.10, 0.0),
	Vector4(19.0, 61.0, 0.065, 0.0),
	Vector4(10.0, 38.0, 0.11, 1.0),
	Vector4(-17.0, 25.0, 0.08, 1.0),
	Vector4(24.0, 16.5, 0.05, 1.0),
	Vector4(-22.0, 11.0, 0.03, 1.0),
]
const MAX_W := 8
const FFT_WIND := Vector2(1.0, 0.35)   # направление ветра, с которым запечена FFT

var water_mean := 0.0
var water_level := 0.0
var wave_scale := 1.0
var time_s := 0.0
var _mat: ShaderMaterial
var _depth_fn: Callable      # (x, z) -> высота рельефа
var _img: Image
var _area: Rect2
var quality := 2
## Качество снимка (0..3); по умолчанию — «ультра» (FFT-рябь, все волны).
var cutscene_quality := 3
var use_fft := false
var _fft_meta := {}
var _cam_xz := Vector2.ZERO
var n_comp := 8

# --- погода и ветер (цели и сглаженные значения) ---
var wind_dir := Vector2(1.0, 0.35).normalized()   # сглаженное направление ветра
var swell_dir := Vector2(1.0, 0.25).normalized()  # направление зыби (меняется медленнее)
var wind_speed := 3.0                              # ветер у поверхности, м/с (CONTRACT_WEATHER)
var storm := 0.0                                    # 0..1
var rain := 0.0
var _t_wind_dir := Vector2(1.0, 0.35).normalized()
var _t_wind_speed := 3.0
var _t_storm := 0.0
var _t_rain := 0.0
var _t_scale := 1.0
var _swell_amp := 1.0   # множитель зыби (сглажен)
var _sea_amp := 1.0     # множитель ветрового волнения (сглажен)
# --- рассчитанные на кадр волны (общие для CPU и шейдера) ---
var _wdir: Array[Vector2] = []
var _wk := PackedFloat64Array()
var _wom := PackedFloat64Array()
var _wamp := PackedFloat64Array()
var _wq := PackedFloat64Array()
var _wphase := PackedFloat64Array()
var _wvtx := PackedByteArray()
var _arr_a := PackedVector4Array()
var _arr_b := PackedVector4Array()
var _drove := false
## Опорная точка фаз (рядом с камерой). Фаза волны = k·dir·(p − origin) − φ.
## При повороте направления поле «вращается» вокруг этой точки — значит, у камеры
## гребни двигаются медленно (без «бега» волн вдали от начала координат мира).
## При переносе опоры φ компенсируется — поле не меняется.
var _origin := Vector2.ZERO
const ORIGIN_STEP := 160.0
var _had_drive := false

func build(terrain_height: Callable, area: Rect2) -> void:
	_depth_fn = terrain_height
	name = "Ocean"
	quality = clampi(cutscene_quality, 0, 3)
	GRID = GRID_BY_Q[clampi(quality, 0, 3)]
	mesh = _make_mesh()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16.0
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://tools/cutscene_waves/cutscene_ocean.gdshader") as Shader
	var tx := "res://tools/cutscene_waves/textures/"
	_mat.set_shader_parameter(&"normal_a", load(tx + "normal_a.jpg"))
	_mat.set_shader_parameter(&"normal_b", load(tx + "normal_b.jpg"))
	var foam_path := tx + "foam.png"
	if ResourceLoader.exists(foam_path):
		_mat.set_shader_parameter(&"foam_tex", load(foam_path))
	_init_waves()
	_make_spray()
	_bake_depth(area)
	_load_fft()
	_apply_quality()
	material_override = _mat

func set_quality(q: int) -> void:
	q = clampi(q, 0, 3)
	if q == quality:
		return
	quality = q
	if GRID != GRID_BY_Q[q]:
		GRID = GRID_BY_Q[q]
		mesh = _make_mesh()
	_apply_quality()
	_init_waves()

func _apply_quality() -> void:
	use_fft = quality >= 2 and not _fft_meta.is_empty()
	n_comp = COMP_BY_Q[clampi(quality, 0, 3)]
	_mat.set_shader_parameter(&"use_fft", use_fft)
	_mat.set_shader_parameter(&"detail_normals", quality >= 1)

## Атлас FFT-кадров -> Texture2DArray (слои с повтором и mip-картами) + высоты для CPU.
func _load_fft() -> void:
	var meta_path := "res://tools/cutscene_waves/fft_meta.gd"
	var atlas_path := "res://tools/cutscene_waves/fft_atlas.png"
	if not ResourceLoader.exists(meta_path) or not ResourceLoader.exists(atlas_path):
		return
	_fft_meta = (load(meta_path) as GDScript).get_script_constant_map().get("META", {})
	if _fft_meta.is_empty():
		return
	var tex := load(atlas_path) as Texture2D
	var atlas := tex.get_image() if tex else null
	if atlas == null:
		return
	if atlas.is_compressed():
		atlas.decompress()
	atlas.convert(Image.FORMAT_RGBA8)
	var n := int(_fft_meta.n)
	var cols := int(_fft_meta.cols)
	var layers: Array[Image] = []
	for f in int(_fft_meta.frames):
		var img := atlas.get_region(Rect2i((f % cols) * n, (f / cols) * n, n, n))
		img.generate_mipmaps()
		layers.append(img)
	var arr := Texture2DArray.new()
	arr.create_from_images(layers)
	_mat.set_shader_parameter(&"fft_tex", arr)
	_mat.set_shader_parameter(&"fft_frames", float(_fft_meta.frames))
	_mat.set_shader_parameter(&"fft_period", float(_fft_meta.period_s))
	_mat.set_shader_parameter(&"fft_tile", float(_fft_meta.tile_m))
	# наклон зыби, нормированный так, что 1.0 в текстуре ≈ реальный наклон плитки
	_mat.set_shader_parameter(&"fft_slope", float(_fft_meta.slope) * 0.32 / float(_fft_meta.height_m))

## Карта глубин: R — 0..30 м (грубо), G — −1..+3 м (точно, для пены у берега).
func _bake_depth(area: Rect2) -> void:
	# строки карты считаются параллельно (рельеф только читается)
	_bake_res = 2.5
	_bake_area = area
	_bake_w = int(area.size.x / _bake_res)
	var h := int(area.size.y / _bake_res)
	_bake_rows.clear()
	for j in h:
		_bake_rows.append({})
	var gid := WorkerThreadPool.add_group_task(_bake_row, h, -1, true, "ocean depth")
	WorkerThreadPool.wait_for_group_task_completion(gid)
	var bytes := PackedByteArray()
	for j in h:
		bytes.append_array(_bake_rows[j].px)
	_bake_rows.clear()
	var img := Image.create_from_data(_bake_w, h, false, Image.FORMAT_RGBA8, bytes)
	_img = img
	_area = area
	var tex := ImageTexture.create_from_image(img)
	_mat.set_shader_parameter(&"depth_map", tex)
	_mat.set_shader_parameter(&"map_origin", area.position)
	_mat.set_shader_parameter(&"map_size", area.size)
	_mat.set_shader_parameter(&"water_mean", water_mean)

var _bake_res := 2.5
var _bake_area := Rect2()
var _bake_w := 0
var _bake_rows: Array[Dictionary] = []

func _bake_row(j: int) -> void:
	var px := PackedByteArray()
	px.resize(_bake_w * 4)
	var z := _bake_area.position.y + (j + 0.5) * _bake_res
	for i in _bake_w:
		var x := _bake_area.position.x + (i + 0.5) * _bake_res
		var d := water_mean - float(_depth_fn.call(x, z))
		px[i * 4] = int(clampf(d / 30.0, 0.0, 1.0) * 255.0 + 0.5)
		px[i * 4 + 1] = int(clampf((d + 1.0) / 4.0, 0.0, 1.0) * 255.0 + 0.5)
		px[i * 4 + 2] = 0
		px[i * 4 + 3] = 255
	_bake_rows[j]["px"] = px

## Шаг плотной части сетки (м); на этот шаг привязана позиция сетки.
func inner_step() -> float:
	return INNER * 2.0 / float(GRID)

func _make_mesh() -> ArrayMesh:
	var n := GRID + 1
	var verts := PackedVector3Array()
	verts.resize(n * n)
	for j in n:
		for i in n:
			verts[j * n + i] = Vector3(_warp(float(i) / GRID * 2.0 - 1.0), 0.0, _warp(float(j) / GRID * 2.0 - 1.0))
	var idx := PackedInt32Array()
	for j in GRID:
		for i in GRID:
			var a := j * n + i
			idx.append_array([a, a + 1, a + n + 1, a, a + n + 1, a + n])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = idx
	var normals := PackedVector3Array()
	normals.resize(n * n)
	normals.fill(Vector3.UP)
	arr[Mesh.ARRAY_NORMAL] = normals
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.custom_aabb = AABB(Vector3(-REACH, -20.0, -REACH), Vector3(REACH * 2.0, 40.0, REACH * 2.0))
	return m

## Плотно в центре, быстро разрежается к краю (гладкая производная на стыке).
static func _warp(u: float) -> float:
	var a := absf(u)
	var half := INNER * 0.5
	var f: float
	if a <= 0.5:
		f = a * INNER
	else:
		var t := a - 0.5
		var c := (REACH - half - INNER * 0.5) / 0.125
		f = half + INNER * t + c * t * t * t
	return signf(u) * f


## Погода/ветер для волн (вызывать каждый кадр до update; без вызова — из wave_scale).
## dir — направление ветра в плоскости XZ; speed — ветер, м/с (штиль 2–4 … шторм 18–28);
## storm 0..1; rain 0..1.
func set_weather_drive(dir: Vector2, speed: float, storm_k: float, rain_k: float) -> void:
	if dir.length_squared() > 1e-6:
		_t_wind_dir = dir.normalized()
		if not _had_drive:   # первый вызов: сразу принять ветер (без поворота на старте)
			wind_dir = _t_wind_dir
			swell_dir = _t_wind_dir
			_had_drive = true
	_t_wind_speed = speed
	_t_storm = clampf(storm_k, 0.0, 1.0)
	_t_rain = clampf(rain_k, 0.0, 1.0)
	_drove = true

func _init_waves() -> void:
	_wdir.resize(MAX_W)
	_wk.resize(MAX_W)
	_wom.resize(MAX_W)
	_wamp.resize(MAX_W)
	_wq.resize(MAX_W)
	_wvtx.resize(MAX_W)
	_arr_a.resize(MAX_W)
	_arr_b.resize(MAX_W)
	if _wphase.size() != MAX_W:
		_wphase.resize(MAX_W)
		for i in MAX_W:   # разные начальные фазы, чтобы гребни не совпадали
			_wphase[i] = fposmod(i * 2.399963, TAU)
	var step := inner_step()
	for i in MAX_W:
		var c: Vector4 = COMPONENTS[i]
		_wk[i] = TAU / c.y
		_wom[i] = sqrt(9.81 * _wk[i])
		# вершины двигают только волны длиннее ~5 шагов сетки (иначе алиасинг —
		# «волна меняет направление»); короткие — только в нормалях фрагмента
		_wvtx[i] = 1 if c.y >= step * 5.0 else 0
	_recalc_waves(0.0)

## Направления, амплитуды, крутизна — из сглаженной погоды; фазы — интегрирование ω·dt.
func _recalc_waves(dt: float) -> void:
	var sw_ang := swell_dir.angle()
	var wd_ang := wind_dir.angle()
	var calm_q := lerpf(0.35, 0.92, storm)   # в шторм — острые гребни (≤1 — без петель)
	for i in MAX_W:
		var c: Vector4 = COMPONENTS[i]
		var base := wd_ang if c.w > 0.5 else sw_ang
		var a := base + deg_to_rad(c.x)
		_wdir[i] = Vector2(cos(a), sin(a))
		var amp := float(c.z) * (_sea_amp if c.w > 0.5 else _swell_amp)
		if i >= n_comp:
			amp = 0.0
		_wamp[i] = amp
		# крутизна Q·k·A на волну, сумма ≤ ~0.8 — без петель
		_wq[i] = clampf(calm_q / maxf(_wk[i] * amp * float(n_comp), 1e-4), 0.0, 1.0) if amp > 0.0 else 0.0
		_wphase[i] = fposmod(_wphase[i] + _wom[i] * dt, TAU)
		_arr_a[i] = Vector4(_wdir[i].x, _wdir[i].y, amp, _wk[i])
		_arr_b[i] = Vector4(_wphase[i], _wq[i], float(_wvtx[i]), 0.0)

# --- водяная пыль с гребней в шторм: несколько маленьких GPU-эмиттеров, которые
# раз в ~0.3 с переставляются на самые крутые гребни у камеры (CPU: 16 точек × до 8 волн).
## Брызги частицами по умолчанию выключены (пользователю не понравились «белые точки»).
const SPRAY_ENABLED := false
const SPRAY_N := 3
const SPRAY_PROBES := 16
var _sprays: Array[GPUParticles3D] = []
var _spray_t := 0.0
var _spray_seed := 0
var _spray_best := 0.0   # для тестов: сжатие лучшего гребня в пробах

func _make_spray() -> void:
	if not SPRAY_ENABLED:
		return
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.28)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.86, 0.9, 0.92, 1.0)
	var rad := GradientTexture2D.new()
	rad.fill = GradientTexture2D.FILL_RADIAL
	rad.fill_from = Vector2(0.5, 0.5)
	rad.fill_to = Vector2(1.0, 0.5)
	var g2 := Gradient.new()
	g2.set_color(0, Color(1, 1, 1, 0.38))
	g2.set_color(1, Color(1, 1, 1, 0.0))
	rad.gradient = g2
	m.albedo_texture = rad
	q.material = m
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.0))
	fade.add_point(0.12, Color(1, 1, 1, 0.6))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = fade
	for i in SPRAY_N:
		var sp := GPUParticles3D.new()
		sp.name = "StormSpray%d" % i
		sp.amount = 90
		sp.lifetime = 1.2
		sp.local_coords = false
		sp.emitting = false
		sp.visibility_aabb = AABB(Vector3(-25, -6, -25), Vector3(50, 16, 50))
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(5.0, 0.25, 1.2)   # вдоль гребня — длинно
		pm.direction = Vector3(1, 0.3, 0)
		pm.spread = 12.0
		pm.initial_velocity_min = 6.0
		pm.initial_velocity_max = 13.0
		pm.gravity = Vector3(0, -5.0, 0)
		pm.damping_min = 1.0
		pm.damping_max = 2.0
		pm.scale_min = 0.4
		pm.scale_max = 1.4
		pm.color_ramp = gt
		sp.process_material = pm
		sp.draw_pass_1 = q
		add_child(sp)
		sp.top_level = true
		_sprays.append(sp)

## Сжатие поверхности у гребня (0..1 от максимума) в точке — как crest_px в шейдере.
func _crest_j(p: Vector2) -> float:
	var j := 0.0
	var qs := 0.0001
	for i in n_comp:
		if _wamp[i] <= 0.0:
			continue
		var qq := maxf(_wq[i], 0.35)
		var s := sin(_wk[i] * _wdir[i].dot(p - _origin) - _wphase[i])
		j += qq * _wk[i] * _wamp[i] * s
		qs += qq * _wk[i] * _wamp[i]
	return j / qs

func _update_spray(dt: float, cam_pos: Vector3) -> void:
	if _sprays.is_empty():
		return
	var k := smoothstep(0.35, 0.9, storm) * (1.0 if quality >= 1 else 0.0)
	if k <= 0.01:
		for sp in _sprays:
			sp.emitting = false
		return
	_spray_t -= dt
	if _spray_t > 0.0:
		return
	_spray_t = 0.3
	# пробы на кольцах 6–40 м вокруг камеры (сдвиг по кругу каждый раз — разные точки)
	var cam := Vector2(cam_pos.x, cam_pos.z)
	var best: Array = []   # [j, Vector2]
	_spray_seed += 1
	for i in SPRAY_PROBES:
		var ang := TAU * (float(i) + fposmod(_spray_seed * 0.618, 1.0)) / float(SPRAY_PROBES)
		var r := 12.0 + 30.0 * fposmod(i * 0.381 + _spray_seed * 0.13, 1.0)   # не у самого лица
		var pt := cam + Vector2.from_angle(ang) * r
		best.append([_crest_j(pt), pt])
	best.sort_custom(func(a, b): return a[0] > b[0])
	var thr := lerpf(0.66, 0.36, storm)
	_spray_best = float(best[0][0]) if not best.is_empty() else 0.0
	var along := Vector2(wind_dir.y, -wind_dir.x)   # правая тройка: along × up = wind
	for i in _sprays.size():
		var sp := _sprays[i]
		var ok: bool = i < best.size() and float(best[i][0]) > thr
		sp.emitting = ok
		if not ok:
			continue
		sp.amount_ratio = k
		var pt: Vector2 = best[i][1]
		var h := wave_height(pt.x, pt.y)
		# эмиттер вытянут вдоль гребня (поперёк ветра)
		var basis := Basis(Vector3(along.x, 0, along.y), Vector3.UP, Vector3(wind_dir.x, 0, wind_dir.y))
		sp.global_transform = Transform3D(basis, Vector3(pt.x, h + 0.2, pt.y))
		var pm := sp.process_material as ParticleProcessMaterial
		pm.direction = Vector3(0, 0.3, 1)   # в локальных осях: +Z — по ветру

## Перенести опору фаз к камере (без изменения поля волн).
func _reanchor(cam: Vector2) -> void:
	if cam.distance_to(_origin) < ORIGIN_STEP:
		return
	var o := Vector2(snappedf(cam.x, ORIGIN_STEP), snappedf(cam.y, ORIGIN_STEP))
	var dlt := _origin - o
	for i in MAX_W:
		if _wdir.size() > i:
			_wphase[i] = fposmod(_wphase[i] + _wk[i] * _wdir[i].dot(dlt), TAU)
	_origin = o
	if _mat:
		_mat.set_shader_parameter(&"w_origin", _origin)

func _smooth_weather(dt: float, scale_waves: float) -> void:
	if not _drove:
		# без драйвера погоды: шторм и ветер из множителя волн погоды
		_t_storm = clampf((scale_waves - 1.3) / 1.7, 0.0, 1.0)
		_t_wind_speed = lerpf(3.0, 24.0, clampf((scale_waves - 0.8) / 2.2, 0.0, 1.0))
	_t_scale = scale_waves
	_drove = false
	var k40 := 1.0 - exp(-dt / 40.0)
	var k60 := 1.0 - exp(-dt / 60.0)
	var k120 := 1.0 - exp(-dt / 120.0)
	wind_speed = lerpf(wind_speed, _t_wind_speed, k40)
	storm = lerpf(storm, _t_storm, k60)
	rain = lerpf(rain, _t_rain, 1.0 - exp(-dt / 8.0))
	wave_scale = lerpf(wave_scale, _t_scale, k60)
	# ветер поворачивает за ~1–2 мин, зыбь ещё медленнее (за ~4 мин)
	wind_dir = Vector2.from_angle(lerp_angle(wind_dir.angle(), _t_wind_dir.angle(), k60))
	swell_dir = Vector2.from_angle(lerp_angle(swell_dir.angle(), wind_dir.angle(), 1.0 - exp(-dt / 240.0)))
	# медленная «погода моря»: иногда волны заметно выше (периоды 3–6 мин)
	var slow := 1.0 + 0.22 * sin(time_s / 211.0) + 0.14 * sin(time_s / 97.0 + 1.7)
	var t_swell := wave_scale * slow * lerpf(1.0, 1.35, storm)
	var t_sea := clampf(0.25 + wind_speed * 0.16, 0.3, 5.0)   # ясно ~0.8, шторм ~4.8
	_swell_amp = lerpf(_swell_amp, t_swell, k40)
	_sea_amp = lerpf(_sea_amp, t_sea, k40)
	if dt <= 0.0:
		_swell_amp = t_swell
		_sea_amp = t_sea

func update(dt: float, cam_pos: Vector3, level: float, scale_waves: float) -> void:
	_update(dt, cam_pos, level, scale_waves)
	# вызовы wave_height (плоты, плавание, боты, акулы) за прошлый кадр
	wave_calls_last = _wave_calls
	_wave_calls = 0

## Сколько раз за кадр спрашивали высоту волны (оверлей F3: «ocean_wave_h»).
var wave_calls_last := 0
var _wave_calls := 0

func _update(dt: float, cam_pos: Vector3, level: float, scale_waves: float) -> void:
	time_s += dt
	water_level = level
	_smooth_weather(dt, scale_waves)
	_reanchor(Vector2(cam_pos.x, cam_pos.z))
	_recalc_waves(dt)
	_update_spray(dt, cam_pos)
	var step := inner_step()
	global_position = Vector3(snappedf(cam_pos.x, step), 0.0, snappedf(cam_pos.z, step))
	# время для текстур (пена, рябь) — с переносом раз в 2 ч, чтобы не терять точность
	_mat.set_shader_parameter(&"u_time", fposmod(time_s, 7200.0))
	_mat.set_shader_parameter(&"water_level", water_level)
	_mat.set_shader_parameter(&"wave_scale", wave_scale)
	_mat.set_shader_parameter(&"storm", storm)
	_mat.set_shader_parameter(&"rain_amount", rain)
	_mat.set_shader_parameter(&"wind_dir", wind_dir)
	_mat.set_shader_parameter(&"wind_k", clampf(wind_speed / 25.0, 0.0, 1.0))
	_mat.set_shader_parameter(&"w_a", _arr_a)
	_mat.set_shader_parameter(&"w_b", _arr_b)
	# FFT-рябь повёрнута так, чтобы её «ветер» совпал с текущим
	var rot := wind_dir.angle() - FFT_WIND.angle()
	_mat.set_shader_parameter(&"fft_rot", Vector2(cos(rot), sin(rot)))
	_cam_xz = Vector2(cam_pos.x, cam_pos.z)
	_mat.set_shader_parameter(&"cam_xz", _cam_xz)

func set_night_tint(c: Color) -> void:
	_mat.set_shader_parameter(&"night_tint", Vector3(c.r, c.g, c.b))

## Высота поверхности воды в точке (волны + прилив/нагон) — как сдвигает вершины шейдер.
func wave_height(x: float, z: float) -> float:
	_wave_calls += 1
	return _wave_height(x, z)

## Горизонтальное смещение Герстнера (только волны, что двигают вершины).
func _gerstner_disp(p: Vector2) -> Vector2:
	var d := Vector2.ZERO
	for i in n_comp:
		if _wvtx[i] == 0 or _wamp[i] <= 0.0:
			continue
		var ph: float = _wk[i] * _wdir[i].dot(p - _origin) - _wphase[i]
		d += _wdir[i] * (_wq[i] * _wamp[i] * cos(ph))
	return d

func _wave_height(x: float, z: float) -> float:
	var depth := depth_at(x, z)
	var shoal := clampf(depth / 3.0, 0.15, 1.0)
	var p := Vector2(x, z)
	# вершина, что после смещения Герстнера оказалась над (x, z): одна итерация
	var p0 := p - _gerstner_disp(p)
	var h := 0.0
	for i in n_comp:
		if _wvtx[i] == 0:
			continue
		h += _wamp[i] * sin(_wk[i] * _wdir[i].dot(p0 - _origin) - _wphase[i])
	var dist := p.distance_to(_cam_xz)
	var vfade := 1.0 - smoothstep(260.0, 600.0, dist)
	return water_level + h * shoal * vfade

## Глубина под точкой так же, как её видит шейдер (карта + линейная фильтрация).
func depth_at(x: float, z: float) -> float:
	if _img == null:
		return water_level - float(_depth_fn.call(x, z))
	var u := (x - _area.position.x) / _area.size.x
	var v := (z - _area.position.y) / _area.size.y
	if u < 0.0 or v < 0.0 or u > 1.0 or v > 1.0:
		return 30.0
	var w := _img.get_width()
	var h := _img.get_height()
	var fx := u * w - 0.5
	var fy := v * h - 0.5
	var i0 := clampi(int(floor(fx)), 0, w - 1)
	var j0 := clampi(int(floor(fy)), 0, h - 1)
	var i1 := clampi(i0 + 1, 0, w - 1)
	var j1 := clampi(j0 + 1, 0, h - 1)
	var tx := clampf(fx - floor(fx), 0.0, 1.0)
	var ty := clampf(fy - floor(fy), 0.0, 1.0)
	var c := _img.get_pixel(i0, j0).lerp(_img.get_pixel(i1, j0), tx).lerp(_img.get_pixel(i0, j1).lerp(_img.get_pixel(i1, j1), tx), ty)
	var coarse := c.r * 30.0
	var fine := c.g * 4.0 - 1.0
	var d := coarse if coarse > 2.8 else fine
	return d + (water_level - water_mean)
