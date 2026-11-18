class_name Shark
extends Node3D
## Акула: движение (рыскание, глубина, обход мелей), состояния патруль → интерес →
## кружение (плавник над водой) → атака → отход. Цели ищет менеджер моря (Sea).
## Урон: apply_damage(amount, source, kind). Нос — в -Z.

enum State { PATROL, INVESTIGATE, STALK, ATTACK, RETREAT, DEAD }

var species: StringName = &"reef"
var cfg: Dictionary
var health: float = 100.0
var max_health: float = 100.0
var state: State = State.PATROL
var sea: Node = null            # менеджер (Sea)
var home: Vector2 = Vector2.ZERO  # центр патруля (XZ)
var home_r: float = 60.0
var orbit_dir: float = 1.0

var yaw: float = 0.0
var speed: float = 2.0
var target_y: float = -3.0
var target: Node3D = null
var frenzy: float = 0.0          # >0 — бешенство (короткие паузы между атаками)
var target_kind: StringName = &"swim"   # swim | deck
var investigate_at: Vector3 = Vector3.ZERO
var length: float = 2.0

var _model: Node3D
var _mat: ShaderMaterial
var _phase: float = 0.0
var _turn_rate: float = 0.0
var _state_t: float = 0.0
var _avoid_t: float = 0.0
var _avoid_dir: float = 0.0
var _scan_t: float = 0.0
var _orbit_a: float = 0.0
var _wander: float = 0.0
var _rng := RandomNumberGenerator.new()
var _dead_t: float = 0.0
var _leap: float = 0.0
var _last_aggressor: Node = null
var _hitbox: StaticBody3D = null
var bait_t: float = 0.0          # >0 — кормится у приманки (почти не ищет людей)
var _bump_cd: float = 0.0

## Слой коллизии для попаданий оружием (лучи Combat видят все слои; игрок/боты — нет).
const HIT_LAYER := 1 << 9
## Добыча с туши: [мясо, зубы].
const LOOT := {&"reef": [3, 2], &"tiger": [5, 4], &"white": [8, 6]}

func setup(p_species: StringName, p_sea: Node, p_home: Vector2, p_home_r: float, seed_i: int) -> void:
	species = p_species
	cfg = SharkModel.SPECIES[species]
	sea = p_sea
	home = p_home
	home_r = p_home_r
	length = cfg["length"]
	max_health = cfg["hp"]
	health = max_health
	_rng.seed = seed_i
	orbit_dir = 1.0 if _rng.randf() < 0.5 else -1.0
	_orbit_a = _rng.randf() * TAU
	_scan_t = _rng.randf() * 0.5
	_phase = _rng.randf() * TAU
	speed = float(cfg["speed"])

func _ready() -> void:
	add_to_group(&"sharks")
	add_to_group(&"animals")
	_model = SharkModel.build(species)
	add_child(_model)
	_mat = (_model.get_node(^"Body") as MeshInstance3D).material_override as ShaderMaterial
	yaw = rotation.y
	# хитбокс для копья/стрел/пуль: капсула вдоль тела (нос в -Z)
	_hitbox = StaticBody3D.new()
	_hitbox.name = "Hitbox"
	_hitbox.collision_layer = HIT_LAYER
	_hitbox.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = maxf(length * float(cfg["girth"]) * 1.25, 0.16)
	cap.height = length * 0.85
	cs.shape = cap
	cs.rotation.x = PI * 0.5
	_hitbox.add_child(cs)
	add_child(_hitbox)

func is_dead() -> bool:
	return state == State.DEAD

func display_name() -> String:
	return cfg.get("name", "Акула")

func forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))

func head_position() -> Vector3:
	return global_position + forward() * length * 0.42

