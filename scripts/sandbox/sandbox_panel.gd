class_name SandboxPanel
extends Control
## Меню «Полигона» (F1 или M): быстрое перемещение по зонам и по карте,
## полёт/бессмертие/бесконечные предметы, время и погода, создание животных,
## акул и ботов у прицела, выдача любых предметов, сброс зоны.

const SHARKS := {&"reef": "Рифовая акула", &"tiger": "Тигровая акула", &"white": "Белая акула"}
const DIFF := [&"easy", &"normal", &"hard"]
const DIFF_NAMES := ["лёгкий", "обычный", "сложный"]

var zones: SandboxZones
var cheats: SandboxCheats
var world: World
var player: Player

var _fly_cb: CheckBox
var _god_cb: CheckBox
var _inf_cb: CheckBox
var _time: HSlider
var _time_lbl: Label
var _wind: HSlider
var _wind_lbl: Label
var _spawn_opt: OptionButton
var _spawn_ids: Array = []
var _team_opt: OptionButton
var _diff_opt: OptionButton
var _search: LineEdit
var _list: ItemList
var _list_ids: Array[StringName] = []
var _reset_opt: OptionButton
var _map: SandboxMap
var _status: Label

func _init() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	theme = UITheme.get_theme()
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.45)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", UITheme.box(UITheme.PANEL, 8, UITheme.LINE, 1, 18))
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 16
	panel.offset_right = -16
	panel.offset_top = 16
	panel.offset_bottom = -16
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 8)
	panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	head.add_child(UITheme.title("Полигон", 30))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_status = UITheme.label("", 14, UITheme.TEXT_DIM)
	head.add_child(_status)
	var close := Button.new()
	var isl := Button.new()
	isl.text = "Полигон островов"
	isl.pressed.connect(func() -> void: IslandsShowcase.start(get_tree()))
	head.add_child(isl)
	close.text = "Закрыть (F1)"
	close.pressed.connect(close_panel)
	head.add_child(close)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override(&"separation", 12)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cols)
	cols.add_child(_travel_col())
	cols.add_child(_tools_col())
	cols.add_child(_items_col())
	var mapbox := VBoxContainer.new()
	mapbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mapbox.size_flags_stretch_ratio = 1.6
	cols.add_child(mapbox)
	mapbox.add_child(UITheme.label("Карта — клик, чтобы переместиться", 15, UITheme.ACCENT, true))
	_map = SandboxMap.new()
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map.clicked.connect(_on_map_click)
	mapbox.add_child(_map)

func setup(z: SandboxZones, c: SandboxCheats, w: World, p: Player) -> void:
	zones = z
	cheats = c
	world = w
	player = p
	_map.setup(w, z, p)
	cheats.changed.connect(_sync)
	_fill_travel()
	_sync()

# ------------------------------------------------------------ колонки

func _scroll_col(title: String, width: float) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(width, 0)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", 2)
	sc.add_child(col)
	col.add_child(UITheme.label(title, 15, UITheme.ACCENT, true))
	col.set_meta(&"scroll", sc)
	return col

var _travel: VBoxContainer

func _travel_col() -> Control:
	_travel = _scroll_col("Быстрое перемещение", 196)
	return _travel.get_meta(&"scroll")

func _fill_travel() -> void:
	for id: StringName in zones.order:
		var b := Button.new()
		b.text = String(zones.points[id].name)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override(&"font_size", 15)
		b.pressed.connect(go.bind(id))
		_travel.add_child(b)

