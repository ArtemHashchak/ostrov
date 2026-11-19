class_name SandboxCheats
extends Node
## Читы «Полигона»: полёт сквозь стены (V), бессмертие, бесконечные предметы,
## телепорт. Работает поверх обычного игрока, не меняя его код.

signal changed

const FLY_MIN := 3.0
const FLY_MAX := 120.0

var player: Player
var fly := false
var god := true
var infinite := false
var fly_speed := 14.0
var _snapshot: Dictionary = {}   # id → сколько должно быть (бесконечные предметы)
var _inf_t := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_physics_priority = 10

func _input(event: InputEvent) -> void:
	if player == null or not is_instance_valid(player) or get_tree().paused or player.ui_open:
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		if (event as InputEventKey).physical_keycode == KEY_V:
			# V с автоматом в руке — переключение режима огня (CombatController), не полёт
			var wd := WeaponDef.of(StringName(player.call(&"held_item"))) if player.has_method(&"held_item") else null
			if wd and wd.fire_modes.size() > 1 and not fly:
				return
			set_fly(not fly)
			get_viewport().set_input_as_handled()
			return
	if fly and event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			fly_speed = minf(FLY_MAX, fly_speed * 1.25)
			_toast("Скорость полёта: %d м/с" % int(fly_speed))
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			fly_speed = maxf(FLY_MIN, fly_speed / 1.25)
			_toast("Скорость полёта: %d м/с" % int(fly_speed))
			get_viewport().set_input_as_handled()

func _toast(t: String) -> void:
	Events.toast.emit(t)

func set_fly(on: bool) -> void:
	if player == null:
		return
	fly = on
	player.set_physics_process(not on)
	player.velocity = Vector3.ZERO
	var shape := player.get(&"_shape") as CollisionShape3D
	if shape:
		shape.disabled = on
	_toast("Полёт: вкл (WASD, Пробел — вверх, Ctrl — вниз, Shift — быстрее, колесо — скорость)" if on else "Полёт: выкл")
	changed.emit()

func set_god(on: bool) -> void:
	god = on
	_toast("Бессмертие: вкл" if on else "Бессмертие: выкл")
	changed.emit()

func set_infinite(on: bool) -> void:
	infinite = on
	_snapshot.clear()
	if on and player:
		_take_snapshot()
	_toast("Бесконечные предметы: вкл" if on else "Бесконечные предметы: выкл")
	changed.emit()

func _take_snapshot() -> void:
	_snapshot.clear()
	for i in Inventory.SIZE:
		var s := player.inventory.get_slot(i)
		if not s.is_empty():
			_snapshot[s.id] = player.inventory.count(s.id)

## Переместить игрока; look — точка, куда смотреть.
func teleport(pos: Vector3, look: Variant = null) -> void:
	if player == null:
		return
	if player.get(&"carrying_log"):
		player.set_carrying_log(false)
	player.velocity = Vector3.ZERO
	player.global_position = pos
	if look is Vector3:
		var eye := pos + Vector3.UP * 1.66
		var d: Vector3 = (look as Vector3) - eye
		var yaw := atan2(-d.x, -d.z)
		var pitch := atan2(d.y, Vector2(d.x, d.z).length())
		player.set_look(yaw, clampf(pitch, -1.2, 1.2))
	player.call(&"_store_spawn")

func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	if god:
		_god()
	if infinite:
		_inf_t -= delta
		if _inf_t <= 0.0:
			_inf_t = 0.4
			_refill()
	if fly and player.alive:
		_fly(delta)

func _god() -> void:
	if not player.alive:
		return
	player.health = player.max_health
	player.hunger = 100.0
	player.thirst = 100.0
	player.breath = Player.BREATH_MAX
	player.stamina = Player.STAMINA_MAX
	player.tired = false
	player.poison = 0.0
	player.poison_time = 0.0

## Бесконечные предметы: количество каждого предмета не убывает
## (новые предметы запоминаются по максимуму).
func _refill() -> void:
	var inv := player.inventory
	for i in Inventory.SIZE:
		var s := inv.get_slot(i)
		if not s.is_empty():
			_snapshot[s.id] = maxi(int(_snapshot.get(s.id, 0)), inv.count(s.id))
	for id: StringName in _snapshot.keys():
		var have := inv.count(id)
		var want := int(_snapshot[id])
		if have < want:
			inv.add(id, want - have)

func _fly(delta: float) -> void:
	var wish := Vector3.ZERO
	if not player.ui_open:
		var v := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
		var cam := player.camera.global_transform.basis
		wish = cam.x * v.x + (-cam.z) * (-v.y)
		if Input.is_action_pressed(&"jump"):
			wish += Vector3.UP
		if Input.is_action_pressed(&"crouch"):
			wish += Vector3.DOWN
	if wish.length() > 1.0:
		wish = wish.normalized()
	var sp := fly_speed * (4.0 if Input.is_action_pressed(&"sprint") else 1.0)
	player.velocity = player.velocity.lerp(wish * sp, clampf(delta * 8.0, 0.0, 1.0))
	player.global_position += player.velocity * delta
	player.call(&"_update_camera", delta, 0.0)
	player.call(&"_update_interact_hint")
