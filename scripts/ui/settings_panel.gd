class_name SettingsPanel
extends PanelContainer
## Настройки: графика (пресет, разрешение 3D, дальность видимости и растений, интерфейс, кадры, окно),
## чувствительность, поле зрения, инверсия Y, громкость,
## переназначение клавиш. Всё пишет в Settings и сохраняет.

signal closed

const REBINDABLE: Array[StringName] = [
	&"move_forward", &"move_back", &"move_left", &"move_right", &"jump", &"sprint",
	&"crouch", &"interact", &"inventory", &"craft", &"drop", &"map",
]
const ACTION_NAMES: Dictionary = {
	&"move_forward": "Вперёд", &"move_back": "Назад", &"move_left": "Влево",
	&"move_right": "Вправо", &"jump": "Прыжок", &"sprint": "Бег", &"crouch": "Присесть",
	&"interact": "Действие", &"inventory": "Инвентарь", &"craft": "Крафт", &"drop": "Выбросить",
	&"map": "Карта",
}

var _waiting: StringName = &""
var _key_buttons: Dictionary = {}

func _init() -> void:
	add_theme_stylebox_override(&"panel", UITheme.box(UITheme.PANEL, 8, UITheme.LINE, 1, 24))
	custom_minimum_size = Vector2(560, 0)
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	theme = UITheme.get_theme()
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 10)
	add_child(v)
	v.add_child(UITheme.title("Настройки", 28))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", 16)
	grid.add_theme_constant_override(&"v_separation", 8)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override(&"separation", 28)
	v.add_child(cols)
	cols.add_child(grid)
	var right := VBoxContainer.new()
	right.add_theme_constant_override(&"separation", 8)
	cols.add_child(right)
	_slider(grid, "Качество графики", 0.0, 3.0, 1.0, float(Settings.graphics_quality),
		func(x: float) -> void:
			Settings.graphics_quality = int(x)
			DynamicResolution.reset()
			Settings.apply_graphics(),
		func(x: float) -> String: return GraphicsQuality.NAMES[int(x)])
	_slider(grid, "Разрешение 3D", 0.0, 1.0, 0.05, Settings.render_scale,
		func(x: float) -> void:
			Settings.render_scale = 0.0 if x < 0.4 else x
			DynamicResolution.reset()
			Settings.apply_graphics(),
		func(x: float) -> String: return "авто" if x < 0.4 else "%d%%" % int(round(x * 100.0)))
	# дальность видимости: авто (по пресету) · 500–3500 м · «Максимум»; применяется на лету
	_slider(grid, "Дальность видимости", ViewDistance.SLIDER_AUTO, ViewDistance.SLIDER_MAXIMUM, 250.0,
		ViewDistance.to_slider(Settings.view_distance),
		func(x: float) -> void:
			Settings.view_distance = 0.0 if x < ViewDistance.MIN else x
			Settings.apply_view(),
		func(x: float) -> String:
			var m := ViewDistance.PRESET_DEFAULT[clampi(Settings.graphics_quality, 0, 3)] if x < ViewDistance.MIN \
				else (ViewDistance.MAXIMUM if x > ViewDistance.SLIDER_MAX + 1.0 else x)
			return "%s · %s" % [ViewDistance.slider_label(x), ViewDistance.cost_hint(m)])
	_slider(grid, "Дальность растений", 0.5, 2.0, 0.1, Settings.flora_distance,
		func(x: float) -> void:
			Settings.flora_distance = x
			Settings.apply_view(),
		func(x: float) -> String:
			return "×%.1f · %s" % [x, "нагрузка: низкая" if x < 0.85 else ("нагрузка: средняя" if x <= 1.25 else "нагрузка: высокая")])
	_slider(grid, "Масштаб интерфейса", 0.75, 1.5, 0.05, Settings.ui_scale,
		func(x: float) -> void:
			Settings.ui_scale = x
			Settings.apply_window(),
		func(x: float) -> String: return "%d%%" % int(round(x * 100.0)))
	_slider(grid, "Лимит кадров", 0.0, 4.0, 1.0, float([0, 30, 60, 120, 144].find(Settings.fps_cap) if Settings.fps_cap in [0, 30, 60, 120, 144] else 0),
		func(x: float) -> void:
			Settings.fps_cap = [0, 30, 60, 120, 144][int(x)]
			Engine.max_fps = Settings.fps_cap,
		func(x: float) -> String: return ["нет", "30", "60", "120", "144"][int(x)])
	_slider(grid, "Чувствительность мыши", 0.0005, 0.006, 0.0001, Settings.mouse_sensitivity,
		func(x: float) -> void: Settings.mouse_sensitivity = x,
		func(x: float) -> String: return "%.1f" % (x / 0.0022))
	_slider(grid, "Поле зрения", 60.0, 100.0, 1.0, Settings.fov,
		func(x: float) -> void: Settings.fov = x,
		func(x: float) -> String: return "%d°" % int(x))
	_slider(grid, "Громкость", 0.0, 1.0, 0.05, Settings.master_volume,
		func(x: float) -> void:
			Settings.master_volume = x
			AudioServer.set_bus_volume_db(0, linear_to_db(maxf(x, 0.0001))),
		func(x: float) -> String: return "%d%%" % int(x * 100.0))
	_check(grid, "Динамическое разрешение", Settings.dynamic_resolution, func(on: bool) -> void:
		Settings.dynamic_resolution = on
		DynamicResolution.reset()
		Settings.apply_graphics())
	_check(grid, "Вертикальная синхронизация", Settings.vsync, func(on: bool) -> void:
		Settings.vsync = on
		Settings.apply_window())
	_check(grid, "Полный экран (F11)", Settings.fullscreen, func(on: bool) -> void:
		Settings.fullscreen = on
		Settings.apply_window())
	_check(grid, "Счётчик FPS (F3)", Settings.show_perf, func(on: bool) -> void:
		Settings.show_perf = on
		PerfOverlay.ensure(get_tree().root))
	_check(grid, "Инверсия по Y", Settings.invert_y, func(on: bool) -> void: Settings.invert_y = on)
	_check(grid, "Прицел: переключать (вкл.) / удерживать (выкл.)", Settings.aim_toggle, func(on: bool) -> void: Settings.aim_toggle = on)
	_check(grid, "Режим разработчика (консоль ` / Ё)", Settings.dev_mode, func(on: bool) -> void: Settings.dev_mode = on)
	var bench := Button.new()
	bench.text = "Тест производительности"
	bench.alignment = HORIZONTAL_ALIGNMENT_LEFT
	bench.pressed.connect(func() -> void:
		Settings.save_settings()
		Benchmark.start(get_tree()))
	v.add_child(bench)

	right.add_child(UITheme.label("Клавиши — нажми, затем новую клавишу", 12, UITheme.TEXT_DIM))
	var kg := GridContainer.new()
	kg.columns = 2
	kg.add_theme_constant_override(&"h_separation", 14)
	kg.add_theme_constant_override(&"v_separation", 4)
	right.add_child(kg)
	for a in REBINDABLE:
		var l := UITheme.label(ACTION_NAMES.get(a, String(a)), 14)
		l.custom_minimum_size = Vector2(110, 0)
		kg.add_child(l)
		var b := Button.new()
		b.custom_minimum_size = Vector2(120, 28)
		b.add_theme_stylebox_override(&"normal", UITheme.box(Color(0, 0, 0, 0.3), 4, UITheme.LINE, 1, 4))
		b.text = UITheme.key_name(a)
		b.add_theme_font_size_override(&"font_size", 14)
		b.pressed.connect(func() -> void: _start_rebind(a))
		kg.add_child(b)
		_key_buttons[a] = b

	var back := Button.new()
	back.text = "Назад"
	back.alignment = HORIZONTAL_ALIGNMENT_LEFT
	back.pressed.connect(close)
	v.add_child(back)

