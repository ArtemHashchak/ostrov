class_name ScreenFx
extends MeshInstance3D
## Экранные эффекты v5 (агент D): лучи солнца (сквозь кроны и под водой), ослепление солнцем,
## радуга после дождя. Один квад, прибавляет свет к кадру (screen_fx.gdshader). Управляет SkyWeather.
## Качество: лучи — Высокое (16 выборок) / Ультра (24); ослепление и радуга — на всех пресетах.

var _mat: ShaderMaterial
var rainbow_k := 0.0          # 0..1, считается SkyWeather (после дождя + солнце за спиной)

func _ready() -> void:
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mesh = q
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://scripts/world/weather/screen_fx.gdshader")
	_mat.render_priority = 120
	material_override = _mat
	extra_cull_margin = 16384.0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ignore_occlusion_culling = true
	visible = false

## sun_dir — мировое направление НА солнце; sun_on 0..1 (над горизонтом, не за тучами).
func update_fx(cam: Camera3D, sun_dir: Vector3, sun_on: float, underwater: bool, aiming: float) -> void:
	if cam == null or _mat == null:
		visible = false
		return
	if get_parent() != cam:
		if get_parent():
			get_parent().remove_child(self)
		cam.add_child(self)
		position = Vector3(0, 0, -0.5)
	var q := Settings.graphics_quality
	var fwd := -cam.global_basis.z
	var facing := fwd.dot(sun_dir)
	var sun_vis := 0.0
	var suv := Vector2(0.5, -1.0)
	if facing > 0.05 and sun_on > 0.01:
		var sp := cam.global_position + sun_dir * 1000.0
		if not cam.is_position_behind(sp):
			suv = cam.unproject_position(sp) / Vector2(get_viewport().get_visible_rect().size)
			sun_vis = sun_on * smoothstep(0.05, 0.5, facing)
	# лучи: только Высокое+, сильнее под водой и в утренней дымке
	var shafts := 0.0
	if q >= 2:
		shafts = (0.55 if not underwater else 0.9) * sun_vis
	# ослепление: взгляд почти на солнце (≤ ~20°), сильнее в прицеле (оптика собирает свет)
	var glare := smoothstep(0.93, 0.995, facing) * sun_on * (0.55 + 0.45 * aiming) * (0.0 if underwater else 1.0)
	var rb := rainbow_k if not underwater else 0.0
	visible = shafts > 0.01 or glare > 0.01 or rb > 0.01
	if not visible:
		return
	_mat.set_shader_parameter(&"sun_uv", suv)
	_mat.set_shader_parameter(&"sun_vis", sun_vis)
	_mat.set_shader_parameter(&"shafts", shafts)
	_mat.set_shader_parameter(&"shaft_samples", 24 if q >= 3 else 16)
	_mat.set_shader_parameter(&"glare", glare)
	_mat.set_shader_parameter(&"rainbow", rb)
	_mat.set_shader_parameter(&"anti_sun", -sun_dir)
	_mat.set_shader_parameter(&"underwater", 1.0 if underwater else 0.0)

## Ослепление сейчас 0..1 (для механики: прицел дрожит/хуже видно — пусть читают F/боты).
func glare_now() -> float:
	return float(_mat.get_shader_parameter(&"glare")) if _mat and visible else 0.0
