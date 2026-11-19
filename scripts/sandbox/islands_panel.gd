class_name IslandsPanel
extends Control
## Меню «Полигона островов» (F1 или M): острова (вид с пляжа / сверху),
## обзор всего ряда, полёт, время суток и погода.

var sc: IslandsShowcase
var _fly_cb: CheckBox
var _ov_cb: CheckBox
var _time: HSlider
var _time_lbl: Label

func _init() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func setup(s: IslandsShowcase) -> void:
	sc = s
	theme = UITheme.get_theme()
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.45)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", UITheme.box(UITheme.PANEL, 8, UITheme.LINE, 1, 18))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(980, 620)
	panel.position = Vector2(-490, -310)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 8)
	panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	head.add_child(UITheme.title("Полигон островов", 30))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var close := Button.new()
	close.text = "Закрыть (F1)"
	close.pressed.connect(close_panel)
	head.add_child(close)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override(&"separation", 14)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cols)
	# острова
	var isl := VBoxContainer.new()
	isl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	isl.add_theme_constant_override(&"separation", 4)
	cols.add_child(isl)
	isl.add_child(UITheme.label("Острова (по порядку в ряду, с запада на восток)", 15, UITheme.ACCENT, true))
	var list := sc.world.showcase()
	for i in list.size():
		var e: Dictionary = list[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 6)
		isl.add_child(row)
		var name_l := UITheme.label("%d. %s" % [i + 1, String(e.name)], 15)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_l)
		var b1 := Button.new()
		b1.text = "С пляжа"
		b1.pressed.connect(func() -> void: sc.go_beach(i); close_panel())
		row.add_child(b1)
		var b2 := Button.new()
		b2.text = "Сверху"
		b2.pressed.connect(func() -> void: sc.go_air(i); close_panel())
		row.add_child(b2)
	# режимы, время, погода
	var tools := VBoxContainer.new()
	tools.custom_minimum_size = Vector2(300, 0)
	tools.add_theme_constant_override(&"separation", 4)
	cols.add_child(tools)
	tools.add_child(UITheme.label("Режимы", 15, UITheme.ACCENT, true))
	_ov_cb = CheckBox.new()
	_ov_cb.text = "Обзор всего ряда (O)"
	_ov_cb.toggled.connect(func(on: bool) -> void: sc.set_overview(on); close_panel())
	tools.add_child(_ov_cb)
	_fly_cb = CheckBox.new()
	_fly_cb.text = "Полёт сквозь стены (V)"
	_fly_cb.toggled.connect(func(on: bool) -> void: sc.cheats.set_fly(on))
	tools.add_child(_fly_cb)
	tools.add_child(UITheme.label("Время суток (F6)", 15, UITheme.ACCENT, true))
	_time_lbl = UITheme.label("", 14)
	tools.add_child(_time_lbl)
	_time = HSlider.new()
	_time.min_value = 0.0
	_time.max_value = 24.0
	_time.step = 0.25
	_time.value_changed.connect(func(x: float) -> void:
		sc.world.set_time_of_day(x)
		_upd_time())
	tools.add_child(_time)
	var trow := HBoxContainer.new()
	tools.add_child(trow)
	for k in SandboxCheats.TIME_CYCLE.size():
		var h: float = SandboxCheats.TIME_CYCLE[k]
		var b := Button.new()
		b.text = SandboxCheats.TIME_NAMES[k]
		b.pressed.connect(func() -> void:
			sc.cheats.set_time(h)
			_time.set_value_no_signal(h)
			_upd_time())
		trow.add_child(b)
	tools.add_child(UITheme.label("Погода (F5)", 15, UITheme.ACCENT, true))
	var wrow := HBoxContainer.new()
	tools.add_child(wrow)
	for w: StringName in SandboxCheats.WEATHER_CYCLE:
		var b := Button.new()
		b.text = String(SandboxCheats.WEATHER_NAMES[w])
		b.pressed.connect(func() -> void: sc.cheats.set_weather(w))
		wrow.add_child(b)
	tools.add_child(UITheme.label("Прилив: кей, коса и риф-флэт атолла\nзаливает в прилив, открывает в отлив.", 13, UITheme.TEXT_DIM))
	var back := Button.new()
	back.text = "В главное меню"
	back.pressed.connect(func() -> void:
		get_tree().paused = false
		Game.end_session()
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn"))
	tools.add_child(back)
	sc.cheats.changed.connect(_sync)

func _upd_time() -> void:
	var x := sc.world.time_of_day()
	_time_lbl.text = "Время: %02d:%02d" % [int(x), int(fmod(x, 1.0) * 60.0)]

func _sync() -> void:
	_fly_cb.set_pressed_no_signal(sc.cheats.fly)
	_ov_cb.set_pressed_no_signal(sc.overview_on())

func open_panel() -> void:
	var p := sc.player
	if p == null or not p.alive or get_tree().paused:
		return
	visible = true
	p.set_ui_open(true)
	_time.set_value_no_signal(sc.world.time_of_day())
	_upd_time()
	_sync()

func close_panel() -> void:
	visible = false
	if sc and sc.player:
		sc.player.set_ui_open(false)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k := (event as InputEventKey).physical_keycode
		if k == KEY_F1 or k == KEY_M:
			if visible:
				close_panel()
			elif sc and sc.player and not sc.player.ui_open:
				open_panel()
			get_viewport().set_input_as_handled()
			return
	if visible and event.is_action_pressed(&"pause"):
		close_panel()
		get_viewport().set_input_as_handled()
