class_name ControlsHelp
extends PanelContainer
## Экран «Управление»: все клавиши (берутся из карты ввода — после
## переназначения показывает новые) и короткие правила матча.

signal closed

const ROWS: Array[Array] = [
	[&"move_forward", "Вперёд"], [&"move_back", "Назад"], [&"move_left", "Влево"], [&"move_right", "Вправо"],
	[&"jump", "Прыжок / всплыть"], [&"sprint", "Бег"], [&"crouch", "Присесть / нырнуть"],
	[&"attack", "Удар / выстрел"], [&"aim", "Использовать / прицел"], [&"interact", "Действие (поднять, положить бревно)"],
	[&"inventory", "Рюкзак"], [&"craft", "Крафт"], [&"build_menu", "Стройка (меню чертежей)"],
	[&"build_rotate", "Повернуть чертёж / перезарядка"], [&"drop", "Выбросить"], [&"map", "Карта"], [&"pause", "Пауза"],
]

func _init() -> void:
	add_theme_stylebox_override(&"panel", UITheme.box(UITheme.PANEL, 8, UITheme.LINE, 1, 24))
	custom_minimum_size = Vector2(640, 0)
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	theme = UITheme.get_theme()
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 10)
	add_child(v)
	v.add_child(UITheme.title("Управление", 28))
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override(&"h_separation", 16)
	g.add_theme_constant_override(&"v_separation", 4)
	v.add_child(g)
	for r in ROWS:
		var k := key_text(r[0])
		var kl := UITheme.label(k, 14, UITheme.ACCENT, true)
		kl.custom_minimum_size = Vector2(70, 0)
		g.add_child(kl)
		var dl := UITheme.label(String(r[1]), 14)
		dl.custom_minimum_size = Vector2(210, 0)
		g.add_child(dl)
	g.add_child(UITheme.label("1–9 · колесо", 14, UITheme.ACCENT, true))
	g.add_child(UITheme.label("Хотбар", 14))
	v.add_child(UITheme.label("Правила: пока флаг команды цел, погибшие возрождаются у него через %d с.\nФлаг уничтожен — возрождений нет; команда выбывает, когда погибнет последний.\nПобеждает последняя команда. Если время вышло — побеждает лидер по очкам\n(цел ли флаг, чужие флаги, убийства)." % int(Game.RESPAWN_TIME), 13, UITheme.TEXT_DIM))
	var back := PauseMenu.menu_button("Назад", close)
	v.add_child(back)

static func key_text(action: StringName) -> String:
	if not InputMap.has_action(action):
		match action:
			&"build_menu": return "B"
			&"build_rotate": return "R"
		return "—"
	return UITheme.key_name(action)

func close() -> void:
	visible = false
	closed.emit()

func _input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed(&"pause"):
		close()
		get_viewport().set_input_as_handled()
