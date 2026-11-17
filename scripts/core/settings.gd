extends Node
## Настройки игрока и карта ввода. Карта ввода создаётся в коде, чтобы
## project.godot не правили все модули сразу и чтобы работало переназначение.

const SAVE_PATH := "user://settings.cfg"

var mouse_sensitivity: float = 0.0022
var gamepad_look_speed: float = 2.6
var invert_y: bool = false
var fov: float = 75.0
var master_volume: float = 1.0
var shadows_quality: int = 2 # 0 выкл, 1 низко, 2 высоко

## Действия → события по умолчанию. Клавиши — physical keycode.
const DEFAULT_KEYS: Dictionary = {
	&"move_forward": [KEY_W],
	&"move_back": [KEY_S],
	&"move_left": [KEY_A],
	&"move_right": [KEY_D],
	&"jump": [KEY_SPACE],
	&"sprint": [KEY_SHIFT],
	&"crouch": [KEY_CTRL, KEY_C],
	&"interact": [KEY_E],
	&"inventory": [KEY_I, KEY_TAB],
	&"craft": [KEY_B],
	&"pause": [KEY_ESCAPE],
	&"drop": [KEY_G],
	&"hotbar_1": [KEY_1], &"hotbar_2": [KEY_2], &"hotbar_3": [KEY_3],
	&"hotbar_4": [KEY_4], &"hotbar_5": [KEY_5], &"hotbar_6": [KEY_6],
	&"hotbar_7": [KEY_7], &"hotbar_8": [KEY_8], &"hotbar_9": [KEY_9],
}
const DEFAULT_MOUSE: Dictionary = {
	&"attack": MOUSE_BUTTON_LEFT,
	&"aim": MOUSE_BUTTON_RIGHT,
}
const DEFAULT_PAD_BUTTONS: Dictionary = {
	&"jump": JOY_BUTTON_A,
	&"interact": JOY_BUTTON_X,
	&"crouch": JOY_BUTTON_B,
	&"sprint": JOY_BUTTON_LEFT_STICK,
	&"inventory": JOY_BUTTON_Y,
	&"pause": JOY_BUTTON_START,
}
## Оси геймпада: действие → [ось, знак]
const DEFAULT_PAD_AXES: Dictionary = {
	&"move_forward": [JOY_AXIS_LEFT_Y, -1.0],
	&"move_back": [JOY_AXIS_LEFT_Y, 1.0],
	&"move_left": [JOY_AXIS_LEFT_X, -1.0],
	&"move_right": [JOY_AXIS_LEFT_X, 1.0],
	&"look_up": [JOY_AXIS_RIGHT_Y, -1.0],
	&"look_down": [JOY_AXIS_RIGHT_Y, 1.0],
	&"look_left": [JOY_AXIS_RIGHT_X, -1.0],
	&"look_right": [JOY_AXIS_RIGHT_X, 1.0],
	&"attack": [JOY_AXIS_TRIGGER_RIGHT, 1.0],
	&"aim": [JOY_AXIS_TRIGGER_LEFT, 1.0],
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_input_map()
	load_settings()

func _build_input_map() -> void:
	var all_actions: Array = []
	for k in DEFAULT_KEYS.keys(): all_actions.append(k)
	for k in DEFAULT_MOUSE.keys(): all_actions.append(k)
	for k in DEFAULT_PAD_AXES.keys(): all_actions.append(k)
	for k in DEFAULT_PAD_BUTTONS.keys(): all_actions.append(k)
	for action: StringName in all_actions:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
	for action: StringName in DEFAULT_KEYS.keys():
		for key: int in DEFAULT_KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key as Key
			InputMap.action_add_event(action, ev)
	for action: StringName in DEFAULT_MOUSE.keys():
		var mb := InputEventMouseButton.new()
		mb.button_index = DEFAULT_MOUSE[action] as MouseButton
		InputMap.action_add_event(action, mb)
	for action: StringName in DEFAULT_PAD_BUTTONS.keys():
		var jb := InputEventJoypadButton.new()
		jb.button_index = DEFAULT_PAD_BUTTONS[action] as JoyButton
		InputMap.action_add_event(action, jb)
	for action: StringName in DEFAULT_PAD_AXES.keys():
		var jm := InputEventJoypadMotion.new()
		jm.axis = DEFAULT_PAD_AXES[action][0] as JoyAxis
		jm.axis_value = DEFAULT_PAD_AXES[action][1]
		InputMap.action_add_event(action, jm)

## Переназначить клавишу действия (заменяет все клавиатурные события).
func rebind_key(action: StringName, keycode: Key) -> void:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			InputMap.action_erase_event(action, ev)
	var nk := InputEventKey.new()
	nk.physical_keycode = keycode
	InputMap.action_add_event(action, nk)
	save_settings()

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("input", "invert_y", invert_y)
	cfg.set_value("video", "fov", fov)
	cfg.set_value("video", "shadows_quality", shadows_quality)
	cfg.set_value("audio", "master_volume", master_volume)
	for action: StringName in DEFAULT_KEYS.keys():
		var keys: Array = []
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				keys.append((ev as InputEventKey).physical_keycode)
		cfg.set_value("keys", String(action), keys)
	cfg.save(SAVE_PATH)

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	mouse_sensitivity = cfg.get_value("input", "mouse_sensitivity", mouse_sensitivity)
	invert_y = cfg.get_value("input", "invert_y", invert_y)
	fov = cfg.get_value("video", "fov", fov)
	shadows_quality = cfg.get_value("video", "shadows_quality", shadows_quality)
	master_volume = cfg.get_value("audio", "master_volume", master_volume)
	for action: StringName in DEFAULT_KEYS.keys():
		var saved: Variant = cfg.get_value("keys", String(action), null)
		if saved is Array and not (saved as Array).is_empty():
			for ev in InputMap.action_get_events(action):
				if ev is InputEventKey:
					InputMap.action_erase_event(action, ev)
			for key in saved:
				var nk := InputEventKey.new()
				nk.physical_keycode = int(key) as Key
				InputMap.action_add_event(action, nk)

## true, если работаем в упрощённом рендере (наши тесты под xvfb, слабые ПК).
func is_compatibility_renderer() -> bool:
	return RenderingServer.get_rendering_device() == null # у OpenGL (gl_compatibility) нет RenderingDevice
