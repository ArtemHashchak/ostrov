extends Control
## Главное меню: «Острова» — Играть / Настройки / Выход. Фоном — медленный
## пролёт камеры над тестовым островом (если он есть), иначе градиент.

const MATCH := "res://scenes/world/match.tscn"
const FALLBACK := "res://scenes/test/test_island.tscn"

var _menu: VBoxContainer
var settings: SettingsPanel
var lobby: LobbyPanel
var controls: ControlsHelp
var credits: CreditsPanel
var _cam: Camera3D
var _t := 0.0

func _ready() -> void:
	# дочерний процесс рендера реплея (scripts/replay): сразу в сцену клипа
	if ReplayPlayback.maybe_start(get_tree()):
		return
	theme = UITheme.get_theme()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	_build_background()
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.78))
	g.set_color(1, Color(0, 0, 0, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_to = Vector2(0.75, 0)
	shade.texture = gt
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	_menu = VBoxContainer.new()
	_menu.anchor_top = 0.5
	_menu.anchor_bottom = 0.5
	_menu.offset_left = 100
	_menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	_menu.add_theme_constant_override(&"separation", 6)
	add_child(_menu)
	var t := UITheme.title("ОСТРОВА", 72)
	t.add_theme_constant_override(&"outline_size", 0)
	_menu.add_child(t)
	var sub := UITheme.label("Защити флаг. Переживи остальных.", 16, UITheme.TEXT_DIM)
	_menu.add_child(sub)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 34)
	_menu.add_child(sp)
	var play := PauseMenu.menu_button("Играть", open_lobby)
	_menu.add_child(play)
	_menu.add_child(PauseMenu.menu_button("Обучение" if not TutorialLauncher.is_done() else "Обучение  ✓", func() -> void: TutorialLauncher.start(get_tree())))
	_menu.add_child(PauseMenu.menu_button("Полигон", func() -> void: Polygon.start(get_tree())))
	_menu.add_child(PauseMenu.menu_button("Настройки", func() -> void:
		_menu.visible = false
		settings.visible = true))
	_menu.add_child(PauseMenu.menu_button("Управление", func() -> void:
		_menu.visible = false
		controls.visible = true))
	_menu.add_child(PauseMenu.menu_button("Авторы", func() -> void:
		_menu.visible = false
		credits.visible = true))
	_menu.add_child(PauseMenu.menu_button("Выход", func() -> void: get_tree().quit()))
	play.grab_focus.call_deferred()

	var ver := UITheme.label("v1.0 · Godot " + Engine.get_version_info().string, 11, UITheme.TEXT_DIM)
	ver.anchor_left = 1.0
	ver.anchor_right = 1.0
	ver.anchor_top = 1.0
	ver.anchor_bottom = 1.0
	ver.offset_left = -220
	ver.offset_top = -30
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ver.offset_right = -18
	add_child(ver)

	settings = SettingsPanel.new()
	settings.visible = false
	settings.anchor_left = 0.5
	settings.anchor_right = 0.5
	settings.anchor_top = 0.5
	settings.anchor_bottom = 0.5
	settings.grow_horizontal = Control.GROW_DIRECTION_BOTH
	settings.grow_vertical = Control.GROW_DIRECTION_BOTH
	settings.closed.connect(func() -> void: _menu.visible = true)
	add_child(settings)
	lobby = LobbyPanel.new()
	_center(lobby)
	lobby.closed.connect(func() -> void: _menu.visible = true)
	add_child(lobby)
	controls = ControlsHelp.new()
	_center(controls)
	controls.closed.connect(func() -> void: _menu.visible = true)
	add_child(controls)
	credits = CreditsPanel.new()
	_center(credits)
	credits.closed.connect(func() -> void: _menu.visible = true)
	add_child(credits)
	Game.end_session()

func _center(c: Control) -> void:
	c.visible = false
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.anchor_top = 0.5
	c.anchor_bottom = 0.5
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BOTH

func open_lobby() -> void:
	_menu.visible = false
	lobby.visible = true
	if lobby.start_button:
		lobby.start_button.grab_focus.call_deferred()

func _build_background() -> void:
	var vc := SubViewportContainer.new()
	vc.set_anchors_preset(Control.PRESET_FULL_RECT)
	vc.stretch = true
	vc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vc.add_child(vp)
	# Фоновый мир: тестовый остров без игрока, камера облетает его.
	if ResourceLoader.exists(FALLBACK):
		var w := (load(FALLBACK) as PackedScene).instantiate()
		vp.add_child(w)
		# Остров сам создаёт игрока в _ready — в меню он не нужен.
		for p in w.find_children("*", "Player", true, false):
			p.get_parent().remove_child(p)
			p.free()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_cam = Camera3D.new()
	_cam.fov = 60
	_cam.far = 2000
	vp.add_child(_cam)
	_cam.current = true
	_update_cam()

func _process(delta: float) -> void:
	_t += delta
	_update_cam()

func _update_cam() -> void:
	if _cam == null:
		return
	var a := _t * 0.02 + 0.6
	_cam.position = Vector3(cos(a) * 70.0, 14.0, sin(a) * 70.0)
	_cam.look_at(Vector3(0, 3, 0))

## Сразу в матч с последними настройками лобби.
func play_game() -> void:
	GameLauncher.start(get_tree(), GameLauncher.load_lobby())

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause") and settings.visible:
		settings.close()
