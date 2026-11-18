class_name UnderwaterFX
extends CanvasLayer
## Подводный вид: когда камера ниже уровня воды — плотный сине-зелёный туман
## (скрывает дно вдали и небо), затемнение с глубиной, тонировка экрана, виньетка
## и пылинки-планктон у камеры. Над водой всё возвращается как было.

var sea: Node = null
var _rect: ColorRect
var _env: Environment = null
var _saved := {}
var _under := false
var _plankton: CPUParticles3D

func _ready() -> void:
	layer = 5
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform float depth = 0.0;
void fragment() {
	vec2 uv = UV - 0.5;
	float vig = smoothstep(0.25, 0.85, length(uv));
	vec3 tint = mix(vec3(0.05, 0.32, 0.36), vec3(0.01, 0.08, 0.14), clamp(depth / 14.0, 0.0, 1.0));
	COLOR = vec4(tint, 0.18 + vig * 0.35 + clamp(depth / 20.0, 0.0, 0.3));
}"""
	var m := ShaderMaterial.new()
	m.shader = sh
	_rect.material = m
	_rect.visible = false
	add_child(_rect)

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or sea == null:
		return
	var wy: float = sea.water_y()
	var cp := cam.global_position
	var depth := wy - cp.y
	var under := depth > 0.05
	if under != _under:
		_under = under
		_apply(under)
	if under:
		(_rect.material as ShaderMaterial).set_shader_parameter(&"depth", depth)
		if _env:
			# тропическая вода прозрачная: видно риф метров на 30
			_env.fog_density = 0.038 + clampf(depth / 15.0, 0.0, 1.0) * 0.03
			var c := Color(0.08, 0.36, 0.40).lerp(Color(0.02, 0.10, 0.16), clampf(depth / 14.0, 0.0, 1.0))
			_env.fog_light_color = c
		if _plankton:
			_plankton.global_position = cp

func _apply(under: bool) -> void:
	var w := get_viewport().find_world_3d()
	_env = w.environment if w else null
	var cam := get_viewport().get_camera_3d()
	if _env == null and cam:
		_env = cam.environment
	_rect.visible = under
	if _env:
		if under:
			_saved = {
				"fog_enabled": _env.fog_enabled, "fog_density": _env.fog_density,
				"fog_light_color": _env.fog_light_color, "fog_sky_affect": _env.fog_sky_affect,
				"fog_aerial": _env.fog_aerial_perspective,
			}
			_env.fog_enabled = true
			_env.fog_sky_affect = 1.0
			_env.fog_aerial_perspective = 0.0
		elif not _saved.is_empty():
			_env.fog_enabled = _saved["fog_enabled"]
			_env.fog_density = _saved["fog_density"]
			_env.fog_light_color = _saved["fog_light_color"]
			_env.fog_sky_affect = _saved["fog_sky_affect"]
			_env.fog_aerial_perspective = _saved["fog_aerial"]
	if under and _plankton == null:
		_plankton = CPUParticles3D.new()
		_plankton.amount = 120
		_plankton.lifetime = 6.0
		_plankton.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		_plankton.emission_sphere_radius = 6.0
		_plankton.gravity = Vector3(0, 0.02, 0)
		_plankton.initial_velocity_min = 0.0
		_plankton.initial_velocity_max = 0.08
		_plankton.scale_amount_min = 0.5
		_plankton.scale_amount_max = 1.0
		_plankton.local_coords = false
		# BILLBOARD_PARTICLES учитывает масштаб частиц (BILLBOARD_ENABLED его терял — квадраты по 1 м)
		var q := QuadMesh.new()
		q.size = Vector2(0.03, 0.03)
		var pm := Sea.soft_material(Color(0.85, 0.95, 0.9, 0.5))
		q.material = pm
		_plankton.mesh = q
		(sea as Node).add_child(_plankton)
	if _plankton:
		_plankton.emitting = under
		_plankton.visible = under
