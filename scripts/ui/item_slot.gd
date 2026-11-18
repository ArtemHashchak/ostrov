class_name ItemSlot
extends Control
## Ячейка инвентаря/хотбара: 3D-иконка предмета, количество, номер, подсветка.
## Перетаскивание между ячейками (drag & drop) меняет местами/объединяет стеки.

signal hovered(index: int)
signal unhovered(index: int)
signal clicked(index: int, button: int)

var inv: Inventory
var index: int = 0
var show_number: bool = false
var selected: bool = false
var dragging_enabled: bool = true
var _hover := false
var _icon: Texture2D = null
var _icon_id: StringName = &""

func _init() -> void:
	custom_minimum_size = Vector2(64, 64)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	mouse_entered.connect(func() -> void: _hover = true; hovered.emit(index); queue_redraw())
	mouse_exited.connect(func() -> void: _hover = false; unhovered.emit(index); queue_redraw())
	var r := ItemIcons.instance(self)
	if not r.icon_ready.is_connected(_on_icon_ready):
		r.icon_ready.connect(_on_icon_ready)
	refresh()

func _on_icon_ready(id: StringName) -> void:
	if id == _icon_id:
		_icon = ItemIcons.cache.get(id)
		queue_redraw()

func slot() -> Dictionary:
	return inv.get_slot(index) if inv else {}

func refresh() -> void:
	var s := slot()
	var id: StringName = s.id if not s.is_empty() else &""
	if id != _icon_id:
		_icon_id = id
		_icon = ItemIcons.request(self, id)
	var d := Items.get_item(id) if id != &"" else null
	tooltip_text = ""
	if d:
		tooltip_text = d.name
		var desc := String(d.data.get("desc", ""))
		if desc != "":
			tooltip_text += "\n" + desc
	queue_redraw()

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var bg := UITheme.SLOT
	draw_style_box(UITheme.box(bg, 6, UITheme.LINE, 1, 0), r)
	if _hover:
		draw_style_box(UITheme.box(UITheme.SLOT_HOVER, 6), r)
	if selected:
		draw_style_box(UITheme.box(Color(0, 0, 0, 0), 6, UITheme.ACCENT, 2, 0), r)
	var s := slot()
	if not s.is_empty():
		var pad := size.x * 0.1
		var ir := Rect2(Vector2(pad, pad), size - Vector2(pad, pad) * 2.0)
		if _icon:
			draw_texture_rect(_icon, ir, false)
		else:
			# Пока иконка рисуется — цветной кружок с буквой.
			var c := PlayerItems.color_of(s.id)
			draw_circle(size * 0.5, size.x * 0.22, c)
			var nm := Items.item_name(s.id)
			var f := UITheme.font(true)
			draw_string(f, Vector2(0, size.y * 0.5 + 6), nm.substr(0, 2), HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, UITheme.TEXT)
		if int(s.n) > 1:
			var f2 := UITheme.font(true)
			var txt := str(int(s.n))
			draw_string_outline(f2, Vector2(0, size.y - 6), txt, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 6, 14, 3, Color(0, 0, 0, 0.8))
			draw_string(f2, Vector2(0, size.y - 6), txt, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 6, 14, UITheme.TEXT)
	if show_number:
		var f3 := UITheme.font()
		draw_string(f3, Vector2(5, 14), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.TEXT_DIM)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		clicked.emit(index, (event as InputEventMouseButton).button_index)

func _get_drag_data(_at: Vector2) -> Variant:
	if not dragging_enabled or slot().is_empty():
		return null
	var prev := TextureRect.new()
	prev.texture = _icon
	prev.custom_minimum_size = size * 0.9
	prev.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	prev.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	prev.modulate = Color(1, 1, 1, 0.85)
	set_drag_preview(prev)
	return {"inv_slot": index, "inv": inv}

func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and (data as Dictionary).has("inv_slot") and (data as Dictionary).inv == inv

func _drop_data(_at: Vector2, data: Variant) -> void:
	inv.move(int((data as Dictionary).inv_slot), index)
