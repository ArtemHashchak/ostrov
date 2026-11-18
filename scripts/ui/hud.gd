class_name HUD
extends CanvasLayer
## Интерфейс игрока в духе The Forest: почти ничего на экране — точка прицела,
## тонкие полоски жизненных показателей внизу слева (ярче, когда мало),
## хотбар, подсказка E, всплывающие сообщения, затемнение при уроне,
## тон под водой и воздух, экран гибели. Панели: инвентарь (I/Tab), крафт (C;
## B — меню стройки),
## пауза (Esc). Создаёт игрок: HUD.new() с player.

var player: Node = null # Player

var root: Control
var _bars: Dictionary = {}        # name -> {bar: ProgressBar, box: Control}
var _hotbar: HBoxContainer
var _hot_slots: Array[ItemSlot] = []
var _hot_name: Label
var _hint: Label
var _hint_box: PanelContainer
var _toasts: VBoxContainer
var _cross: Control
var _water: ColorRect
var _flash: TextureRect
var _death: Control
var _death_title: Label
var _death_sub: Label
var _flash_a := 0.0
var _name_t := 0.0

var inventory_panel: InventoryPanel
var craft_panel: CraftPanel
var pause_menu: PauseMenu

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.name = "HUDRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	add_child(root)
	_build_water()
	_build_flash()
	_build_crosshair()
	_build_vitals()
	_build_hotbar()
	_build_hint()
	_build_toasts()
	_build_death()
	inventory_panel = InventoryPanel.new()
	inventory_panel.player = player
	root.add_child(inventory_panel)
	craft_panel = CraftPanel.new()
	craft_panel.player = player
	root.add_child(craft_panel)
	pause_menu = PauseMenu.new()
	pause_menu.player = player
	root.add_child(pause_menu)
	Events.interact_hint_changed.connect(_on_hint)
	Events.toast.connect(show_toast)
	Events.item_crafted.connect(func(o: Node, id: StringName, n: int) -> void:
		if o == player: show_toast("Сделано: %s ×%d" % [Items.item_name(id), n]))
	Events.pause_toggled.connect(func(p: bool) -> void: pause_menu.set_open(p))
	var inv := player.get(&"inventory") as Inventory
	if inv:
		inv.changed.connect(_refresh_hotbar)
	_refresh_hotbar()

# ---------------- построение ----------------

func _build_water() -> void:
	_water = ColorRect.new()
	_water.set_anchors_preset(Control.PRESET_FULL_RECT)
	_water.color = Color(0.05, 0.28, 0.32, 0.42)
	_water.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_water.visible = false
	root.add_child(_water)

