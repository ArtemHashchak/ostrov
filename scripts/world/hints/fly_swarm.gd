class_name FlySwarm
extends CPUParticles3D
## Рой насекомых: мухи над тушей/испорченной едой (пункт 28 — выдают тайник), комары в манграх
## ночью (пункт 29). Мелкие тёмные точки, кружат в сфере радиуса radius и не улетают.
## follow — узел, за которым рой держится (игрок для комаров, тушка для мух).

var follow: Node3D = null
var follow_offset := Vector3(0, 0.4, 0)
var kind := &"flies"        # flies | mosquito

static func make(kind_: StringName, radius: float = 0.6, n: int = 24) -> FlySwarm:
	var s := FlySwarm.new()
	s.kind = kind_
	s.amount = n
	s.lifetime = 2.4
	s.preprocess = 2.4
	s.local_coords = true
	s.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	s.emission_sphere_radius = radius
	s.gravity = Vector3.ZERO
	s.direction = Vector3(1, 0.2, 0)
	s.spread = 180.0
	s.initial_velocity_min = 0.6 if kind_ == &"flies" else 0.35
	s.initial_velocity_max = 1.4 if kind_ == &"flies" else 0.8
	s.tangential_accel_min = -2.0
	s.tangential_accel_max = 2.0
	s.radial_accel_min = -1.6        # тянет к центру — рой держится вместе
	s.radial_accel_max = -0.6
	s.damping_min = 0.2
	s.damping_max = 0.6
	var sz := 0.012 if kind_ == &"flies" else 0.007
	s.scale_amount_min = sz * 0.8
	s.scale_amount_max = sz * 1.3
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 4
	m.rings = 2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.06, 0.06, 0.05) if kind_ == &"flies" else Color(0.18, 0.17, 0.16)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material = mat
	s.mesh = m
	s.emitting = true
	s.name = "FlySwarm_" + String(kind_)
	return s

func _process(_dt: float) -> void:
	if follow:
		if not is_instance_valid(follow):
			queue_free()
			return
		global_position = follow.global_position + follow_offset
