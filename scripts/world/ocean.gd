class_name Ocean
extends MeshInstance3D
## Океан: сетка, плотная у камеры (1.5 м) и разреженная к горизонту (до 6 км),
## следует за камерой с привязкой к шагу сетки. Волны — та же формула, что в
## шейдере ocean.gdshader (wave_height совпадает в радиусе ~250 м от камеры).
##
## Дёшево и красиво (по пресету Settings.graphics_quality):
##  * низкое/среднее — 4 волны Герстнера + рябь из карты нормалей;
##  * высокое/ультра — поверх них запечённая зацикленная FFT-зыбь (Тессендорф,
##    tools/bake_ocean_fft.py → assets/ocean/fft_atlas.png): шейдер только
##    листает кадры текстуры, симуляции во время игры нет. Мелкая зыбь двигает
##    вершины у камеры (wave_height на CPU читает те же кадры), даёт нормали,
##    барашки по якобиану.
##  * число вершин сетки зависит от пресета (GRID_BY_Q).

const GRID_BY_Q: Array[int] = [110, 140, 180, 220]
const FFT_FADE_START := 70.0     # где зыбь в вершинах начинает гаснуть, м
const FFT_FADE_END := 150.0
const FFT_AMP := 0.32            # макс. добавка высоты от зыби, м (при wave_scale 1)
var GRID := 180
const INNER := 330.0        # ширина плотной части, м
const REACH := 6000.0
const SNAP := 1.5

const WAVES: Array[Vector4] = [
	Vector4(1.0, 0.3, 0.18, 22.0),
	Vector4(0.6, 1.0, 0.12, 13.0),
	Vector4(-0.4, 0.9, 0.07, 7.5),
	Vector4(0.9, -0.5, 0.05, 4.5),
]

var water_mean := 0.0
var water_level := 0.0
var wave_scale := 1.0
var time_s := 0.0
var _mat: ShaderMaterial
var _depth_fn: Callable      # (x, z) -> высота рельефа
var _img: Image
var _area: Rect2
var quality := 2
var use_fft := false
var _fft_meta := {}
var _fft_h: Array[PackedByteArray] = []   # высоты кадров (B-канал) для wave_height
var _fft_n := 128
var _cam_xz := Vector2.ZERO

func build(terrain_height: Callable, area: Rect2) -> void:
	_depth_fn = terrain_height
	name = "Ocean"
	quality = Settings.graphics_quality if Settings else 2
	GRID = GRID_BY_Q[clampi(quality, 0, 3)]
	mesh = _make_mesh()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16.0
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://scripts/world/shaders/ocean.gdshader") as Shader
	var lesusx := "res://addons/ostrova_water/lesusx_gerstner/textures/"
	_mat.set_shader_parameter(&"normal_a", load(lesusx + "Water 0339normal.jpg"))
	_mat.set_shader_parameter(&"normal_b", load(lesusx + "water 0342normal.jpg"))
	var foam_path := "res://addons/ostrova_water/antz_foam_water/textures/water_foam.png"
	if ResourceLoader.exists(foam_path):
		_mat.set_shader_parameter(&"foam_tex", load(foam_path))
	_mat.set_shader_parameter(&"wave_a", WAVES[0])
	_mat.set_shader_parameter(&"wave_b", WAVES[1])
	_mat.set_shader_parameter(&"wave_c", WAVES[2])
	_mat.set_shader_parameter(&"wave_d", WAVES[3])
	_bake_depth(area)
	_load_fft()
	_apply_quality()
	material_override = _mat
	if Settings and not Settings.graphics_changed.is_connected(_on_graphics_changed):
		Settings.graphics_changed.connect(_on_graphics_changed)

func _on_graphics_changed() -> void:
	var q := clampi(Settings.graphics_quality, 0, 3)
	if q == quality:
		return
	quality = q
	if GRID != GRID_BY_Q[q]:
		GRID = GRID_BY_Q[q]
		mesh = _make_mesh()
	_apply_quality()

func _apply_quality() -> void:
	use_fft = quality >= 2 and not _fft_h.is_empty()
	_mat.set_shader_parameter(&"use_fft", use_fft)
	_mat.set_shader_parameter(&"detail_normals", quality >= 1)

