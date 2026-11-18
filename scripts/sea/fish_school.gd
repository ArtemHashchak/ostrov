class_name FishSchool
extends MultiMeshInstance3D
## Стая рыб: MultiMesh + упрощённые boids (каждая рыба держит «место» в стае,
## стая плавно бродит вокруг точки, разлетается от акул и людей).
## Дальние стаи не рисуются и не симулируются.

const FISH_SHADER := preload("res://scripts/sea/shaders/fish.gdshader")
const PALETTES := [
	[Color(0.95, 0.75, 0.15), Color(0.2, 0.55, 0.85), Color(0.95, 0.95, 0.9)],   # жёлто-синие рифовые
	[Color(0.75, 0.78, 0.82), Color(0.6, 0.65, 0.72)],                            # серебристые (сардины)
	[Color(0.95, 0.45, 0.2), Color(0.98, 0.98, 0.95)],                             # оранжевые (клоуны)
	[Color(0.35, 0.7, 0.55), Color(0.2, 0.45, 0.6)],                               # зелёно-синие
]

@export var count: int = 36
@export var radius: float = 2.2          # размер стаи
@export var center: Vector3 = Vector3.ZERO  # точка, вокруг которой бродит стая
@export var roam: float = 10.0           # как далеко бродит от центра
@export var water_level: float = 0.0
@export var palette: int = 0
@export var fish_length: float = 0.3
@export var lod_distance: float = 90.0

## Высота дна под точкой (Callable(x, z) -> float); если пусто — дно не учитывается.
var floor_func: Callable

var _pos := Vector3.ZERO
var _vel := Vector3.ZERO
var _goal := Vector3.ZERO
var _offs: PackedVector3Array
var _phase: PackedFloat32Array
var _speed: PackedFloat32Array
var _fpos: PackedVector3Array
var _fdir: PackedVector3Array
var _scare := Vector3.ZERO
var _scare_t := 0.0
var _goal_t := 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	add_to_group(&"fish_schools")
	_rng.randomize()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = make_fish_mesh(fish_length)
	mm.instance_count = count
	multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = FISH_SHADER
	mat.set_shader_parameter(&"fish_length", fish_length)
	material_override = mat
	_pos = center
	_goal = center
	_offs.resize(count)
	_phase.resize(count)
	_speed.resize(count)
	_fpos.resize(count)
	_fdir.resize(count)
	var pal: Array = PALETTES[palette % PALETTES.size()]
	for i in count:
		_offs[i] = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.45, 0.45), _rng.randf_range(-1, 1)).normalized() * radius * pow(_rng.randf(), 0.5)
		_phase[i] = _rng.randf()
		_speed[i] = _rng.randf_range(0.8, 1.25)
		_fpos[i] = _pos + _offs[i]
		_fdir[i] = Vector3.FORWARD
		var c: Color = pal[_rng.randi() % pal.size()]
		c = c.lightened(_rng.randf_range(-0.1, 0.1))
		mm.set_instance_custom_data(i, Color(c.r, c.g, c.b, _phase[i]))
		mm.set_instance_transform(i, Transform3D(Basis(), _fpos[i]))

## Спугнуть стаю (акула, пловец, всплеск).
func scare(from: Vector3, strength: float = 1.0) -> void:
	var d := _pos - from
	d.y = 0.0
	if d.length() < 0.1:
		d = Vector3(1, 0, 0)
	_scare = d.normalized() * 5.0 * strength
	_scare_t = 2.5

