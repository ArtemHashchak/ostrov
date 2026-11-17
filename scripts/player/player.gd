class_name Player
extends CharacterBody3D
## Игрок от первого лица в духе The Forest: ходьба/бег/присед/прыжок,
## выносливость с плавной усталостью, покачивание головы, руки, взаимодействие.

signal swing_hit(hit: Dictionary)

# --- скорости (м/с) ---
const WALK_SPEED := 3.4
const RUN_SPEED := 6.4
const CROUCH_SPEED := 1.7
const CARRY_SPEED_MUL := 0.72   # несёт бревно — медленнее
const TIRED_SPEED_MUL := 0.82
const JUMP_HEIGHT := 1.05
const ACCEL_GROUND := 11.0
const DECEL_GROUND := 13.0
const ACCEL_AIR := 2.5

# --- рост ---
const HEIGHT := 1.80
const CROUCH_HEIGHT := 1.15
const RADIUS := 0.32
const EYE_OFFSET := 0.14 # глаза ниже макушки

# --- выносливость ---
const STAMINA_MAX := 100.0
const STAMINA_RUN_COST := 16.0   # в секунду
const STAMINA_JUMP_COST := 12.0
const STAMINA_REGEN := 13.0      # в секунду
const STAMINA_REGEN_DELAY := 0.9
const TIRED_RECOVER_AT := 35.0   # пока не восстановится — спринта нет

const INTERACT_REACH := 2.8
const SWING_REACH := 2.2

@export var team: int = 0

var stamina: float = STAMINA_MAX
var tired: bool = false
var tired_amount: float = 0.0     # 0..1, плавно — для анимаций
var sprinting: bool = false
var crouching: bool = false
var carrying_log: bool = false
var carried_object: Node = null   # что несём (бревно и т.п.) — E без цели кладёт его
var alive: bool = true
var input_enabled: bool = true

var _yaw: float = 0.0
var _pitch: float = 0.0
var _stamina_used_t: float = 0.0
var _bob_t: float = 0.0
var _cur_height: float = HEIGHT
var _land_dip: float = 0.0
var _was_on_floor: bool = true
var _fall_speed: float = 0.0
var _hint: String = ""
var _gravity: float = 19.6

var head: Node3D
var camera: Camera3D
var hands: FPHands
var ray: RayCast3D
var _shape: CollisionShape3D
var _capsule: CapsuleShape3D

func _ready() -> void:
	# ALWAYS — чтобы Esc снимал паузу; физика при паузе сама выходит.
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"characters")
	add_to_group(&"player")
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 19.6))
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(48.0)
	_capsule = CapsuleShape3D.new()
	_capsule.radius = RADIUS
	_capsule.height = HEIGHT
	_shape = CollisionShape3D.new()
	_shape.shape = _capsule
	_shape.position.y = HEIGHT * 0.5
	add_child(_shape)
	head = Node3D.new()
	head.name = "Head"
	head.position.y = HEIGHT - EYE_OFFSET
	add_child(head)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = Settings.fov
	camera.near = 0.03
	camera.far = 1500.0
	camera.current = true
	head.add_child(camera)
	ray = RayCast3D.new()
	ray.target_position = Vector3(0, 0, -INTERACT_REACH)
	ray.add_exception(self)
	ray.collide_with_areas = true
	camera.add_child(ray)
	hands = FPHands.new()
	hands.name = "Hands"
	camera.add_child(hands)
	hands.swing_impact.connect(_on_swing_impact)
	_yaw = rotation.y
	rotation = Vector3.ZERO
	Game.register_member(team, self)
	Events.character_spawned.emit(self)
	capture_mouse(true)

