class_name SeaFX
extends Node3D
## Подводные эффекты, которые работают и в gl_compatibility:
## - каустика на дне вокруг камеры (сетка по рельефу дна, пересчёт при сдвиге на 8 м);
## - лучи света сквозь воду, когда камера под водой;
## - пузыри у ныряющих персонажей (выдох раз в несколько секунд).

const CAUSTICS_SHADER := preload("res://scripts/sea/shaders/caustics.gdshader")
const GRID_HALF := 28.0
const GRID_STEP := 2.0
const RESAMPLE := 8.0

var sea: Node = null
var _caus: MeshInstance3D
var _caus_mat: ShaderMaterial
var _grid_c := Vector3(INF, 0, INF)
var _rays: Array[MeshInstance3D] = []
var _ray_shader_mat: ShaderMaterial
var _bubble_t: Dictionary = {}
var _bubble_mesh: QuadMesh
var _rng := RandomNumberGenerator.new()
var _t := 0.0

func _ready() -> void:
	_rng.randomize()
	_caus = MeshInstance3D.new()
	_caus.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_caus_mat = ShaderMaterial.new()
	_caus_mat.shader = CAUSTICS_SHADER
	_caus_mat.set_shader_parameter(&"grid_half", GRID_HALF)
	_caus.material_override = _caus_mat
	_caus.top_level = true
	add_child(_caus)
	# лучи: мягкие вертикальные полосы, всегда лицом к камере по Y
	var rsh := Shader.new()
	rsh.code = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform float strength = 0.12;
void vertex() {
	// поворот к камере вокруг Y
	vec3 cam = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	vec2 d = normalize(cam.xz + vec2(0.0001));
	VERTEX = vec3(VERTEX.x * d.y, VERTEX.y, -VERTEX.x * d.x);
}
void fragment() {
	float x = abs(UV.x - 0.5) * 2.0;
	float side = pow(1.0 - clamp(x, 0.0, 1.0), 2.2);
	float v = smoothstep(0.0, 0.12, UV.y) * (1.0 - smoothstep(0.35, 1.0, UV.y));
	float flick = 0.75 + 0.25 * sin(TIME * 0.8 + NODE_POSITION_WORLD.x);
	ALBEDO = vec3(0.65, 0.95, 0.9) * side * v * strength * flick;
}"""
	_ray_shader_mat = ShaderMaterial.new()
	_ray_shader_mat.shader = rsh
	for i in 7:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(_rng.randf_range(0.8, 2.2), 12.0)
		mi.mesh = q
		mi.material_override = _ray_shader_mat
		mi.extra_cull_margin = 3.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.top_level = true
		mi.visible = false
		add_child(mi)
		_rays.append(mi)
	_bubble_mesh = QuadMesh.new()
	_bubble_mesh.size = Vector2(1, 1)
	var bm := Sea.soft_material(Color(0.85, 0.95, 1.0, 0.7))
	_bubble_mesh.material = bm

func _wy() -> float:
	return float(sea.call(&"water_y")) if sea else 0.0

func _process(delta: float) -> void:
	if sea == null:
		return
	_t += delta
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	var wy := _wy()
	_caus_mat.set_shader_parameter(&"water_level", wy)
	var sun := 1.0
	var w: Node = sea.get(&"world")
	if w and w.has_method(&"is_night") and bool(w.call(&"is_night")):
		sun = 0.15
	_caus_mat.set_shader_parameter(&"sun", sun)
	# каустика — только если камера не слишком высоко над водой
	var show := cp.y - wy < 35.0
	_caus.visible = show
	if show and Vector2(cp.x - _grid_c.x, cp.z - _grid_c.z).length() > RESAMPLE:
		_rebuild_grid(cp)
	# лучи под водой
	var under := cp.y < wy - 0.05
	for i in _rays.size():
		var r := _rays[i]
		r.visible = under and sun > 0.5
		if r.visible:
			var a := TAU * i / _rays.size() + _t * 0.03 + i * 0.7
			var d := 4.0 + float(i % 3) * 3.5
			var h := 12.0
			r.global_position = Vector3(cp.x + cos(a) * d, wy - h * 0.5 + 0.2, cp.z + sin(a) * d)
			r.rotation = Vector3.ZERO
	# пузыри у ныряльщиков
	for n in get_tree().get_nodes_in_group(&"characters"):
		var ch := n as Node3D
		if ch == null:
			continue
		var head := ch.global_position + Vector3(0, 1.5, 0)
		if ch.has_method(&"get_eye_position"):
			head = ch.call(&"get_eye_position")
		if head.y > wy - 0.15 or head.distance_to(cp) > 40.0:
			continue
		var id := ch.get_instance_id()
		var nt: float = _bubble_t.get(id, 0.0)
		if _t >= nt:
			_bubble_t[id] = _t + _rng.randf_range(2.5, 4.5)
			bubbles(head + (-ch.global_basis.z) * 0.15, 10, wy)

## Струйка пузырей из точки к поверхности.
func bubbles(pos: Vector3, amount: int = 10, wy: float = NAN) -> void:
	if is_nan(wy):
		wy = _wy()
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = clampf((wy - pos.y) / 1.2, 0.6, 4.0)
	p.explosiveness = 0.6
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 1.5
	p.gravity = Vector3(0, 0.6, 0)
	p.scale_amount_min = 0.025
	p.scale_amount_max = 0.07
	p.mesh = _bubble_mesh
	p.local_coords = false
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.5).timeout.connect(p.queue_free)

func _rebuild_grid(cp: Vector3) -> void:
	var c := Vector3(snappedf(cp.x, GRID_STEP), 0.0, snappedf(cp.z, GRID_STEP))
	_grid_c = c
	_caus_mat.set_shader_parameter(&"grid_center", c)
	var n := int(GRID_HALF * 2.0 / GRID_STEP)
	var wy := _wy()
	var hs := PackedFloat32Array()
	hs.resize((n + 1) * (n + 1))
	var any_water := false
	for i in n + 1:
		for j in n + 1:
			var x := c.x - GRID_HALF + j * GRID_STEP
			var z := c.z - GRID_HALF + i * GRID_STEP
			var h: float = sea.call(&"floor_at", x, z)
			hs[i * (n + 1) + j] = h
			if h < wy - 0.05:
				any_water = true
	if not any_water:
		_caus.mesh = null
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		for j in n:
			var h00 := hs[i * (n + 1) + j]
			var h01 := hs[i * (n + 1) + j + 1]
			var h10 := hs[(i + 1) * (n + 1) + j]
			var h11 := hs[(i + 1) * (n + 1) + j + 1]
			if minf(minf(h00, h01), minf(h10, h11)) > wy:
				continue
			var x0 := c.x - GRID_HALF + j * GRID_STEP
			var z0 := c.z - GRID_HALF + i * GRID_STEP
			var p00 := Vector3(x0, h00 + 0.07, z0)
			var p01 := Vector3(x0 + GRID_STEP, h01 + 0.07, z0)
			var p10 := Vector3(x0, h10 + 0.07, z0 + GRID_STEP)
			var p11 := Vector3(x0 + GRID_STEP, h11 + 0.07, z0 + GRID_STEP)
			st.add_vertex(p00)
			st.add_vertex(p01)
			st.add_vertex(p11)
			st.add_vertex(p00)
			st.add_vertex(p11)
			st.add_vertex(p10)
	_caus.mesh = st.commit()
	_caus.global_transform = Transform3D.IDENTITY