func _tools_col() -> Control:
	var col := _scroll_col("Режимы", 262)
	_fly_cb = _check(col, "Полёт сквозь стены (V)", func(on: bool) -> void: cheats.set_fly(on))
	_god_cb = _check(col, "Бессмертие", func(on: bool) -> void: cheats.set_god(on))
	_inf_cb = _check(col, "Бесконечные предметы", func(on: bool) -> void: cheats.set_infinite(on))
	col.add_child(_gap())
	col.add_child(UITheme.label("Время и погода", 15, UITheme.ACCENT, true))
	_time_lbl = UITheme.label("", 14)
	col.add_child(_time_lbl)
	_time = HSlider.new()
	_time.min_value = 0.0
	_time.max_value = 24.0
	_time.step = 0.25
	_time.custom_minimum_size = Vector2(230, 22)
	_time.value_changed.connect(func(x: float) -> void:
		if world:
			world.set_time_of_day(x)
		_time_lbl.text = "Время: %02d:%02d" % [int(x), int(fmod(x, 1.0) * 60.0)])
	col.add_child(_time)
	var tr := HBoxContainer.new()
	col.add_child(tr)
	for i in SandboxCheats.TIME_CYCLE.size():
		var h: float = SandboxCheats.TIME_CYCLE[i]
		var b := Button.new()
		b.text = SandboxCheats.TIME_NAMES[i]
		b.pressed.connect(func() -> void:
			cheats.set_time(h)
			_time.set_value_no_signal(h)
			_time_lbl.text = "Время: %02d:%02d" % [int(h), int(fmod(h, 1.0) * 60.0)])
		tr.add_child(b)
	var wr := HBoxContainer.new()
	col.add_child(wr)
	for w: StringName in SandboxCheats.WEATHER_CYCLE:
		var b := Button.new()
		b.text = SandboxCheats.WEATHER_NAMES[w]
		b.pressed.connect(func() -> void: cheats.set_weather(w))
		wr.add_child(b)
	_wind_lbl = UITheme.label("Ветер: как у погоды", 14)
	col.add_child(_wind_lbl)
	_wind = HSlider.new()
	_wind.min_value = -1.0
	_wind.max_value = 30.0
	_wind.step = 1.0
	_wind.value = -1.0
	_wind.custom_minimum_size = Vector2(230, 22)
	_wind.value_changed.connect(func(x: float) -> void:
		cheats.set_wind(x)
		_wind_lbl.text = "Ветер: как у погоды" if x < 0.0 else "Ветер: %d м/с" % int(x))
	col.add_child(_wind)
	col.add_child(UITheme.label("F5 — сменить погоду · F6 — время суток", 13, Color(0.8, 0.8, 0.8)))
	var ra := Button.new()
	ra.text = "Вернуть убитых животных"
	ra.pressed.connect(func() -> void:
		var n := zones.respawn_all()
		_toast("Возвращено животных: %d" % n))
	col.add_child(ra)
	col.add_child(_gap())
	col.add_child(UITheme.label("Создать у прицела", 15, UITheme.ACCENT, true))
	_spawn_opt = OptionButton.new()
	for sp: StringName in SandboxZones.SPECIES_ORDER + SandboxZones.BIRDS:
		var cfg: Dictionary = Animal.SPECIES.get(sp, {})
		_spawn_opt.add_item(String(cfg.get("name", sp)))
		_spawn_ids.append([&"animal", sp])
	for sp: StringName in SHARKS:
		_spawn_opt.add_item(SHARKS[sp])
		_spawn_ids.append([&"shark", sp])
	col.add_child(_spawn_opt)
	var sb := Button.new()
	sb.text = "Создать животное"
	sb.pressed.connect(_spawn_animal)
	col.add_child(sb)
	var br := HBoxContainer.new()
	col.add_child(br)
	_team_opt = OptionButton.new()
	for i in 4:
		_team_opt.add_item(Game.TEAM_NAMES[i])
	_team_opt.select(1)
	br.add_child(_team_opt)
	_diff_opt = OptionButton.new()
	for n in DIFF_NAMES:
		_diff_opt.add_item(n)
	_diff_opt.select(1)
	br.add_child(_diff_opt)
	var bb := Button.new()
	bb.text = "Создать бота у прицела"
	bb.pressed.connect(func() -> void: _spawn_bot(false))
	col.add_child(bb)
	var ba := Button.new()
	ba.text = "Создать бота на арене"
	ba.pressed.connect(func() -> void: _spawn_bot(true))
	col.add_child(ba)
	var tm := Button.new()
	tm.text = "Приручить животное у прицела"
	tm.pressed.connect(_tame_aimed)
	col.add_child(tm)
	var sup := Button.new()
	sup.text = "Посылка спонсора у прицела"
	sup.pressed.connect(_drop_supply)
	col.add_child(sup)
	col.add_child(_gap())
	col.add_child(UITheme.label("Сбросить зону", 15, UITheme.ACCENT, true))
	_reset_opt = OptionButton.new()
	for id: StringName in [&"flora", &"fauna", &"items", &"range", &"build", &"bridge", &"survival", &"beach"]:
		_reset_opt.add_item(_zone_name(id))
		_reset_opt.set_item_metadata(_reset_opt.item_count - 1, id)
	col.add_child(_reset_opt)
	var rb := Button.new()
	rb.text = "Вернуть как было"
	rb.pressed.connect(func() -> void:
		var id: StringName = _reset_opt.get_item_metadata(_reset_opt.selected)
		zones.reset_zone(id)
		_toast("Зона «%s» восстановлена" % _zone_name(id)))
	col.add_child(rb)
	return col.get_meta(&"scroll")

