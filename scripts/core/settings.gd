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
## Качество графики: 0 низкое, 1 среднее, 2 высокое, 3 ультра (apply_graphics).
var graphics_quality: int = 2
## Обучение пройдено (TUTORIAL).
var tutorial_done: bool = false
## Масштаб 3D: 0 — авто по пресету и разрешению, иначе 0.25..1.0.
var render_scale: float = 0.0
## Динамическое разрешение: снижать масштаб 3D, когда кадр не успевает.
var dynamic_resolution: bool = false
## Вертикальная синхронизация и ограничение кадров (0 — без ограничения).
var vsync: bool = true
var fps_cap: int = 0
## Масштаб интерфейса поверх растяжения canvas_items (0.75..1.5).
var ui_scale: float = 1.0
var fullscreen: bool = false
## Оверлей производительности (F3).
var show_perf: bool = false
## Пресет графики уже подобран автоматически при первом запуске.
var graphics_detected: bool = false

## Изменились настройки графики — окружение/солнце/модули перенастраиваются.
signal graphics_changed

## Действия → события по умолчанию. Клавиши — physical keycode.
const DEFAULT_KEYS: Dictionary = {
	&"move_forward": [KEY_W],
	&"move_back": [KEY_S],
	&"move_left": [KEY_A],
	&"move_right": [KEY_D],
	&"jump": [KEY_SPACE],
	&"sprint": [KEY_SHIFT],
	&"crouch": [KEY_CTRL],
	&"interact": [KEY_E],
	&"inventory": [KEY_I, KEY_TAB],
	&"craft": [KEY_C], # B — меню стройки (build), см. GAME/UI
	&"map": [KEY_M],
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
	AutoLOD.connect_tree(get_tree())
	load_settings()
	apply_graphics.call_deferred()
	PerfOverlay.ensure.call_deferred(get_tree().root)
	var args := OS.get_cmdline_user_args()
	if "--benchmark" in args or "--benchmark-quit" in args:
		_start_benchmark.call_deferred("--benchmark-quit" in args)

func _start_benchmark(quit: bool) -> void:
	await get_tree().process_frame
	Benchmark.start(get_tree(), quit)

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
	cfg.set_value("video", "graphics_quality", graphics_quality)
	cfg.set_value("video", "render_scale", render_scale)
	cfg.set_value("video", "dynamic_resolution", dynamic_resolution)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "fps_cap", fps_cap)
	cfg.set_value("video", "ui_scale", ui_scale)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "show_perf", show_perf)
	cfg.set_value("video", "graphics_detected", graphics_detected)
	cfg.set_value("meta", "keys_version", KEYS_VERSION)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("progress", "tutorial_done", tutorial_done)
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
	graphics_quality = cfg.get_value("video", "graphics_quality", graphics_quality)
	render_scale = float(cfg.get_value("video", "render_scale", render_scale))
	dynamic_resolution = bool(cfg.get_value("video", "dynamic_resolution", dynamic_resolution))
	vsync = bool(cfg.get_value("video", "vsync", vsync))
	fps_cap = int(cfg.get_value("video", "fps_cap", fps_cap))
	ui_scale = float(cfg.get_value("video", "ui_scale", ui_scale))
	fullscreen = bool(cfg.get_value("video", "fullscreen", fullscreen))
	show_perf = bool(cfg.get_value("video", "show_perf", show_perf))
	graphics_detected = bool(cfg.get_value("video", "graphics_detected", graphics_detected))
	var old_keys := int(cfg.get_value("meta", "keys_version", 1)) < KEYS_VERSION
	master_volume = cfg.get_value("audio", "master_volume", master_volume)
	tutorial_done = bool(cfg.get_value("progress", "tutorial_done", tutorial_done))
	for action: StringName in DEFAULT_KEYS.keys():
		if not cfg.has_section_key("keys", String(action)):
			continue
		var saved: Variant = cfg.get_value("keys", String(action))
		# v2: крафт B→C, C больше не приседание (B занят стройкой).
		if old_keys and action in [&"craft", &"crouch"]:
			continue
		if saved is Array and not (saved as Array).is_empty():
			for ev in InputMap.action_get_events(action):
				if ev is InputEventKey:
					InputMap.action_erase_event(action, ev)
			for key in saved:
				var nk := InputEventKey.new()
				nk.physical_keycode = int(key) as Key
				InputMap.action_add_event(action, nk)

const KEYS_VERSION := 2

## Применить качество графики: масштаб 3D/апскейлер/сглаживание/тени
## (GraphicsQuality), синхронизация и лимит кадров, окно, масштаб интерфейса.
## Окружение и солнце перенастраивают модули по сигналу graphics_changed.
func apply_graphics() -> void:
	var tree := get_tree()
	if tree == null:
		return
	if not graphics_detected and not _is_test_run():
		graphics_quality = GraphicsQuality.detect_default()
		graphics_detected = true
		save_settings()
	graphics_quality = clampi(graphics_quality, 0, 3)
	var vp := tree.root
	GraphicsQuality.apply_viewport(vp)
	apply_window()
	Engine.max_fps = fps_cap
	AutoLOD.rescale(tree)
	graphics_changed.emit()

## Окно: полноэкранный режим, вертикальная синхронизация, масштаб интерфейса.
## Масштаб 3D от интерфейса не зависит (canvas_items: 3D — в полном разрешении
## окна × scaling_3d_scale).
func apply_window() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var win := tree.root
	win.content_scale_factor = clampf(ui_scale, 0.75, 1.5)
	if _is_test_run() or DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	var cur := DisplayServer.window_get_mode()
	var is_full := cur == DisplayServer.WINDOW_MODE_FULLSCREEN or cur == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if fullscreen != is_full:
		DisplayServer.window_set_mode(want)

func toggle_fullscreen() -> void:
	fullscreen = not fullscreen
	apply_window()
	save_settings()

## Запущены автотесты (tests/runner.tscn): не трогаем окно и пресет.
func _is_test_run() -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--test="):
			return true
	return false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k := event as InputEventKey
		if k.physical_keycode == KEY_F11 or (k.physical_keycode == KEY_ENTER and k.alt_pressed):
			toggle_fullscreen()
			get_viewport().set_input_as_handled()
		elif k.physical_keycode == KEY_F3:
			show_perf = not show_perf
			PerfOverlay.ensure(get_tree().root)
			save_settings()
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if dynamic_resolution:
		DynamicResolution.tick(get_tree().root, delta)

## true, если работаем в упрощённом рендере (наши тесты под xvfb, слабые ПК).
func is_compatibility_renderer() -> bool:
	return RenderingServer.get_rendering_device() == null # у OpenGL (gl_compatibility) нет RenderingDevice
