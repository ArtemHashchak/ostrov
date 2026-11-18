class_name Ocean
extends MeshInstance3D
## Океан: сетка, плотная у камеры (1.5 м) и разреженная к горизонту (до 6 км),
## следует за камерой с привязкой к шагу сетки. Волны — та же формула, что в
## шейдере ocean.gdshader (wave_height совпадает в радиусе ~250 м от камеры).

const GRID := 180
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

func build(terrain_height: Callable, area: Rect2) -> void:
	_depth_fn = terrain_height
	name = "Ocean"
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
	material_override = _mat

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
	_mat.set_shader_parameter(&"cam_xz", Vector2(cam_pos.x, cam_pos.z))

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