## Урон акуле (оружие, взрыв). Агрессор в воде становится целью.
func apply_damage(amount: float, source: Node, kind: StringName = &"melee") -> void:
	if state == State.DEAD:
		return
	# под водой удары и пули слабее, акула уворачивается
	if kind == &"bullet" or kind == &"arrow":
		amount *= 0.6
	if _rng.randf() < 0.12 and kind != &"explosion":
		return
	health -= amount
	if sea and sea.has_method(&"add_blood"):
		sea.add_blood(global_position, minf(amount, 30.0) * 0.5, false)
	if health <= 0.0:
		_die(source)
		return
	if source is Node3D and source.has_method(&"is_in_water"):
		_last_aggressor = source
	if health < max_health * 0.25:
		_enter(State.RETREAT, 6.0)   # раненая уходит
	elif source is Node3D and _is_valid_prey(source as Node3D):
		target = source as Node3D
		_enter(State.ATTACK, 0.0)

func _die(killer: Node) -> void:
	state = State.DEAD
	_dead_t = 0.0
	target = null
	if _hitbox:
		_hitbox.collision_layer = 0
	_drop_loot()
	if sea and sea.has_method(&"on_shark_died"):
		sea.on_shark_died(self, killer)

## Туша: мясо и зубы мешком у поверхности (тонет к дну вместе с акулой).
func _drop_loot() -> void:
	var l: Array = LOOT.get(species, [3, 2])
	var parent := get_parent()
	if parent == null or not is_inside_tree():
		return
	var arr: Array[Dictionary] = [{"id": &"shark_meat", "n": int(l[0])}, {"id": &"shark_tooth", "n": int(l[1])}]
	var p := global_position
	if sea:
		p.y = maxf(p.y, float(sea.water_y()) - 0.6)
	ItemPickup.spawn(parent, p, arr)

## Приманка: бросить текущую жертву (если та не истекает кровью) и плыть кормиться.
func lure(pos: Vector3, seconds: float) -> bool:
	if state == State.DEAD:
		return false
	if state == State.ATTACK and frenzy > 0.0 and _target_ok() and sea.call(&"is_bleeding", target):
		return false
	target = null
	_leap = 0.0
	investigate_at = pos
	bait_t = seconds
	_enter(State.INVESTIGATE, seconds)
	return true

func _enter(s: State, t: float) -> void:
	state = s
	_state_t = t

## Стая почуяла атаку/кровь: переключиться на жертву (бешенство).
func alert(prey: Node3D, kind: StringName) -> void:
	if state == State.DEAD or not _is_valid_prey(prey):
		return
	frenzy = 12.0
	if state == State.PATROL or state == State.INVESTIGATE:
		target = prey
		target_kind = kind
		_enter(State.STALK, _rng.randf_range(0.2, 0.6))

func _fz(a: float, b: float) -> float:
	var k := 0.3 if frenzy > 0.0 else 1.0
	return _rng.randf_range(a, b) * k

func _is_valid_prey(n: Node3D) -> bool:
	return sea != null and is_instance_valid(n) and sea.is_prey(n)

