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

# --- здоровье и выживание ---
const MAX_HEALTH := 100.0
const HUNGER_PER_SEC := 100.0 / (75.0 * 60.0)  # 0 через ~75 мин (SURVIVAL: баланс под матч 3–4 ч)
const THIRST_PER_SEC := 100.0 / (50.0 * 60.0)  # 0 через ~50 мин (SURVIVAL: дефицит воды средний)
const STARVE_DMG := 0.5                        # урон/с на нуле голода или жажды
const REGEN_PER_SEC := 0.15                    # сытый и напившийся — медленно лечится
const FALL_SAFE_SPEED := 11.0
const FALL_DMG_PER_MS := 7.0

# --- вода ---
const SWIM_DEPTH := 1.25       # глубже (от ног до поверхности) — плывём
const SWIM_FLOAT_EYE := 0.22   # глаза над водой на плаву
const SWIM_SPEED := 2.0
const SWIM_FAST := 3.0
const DIVE_SPEED := 1.8
const WADE_MUL := 0.75
const BREATH_MAX := 100.0
const BREATH_TIME := 30.0      # секунд под водой до удушья
const DROWN_DMG := 12.0        # урон/с без воздуха
const DRINK_REACH := 3.2

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
var ui_open: bool = false        # открыта панель интерфейса (инвентарь/крафт) — UI ставит
var fov_zoom: float = 0.0        # COMBAT: прицеливание ПКМ сужает FOV (ставит CombatController)
var swim_mul: float = 1.0        # SUPPLY: ласты в инвентаре ускоряют плавание (ставит SupplyController)

var health: float = MAX_HEALTH
var max_health: float = MAX_HEALTH
var hunger: float = 100.0
var thirst: float = 100.0
var breath: float = BREATH_MAX
var swimming: bool = false
var eliminated: bool = false
var respawn_left: float = 0.0
var last_damage_kind: StringName = &""
var poison: float = 0.0           # урон яда в секунду (FAUNA: змеи/скорпионы/пауки; тикает Fauna)
var poison_time: float = 0.0      # сколько ещё действует яд, с (противоядие: poison_time = 0)
var inventory: Inventory
var hud: Node = null
@export var starter_items: Dictionary = {&"flag": 1}
@export var create_hud: bool = true

var _spawn_origin: Vector3 = Vector3.ZERO
var _starve_acc: float = 0.0
var _pending_use: StringName = &""
var _death_roll: float = 0.0

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
	hands.use_finished.connect(_on_use_finished)
	PlayerItems.register()
	inventory = Inventory.new()
	add_child(inventory)
	inventory.changed.connect(_on_inventory_changed)
	for id in starter_items.keys():
		inventory.add(StringName(id), int(starter_items[id]))
	_yaw = rotation.y
	rotation = Vector3.ZERO
	Game.register_member(team, self)
	Events.character_spawned.emit(self)
	if create_hud and ResourceLoader.exists("res://scripts/ui/hud.gd"):
		hud = (load("res://scripts/ui/hud.gd") as GDScript).new()
		hud.set(&"player", self)
		add_child(hud)
	_on_inventory_changed()
	call_deferred(&"_store_spawn")
	capture_mouse(true)

func _store_spawn() -> void:
	_spawn_origin = global_position

