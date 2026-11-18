class_name Bot
extends CharacterBody3D
## Бот-соперник: такой же персонаж, как игрок (здоровье, голод, жажда, яд, плавание,
## инвентарь, урон по контракту apply_damage/on_hit), но управляется BotBrain.
## Возрождается у флага своей команды, пока флаг цел (Game.request_respawn).

const HEIGHT := 1.8
const RADIUS := 0.32
const EYE := 1.62
const WALK_SPEED := 3.2
const RUN_SPEED := 5.4
const SWIM_SPEED := 1.9
const CARRY_MUL := 0.72
const ACCEL := 10.0
const JUMP_V := 6.2
const MAX_HEALTH := 100.0
const HUNGER_PER_SEC := 100.0 / (75.0 * 60.0)
const THIRST_PER_SEC := 100.0 / (50.0 * 60.0)
const STARVE_DMG := 0.5
const REGEN_PER_SEC := 0.25
const SWIM_DEPTH := 1.25
const BREATH_MAX := 100.0
const DROWN_DMG := 12.0
const MAX_LOGS := 2
const FALL_SAFE_SPEED := 11.0
const FALL_DMG_PER_MS := 7.0

## Параметры сложности: реакция (с), разброс прицела (°), скорость, дальность агрессии (м),
## сколько глубокой воды готов проплыть (м), период «мысли» (с), урон.
const DIFFICULTY := {
	&"easy": {"reaction": 0.85, "spread": 7.0, "speed": 0.9, "aggro": 18.0, "swim": 0.0, "think": 0.6, "dmg": 0.8, "work": 0.8},
	&"normal": {"reaction": 0.45, "spread": 3.5, "speed": 1.0, "aggro": 28.0, "swim": 35.0, "think": 0.4, "dmg": 1.0, "work": 1.0},
	&"hard": {"reaction": 0.25, "spread": 1.5, "speed": 1.08, "aggro": 40.0, "swim": 60.0, "think": 0.25, "dmg": 1.15, "work": 1.25},
}

var team: int = 1
var difficulty: StringName = &"normal"
var display_name: String = ""
var index: int = 0

var health: float = MAX_HEALTH
var max_health: float = MAX_HEALTH
var hunger: float = 100.0
var thirst: float = 100.0
var breath: float = BREATH_MAX
var poison: float = 0.0
var poison_time: float = 0.0
var alive: bool = true
var eliminated: bool = false
var respawn_left: float = 0.0
var swimming: bool = false
var last_damage_kind: StringName = &""

var carrying_log: bool = false
var carried_object: Node = null
var logs_carried: int = 0
var inventory: Inventory
var current_tool: StringName = &"hand"   # для Flora.tool_of
var held_id: StringName = &""

var brain: BotBrain
var team_ai: BotTeam
var model: BotModel
var nav: BotNav

## Путь: [{p, water, deck}] — ведёт BotBrain через BotNav.
var path: Array[Dictionary] = []
var arrive_dist: float = 1.0
var running: bool = false
var aim_target: Vector3 = Vector3.ZERO
var aiming: bool = false
var last_attacker: Node = null
var last_attacked_t: float = -100.0
var stuck: int = 0                       # сколько раз застрял на текущем пути

var _shape: CollisionShape3D
var _gravity: float = 19.6
var _starve_acc: float = 0.0
var _steer_t: float = 0.0
var _steer_dir: Vector3 = Vector3.ZERO
var _progress_t: float = 0.0
var _progress_pos: Vector3 = Vector3.ZERO
var _unstick_t: float = 0.0
var _unstick_dir: Vector3 = Vector3.ZERO
var _yaw: float = 0.0
var _think_t: float = 0.0
var _fall_speed: float = 0.0
var _water_cache_t: float = 0.0
var _wl: float = 0.0
var _ground_h: float = -100.0
var _dead_t: float = 0.0
var _world: Node = null

func setup(team_id: int, diff: StringName, idx: int) -> Bot:
	team = team_id
	difficulty = diff if DIFFICULTY.has(diff) else &"normal"
	index = idx
	display_name = "%s — бот %d" % [Game.TEAM_NAMES[posmod(team, 4)], idx + 1]
	name = "Bot_%d_%d" % [team, idx]
	return self

func cfg(key: String) -> float:
	return float((DIFFICULTY[difficulty] as Dictionary)[key])