## Шаг ИИ и движения. full=false — дешёвая симуляция дальней акулы.
func tick(delta: float, full: bool) -> void:
	if state == State.DEAD:
		_tick_dead(delta)
		return
	var water: float = sea.water_y()
	_state_t -= delta
	_scan_t -= delta
	frenzy = maxf(frenzy - delta, 0.0)
	bait_t = maxf(bait_t - delta, 0.0)
	_bump_cd = maxf(_bump_cd - delta, 0.0)
	if _scan_t <= 0.0 and (state == State.PATROL or state == State.INVESTIGATE):
		_scan_t = 0.45 + _rng.randf() * 0.25
		var found: Dictionary = sea.find_prey(self)
		if not found.is_empty():
			target = found["node"]
			target_kind = found["kind"]
			var stalk: float = _rng.randf_range(1.4, 3.0) * (0.45 if found.get("blood", false) else 1.0)
			_enter(State.STALK, stalk)
		elif sea.has_method(&"nearest_attractor"):
			var at: Variant = sea.nearest_attractor(global_position, float(cfg["sense"]) * 2.2)
			if at is Vector3:
				investigate_at = at
				_enter(State.INVESTIGATE, 8.0)

	var want := Vector3.ZERO
	var want_speed: float = cfg["speed"]
	var depth_here: float = sea.depth_at(global_position.x, global_position.z)
	var cruise_depth := clampf(depth_here * 0.45, 1.3, 4.5)
	target_y = water - cruise_depth

	match state:
		State.PATROL:
			_orbit_a += orbit_dir * (speed / maxf(home_r, 5.0)) * delta
			_wander += delta * 0.3
			var r := home_r + sin(_wander * 1.7 + _phase) * home_r * 0.15
			var p := home + Vector2(cos(_orbit_a), sin(_orbit_a)) * r
			want = Vector3(p.x - global_position.x, 0.0, p.y - global_position.z)
		State.INVESTIGATE:
			want = investigate_at - global_position
			want.y = 0.0
			want_speed *= 1.4
			if bait_t > 0.0:
				# кормится: кружит у приманки, рывками хватает куски
				var d := want.length()
				if d < 7.0:
					var tang := Vector3(-want.z, 0.0, want.x).normalized() * orbit_dir
					want = tang + want.normalized() * clampf((d - 3.0) * 0.4, -1.0, 1.0)
					want_speed = float(cfg["speed"]) * 1.2
					target_y = water - 0.5
				if _state_t <= 0.0:
					bait_t = 0.0
					_enter(State.PATROL, 0.0)
			elif want.length() < 4.0 or _state_t <= 0.0:
				_enter(State.PATROL, 0.0)
		State.STALK:
			if not _target_ok():
				_lose_target()
			else:
				var tp := target.global_position
				var to := Vector3(tp.x - global_position.x, 0.0, tp.z - global_position.z)
				var d := to.length()
				var circle_r := 3.5 + length * 0.6
				# кружим: касательная + притяжение к окружности
				var tang := Vector3(-to.z, 0.0, to.x).normalized() * orbit_dir
				want = tang + to.normalized() * clampf((d - circle_r) * 0.4, -1.0, 1.0)
				want_speed *= 1.25
				target_y = water - 0.32   # плавник над водой
				if _state_t <= 0.0 and d < circle_r * (4.0 if frenzy > 0.0 else 2.5):
					_enter(State.ATTACK, 6.0)
		State.ATTACK:
			if not _target_ok():
				_lose_target()
			else:
				var tp := _attack_point()
				want = tp - global_position
				want.y = 0.0
				want_speed = cfg["burst"]
				target_y = minf(tp.y - 0.15, water - 0.3)
				if target_kind == &"deck" and want.length() < 3.5:
					_leap = 1.0
				var head := head_position()
				var dh := Vector2(tp.x - head.x, tp.z - head.z).length()
				if dh < 0.7 + length * 0.18 and absf(tp.y - head.y) < 1.6 + _leap:
					if sea.try_bite(self, target):
						_enter(State.RETREAT, _fz(1.0, 1.7))
					else:
						_enter(State.STALK, _fz(0.5, 1.0))
				elif _state_t <= 0.0:
					_enter(State.STALK, _fz(0.8, 1.6))
		State.RETREAT:
			var away := global_position - (target.global_position if _target_ok() else global_position + forward())
			away.y = 0.0
			want = away.normalized() + forward() * 0.5
			want_speed *= 1.3
			if _state_t <= 0.0:
				if _target_ok() and health > max_health * 0.25:
					_enter(State.STALK, _fz(0.5, 1.2))
				else:
					_lose_target()

	_steer(want, want_speed, delta, depth_here)
	if full:
		_animate(delta)

func can_bump() -> bool:
	return _bump_cd <= 0.0 and state != State.DEAD

func did_bump() -> void:
	_bump_cd = _rng.randf_range(8.0, 16.0)
	orbit_dir = -orbit_dir