func _slider(parent: Control, title_text: String, mn: float, mx: float, step: float, val: float, on_change: Callable, fmt: Callable) -> void:
	parent.add_child(UITheme.label(title_text, 14))
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = val
	s.custom_minimum_size = Vector2(220, 20)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(s)
	var vl := UITheme.label(fmt.call(val), 14, UITheme.TEXT_DIM)
	vl.custom_minimum_size = Vector2(60, 0)
	parent.add_child(vl)
	s.value_changed.connect(func(x: float) -> void:
		on_change.call(x)
		vl.text = fmt.call(x))

func _check(parent: Control, title_text: String, val: bool, on_toggle: Callable) -> void:
	parent.add_child(UITheme.label(title_text, 14))
	var cb := CheckBox.new()
	cb.button_pressed = val
	cb.toggled.connect(on_toggle)
	parent.add_child(cb)
	parent.add_child(Control.new())

func _start_rebind(a: StringName) -> void:
	_waiting = a
	(_key_buttons[a] as Button).text = "…"

func _input(event: InputEvent) -> void:
	if _waiting == &"" or not is_visible_in_tree():
		return
	if event is InputEventKey and (event as InputEventKey).pressed:
		var k := event as InputEventKey
		var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		if code != KEY_ESCAPE:
			Settings.rebind_key(_waiting, code)
		(_key_buttons[_waiting] as Button).text = UITheme.key_name(_waiting)
		_waiting = &""
		get_viewport().set_input_as_handled()

func close() -> void:
	Settings.save_settings()
	visible = false
	closed.emit()
