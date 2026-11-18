class_name PauseMenu
extends Control
## Меню паузы: Продолжить / Настройки / Главное меню / Выход.
## Открывается по Events.pause_toggled (игрок ставит паузу на Esc).

const MAIN_MENU := "res://scenes/ui/main_menu.tscn"

var player: Node = null
var _menu: VBoxContainer
var settings: SettingsPanel
var controls: ControlsHelp

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.03, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_menu = VBoxContainer.new()
	_menu.anchor_top = 0.5
	_menu.anchor_bottom = 0.5
	_menu.offset_left = 90
	_menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	_menu.add_theme_constant_override(&"separation", 6)
	add_child(_menu)
	_menu.add_child(UITheme.title("Пауза", 44))
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 18)
	_menu.add_child(sp)
	_menu.add_child(menu_button("Продолжить", resume))
	_menu.add_child(menu_button("Настройки", show_settings))
	_menu.add_child(menu_button("Управление", func() -> void:
		_menu.visible = false
		controls.visible = true))
	_menu.add_child(menu_button("Главное меню", func() -> void:
		GameLauncher.to_menu(get_tree())))
	_menu.add_child(menu_button("Выход", func() -> void: get_tree().quit()))
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
	controls = ControlsHelp.new()
	controls.visible = false
	controls.anchor_left = 0.5
	controls.anchor_right = 0.5
	controls.anchor_top = 0.5
	controls.anchor_bottom = 0.5
	controls.grow_horizontal = Control.GROW_DIRECTION_BOTH
	controls.grow_vertical = Control.GROW_DIRECTION_BOTH
	controls.closed.connect(func() -> void: _menu.visible = true)
	add_child(controls)

## Кнопка-текст в стиле The Forest (без рамок, подсветка при наведении).
static func menu_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.flat = true
	b.add_theme_font_size_override(&"font_size", 24)
	b.add_theme_font_override(&"font", UITheme.serif(false))
	b.add_theme_color_override(&"font_color", UITheme.TEXT_DIM)
	b.add_theme_color_override(&"font_hover_color", UITheme.ACCENT)
	b.add_theme_color_override(&"font_focus_color", UITheme.TEXT)
	b.add_theme_color_override(&"font_pressed_color", UITheme.ACCENT)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(cb)
	return b

func set_open(on: bool) -> void:
	visible = on
	_menu.visible = true
	settings.visible = false
	controls.visible = false

func show_settings() -> void:
	_menu.visible = false
	settings.visible = true

func resume() -> void:
	if player and player.has_method(&"set_paused"):
		player.call(&"set_paused", false)
	else:
		get_tree().paused = false
		set_open(false)

func _input(event: InputEvent) -> void:
	if visible and settings.visible and event.is_action_pressed(&"pause"):
		settings.close()
		get_viewport().set_input_as_handled()
