class_name TutorialUI
extends CanvasLayer
## Интерфейс обучения: панель задания слева (шаг, текст, прогресс, клавиши),
## стрелка к цели (на краю экрана, если цель за кадром), всплывающее «Готово»,
## экран «Обучение завершено».

signal start_match_pressed
signal menu_pressed

var panel: PanelContainer
var _step_lbl: Label
var _title: Label
var _text: Label
var _progress: Label
var _hint: Label
var _skip: Label
var _flash: Label
var _arrow: Control
var done_screen: Control
var target: Variant = null      # Vector3 или null
var target_label: String = ""

func _ready() -> void:
	layer = 6
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	add_child(root)

	_arrow = Control.new()
	_arrow.set_anchors_preset(Control.PRESET_FULL_RECT)
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.draw.connect(_draw_arrow)
	root.add_child(_arrow)

	panel = PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", UITheme.box(Color(0.03, 0.04, 0.03, 0.74), 8,
			Color(0.86, 0.72, 0.45, 0.55), 1, 14))
	panel.position = Vector2(18, 178)
	panel.custom_minimum_size = Vector2(430, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override(&"separation", 6)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vb)
	_step_lbl = UITheme.label("ОБУЧЕНИЕ", 12, UITheme.ACCENT, true)
	vb.add_child(_step_lbl)
	_title = UITheme.title("", 23)
	_title.custom_minimum_size = Vector2(400, 0)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_title)
	_text = UITheme.label("", 15, UITheme.TEXT)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(400, 0)
	vb.add_child(_text)
	_progress = UITheme.label("", 15, UITheme.ACCENT, true)
	_progress.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_progress.custom_minimum_size = Vector2(400, 0)
	vb.add_child(_progress)
	var sep := ColorRect.new()
	sep.color = UITheme.LINE
	sep.custom_minimum_size = Vector2(0, 1)
	vb.add_child(sep)
	_hint = UITheme.label("", 13, UITheme.TEXT_DIM)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(400, 0)
	vb.add_child(_hint)
	_skip = UITheme.label("", 12, UITheme.TEXT_DIM)
	vb.add_child(_skip)

	_flash = UITheme.title("", 34)
	_flash.anchor_left = 0.0
	_flash.anchor_right = 1.0
	_flash.anchor_top = 0.32
	_flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flash.add_theme_color_override(&"font_color", UITheme.ACCENT)
	_flash.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.8))
	_flash.add_theme_constant_override(&"outline_size", 6)
	_flash.modulate.a = 0.0
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_flash)

	_build_done(root)

## Показать шаг. hint — строка с клавишами (уже подставленными).
func set_step(index: int, total: int, title: String, text: String, hint: String) -> void:
	_step_lbl.text = "ОБУЧЕНИЕ · ШАГ %d ИЗ %d" % [index + 1, total]
	_title.text = title
	_text.text = text
	_hint.text = hint
	_hint.visible = hint != ""
	_progress.text = ""
	_skip.text = "%s — пропустить шаг   ·   %s — пауза" % [UITheme.key_name(&"tutorial_skip"), UITheme.key_name(&"pause")]
	panel.modulate.a = 0.0
	create_tween().tween_property(panel, "modulate:a", 1.0, 0.35)

func set_progress(text: String) -> void:
	if _progress.text != text:
		_progress.text = text

func set_target(pos: Variant, label: String = "") -> void:
	target = pos
	target_label = label

func flash(text: String) -> void:
	_flash.text = text
	var tw := create_tween()
	_flash.modulate.a = 0.0
	tw.tween_property(_flash, "modulate:a", 1.0, 0.2)
	tw.tween_interval(1.1)
	tw.tween_property(_flash, "modulate:a", 0.0, 0.5)

func _process(_delta: float) -> void:
	_arrow.queue_redraw()

