class_name SandboxCatalog
extends PanelContainer
## «Каталог существ» полигона (кнопка в меню F1): кнопка на каждый вид из реестров игры,
## по группам (животные / птицы / море / растения), выбор количества 1/10/100.
## Призывает у прицела через тот же CreatureSpawner, что и консоль (` / Ё).

var panel: Node                 # SandboxPanel (aim_point, _toast)
var _count := 1
var _groups: VBoxContainer
var _filter: LineEdit
var _status: Label

func _ready() -> void:
	# по центру экрана, 80×80 % (поверх меню F1)
	anchor_left = 0.1
	anchor_right = 0.9
	anchor_top = 0.08
	anchor_bottom = 0.92
	offset_left = 0
	offset_right = 0
	offset_top = 0
	offset_bottom = 0
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.08, 0.1, 0.95)
	sb.border_color = Color(0.3, 0.75, 0.7)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(14)
	add_theme_stylebox_override(&"panel", sb)
	var v := VBoxContainer.new()
	add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var t := Label.new()
	t.text = "Каталог существ"
	t.add_theme_font_size_override(&"font_size", 22)
	t.add_theme_color_override(&"font_color", Color(0.55, 0.95, 0.85))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(t)
	top.add_child(_lbl("Сколько:"))
	for n: int in [1, 10, 100]:
		var b := Button.new()
		b.text = "×%d" % n
		b.toggle_mode = true
		b.button_pressed = n == 1
		b.pressed.connect(func() -> void:
			_count = n
			for c in top.get_children():
				if c is Button and (c as Button).toggle_mode:
					(c as Button).set_pressed_no_signal((c as Button).text == "×%d" % n))
		top.add_child(b)
	_filter = LineEdit.new()
	_filter.placeholder_text = "поиск…"
	_filter.custom_minimum_size = Vector2(160, 0)
	_filter.text_changed.connect(func(_s: String) -> void: rebuild())
	top.add_child(_filter)
	var cl := Button.new()
	cl.text = "Убрать созданных"
	cl.pressed.connect(func() -> void:
		var k := CreatureSpawner.instance().clear(Vector3.ZERO, 0.0)
		_status.text = "Убрано: %d" % k)
	top.add_child(cl)
	var x := Button.new()
	x.text = "✕"
	x.pressed.connect(func() -> void: visible = false)
	top.add_child(x)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	_groups = VBoxContainer.new()
	_groups.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_groups)
	_status = _lbl("Нажмите на вид — он появится у прицела. Консоль: ` / Ё (spawn краб 100).")
	v.add_child(_status)
	rebuild()

func _lbl(s: String) -> Label:
	var l := Label.new()
	l.text = s
	return l

## Пересобрать кнопки (список живой: новые виды появляются сами).
func rebuild() -> void:
	for c in _groups.get_children():
		c.queue_free()
	var f := _filter.text.strip_edges().to_lower() if _filter else ""
	for cat: String in CreatureSpawner.CATS:
		var list := CreatureSpawner.all_species(cat)
		var shown: Array[Dictionary] = []
		for d in list:
			if f == "" or String(d.name).to_lower().contains(f) or String(d.id).contains(f):
				shown.append(d)
		if shown.is_empty():
			continue
		var h := _lbl("%s — %d" % [CreatureSpawner.CATS[cat], shown.size()])
		h.add_theme_font_size_override(&"font_size", 17)
		h.add_theme_color_override(&"font_color", Color(0.95, 0.8, 0.45))
		_groups.add_child(h)
		var g := GridContainer.new()
		g.columns = 5
		_groups.add_child(g)
		for d in shown:
			var b := Button.new()
			b.text = String(d.name)
			b.tooltip_text = "%s  [%s]" % [d.id, d.src]
			b.custom_minimum_size = Vector2(184, 30)
			b.clip_text = true
			var id := String(d.id)
			b.pressed.connect(func() -> void: spawn(id))
			g.add_child(b)

func spawn(id: String) -> int:
	var p: Vector3 = panel.call(&"aim_point") if panel and panel.has_method(&"aim_point") else Vector3.ZERO
	var got := CreatureSpawner.spawn(id, p, _count)
	var info := CreatureSpawner.find(id)
	_status.text = ("Призываю: %s ×%d" % [info.get("name", id), got]) if got > 0 else "Лимит существ — нажмите «Убрать созданных»."
	return got

func open() -> void:
	visible = true
	rebuild()