func _ready() -> void:
	add_to_group(&"characters")
	add_to_group(&"bots")
	collision_layer = 1
	collision_mask = 1
	floor_snap_length = 0.45
	floor_max_angle = deg_to_rad(50.0)
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * 2.0
	_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = HEIGHT
	_shape.shape = cap
	_shape.position = Vector3(0, HEIGHT * 0.5, 0)
	add_child(_shape)
	inventory = Inventory.new()
	inventory.name = "Inventory"
	add_child(inventory)
	model = BotModel.new().setup(team, team * 7 + index * 3)
	model.name = "Model"
	add_child(model)
	_world = get_tree().get_first_node_in_group(&"world")
	_think_t = randf() * 0.5
	Game.register_character(self, team)
	Events.character_spawned.emit(self)

# ======================================================== интерфейс персонажа

func is_dead() -> bool:
	return not alive

func get_eye_position() -> Vector3:
	return global_position + Vector3.UP * (EYE if not swimming else 0.35)

func get_look_dir() -> Vector3:
	if aiming:
		return (aim_target - get_eye_position()).normalized()
	return -global_basis.z

func get_tool() -> StringName:
	return current_tool

func water_level() -> float:
	return _wl

func is_in_water() -> bool:
	return alive and _wl - global_position.y > 0.5 and _ground_h < _wl - 0.4

func is_underwater() -> bool:
	return alive and _wl - global_position.y > 1.75

func set_carrying_log(on: bool, obj: Node = null) -> void:
	carrying_log = on
	carried_object = obj
	if not on:
		logs_carried = 0
	model.set_logs(logs_carried if on else 0)

func add_log() -> bool:
	if logs_carried >= MAX_LOGS:
		return false
	logs_carried += 1
	carrying_log = true
	model.set_logs(logs_carried)
	return true

func take_logs(n: int) -> int:
	var k := mini(n, logs_carried)
	logs_carried -= k
	carrying_log = logs_carried > 0
	model.set_logs(logs_carried)
	return k

func inv_count(id: StringName) -> int:
	var n := inventory.count(id)
	if id == &"stone":
		n += inventory.count(&"rock")
	elif id == &"rock":
		n += inventory.count(&"stone")
	return n

func inv_remove(id: StringName, n: int) -> bool:
	if inventory.remove(id, n):
		return true
	if id == &"stone":
		return inventory.remove(&"rock", n)
	if id == &"rock":
		return inventory.remove(&"stone", n)
	return false

## В руку — оружие/инструмент для анимации и Flora.tool_of.
func hold(id: StringName) -> void:
	held_id = id
	current_tool = PlayerItems.tool_of(id) if id != &"" else &"hand"
	model.set_held(id)

func swing_anim() -> void:
	model.action(&"swing")

func apply_damage(amount: float, source: Node = null, kind: StringName = &"melee") -> void:
	if not alive or amount <= 0.0:
		return
	if source and source != self:
		var st: Variant = source.get(&"team")
		var src_ch := Game.character_of(source)
		if src_ch and src_ch != self and src_ch.get(&"team") != null and int(src_ch.get(&"team")) == team and kind != &"explosion" and kind != &"fire":
			return # свои по своим не бьют (кроме огня/взрыва)
		if st == null or int(st) != team:
			last_attacker = src_ch if src_ch else source
			last_attacked_t = Game.match_time
	# SUPPLY: бронежилет гасит часть урона пуль/осколков
	var sup := get_tree().get_first_node_in_group(&"supply") if is_inside_tree() else null
	if sup and sup.has_method(&"filter_damage"):
		amount = float(sup.call(&"filter_damage", self, amount, kind))
	health = maxf(0.0, health - amount)
	last_damage_kind = kind
	Events.character_damaged.emit(self, amount, source)
	if health <= 0.0:
		die(source, kind)

func on_hit(by: Node, hit: Dictionary) -> void:
	var dmg := float(hit.get("damage", 0.0))
	if dmg <= 0.0:
		var t := String(hit.get("tool", "hand"))
		dmg = 14.0 if t.begins_with("axe") else (10.0 if t == "spear" else (7.0 if t == "rock" else 4.0))
	apply_damage(dmg, by, &"axe" if String(hit.get("tool", "")).begins_with("axe") else &"melee")

func die(killer: Node = null, kind: StringName = &"") -> void:
	if not alive:
		return
	alive = false
	last_damage_kind = kind
	velocity = Vector3.ZERO
	swimming = false
	path.clear()
	aiming = false
	_drop_on_death()
	logs_carried = 0
	carrying_log = false
	model.set_logs(0)
	model.set_dead(true)
	_shape.set_deferred(&"disabled", true)
	_dead_t = 0.0
	if brain:
		brain.on_died()
	Events.character_died.emit(self, killer)
	respawn_left = Game.RESPAWN_TIME
	eliminated = not Game.can_respawn(team)

