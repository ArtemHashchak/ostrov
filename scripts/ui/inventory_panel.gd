class_name InventoryPanel
extends Control
## Рюкзак: сетка 6×4 + ряд хотбара. Перетаскивание меняет местами/объединяет,
## перетаскивание за пределы панели — выбросить. Наведение + цифра 1–9 —
## переложить предмет в эту ячейку хотбара. ПКМ — быстро переложить
## между рюкзаком и хотбаром.

const COLS := 6

var player: Node = null
var slots: Array[ItemSlot] = []
var hovered_index: int = -1
var _info_name: Label
var _info_desc: Label
var _weight: Label

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	var inv := _inv()
	# Затемнение фона (сюда можно «уронить» предмет — выбросить).
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(dim)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", UITheme.box(UITheme.PANEL, 8, UITheme.LINE, 1, 22))
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 12)
	panel.add_child(v)

	var head := HBoxContainer.new()
	head.add_child(UITheme.title("Рюкзак", 26))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_weight = UITheme.label("", 13, UITheme.TEXT_DIM)
	_weight.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_weight)
	v.add_child(head)

	var grid := GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override(&"h_separation", 6)
	grid.add_theme_constant_override(&"v_separation", 6)
	v.add_child(grid)
	for i in range(Inventory.HOTBAR, Inventory.SIZE):
		grid.add_child(_make_slot(inv, i, false))

	v.add_child(_sep())
	var hl := UITheme.label("Под рукой  ·  наведи и нажми 1–9", 12, UITheme.TEXT_DIM)
	v.add_child(hl)
	var hot := HBoxContainer.new()
	hot.add_theme_constant_override(&"separation", 6)
	v.add_child(hot)
	for i in Inventory.HOTBAR:
		var s := _make_slot(inv, i, true)
		s.custom_minimum_size = Vector2(52, 52)
		hot.add_child(s)

	v.add_child(_sep())
	_info_name = UITheme.label(" ", 16, UITheme.TEXT, true)
	v.add_child(_info_name)
	_info_desc = UITheme.label(" ", 13, UITheme.TEXT_DIM)
	_info_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_desc.custom_minimum_size = Vector2(0, 34)
	v.add_child(_info_desc)
	var help := UITheme.label("Перетащи — переложить  ·  за край — выбросить  ·  ПКМ — в хотбар/рюкзак  ·  %s — крафт" % UITheme.key_name(&"craft"), 11, UITheme.TEXT_DIM)
	v.add_child(help)
	if inv:
		inv.changed.connect(_refresh)

func _sep() -> Control:
	var c := ColorRect.new()
	c.color = UITheme.LINE
	c.custom_minimum_size = Vector2(0, 1)
	return c

func _make_slot(inv: Inventory, i: int, num: bool) -> ItemSlot:
	var s := ItemSlot.new()
	s.inv = inv
	s.index = i
	s.show_number = num
	s.hovered.connect(_on_hover)
	s.unhovered.connect(func(idx: int) -> void:
		if hovered_index == idx:
			hovered_index = -1)
	s.clicked.connect(_on_click)
	slots.append(s)
	return s

func _inv() -> Inventory:
	return player.get(&"inventory") as Inventory if player else null

func open() -> void:
	visible = true
	_refresh()

func close() -> void:
	visible = false
	hovered_index = -1

func _refresh() -> void:
	var inv := _inv()
	if inv == null:
		return
	var w := 0.0
	for s in slots:
		s.selected = s.index == inv.selected
		s.refresh()
		var d := inv.get_slot(s.index)
		if not d.is_empty():
			var def := Items.get_item(d.id)
			if def:
				w += def.weight * int(d.n)
	_weight.text = "Вес: %.1f" % w
	_on_hover(hovered_index)

func _on_hover(i: int) -> void:
	hovered_index = i
	var inv := _inv()
	var d := inv.get_slot(i) if inv and i >= 0 else {}
	if d.is_empty():
		_info_name.text = " "
		_info_desc.text = " "
		return
	var def := Items.get_item(d.id)
	_info_name.text = Items.item_name(d.id) + ("  ×%d" % int(d.n) if int(d.n) > 1 else "")
	var desc := String(def.data.get("desc", "")) if def else ""
	if PlayerItems.is_consumable(d.id):
		desc += ("  " if desc != "" else "") + "(%s — съесть/выпить в руке)" % UITheme.key_name(&"aim")
	_info_desc.text = desc if desc != "" else " "

func _on_click(i: int, button: int) -> void:
	if button == MOUSE_BUTTON_RIGHT:
		quick_move(i)

## ПКМ: из рюкзака — в первую свободную ячейку хотбара, из хотбара — в рюкзак.
func quick_move(i: int) -> void:
	var inv := _inv()
	if inv == null or inv.get_slot(i).is_empty():
		return
	var rng := range(0, Inventory.HOTBAR) if i >= Inventory.HOTBAR else range(Inventory.HOTBAR, Inventory.SIZE)
	for j: int in rng:
		if inv.get_slot(j).is_empty():
			inv.move(i, j)
			return

## Наведение + цифра: переложить предмет в ячейку хотбара n (0..8).
func to_hotbar(from: int, n: int) -> void:
	var inv := _inv()
	if inv and from >= 0 and from != n:
		inv.move(from, n)

func _input(event: InputEvent) -> void:
	if not visible or hovered_index < 0:
		return
	for n in Inventory.HOTBAR:
		if event.is_action_pressed(StringName("hotbar_%d" % (n + 1))):
			to_hotbar(hovered_index, n)
			get_viewport().set_input_as_handled()
			return

# Бросили предмет мимо ячеек — выбросить его в мир.
func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and (data as Dictionary).has("inv_slot")

func _drop_data(_at: Vector2, data: Variant) -> void:
	if player and player.has_method(&"drop_slot"):
		player.call(&"drop_slot", int((data as Dictionary).inv_slot))
