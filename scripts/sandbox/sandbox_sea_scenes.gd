class_name SandboxSeaScenes
extends CanvasLayer
## Полигон, точка «Сцены моря»: панель (F7) с кнопкой на каждую сцену морской жизни
## (SeaScenesLib: охота акулы, укрытия в кораллах, нерест, крабы, осьминог, скат, дельфины…).
## Нажал — сцена ставится там, где глубина ей подходит (рядом с вами или в радиусе 160 м),
## а вы переноситесь к точке обзора. Время суток и погода — кнопки «Полигона» (F1).

const KEY := KEY_F7

var _panel: PanelContainer
var _status: Label
var _auto_cb: CheckBox
var _move_cb: CheckBox

## Точка телепорта у подводного склона и сама панель.
static func build(zones: SandboxZones, root: Node3D) -> void:
	var w := zones.world
	if w == null:
		return
	var I: Dictionary = w.arch.islands[0]
	var cc: Vector2 = I.center
	var dir := Vector2.from_angle(PI * 0.5 + 0.6)
	var spot := Vector2.INF
	for st in range(20, 260, 2):
		var q := cc + dir * float(st)
		if SandboxProps.ground(q.x, q.y) < -3.5:
			spot = q
			break
	if spot.x != INF:
		var gy := SandboxProps.ground(spot.x, spot.y)
		zones._point(&"sea_scenes", "Сцены моря (F7 — список)",
			Vector3(spot.x - dir.x * 6.0, clampf(gy + 2.0, gy + 1.0, -1.2), spot.y - dir.y * 6.0), Vector3(spot.x, gy + 1.0, spot.y))
		SandboxProps.label(root, Vector3(spot.x - dir.x * 5.0, 2.4, spot.y - dir.y * 5.0), "Сцены морской жизни · F7 — выбрать сцену · нырните", 34, SandboxProps.SIGN_COLOR, 60.0)
	var ui := SandboxSeaScenes.new()
	ui.name = "SeaScenesUI"
	root.add_child(ui)

func _ready() -> void:
	layer = 20
	_panel = PanelContainer.new()
	_panel.theme = UITheme.get_theme()
	_panel.add_theme_stylebox_override(&"panel", UITheme.box(UITheme.PANEL, 8, UITheme.LINE, 1, 12))
	_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_panel.offset_left = -440
	_panel.offset_top = 16
	_panel.offset_bottom = -16
	_panel.offset_right = -16
	_panel.visible = false
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 4)
	_panel.add_child(v)
	v.add_child(UITheme.title("Сцены моря", 24))
	v.add_child(UITheme.label("Виды без своих моделей играют «дублёры» — модели пака с подкраской или простые силуэты.", 13, UITheme.TEXT_DIM))
	_auto_cb = CheckBox.new()
	_auto_cb.text = "Сцены сами появляются рядом (как в игре)"
	_auto_cb.button_pressed = true
	_auto_cb.toggled.connect(func(on: bool) -> void:
		var d := SeaSceneDirector.instance()
		if d:
			d.auto = on)
	v.add_child(_auto_cb)
	_move_cb = CheckBox.new()
	_move_cb.text = "Переносить меня к сцене"
	_move_cb.button_pressed = true
	v.add_child(_move_cb)
	var stop := Button.new()
	stop.text = "Убрать все сцены"
	stop.pressed.connect(func() -> void:
		var d := SeaSceneDirector.instance()
		if d:
			d.stop_all()
		_status.text = "Сцены убраны")
	v.add_child(stop)
	_status = UITheme.label("", 13, UITheme.ACCENT)
	v.add_child(_status)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	for id: String in SeaScenesLib.ids():
		var info: Dictionary = SeaScenesLib.CATALOG[id]
		var b := Button.new()
		var tm: String = {"day": "день", "night": "ночь", "dusk": "закат", "any": ""}.get(String(info.get("time", "any")), "")
		b.text = String(info.title) + ("  · " + String(tm) if tm != "" else "")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override(&"font_size", 14)
		b.clip_text = true
		b.pressed.connect(_play.bind(id))
		list.add_child(b)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and (e as InputEventKey).pressed and not (e as InputEventKey).echo and (e as InputEventKey).keycode == KEY:
		toggle()
		get_viewport().set_input_as_handled()

func toggle() -> void:
	_panel.visible = not _panel.visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _panel.visible else Input.MOUSE_MODE_CAPTURED

## Поставить сцену: у камеры, если глубина подходит, иначе — в радиусе 160 м.
func _play(id: String) -> void:
	var d := SeaSceneDirector.instance()
	var cam := get_viewport().get_camera_3d()
	if d == null or cam == null:
		_status.text = "Нет моря на сцене"
		return
	var info: Dictionary = SeaScenesLib.CATALOG[id]
	var pos: Variant = d.find_spot(info, cam.global_position, -cam.global_transform.basis.z)
	if pos == null:
		pos = d.find_spot_around(info, cam.global_position, 200.0)
	if pos == null:
		_status.text = "Нет подходящей глубины рядом: %s" % str(info.depth)
		return
	var s := d.play(id, pos as Vector3)
	if s == null:
		return
	_status.text = "Сцена: %s (%d м)" % [s.title, int((pos as Vector3).distance_to(cam.global_position))]
	if _move_cb.button_pressed and not bool(info.get("far", false)):
		_view(s, String(info.get("view", "underwater")))
	toggle()

## Перенести игрока к точке обзора сцены.
func _view(s: SeaScene, view: String) -> void:
	var cheats := get_tree().current_scene.find_child("Cheats", true, false) as SandboxCheats if get_tree().current_scene else null
	if cheats == null:
		return
	var wy := s.water_y()
	var p := s.at + Vector3(-4.5, 0.0, -4.5)
	var fl := s.floor_y(p.x, p.z)
	var look := s.at + Vector3(0, 0.6, 0)
	if view == "surface" or wy - fl < 1.2:
		p.y = maxf(fl, wy) + 0.1
		look = Vector3(s.at.x, wy, s.at.z)
	else:
		p.y = clampf(fl + 1.0, fl + 0.5, wy - 1.8)
	cheats.teleport(p, look)