func _build_flash() -> void:
	_flash = TextureRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_flash.stretch_mode = TextureRect.STRETCH_SCALE
	var g := Gradient.new()
	g.set_color(0, Color(0.5, 0.0, 0.0, 0.0))
	g.set_color(1, Color(0.55, 0.02, 0.02, 0.85))
	g.add_point(0.55, Color(0.5, 0.0, 0.0, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.05, 0.5)
	gt.width = 256
	gt.height = 256
	_flash.texture = gt
	_flash.modulate.a = 0.0
	root.add_child(_flash)

func _build_crosshair() -> void:
	_cross = Control.new()
	_cross.set_anchors_preset(Control.PRESET_CENTER)
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cross.draw.connect(func() -> void:
		_cross.draw_circle(Vector2.ZERO, 2.6, Color(0, 0, 0, 0.45))
		_cross.draw_circle(Vector2.ZERO, 1.6, Color(1, 0.98, 0.92, 0.85)))
	root.add_child(_cross)

func _build_vitals() -> void:
	var box := VBoxContainer.new()
	box.name = "Vitals"
	box.add_theme_constant_override(&"separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.offset_left = 30
	box.offset_bottom = -26
	root.add_child(box)
	_add_bar(box, "health", "Здоровье", Color(0.78, 0.2, 0.17))
	_add_bar(box, "hunger", "Сытость", Color(0.84, 0.6, 0.28))
	_add_bar(box, "thirst", "Вода", Color(0.35, 0.62, 0.82))
	_add_bar(box, "stamina", "Силы", Color(0.86, 0.84, 0.76))
	_add_bar(box, "breath", "Воздух", Color(0.6, 0.85, 0.95))

func _add_bar(parent: Control, key: String, title_text: String, col: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UITheme.label(title_text, 12, Color(UITheme.TEXT, 0.85))
	l.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override(&"outline_size", 4)
	l.custom_minimum_size = Vector2(68, 0)
	row.add_child(l)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(150, 4)
	bar.show_percentage = false
	bar.max_value = 100.0
	bar.value = 100.0
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	bg.border_color = Color(0, 0, 0, 0.35)
	bg.set_border_width_all(1)
	bg.expand_margin_top = 1
	bg.expand_margin_bottom = 1
	bg.set_corner_radius_all(3)
	var fg := StyleBoxFlat.new()
	fg.bg_color = col
	fg.set_corner_radius_all(3)
	bar.add_theme_stylebox_override(&"background", bg)
	bar.add_theme_stylebox_override(&"fill", fg)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar)
	parent.add_child(row)
	_bars[key] = {"bar": bar, "row": row}

func _build_hotbar() -> void:
	var holder := VBoxContainer.new()
	holder.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	holder.anchor_left = 0.5
	holder.anchor_right = 0.5
	holder.anchor_top = 1.0
	holder.anchor_bottom = 1.0
	holder.grow_horizontal = Control.GROW_DIRECTION_BOTH
	holder.grow_vertical = Control.GROW_DIRECTION_BEGIN
	holder.offset_bottom = -18
	holder.alignment = BoxContainer.ALIGNMENT_END
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(holder)
	_hot_name = UITheme.label("", 15, UITheme.TEXT)
	_hot_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hot_name.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.7))
	_hot_name.add_theme_constant_override(&"outline_size", 4)
	holder.add_child(_hot_name)
	_hotbar = HBoxContainer.new()
	_hotbar.add_theme_constant_override(&"separation", 6)
	_hotbar.alignment = BoxContainer.ALIGNMENT_CENTER
	_hotbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_hotbar)
	var inv := player.get(&"inventory") as Inventory
	for i in Inventory.HOTBAR:
		var s := ItemSlot.new()
		s.inv = inv
		s.index = i
		s.show_number = true
		s.custom_minimum_size = Vector2(54, 54)
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.dragging_enabled = false
		_hotbar.add_child(s)
		_hot_slots.append(s)

func _build_hint() -> void:
	_hint_box = PanelContainer.new()
	_hint_box.add_theme_stylebox_override(&"panel", UITheme.box(Color(0, 0, 0, 0.35), 5, Color(0, 0, 0, 0), 0, 10))
	_hint_box.set_anchors_preset(Control.PRESET_CENTER)
	_hint_box.anchor_left = 0.5
	_hint_box.anchor_right = 0.5
	_hint_box.anchor_top = 0.5
	_hint_box.anchor_bottom = 0.5
	_hint_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint_box.offset_top = 46
	_hint_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint = UITheme.label("", 15, UITheme.TEXT)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_box.add_child(_hint)
	_hint_box.visible = false
	root.add_child(_hint_box)

func _build_toasts() -> void:
	_toasts = VBoxContainer.new()
	_toasts.anchor_left = 0.5
	_toasts.anchor_right = 0.5
	_toasts.anchor_top = 0.0
	_toasts.offset_top = 70
	_toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toasts.add_theme_constant_override(&"separation", 6)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toasts)

func _build_death() -> void:
	_death = ColorRect.new()
	(_death as ColorRect).color = Color(0.05, 0.0, 0.0, 0.55)
	_death.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death.visible = false
	root.add_child(_death)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.anchor_left = 0.5
	v.anchor_right = 0.5
	v.anchor_top = 0.5
	v.anchor_bottom = 0.5
	v.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v.grow_vertical = Control.GROW_DIRECTION_BOTH
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	_death.add_child(v)
	_death_title = UITheme.title("Ты погиб", 46)
	_death_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_death_title)
	_death_sub = UITheme.label("", 18, UITheme.TEXT_DIM)
	_death_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_death_sub)

# ---------------- обновление ----------------