func _zone_name(id: StringName) -> String:
	match id:
		&"bridge": return "Мосты"
		&"beach": return "Мусорный пляж"
	return String(SandboxZones.ZONES[id].name) if SandboxZones.ZONES.has(id) else String(id)

func _items_col() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(230, 0)
	col.add_theme_constant_override(&"separation", 4)
	col.add_child(UITheme.label("Выдать предмет", 15, UITheme.ACCENT, true))
	_search = LineEdit.new()
	_search.placeholder_text = "Поиск…"
	_search.text_changed.connect(func(_t: String) -> void: _fill_list())
	col.add_child(_search)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.add_theme_stylebox_override(&"panel", UITheme.box(Color(0, 0, 0, 0.3), 4, UITheme.LINE, 1, 6))
	_list.item_activated.connect(func(i: int) -> void: _give(_list_ids[i], false))
	col.add_child(_list)
	var r := HBoxContainer.new()
	col.add_child(r)
	var g1 := Button.new()
	g1.text = "Выдать 1"
	g1.pressed.connect(func() -> void: _give_selected(false))
	r.add_child(g1)
	var g2 := Button.new()
	g2.text = "Выдать стопку"
	g2.pressed.connect(func() -> void: _give_selected(true))
	r.add_child(g2)
	var cl := Button.new()
	cl.text = "Очистить инвентарь"
	cl.pressed.connect(func() -> void:
		player.inventory.clear()
		cheats.set_infinite(cheats.infinite)
		_toast("Инвентарь очищен"))
	col.add_child(cl)
	_fill_list.call_deferred()
	return col

func _fill_list() -> void:
	_list.clear()
	_list_ids.clear()
	var q := _search.text.strip_edges().to_lower()
	var ids: Array[StringName] = []
	for id: StringName in Items.items:
		ids.append(id)
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return Items.item_name(a) < Items.item_name(b))
	for id in ids:
		var nm := Items.item_name(id)
		if q != "" and not nm.to_lower().contains(q) and not String(id).contains(q):
			continue
		_list.add_item(nm)
		_list_ids.append(id)

func _give_selected(stack: bool) -> void:
	var sel := _list.get_selected_items()
	if sel.is_empty():
		_toast("Выберите предмет в списке")
		return
	_give(_list_ids[sel[0]], stack)

func _give(id: StringName, stack: bool) -> void:
	if player == null:
		return
	var n := Inventory.stack_of(id) if stack else 1
	if Inventory.is_heavy(id):
		_toast("«%s» носят в руках — возьмите на складе стройки" % Items.item_name(id))
		return
	var left := player.inventory.add(id, n)
	if left >= n:
		_toast("Инвентарь полон")
	else:
		_toast("Выдано: %s ×%d" % [Items.item_name(id), n - left])

static func _gap() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 10)
	return c

