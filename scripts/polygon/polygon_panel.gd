class_name PolygonPanel
extends PanelContainer
## Меню нового полигона (F1 или M): разделы музея (быстрое перемещение), острова и
## архипелаг (по одному), мир (время, перемотка, погода, прилив, ветер), игрок
## (наблюдатель, полёт, бессмертие, бесконечные предметы), анимации существа у прицела,
## отладка (каталог существ, убрать созданных, перестроить раздел, сценки режиссёра),
## реплей в максимальной графике.

var poly: Node                       # Polygon или PolygonIslandStage
var tabs: TabContainer
var _anim_box: VBoxContainer
var _anim_target: Label
var _catalog: SandboxCatalog
var catalog: SandboxCatalog:
	get:
		return _catalog
var _status: Label
var _tide: HSlider

func setup(p: Node) -> void:
	poly = p
	visible = false
	anchor_left = 0.18
	anchor_right = 0.82
	anchor_top = 0.08
	anchor_bottom = 0.9
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.08, 0.1, 0.94)
	sb.border_color = Color(0.3, 0.75, 0.7)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	add_theme_stylebox_override(&"panel", sb)
	var v := VBoxContainer.new()
	add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var t := Label.new()
	t.text = "Полигон"
	t.add_theme_font_size_override(&"font_size", 24)
	t.add_theme_color_override(&"font_color", Color(0.55, 0.95, 0.85))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(t)
	var x := Button.new()
	x.text = "✕  (F1)"
	x.pressed.connect(close)
	top.add_child(x)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tabs)
	_status = Label.new()
	_status.text = ""
	v.add_child(_status)
	_tab_sections()
	_tab_islands()
	_tab_world()
	_tab_player()
	_tab_anim()
	_tab_debug()
	_catalog = SandboxCatalog.new()
	_catalog.panel = poly
	_catalog.visible = false
	get_parent().add_child.call_deferred(_catalog)

