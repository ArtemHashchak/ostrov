class_name StormDebris
extends Node3D
## После шторма в джунглях и на пляже валяются сорванные ветки и сухие листья пальм (v5, агент D).
## Когда шторм силой ≥ 0.7 стихает, вокруг камеры (до 70 м) на суше рассыпается валежник
## (MultiMesh, модель polyhaven dry_branches_medium_01, CC0) — плотнее под деревьями, реже на пляже.
## Через ~2 игровых суток (48 мин) остатки исчезают (их «растащили» и замело).

const MODEL := "res://assets/models/polyhaven_obj/dry_branches_medium_01/dry_branches_medium_01.obj"
const ALBEDO := "res://assets/models/polyhaven_obj/dry_branches_medium_01/dry_branches_medium_01_Albedo.jpg"
const MASK := "res://assets/models/polyhaven_obj/dry_branches_medium_01/dry_branches_medium_01_Mask.png"
const LIFE := 2880.0

var _peak := 0.0
var _mm: MultiMeshInstance3D
var _age := 0.0

func update_debris(dt: float, world: Node, cam: Camera3D, storm: float) -> void:
	_peak = maxf(_peak, storm)
	if _peak >= 0.7 and storm < 0.25 and world and cam:
		_scatter(world, cam.global_position)
		_peak = 0.0
	if _mm:
		_age += dt
		if _age > LIFE:
			_mm.queue_free()
			_mm = null

func count() -> int:
	return _mm.multimesh.visible_instance_count if _mm and _mm.multimesh else 0

## Рассыпать валежник вокруг точки (вызывается само после шторма; публично — для полигона/тестов).
func scatter_now(world: Node, at: Vector3) -> void:
	_scatter(world, at)

func _scatter(world: Node, at: Vector3) -> void:
	var mesh := load(MODEL) as Mesh
	if mesh == null:
		return
	if _mm:
		_mm.queue_free()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(ALBEDO) as Texture2D
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.4
	var mask := load(MASK) as Texture2D
	if mask:
		mat.roughness_texture = mask
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var q := Settings.graphics_quality
	var n := 40 if q <= 1 else 90
	var rng := RandomNumberGenerator.new()
	rng.seed = int(at.x * 13.0 + at.z * 7.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = n
	var wl := float(world.water_level())
	var k := 0
	var tries := 0
	while k < n and tries < n * 8:
		tries += 1
		var p := Vector2(at.x, at.z) + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * 70.0
		var h := float(world.height_at(p.x, p.y))
		if h < wl + 0.3:
			continue
		var b: StringName = world.biome_at(p.x, p.y)
		if b == &"rocky" or b == &"water":
			continue
		if b == &"beach" and rng.randf() < 0.6:
			continue   # на пляже — реже
		var nrm: Vector3 = world.normal_at(p.x, p.y) if world.has_method(&"normal_at") else Vector3.UP
		var basis := Basis(Vector3.UP, rng.randf() * TAU)
		# положить по склону
		var ax := Vector3.UP.cross(nrm)
		if ax.length() > 0.01:
			basis = Basis(ax.normalized(), Vector3.UP.angle_to(nrm)) * basis
		var s := rng.randf_range(0.6, 1.3)
		mm.set_instance_transform(k, Transform3D(basis.scaled(Vector3(s, s, s)), Vector3(p.x, h + 0.02, p.y)))
		k += 1
	mm.visible_instance_count = k
	_mm = MultiMeshInstance3D.new()
	_mm.name = "StormDebris"
	_mm.multimesh = mm
	_mm.material_override = mat
	_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if q >= 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mm.visibility_range_end = 90.0
	add_child(_mm)
	_age = 0.0
