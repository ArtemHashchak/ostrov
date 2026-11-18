class_name EndScreen
extends Control
## Экран конца матча (и выбывания своей команды): итог, таблица статистики,
## кнопки «Ещё раз» / «В меню» (+ «Наблюдать», если матч ещё идёт).

var _title: Label
var _sub: Label
var _grid: GridContainer
var _watch: Button
var _again: Button
var final := false

const COLS: Array[String] = ["Игрок", "Команда", "Убийства", "Смерти", "Брёвна", "Мосты", "Флаги", "В игре"]

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	theme = UITheme.get_theme()
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.03, 0.84)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var v := VBoxContainer.new()
	v.anchor_left = 0.5
	v.anchor_right = 0.5
	v.anchor_top = 0.5
	v.anchor_bottom = 0.5
	v.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v.grow_vertical = Control.GROW_DIRECTION_BOTH
	v.add_theme_constant_override(&"separation", 10)
	add_child(v)
	_title = UITheme.title("", 54)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title)
	_sub = UITheme.label("", 18, UITheme.TEXT_DIM)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_sub)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override(&"panel", UITheme.box(UITheme.PANEL, 8, UITheme.LINE, 1, 18))
	v.add_child(pc)
	_grid = GridContainer.new()
	_grid.columns = COLS.size()
	_grid.add_theme_constant_override(&"h_separation", 22)
	_grid.add_theme_constant_override(&"v_separation", 6)
	pc.add_child(_grid)
	var bh := HBoxContainer.new()
	bh.alignment = BoxContainer.ALIGNMENT_CENTER
	bh.add_theme_constant_override(&"separation", 30)
	v.add_child(bh)
	_watch = PauseMenu.menu_button("Наблюдать", func() -> void:
		visible = false
		_set_player_ui(false))
	bh.add_child(_watch)
	_again = PauseMenu.menu_button("Ещё раз", func() -> void: GameLauncher.restart(get_tree()))
	bh.add_child(_again)
	bh.add_child(PauseMenu.menu_button("В меню", func() -> void: GameLauncher.to_menu(get_tree())))

## Показать. win — победившая команда (-1 ничья); final=false — своя команда выбыла, матч идёт.
func show_result(win: int, is_final: bool) -> void:
	final = is_final
	var pteam := _player_team()
	if not is_final:
		_title.text = "Ваша команда выбыла"
		_title.add_theme_color_override(&"font_color", UITheme.DANGER)
		_sub.text = "Флаг уничтожен, все погибли · %s" % MatchHUD.fmt_time(Game.match_time)
	elif win < 0:
		_title.text = "Ничья"
		_title.add_theme_color_override(&"font_color", UITheme.ACCENT)
		_sub.text = "Время вышло · %s" % MatchHUD.fmt_time(Game.match_time)
	else:
		var won := win == pteam
		_title.text = "Победа!" if won else "Поражение"
		_title.add_theme_color_override(&"font_color", UITheme.ACCENT if won else UITheme.DANGER)
		var how := "последний флаг" if not Game.has_time_limit() or Game.time_left() > 0.5 else "по очкам, время вышло"
		_sub.text = "Победили %s (%s) · %s" % [Game.TEAM_NAMES[win % 4], how, MatchHUD.fmt_time(Game.match_time)]
	_watch.visible = not is_final
	_fill()
	visible = true
	_set_player_ui(true)
	_again.grab_focus.call_deferred()

func _fill() -> void:
	for c in _grid.get_children():
		c.queue_free()
	for h in COLS:
		_grid.add_child(UITheme.label(h, 13, UITheme.ACCENT, true))
	for r in Game.stats_rows():
		var team := int(r.team)
		var col := UITheme.TEXT if not bool(r.is_player) else UITheme.ACCENT
		_grid.add_child(UITheme.label(String(r.name), 15, col, bool(r.is_player)))
		_grid.add_child(UITheme.label(Game.TEAM_NAMES[team % 4], 15, Game.team_color(team).lightened(0.2)))
		for k: String in ["kills", "deaths", "logs", "bridges", "flags"]:
			var l := UITheme.label(str(int(r[k])), 15, col)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_grid.add_child(l)
		_grid.add_child(UITheme.label(MatchHUD.fmt_time(float(r.out_time)), 15, col))

func _player_team() -> int:
	var p := get_tree().get_first_node_in_group(&"player")
	return int(p.get(&"team")) if p and p.get(&"team") != null else 0

func _set_player_ui(open: bool) -> void:
	var p := get_tree().get_first_node_in_group(&"player")
	# HUD игрока (экран гибели) не должен просвечивать под итогом.
	var h: Variant = p.get(&"hud") if p else null
	if h is CanvasLayer:
		(h as CanvasLayer).visible = not open
	if p and p.has_method(&"set_ui_open"):
		p.call(&"set_ui_open", open)
	elif DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
	# Esc на экране итога не ставит паузу.
	if visible and event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
