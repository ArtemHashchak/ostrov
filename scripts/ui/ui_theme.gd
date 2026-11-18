class_name UITheme
extends RefCounted
## Общий стиль интерфейса в духе The Forest: минимализм, тёплый белый текст,
## тёмные полупрозрачные панели без рамок, тонкие линии.

const FONT := "res://scenes/ui/fonts/DejaVuSans.ttf"
const FONT_BOLD := "res://scenes/ui/fonts/DejaVuSans-Bold.ttf"
const FONT_SERIF := "res://scenes/ui/fonts/DejaVuSerif.ttf"
const FONT_SERIF_BOLD := "res://scenes/ui/fonts/DejaVuSerif-Bold.ttf"

const TEXT := Color(0.94, 0.92, 0.86)
const TEXT_DIM := Color(0.94, 0.92, 0.86, 0.6)
const ACCENT := Color(0.86, 0.72, 0.45)       # тёплый песочный
const DANGER := Color(0.82, 0.25, 0.2)
const PANEL := Color(0.05, 0.06, 0.05, 0.72)
const SLOT := Color(0.0, 0.0, 0.0, 0.38)
const SLOT_HOVER := Color(1.0, 0.95, 0.85, 0.12)
const LINE := Color(1.0, 0.96, 0.88, 0.16)

static var _theme: Theme = null

static func font(bold: bool = false) -> FontFile:
	return load(FONT_BOLD if bold else FONT) as FontFile

static func serif(bold: bool = true) -> FontFile:
	return load(FONT_SERIF_BOLD if bold else FONT_SERIF) as FontFile

static func box(bg: Color, radius: int = 6, border: Color = Color(0, 0, 0, 0), bw: int = 0, pad: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.6
	sb.content_margin_bottom = pad * 0.6
	sb.anti_aliasing = true
	return sb

static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 16
	t.set_color(&"font_color", &"Label", TEXT)
	t.set_color(&"font_outline_color", &"Label", Color(0, 0, 0, 0.55))
	t.set_constant(&"outline_size", &"Label", 0)
	# Кнопки — текст без коробок, подсветка линией (как меню The Forest).
	var empty := StyleBoxEmpty.new()
	var hover := box(Color(1, 0.95, 0.85, 0.08), 4, Color(0, 0, 0, 0), 0, 14)
	var pressed := box(Color(1, 0.95, 0.85, 0.16), 4, Color(0, 0, 0, 0), 0, 14)
	var normal := box(Color(0, 0, 0, 0), 4, Color(0, 0, 0, 0), 0, 14)
	t.set_stylebox(&"normal", &"Button", normal)
	t.set_stylebox(&"hover", &"Button", hover)
	t.set_stylebox(&"pressed", &"Button", pressed)
	t.set_stylebox(&"focus", &"Button", empty)
	t.set_stylebox(&"disabled", &"Button", normal)
	t.set_color(&"font_color", &"Button", TEXT)
	t.set_color(&"font_hover_color", &"Button", ACCENT)
	t.set_color(&"font_pressed_color", &"Button", ACCENT)
	t.set_color(&"font_focus_color", &"Button", TEXT)
	t.set_color(&"font_disabled_color", &"Button", TEXT_DIM)
	t.set_font_size(&"font_size", &"Button", 18)
	t.set_stylebox(&"panel", &"PanelContainer", box(PANEL, 8, LINE, 1, 16))
	t.set_stylebox(&"panel", &"Panel", box(PANEL, 8, LINE, 1, 16))
	t.set_stylebox(&"normal", &"LineEdit", box(Color(0, 0, 0, 0.35), 4, LINE, 1, 8))
	t.set_color(&"font_color", &"LineEdit", TEXT)
	# Слайдеры.
	var track := box(Color(1, 1, 1, 0.14), 2, Color(0, 0, 0, 0), 0, 0)
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	t.set_stylebox(&"slider", &"HSlider", track)
	var fill := box(ACCENT * Color(1, 1, 1, 0.8), 2, Color(0, 0, 0, 0), 0, 0)
	fill.content_margin_top = 2
	fill.content_margin_bottom = 2
	t.set_stylebox(&"grabber_area", &"HSlider", fill)
	t.set_stylebox(&"grabber_area_highlight", &"HSlider", fill)
	t.set_color(&"font_color", &"CheckBox", TEXT)
	t.set_color(&"font_hover_color", &"CheckBox", ACCENT)
	t.set_stylebox(&"normal", &"CheckBox", normal)
	t.set_stylebox(&"hover", &"CheckBox", hover)
	t.set_stylebox(&"pressed", &"CheckBox", normal)
	t.set_stylebox(&"focus", &"CheckBox", empty)
	t.set_icon(&"unchecked", &"CheckBox", _check_icon(false))
	t.set_icon(&"checked", &"CheckBox", _check_icon(true))
	t.set_stylebox(&"panel", &"TooltipPanel", box(Color(0.04, 0.04, 0.03, 0.92), 4, LINE, 1, 10))
	t.set_color(&"font_color", &"TooltipLabel", TEXT)
	var scroll_bg := StyleBoxEmpty.new()
	t.set_stylebox(&"panel", &"ScrollContainer", scroll_bg)
	t.set_stylebox(&"scroll", &"VScrollBar", box(Color(1, 1, 1, 0.05), 3, Color(0, 0, 0, 0), 0, 2))
	t.set_stylebox(&"grabber", &"VScrollBar", box(Color(1, 1, 1, 0.22), 3, Color(0, 0, 0, 0), 0, 2))
	t.set_stylebox(&"grabber_highlight", &"VScrollBar", box(ACCENT, 3, Color(0, 0, 0, 0), 0, 2))
	_theme = t
	return t

static func label(text: String, size: int = 16, color: Color = TEXT, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	if bold:
		l.add_theme_font_override(&"font", font(true))
	return l

static func title(text: String, size: int = 40) -> Label:
	var l := label(text, size, TEXT)
	l.add_theme_font_override(&"font", serif(true))
	return l

## Короткое имя клавиши действия ("E", "ЛКМ").
static func key_name(action: StringName) -> String:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
			return OS.get_keycode_string(code)
		if ev is InputEventMouseButton:
			match (ev as InputEventMouseButton).button_index:
				MOUSE_BUTTON_LEFT: return "ЛКМ"
				MOUSE_BUTTON_RIGHT: return "ПКМ"
				MOUSE_BUTTON_MIDDLE: return "СКМ"
	return "?"

## Иконка флажка 18×18: рамка, внутри — песочный квадрат, если включено.
static func _check_icon(on: bool) -> ImageTexture:
	var n := 18
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0.35))
	for i in n:
		for e in [0, n - 1]:
			img.set_pixel(i, e, Color(TEXT, 0.55))
			img.set_pixel(e, i, Color(TEXT, 0.55))
	if on:
		img.fill_rect(Rect2i(4, 4, n - 8, n - 8), ACCENT)
	return ImageTexture.create_from_image(img)