func _page(title: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = title
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	return v

func _btn(parent: Control, text: String, cb: Callable, w: float = 220.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 34)
	b.clip_text = true
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _grid(parent: Control, cols: int = 3) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	parent.add_child(g)
	return g

func _head(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", 17)
	l.add_theme_color_override(&"font_color", Color(0.95, 0.8, 0.45))
	parent.add_child(l)

# ------------------------------------------------------------ вкладки

func _tab_sections() -> void:
	var v := _page("Разделы")
	if not poly is Polygon:
		_head(v, "Вы на острове. Вернуться в музей полигона:")
		_btn(v, "← В музей полигона", func() -> void: PolygonIslandStage.back_to_museum(get_tree()), 300)
		return
	_head(v, "Быстрое перемещение по музею")
	var g := _grid(v)
	_btn(g, "Центр", func() -> void:
		(poly as Polygon).goto_hub()
		close())
	for s: Dictionary in PolygonLayout.get_layout().sections:
		var id: StringName = s.id
		_btn(g, "%s (%d)" % [s.name, int(s.count)], func() -> void:
			(poly as Polygon).goto_section(id)
			close())

func _tab_islands() -> void:
	var v := _page("Острова")
	_head(v, "Острова и архипелаг загружаются по одному (остальное выгружается)")
	var g := _grid(v, 2)
	for e: Dictionary in PolygonIslands.list():
		var id := String(e.id)
		_btn(g, String(e.name), func() -> void: PolygonIslandStage.open(get_tree(), id), 300)

func _tab_world() -> void:
	var v := _page("Мир")
	_head(v, "Время суток")
	var g := _grid(v, 7)
	for h: float in [5.5, 7.0, 9.0, 12.0, 15.0, 18.3, 20.0, 22.0, 0.0]:
		var hh := h
		_btn(g, "%02d:%02d" % [int(h), int(fmod(h, 1.0) * 60.0)], func() -> void: _cheats().set_time(hh), 80)
	var rw := HBoxContainer.new()
	v.add_child(rw)
	_btn(rw, "⟲ −1 ч", func() -> void: _shift_time(-1.0), 110)
	_btn(rw, "−10 мин", func() -> void: _shift_time(-1.0 / 6.0), 110)
	_btn(rw, "+10 мин", func() -> void: _shift_time(1.0 / 6.0), 110)
	_btn(rw, "+1 ч ⟳", func() -> void: _shift_time(1.0), 110)
	var pause := CheckBox.new()
	pause.text = "Остановить время"
	pause.toggled.connect(func(on: bool) -> void:
		var w: Object = _world()
		if w and w.has_method(&"set_time_paused"):
			w.call(&"set_time_paused", on))
	rw.add_child(pause)
	_head(v, "Погода")
	var gw := _grid(v, 5)
	for w: StringName in SandboxCheats.WEATHER_NAMES:
		var ww := w
		_btn(gw, String(SandboxCheats.WEATHER_NAMES[w]), func() -> void: _cheats().set_weather(ww), 130)
	_head(v, "Прилив / уровень моря (м)")
	_tide = HSlider.new()
	_tide.min_value = -1.2
	_tide.max_value = 1.2
	_tide.step = 0.05
	_tide.custom_minimum_size = Vector2(420, 24)
	_tide.value_changed.connect(func(val: float) -> void:
		var w: Object = _world()
		if w and w.has_method(&"set_tide"):
			w.call(&"set_tide", val)
		elif w:
			w.set(&"tide_amplitude", absf(val))
		_status.text = "Уровень моря: %+.2f м" % val)
	v.add_child(_tide)
	_head(v, "Ветер")
	var gv := _grid(v, 6)
	for s: float in [-1.0, 0.0, 3.0, 7.0, 12.0, 20.0]:
		var ss := s
		_btn(gv, "как в погоде" if s < 0.0 else "%d м/с" % int(s), func() -> void: _cheats().set_wind(ss), 120)

func _tab_player() -> void:
	var v := _page("Игрок")
	var obs := CheckBox.new()
	obs.text = "Наблюдатель — животные, акулы и рыбы не замечают игрока"
	obs.toggled.connect(func(on: bool) -> void:
		if poly.has_method(&"set_observer"):
			poly.call(&"set_observer", on)
		_status.text = "Наблюдатель: " + ("вкл" if on else "выкл"))
	v.add_child(obs)
	var fly := CheckBox.new()
	fly.text = "Полёт (V) — Shift быстрее, колесо — скорость"
	fly.toggled.connect(func(on: bool) -> void: _cheats().set_fly(on))
	v.add_child(fly)
	var god := CheckBox.new()
	god.text = "Бессмертие (сытость, вода, здоровье)"
	god.button_pressed = true
	god.toggled.connect(func(on: bool) -> void: _cheats().set_god(on))
	v.add_child(god)
	var inf := CheckBox.new()
	inf.text = "Бесконечные предметы"
	inf.button_pressed = true
	inf.toggled.connect(func(on: bool) -> void: _cheats().set_infinite(on))
	v.add_child(inf)

func _tab_anim() -> void:
	var v := _page("Анимации")
	_head(v, "Наведите прицел на существо и нажмите «Найти»")
	var h := HBoxContainer.new()
	v.add_child(h)
	_btn(h, "Найти у прицела", _pick_anim_target, 200)
	_anim_target = Label.new()
	_anim_target.text = "—"
	h.add_child(_anim_target)
	_anim_box = VBoxContainer.new()
	v.add_child(_anim_box)

func _tab_debug() -> void:
	var v := _page("Отладка")
	var g := _grid(v, 2)
	_btn(g, "Каталог существ — призвать любое", func() -> void:
		_catalog.open()
		close(), 320)
	_btn(g, "Убрать созданных", func() -> void:
		var k := CreatureSpawner.instance().clear(Vector3.ZERO, 0.0) if CreatureSpawner.instance() else 0
		_status.text = "Убрано: %d" % k, 320)
	_btn(g, "Перестроить текущий раздел", _rebuild_section, 320)
	_btn(g, "Консоль разработчика (`)", func() -> void:
		close()
		DevConsole.call(&"open"), 320)
	_head(v, "Сценки режиссёра")
	var scenes := _director_scenes()
	if scenes.is_empty():
		var l := Label.new()
		l.text = "Режиссёр сценок ещё не подключён — список появится сам."
		v.add_child(l)
	else:
		var gs := _grid(v, 3)
		for sid: String in scenes:
			var id := sid
			_btn(gs, id, func() -> void: _run_scene(id), 220)
	_head(v, "Реплей в максимальной графике")
	var l2 := Label.new()
	l2.text = "Игра всё время записывает последние 60 с. Кнопка перерисует их покадрово\nна «ультра» (не в реальном времени) и покажет видео. Консоль: replay [сек]"
	v.add_child(l2)
	var rh := HBoxContainer.new()
	v.add_child(rh)
	for sec_: int in [15, 30, 60]:
		var s := sec_
		_btn(rh, "Реплей: %d с" % s, func() -> void:
			close()
			ReplayRecorder.request(get_tree(), float(s)), 160)

# ------------------------------------------------------------ действия

func _cheats() -> SandboxCheats:
	return poly.get(&"cheats") as SandboxCheats

func _world() -> Object:
	return poly.get(&"world")

func _shift_time(dh: float) -> void:
	var w: Object = _world()
	if w == null:
		return
	var h := fposmod(float(w.call(&"time_of_day")) + dh, 24.0)
	_cheats().set_time(h)

func _rebuild_section() -> void:
	if not poly is Polygon:
		return
	var pg := poly as Polygon
	var id := pg.current_section()
	if id == &"":
		return
	pg.unload_section(id)
	pg.build_section(id)
	_status.text = "Раздел перестроен"

func _director_scenes() -> Array:
	for path: String in ["res://scripts/world/director/director.gd", "res://scripts/core/director.gd"]:
		if ResourceLoader.exists(path):
			var s := load(path) as Script
			if s and s.has_method(&"scene_ids"):
				return s.call(&"scene_ids")
	return []

func _run_scene(id: String) -> void:
	for path: String in ["res://scripts/world/director/director.gd", "res://scripts/core/director.gd"]:
		if ResourceLoader.exists(path):
			var s := load(path) as Script
			if s and s.has_method(&"trigger"):
				s.call(&"trigger", id, poly.call(&"aim_point"))
				_status.text = "Сценка: " + id
				return

func _pick_anim_target() -> void:
	for c in _anim_box.get_children():
		c.queue_free()
	var p: Vector3 = poly.call(&"aim_point")
	var best: Node3D = null
	var bd := 6.0
	for n in get_tree().get_nodes_in_group(&"wild_animals") + get_tree().get_nodes_in_group(&"sharks") + \
			get_tree().get_nodes_in_group(&"creatures"):
		var n3 := n as Node3D
		if n3 == null:
			continue
		var d := n3.global_position.distance_to(p)
		if d < bd:
			bd = d
			best = n3
	if best == null:
		# любой узел с AnimationPlayer у прицела
		for n in _anim_candidates(p):
			best = n
			break
	if best == null:
		_anim_target.text = "рядом с прицелом никого нет"
		return
	var aps: Array = best.find_children("*", "AnimationPlayer", true, false)
	_anim_target.text = "%s — плееров анимации: %d" % [best.name, aps.size()]
	for ap: AnimationPlayer in aps:
		var g := _grid(_anim_box, 4)
		for an: StringName in ap.get_animation_list():
			var a := an
			var pl := ap
			_btn(g, String(an), func() -> void:
				var target := best
				if target.process_mode == Node.PROCESS_MODE_DISABLED:
					pl.process_mode = Node.PROCESS_MODE_ALWAYS
				pl.play(a)
				_status.text = "Анимация: " + String(a), 180)

func _anim_candidates(p: Vector3) -> Array:
	var out: Array = []
	for ap in get_tree().root.find_children("*", "AnimationPlayer", true, false):
		var host := (ap as Node).get_parent() as Node3D
		while host and not (host.get_parent() is PolygonSection) and host.get_parent() != get_tree().root and \
				host.get_parent() is Node3D and (host.get_parent() as Node3D).global_position.distance_to(host.global_position) < 0.01:
			host = host.get_parent() as Node3D
		if host and host.global_position.distance_to(p) < 5.0:
			out.append(host)
	return out

# ------------------------------------------------------------ открыть/закрыть

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var pl: Object = poly.get(&"player")
	if pl:
		pl.set(&"ui_open", true)
	if _tide:
		var w: Object = _world()
		if w and w.get(&"tide_offset") != null:
			_tide.set_value_no_signal(float(w.get(&"tide_offset")))

## Совместимость со старым меню (консоль, тесты).
func open_panel() -> void:
	open()

func close_panel() -> void:
	close()
	if _catalog:
		_catalog.visible = false

func open_catalog() -> void:
	if _catalog:
		_catalog.open()

func close() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var pl: Object = poly.get(&"player")
	if pl:
		pl.set(&"ui_open", false)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).physical_keycode
		if k == KEY_F1 or k == KEY_M:
			if DevConsole.call(&"is_open"):
				return
			toggle()
			get_viewport().set_input_as_handled()
		elif k == KEY_ESCAPE and visible:
			close()
			get_viewport().set_input_as_handled()