func _physics_process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_to(_pos) > lod_distance:
		visible = false
		return
	visible = true
	_goal_t -= delta
	if _goal_t <= 0.0 or _pos.distance_to(_goal) < 1.5:
		_goal_t = _rng.randf_range(5.0, 12.0)
		_goal = center + Vector3(_rng.randf_range(-roam, roam), 0.0, _rng.randf_range(-roam, roam))
		_goal.y = _clamp_depth(_goal).y
	var want := (_goal - _pos).normalized() * 1.2
	if _scare_t > 0.0:
		_scare_t -= delta
		want += _scare * (_scare_t / 2.5)
	_vel = _vel.lerp(want, clampf(delta * 1.5, 0.0, 1.0))
	_pos += _vel * delta
	_pos = _clamp_depth(_pos)
	var spread := 1.0 + (_scare_t / 2.5) * 1.5
	var t := Time.get_ticks_msec() * 0.001
	var mm := multimesh
	for i in count:
		var o := _offs[i] * spread
		# «дыхание» строя
		o += Vector3(sin(t * 0.7 * _speed[i] + _phase[i] * 6.0), sin(t * 0.9 + _phase[i] * 4.0) * 0.3, cos(t * 0.6 * _speed[i] + _phase[i] * 5.0)) * 0.35
		var target := _pos + o
		var p := _fpos[i]
		var dv := target - p
		var step := dv * clampf(delta * 2.2 * _speed[i], 0.0, 1.0) + _vel * delta * 0.3
		p += step
		_fpos[i] = p
		var dir := _fdir[i].lerp(step.normalized() if step.length() > 0.0005 else _fdir[i], clampf(delta * 6.0, 0.0, 1.0))
		if dir.length() < 0.01:
			dir = Vector3.FORWARD
		dir = dir.normalized()
		_fdir[i] = dir
		var b := Basis.looking_at(dir, Vector3.UP)
		mm.set_instance_transform(i, Transform3D(b, p))

func _clamp_depth(p: Vector3) -> Vector3:
	var top := water_level - 0.6
	var bottom := water_level - 6.0
	if floor_func.is_valid():
		bottom = maxf(bottom, float(floor_func.call(p.x, p.z)) + 0.6)
	p.y = clampf(p.y, minf(bottom, top), top)
	return p

## Процедурная рыбка: веретено + хвост + спинной плавник. Нос в -Z.
static func make_fish_mesh(L: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 10
	var segs := 8
	for i in rings + 1:
		var t := float(i) / rings
		var z := -L * 0.5 + t * L * 0.82
		var r := sin(clampf(t, 0.02, 1.0) * PI) * 0.5 + 0.08
		if t > 0.85:
			r *= 0.5
		var hw := L * 0.07 * r * 1.2
		var hh := L * 0.17 * r
		for j in segs:
			var a := TAU * float(j) / segs - PI * 0.5
			var dorsal := 0.5 + 0.5 * sin(a)
			var stripe := 0.75 if (i == 4 or i == 6) else 1.0
			st.set_color(Color(dorsal, stripe, 0.0))
			st.add_vertex(Vector3(hw * cos(a), hh * sin(a), z))
	for i in rings:
		for j in segs:
			var a0 := i * segs + j
			var a1 := i * segs + (j + 1) % segs
			var b0 := (i + 1) * segs + j
			var b1 := (i + 1) * segs + (j + 1) % segs
			st.add_index(a0); st.add_index(b0); st.add_index(a1)
			st.add_index(a1); st.add_index(b0); st.add_index(b1)
	var n := (rings + 1) * segs
	# хвост (вилка)
	var tz := -L * 0.5 + L * 0.82
	var tail := [Vector3(0, 0, tz - L * 0.02), Vector3(0, L * 0.13, tz + L * 0.17), Vector3(0, 0.0, tz + L * 0.09), Vector3(0, -L * 0.13, tz + L * 0.17)]
	for p in tail:
		st.set_color(Color(0.6, 0.9, 0.0))
		st.add_vertex(p)
	st.add_index(n); st.add_index(n + 1); st.add_index(n + 2)
	st.add_index(n); st.add_index(n + 2); st.add_index(n + 3)
	# спинной плавник
	var d := [Vector3(0, L * 0.06, -L * 0.1), Vector3(0, L * 0.15, L * 0.02), Vector3(0, L * 0.06, L * 0.12)]
	for p in d:
		st.set_color(Color(1.0, 0.85, 0.0))
		st.add_vertex(p)
	st.add_index(n + 4); st.add_index(n + 5); st.add_index(n + 6)
	st.generate_normals()
	return st.commit()
