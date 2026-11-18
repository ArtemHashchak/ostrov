class_name BuildChestPanel
extends CanvasLayer
## Окно сундука: сверху 12 ячеек сундука, снизу инвентарь игрока.
## ЛКМ по ячейке — перенести весь стек туда-обратно, ПКМ — половину.
## E / Esc / Tab — закрыть; закрывается само, если отойти.

const CELL := 58

var player: Node
var chest: BuildChest
var _chest_cells: Array[Control] = []
var _inv_cells: Array[Control] = []
var _title: Label

static func open_for(p: Node, c: BuildChest) -> BuildChestPanel:
	var old := p.get_node_or_null(^"ChestPanel")
	if old:
		old.queue_free()
	var panel := BuildChestPanel.new()
	panel.name = "ChestPanel"
	panel.player = p
	panel.chest = c
	p.add_child(panel)
	return panel

func _ready() -> void:
	layer = 12
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.35)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", UITheme.box(UITheme.PANEL, 8, UITheme.LINE, 1, 16))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 8)
	panel.add_child(v)
	_title = UITheme.label("Сундук", 22, UITheme.ACCENT, true)
	v.add_child(_title)
	var cg := GridContainer.new()
	cg.columns = 6
	v.add_child(cg)
	for i in chest.storage.size():
		var cell := _cell(true, i)
		cg.add_child(cell)
		_chest_cells.append(cell)
	v.add_child(UITheme.label("Твои вещи   ·   ЛКМ — весь стек, ПКМ — половина   ·   E — закрыть", 13, UITheme.TEXT_DIM))
	var ig := GridContainer.new()
	ig.columns = 9
	v.add_child(ig)
	var inv := _inv()
	var n: int = inv.slots.size() if inv else 0
	for i in n:
		var cell2 := _cell(false, i)
		ig.add_child(cell2)
		_inv_cells.append(cell2)
	await get_tree().process_frame
	panel.position = (panel.get_viewport_rect().size - panel.size) * 0.5
	if player.has_method(&"set_ui_open"):
		player.call(&"set_ui_open", true)
	chest.viewer(true)
	chest.storage.changed.connect(_redraw)
	var icons := ItemIcons.instance(self)
	if icons:
		icons.icon_ready.connect(func(_id: StringName) -> void: _redraw())
	if inv:
		inv.changed.connect(_redraw)

func _inv() -> Inventory:
	return BuildEnv.inventory(player) as Inventory

func _cell(is_chest: bool, i: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(CELL, CELL)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.draw.connect(_draw_cell.bind(c, is_chest, i))
	c.gui_input.connect(_cell_input.bind(is_chest, i))
	c.mouse_entered.connect(c.queue_redraw)
	c.mouse_exited.connect(c.queue_redraw)
	return c

func _slot(is_chest: bool, i: int) -> Dictionary:
	if is_chest:
		return chest.storage.get_slot(i)
	var inv := _inv()
	return inv.get_slot(i) if inv else {}

func _draw_cell(c: Control, is_chest: bool, i: int) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	c.draw_style_box(UITheme.box(UITheme.SLOT, 6, UITheme.LINE, 1, 0), r)
	if c.get_global_rect().has_point(c.get_global_mouse_position()):
		c.draw_style_box(UITheme.box(UITheme.SLOT_HOVER, 6), r)
	if not is_chest and i < 9:
		c.draw_string(UITheme.font(), Vector2(4, 12), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UITheme.TEXT_DIM)
	var s := _slot(is_chest, i)
	if s.is_empty():
		return
	var icon := ItemIcons.request(c, StringName(s.id))
	var pad := c.size.x * 0.12
	if icon:
		c.draw_texture_rect(icon, Rect2(Vector2(pad, pad), c.size - Vector2(pad, pad) * 2.0), false)
	else:
		c.draw_circle(c.size * 0.5, c.size.x * 0.22, PlayerItems.color_of(StringName(s.id)))
		c.draw_string(UITheme.font(true), Vector2(0, c.size.y * 0.5 + 6), Items.item_name(StringName(s.id)).substr(0, 2),
			HORIZONTAL_ALIGNMENT_CENTER, c.size.x, 15, UITheme.TEXT)
	if int(s.n) > 1:
		var f := UITheme.font(true)
		c.draw_string_outline(f, Vector2(0, c.size.y - 5), str(int(s.n)), HORIZONTAL_ALIGNMENT_RIGHT, c.size.x - 5, 13, 3, Color(0, 0, 0, 0.8))
		c.draw_string(f, Vector2(0, c.size.y - 5), str(int(s.n)), HORIZONTAL_ALIGNMENT_RIGHT, c.size.x - 5, 13, UITheme.TEXT)
	c.tooltip_text = Items.item_name(StringName(s.id))

func _cell_input(ev: InputEvent, is_chest: bool, i: int) -> void:
	var mb := ev as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		transfer(is_chest, i, false)
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		transfer(is_chest, i, true)

## Перенести стек (или половину) из ячейки в другое хранилище.
func transfer(from_chest: bool, i: int, half: bool) -> void:
	var inv := _inv()
	if inv == null:
		return
	var s := _slot(from_chest, i)
	if s.is_empty():
		return
	var id := StringName(s.id)
	var n := int(s.n)
	var amount := maxi(1, n / 2) if half else n
	var left := 0
	if from_chest:
		left = inv.add(id, amount)
		chest.storage.remove(id, amount - left)
	else:
		left = chest.storage.add(id, amount)
		inv.remove(id, amount - left)
	if left == amount:
		BuildEnv.toast("Нет места")
	_redraw()

func _redraw() -> void:
	for c in _chest_cells:
		c.queue_redraw()
	for c in _inv_cells:
		c.queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"interact") or event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel") \
			or (InputMap.has_action(&"inventory") and event.is_action_pressed(&"inventory")):
		get_viewport().set_input_as_handled()
		close()

func _input(event: InputEvent) -> void:
	# панель ловит клавиши раньше игрока/HUD
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		_unhandled_input(event)

func _process(_d: float) -> void:
	if not is_instance_valid(chest) or chest.is_queued_for_deletion() or not chest.complete:
		close()
		return
	var p3 := player as Node3D
	if p3 and p3.global_position.distance_to(chest.global_position) > 4.5:
		close()

var _closed := false
func close() -> void:
	if _closed:
		return
	_closed = true
	if is_instance_valid(chest):
		chest.viewer(false)
	if is_instance_valid(player) and player.has_method(&"set_ui_open"):
		player.call(&"set_ui_open", false)
	queue_free()
