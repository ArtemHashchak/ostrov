class_name SeaCreature
extends Node3D
## Мирный морской обитатель: скат (у дна), морская черепаха (всплывает подышать),
## медуза (дрейфует у поверхности, жжётся). Движение — простое рыскание с обходом мелей.
## Скат и черепаха — добыча (копьё/стрелы): apply_damage → мясо мешком.

enum Kind { RAY, TURTLE, JELLY }

var kind: Kind = Kind.RAY
var sea: Node = null
var home: Vector2 = Vector2.ZERO
var home_r: float = 30.0
var health: float = 40.0
var dead: bool = false

var yaw: float = 0.0
var speed: float = 0.8
var _goal := Vector3.ZERO
var _goal_t := 0.0
var _breath_t := 0.0
var _flee_t := 0.0
var _rng := RandomNumberGenerator.new()
var _mi: MeshInstance3D
var _hitbox: StaticBody3D
var _dead_t := 0.0

static var _mats: Dictionary = {}

func setup(k: Kind, p_sea: Node, p_home: Vector2, p_r: float, seed_i: int) -> void:
	kind = k
	sea = p_sea
	home = p_home
	home_r = p_r
	_rng.seed = seed_i
	match kind:
		Kind.RAY:
			health = 35.0
			speed = 0.9
		Kind.TURTLE:
			health = 60.0
			speed = 0.6
			_breath_t = _rng.randf_range(20.0, 90.0)
		Kind.JELLY:
			health = 3.0
			speed = 0.18

func _ready() -> void:
	add_to_group(&"sea_life")
	_mi = MeshInstance3D.new()
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var wy: float = sea.call(&"water_y") if sea else 0.0
	match kind:
		Kind.RAY:
			_mi.mesh = SeaMeshes.ray_mesh()
			_mi.material_override = _material(0, wy)
			var s := _rng.randf_range(0.6, 1.1)
			_mi.scale = Vector3.ONE * s
		Kind.TURTLE:
			_mi.mesh = SeaMeshes.turtle_mesh()
			_mi.material_override = _material(1, wy)
			_mi.scale = Vector3.ONE * _rng.randf_range(1.0, 1.5)
		Kind.JELLY:
			_mi.mesh = SeaMeshes.jelly_mesh()
			_mi.material_override = _jelly_mat(_rng.randi() % 3)
			_mi.scale = Vector3.ONE * _rng.randf_range(0.6, 1.3)
	add_child(_mi)
	_mi.set_instance_shader_parameter(&"phase", _rng.randf() * TAU)
	if kind != Kind.JELLY:
		_mi.set_instance_shader_parameter(&"rate", _rng.randf_range(0.8, 1.2))
		_hitbox = StaticBody3D.new()
		_hitbox.collision_layer = Shark.HIT_LAYER
		_hitbox.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.6, 0.25, 1.2) * _mi.scale.x if kind == Kind.RAY else Vector3(0.7, 0.35, 0.9) * _mi.scale.x
		cs.shape = bs
		_hitbox.add_child(cs)
		add_child(_hitbox)
	yaw = _rng.randf() * TAU
	_new_goal()

static func _material(k: int, wy: float) -> ShaderMaterial:
	var key := "c%d_%.2f" % [k, wy]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = SeaMeshes.CREATURE_SHADER
	m.set_shader_parameter(&"kind", k)
	m.set_shader_parameter(&"water_level", wy)
	_mats[key] = m
	return m

static func _jelly_mat(v: int) -> ShaderMaterial:
	var key := "j%d" % v
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = SeaMeshes.JELLY_SHADER
	var tints := [Color(0.78, 0.62, 0.95, 0.5), Color(0.6, 0.8, 0.95, 0.45), Color(0.95, 0.7, 0.75, 0.5)]
	m.set_shader_parameter(&"tint", tints[v % tints.size()])
	_mats[key] = m
	return m

static func clear_cache() -> void:
	_mats.clear()

func _wy() -> float:
	return float(sea.call(&"water_y"))

func _depth(x: float, z: float) -> float:
	return float(sea.call(&"depth_at", x, z))

func _new_goal() -> void:
	_goal_t = _rng.randf_range(6.0, 16.0)
	for i in 8:
		var a := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * home_r
		var p := Vector3(home.x + cos(a) * r, 0.0, home.y + sin(a) * r)
		if _depth(p.x, p.z) > (1.4 if kind == Kind.RAY else 2.0):
			_goal = p
			return
	_goal = Vector3(home.x, 0.0, home.y)

