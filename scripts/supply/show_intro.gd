class_name ShowIntro
extends CanvasLayer
## Кат-сцена №2 «В эфире» (docs/LORE.md): ~9 с в начале матча — «дрон» пролетает над
## архипелагом по дуге вокруг Вулкана и снижается к домашнему острову игрока; плашки
## команд у их островов с «коэффициентами букмекеров», «● ПРЯМОЙ ЭФИР», титр «ОСТРОВА».
## Пропуск — Пробел/Esc/E. Игру не ставит на паузу (матч уже идёт); игрок на время
## заморожен. Под тестами (сцена Runner) не запускается, если в конфиге матча нет "intro": true;
## "intro": false — выключить всегда.
##
## API: ShowIntro.instance(), playing, play(), stop()

const LEN := 9.0

var playing := false
var _t := 0.0
var _cam: Camera3D
var _prev_cam: Camera3D
var _player: Node3D
var _path: Array[Vector3] = []     # опорные точки камеры (Catmull-Rom)
var _look: Array[Vector3] = []     # куда смотрит камера в этих точках
var _plates: Array[Dictionary] = []  # {label, pos}
var _root: Control
var _live: Label
var _title: Label
var _fade: ColorRect
var _hidden: Array[CanvasLayer] = []   # HUD, спрятанные на время кат-сцены

static func instance() -> ShowIntro:
	var t := Engine.get_main_loop() as SceneTree
	return t.get_first_node_in_group(&"show_intro") as ShowIntro if t else null

func _ready() -> void:
	name = "ShowIntro"
	layer = 7
	add_to_group(&"show_intro")
	_build_ui()
	Events.match_started.connect(_on_match_started)

func _on_match_started(cfg: Dictionary) -> void:
	var want: Variant = cfg.get("intro", null)
	if want != null and not bool(want):
		return
	var cs := get_tree().current_scene
	if want == null and cs and cs.name == "Runner":
		return   # автотесты ждут управление сразу
	get_tree().create_timer(0.3, false).timeout.connect(play)

func play() -> void:
	if playing or not is_inside_tree():
		return
	var w := get_tree().get_first_node_in_group(&"world")
	_player = get_tree().get_first_node_in_group(&"player") as Node3D
	if w == null or not w.has_method(&"islands") or _player == null:
		return
	_build_path(w)
	if _path.size() < 4:
		return
	_prev_cam = get_viewport().get_camera_3d()
	_cam = Camera3D.new()
	_cam.name = "IntroCam"
	_cam.fov = 62.0
	_cam.far = 4000.0
	add_child(_cam)
	_cam.global_position = _path[1]
	_cam.make_current()
	_player.set_physics_process(false)
	playing = true
	_t = 0.0
	_root.visible = true
	_place_plates(w)
	_hidden.clear()
	for c in get_tree().root.find_children("*", "CanvasLayer", true, false):
		if (c is MatchHUD or c is HUD) and (c as CanvasLayer).visible:
			(c as CanvasLayer).visible = false
			_hidden.append(c)

func stop() -> void:
	if not playing:
		return
	playing = false
	_root.visible = false
	for pl in _plates:
		(pl.label as Label).queue_free()
	_plates.clear()
	for c in _hidden:
		if is_instance_valid(c):
			c.visible = true
	_hidden.clear()
	if is_instance_valid(_player):
		_player.set_physics_process(true)
	if _cam:
		if _cam.current:
			var pc: Variant = _player.get(&"camera") if is_instance_valid(_player) else null
			if pc is Camera3D and is_instance_valid(pc):
				(pc as Camera3D).make_current()
			elif _prev_cam and is_instance_valid(_prev_cam):
				_prev_cam.make_current()
		_cam.queue_free()
		_cam = null

## Дуга вокруг Вулкана на высоте ~150 м → снижение к домашнему острову → к глазам игрока.
func _build_path(w: Node) -> void:
	_path.clear()
	_look.clear()
	var center := Vector3.ZERO
	var home := Vector3.ZERO
	var team := int(_player.get(&"team")) if _player.get(&"team") != null else 0
	for I: Dictionary in w.call(&"islands"):
		var c: Vector2 = I.center
		if StringName(I.kind) == &"center":
			center = Vector3(c.x, 40.0, c.y)
		if StringName(I.kind) == &"home" and int(I.team) == team:
			home = Vector3(c.x, 10.0, c.y)
	var eye := _player.global_position + Vector3.UP * 1.6
	var a_home := atan2(home.z - center.z, home.x - center.x)
	var R := maxf(Vector2(home.x - center.x, home.z - center.z).length() * 0.9, 300.0)
	# начинаем «напротив» дома и облетаем половину круга
	for k in 4:
		var a := a_home + PI * (1.0 - k / 3.0) * 0.9
		_path.append(center + Vector3(cos(a) * R, 150.0 - k * 18.0, sin(a) * R))
		_look.append(center)
	var to_home := (home - center)
	to_home.y = 0.0
	var dir := to_home.normalized()
	_path.append(home - dir * 70.0 + Vector3.UP * 55.0)
	_look.append(home)
	_path.append(eye - dir * 6.0 + Vector3.UP * 3.0)
	_look.append(eye + dir * 8.0)
	_path.append(eye)
	_look.append(eye + dir * 10.0)
	# фантомные концы для Catmull-Rom
	_path.push_front(_path[0] * 2.0 - _path[1])
	_look.push_front(_look[0])
	_path.append(_path[-1] * 2.0 - _path[-2])
	_look.append(_look[-1])

