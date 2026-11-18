class_name CraftPanel
extends Control
## Крафт: список рецептов (Items.recipes) слева, выбранный рецепт справа —
## что нужно, сколько есть, станция, кнопка «Сделать».

const ItemsScript := preload("res://scripts/core/items.gd")

var player: Node = null
var selected_recipe: StringName = &""
var _list: VBoxContainer
var _rows: Dictionary = {}  # recipe id -> Button
var _icon: TextureRect
var _name: Label
var _desc: Label
var _needs: VBoxContainer
var _reason: Label
var _make: Button

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", UITheme.box(UITheme.PANEL, 8, UITheme.LINE, 1, 22))
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(640, 400)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 14)
	panel.add_child(v)
	v.add_child(UITheme.title("Крафт", 26))
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 22)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(h)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(230, 320)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	h.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 2)
	scroll.add_child(_list)

	var line := ColorRect.new()
	line.color = UITheme.LINE
	line.custom_minimum_size = Vector2(1, 0)
	h.add_child(line)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override(&"separation", 10)
	h.add_child(right)
	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 14)
	right.add_child(top)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(84, 84)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	top.add_child(_icon)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tv)
	_name = UITheme.label("", 20, UITheme.TEXT, true)
	tv.add_child(_name)
	_desc = UITheme.label("", 13, UITheme.TEXT_DIM)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(260, 0)
	tv.add_child(_desc)
	right.add_child(UITheme.label("Нужно", 12, UITheme.TEXT_DIM))
	_needs = VBoxContainer.new()
	_needs.add_theme_constant_override(&"separation", 4)
	right.add_child(_needs)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(sp)
	_reason = UITheme.label("", 13, UITheme.DANGER)
	right.add_child(_reason)
	_make = Button.new()
	_make.text = "Сделать"
	_make.custom_minimum_size = Vector2(170, 40)
	_make.add_theme_stylebox_override(&"normal", UITheme.box(Color(0.86, 0.72, 0.45, 0.18), 5, UITheme.ACCENT, 1, 8))
	_make.add_theme_stylebox_override(&"hover", UITheme.box(Color(0.86, 0.72, 0.45, 0.32), 5, UITheme.ACCENT, 1, 8))
	_make.add_theme_stylebox_override(&"pressed", UITheme.box(Color(0.86, 0.72, 0.45, 0.45), 5, UITheme.ACCENT, 1, 8))
	_make.add_theme_stylebox_override(&"disabled", UITheme.box(Color(0, 0, 0, 0.2), 5, UITheme.LINE, 1, 8))
	_make.pressed.connect(craft_selected)
	right.add_child(_make)
	ItemIcons.instance(self).icon_ready.connect(func(_id: StringName) -> void: if visible: _show_selected())
	var inv := _inv()
	if inv:
		inv.changed.connect(func() -> void: if visible: _rebuild())

func _inv() -> Inventory:
	return player.get(&"inventory") as Inventory if player else null

func open() -> void:
	visible = true
	_rebuild()

func close() -> void:
	visible = false

## Рецепты, отсортированные: сначала доступные, потом по имени.
func sorted_recipes() -> Array:
	var arr: Array = Items.recipes.values()
	arr.sort_custom(func(a: ItemsScript.RecipeDef, b: ItemsScript.RecipeDef) -> bool:
		var ra := PlayerItems.craft_block_reason(player, a) == ""
		var rb := PlayerItems.craft_block_reason(player, b) == ""
		if ra != rb:
			return ra
		return Items.item_name(a.output) < Items.item_name(b.output))
	return arr

func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
		_list.remove_child(c)
	_rows.clear()
	var recs := sorted_recipes()
	if selected_recipe == &"" or not Items.recipes.has(selected_recipe):
		selected_recipe = (recs[0] as ItemsScript.RecipeDef).id if not recs.is_empty() else &""
	for r: ItemsScript.RecipeDef in recs:
		var ok := PlayerItems.craft_block_reason(player, r) == ""
		var b := Button.new()
		b.text = Items.item_name(r.output) + ("  ×%d" % r.count if r.count > 1 else "")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_pressed = r.id == selected_recipe
		b.icon = ItemIcons.request(self, r.output)
		b.expand_icon = false
		b.add_theme_constant_override(&"icon_max_width", 28)
		b.add_theme_color_override(&"font_color", UITheme.TEXT if ok else UITheme.TEXT_DIM)
		var rid := r.id
		b.pressed.connect(func() -> void: select_recipe(rid))
		_list.add_child(b)
		_rows[r.id] = b
	_show_selected()

func select_recipe(id: StringName) -> void:
	selected_recipe = id
	for k in _rows.keys():
		(_rows[k] as Button).button_pressed = k == id
	_show_selected()

func _show_selected() -> void:
	for c in _needs.get_children():
		c.queue_free()
	var r := Items.recipes.get(selected_recipe) as ItemsScript.RecipeDef
	if r == null:
		_name.text = "Нет рецептов"
		_desc.text = ""
		_reason.text = ""
		_make.disabled = true
		_icon.texture = null
		return
	_icon.texture = ItemIcons.request(self, r.output)
	_name.text = Items.item_name(r.output) + ("  ×%d" % r.count if r.count > 1 else "")
	var def := Items.get_item(r.output)
	_desc.text = String(def.data.get("desc", "")) if def else ""
	var inv := _inv()
	for k in r.needs.keys():
		var need := int(r.needs[k])
		var have := inv.count(StringName(k)) if inv else 0
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 8)
		var ic := TextureRect.new()
		ic.texture = ItemIcons.request(self, StringName(k))
		ic.custom_minimum_size = Vector2(26, 26)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(ic)
		var l := UITheme.label("%s   %d / %d" % [Items.item_name(StringName(k)), have, need], 14, UITheme.TEXT if have >= need else UITheme.DANGER)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(l)
		_needs.add_child(row)
	if r.station != &"":
		_needs.add_child(UITheme.label("Станция: %s" % PlayerItems.station_name(r.station), 13, UITheme.TEXT_DIM))
	var why := PlayerItems.craft_block_reason(player, r)
	_reason.text = why
	_make.disabled = why != ""

func craft_selected() -> bool:
	var r := Items.recipes.get(selected_recipe) as ItemsScript.RecipeDef
	if r == null:
		return false
	var ok := PlayerItems.craft(player, r)
	if ok and player.get(&"hands"):
		(player.get(&"hands") as FPHands).play_use()
	_rebuild()
	return ok