## Урон: копьё/стрела/взрыв.
func apply_damage(amount: float, source: Node, _kind: StringName = &"melee") -> void:
	if dead:
		return
	health -= amount
	_flee_t = 6.0
	if source is Node3D:
		var away := global_position - (source as Node3D).global_position
		_goal = global_position + Vector3(away.x, 0.0, away.z).normalized() * 18.0
	if sea:
		sea.call(&"add_blood", global_position, minf(amount, 20.0) * 0.4, kind != Kind.JELLY)
	if health <= 0.0:
		_die()

func _die() -> void:
	dead = true
	if _hitbox:
		_hitbox.collision_layer = 0
	if kind == Kind.JELLY:
		queue_free()
		return
	var n := 2 if kind == Kind.RAY else 4
	var arr: Array[Dictionary] = [{"id": &"meat_raw", "n": n}]
	var pk := ItemPickup.spawn(get_parent(), global_position + Vector3.UP * 0.2, arr)
	if pk:
		pk.set_meta(&"sea_loot", true)

func is_dead() -> bool:
	return dead

## Шаг ИИ. Зовёт SeaLife только для ближних (дальние спят).
func tick(delta: float) -> void:
	if dead:
		_dead_t += delta
		rotation.z = lerpf(rotation.z, PI, clampf(delta, 0.0, 1.0))
		var fy: float = sea.call(&"floor_at", global_position.x, global_position.z)
		global_position.y = maxf(fy + 0.15, global_position.y - delta * 0.3)
		if _dead_t > 30.0:
			queue_free()
		return
	_goal_t -= delta
	_flee_t = maxf(_flee_t - delta, 0.0)
	var to := _goal - global_position
	to.y = 0.0
	if _goal_t <= 0.0 or to.length() < 2.0:
		_new_goal()
		to = _goal - global_position
		to.y = 0.0
	var wy := _wy()
	var fy: float = sea.call(&"floor_at", global_position.x, global_position.z)
	var depth := wy - fy
	var spd := speed * (2.6 if _flee_t > 0.0 else 1.0)
	var ty := wy - 1.0
	match kind:
		Kind.RAY:
			ty = fy + 0.45 + 0.25 * sin(Time.get_ticks_msec() * 0.0004 + home.x)
			_mi.set_instance_shader_parameter(&"amp", 1.6 if _flee_t > 0.0 else 1.0)
		Kind.TURTLE:
			_breath_t -= delta
			if _breath_t < 0.0:
				ty = wy - 0.22
				if _breath_t < -5.0:
					_breath_t = _rng.randf_range(50.0, 120.0)
			else:
				ty = lerpf(wy - 1.2, fy + 0.8, 0.45)
			_mi.set_instance_shader_parameter(&"amp", 1.3 if _flee_t > 0.0 else 0.8)
		Kind.JELLY:
			ty = wy - clampf(depth * 0.3, 0.6, 2.2)
			# течение
			var cur := Vector3(sin(home.x * 0.01 + Time.get_ticks_msec() * 0.00005), 0.0, cos(home.y * 0.01)) * 0.12
			to = to.normalized() * 0.08 + cur
	ty = clampf(ty, fy + 0.3, wy - 0.2)
	# обход мели
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var ahead := global_position + fwd * 3.0
	var desired := atan2(-to.x, -to.z) if to.length() > 0.01 else yaw
	if kind != Kind.JELLY and _depth(ahead.x, ahead.z) < 1.0:
		desired = yaw + 1.4
	var turn_rate := 0.9 if kind != Kind.JELLY else 0.3
	yaw += clampf(wrapf(desired - yaw, -PI, PI), -turn_rate * delta, turn_rate * delta)
	fwd = Vector3(-sin(yaw), 0.0, -cos(yaw))
	var p := global_position
	if kind == Kind.JELLY:
		p += to.normalized() * spd * delta
	else:
		p += fwd * spd * delta
	if _depth(p.x, p.z) < 0.7:
		p.x = global_position.x
		p.z = global_position.z
	p.y = move_toward(global_position.y, ty, delta * 0.6)
	global_position = p
	if kind == Kind.JELLY:
		rotation = Vector3(0.0, yaw * 0.2, 0.0)
	else:
		rotation = Vector3(0.0, yaw, 0.0)