func _sample(arr: Array[Vector3], u: float) -> Vector3:
	var n := arr.size() - 3          # число сегментов
	var f := clampf(u, 0.0, 0.9999) * n
	var i := int(f)
	var t := f - i
	var p0 := arr[i]
	var p1 := arr[i + 1]
	var p2 := arr[i + 2]
	var p3 := arr[i + 3]
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t)

func _process(delta: float) -> void:
	if not playing:
		return
	_t += delta
	var u := clampf(_t / LEN, 0.0, 1.0)
	var e := u * u * (3.0 - 2.0 * u) * 0.35 + u * 0.65   # мягкий старт и финиш
	var pos := _sample(_path, e)
	var lk := _sample(_look, e)
	_cam.global_position = pos
	if lk.distance_to(pos) > 0.5:
		_cam.look_at(lk, Vector3.UP)
	# титры
	_title.modulate.a = clampf(_t / 0.8, 0.0, 1.0) * (1.0 - clampf((_t - 3.5) / 1.0, 0.0, 1.0))
	_live.visible = fmod(_t, 1.2) < 0.85 or _t > LEN - 1.0
	_fade.color.a = clampf((_t - (LEN - 0.5)) / 0.5, 0.0, 1.0) * 0.8 + (1.0 - clampf(_t / 0.6, 0.0, 1.0))
	for pl in _plates:
		var lb := pl.label as Label
		var p: Vector3 = pl.pos
		var vis := not _cam.is_position_behind(p) and _t < LEN - 2.0
		lb.visible = vis
		if vis:
			lb.position = _cam.unproject_position(p) - lb.size * 0.5
	if _t >= LEN:
		stop()

func _input(event: InputEvent) -> void:
	if not playing or _t < 0.5:
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"jump") or event.is_action_pressed(&"interact"):
		stop()
		get_viewport().set_input_as_handled()

func _place_plates(w: Node) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for I: Dictionary in w.call(&"islands"):
		if StringName(I.kind) != &"home":
			continue
		var team := int(I.team)
		if team < 0:
			continue
		var c: Vector2 = I.center
		var lb := Label.new()
		var odds := "%d:1" % rng.randi_range(2, 7)
		lb.text = "%s — %s у букмекеров" % [Game.TEAM_NAMES[team % 4], odds]
		lb.add_theme_font_size_override(&"font_size", 18)
		lb.add_theme_color_override(&"font_color", Game.team_color(team).lightened(0.3))
		lb.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.9))
		lb.add_theme_constant_override(&"outline_size", 6)
		lb.visible = false
		_root.add_child(lb)
		_plates.append({"label": lb, "pos": Vector3(c.x, float(I.max_h) + 25.0, c.y) if I.has("max_h") else Vector3(c.x, 40.0, c.y)})

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)
	_fade = ColorRect.new()
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0, 0, 0, 1)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fade)
	# «кино»-полосы
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 1)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_right = 1.0
		if top:
			bar.anchor_bottom = 0.0
			bar.offset_bottom = 54
		else:
			bar.anchor_top = 1.0
			bar.anchor_bottom = 1.0
			bar.offset_top = -54
		_root.add_child(bar)
	_live = Label.new()
	_live.text = "●  ПРЯМОЙ ЭФИР"
	_live.position = Vector2(28, 70)
	_live.add_theme_font_size_override(&"font_size", 20)
	_live.add_theme_color_override(&"font_color", Color(1.0, 0.2, 0.15))
	_live.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.8))
	_live.add_theme_constant_override(&"outline_size", 5)
	_root.add_child(_live)
	_title = Label.new()
	_title.text = "ОСТРОВА"
	_title.set_anchors_preset(Control.PRESET_CENTER)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_title.grow_vertical = Control.GROW_DIRECTION_BOTH
	_title.add_theme_font_size_override(&"font_size", 64)
	_title.add_theme_color_override(&"font_color", Color(0.97, 0.94, 0.86))
	_title.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.7))
	_title.add_theme_constant_override(&"outline_size", 10)
	_root.add_child(_title)
	var skip := Label.new()
	skip.text = "Пробел — пропустить"
	skip.anchor_left = 1.0
	skip.anchor_right = 1.0
	skip.anchor_top = 1.0
	skip.anchor_bottom = 1.0
	skip.offset_left = -220
	skip.offset_top = -44
	skip.add_theme_font_size_override(&"font_size", 14)
	skip.add_theme_color_override(&"font_color", Color(0.8, 0.8, 0.8, 0.8))
	_root.add_child(skip)