func _target_ok() -> bool:
	return target != null and is_instance_valid(target) and _is_valid_prey(target)

func _lose_target() -> void:
	target = null
	_leap = 0.0
	_enter(State.PATROL, 0.0)

func _attack_point() -> Vector3:
	var tp := target.global_position
	if target_kind == &"deck":
		return Vector3(tp.x, sea.water_y() + 0.2, tp.z)
	return tp + Vector3(0.0, 0.25, 0.0)

func _steer(want: Vector3, want_speed: float, delta: float, depth_here: float) -> void:
	var max_turn: float = cfg["turn"]
	# обход мелководья: щупаем дно впереди
	var look := maxf(3.0, speed * 1.3) + length * 0.5
	var ahead := global_position + forward() * look
	var min_depth := 1.0 + length * 0.22
	if _avoid_t > 0.0:
		_avoid_t -= delta
	elif sea.depth_at(ahead.x, ahead.z) < min_depth:
		var l := global_position + forward().rotated(Vector3.UP, 0.8) * look
		var r := global_position + forward().rotated(Vector3.UP, -0.8) * look
		_avoid_dir = 1.0 if sea.depth_at(l.x, l.z) > sea.depth_at(r.x, r.z) else -1.0
		_avoid_t = 0.9
	var desired_yaw := yaw
	if want.length() > 0.01:
		desired_yaw = atan2(-want.x, -want.z)
	if _avoid_t > 0.0:
		desired_yaw = yaw + _avoid_dir * 1.2
	var diff := wrapf(desired_yaw - yaw, -PI, PI)
	var turn := clampf(diff, -max_turn * delta, max_turn * delta)
	yaw += turn
	_turn_rate = lerpf(_turn_rate, turn / maxf(delta, 0.001) / max_turn, clampf(delta * 5.0, 0.0, 1.0))
	speed = move_toward(speed, want_speed, delta * (4.0 if want_speed > speed else 2.0))
	var p := global_position + forward() * speed * delta
	# глубина
	var water: float = sea.water_y()
	var floor_y: float = sea.floor_at(p.x, p.z)
	var ty := clampf(target_y, floor_y + 0.35 + length * 0.07, water - 0.22)
	if _leap > 0.0:
		ty = water + 0.15 * _leap
		_leap = maxf(0.0, _leap - delta * 1.5)
	p.y = move_toward(global_position.y, ty, delta * (1.8 + _leap * 4.0))
	# не заплывать на сушу
	if sea.depth_at(p.x, p.z) < 0.5:
		p.x = global_position.x
		p.z = global_position.z
		yaw += PI * 0.5 * delta
	var pitch := clampf((p.y - global_position.y) / maxf(speed * delta, 0.01), -0.6, 0.6) * 0.5
	global_position = p
	rotation = Vector3(pitch, yaw, -_turn_rate * 0.12)

func _animate(delta: float) -> void:
	var freq := 1.6 + speed * 0.55
	_phase += delta * freq * TAU * 0.5
	_mat.set_shader_parameter(&"swim_phase", _phase)
	_mat.set_shader_parameter(&"swim_amp", 0.05 + clampf(speed / float(cfg["burst"]), 0.0, 1.0) * 0.05)
	_mat.set_shader_parameter(&"turn_bend", clampf(-_turn_rate, -1.0, 1.0))

func _tick_dead(delta: float) -> void:
	_dead_t += delta
	# брюхом вверх, медленно тонет
	rotation.z = lerpf(rotation.z, PI, clampf(delta * 1.2, 0.0, 1.0))
	var floor_y: float = sea.floor_at(global_position.x, global_position.z)
	global_position.y = maxf(floor_y + 0.3, global_position.y - delta * 0.25)
	if _mat:
		_mat.set_shader_parameter(&"swim_amp", 0.0)
	if _dead_t > 40.0:
		queue_free()
