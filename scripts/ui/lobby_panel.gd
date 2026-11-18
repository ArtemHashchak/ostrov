class_name LobbyPanel
extends PanelContainer
## Лобби перед матчем: режим, боты, сложность, длительность, размер карты,
## сид, флаги. «Начать» → GameLauncher.start(config).

signal closed
signal started(config: Dictionary)

var config: Dictionary = {}
## false — только сигнал started, без смены сцены (для тестов).
var launch := true
var _groups: Dictionary = {} # key → Array[Button]
var _seed_edit: LineEdit
var start_button: Button
var _note: Label

const OPTIONS: Array[Dictionary] = [
	{"key": "mode", "title": "Режим", "values": ["ffa", "2x2"], "labels": ["Каждый за себя · 4 команды", "2 × 2"]},
	{"key": "bots_enemy", "title": "Ботов в команде соперника", "values": [0, 1, 2, 3], "labels": ["0", "1", "2", "3"]},
	{"key": "bots_ally", "title": "Ботов-союзников", "values": [0, 1, 2, 3], "labels": ["0", "1", "2", "3"]},
	{"key": "difficulty", "title": "Сложность ботов", "values": ["easy", "normal", "hard"], "labels": ["Лёгкие", "Средние", "Сильные"]},
	{"key": "minutes", "title": "Длительность", "values": [60, 120, 180, 240, 0], "labels": ["1 ч", "2 ч", "3 ч", "4 ч", "До последнего флага"]},
	{"key": "map_size", "title": "Размер карты", "values": ["small", "normal", "large"], "labels": ["Малая", "Обычная", "Большая"]},
	{"key": "auto_flags", "title": "Флаги", "values": [true, false], "labels": ["Стоят с начала", "Поставить самому"]},
]

func _init() -> void:
	add_theme_stylebox_override(&"panel", UITheme.box(UITheme.PANEL, 8, UITheme.LINE, 1, 26))
	custom_minimum_size = Vector2(700, 0)
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	theme = UITheme.get_theme()
	if config.is_empty():
		config = GameLauncher.load_lobby()
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 12)
	add_child(v)
	v.add_child(UITheme.title("Новый матч", 32))
	v.add_child(UITheme.label("Защити флаг. Пока он стоит — ты возрождаешься. Последний флаг побеждает.", 13, UITheme.TEXT_DIM))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 18)
	grid.add_theme_constant_override(&"v_separation", 10)
	v.add_child(grid)
	for o in OPTIONS:
		var l := UITheme.label(String(o.title), 14)
		l.custom_minimum_size = Vector2(210, 0)
		grid.add_child(l)
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 4)
		grid.add_child(row)
		var bg := ButtonGroup.new()
		var btns: Array[Button] = []
		for i in (o.values as Array).size():
			var b := _seg_button(String(o.labels[i]))
			b.button_group = bg
			var key := String(o.key)
			var val: Variant = o.values[i]
			b.pressed.connect(func() -> void: set_option(key, val))
			row.add_child(b)
			btns.append(b)
		_groups[String(o.key)] = btns
	grid.add_child(UITheme.label("Сид карты", 14))
	var sr := HBoxContainer.new()
	sr.add_theme_constant_override(&"separation", 6)
	grid.add_child(sr)
	_seed_edit = LineEdit.new()
	_seed_edit.custom_minimum_size = Vector2(140, 30)
	_seed_edit.text = str(int(config.get("seed", 2026)))
	_seed_edit.text_changed.connect(func(t: String) -> void:
		if t.is_valid_int(): config.seed = int(t))
	sr.add_child(_seed_edit)
	var rnd := _seg_button("Случайный")
	rnd.toggle_mode = false
	rnd.pressed.connect(func() -> void:
		config.seed = randi() % 100000
		_seed_edit.text = str(int(config.seed)))
	sr.add_child(rnd)
	_note = UITheme.label("", 12, UITheme.TEXT_DIM)
	v.add_child(_note)
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override(&"separation", 26)
	v.add_child(bh)
	start_button = PauseMenu.menu_button("Начать", start_match)
	start_button.add_theme_color_override(&"font_color", UITheme.ACCENT)
	bh.add_child(start_button)
	bh.add_child(PauseMenu.menu_button("Назад", close))
	_sync()

func _seg_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(44, 30)
	b.add_theme_font_size_override(&"font_size", 14)
	b.add_theme_stylebox_override(&"normal", UITheme.box(Color(0, 0, 0, 0.3), 4, UITheme.LINE, 1, 6))
	b.add_theme_stylebox_override(&"hover", UITheme.box(UITheme.SLOT_HOVER, 4, UITheme.LINE, 1, 6))
	b.add_theme_stylebox_override(&"pressed", UITheme.box(Color(UITheme.ACCENT, 0.28), 4, UITheme.ACCENT, 1, 6))
	b.add_theme_stylebox_override(&"hover_pressed", UITheme.box(Color(UITheme.ACCENT, 0.36), 4, UITheme.ACCENT, 1, 6))
	b.add_theme_color_override(&"font_pressed_color", UITheme.TEXT)
	b.add_theme_color_override(&"font_hover_pressed_color", UITheme.TEXT)
	return b

func set_option(key: String, val: Variant) -> void:
	config[key] = val
	_sync()

func _sync() -> void:
	for o in OPTIONS:
		var key := String(o.key)
		var btns: Array = _groups.get(key, [])
		var cur: Variant = config.get(key, Game.DEFAULT_CONFIG.get(key))
		for i in btns.size():
			(btns[i] as Button).set_pressed_no_signal(_same(o.values[i], cur))
	var two := String(config.get("mode", "ffa")) == "2x2"
	var note := _note
	if note:
		var enemies := (1 if two else 3) * int(config.get("bots_enemy", 1))
		var allies := int(config.get("bots_ally", 0))
		note.text = "%s · команд: %d · ботов: %d соперников, %d союзников" % [
			"2 × 2" if two else "Каждый за себя", 2 if two else 4, enemies, allies]

static func _same(a: Variant, b: Variant) -> bool:
	if typeof(a) == TYPE_BOOL or typeof(b) == TYPE_BOOL:
		return bool(a) == bool(b)
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
		return int(a) == int(b)
	return str(a) == str(b)

## Итоговый конфиг матча.
func build_config() -> Dictionary:
	var c: Dictionary = Game.DEFAULT_CONFIG.duplicate()
	c.merge(config, true)
	c.teams = 2 if String(c.mode) == "2x2" else 4
	c.minutes = int(c.minutes)
	c.bots_enemy = int(c.bots_enemy)
	c.bots_ally = int(c.bots_ally)
	c.seed = int(c.seed)
	return c

func start_match() -> void:
	var c := build_config()
	started.emit(c)
	if launch:
		GameLauncher.start(get_tree(), c)
	else:
		Game.pending_config = c

func close() -> void:
	visible = false
	closed.emit()

func _input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed(&"pause"):
		close()
		get_viewport().set_input_as_handled()