func _process(delta: float) -> void:
	if player == null:
		return
	var p := player
	_set_bar("health", float(p.get(&"health")), float(p.get(&"max_health")))
	_set_bar("hunger", float(p.get(&"hunger")), 100.0)
	_set_bar("thirst", float(p.get(&"thirst")), 100.0)
	_set_bar("stamina", float(p.get(&"stamina")), 100.0, bool(p.get(&"tired")))
	var br := float(p.get(&"breath"))
	_set_bar("breath", br, 100.0)
	(_bars["breath"].row as Control).visible = br < 99.5 or bool(p.call(&"is_underwater"))
	var under := bool(p.call(&"is_underwater")) and bool(p.get(&"alive"))
	_water.visible = under
	_flash_a = move_toward(_flash_a, 0.0, delta * 0.9)
	var hp01 := float(p.get(&"health")) / maxf(1.0, float(p.get(&"max_health")))
	_flash.modulate.a = maxf(_flash_a, clampf((0.3 - hp01) * 2.0, 0.0, 0.5))
	_name_t = maxf(0.0, _name_t - delta)
	_hot_name.modulate.a = clampf(_name_t, 0.0, 1.0)
	# В паузе — только меню; в открытом рюкзаке/крафте — без подсказок.
	var paused := get_tree().paused
	for n: Control in [_hotbar.get_parent() as Control, _bars["health"].row.get_parent() as Control, _toasts]:
		n.visible = not paused and bool(p.get(&"alive"))
	_hint_box.modulate.a = 0.0 if paused or bool(p.get(&"ui_open")) else 1.0
	var alive := bool(p.get(&"alive"))
	_cross.visible = alive and not bool(p.get(&"ui_open"))
	_death.visible = not alive
	if not alive:
		if bool(p.get(&"eliminated")):
			_death_title.text = "Ты выбыл"
			_death_sub.text = "Флаг твоей команды уничтожен — возрождения больше нет"
		else:
			_death_title.text = "Ты погиб"
			_death_sub.text = "%s\nВозрождение у флага через %d с" % [_death_reason(StringName(p.get(&"last_damage_kind"))), ceili(float(p.get(&"respawn_left")))]

func _death_reason(kind: StringName) -> String:
	match kind:
		&"drown": return "Утонул"
		&"fall": return "Разбился при падении"
		&"starve": return "Истощение"
		&"bite": return "Растерзан"
		&"fire": return "Сгорел"
		&"food": return "Отравление"
		_: return "Убит"

func _set_bar(key: String, v: float, mx: float, warn: bool = false) -> void:
	var b := _bars[key].bar as ProgressBar
	var row := _bars[key].row as Control
	b.max_value = mx
	b.value = v
	var frac := v / maxf(1.0, mx)
	# Полные показатели почти прозрачны; низкие — яркие (как в The Forest).
	var a := lerpf(1.0, 0.62, clampf((frac - 0.35) / 0.5, 0.0, 1.0))
	if warn:
		a = 0.6 + 0.4 * absf(sin(Time.get_ticks_msec() * 0.006))
	row.modulate.a = a

func _refresh_hotbar() -> void:
	var inv := player.get(&"inventory") as Inventory
	if inv == null:
		return
	for s in _hot_slots:
		s.selected = s.index == inv.selected
		s.refresh()
	var id := inv.selected_id()
	_hot_name.text = Items.item_name(id) if id != &"" else ""
	_name_t = 2.2

func _on_hint(text: String) -> void:
	if text == "":
		_hint_box.visible = false
		return
	_hint.text = text
	_hint_box.visible = true

func show_toast(text: String) -> void:
	var l := UITheme.label(text, 16, UITheme.TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override(&"outline_size", 5)
	_toasts.add_child(l)
	while _toasts.get_child_count() > 4:
		_toasts.get_child(0).queue_free()
		_toasts.remove_child(_toasts.get_child(0))
	var tw := l.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_interval(2.6)
	tw.tween_property(l, "modulate:a", 0.0, 0.9)
	tw.tween_callback(l.queue_free)

func flash_damage(strength: float) -> void:
	_flash_a = maxf(_flash_a, strength)

# ---------------- панели ----------------

func _unhandled_input(event: InputEvent) -> void:
	if player == null or not bool(player.get(&"alive")) or get_tree().paused:
		return
	if event.is_action_pressed(&"inventory"):
		toggle_panel(inventory_panel)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"craft"):
		toggle_panel(craft_panel)
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	# Esc закрывает открытую панель раньше, чем игрок поставит паузу.
	if event.is_action_pressed(&"pause") and any_panel_open():
		close_panels()
		get_viewport().set_input_as_handled()

func any_panel_open() -> bool:
	return inventory_panel.visible or craft_panel.visible

func toggle_panel(p: Control) -> void:
	var open := not p.visible
	close_panels()
	if open:
		p.call(&"open")
		player.call(&"set_ui_open", true)

func close_panels() -> void:
	if inventory_panel.visible:
		inventory_panel.call(&"close")
	if craft_panel.visible:
		craft_panel.call(&"close")
	player.call(&"set_ui_open", false)