## Атлас FFT-кадров -> Texture2DArray (слои с повтором и mip-картами) + высоты для CPU.
func _load_fft() -> void:
	var meta_path := "res://assets/ocean/fft_meta.json"
	var atlas_path := "res://assets/ocean/fft_atlas.png"
	if not FileAccess.file_exists(meta_path) or not ResourceLoader.exists(atlas_path):
		return
	_fft_meta = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
	var tex := load(atlas_path) as Texture2D
	var atlas := tex.get_image() if tex else null
	if atlas == null:
		return
	if atlas.is_compressed():
		atlas.decompress()
	atlas.convert(Image.FORMAT_RGBA8)
	var n := int(_fft_meta.n)
	_fft_n = n
	var cols := int(_fft_meta.cols)
	var layers: Array[Image] = []
	_fft_h.clear()
	for f in int(_fft_meta.frames):
		var img := atlas.get_region(Rect2i((f % cols) * n, (f / cols) * n, n, n))
		var data := img.get_data()
		var hb := PackedByteArray()
		hb.resize(n * n)
		for i in n * n:
			hb[i] = data[i * 4 + 2]
		_fft_h.append(hb)
		img.generate_mipmaps()
		layers.append(img)
	var arr := Texture2DArray.new()
	arr.create_from_images(layers)
	_mat.set_shader_parameter(&"fft_tex", arr)
	_mat.set_shader_parameter(&"fft_frames", float(_fft_meta.frames))
	_mat.set_shader_parameter(&"fft_period", float(_fft_meta.period_s))
	_mat.set_shader_parameter(&"fft_tile", float(_fft_meta.tile_m))
	_mat.set_shader_parameter(&"fft_slope", float(_fft_meta.slope) * FFT_AMP / float(_fft_meta.height_m))
	_mat.set_shader_parameter(&"fft_amp", FFT_AMP)
	_mat.set_shader_parameter(&"fft_fade", Vector2(FFT_FADE_START, FFT_FADE_END))

## Высота зыби (−1..1, без масштаба) в точке — та же выборка, что в шейдере.
func _fft_sample(x: float, z: float) -> float:
	var n := _fft_n
	var tile := float(_fft_meta.tile_m)
	var frames := _fft_h.size()
	var ft := fposmod(time_s / float(_fft_meta.period_s), 1.0) * frames
	var f0 := int(ft) % frames
	var f1 := (f0 + 1) % frames
	var fw := ft - floorf(ft)
	var fx := fposmod(x / tile, 1.0) * n - 0.5
	var fy := fposmod(z / tile, 1.0) * n - 0.5
	var i0 := posmod(int(floorf(fx)), n)
	var j0 := posmod(int(floorf(fy)), n)
	var i1 := (i0 + 1) % n
	var j1 := (j0 + 1) % n
	var tx := fx - floorf(fx)
	var ty := fy - floorf(fy)
	var r := 0.0
	for k in 2:
		var hb: PackedByteArray = _fft_h[f0 if k == 0 else f1]
		var a := lerpf(hb[j0 * n + i0], hb[j0 * n + i1], tx)
		var b := lerpf(hb[j1 * n + i0], hb[j1 * n + i1], tx)
		var v := lerpf(a, b, ty) / 255.0 * 2.0 - 1.0
		r += v * (1.0 - fw if k == 0 else fw)
	return r

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

func update(dt: float, cam_pos: Vector3, level: float, scale_waves: float) -> void:
	time_s += dt
	water_level = level
	wave_scale = scale_waves
	global_position = Vector3(snappedf(cam_pos.x, SNAP), 0.0, snappedf(cam_pos.z, SNAP))
	_mat.set_shader_parameter(&"u_time", time_s)
	_mat.set_shader_parameter(&"water_level", water_level)
	_mat.set_shader_parameter(&"wave_scale", wave_scale)
	_cam_xz = Vector2(cam_pos.x, cam_pos.z)
	_mat.set_shader_parameter(&"cam_xz", _cam_xz)

func set_night_tint(c: Color) -> void:
	_mat.set_shader_parameter(&"night_tint", Vector3(c.r, c.g, c.b))

## Высота поверхности воды в точке (волны + прилив) — как в шейдере.
func wave_height(x: float, z: float) -> float:
	var depth := depth_at(x, z)
	var shoal := clampf(depth / 3.0, 0.15, 1.0)
	var h := 0.0
	var p := Vector2(x, z)
	for w in WAVES:
		var d := Vector2(w.x, w.y).normalized()
		var k := TAU / w.w
		var om := sqrt(9.81 * k)
		h += w.z * sin(k * d.dot(p) - om * time_s)
	var dist := p.distance_to(_cam_xz)
	var vfade := 1.0 - smoothstep(260.0, 600.0, dist)
	h *= vfade
	if use_fft:
		var ff := 1.0 - smoothstep(FFT_FADE_START, FFT_FADE_END, dist)
		if ff > 0.0:
			h += _fft_sample(x, z) * FFT_AMP * ff
	return water_level + h * wave_scale * shoal

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
