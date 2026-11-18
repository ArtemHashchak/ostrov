class_name SpectatorCam
extends Camera3D
## Камера наблюдения после выбывания команды игрока.
## Облетает живых персонажей (сначала союзников, затем остальных);
## ЛКМ / Пробел / Tab — следующий, ПКМ — предыдущий, колесо — дальше/ближе.
## Если живых нет — медленно кружит над своим островом.

const HEIGHT := 4.5
var radius := 9.0
var team := 0
var _idx := 0
var _angle := 0.0
var _target: Node3D = null
var _pos_smooth := Vector3.ZERO
var _first := true

static func start(tree: SceneTree, own_team: int) -> SpectatorCam:
	var scene := tree.current_scene
	if scene == null:
		return null
	var old := tree.get_first_node_in_group(&"spectator_cam")
	if old:
		return old as SpectatorCam
	var cam := SpectatorCam.new()
	cam.team = own_team
	cam.add_to_group(&"spectator_cam")
	cam.far = 1500.0
	scene.add_child(cam)
	cam.current = true
	return cam

func _candidates() -> Array[Node3D]:
	var own: Array[Node3D] = []
	var other: Array[Node3D] = []
	for t in Game.teams:
		for m in t.members:
			if m is Node3D and Game.is_alive(m) and not (m as Node).is_in_group(&"player"):
				if t.id == team:
					own.append(m)
				else:
					other.append(m)
	own.append_array(other)
	return own

func _pick(step: int) -> void:
	var c := _candidates()
	if c.is_empty():
		_target = null
		return
	_idx = posmod(_idx + step, c.size())
	_target = c[_idx]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT: _pick(1)
			MOUSE_BUTTON_RIGHT: _pick(-1)
			MOUSE_BUTTON_WHEEL_UP: radius = maxf(radius - 1.0, 4.0)
			MOUSE_BUTTON_WHEEL_DOWN: radius = minf(radius + 1.0, 40.0)
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_SPACE or k == KEY_TAB:
			_pick(1)

func _process(delta: float) -> void:
	if _target == null or not Game.is_alive(_target):
		_pick(0)
	_angle += delta * 0.25
	var focus: Vector3
	var r := radius
	var h := HEIGHT
	if _target:
		focus = _target.global_position + Vector3(0, 1.2, 0)
	else:
		focus = Game.respawn_position(team) if team < Game.teams.size() else Vector3.ZERO
		r = 70.0
		h = 40.0
	var want := focus + Vector3(cos(_angle) * r, h, sin(_angle) * r)
	var w := get_tree().get_first_node_in_group(&"world")
	if w and w.has_method(&"height_at"):
		var gh: float = maxf(float(w.call(&"height_at", want.x, want.z)), 0.0)
		want.y = maxf(want.y, gh + 2.0)
	if _first:
		_pos_smooth = want
		_first = false
	else:
		_pos_smooth = _pos_smooth.lerp(want, clampf(delta * 3.0, 0.0, 1.0))
	global_position = _pos_smooth
	if global_position.distance_to(focus) > 0.1:
		look_at(focus)