static func _check(col: VBoxContainer, text: String, cb: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.toggled.connect(cb)
	col.add_child(c)
	return c

func _toast(t: String) -> void:
	Events.toast.emit(t)
	if _status:
		_status.text = t

func _sync() -> void:
	if cheats == null:
		return
	_fly_cb.set_pressed_no_signal(cheats.fly)
	_god_cb.set_pressed_no_signal(cheats.god)
	_inf_cb.set_pressed_no_signal(cheats.infinite)

# ------------------------------------------------------------ открыть/закрыть

func open_panel() -> void:
	if player == null or not player.alive or get_tree().paused:
		return
	visible = true
	player.set_ui_open(true)
	if world:
		_time.set_value_no_signal(world.time_of_day())
		var x := world.time_of_day()
		_time_lbl.text = "Время: %02d:%02d" % [int(x), int(fmod(x, 1.0) * 60.0)]
	_map.queue_redraw()

func close_panel() -> void:
	visible = false
	if player:
		player.set_ui_open(false)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k := (event as InputEventKey).physical_keycode
		if k == KEY_F1 or (k == KEY_M and not (_search and _search.has_focus())):
			if visible:
				close_panel()
			elif player and not player.ui_open:
				open_panel()
			get_viewport().set_input_as_handled()
			return
	if visible and event.is_action_pressed(&"pause"):
		close_panel()
		get_viewport().set_input_as_handled()

# ------------------------------------------------------------ действия

func go(id: StringName) -> void:
	var pt: Dictionary = zones.points.get(id, {})
	if pt.is_empty():
		return
	cheats.teleport(pt.pos, pt.look)
	close_panel()
	_toast(String(pt.name))

func _on_map_click(world_xz: Vector2) -> void:
	var h := world.height_at(world_xz.x, world_xz.y)
	var y := maxf(h, world.water_level()) + 0.3
	if h < world.water_level() and not cheats.fly:
		cheats.set_fly(true)
		y = world.water_level() + 3.0
	cheats.teleport(Vector3(world_xz.x, y, world_xz.y))
	close_panel()

## Точка у прицела (луч до 250 м; иначе — по рельефу).
func aim_point() -> Vector3:
	var cam := player.camera
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 250.0)
	q.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		return hit.position
	var t := 1.0
	while t < 250.0:
		var p := from + dir * t
		if p.y <= maxf(world.height_at(p.x, p.z), world.water_level()):
			return p
		t += 1.0
	return from + dir * 12.0

func _spawn_animal() -> void:
	var e: Array = _spawn_ids[_spawn_opt.selected]
	var p := aim_point()
	if e[0] == &"shark":
		var sea := get_tree().get_first_node_in_group(&"sea") as Sea
		if sea:
			sea.spawn_shark(e[1], Vector2(p.x, p.z), 6.0, randi() % 100000)
			_toast("Создана: %s (появится на глубине у прицела)" % SHARKS[e[1]])
		return
	var fa := Fauna.instance()
	if fa == null:
		return
	if e[1] in SandboxZones.BIRDS:
		fa.spawn_flock(e[1], p, 3, 8.0)
	else:
		fa.spawn(e[1], p + Vector3.UP * 0.3, 12.0)
	_toast("Создано: %s" % _spawn_opt.get_item_text(_spawn_opt.selected))

func _spawn_bot(arena: bool) -> void:
	var bots := Bots.instance()
	if bots == null:
		_toast("Модуль ботов не загружен")
		return
	var team := _team_opt.selected
	var p := zones.arena_center() if arena else aim_point() + Vector3.UP * 0.3
	if arena:
		var a := randf() * TAU
		p += Vector3(cos(a), 0, sin(a)) * randf_range(2.0, 10.0)
		p.y = world.height_at(p.x, p.z) + 0.3
	var b := bots.spawn_bot(team, DIFF[_diff_opt.selected], p)
	if b:
		_toast("Бот команды «%s» (%s)" % [Game.TEAM_NAMES[team], DIFF_NAMES[_diff_opt.selected]])
		if arena:
			go(&"bots")

func _drop_supply() -> void:
	var sup := get_tree().get_first_node_in_group(&"supply")
	if sup == null or not sup.has_method(&"drop_now"):
		_toast("Посылок в этой версии нет")
		return
	var p := aim_point()
	p.y = maxf(world.height_at(p.x, p.z), world.water_level())
	sup.call(&"drop_now", p)
	_toast("Самолёт со сбросом летит — смотрите в небо")
	close_panel()

## Приручить ближайшее к прицелу животное (в 6 м от точки прицела).
func _tame_aimed() -> void:
	var fa := Fauna.instance()
	if fa == null:
		return
	var p := aim_point()
	var best: Animal = null
	var bd := 6.0
	for a in fa.animals_near(p, 6.0):
		if a.tamed:
			continue
		var d := a.global_position.distance_to(p)
		if d < bd:
			bd = d
			best = a
	if best == null:
		_toast("Наведите прицел на животное")
		return
	if not bool(best.cfg.get("tame", false)):
		_toast("%s не приручается" % String(best.cfg.get("name", best.species)))
		return
	fa.tame(best, player)
	_toast("%s приручен(а) — идёт за вами" % String(best.cfg.get("name", best.species)))
	close_panel()