func capture_mouse(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		_toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if not input_enabled or get_tree().paused:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		look(mm.relative * Settings.mouse_sensitivity)
	elif event.is_action_pressed(&"attack"):
		swing()
	elif event.is_action_pressed(&"interact"):
		interact()

func _toggle_pause() -> void:
	var p := not get_tree().paused
	get_tree().paused = p
	capture_mouse(not p)
	Events.pause_toggled.emit(p)

## Поворот взгляда (dx, dy в радианах).
func look(rel: Vector2) -> void:
	_yaw -= rel.x
	var dy := rel.y * (-1.0 if Settings.invert_y else 1.0)
	_pitch = clampf(_pitch - dy, deg_to_rad(-88.0), deg_to_rad(88.0))

func set_look(yaw: float, pitch: float) -> void:
	_yaw = yaw
	_pitch = pitch

func _physics_process(delta: float) -> void:
	if not alive or get_tree().paused:
		return
	_gamepad_look(delta)
	var wish := Vector2.ZERO
	var want_sprint := false
	var want_crouch := false
	var want_jump := false
	if input_enabled:
		wish = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
		want_sprint = Input.is_action_pressed(&"sprint")
		want_crouch = Input.is_action_pressed(&"crouch")
		want_jump = Input.is_action_just_pressed(&"jump")
	_update_crouch(want_crouch, delta)
	_update_stamina_state(delta)

	var moving_forward := wish.y < -0.2
	sprinting = want_sprint and moving_forward and not crouching and not tired and is_on_floor() and stamina > 0.0
	var speed := WALK_SPEED
	if crouching:
		speed = CROUCH_SPEED
	elif sprinting:
		speed = RUN_SPEED
	if carrying_log:
		speed *= CARRY_SPEED_MUL
	speed *= lerpf(1.0, TIRED_SPEED_MUL, tired_amount)

	if sprinting:
		_use_stamina(STAMINA_RUN_COST * delta)

	var basis_yaw := Basis(Vector3.UP, _yaw)
	var dir := basis_yaw * Vector3(wish.x, 0.0, wish.y)
	if dir.length() > 1.0:
		dir = dir.normalized()
	var target := dir * speed
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	var accel := ACCEL_AIR
	if is_on_floor():
		accel = ACCEL_GROUND if target.length() > horiz.length() else DECEL_GROUND
	horiz = horiz.lerp(target, clampf(accel * delta, 0.0, 1.0))
	velocity.x = horiz.x
	velocity.z = horiz.z

	if is_on_floor():
		if want_jump and stamina >= STAMINA_JUMP_COST * 0.5 and not crouching:
			velocity.y = sqrt(2.0 * _gravity * JUMP_HEIGHT) * lerpf(1.0, 0.8, tired_amount)
			_use_stamina(STAMINA_JUMP_COST)
	else:
		velocity.y -= _gravity * delta
		_fall_speed = maxf(_fall_speed, -velocity.y)

	move_and_slide()

	if is_on_floor() and not _was_on_floor:
		_land_dip = clampf(_fall_speed * 0.012, 0.0, 0.12)
		_fall_speed = 0.0
	_was_on_floor = is_on_floor()

	_update_camera(delta, horiz.length())
	_update_interact_hint()

func _gamepad_look(delta: float) -> void:
	if not input_enabled:
		return
	var v := Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	if v.length() > 0.05:
		look(v * Settings.gamepad_look_speed * delta)

func _update_crouch(want: bool, delta: float) -> void:
	if want:
		crouching = true
	elif crouching and _can_stand():
		crouching = false
	var target_h := CROUCH_HEIGHT if crouching else HEIGHT
	_cur_height = move_toward(_cur_height, target_h, delta * 4.0)
	_capsule.height = _cur_height
	_shape.position.y = _cur_height * 0.5

func _can_stand() -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * (_cur_height - 0.05),
		global_position + Vector3.UP * (HEIGHT + 0.05))
	q.exclude = [get_rid()]
	return space.intersect_ray(q).is_empty()

func _use_stamina(amount: float) -> void:
	stamina = maxf(0.0, stamina - amount)
	_stamina_used_t = 0.0

