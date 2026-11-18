class_name CombatBomb
extends RigidBody3D
## Связка динамита: летит и катится как тело, фитиль искрит и шипит, по таймеру — взрыв.

var thrower: Node
var fuse := 3.2
var radius := 6.5
var damage := 140.0
var _t := 0.0
var _sparks: CPUParticles3D
var _done := false

func _ready() -> void:
	mass = 0.6
	continuous_cd = true
	angular_damp = 1.5
	linear_damp = 0.1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.12, 0.22, 0.08)
	cs.shape = bs
	add_child(cs)
	var m := CombatModels.projectile(&"dynamite")
	add_child(m)
	if thrower is CollisionObject3D:
		add_collision_exception_with(thrower as CollisionObject3D)
	var fl := m.find_child("Flame", true, false) as Node3D
	_sparks = CombatFx.particles(fl if fl else self, (fl if fl else self).global_position if is_inside_tree() else Vector3.ZERO, 16, 0.35, "flame", true,
		CombatFx._ramp([Color(1, 0.9, 0.6, 1), Color(1, 0.5, 0.1, 0.6), Color(1, 0.3, 0.0, 0)]), 0.04, 1.5, 70.0, Vector3.UP, Vector3(0, -3, 0), false)
	_sparks.local_coords = false
	CombatFx.loop_on(self, "fuse_loop", -4.0)

func _physics_process(delta: float) -> void:
	_t += delta
	if _sparks and is_instance_valid(_sparks):
		var fl := find_child("Flame", true, false) as Node3D
		if fl:
			_sparks.global_position = fl.global_position
	# страховка от «туннелирования» сквозь рельеф (тонкое быстрое тело, низкий FPS физики)
	if BuildEnv.world() != null:
		var gy := BuildEnv.height_at(global_position.x, global_position.z)
		if global_position.y < gy - 0.02:
			global_position.y = gy + 0.06
			if linear_velocity.y < 0.0:
				linear_velocity = Vector3(linear_velocity.x * 0.4, -linear_velocity.y * 0.15, linear_velocity.z * 0.4)
	# в воде фитиль гаснет
	if global_position.y < BuildEnv.water_surface(global_position.x, global_position.z) - 0.15 and not _done:
		_done = true
		CombatFx.impact(self, global_position, Vector3.UP, &"water")
		if _sparks:
			_sparks.emitting = false
		get_tree().create_timer(4.0).timeout.connect(queue_free)
		return
	if _t >= fuse and not _done:
		_done = true
		Combat.explode(global_position, radius, damage, thrower)
		queue_free()