func capture_mouse(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		if ui_open:
			return # панель закрывает сам UI
		_toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if not input_enabled or ui_open or get_tree().paused or not alive:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		look(mm.relative * Settings.mouse_sensitivity)
	elif event.is_action_pressed(&"attack"):
		swing()
	elif event.is_action_pressed(&"aim"):
		use_selected()
	elif event.is_action_pressed(&"interact"):
		interact()
	elif event.is_action_pressed(&"drop"):
		drop_selected()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			inventory.select(posmod(inventory.selected - 1, Inventory.HOTBAR))
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			inventory.select(posmod(inventory.selected + 1, Inventory.HOTBAR))
	else:
		for i in Inventory.HOTBAR:
			if event.is_action_pressed(StringName("hotbar_%d" % (i + 1))):
				inventory.select(i)
				break

func _toggle_pause() -> void:
	set_paused(not get_tree().paused)

func set_paused(p: bool) -> void:
	get_tree().paused = p
	capture_mouse(not p and not ui_open)
	Events.pause_toggled.emit(p)

## UI открыл/закрыл панель (инвентарь, крафт): мышь свободна, игрок стоит.
func set_ui_open(on: bool) -> void:
	ui_open = on
	capture_mouse(not on and not get_tree().paused)

## Поворот взгляда (dx, dy в радианах).
func look(rel: Vector2) -> void:
	_yaw -= rel.x
	var dy := rel.y * (-1.0 if Settings.invert_y else 1.0)
	_pitch = clampf(_pitch - dy, deg_to_rad(-88.0), deg_to_rad(88.0))

func set_look(yaw: float, pitch: float) -> void:
	_yaw = yaw
	_pitch = pitch

func _physics_process(delta: float) -> void:
	var __pt := PerfStats.begin()
	_perf_physics(delta)
	PerfStats.end(&"player", __pt)

func _perf_physics(delta: float) -> void:
	if get_tree().paused:
		return
	if not alive:
		_dead_process(delta)
		return
	_update_vitals(delta)
	if not alive:
		return
	var wl := water_level()
	var depth := wl - global_position.y
	swimming = depth > SWIM_DEPTH or (swimming and depth > SWIM_DEPTH - 0.25)
	if swimming:
		_swim_process(delta, wl)
		return
	_gamepad_look(delta)
	var wish := Vector2.ZERO
	var want_sprint := false
	var want_crouch := false
	var want_jump := false
	if input_enabled and not ui_open:
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
	if depth > 0.4:
		speed *= WADE_MUL
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
		if _fall_speed > FALL_SAFE_SPEED and wl - global_position.y < 0.5:
			apply_damage((_fall_speed - FALL_SAFE_SPEED) * FALL_DMG_PER_MS, null, &"fall")
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
	var fov_target := Settings.fov + (5.0 if sprinting else 0.0) - fov_zoom
	camera.fov = lerpf(camera.fov, fov_target, clampf(delta * 6.0, 0.0, 1.0))
	hands.set_items_hidden(swimming) # плывём — руки гребут, предмет убран
	hands.animate(delta, clampf(hspeed / RUN_SPEED, 0.0, 1.0), sprinting, tired_amount, is_on_floor(), carrying_log, swimming)

# --- действия ---

func swing() -> void:
	if not alive or carrying_log or swimming:
		return
	hands.play_swing(hands.swing_kind_for(held_item()))

func held_item() -> StringName:
	if carrying_log or inventory == null:
		return &""
	var id := inventory.selected_id()
	var d := Items.get_item(id)
	# В руке «держим» только то, чем можно бить/что можно съесть/поставить.
	if d == null:
		return &""
	return id

func _on_swing_impact() -> void:
	var space := get_world_3d().direct_space_state
	var from := camera.global_position
	var id := held_item()
	var reach := float(PlayerItems.data(id).get("reach", SWING_REACH))
	var to := from - camera.global_transform.basis.z * reach
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	q.collide_with_areas = true
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		hit = {"miss": true}
	hit["tool"] = PlayerItems.tool_of(id)
	hit["damage"] = PlayerItems.damage_of(id)
	hit["item"] = id
	swing_hit.emit(hit)
	Events.player_swing.emit(self, hit)
	if hit.has("collider"):
		var target := _find_with_method(hit.collider as Node, &"on_hit")
		if target:
			target.call(&"on_hit", self, hit)
		else:
			var victim := _find_with_method(hit.collider as Node, &"apply_damage")
			if victim and victim != self:
				var kind: StringName = &"axe" if hit.tool == &"axe" else &"melee"
				victim.call(&"apply_damage", float(hit.damage), self, kind)

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
	elif can_drink_here():
		drink_water()

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
	elif can_drink_here():
		text = "E — попить воды"
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

# ======================= вода =======================

## Уровень воды: у мира (группа `world`) — water_level(); иначе 0.
func water_level() -> float:
	var w := get_tree().get_first_node_in_group(&"world")
	if w and w.has_method(&"water_level"):
		return float(w.call(&"water_level"))
	return 0.0

func is_in_water() -> bool:
	return water_level() - global_position.y > 0.05

func is_underwater() -> bool:
	return camera != null and camera.global_position.y < water_level() - 0.06

func _swim_process(delta: float, wl: float) -> void:
	_gamepad_look(delta)
	var wish := Vector2.ZERO
	var fast := false
	var up := false
	var down := false
	if input_enabled and not ui_open:
		wish = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
		fast = Input.is_action_pressed(&"sprint") and not tired and stamina > 0.0
		up = Input.is_action_pressed(&"jump")
		down = Input.is_action_pressed(&"crouch")
	_update_stamina_state(delta)
	sprinting = false
	crouching = false
	_cur_height = HEIGHT
	_capsule.height = HEIGHT
	_shape.position.y = HEIGHT * 0.5
	var speed := SWIM_FAST if fast and wish.length() > 0.1 else SWIM_SPEED
	if fast and wish.length() > 0.1:
		_use_stamina(STAMINA_RUN_COST * 0.8 * delta)
	speed *= lerpf(1.0, 0.75, tired_amount) * swim_mul
	# Под водой плывём туда, куда смотрим (с наклоном), на поверхности — горизонтально.
	var look_basis := Basis(Vector3.UP, _yaw)
	if is_underwater():
		look_basis = look_basis * Basis(Vector3.RIGHT, _pitch)
	var dir := look_basis * Vector3(wish.x, 0.0, wish.y)
	if dir.length() > 1.0:
		dir = dir.normalized()
	var target := dir * speed
	# Плавучесть: держим глаза над водой, если не ныряем.
	var float_y := wl - (HEIGHT - EYE_OFFSET) + SWIM_FLOAT_EYE
	var vy := target.y
	if down:
		vy = -DIVE_SPEED
	elif up:
		vy = DIVE_SPEED if global_position.y < float_y - 0.05 else (float_y - global_position.y) * 4.0
	elif not is_underwater() or wish.length() < 0.1:
		vy += clampf((float_y - global_position.y) * 2.5, -1.5, 1.2)
	velocity = velocity.lerp(Vector3(target.x, vy, target.z), clampf(delta * 4.0, 0.0, 1.0))
	move_and_slide()
	_fall_speed = 0.0
	_was_on_floor = is_on_floor()
	_update_camera(delta, Vector2(velocity.x, velocity.z).length() * 0.6)
	_update_interact_hint()

# ======================= выживание =======================

func _update_vitals(delta: float) -> void:
	var mul := 1.5 if sprinting else 1.0
	hunger = maxf(0.0, hunger - HUNGER_PER_SEC * mul * delta)
	thirst = maxf(0.0, thirst - THIRST_PER_SEC * mul * delta)
	# Дыхание.
	if is_underwater():
		breath = maxf(0.0, breath - BREATH_MAX / BREATH_TIME * delta)
		if breath <= 0.0:
			apply_damage(DROWN_DMG * delta, null, &"drown")
	else:
		breath = minf(BREATH_MAX, breath + 30.0 * delta)
	# Голод/жажда на нуле — урон; сытый — медленное лечение.
	if hunger <= 0.0 or thirst <= 0.0:
		_starve_acc += delta
		if _starve_acc >= 1.0:
			_starve_acc -= 1.0
			apply_damage(STARVE_DMG * (2.0 if hunger <= 0.0 and thirst <= 0.0 else 1.0), null, &"starve")
	elif hunger > 60.0 and thirst > 60.0 and health < max_health:
		health = minf(max_health, health + REGEN_PER_SEC * delta)

func apply_damage(amount: float, source: Node = null, kind: StringName = &"melee") -> void:
	if not alive or amount <= 0.0:
		return
	# SUPPLY: бронежилет гасит часть урона пуль/осколков
	var sup := get_tree().get_first_node_in_group(&"supply") if is_inside_tree() else null
	if sup and sup.has_method(&"filter_damage"):
		amount = float(sup.call(&"filter_damage", self, amount, kind))
	health = maxf(0.0, health - amount)
	last_damage_kind = kind
	Events.character_damaged.emit(self, amount, source)
	if hud and hud.has_method(&"flash_damage") and kind != &"starve":
		hud.call(&"flash_damage", clampf(amount / 30.0, 0.15, 1.0))
	if health <= 0.0:
		die(source, kind)

func is_dead() -> bool:
	return not alive

func die(killer: Node = null, kind: StringName = &"") -> void:
	if not alive:
		return
	alive = false
	last_damage_kind = kind
	velocity = Vector3.ZERO
	sprinting = false
	swimming = false
	if carrying_log and carried_object and carried_object.has_method(&"interact"):
		carried_object.call(&"interact", self) # уронить бревно
	set_carrying_log(false)
	hands.visible = false
	_drop_on_death()
	Events.character_died.emit(self, killer)
	if Game.can_respawn(team):
		respawn_left = Game.RESPAWN_TIME
	else:
		eliminated = true
		respawn_left = 0.0

## Ресурсы и еда выпадают мешком; инструменты, оружие и флаг остаются (как в Bed Wars).
func _drop_on_death() -> void:
	var drop: Array[Dictionary] = []
	for i in Inventory.SIZE:
		var s := inventory.get_slot(i)
		if s.is_empty():
			continue
		var d := Items.get_item(s.id)
		if d and d.kind in [&"tool", &"weapon"] or s.id == &"flag":
			continue
		drop.append(inventory.take_slot(i))
	if not drop.is_empty() and is_inside_tree():
		ItemPickup.spawn(get_parent(), global_position + Vector3.UP * 0.6, drop)

func _dead_process(delta: float) -> void:
	_death_roll = minf(1.0, _death_roll + delta * 1.4)
	head.position.y = lerpf(head.position.y, 0.35, clampf(delta * 3.0, 0.0, 1.0))
	head.rotation.z = lerpf(0.0, deg_to_rad(70.0), _death_roll)
	if eliminated:
		return
	if not Game.can_respawn(team):
		eliminated = true
		return
	respawn_left -= delta
	if respawn_left <= 0.0:
		respawn()

func respawn() -> void:
	alive = true
	eliminated = false
	health = max_health
	hunger = maxf(hunger, 50.0)
	thirst = maxf(thirst, 50.0)
	breath = BREATH_MAX
	stamina = STAMINA_MAX
	tired = false
	tired_amount = 0.0
	_death_roll = 0.0
	hands.visible = true
	velocity = Vector3.ZERO
	global_position = respawn_position()
	Events.character_spawned.emit(self)

func respawn_position() -> Vector3:
	if team >= 0 and team < Game.teams.size() and Game.teams[team].flag_placed:
		return Game.teams[team].flag_pos + Vector3(1.6, 0.3, 1.6)
	var w := get_tree().get_first_node_in_group(&"world")
	if w and w.has_method(&"spawn_point"):
		return w.call(&"spawn_point", team) as Vector3
	return _spawn_origin + Vector3.UP * 0.3

# ======================= предметы =======================

func _on_inventory_changed() -> void:
	if hands:
		hands.set_held(held_item())

## ПКМ: съесть/выпить/использовать выбранное.
func use_selected() -> void:
	if not alive or carrying_log or hands.is_busy():
		return
	var id := held_item()
	if id != &"" and _try_feed_target(id):
		return
	# SURVIVAL: тара, наборы построек, кокос и т.п. (true — обработано там)
	var sv := get_tree().get_first_node_in_group(&"survival")
	if id != &"" and sv and sv.has_method(&"on_use_item") and bool(sv.call(&"on_use_item", self, id)):
		return
	if id == &"" or not PlayerItems.is_consumable(id):
		return
	var dd := PlayerItems.data(id)
	if dd.has("hunger") and not dd.has("thirst") and hunger >= 99.0 and not (dd.has("health") and health < max_health):
		Events.toast.emit("Не хочется есть")
		return
	_pending_use = id
	hands.play_use()

## FAUNA-хук: ПКМ с едой, глядя на животное, — покормить (on_feed(self, id) -> bool).
func _try_feed_target(id: StringName) -> bool:
	ray.force_raycast_update()
	if not ray.is_colliding():
		return false
	var t := _find_with_method(ray.get_collider() as Node, &"on_feed")
	if t and bool(t.call(&"on_feed", self, id)):
		inventory.remove(id, 1)
		return true
	return false

func _on_use_finished() -> void:
	var id := _pending_use
	_pending_use = &""
	if id == &"" or not inventory.remove(id, 1):
		return
	consume(id)

## Эффект употребления предмета (без анимации) — можно звать из других модулей.
func consume(id: StringName) -> void:
	var dd := PlayerItems.data(id)
	hunger = minf(100.0, hunger + float(dd.get("hunger", 0.0)))
	thirst = minf(100.0, thirst + float(dd.get("thirst", 0.0)))
	health = minf(max_health, health + float(dd.get("health", 0.0)))
	var risk := float(dd.get("raw_risk", 0.0))
	if risk > 0.0 and randf() < risk:
		apply_damage(randf_range(6.0, 12.0), null, &"food")
		Events.toast.emit("Живот скрутило — сырое лучше жарить")
	# SURVIVAL: тара назад, морская вода, яд/травы, гниль, свежесть
	var sv := get_tree().get_first_node_in_group(&"survival") if is_inside_tree() else null
	if sv and sv.has_method(&"on_consumed"):
		sv.call(&"on_consumed", self, id)

## Можно попить: стоим в воде или смотрим на воду рядом.
func can_drink_here() -> bool:
	if not alive or carrying_log:
		return false
	var wl := water_level()
	if is_in_water() and not swimming:
		return true
	var eye := camera.global_position
	var dir := get_look_dir()
	if dir.y >= -0.05 or eye.y <= wl:
		return false
	var t := (wl - eye.y) / dir.y
	if t > DRINK_REACH:
		return false
	# Луч до поверхности воды не упирается в землю.
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(eye, eye + dir * t)
	q.exclude = [get_rid()]
	return space.intersect_ray(q).is_empty()

func drink_water() -> void:
	# SURVIVAL: морская/пресная вода, наполнение тары (true — обработано там)
	var sv := get_tree().get_first_node_in_group(&"survival")
	if sv and sv.has_method(&"on_drink_water") and bool(sv.call(&"on_drink_water", self)):
		return
	if thirst >= 99.0:
		Events.toast.emit("Не хочется пить")
		return
	thirst = minf(100.0, thirst + 25.0)
	hands.play_use()
	Events.toast.emit("Ты попил воды")

## G: выбросить выбранный стек.
func drop_selected() -> void:
	if carrying_log or inventory == null:
		return
	drop_slot(inventory.selected)

## Выбросить стек из ячейки i перед собой (G, перетаскивание за панель).
func drop_slot(i: int) -> void:
	if inventory == null:
		return
	var s := inventory.take_slot(i)
	if s.is_empty():
		return
	var pos := camera.global_position + get_look_dir() * 0.7
	var arr: Array[Dictionary] = [s]
	ItemPickup.spawn(get_parent(), pos, arr, get_look_dir() * 2.0)