## Ресурсы и еда выпадают мешком; инструменты и оружие остаются (как у игрока).
func _drop_on_death() -> void:
	var drop: Array[Dictionary] = []
	for i in Inventory.SIZE:
		var s := inventory.get_slot(i)
		if s.is_empty():
			continue
		var d := Items.get_item(s.id)
		if (d and d.kind in [&"tool", &"weapon"]) or Combat.is_weapon(s.id):
			continue
		drop.append(inventory.take_slot(i))
	if not drop.is_empty() and is_inside_tree():
		ItemPickup.spawn(get_parent(), global_position + Vector3.UP * 0.6, drop)

func respawn() -> void:
	alive = true
	eliminated = false
	health = max_health
	hunger = maxf(hunger, 50.0)
	thirst = maxf(thirst, 50.0)
	breath = BREATH_MAX
	poison = 0.0
	poison_time = 0.0
	velocity = Vector3.ZERO
	path.clear()
	stuck = 0
	_shape.set_deferred(&"disabled", false)
	global_position = Game.respawn_position(team)
	model.set_dead(false)
	if brain:
		brain.on_respawned()
	Events.character_spawned.emit(self)

func _dead_process(delta: float) -> void:
	_dead_t += delta
	if eliminated:
		if _dead_t > 20.0 and model.visible:
			model.visible = false
		return
	respawn_left -= delta
	if respawn_left <= 0.0:
		if not Game.request_respawn(self):
			eliminated = true

# ======================================================== движение

func set_path(p: Array[Dictionary], arrive: float = 1.0) -> void:
	path = p
	arrive_dist = arrive
	stuck = 0
	_progress_t = 0.0
	_progress_pos = global_position

func stop() -> void:
	path.clear()

func has_path() -> bool:
	return not path.is_empty()

func _physics_process(delta: float) -> void:
	if not alive:
		_dead_process(delta)
		if not is_on_floor():
			velocity.y -= _gravity * delta
			velocity.x = 0.0
			velocity.z = 0.0
			move_and_slide()
		return
	_update_water(delta)
	_vitals(delta)
	_think_t -= delta
	if _think_t <= 0.0 and brain:
		_think_t = cfg("think") * randf_range(0.85, 1.15)
		brain.think(cfg("think"))
	if brain:
		brain.act(delta)
	_move(delta)

func _update_water(delta: float) -> void:
	_water_cache_t -= delta
	if _water_cache_t > 0.0 and _world:
		return
	_water_cache_t = 0.15
	if _world == null:
		_world = get_tree().get_first_node_in_group(&"world")
		if _world == null:
			return
	var p := global_position
	_wl = float(_world.call(&"wave_height", p.x, p.z))
	_ground_h = float(_world.call(&"height_at", p.x, p.z))
	var depth := _wl - p.y
	var was := swimming
	swimming = depth > SWIM_DEPTH and _ground_h < _wl - SWIM_DEPTH and not _on_deck()
	if swimming and not was:
		_fall_speed = 0.0

func _on_deck() -> bool:
	if not is_on_floor():
		return false
	var c := get_last_slide_collision()
	if c == null:
		return false
	var n := c.get_collider() as Node
	for i in 4:
		if n == null:
			return false
		if n.is_in_group(&"raft_deck"):
			return true
		n = n.get_parent()
	return false

func _vitals(delta: float) -> void:
	hunger = maxf(0.0, hunger - HUNGER_PER_SEC * delta)
	thirst = maxf(0.0, thirst - THIRST_PER_SEC * delta)
	if hunger <= 0.0 or thirst <= 0.0:
		_starve_acc += delta
		if _starve_acc >= 1.0:
			_starve_acc -= 1.0
			apply_damage(STARVE_DMG, null, &"starve")
	elif hunger > 60.0 and thirst > 60.0 and health < max_health:
		health = minf(max_health, health + REGEN_PER_SEC * delta)
	if is_underwater():
		breath = maxf(0.0, breath - BREATH_MAX / 30.0 * delta)
		if breath <= 0.0:
			apply_damage(DROWN_DMG * delta, null, &"drown")
	else:
		breath = minf(BREATH_MAX, breath + 25.0 * delta)