func _draw_arrow() -> void:
	if not (target is Vector3) or done_screen.visible:
		return
	var cam := _arrow.get_viewport().get_camera_3d()
	if cam == null:
		return
	var tp: Vector3 = target
	var size := _arrow.size
	var center := size * 0.5
	var dist := cam.global_position.distance_to(tp)
	var col := UITheme.ACCENT
	var txt := ("%s · %d м" % [target_label, int(dist)]) if target_label != "" else "%d м" % int(dist)
	var font := UITheme.font(true)
	var on := not cam.is_position_behind(tp)
	var sp := cam.unproject_position(tp + Vector3.UP * 1.2) if on else Vector2.ZERO
	var margin := 46.0
	if on and sp.x > margin and sp.x < size.x - margin and sp.y > margin and sp.y < size.y - margin:
		# цель в кадре: ромб над ней и подпись
		var r := 9.0
		var pts := PackedVector2Array([sp + Vector2(0, -r), sp + Vector2(r, 0), sp + Vector2(0, r), sp + Vector2(-r, 0)])
		_arrow.draw_colored_polygon(pts, Color(col, 0.9))
		_arrow.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(0, 0, 0, 0.7), 1.5)
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		_arrow.draw_string_outline(font, sp + Vector2(-tw * 0.5, -16), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.8))
		_arrow.draw_string(font, sp + Vector2(-tw * 0.5, -16), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
		return
	# цель за кадром: стрелка у края экрана
	var local := cam.global_transform.affine_inverse() * tp
	var d := Vector2(local.x, -local.y)
	if d.length() < 0.001:
		d = Vector2(0, -1)
	d = d.normalized()
	var ext := center - Vector2(margin, margin)
	var k := minf(ext.x / maxf(absf(d.x), 0.001), ext.y / maxf(absf(d.y), 0.001))
	var p := center + d * k
	var perp := Vector2(-d.y, d.x)
	var tri := PackedVector2Array([p + d * 16.0, p - d * 10.0 + perp * 12.0, p - d * 10.0 - perp * 12.0])
	_arrow.draw_colored_polygon(tri, Color(col, 0.95))
	_arrow.draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color(0, 0, 0, 0.7), 1.5)
	var tw2 := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var lp := p - d * 34.0 + Vector2(-tw2 * 0.5, 5)
	lp.x = clampf(lp.x, 8.0, size.x - tw2 - 8.0)
	_arrow.draw_string_outline(font, lp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.8))
	_arrow.draw_string(font, lp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)

# ------------------------------------------------------------ финал

var _done_info: Label
var start_button: Button

func _build_done(root: Control) -> void:
	done_screen = Control.new()
	done_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	done_screen.visible = false
	root.add_child(done_screen)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.62)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	done_screen.add_child(bg)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override(&"panel", UITheme.box(Color(0.04, 0.05, 0.04, 0.92), 10,
			Color(0.86, 0.72, 0.45, 0.6), 1, 30))
	pc.anchor_left = 0.5
	pc.anchor_right = 0.5
	pc.anchor_top = 0.5
	pc.anchor_bottom = 0.5
	pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pc.grow_vertical = Control.GROW_DIRECTION_BOTH
	pc.custom_minimum_size = Vector2(560, 0)
	done_screen.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override(&"separation", 10)
	pc.add_child(vb)
	var t := UITheme.title("Обучение завершено", 40)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var sub := UITheme.label("Ты умеешь всё, что нужно, чтобы защитить свой флаг\nи сломать чужие. Удачи на островах!", 16, UITheme.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	_done_info = UITheme.label("", 14, UITheme.ACCENT)
	_done_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_done_info)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 10)
	vb.add_child(sp)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override(&"separation", 40)
	vb.add_child(hb)
	start_button = PauseMenu.menu_button("Начать матч", func() -> void: start_match_pressed.emit())
	start_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	hb.add_child(start_button)
	var mb := PauseMenu.menu_button("В меню", func() -> void: menu_pressed.emit())
	mb.alignment = HORIZONTAL_ALIGNMENT_CENTER
	hb.add_child(mb)

func show_done(info: String) -> void:
	_done_info.text = info
	panel.visible = false
	target = null
	done_screen.visible = true
	done_screen.modulate.a = 0.0
	create_tween().tween_property(done_screen, "modulate:a", 1.0, 0.5)
	start_button.grab_focus.call_deferred()