func _update_stamina_state(delta: float) -> void:
	_stamina_used_t += delta
	if _stamina_used_t > STAMINA_REGEN_DELAY:
		var regen := STAMINA_REGEN * (0.6 if (Vector2(velocity.x, velocity.z).length() > 0.5) else 1.0)
		stamina = minf(STAMINA_MAX, stamina + regen * delta)
	# Гистерезис: выдохся на нуле, отдышался на TIRED_RECOVER_AT — без мигания.
	var was_tired := tired
	if not tired and stamina <= 0.5:
		tired = true
		Events.toast.emit("Ты выдохся — отдышись")
	elif tired and stamina >= TIRED_RECOVER_AT:
		tired = false
	tired_amount = move_toward(tired_amount, 1.0 if tired else 0.0, delta * 1.5)
	if was_tired != tired or Engine.get_physics_frames() % 6 == 0:
		Events.player_stamina_changed.emit(stamina, STAMINA_MAX, tired)

func _update_camera(delta: float, hspeed: float) -> void:
	rotation.y = 0.0
	var moving := is_on_floor() and hspeed > 0.4
	var freq := 7.0 if not sprinting else 10.5
	freq = lerpf(freq, 5.5, tired_amount)
	if moving:
		_bob_t += delta * freq * clampf(hspeed / WALK_SPEED, 0.6, 1.6)
	var amp := 0.035 if not sprinting else 0.06
	amp *= lerpf(1.0, 1.7, tired_amount)
	var moving_f := 1.0 if moving else 0.0
	var bob_y := sin(_bob_t * 2.0) * amp * moving_f
	var bob_x := cos(_bob_t) * amp * 0.6 * moving_f
	# Тяжёлое дыхание — медленное покачивание даже стоя.
	var breath := sin(Time.get_ticks_msec() * 0.0042) * 0.018 * tired_amount
	_land_dip = move_toward(_land_dip, 0.0, delta * 0.6)
	head.position = Vector3(bob_x, _cur_height - EYE_OFFSET + bob_y + breath - _land_dip, 0.0)
	head.rotation = Vector3(_pitch + breath * 0.3, _yaw, sin(_bob_t) * 0.006 * moving_f * (1.0 + tired_amount * 2.0))
	var fov_target := Settings.fov + (5.0 if sprinting else 0.0)
	camera.fov = lerpf(camera.fov, fov_target, clampf(delta * 6.0, 0.0, 1.0))
	hands.animate(delta, clampf(hspeed / RUN_SPEED, 0.0, 1.0), sprinting, tired_amount, is_on_floor(), carrying_log)

# --- действия ---

func swing() -> void:
	if not alive or carrying_log:
		return
	hands.play_swing()

func _on_swing_impact() -> void:
	var space := get_world_3d().direct_space_state
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * SWING_REACH
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	q.collide_with_areas = true
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		hit = {"miss": true}
	swing_hit.emit(hit)
	Events.player_swing.emit(self, hit)
	if hit.has("collider"):
		var target := _find_with_method(hit.collider as Node, &"on_hit")
		if target:
			target.call(&"on_hit", self, hit)

func set_carrying_log(on: bool, obj: Node = null) -> void:
	carrying_log = on
	carried_object = obj if on else null
	hands.set_carry(on)

func interact() -> void:
	var target := _interact_target()
	if target:
		target.call(&"interact", self)
	elif carried_object and carried_object.has_method(&"interact"):
		carried_object.call(&"interact", self)

func _interact_target() -> Node:
	ray.force_raycast_update()
	if not ray.is_colliding():
		return null
	return _find_with_method(ray.get_collider() as Node, &"interact")

func _update_interact_hint() -> void:
	var t := _interact_target()
	var text := ""
	if t:
		text = String(t.call(&"get_interact_text", self)) if t.has_method(&"get_interact_text") else "E — взаимодействовать"
	elif carried_object and carried_object.has_method(&"get_interact_text"):
		text = String(carried_object.call(&"get_interact_text", self))
	if text != _hint:
		_hint = text
		Events.interact_hint_changed.emit(text)

## Ищет у узла или его предков метод (коллайдер обычно — дочерний узел объекта).
static func _find_with_method(n: Node, method: StringName) -> Node:
	var cur := n
	var depth := 0
	while cur and depth < 6:
		if cur.has_method(method):
			return cur
		cur = cur.get_parent()
		depth += 1
	return null

func get_look_dir() -> Vector3:
	return -camera.global_transform.basis.z

func get_eye_position() -> Vector3:
	return camera.global_position