func _move(delta: float) -> void:
	var wish := Vector3.ZERO
	var allow_water := false
	if not path.is_empty():
		var wp: Dictionary = path[0]
		var tgt: Vector3 = wp.p
		var to := tgt - global_position
		to.y = 0.0
		var last := path.size() == 1
		var reach := arrive_dist if last else (0.7 if bool(wp.get("deck", false)) else 1.2)
		if to.length() < reach:
			path.pop_front()
			_progress_t = 0.0
			_progress_pos = global_position
		else:
			allow_water = bool(wp.get("water", false)) or swimming
			wish = _steer(to.normalized(), allow_water, bool(wp.get("deck", false)), delta)
	var spd := (RUN_SPEED if running else WALK_SPEED) * cfg("speed")
	if carrying_log:
		spd *= CARRY_MUL
	if swimming:
		spd = SWIM_SPEED * cfg("speed")
	var hv := Vector3(velocity.x, 0, velocity.z)
	hv = hv.move_toward(wish * spd, ACCEL * delta * spd)
	velocity.x = hv.x
	velocity.z = hv.z
	if swimming:
		var target_y := _wl - 1.45
		velocity.y = clampf((target_y - global_position.y) * 3.0, -2.0, 2.0)
	else:
		if not is_on_floor():
			velocity.y -= _gravity * delta
			_fall_speed = maxf(_fall_speed, -velocity.y)
		else:
			if _fall_speed > FALL_SAFE_SPEED:
				apply_damage((_fall_speed - FALL_SAFE_SPEED) * FALL_DMG_PER_MS, null, &"fall")
			_fall_speed = 0.0
	move_and_slide()
	if wish != Vector3.ZERO and not swimming and is_on_wall():
		_step_up(wish)
	# смотреть: на цель прицела, иначе по ходу
	var face := Vector3.ZERO
	if aiming:
		face = aim_target - global_position
	elif hv.length() > 0.3:
		face = hv
	face.y = 0.0
	if face.length() > 0.05:
		var want := atan2(-face.x, -face.z)
		_yaw = lerp_angle(_yaw, want, clampf(delta * 9.0, 0.0, 1.0))
		rotation.y = _yaw
	model.update_pose(delta, hv.length(), swimming, running)
	_check_progress(delta, wish)

## Шаг на невысокий уступ (борт плота, камень, ступень) — до 0.65 м.
func _step_up(wish: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var ahead := global_position + wish.normalized() * (RADIUS + 0.25)
	var q := PhysicsRayQueryParameters3D.create(ahead + Vector3.UP * 0.75, ahead + Vector3.DOWN * 0.1)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var top := (hit.position as Vector3).y
	var rise := top - global_position.y
	if rise > 0.04 and rise < 0.68 and (hit.normal as Vector3).y > 0.6:
		global_position = Vector3(global_position.x, top + 0.03, global_position.z) + wish.normalized() * 0.12
		velocity.y = maxf(velocity.y, 0.0)

func face_to(p: Vector3) -> void:
	var f := p - global_position
	f.y = 0.0
	if f.length() > 0.05:
		_yaw = atan2(-f.x, -f.z)
		rotation.y = _yaw

## Обход препятствий: выбираем из веера направлений ближайшее к нужному без воды/обрыва/стены.
func _steer(desired: Vector3, allow_water: bool, deck: bool, delta: float) -> Vector3:
	if _unstick_t > 0.0:
		_unstick_t -= delta
		return _unstick_dir
	_steer_t -= delta
	if _steer_t > 0.0 and _steer_dir != Vector3.ZERO and _steer_dir.dot(desired) > 0.3:
		return _steer_dir
	_steer_t = 0.2
	if deck or _world == null:
		_steer_dir = desired
		return desired
	var best := desired
	var best_s := -INF
	var here_h := global_position.y
	var wl := _wl
	for a in [0.0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6, 2.4, -2.4]:
		var d := desired.rotated(Vector3.UP, float(a))
		var s := d.dot(desired) * 2.0
		var p := global_position + d * 1.8
		var gh := float(_world.call(&"height_at", p.x, p.z))
		if not allow_water and gh < wl - 0.9:
			s -= 4.0
		if gh - here_h > 1.4 and not swimming:
			s -= 3.0
		if s > best_s - 0.01 and _blocked(d):
			s -= 2.5
		if s > best_s:
			best_s = s
			best = d
	_steer_dir = best
	return best

func _blocked(d: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 0.9
	var q := PhysicsRayQueryParameters3D.create(from, from + d * 1.1)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return false
	var c := hit.collider as Node
	return not (c is CharacterBody3D)

func _check_progress(delta: float, wish: Vector3) -> void:
	if wish == Vector3.ZERO:
		_progress_t = 0.0
		_progress_pos = global_position
		return
	_progress_t += delta
	if _progress_t < 1.6:
		return
	var moved := (global_position - _progress_pos).length()
	_progress_t = 0.0
	_progress_pos = global_position
	if moved < 0.6:
		stuck += 1
		# прыжок + шаг в сторону
		if is_on_floor() and not swimming:
			velocity.y = JUMP_V
		_unstick_dir = wish.rotated(Vector3.UP, (PI * 0.5 if randf() < 0.5 else -PI * 0.5) * randf_range(0.6, 1.0))
		_unstick_t = 0.9
	elif stuck > 0 and moved > 2.0:
		stuck = maxi(0, stuck - 1)
